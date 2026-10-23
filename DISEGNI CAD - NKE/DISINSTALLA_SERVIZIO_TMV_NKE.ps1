# =================================================================================================================================
# Script di Disinstallazione Servizio Windows: TMV.NKE.Service (CAD Robot Connector & Intranet Monitor)
# Autore: SOLVERIS - Bandera Marco
# Target: Server Applicativo TMV
# =================================================================================================================================

[CmdletBinding()]
param (
    [string]$ServiceName = "TMV.NKE.Service",
    [int]$Port = 5050
)

# Verifica privilegi di amministratore
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "ERRORE: Questo script deve essere eseguito come Amministratore (Run as Administrator)."
    exit 1
}

Write-Host "=================================================================================" -ForegroundColor Yellow
Write-Host " DISINSTALLAZIONE SERVIZIO WINDOWS: $ServiceName" -ForegroundColor Yellow
Write-Host "=================================================================================" -ForegroundColor Yellow

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -eq "Running") {
        Write-Host "Arresto del servizio in corso..." -ForegroundColor Cyan
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
    }

    Write-Host "Rimozione servizio dal registro..." -ForegroundColor Cyan
    & sc.exe delete $ServiceName | Out-Null
    Write-Host "Servizio rimosso con successo." -ForegroundColor Green
} else {
    Write-Host "Il servizio $ServiceName non risulta registrato nel sistema." -ForegroundColor Yellow
}

# Rimozione eventuale regola Firewall
$ruleName = "TMV NKE Web Monitor (Port $Port)"
$rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($rule) {
    Write-Host "Rimozione regola firewall $ruleName..." -ForegroundColor Cyan
    Remove-NetFirewallRule -DisplayName $ruleName
}

Write-Host "Disinstallazione completata." -ForegroundColor Green

