param(
    [ValidateSet('demo', 'dev', 'android-setup', 'android-build', 'android-start', 'android-test', 'openxr', 'stop')]
    [string]$Task = 'demo',
    [switch]$AcceptAndroidSdk
)

$ErrorActionPreference = 'Stop'
function Invoke-Docker {
    & docker @args
    if ($LASTEXITCODE -ne 0) { throw "Docker termino con codigo $LASTEXITCODE" }
}

Push-Location (Join-Path $PSScriptRoot '..')
try {
    $os = & docker info --format '{{.OSType}}'
    if ($LASTEXITCODE -ne 0 -or $os -ne 'linux') {
        throw 'Inicia Docker Desktop con contenedores Linux en WSL2.'
    }
    switch ($Task) {
        demo { Invoke-Docker compose up --build --detach --wait demo }
        dev { Invoke-Docker compose up --build --detach --wait dev }
        'android-setup' {
            if (!$AcceptAndroidSdk) {
                throw 'Lee https://developer.android.com/studio/terms y usa -AcceptAndroidSdk si aceptas la licencia.'
            }
            Invoke-Docker compose exec dev android/setup.sh --accept
        }
        'android-build' { Invoke-Docker compose exec dev android/build-apk.sh }
        'android-start' { Invoke-Docker compose exec dev android/start.sh }
        'android-test' { Invoke-Docker compose exec dev android/smoke.sh }
        openxr { Invoke-Docker compose -f openxr/compose.yaml up --build --detach --wait }
        stop { Invoke-Docker compose --profile '*' down }
    }
} finally {
    Pop-Location
}
