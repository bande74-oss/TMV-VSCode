# TMV NKE CAD Connector & Intranet Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Realizzare un Windows Service resiliente in .NET 8 con Kestrel integrato per orchestrare l'invio asincrono delle richieste CAD dall'ERP Gamma Enterprise (`DBTMV`) verso le WebAPI NKE Robot, comprensivo di dashboard web intranet (Swiss Office Minimal) per il monitoraggio live e la forzatura manuale degli ordini.

**Architecture:** Il database MSSQL (`DBTMV`) gestisce esclusivamente tabelle transazionali e di coda (`RT13_NKE`, tabella ponte ordini `RT13_NKE_DOCS_GEMINI`, log esteso `RT13_NKE_LOG_DETAIL_GEMINI`). Il Windows Service (.NET 8) esegue in background due worker: un dispatcher serializzato (cooldown 30s, retry max 3, dead-letter) e un alimentatore massivo schedulato (ogni 10 min), esponendo tramite ASP.NET Core Kestrel (porta 5050) le API REST e la Single Page Application per gli operatori dell'Ufficio Tecnico.

**Tech Stack:** C# .NET 8 (LTS), `Microsoft.Extensions.Hosting.WindowsServices`, ASP.NET Core Kestrel, `Microsoft.Data.SqlClient`, `Dapper`, HTML5/CSS/Vanilla JS ("Swiss Office Minimal"), MSSQL 2017 (14.0.2120.1).

**Spec:** `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\2026-10-23-servizio-nke-monitor-intranet-design.md`

## Global Constraints

- **Piattaforma DB**: MSSQL 14.0.2120.1 (SQL Server 2017).
- **Naming SQL**: prefissi obbligatori `SPSO_` per Stored Procedure, `RT13_..._GEMINI` o `SO_..._GEMINI` per tabelle personalizzate, suffisso `_GEMINI` su ogni nuovo oggetto.
- **Transazionalità e Sicurezza**: blocchi `TRY...CATCH` e `BEGIN TRAN / COMMIT` per modifiche DML; letture sempre con `WITH (NOLOCK)`.
- **Cartiglio Narrativo**: ogni script SQL deve iniziare con il cartiglio narrativo SOLVERIS e commenti prolissi sul "perché" di business.
- **No-Python Policy**: divieto assoluto di script Python per manipolare o esportare documenti.
- **Architettura Web**: Single Page Application leggera senza framework pesanti esterni (nessun npm build complesso a runtime), servita direttamente da Kestrel su porta 5050 in LAN interna.
- **Serializzazione NKE**: rigoroso rispetto del cooldown minimo di 30 secondi tra chiamate verso `http://192.168.1.138:7171/configure`.

## Review Focus

1. **NKE WebAPI Error Payload in HTTP 200**: la WebAPI NKE potrebbe rispondere HTTP 200 ma contenere nel body JSON un errore applicativo iLogic (es. `{"Error":"Inventor exception"}`). Il parser semantico deve intercettare il fallimento e trattarlo come errore.
2. **NKE WebAPI Timeout / Socket Failure**: mancata risposta entro 10 secondi o caduta della connessione TCP verso `192.168.1.138:7171`. Il client deve gestire il timeout senza bloccare i thread del worker e scatenare il retry con backoff.
3. **Dead-Letter Handling**: se un record fallisce tutti e 3 i tentativi, deve essere evacuato dalla coda attiva `RT13_NKE` e registrato in `RT13_NKE_LOG_DETAIL_GEMINI` con `ESITO_GENERAZIONE = 0` per non bloccare la pipeline, allertando la dashboard.
4. **Mutua Esclusione tra Scan Massivo e Forzatura Manuale**: se l'utente clicca "Invia Subito a NKE" esattamente mentre scatta il timer schedulato dei 10 minuti, un semaforo/lock deve serializzare l'esecuzione su `SPSO_NKE_ALIMENTA_CODA_GEMINI`.
5. **Delta Engine Safety**: in `SPSO_NKE_ALIMENTA_CODA_GEMINI`, il delta engine deve verificare tassativamente `WHERE RT13_FILE_GENERATO = 1` nello storico, in modo che record falliti non vengano erroneamente ignorati come `GIA_A_LOG`.

