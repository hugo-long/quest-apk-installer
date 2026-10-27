param([string]$Version = '0.1.0')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$') { throw 'Invalid version.' }
if ($PSVersionTable.PSEdition -eq 'Core') { throw 'Run this build with Windows PowerShell 5.1 (powershell.exe).' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (!(Test-Path -LiteralPath $compiler)) { throw '.NET Framework C# compiler was not found.' }
$automation = [PSObject].Assembly.Location
$dist = Join-Path $PSScriptRoot 'dist'
$package = Join-Path $dist "QuestApkInstaller-v$Version-Windows"
New-Item -ItemType Directory -Force -Path $package | Out-Null
$exe = Join-Path $package 'QuestApkInstaller.exe'
& $compiler /nologo /target:winexe "/out:$exe" /reference:System.Windows.Forms.dll "/reference:$automation" (Join-Path $PSScriptRoot 'Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
foreach ($name in @('QuestApkInstaller.ps1','Start.cmd','README.md','LICENSE','使用说明.md')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $package -Force
}
$zip = "$package.zip"
Compress-Archive -LiteralPath $package -DestinationPath $zip -Force
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($zip))" | Set-Content -LiteralPath (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII
Write-Output "Built: $zip"
