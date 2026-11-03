param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64'
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not $IsWindows) { throw 'Build and publish the Windows app on Windows with PowerShell 7.' }
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
dotnet run --project ClipKeep.Core.Tests -c Release
if ($LASTEXITCODE -ne 0) { throw 'Core regression checks failed.' }
dotnet publish ClipKeep.Windows/ClipKeep.Windows.csproj -c Release -r $Runtime --self-contained true -o "dist/$Runtime"
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
Write-Host "Built $PSScriptRoot/dist/$Runtime/ClipKeep.exe"
Write-Host 'Copy the entire output directory. This is an unsigned portable build, not an installer.'
