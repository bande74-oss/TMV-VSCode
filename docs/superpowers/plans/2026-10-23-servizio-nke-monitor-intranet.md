# Servizio APP Server & Monitor Intranet TMV_NKE - Piano di Implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Realizzare un servizio Windows .NET 8 con Web App Intranet Kestrel integrata per la gestione asincrona, monitoraggio operativo e forzatura manuale delle chiamate al generatore CAD NKE, disaccoppiando l'ERP Gamma da chiamate HTTP dirette.

**Architecture:** Servizio Windows C# (.NET 8) ospitato sul Server Applicativo TMV che integra due Background Worker (uno per l'alimentazione massiva periodica e uno per l'invio serializzato della coda a NKE con cooldown di 30 secondi), esponendo un Web Server Kestrel locale sulla porta 5050 con API REST e Dashboard HTML/JS "Swiss Office Minimal" per gli operatori dell'Ufficio Tecnico.

**Tech Stack:** .NET 8 (C#), ASP.NET Core Kestrel, Microsoft.Data.SqlClient, Dapper, HTML5/Tailwind/CSS Vanilla, Microsoft SQL Server 2017 (`DBTMV`).

**Spec:** `DISEGNI CAD - NKE/2026-10-23-servizio-nke-monitor-intranet-design.md`

## Global Constraints

- Piattaforma DB: Microsoft SQL Server 2017 (MSSQL 14.0.2120.1) su database `DBTMV`.
- Standard SQL SOLVERIS: Prefisso stored procedure `SPSO_..._GEMINI`, tabelle personalizzate con suffisso `_GEMINI`, cartiglio narrativo obbligatorio.
- Framework applicativo: .NET 8.0 Worker Service con Kestrel Web Host integrato.
- Nessuna dipendenza cloud esterna: operatività 100% su rete locale LAN aziendale.
- Nessun blocco su SQL Server: niente `sp_OAMethod` o chiamate HTTP sincrone da T-SQL; tutte le query di lettura eseguite con `WITH (NOLOCK)`.
- UI Design: Stile "Swiss Office Minimal" (Enterprise Blue `#2563EB`, Slate `#1E293B`, sfondi `#F8FAFC`, SVG inline).

## Review Focus

1. Gestione timeout e mancata risposta della WebAPI NKE: il servizio deve registrare l'errore senza bloccare il ciclo della coda e senza fermare il Web Server.
2. Risposta HTTP 200 con errore applicativo nel body JSON: il client HTTP deve verificare sia il codice di stato che i campi interni del messaggio prima di considerare generato il file.
3. Riconoscimento ordini nel monitor con deduplicazione attiva: la tabella ponte deve associare ogni richiesta a tutte le righe d'ordine corrispondenti.
4. Concorrenza tra scansione periodica e richiesta manuale dell'operatore: un semaforo interno deve garantire che non vi siano esecuzioni sovrapposte della procedura di alimentazione coda.
5. Esclusione elementi falliti dal Delta Engine: verificare che solo i record con generazione confermata siano considerati già trattati.

---

### Task 1: Creazione Tabelle di Tracciabilità e Dettaglio Chiamate in DBTMV

**Files:**
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/DISEGNI CAD - NKE/01_CREATE_TABLES_TRACCIABILITA_GEMINI.sql`
- Test: Esecuzione script e verifica esistenza strutture su `DBTMV` tramite query di sistema

**Interfaces:**
- Produces: `[dbo].[RT13_NKE_DOCS_GEMINI]` e `[dbo].[RT13_NKE_LOG_DETAIL_GEMINI]`

- [ ] **Step 1: Scrittura dello script DDL con cartiglio SOLVERIS per la creazione delle tabelle**

Creare `DISEGNI CAD - NKE/01_CREATE_TABLES_TRACCIABILITA_GEMINI.sql` contenente:
- `RT13_NKE_DOCS_GEMINI`: colonne `ID_DOC_NKE` (bigint PK), `MG87_GUID` (uniqueidentifier), `DO11_DITTA_CG18`, `DO11_DOCUM_MG36`, `DO11_NUMDOC` (int), `DO11_SEZDOC` (varchar 3), `DO11_ANNODOC` (smallint), `DO11_DATADOC` (datetime), `DO30_PROGRIGA` (int), `DO30_CODART_MG66`, `DO30_OPZIONE_MG5E`, `RAGIONE_SOCIALE`, `DATA_INSERIMENTO`.
- `RT13_NKE_LOG_DETAIL_GEMINI`: colonne `ID_LOG` (bigint PK), `MG87_GUID` (uniqueidentifier), `MOMENTO_CHIAMATA` (datetime), `LATENCY_MS` (int), `HTTP_STATUS` (int), `RICHIESTA_JSON` (nvarchar max), `RISPOSTA_JSON` (nvarchar max), `ESITO_GENERATO` (bit), `MESSAGGIO_ERRORE` (nvarchar max), `OPERATORE` (varchar 50), `IP_CLIENT` (varchar 45).
- Indici su `MG87_GUID` e `DO11_NUMDOC`.

- [ ] **Step 2: Esecuzione DDL su DBTMV**

Eseguire lo script su `DBTMV` verificando la corretta creazione degli oggetti.

- [ ] **Step 3: Test di verifica presenza colonne e indici**

Eseguire query su `sys.tables` e `sys.columns` per convalidare la conformità dello schema.

---

### Task 2: Aggiornamento Stored Procedure SPSO_NKE_ALIMENTA_CODA_GEMINI

**Files:**
- Modify: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/DISEGNI CAD - NKE/SPSO_NKE_ALIMENTA_CODA_GEMINI.sql`
- Test: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/DISEGNI CAD - NKE/TEST_COLLAUDO_CO5519_GEMINI.sql`

**Interfaces:**
- Consumes: `[dbo].[RT13_NKE_DOCS_GEMINI]`
- Produces: Popolamento coda `RT13_NKE` e tracciamento righe in `RT13_NKE_DOCS_GEMINI`

- [ ] **Step 1: Aggiornamento cartiglio narrativo e revisione del Delta Check**

Modificare la condizione di verifica pregressa nel Delta Engine in:
```sql
WHERE l.MG87_GUID = c.MG87_GUID AND l.RT13_FILE_GENERATO = 1
```

- [ ] **Step 2: Aggiunta inserimento nella tabella ponte RT13_NKE_DOCS_GEMINI**

Nella Sezione 4 (modalità reale `@ModalitaDryRun = 0`), contestualmente all'inserimento deduplicato in `RT13_NKE`, inserire tutte le righe d'ordine analizzate in `RT13_NKE_DOCS_GEMINI` per conservare il legame con Numero Ordine, Riga e Ragione Sociale cliente.

- [ ] **Step 3: Compilazione della Stored Procedure su DBTMV**

Applicare l'aggiornamento su `DBTMV`.

- [ ] **Step 4: Verifica con test di collaudo su CO 5519**

Eseguire la simulazione Dry-Run su `CO 5519` verificando che le 68 righe mantengano l'esito `DA_INSERIRE_NUOVO` e che la struttura dati sia coerente.

---

### Task 3: Scaffolding Soluzione .NET 8 Worker Service & Kestrel Host

**Files:**
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Tmv.Nke.Connector.csproj`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Program.cs`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/appsettings.json`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Configuration/NkeSettings.cs`

**Interfaces:**
- Produces: Entrypoint del servizio Windows con configurazione Kestrel sulla porta 5050 e dependency injection registrata.

- [ ] **Step 1: Creazione cartella progetto e file di progetto .csproj**

Creare `src/Tmv.Nke.Connector/Tmv.Nke.Connector.csproj` con:
- TargetFramework `net8.0`
- Pacchetti NuGet: `Microsoft.Extensions.Hosting.WindowsServices`, `Microsoft.Data.SqlClient`, `Dapper`.

- [ ] **Step 2: Creazione classi di configurazione e file appsettings.json**

Definire le impostazioni in `appsettings.json`:
- ConnectionString `DBTMV`
- Indirizzo endpoint NKE (`http://192.168.1.138:7171/configure`)
- Secondi cooldown (30)
- Timeout chiamata (10s)
- Intervallo scansione massiva (600s / 10 min)
- Porta server web (5050)

- [ ] **Step 3: Configurazione Program.cs con Kestrel e supporto Windows Service**

Configurare l'host con `UseWindowsService()`, `ConfigureWebHostDefaults` per servire file statici e controller API.

- [ ] **Step 4: Verifica build del progetto**

Eseguire `dotnet build` verificando l'assenza di errori di compilazione.

---

### Task 4: Client HTTP Resiliente e Validatore Risposte NKE

**Files:**
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Services/INkeApiClient.cs`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Services/NkeApiClient.cs`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Models/NkeApiModels.cs`

**Interfaces:**
- Produces: Metodo `SendConfigurationAsync(NkeRequestPayload payload, CancellationToken ct)` che restituisce `NkeCallResult` con metriche di latenza, stato ed esito logico.

- [ ] **Step 1: Definizione modelli richiesta e risultato**

Creare i modelli per la serializzazione JSON (`Id`, `MasterDataArray`, `ParametersArray`) e il risultato della chiamata con tempo di risposta in ms.

- [ ] **Step 2: Implementazione NkeApiClient**

Implementare la chiamata asincrona con `HttpClient`, misurazione del tempo tramite `Stopwatch`, e analisi del contenuto per verificare l'assenza di stringhe di errore nel body anche se HTTP 200.

- [ ] **Step 3: Compilazione e verifica client**

Verificare che il modulo compili correttamente.

---

### Task 5: Background Dispatcher Worker della Coda RT13_NKE

**Files:**
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Workers/DispatcherWorker.cs`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Services/IQueueRepository.cs`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Services/QueueRepository.cs`

**Interfaces:**
- Consumes: `IQueueRepository`, `INkeApiClient`
- Produces: Ciclo continuo di prelievo coda, rispetto del cooldown di 30s, gestione dei 3 tentativi e archiviazione nel log dettagliato.

- [ ] **Step 1: Implementazione Repository per accesso a RT13_NKE e RT13_NKE_LOG_DETAIL_GEMINI**

Metodi Dapper per:
- Lettura elementi pendenti con lock transazionale leggero
- Aggiornamento stato tentativo e timestamp
- Cancellazione da coda e inserimento nel log di dettaglio

- [ ] **Step 2: Implementazione logica del DispatcherWorker**

Ciclo di esecuzione ogni 10 secondi:
- Controllo del tempo trascorso dall'ultima chiamata inviata
- Invio del singolo elemento a NKE
- In caso di successo: rimozione dalla coda e registrazione log positivo
- In caso di errore: incremento tentativi. Se tentativi >= 3, archiviazione come errore definitivo per non bloccare la coda

- [ ] **Step 3: Verifica compilazione del worker**

Eseguire `dotnet build` verificando la correttezza del worker.

---

### Task 6: Massive Ingestion Worker e Controllo Concorrenza

**Files:**
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Workers/MassiveIngestionWorker.cs`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Services/IExecutionCoordinator.cs`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Services/ExecutionCoordinator.cs`

**Interfaces:**
- Produces: Coordinamento tra scansione periodica ogni 10 minuti e forzature manuali avviate da interfaccia web tramite `SemaphoreSlim`.

- [ ] **Step 1: Implementazione coordinatore di esecuzione**

Creare il singleton `ExecutionCoordinator` con semaforo per garantire mutua esclusione tra scansione massiva e forzatura manuale.

- [ ] **Step 2: Implementazione MassiveIngestionWorker**

Worker periodico che, all'intervallo configurato (10 minuti), acquisisce il semaforo ed esegue `SPSO_NKE_ALIMENTA_CODA_GEMINI @ModalitaDryRun = 0, @GiorniIndietro = 15`.

- [ ] **Step 3: Verifica compilazione**

Eseguire `dotnet build`.

---

### Task 7: Controller API REST per Monitoraggio e Azioni Operative

**Files:**
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Controllers/MonitorApiController.cs`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/Models/ApiContracts.cs`

**Interfaces:**
- Produces: Endpoint `/api/status`, `/api/kpis`, `/api/queue`, `/api/logs`, `/api/orders/simulate`, `/api/orders/force`.

- [ ] **Step 1: Creazione endpoint di lettura stato e metriche**

Implementare `/api/status` e `/api/kpis` con conteggio elementi in coda, chiamate eseguite nelle 24h, errori e tempo medio di risposta.

- [ ] **Step 2: Creazione endpoint log e dettaglio ordini**

Implementare `/api/logs` con paginazione e ricerca, effettuando la join tra `RT13_NKE_LOG_DETAIL_GEMINI` e `RT13_NKE_DOCS_GEMINI` per restituire numero ordine e cliente.

- [ ] **Step 3: Creazione endpoint di simulazione e forzatura ordine**

Implementare `/api/orders/simulate` (Dry-Run) e `/api/orders/force` (con acquisizione operatore e IP client richiedente).

- [ ] **Step 4: Verifica compilazione controller**

Eseguire `dotnet build`.

---

### Task 8: Dashboard Web Intranet (Swiss Office Minimal)

**Files:**
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/wwwroot/index.html`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/wwwroot/css/dashboard.css`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/src/Tmv.Nke.Connector/wwwroot/js/dashboard.js`

**Interfaces:**
- Consumes: Endpoint REST di Task 7
- Produces: Interfaccia utente web accessibile via browser LAN (`http://localhost:5050`) conforme al mockup validato.

- [ ] **Step 1: Creazione struttura HTML e stili CSS**

Realizzare il layout conforme a `/ui-ux-pro-max` (banner con stato servizio NKE, card KPI, barra di forzatura con input ordine e sigla operatore, griglia log con badge di stato e cassetto per ispezione dati JSON).

- [ ] **Step 2: Logica JavaScript per aggiornamento live e interazioni**

Implementare:
- Polling automatico ogni 10 secondi per aggiornare KPI e griglia log
- Gestione click "Simula (Dry-Run)" con visualizzazione del prospetto righe in modale/pannello
- Gestione click "Invia Subito a NKE" con conferma e avviso visivo
- Apertura del cassetto laterale per visualizzare la richiesta JSON inviata e la risposta ricevuta

- [ ] **Step 3: Test visivo e funzionale della dashboard su browser**

Avviare temporaneamente il servizio ed effettuare una verifica di rendering e chiamata API.

---

### Task 9: Collaudo Generale e Preparazione Script di Installazione Servizio

**Files:**
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/DISEGNI CAD - NKE/INSTALLA_SERVIZIO_TMV_NKE.ps1`
- Create: `c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE - TMV/DISEGNI CAD - NKE/DISINSTALLA_SERVIZIO_TMV_NKE.ps1`
- Test: Test end-to-end con simulazione su `CO 5519`

**Interfaces:**
- Produces: Pacchetto pubblicato autonomo (.NET self-contained o framework-dependent) e script PowerShell per registrazione come Servizio Windows.

- [ ] **Step 1: Pubblicazione dell'applicazione .NET 8 per ambiente Windows**

Eseguire `dotnet publish -c Release -r win-x64 --self-contained false -o ./publish`.

- [ ] **Step 2: Scrittura script PowerShell per installazione Windows Service**

Creare lo script di installazione tramite comando `New-Service` o `sc.exe create TMV.NKE.Service binPath= ... start= auto`.

- [ ] **Step 3: Collaudo finale del flusso end-to-end**

Verificare il funzionamento coordinato tra DB SQL Server, servizio di background e interfaccia web intranet.
