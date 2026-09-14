# Verbale di Attività Svolte: Allineamento Cicli di Produzione ODL e Ripristino Esportazione MES

**Data Intervento:** 14/09/2026  
**Autore / Consulente:** SOLVERIS - Bandera Marco  
**Oggetto:** Integrazione gestionale Gamma TeamSystem con sistema MES OverOne – Normalizzazione cicli di lavoro e sblocco esportazione  
**Riferimento Ordine di Lavoro (ODL):** `202600184219` (Ditta 1)  

---

## Parte 1: Logiche di Business (Relazione per la Committenza)

### 1.1 Contesto e Scenario di Partenza
Nel modello produttivo aziendale, gli Ordini di Lavoro (ODL) emessi dal gestionale **Gamma TeamSystem** vengono sincronizzati automaticamente verso il sistema di fabbrica **MES OverOne** per consentire agli operatori sulle linee e ai terzisti esterni di avanzare le fasi di lavorazione, consuntivare i tempi e registrare i versamenti dei semilavorati e prodotti finiti.

Durante le consuete operazioni di esportazione dell'ODL **`202600184219`** (composto da **114 righe di produzione**), è emersa un'anomalia bloccante:
1. Sul sistema MES non venivano recepite tutte le fasi operative necessarie, in particolare le **fasi di conto lavoro esterno** (es. trattamenti termici/verniciature esterne affidate al fornitore `2682` con reparto `R300`).
2. Tale disallineamento comportava l'impossibilità per il MES di tracciare l'intero flusso operativo previsto dalla Distinta Base standard (il cosiddetto "Master Pattern" di 7 fasi: 10, 15, 16, 20, 30, 35, 40).
3. Inoltre, alcune fasi dell'ODL erano **già state avanzate dagli operatori in fabbrica** sul MES e recepite nel gestionale, rendendo categoricamente impraticabile qualsiasi azzeramento o rigenerazione cieca del documento, pena la perdita irrecuperabile del lavoro già consuntivato.

