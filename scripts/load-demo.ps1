param(
    [Parameter(Mandatory=$true)]
    [string]$Archive,
    [Parameter(Mandatory=$true)]
    [string]$Checksum
)

$ErrorActionPreference = 'Stop'
$expected = ((Get-Content -LiteralPath $Checksum -TotalCount 1) -split '\s+')[0]
if ($expected -notmatch '^[a-fA-F0-9]{64}$') { throw 'El fichero SHA-256 no es valido.' }
$actual = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
if ($actual -ne $expected) { throw 'El SHA-256 no coincide.' }

docker load --input $Archive
if ($LASTEXITCODE -ne 0) { throw 'Docker no pudo cargar la imagen.' }

docker run -d --name openvr-demo -p 127.0.0.1:8080:8080 --read-only --mount type=volume,source=openvr-demo-results,target=/data/results openvr-demo:0.1.0
if ($LASTEXITCODE -ne 0) { throw 'Docker no pudo iniciar el contenedor.' }

Write-Host 'Abre http://localhost:8080/'
