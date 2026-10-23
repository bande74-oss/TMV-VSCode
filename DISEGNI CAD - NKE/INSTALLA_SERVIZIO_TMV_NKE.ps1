# =================================================================================================================================
# Script di Installazione Servizio Windows: TMV.NKE.Service (CAD Robot Connector & Intranet Monitor)
# Autore: SOLVERIS - Bandera Marco
# Target: Server Applicativo TMV
# =================================================================================================================================

[CmdletBinding()]
param (
    [string]$ServiceName = "TMV.NKE.Service",
    [string]$DisplayName = "TMV - Connettore Robot CAD NKE & Monitor Intranet",
    [string]$Description = "Servizio applicativo per la gestione asincrona delle code disegni CAD NKE e dashboard web intranet.",
    [string]$BinaryPath = "$PSScriptRoot\..\src\Tmv.Nke.Connector\publish\Tmv.Nke.Connector.exe",
    [int]$Port = 5050
)

# Verifica privilegi di amministratore
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "ERRORE: Questo script deve essere eseguito come Amministratore (Run as Administrator)."
    exit 1
}

Write-Host "=================================================================================" -ForegroundColor Cyan
Write-Host " INSTALLAZIONE SERVIZIO WINDOWS: $ServiceName" -ForegroundColor Cyan
Write-Host "=================================================================================" -ForegroundColor Cyan

$resolvedBinPath = [System.IO.Path]::GetFullPath($BinaryPath)
if (-not (Test-Path $resolvedBinPath)) {
    Write-Error "ERRORE: File eseguibile non trovato al percorso: $resolvedBinPath"
    exit 1
}

Write-Host "Eseguibile individuato: $resolvedBinPath" -ForegroundColor Green

# Se il servizio esiste già, lo arrestiamo e rimuoviamo
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Il servizio $ServiceName esiste già. Arresto in corso..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "Rimozione servizio preesistente..." -ForegroundColor Yellow
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
}

# Creazione del nuovo servizio Windows con avvio automatico
Write-Host "Creazione del servizio Windows in sc.exe..." -ForegroundColor Cyan
$scArgs = @(
    "create", $ServiceName,
    "binPath=", "`"$resolvedBinPath`"",
    "start=", "auto",
    "DisplayName=", "`"$DisplayName`""
)
& sc.exe $scArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Errore durante la creazione del servizio con sc.exe (ExitCode: $LASTEXITCODE)"
    exit $LASTEXITCODE
}

# Imposta descrizione e riavvio automatico in caso di errore
& sc.exe description $ServiceName "$Description"
& sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000

# Apertura porta nel Windows Firewall locale
$ruleName = "TMV NKE Web Monitor (Port $Port)"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if (-not $existingRule) {
    Write-Host "Apertura porta $Port nel Windows Firewall..." -ForegroundColor Cyan
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow | Out-Null
    Write-Host "Regola firewall creata con successo." -ForegroundColor Green
}

# Avvio del servizio
Write-Host "Avvio del servizio $ServiceName..." -ForegroundColor Cyan
Start-Service -Name $ServiceName

Start-Sleep -Seconds 3
$status = Get-Service -Name $ServiceName
if ($status.Status -eq "Running") {
    Write-Host "=================================================================================" -ForegroundColor Green
    Write-Host " SERVIZIO INSTALLATO E AVVIATO CON SUCCESSO!" -ForegroundColor Green
    Write-Host " Stato attuale: $($status.Status)" -ForegroundColor Green
    Write-Host " Dashboard Intranet raggiungibile su: http://localhost:$Port" -ForegroundColor Green
    Write-Host "=================================================================================" -ForegroundColor Green
} else {
    Write-Warning "Il servizio è nello stato: $($status.Status). Verificare il file di log o il Visualizzatore Eventi di Windows."
}