### 1.2 Obiettivi dell'Intervento
- **Garantire la completezza del ciclo:** Tutte le 114 righe dell'ODL devono disporre dell'intero pacchetto di 7 fasi operative (per un totale di **798 fasi attese**).
- **Protezione assoluta degli avanzamenti in corso:** Nessun dato già lavorato, consuntivato o versato (quantità consolidate, stati d'ordine, date e identificativi univoci) doveva essere toccato o eliminato.
- **Riconciliazione delle anagrafiche tecniche:** Allineare i cicli anagrafici collegati a ciascuna distinta base dell'ODL, valorizzando correttamente fornitori e reparti.
- **Ripristino dell'esportazione verso il MES:** Riportare lo stato dell'ODL in condizione di "Da esportare" nel flusso di lavoro, superando i vincoli storici del tracciato di esportazione e consentendo al connettore MES di acquisire l'ordine con successo.

### 1.3 Risultati Raggiunti
- **Zero perdite di dati:** Tutte le 571 fasi già avanzate o movimentate in produzione sono state rigorosamente protette e preservate nella loro integrità storica.
- **Ciclo completo al 100%:** L'ODL espone ora la totalità delle **798 fasi operative** previste dal ciclo produttivo corretto.
- **Tracciato MES verificato:** La vista di esportazione ufficiale (`VPMES_ODLExport`) estrae ora regolarmente **798 righe**, complete di tutti gli indicatori per il conto lavoro (Flag Conto Lavoro attivo, codice fornitore `2682`, codice reparto `R300`).
- **Sblocco e riesportazione completati:** L'ODL è stato reimpostato con successo nello stato "Da esportare" ed è pronto per essere elaborato dalla procedura automatica di interscambio.
- **Automatizzazione e riusabilità futura:** L'intervento è stato strutturato attraverso script parametrici e idempotenti, che consentiranno in futuro di gestire scenari analoghi su qualsiasi altro ODL variando unicamente il numero di registrazione.

---

## Parte 2: Scelte Tecniche e Dettaglio Implementativo (Handover Sviluppo)

### 2.1 Architettura Dati e Componenti Coinvolti
Il flusso di produzione e interscambio si basa su 7 entità relazionali nel database `DBTMV` (SQL Server):
1. **`DO11_DOCTESTATA` / `DO30_DOCCORPO`:** Testata e righe documento dell'ODL. Ciascuna riga DO30 possiede una propria distinta base identificata da `DO30_IDDISBA_PD95`.
2. **`DO46_DOCCORORDDET`:** Tabella operativa delle fasi di lavorazione dell'ODL (fasi schedulate, avanzamenti, stati ordine `DO46_INDSTATOORD`, quantità consolidate `DO46_QTA1CONSOLID`, puntatore al ciclo `DO46_IDCICLO_PD48`, e identificativo univoco `DO46_GUID`).
3. **`PD48_CICLI`:** Anagrafica dei cicli e delle fasi di lavorazione legata alla singola distinta (`PD48_IDDISBA_PD95`).
4. **`RT15_OVERONE_AVANZAMENTI`:** Tabella del connettore MES che memorizza gli avanzamenti effettuati in fabbrica per ciascun ODL/Riga/Fase.
5. **`CO4H_STATIATTUALI` / `CO4I_STATISTORICO`:** Gestione flussi e stati documentali Gamma (Flusso `10012`).
6. **`VPMES_ODLExport`:** Vista SQL ufficiale per l'estrazione dati utilizzata dal tracciato `TMV-MES-ODL-CSV` (tabella di transito `IE25`).

### 2.2 Root Cause Analysis (Analisi delle Cause Radice)
1. **Mancanza dell'INNER JOIN in `VPMES_ODLExport`:**
   La vista effettua la seguente giunzione obbligatoria:
   ```sql
   dbo.PD48_CICLI INNER JOIN dbo.DO46_DOCCORORDDET 
       ON dbo.PD48_CICLI.PD48_IDCICLO = dbo.DO46_DOCCORORDDET.DO46_IDCICLO_PD48
   ```
   Nelle righe dell'ODL 202600184219, le fasi di conto lavoro (`4031`, `4001`, `4011`, `4021`) avevano `DO46_IDCICLO_PD48 = NULL` e non avevano corrispondenza in `PD48_CICLI` per le singole distinte. Di conseguenza, l'INNER JOIN scartava l'intero record dal flusso di esportazione.
2. **Disallineamento puntatori distinti:**
   Le righe 2..114 di DO46 puntavano erroneamente agli ID ciclo (`PD48_IDCICLO`) appartenenti alla distinta della riga 1, creando disallineamenti di sequenza e fornitore.
3. **Fase 1480 priva di fornitore in PD48:**
   In `PD48_CICLI`, la fase 1480 presentava `PD48_CODFORN_CG44 = 0`, provocando l'azzeramento del campo 34 nel MES (`FLAG_CONTO_LAVORO_MES_C34`).
4. **Vincolo di Esclusione Storica nella Vista `VPMES_ODLExport`:**
   La vista adotta una subquery di filtro:
   ```sql
   LEFT JOIN (
       SELECT CO4I_GUID, CO4I_IDSTATO_CO4C 
       FROM dbo.CO4I_STATISTORICO 
       WHERE CO4I_IDFLUSSO_CO4B = 10012 AND CO4I_IDSTATO_CO4C = 10057
   ) AS CO4I_ESPORTATO ON DO11_GUID = CO4I_ESPORTATO.CO4I_GUID
   WHERE CO4I_DA_ESPORTARE.CO4I_IDSTATO_CO4C = 10056
     AND CO4I_ESPORTATO.CO4I_GUID IS NULL
   ```
   La presenza del record `10057` ("Esportato") nello storico inibiva qualsiasi riesportazione, anche in caso di aggiornamento dello stato corrente a `10056` da interfaccia gestionale.

### 2.3 Soluzione Tecnica Adottata: Smart UPSERT con Advancement Protection
Per risolvere il problema senza rischiare perdite di dati, è stata rigettata l'ipotesi di cancellazione massiva (`DELETE`) di DO46, adottando una strategia conservativa:
1. **Allineamento Anagrafico su `PD48_CICLI`:**
   - Inserimento delle fasi mancanti su ciascuna distinta base associata alle 114 righe documento, generando nuovi record con `IDENTITY` nativa e `NEWID()`.
   - Aggiornamento della fase 1480 con fornitore `2682` e reparto `R300`.
2. **Smart UPSERT su `DO46_DOCCORORDDET`:**
   - **Fasi già avanzate (`DO46_INDSTATOORD > 1`, `DO46_QTA1CONSOLID > 0` o presenti in `RT15`):** NON CANCELLATE. Mantenuti inalterati `DO46_GUID`, date, quantità consolidate e stati. Eseguito unicamente l'UPDATE mirato del puntatore `DO46_IDCICLO_PD48 = P.PD48_IDCICLO` collegandolo alla distinta corretta della riga.
   - **Fasi mancanti:** Inserite ex-novo leggendo le quantità ordinate da `DO30_DOCCORPO` (`DO30_QTA1`).
   - **Fasi spurie:** Eliminate solo ed esclusivamente se non avanzate (vergini).
3. **Sblocco e Ripristino Stato Documentale:**
   - Rimozione selettiva del record storico `10057` in `CO4I_STATISTORICO` per azzerare il vincolo bloccante della subquery.
   - Aggiornamento di `CO4H_STATIATTUALI` a `10056` ("Da esportare") con data validità corrente.
   - Attivazione automatica del trigger di sistema `TRG_INSERTSTORICO_CO4H_UPD` per il tracciamento del nuovo stato.

---

## Parte 3: Riferimento Script e Artefatti Realizzati

I componenti realizzati sono stati collocati nella directory di progetto:  
`c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DIBALOC\ADEGUAMENTO_CICLI_MES_ODL\`

1. **`AdeguamentoCiclo_DO46_GEMINI.sql`** (Revisione 6):  
   Script transazionale per l'allineamento dei cicli e delle fasi in `PD48_CICLI` e `DO46_DOCCORORDDET`, dotato di modalità Dry-Run di default (`@DryRun = 1`) e protezione avanzamenti.
2. **`ImpostaStato_DaEsportare_ODL_GEMINI.sql`** (Revisione 1):  
   Script transazionale per il ripristino dello stato a "Da esportare" (ID `10056`, Flusso `10012`) e rimozione controllata del vincolo storico per la riesportazione MES.
3. **`README_CONTESTO_TECNICO.md`**:  
   Manuale operativo e guida architetturale per sviluppatori e manutentori.