---

### Task 1: Potenziamento Strato Database SQL Server (`DBTMV`)

**Files:**
- Create: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\01_CREAZIONE_STRUTTURE_DATI_NKE_GEMINI.sql`
- Modify: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\SPSO_NKE_ALIMENTA_CODA_GEMINI.sql`
- Test: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\02_TEST_STRUTTURE_E_DELTA_GEMINI.sql`

**Interfaces:**
- Consumes: `DBTMV.dbo.RT13_NKE`, `DBTMV.dbo.RT13_NKE_LOG`, `DBTMV.dbo.DO11_DOCTESTA`, `DBTMV.dbo.DO30_DOCCORPO`
- Produces:
  - Table: `[dbo].[RT13_NKE_DOCS_GEMINI]` (`ID_DOC_NKE`, `MG87_GUID`, `DO11_DITTA_CG18`, `DO11_DOCUM_MG36`, `DO11_NUMDOC`, `DO11_SEZDOC`, `DO11_ANNODOC`, `DO11_DATADOC`, `DO30_PROGRIGA`, `DO30_CODART_MG66`, `DO30_OPZIONE_MG5E`, `RAGIONE_SOCIALE`, `DATA_INSERIMENTO`)
  - Table: `[dbo].[RT13_NKE_LOG_DETAIL_GEMINI]` (`ID_LOG`, `MG87_GUID`, `MOMENTO_CHIAMATA`, `LATENCY_MS`, `HTTP_STATUS`, `PAYLOAD_INVIATO`, `RISPOSTA_RICEVUTA`, `ESITO_GENERAZIONE`, `MESSAGGIO_ERRORE`, `OPERATORE`, `IP_CLIENT`)
  - Stored Procedure: `[dbo].[SPSO_NKE_ALIMENTA_CODA_GEMINI]` (aggiornata con popolamento di `RT13_NKE_DOCS_GEMINI` e delta check con `RT13_FILE_GENERATO = 1`)

- [ ] **Step 1: Scrittura DDL per tabelle `RT13_NKE_DOCS_GEMINI` e `RT13_NKE_LOG_DETAIL_GEMINI`**
  Creare il file `01_CREAZIONE_STRUTTURE_DATI_NKE_GEMINI.sql` contenente cartiglio narrativo SOLVERIS, verifiche `OBJECT_ID IS NULL`, creazione colonne, vincoli PK e indici performanti su `MG87_GUID`, `DO11_NUMDOC` e `MOMENTO_CHIAMATA`.

- [ ] **Step 2: Esecuzione DDL su `DBTMV` tramite MCP mssql-dbtmv**
  Eseguire lo script su `DBTMV` e verificare la presenza delle due tabelle e relativi indici.

- [ ] **Step 3: Aggiornamento Stored Procedure `SPSO_NKE_ALIMENTA_CODA_GEMINI`**
  Modificare `SPSO_NKE_ALIMENTA_CODA_GEMINI.sql`:
  - Nel Delta Engine: aggiungere la condizione `WHERE l1.RT13_FILE_GENERATO = 1` nella verifica esistenza in `RT13_NKE_LOG`.
  - Nella Sezione 4 (Esecuzione Reale): inserire l'istruzione di popolamento di `[dbo].[RT13_NKE_DOCS_GEMINI]` per tutte le righe analizzate appartenenti ai lotti accodati (`EsitoDelta IN ('DA_INSERIRE_NUOVO', 'DA_REINVIARE_FORZATO')`), associando la ragione sociale del cliente da `CG44_CLIFOR`.
  - Incrementare la revisione nel cartiglio storico (Rev. 2.0).

- [ ] **Step 4: Compilazione della SP aggiornata su `DBTMV`**
  Eseguire `ALTER PROCEDURE [dbo].[SPSO_NKE_ALIMENTA_CODA_GEMINI]` su `DBTMV`.

- [ ] **Step 5: Esecuzione suite di test su CO 5519**
  Creare ed eseguire `02_TEST_STRUTTURE_E_DELTA_GEMINI.sql` per simulare l'ordine 5519 (`@ModalitaDryRun = 1`), verificare il delta, poi testare l'alimentazione in transazione con rollback per accertare il corretto popolamento di `RT13_NKE_DOCS_GEMINI`.

---

### Task 2: Scaffolding Progetto .NET 8 Worker Service & Setup Soluzione

**Files:**
- Create: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\TMV.NKE.Service\TMV.NKE.Service.sln`
- Create: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\TMV.NKE.Service\src\TMV.NKE.Service\TMV.NKE.Service.csproj`
- Create: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\TMV.NKE.Service\src\TMV.NKE.Service\appsettings.json`
- Create: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\TMV.NKE.Service\src\TMV.NKE.Service\Program.cs`
- Create: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\TMV.NKE.Service\tests\TMV.NKE.Service.Tests\TMV.NKE.Service.Tests.csproj`

