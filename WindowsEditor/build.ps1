$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$env:DOTNET_CLI_HOME = Join-Path $projectRoot '.dotnet'
$env:NUGET_PACKAGES = Join-Path $projectRoot '.packages'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'

# Draw the application's small vector icon without external image dependencies.
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap 256, 256
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::FromArgb(88, 82, 190))
$white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 13
$pen.StartCap = 'Round'; $pen.EndCap = 'Round'
$graphics.DrawLine($pen, 108, 163, 108, 70)
$graphics.DrawLine($pen, 108, 70, 180, 54)
$graphics.DrawLine($pen, 180, 54, 180, 147)
$graphics.FillEllipse($white, 69, 146, 45, 33)
$graphics.FillEllipse($white, 141, 130, 45, 33)
$graphics.DrawLine($pen, 66, 211, 190, 211)
$memory = New-Object System.IO.MemoryStream
$bitmap.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
$png = $memory.ToArray()
$iconStream = [System.IO.File]::Create((Join-Path $projectRoot 'app.ico'))
$writer = New-Object System.IO.BinaryWriter $iconStream
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
$writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0)
$writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$png.Length); $writer.Write([uint32]22); $writer.Write($png)
$writer.Dispose(); $memory.Dispose(); $graphics.Dispose(); $bitmap.Dispose(); $white.Dispose(); $pen.Dispose()

dotnet publish (Join-Path $projectRoot 'Otonotana.Editor.csproj') -c Release -o (Join-Path $projectRoot 'publish') --nologo
if ($LASTEXITCODE -ne 0) { throw 'Windows application build failed.' }

$licenses = Join-Path $projectRoot 'publish/Licenses'
New-Item -ItemType Directory -Path $licenses -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot '使い方.txt') -Destination (Join-Path $projectRoot 'publish/使い方.txt') -Force
Copy-Item -LiteralPath (Join-Path $env:NUGET_PACKAGES 'microsoft.web.webview2/1.0.4258.31/LICENSE.txt') -Destination (Join-Path $licenses 'WebView2-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $env:NUGET_PACKAGES 'microsoft.web.webview2/1.0.4258.31/NOTICE.txt') -Destination (Join-Path $licenses 'WebView2-NOTICE.txt') -Force
Copy-Item -LiteralPath (Join-Path $env:NUGET_PACKAGES 'microsoft.netcore.app.runtime.win-x64/8.0.32/LICENSE.TXT') -Destination (Join-Path $licenses 'DotNet-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $env:NUGET_PACKAGES 'microsoft.netcore.app.runtime.win-x64/8.0.32/THIRD-PARTY-NOTICES.TXT') -Destination (Join-Path $licenses 'DotNet-THIRD-PARTY-NOTICES.txt') -Force
Copy-Item -LiteralPath (Join-Path $env:NUGET_PACKAGES 'microsoft.windowsdesktop.app.runtime.win-x64/8.0.32/LICENSE') -Destination (Join-Path $licenses 'WindowsDesktop-LICENSE.txt') -Force

