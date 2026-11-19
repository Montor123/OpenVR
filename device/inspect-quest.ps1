[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.:\[\]%-]+$')]
    [string] $Serial,

    [ValidateNotNullOrEmpty()]
    [string] $Adb = 'adb',

    [ValidateNotNullOrEmpty()]
    [string] $OutputPath = 'results/quest2-inventory.json',

    [switch] $Display
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$adbCommand = Get-Command -Name $Adb -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $adbCommand) {
    throw 'No se ha encontrado adb. Indica la ruta de Android Platform Tools con -Adb.'
}

function Invoke-AdbRead {
    param([string[]] $Arguments)

    # ADB can put the transport serial in errors. Keep the raw stream out of reports.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $lines = & $adbCommand.Source @Arguments 2>$null
    $succeeded = $LASTEXITCODE -eq 0
    [pscustomobject] @{
        Succeeded = $succeeded
        Text = ($lines -join "`n").Trim()
    }
}

$result = Invoke-AdbRead -Arguments @('devices')
if (-not $result.Succeeded) {
    throw 'ADB no pudo enumerar dispositivos. Comprueba Android Platform Tools y el servicio ADB local.'
}

$devices = @(
    foreach ($line in $result.Text -split '\r?\n') {
        if ($line -cmatch '^(?<Transport>[A-Za-z0-9_.:\[\]%-]+)[\t ]+(?<State>device|offline|unauthorized|no permissions|recovery|sideload|bootloader|authorizing|connecting)(?:[\t ]|$)') {
            [pscustomobject] @{ Transport = $Matches.Transport; State = $Matches.State }
        }
    }
)
if ($PSBoundParameters.ContainsKey('Serial')) {
    $matchesBySerial = @($devices | Where-Object { $_.Transport -ceq $Serial })
    if ($matchesBySerial.Count -ne 1) {
        throw 'ADB no muestra el transporte seleccionado. Consulta adb devices y comprueba -Serial.'
    }
    $selectedDevice = $matchesBySerial[0]
} else {
    if ($devices.Count -ne 1) {
        throw 'Conecta un único dispositivo o indica -Serial según la salida de adb devices.'
    }
    $selectedDevice = $devices[0]
}
if ($selectedDevice.State -cne 'device') {
    throw 'El transporte seleccionado no está listo. Autoriza la depuración en el visor y comprueba adb devices.'
}

$transport = $selectedDevice.Transport
$readErrors = [System.Collections.Generic.List[string]]::new()

function Read-InventoryValue {
    param([string] $Name, [string[]] $Arguments)

    $response = Invoke-AdbRead -Arguments (@('-s', $transport, 'shell') + $Arguments)
    if (-not $response.Succeeded) {
        $readErrors.Add($Name)
        return $null
    }
    if ($response.Text -ceq $transport -or $response.Text -cnotmatch '^[A-Za-z0-9 _.,:/+@()=\-]{1,512}$') {
        return $null
    }
    return $response.Text
}

function Read-DeviceTreeModel {
    foreach ($path in @('/sys/firmware/devicetree/base/model', '/proc/device-tree/model')) {
        $response = Invoke-AdbRead -Arguments @('-s', $transport, 'shell', 'cat', $path)
        $value = $response.Text.TrimEnd([char] 0).Trim()
        if ($response.Succeeded -and $value -cne $transport -and $value -cmatch '^[A-Za-z0-9 _.,:/+@()=\-]{1,512}$') {
            return $value
        }
    }
    $readErrors.Add('board.model')
    return $null
}

function Read-PartitionNames {
    param([string] $Name, [string[]] $Paths)

    foreach ($path in $Paths) {
        $response = Invoke-AdbRead -Arguments @('-s', $transport, 'shell', 'ls', '-1', $path)
        if ($response.Succeeded) {
            $names = @(
                $response.Text -split '\r?\n' | Where-Object {
                    $_ -ine $transport -and $_ -cmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$'
                } | Sort-Object -CaseSensitive -Unique
            )
            return [ordered] @{ source = $path; names = $names }
        }
    }
    $readErrors.Add($Name)
    return [ordered] @{ source = $null; names = $null }
}

$model = Read-InventoryValue -Name 'ro.product.model' -Arguments @('getprop', 'ro.product.model')
$productDevice = Read-InventoryValue -Name 'ro.product.device' -Arguments @('getprop', 'ro.product.device')
if ($productDevice -ine 'hollywood' -and $model -inotmatch '^(?:(?:Oculus|Meta) )?Quest 2$') {
    throw 'La identidad que declara Android no coincide con Quest 2. Comprueba que seleccionaste el visor correcto.'
}