**Interfaces:**
- Consumes: Framework .NET 8 SDK
- Produces: Progetto compilabile con supporto sia ad ASP.NET Core Kestrel (porta 5050) che a Windows Service (`Microsoft.Extensions.Hosting.WindowsServices`).
- Configurazione `appsettings.json`:
  ```json
  {
    "ConnectionStrings": {
      "DBTMV": "Server=localhost;Database=DBTMV;Integrated Security=True;TrustServerCertificate=True;"
    },
    "NkeSettings": {
      "EndpointUrl": "http://192.168.1.138:7171/configure",
      "TimeoutSeconds": 10,
      "CooldownSeconds": 30,
      "MaxRetries": 3,
      "QueuePollingIntervalSeconds": 10,
      "MassiveIngestionIntervalMinutes": 10,
      "LookbackDays": 15
    },
    "Kestrel": {
      "Endpoints": {
        "Http": {
          "Url": "http://0.0.0.0:5050"
        }
      }
    }
  }
  ```

- [ ] **Step 1: Creazione cartelle e soluzione .NET**
  Inizializzare la directory `TMV.NKE.Service` ed eseguire `dotnet new sln -n TMV.NKE.Service`.

- [ ] **Step 2: Scaffolding del progetto Worker + Web API**
  Creare il progetto `src/TMV.NKE.Service` con template `web` (ASP.NET Core Web API / Minimal API abilitata a Kestrel).
  Aggiungere package NuGet:
  - `Microsoft.Extensions.Hosting.WindowsServices`
  - `Microsoft.Data.SqlClient`
  - `Dapper`

- [ ] **Step 3: Scaffolding del progetto Unit Test**
  Creare il progetto `tests/TMV.NKE.Service.Tests` con template `xunit` e aggiungere reference al progetto principale.
  Aggiungere package NuGet `Moq`, `FluentAssertions`.

- [ ] **Step 4: Configurazione `Program.cs` con `.UseWindowsService()`**
  Configurare `WebApplicationBuilder` per abilitare `builder.Host.UseWindowsService()`, registrare la configurazione tipizzata `NkeSettings` e registrare le dipendenze DI.

- [ ] **Step 5: Verifica Build**
  Eseguire `dotnet build TMV.NKE.Service.sln` e verificare esito 0 errori.

---

### Task 3: Modello Dati, Builder Payload NKE e Client HTTP Resiliente

