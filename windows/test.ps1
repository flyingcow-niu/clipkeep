$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not $IsWindows) { throw 'DPAPI and WPF tests require Windows with PowerShell 7.' }
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
dotnet run --project ClipKeep.Core.Tests -c Release
if ($LASTEXITCODE -ne 0) { throw 'Core regression checks failed.' }
dotnet build ClipKeep.Windows/ClipKeep.Windows.csproj -c Release
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
$app = Join-Path $PSScriptRoot 'ClipKeep.Windows/bin/Release/net10.0-windows/ClipKeep.exe'
$process = Start-Process -FilePath $app -ArgumentList '--self-test' -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "DPAPI/WPF self-test failed: $($process.ExitCode)" }
Write-Host 'DPAPI encrypted round-trip, atomic save, corruption handling and WPF construction passed.'