$properties = [ordered] @{
    'ro.product.model' = $model
    'ro.product.device' = $productDevice
}
$propertyNames = @(
    'ro.product.board'
    'ro.hardware'
    'ro.board.platform'
    'ro.revision'
    'ro.boot.hwrev'
    'ro.boot.hardware.sku'
    'ro.soc.manufacturer'
    'ro.soc.model'
    'ro.product.cpu.abilist'
    'ro.product.first_api_level'
    'ro.build.fingerprint'
    'ro.build.id'
    'ro.build.version.incremental'
    'ro.build.version.release'
    'ro.build.version.sdk'
    'ro.build.version.security_patch'
    'ro.vendor.build.fingerprint'
    'ro.vendor.build.security_patch'
    'ro.bootimage.build.fingerprint'
    'ro.bootloader'
    'ro.boot.slot'
    'ro.boot.slot_suffix'
    'ro.boot.verifiedbootstate'
    'ro.boot.vbmeta.device_state'
    'ro.boot.flash.locked'
    'ro.boot.dynamic_partitions'
    'ro.build.ab_update'
    'ro.virtual_ab.enabled'
)
foreach ($property in $propertyNames) {
    $properties[$property] = Read-InventoryValue -Name $property -Arguments @('getprop', $property)
}

$slots = @(
    foreach ($property in @('ro.boot.slot_suffix', 'ro.boot.slot')) {
        if ($properties[$property] -cmatch '^_?([ab])$') {
            $Matches[1]
        }
    }
)
$slotConflict = $slots.Count -eq 2 -and $slots[0] -cne $slots[1]
$activeSlot = $null
if ($slots.Count -gt 0 -and -not $slotConflict) {
    $activeSlot = $slots[0]
}
$flashLocked = switch ($properties['ro.boot.flash.locked']) {
    '0' { $false }
    '1' { $true }
    default { $null }
}

$report = [ordered] @{
    schema_version = 1
    collected_utc_date = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
    properties = $properties
    kernel = [ordered] @{
        release = Read-InventoryValue -Name 'kernel.release' -Arguments @('uname', '-r')
        machine = Read-InventoryValue -Name 'kernel.machine' -Arguments @('uname', '-m')
    }
    boot = [ordered] @{
        active_slot = $activeSlot
        slot_conflict = $slotConflict
        verified_boot_state = $properties['ro.boot.verifiedbootstate']
        flash_locked = $flashLocked
        vbmeta_device_state = $properties['ro.boot.vbmeta.device_state']
    }
    board = [ordered] @{
        model = Read-DeviceTreeModel
        boot_hardware_revision = $properties['ro.boot.hwrev']
        hardware_revision = $properties['ro.revision']
        boot_hardware_sku = $properties['ro.boot.hardware.sku']
    }
    partitions = [ordered] @{
        by_name = Read-PartitionNames -Name 'partitions.by_name' -Paths @('/dev/block/by-name', '/dev/block/bootdevice/by-name')
        mapper = Read-PartitionNames -Name 'partitions.mapper' -Paths @('/dev/block/mapper')
    }
}

if ($Display) {
    $report['display_android_wm'] = [ordered] @{}
    $size = Invoke-AdbRead -Arguments @('-s', $transport, 'shell', 'wm', 'size')
    $density = Invoke-AdbRead -Arguments @('-s', $transport, 'shell', 'wm', 'density')
    foreach ($kind in @('Physical', 'Override')) {
        $sizeKey = $kind.ToLowerInvariant()
        $value = $null
        if ($size.Succeeded -and $size.Text -cmatch "(?m)^${kind} size: ([0-9]{1,5})x([0-9]{1,5})\r?$") {
            $value = [ordered] @{ width = [int] $Matches[1]; height = [int] $Matches[2] }
        }
        $report['display_android_wm']["${sizeKey}_size"] = $value

        $value = $null
        if ($density.Succeeded -and $density.Text -cmatch "(?m)^${kind} density: ([0-9]{1,5})\r?$") {
            $value = [int] $Matches[1]
        }
        $report['display_android_wm']["${sizeKey}_density_dpi"] = $value
    }
    if (-not $size.Succeeded) { $readErrors.Add('wm size') }
    if (-not $density.Succeeded) { $readErrors.Add('wm density') }
}
$report['read_errors'] = $readErrors.ToArray()

$destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ([System.IO.File]::Exists($destination) -or [System.IO.Directory]::Exists($destination)) {
    throw 'La ruta indicada ya existe. Elige otro -OutputPath para conservar el informe anterior.'
}
$directory = [System.IO.Path]::GetDirectoryName($destination)
[void] [System.IO.Directory]::CreateDirectory($directory)
$temporary = [System.IO.Path]::Combine($directory, ('quest2-' + [Guid]::NewGuid().ToString('N') + '.tmp'))
try {
    $json = $report | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temporary, $destination)
} finally {
    if ([System.IO.File]::Exists($temporary)) {
        [System.IO.File]::Delete($temporary)
    }
}

Write-Output "Inventario guardado en $destination"