**Files:**
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Models/NkePayloadModels.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Services/INkeClient.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Services/NkeClient.cs`
- Create: `TMV.NKE.Service/tests/TMV.NKE.Service.Tests/NkeClientTests.cs`

**Interfaces:**
- Consumes: `NkeSettings`
- Produces:
  - `public record NkeRequest(Guid Id, List<MasterDataEntry> MasterDataArray, List<object> ParametersArray)`
  - `public record NkeCallResult(bool IsSuccess, int HttpStatus, long LatencyMs, string RawResponse, string? ErrorMessage)`
  - `public interface INkeClient { Task<NkeCallResult> SendConfigureAsync(Guid guid, string codArt, string opzione, CancellationToken ct); }`
  - Formattazione deterministica del `Master` NKE:
    `LEFT(codArt, 5) + "---" + RIGHT(codArt, 6) + LEFT(opzione + "-----------------", 5) + "------" + RIGHT(LEFT(opzione + "-----------------", 11), 6) + RIGHT(LEFT(opzione + "-----------------", 17), 6)`

- [ ] **Step 1: Scrittura dei test unitari per il Builder di Payload e la Response Validation**
  In `NkeClientTests.cs`:
  - Test 1: `FormatMasterString_ShouldMatchLegacySpecification`: verifica la formattazione stringa Master esattamente coincidente con `SPSO_NKE_SCHED_GEMINI`.
  - Test 2: `ParseResponse_WhenHttp200AndValidJson_ShouldReturnSuccess`.
  - Test 3: `ParseResponse_WhenHttp200AndContainsErrorField_ShouldReturnFailure` (Review Focus 1).
  - Test 4: `ParseResponse_WhenHttp500_ShouldReturnFailure`.
  - Test 5: `SendConfigure_WhenTimeoutOccurs_ShouldReturnFailureWithTimeoutDetail` (Review Focus 2).

- [ ] **Step 2: Esecuzione test unitari e verifica del fallimento iniziale (RED)**
  Eseguire `dotnet test` per verificare che i test falliscano per assenza di implementazione.

- [ ] **Step 3: Implementazione di `NkePayloadModels` e `NkeClient` (GREEN)**
  Implementare la classe `NkeClient` con `IHttpClientFactory`:
  - Gestione timeout socket a 10s.
  - Costruzione del payload identico al formato Autodesk Inventor.
  - Misurazione latenza con `Stopwatch`.
  - Controllo semantico del body: se il JSON contiene proprietà `error`, `failed`, `exception` o messaggi di fault iLogic, impostare `IsSuccess = false`.

- [ ] **Step 4: Esecuzione test unitari e verifica del superamento (PASS)**
  Eseguire `dotnet test` e accertare 100% test superati.

---

### Task 4: Repository Dati e Interazione Transazionale con `DBTMV`

**Files:**
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Data/INkeRepository.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Data/NkeRepository.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Models/DatabaseEntities.cs`
- Create: `TMV.NKE.Service/tests/TMV.NKE.Service.Tests/NkeRepositoryTests.cs`

**Interfaces:**
- Consumes: `DBTMV` connection string, Dapper
- Produces:
  - `Task<QueueItem?> GetNextEligibleItemAsync(int cooldownSeconds, CancellationToken ct)`
  - `Task RecordSuccessAsync(Guid guid, NkeCallResult result, CancellationToken ct)`
  - `Task RecordRetryAsync(Guid guid, int currentRetries, NkeCallResult result, CancellationToken ct)`
  - `Task RecordDeadLetterAsync(Guid guid, NkeCallResult result, CancellationToken ct)` (Review Focus 3)
  - `Task<IEnumerable<QueueItemDto>> GetCurrentQueueAsync(CancellationToken ct)`
  - `Task<PagedResult<LogItemDto>> GetLogsAsync(LogFilterDto filter, CancellationToken ct)`
  - `Task<LogPayloadDto?> GetLogPayloadAsync(long logId, CancellationToken ct)`
  - `Task<KpiSummaryDto> GetKpisAsync(CancellationToken ct)`
  - `Task<IEnumerable<CandidateRowDto>> SimulateOrderAsync(int numDoc, int? annoDoc, CancellationToken ct)`
  - `Task<ForceOrderResultDto> ForceOrderAsync(int numDoc, int? annoDoc, bool sovrascrivi, string operatore, string ip, CancellationToken ct)`
  - `Task ExecuteMassiveIngestionAsync(int lookbackDays, CancellationToken ct)`

- [ ] **Step 1: Definizione DTO e Interfaccia Repository**
  Definire i contratti in `DatabaseEntities.cs` e `INkeRepository.cs`.

- [ ] **Step 2: Implementazione di `NkeRepository` con Dapper e SQL con `NOLOCK`**
  Implementare i metodi SQL:
  - Lettura del prossimo elemento in coda `RT13_NKE` rispettando l'ordinamento per data inserimento e il controllo cooldown sull'ultima chiamata.
  - Cancellazione atomica da `RT13_NKE` su successo o dead-letter, aggiornando `RT13_NKE_LOG` e inserendo il record in `RT13_NKE_LOG_DETAIL_GEMINI`.
  - Invocazione di `SPSO_NKE_ALIMENTA_CODA_GEMINI` per simulazione (`@ModalitaDryRun = 1`) ed esecuzione reale (`@ModalitaDryRun = 0`).

