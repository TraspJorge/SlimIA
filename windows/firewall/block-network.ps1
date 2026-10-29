# Blocks Coucou's network from the system's side, whatever the code does.
# Run in an elevated PowerShell (Run as administrator):
#
#   .\block-network.ps1                       # add the rules
#   .\block-network.ps1 -Remove                # take them off again
#   .\block-network.ps1 -Program "D:\Coucou\coucou.exe"
#
# Windows Firewall does not filter the loopback interface, so Coucou can still
# reach a model server on this PC (Ollama, LM Studio on 127.0.0.1).

param(
    [string[]]$Program = @("$env:LOCALAPPDATA\Coucou\coucou.exe", "$env:LOCALAPPDATA\Coucou\coucou-hook.exe"),
    [switch]$Remove
)

$ErrorActionPreference = "Stop"
$prefix = "Coucou: no network"

if ($Remove) {
    Get-NetFirewallRule -DisplayName "$prefix*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host "Rules removed."
    return
}

foreach ($exe in $Program) {
    foreach ($direction in "Outbound", "Inbound") {
        New-NetFirewallRule `
            -DisplayName "$prefix ($direction, $(Split-Path $exe -Leaf))" `
            -Direction $direction `
            -Program $exe `
            -Action Block `
            -Profile Any | Out-Null
    }
    Write-Host "Blocked: $exe"
}
Write-Host "Done. Check with: Get-NetFirewallRule -DisplayName '$prefix*'"
