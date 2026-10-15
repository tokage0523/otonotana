param([string]$TestRoot, [string]$M4AFixture)
$ErrorActionPreference = 'Stop'
if (-not $TestRoot) { $TestRoot = Join-Path $PSScriptRoot ('TestRun-' + [guid]::NewGuid().ToString('N')) }
$TestRoot = [System.IO.Path]::GetFullPath($TestRoot)
if (Test-Path -LiteralPath $TestRoot) { throw 'Use a new, empty test directory to avoid changing existing drafts.' }
New-Item -ItemType Directory -Path $TestRoot | Out-Null
if ($M4AFixture) { Copy-Item -LiteralPath $M4AFixture -Destination (Join-Path $TestRoot 'sample.m4a') }
foreach ($phase in 1..2) {
    $process = Start-Process -FilePath (Join-Path $PSScriptRoot 'publish/OtonotanaEditor.exe') -ArgumentList @('--self-test', ('"' + $TestRoot + '"')) -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(45000)) { Stop-Process -Id $process.Id; throw 'Windows editor self-test timed out.' }
    if ($process.ExitCode -ne 0) { throw (Get-Content -LiteralPath (Join-Path $TestRoot 'test-error.txt') -Raw) }
    $result = Join-Path $TestRoot "phase$phase.ok"
    if (-not (Test-Path -LiteralPath $result)) { throw "Missing phase $phase result." }
    Get-Content -LiteralPath $result
}
Write-Output "Verified Windows editor. Preview: $TestRoot/desktop-preview.png"