- [ ] **Step 3: Test unitari e di integrazione query**
  Verificare la correttezza delle query con test unitari su mapping e logiche di filtro.

---

### Task 5: Background Workers (Dispatcher & Massive Ingestion) con Mutua Esclusione

**Files:**
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Workers/DispatcherWorker.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Workers/MassiveIngestionWorker.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Services/IWorkCoordinationService.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Services/WorkCoordinationService.cs`
- Create: `TMV.NKE.Service/tests/TMV.NKE.Service.Tests/DispatcherWorkerTests.cs`

**Interfaces:**
- Consumes: `INkeRepository`, `INkeClient`, `NkeSettings`
- Produces:
  - `WorkCoordinationService`: semaforo/lock asincrono per prevenire collisioni tra forzatura da UI e scan massivo (Review Focus 4).
  - `DispatcherWorker`: ciclo `ExecuteAsync` ogni 10s: preleva elemento eleggibile -> chiama NKE -> esito positivo (cancella e archivia) | esito fallito < 3 tentativi (incrementa retry) | esito fallito >= 3 tentativi (dead letter scarto ed allarme).
  - `MassiveIngestionWorker`: ciclo `PeriodicTimer` ogni 10 min: acquisisce lock -> invoca `ExecuteMassiveIngestionAsync(15)` -> rilascia lock.

- [ ] **Step 1: Implementazione `WorkCoordinationService`**
  Creare il coordinatore di lock con `SemaphoreSlim(1, 1)` e metodi `ExecuteExclusiveAsync(...)` con logging.

- [ ] **Step 2: Implementazione `DispatcherWorker`**
  Implementare la logica del dispatcher con gestione del ciclo di vita dei tentativi e cattura delle eccezioni per non terminare mai il Windows Service in caso di errori temporanei.

- [ ] **Step 3: Implementazione `MassiveIngestionWorker`**
  Implementare il worker schedulato per l'alimentazione ordinaria ogni 10 minuti con token di cancellazione pulito.

- [ ] **Step 4: Test unitari del Dispatcher Loop e Dead-Letter**
  Simulare la sequenza di retry fino al terzo fallimento e verificare che l'elemento venga inviato a `RecordDeadLetterAsync`.

---

### Task 6: API REST & Controller HTTP

**Files:**
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Controllers/StatusController.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Controllers/QueueController.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Controllers/LogsController.cs`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/Controllers/OrdersController.cs`
- Create: `TMV.NKE.Service/tests/TMV.NKE.Service.Tests/OrdersControllerTests.cs`

**Interfaces:**
- Consumes: `INkeRepository`, `IWorkCoordinationService`, `INkeClient`
- Produces:
  - `GET /api/status`: status, uptime, ping NKE
  - `GET /api/kpis`: statistiche 24h
  - `GET /api/queue`: elenco coda corrente
  - `GET /api/logs?page=...&search=...&esito=...`: log storico paginato
  - `GET /api/logs/{id}/payload`: JSON payload e risposta NKE
  - `POST /api/orders/simulate`: dry-run su ordine
  - `POST /api/orders/force`: forzatura su ordine con audit operatore e IP client

- [ ] **Step 1: Test unitari su `OrdersController` (Validation & Input Sanitization)**
  Test su validazione numero ordine (non nullo, maggiore di 0), richiesta operatore, e gestione concorrenza se il lock è occupato.

- [ ] **Step 2: Implementazione dei Controller REST**
  Creare i 4 controller con gestione standard degli errori, status code coerenti (200, 400, 500) e serializzazione JSON camelCase.

- [ ] **Step 3: Estrazione IP Client e Headers per Audit Trail**
  Nel controller `OrdersController`, estrarre `HttpContext.Connection.RemoteIpAddress` per registrarlo permanentemente nella tabella `RT13_NKE_LOG_DETAIL_GEMINI`.

- [ ] **Step 4: Verifica integrazione Endpoint API**
  Eseguire test API tramite `WebApplicationFactory` o test xUnit per validare le risposte.

---

### Task 7: Frontend Intranet UI ("Swiss Office Minimal")

**Files:**
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/wwwroot/index.html`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/wwwroot/css/app.css`
- Create: `TMV.NKE.Service/src/TMV.NKE.Service/wwwroot/js/app.js`

**Interfaces:**
- Consumes: REST API (`/api/status`, `/api/kpis`, `/api/queue`, `/api/logs`, `/api/orders/*`)
- Produces: Interfaccia web Single Page responsive conforme al mockup approvato:
  - Palette: Enterprise Blue (`#2563EB`), Slate (`#0F172A`, `#1E293B`), sfondi neutri (`#F8FAFC`).
  - Font: Inter / Segoe UI per interfaccia, font monospace per stringhe tecniche.
  - Icone: SVG inline (nessuna dipendenza CDN esterna).
  - Banner di stato live con connessione a NKE.
  - 4 schede KPI.
  - Barra d'azione per simulazione e forzatura con campo operatore e conferma rapida.
  - Tabella log operativo con auto-refresh (10s), ricerca istantanea, badge di stato e cassetto (drawer) laterale per ispezione JSON.

- [ ] **Step 1: Realizzazione della struttura HTML5 semantica (`index.html`)**
  Implementare la testata aziendale, il banner di stato, il contenitore KPI, il pannello forzatura ordini, la tabella log con paginazione e il drawer di ispezione.

- [ ] **Step 2: Realizzazione del foglio di stile CSS pulito (`css/app.css`)**
  Implementare layout flessibile, tipografia proporzionata, stili per badge di stato (verde 200 OK, giallo warning/retry, rosso errore/timeout), animazioni per drawer e spinner di caricamento.

- [ ] **Step 3: Implementazione della logica JavaScript Vanilla (`js/app.js`)**
  - Chiamate asincrone `fetch()` verso le API interne.
  - Polling automatico dello stato e della tabella ogni 10 secondi.
  - Gestione click su "Simula" con rendering della preview righe.
  - Gestione click su "Invia Subito a NKE" con validazione sigla operatore e feedback immediato a video.
  - Apertura e popolamento del drawer per visualizzare il payload JSON e l'esito tecnico.

- [ ] **Step 4: Configurazione in `Program.cs` di `app.UseStaticFiles()` e `app.UseDefaultFiles()`**
  Assicurare che Kestrel serva la cartella `wwwroot` come root predefinita su porta 5050.

---

### Task 8: Collaudo E2E, Script di Installazione Servizio Windows & Consegna

**Files:**
- Create: `TMV.NKE.Service/scripts/install-service.ps1`
- Create: `TMV.NKE.Service/scripts/uninstall-service.ps1`
- Create: `TMV.NKE.Service/scripts/publish-appserver.ps1`
- Create: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\03_COLLAUDO_FINALE_E2E_GEMINI.sql`
- Modify: `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DISEGNI CAD - NKE\DOCUMENTO_TECNICO_REVISIONE_PROCESSO_NKE_GEMINI.md`

**Interfaces:**
- Consumes: Servizio compilato in `Release`, database `DBTMV`
- Produces: Pacchetto pronto per il deploy su Server APP del cliente e procedura di registrazione Windows Service (`sc.exe create TMV.NKE.Service`).

- [ ] **Step 1: Compilazione del pacchetto standalone in Release**
  Eseguire `dotnet publish -c Release -r win-x64 --self-contained false -o ./publish`.

- [ ] **Step 2: Creazione degli script PowerShell di gestione servizio Windows**
  Creare `install-service.ps1` con comandi `New-Service` / `sc.exe`, impostazione avvio automatico (`Delayed-Auto`), configurazione porta firewall locale 5050, e script di rimozione pulita `uninstall-service.ps1`.

- [ ] **Step 3: Esecuzione test E2E simulato**
  Avviare il servizio in modalità console locale (`dotnet run`), aprire `http://localhost:5050`, verificare KPI, eseguire simulazione ordine `CO 5519`, verificare la tabella log e l'ispezione payload.

- [ ] **Step 4: Aggiornamento Documento Tecnico Ufficiale e Ricompilazione Pandoc**
  Aggiornare `DOCUMENTO_TECNICO_REVISIONE_PROCESSO_NKE_GEMINI.md` includendo l'architettura del nuovo Servizio Windows e le istruzioni di installazione, quindi compilarlo in `.docx` con il template SOLVERIS.
