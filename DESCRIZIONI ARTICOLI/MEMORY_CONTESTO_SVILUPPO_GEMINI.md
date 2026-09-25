# MEMORY CONTESTO SVILUPPO E KNOWLEDGE BASE GEMINI
## Progetto TMV: Normalizzazione Automatica, Diagnostica e Bonifica Massiva Descrizioni Articoli

**Autore:** SOLVERIS - Bandera Marco  
**Ambiente Database Ufficiale:** Microsoft SQL Server 2017 (MSSQL 14.0.2120.1) - Database `DBTMV`  
**ERP di Riferimento:** TeamSystem Gamma Enterprise  
**Directory Progetto:** `@[DESCRIZIONI ARTICOLI]`  
**Data Redazione Memory:** 25/09/2026  
**Stato Attività:** Completato, Testato in Dry-Run su 649.240 record e sincronizzato su Git / GitHub  

---

## 1. SCOPO DEL DOCUMENTO (AGENT MEMORY GUIDELINES)

Questo documento costituisce la **memoria tecnica persistente** e la **Knowledge Base architetturale** per Antigravity, agenti AI e colleghi sviluppatori per qualsiasi futuro sviluppo, manutenzione o estensione sul modulo di decodifica e gestione anagrafica descrizioni articoli di **TMV**.

> [!IMPORTANT]
> Prima di intraprendere qualsiasi modifica ai file della cartella `DESCRIZIONI ARTICOLI/`, consultare attentamente questo documento per evitare la reintroduzione di anomalie architetturali già risolte (es. errore MSSQL 8632, collasso dei ritorni a capo `CR+LF` o confusione sul parametro `@Sezione`).

---

## 2. CONTESTO DI BUSINESS E OBIETTIVI AZIENDALI

### 2.1 Chi è TMV e il Dominio Industriale
TMV è un'azienda leader nella produzione e lavorazione meccanica di viteria, tiranti, barre filettate, dadi e componenti speciali destinati a settori critici (Oil & Gas, chimico, petrolchimico, sottomarino ed energetico).  
I prodotti sono soggetti a normative internazionali stringenti:
- **Norme Dimensionali e Filettature:** UNI, DIN (es. DIN 976, DIN 934, DIN 912), ISO (es. ISO 4026, ISO 4762), ASME/ANSI (es. B18.2.1, B18.2.2, B18.3).
- **Norme Metallurgiche e Materiali:** ASTM (A193 B7/B7M, A320 L7/L7M, A194 2H/7M), acciai inossidabili (B8, B8M, AISI 316, 17-4 PH), leghe speciali (Inconel, Monel, Hastelloy con relative codifiche UNS).

### 2.2 Il Problema di Partenza
Nel corso degli anni, l'anagrafica articoli di Gamma Enterprise (`MG87_ARTDESC`, oltre 650.000 record) ha accumulato difformità e incongruenze:
1. **Diciture Passi e Quote Metriche Obsolete:** Alcune misure metriche non riportavano la quota nominale corretta o la distinzione tra passo grosso e fine (es. `M125 4` anziché `Ø 122,11 mm` o `M125x4`).
2. **Refusi Storici su Materiali:** Errori di battitura ereditati da vecchi inserimenti, in primis il refuso `UNS S020910` invece del corretto `UNS S20910` (Nitronic 50).
3. **Residui Testuali di Sistema:** Articoli configurati che contenevano ancora nel testo la dicitura `Modello` o `Min.0`.
4. **Assenza della Lingua Estera (`'LNG'`):** Centinaia di articoli erano privi della riga in lingua inglese, bloccando le esportazioni o richiedendo interventi manuali in fatturazione/spedizione.
5. **Troncamento Cieco al 70° Carattere:** Il limite fisico di `MG87_DESCART` (70 car. utili + 2 byte di CRLF) portava il vecchio sistema a spezzare frasi a metà (es. `1"-8UNC L:88` su riga 1 e `mm` orfano su riga 2; quote frazionarie spezzate tra intero e frazione).

---

## 3. ARCHITETTURA TECNICA E MODELLO DATI ERP GAMMA ENTERPRISE

### 3.1 Tabelle Anagrafiche Native Gamma Enterprise
- **`MG66_ANAGRART`**: Anagrafica articoli di base.
- **`MG87_ARTDESC`**: Descrizioni tecniche per lingua. Chiave primaria: `(MG87_DITTA_CG18, MG87_CODART_MG66, MG87_OPZIONE_MG5E, MG87_LINGUA_MG52)`.
  - `MG87_DESCART`: `VARCHAR(72)` (descrizione breve). In realtà ospita fino a 70 caratteri + terminatore `CR+LF`. **Attenzione:** il 99.5% dei record in TMV usa questa colonna come testo multiriga (Tipologia + CRLF + Materiale + CRLF + Diametro/Passo)!
  - `MG87_DESCARTEST`: `VARCHAR(1672)` (descrizione estesa).
  - `MG87_LINGUA_MG52`: `''` (spazio vuoto) per Italiano; `'LNG'` per Inglese Tecnico Internazionale.
  - `MG87_LASTCHANGE`: Timestamp di modifica.
- **`CM15_CONFGCOMM`**: Configuratore commerciale. Contiene la combinazione delle categorie dell'articolo e il legame con l'articolo modello matrice (`CM15_CODARTMOD_MG66`).
- **`CM17_CATCONFIG`**: Mappatura tra configurazione e valori assegnati per categoria.
- **`CM01_CATEGORIECOMM`**: Elenco categorie: `1` = Tipologia, `2` = Minorazione, `3` = Materiale, `4` = Diametro, `5` = Passo.
- **`CM02_VALORICATCOMM`**: Decodifiche descrittive dei valori di categoria.
- **`MG5E_OPZIONI`** e **`MG6B_GESVARART`**: Varianti operative (`A0`=Lunghezza, `A1`=Coating 1, `A2`=Coating 2, `A3`=Tornitura Tondi Dxxx / Quota 1, `A4`=Quota 2).

### 3.2 Tabelle Personalizzate SOLVERIS / Readytec
- **`RT03_DESCRALTER`**: Descrizioni alternative per Tipologia, Materiale e Minorazione (distinzione Metrico vs Pollici).
- **`RT04_DESCRALTER_OPZ`**: Decodifiche descrittive varianti per trattamenti superficiali A1 e A2.
- **`RT05_DESCR_DIAM_PASSO`**: Tabella combinatoria diametro/passo. È la sorgente primaria che determina se comporre la dicitura con `Ø ... mm` (per tiranti TDP, TDR, TDL, TDF) o `Diametro x Passo` (es. `M125x4`).
- **`RT12_AGG_DESCR_ART`**: Tabella di frontiera delta per i batch incrementali.
- **`RT14_VARIABILI_READYTEC`**: Watermark temporale per esecuzioni batch (es. variabile `'SPRT_TMV_AGG_DESCR_ART'`).

### 3.3 Tabelle e Viste di Nuova Concezione (Suffisso `_GEMINI`)
- **`SO_DIFF_DESCRIZIONI_GEMINI`**: Tabella globale di audit e staging. Contiene l'intero storico delle discrepanze rilevate, il testo attuale vs testo calcolato (Short e Long), la classificazione del motivo (`MotivoDifferenza`), e la marca temporale di bonifica (`DataAdeguamento`).
- **`VPSO_DIFF_DESCRIZIONI_GEMINI`**: Vista aggregata per `(Ditta, Prefisso, MotivoDifferenza)` per il monitoraggio direzionale.
- **`VPRT_ARTICOLI_MODELLO`**: Vista protetta di isolamento degli articoli modello matrice (`CM15_CODARTMOD_MG66`).

---

## 4. CRONISTORIA DELL'EVOLUZIONE E ROOT CAUSE DEI 3 INCIDENTI CHIAVE

Nel corso dello sviluppo e del collaudo su base dati di produzione, sono stati affrontati e risolti tre incidenti tecnici di altissima complessità:

### INCIDENTE 1: Errore MSSQL 8632 (Expression Services Limit Reached)
- **Sintomo:** Durante la prima esecuzione massiva di `SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI`, SQL Server abortiva con:  
  `Internal error: An expression services limit has been reached. Please look for potentially complex expressions in your query, and try to simplify them (Error 8632).`
- **Root Cause:** La funzione smart-split `dbo.SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI` era stata originariamente implementata come **Inline Table-Valued Function (iTVF)**. In un piano di esecuzione massivo su centinaia di migliaia di righe, il Query Optimizer di SQL Server inietta il codice dell'iTVF direttamente nell'albero delle espressioni della query principale. La presenza di due chiamate parallele (Short e Long) con annidamenti di `SUBSTRING`, `TRIM`, `CASE` e join multiple ha fatto collassare l'Expression Tree Compiler di MSSQL 14.0.
- **Risoluzione Definitiva:** Riconversione della funzione da iTVF a **Multi-Statement Table-Valued Function (mTVF)** con dichiarazione esplicita della variabile `@Result TABLE`. In questo modo SQL Server crea una barriera di ottimizzazione: esegue la funzione come modulo procedurale autonomo e non ne espande l'albero sintattico nella query esterna, azzerando l'errore 8632.

### INCIDENTE 2: Collasso dei Ritorni a Capo `CR+LF` e Incollamento delle Parole (Dadi Check 4)
- **Sintomo:** Nei risultati di Check 4 sulla famiglia dadi (`D--`), le parole risultavano attaccate:
  - *Attuale:* `Hex Nut DIN 934 H=D  HASTELLOY X/UNS N06002  M160 Passo Grosso`
  - *Calcolato errato:* `Hex Nut DIN 934 H=DHASTELLOY X/UNS N06002M160x8` (mancavano gli spazi tra `H=D` e `HASTELLOY` e tra `N06002` e `M160x8`).
  - Contestualmente, il Check 1 segnalava un volume esorbitante di **350.000 articoli** classificati come `RETTIFICA_SOLO_SHORT`.
- **Root Cause:** All'interno di `SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI` era presente una pulizia preliminare:
  `DECLARE @Clean VARCHAR(MAX) = RTRIM(LTRIM(REPLACE(REPLACE(@TestoGrezzo, CHAR(13), ''), CHAR(10), '')));`
  Questa istruzione cancellava tutti i ritorni a capo interni nativi di Gamma Enterprise senza sostituirli con spazi. Inoltre, la query di confronto eseguiva `RTRIM` *prima* della rimozione dei ritorni a capo, non trimmando gli spazi prima del CRLF e generando centinaia di migliaia di falsi positivi.
- **Risoluzione Definitiva:**
  1. In `SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI`: sostituzione del `REPLACE` con `TRIM(' ' + CHAR(9) + CHAR(13) + CHAR(10) FROM @TestoGrezzo)`. In MSSQL 2017 la sintassi `TRIM(chars FROM str)` opera **esclusivamente sui bordi esterni**, preservando integralmente i `CR+LF` interni tra le righe.
  2. Protezione del blocco diametro: impedito qualsiasi spezzamento subito dopo il simbolo `Ø` (`CHAR(216)`).
  3. Nel confronto diagnostico: inversione in `RTRIM(REPLACE(REPLACE(testo, CR, ''), LF, ''))` per eliminare gli spazi residui dopo la rimozione del CRLF.

### INCIDENTE 3: Disallineamento del Parametro `@Sezione` in `SFSO_TMV_DESCRIZIONE_GEMINI`
- **Sintomo:** Anche dopo la correzione dei CRLF, famiglie massive come `VEI%` (206.000 record) e `T--%` (53.000 record) continuavano a evidenziare oltre il 70% di discrepanze su SHORT.
- **Root Cause (Analisi Chirurgica):** Nella funzione `dbo.SFSO_TMV_DESCRIZIONE_GEMINI`, l'assegnazione finale era:
  `IF TRIM(UPPER(@Sezione)) = 'SHORT' SET @Descrizione = TRIM(@DescrizioneBreve);`
  Nelle procedure storiche e nella SP diagnostica, la chiamata per la lingua italiana veniva eseguita con **stringa vuota `''`** (ovvero `@Sezione = ''`).  
  Poiché `'' <> 'SHORT'`, la condizione falliva sistematicamente e la funzione restituiva `@Descrizione`, che conteneva la descrizione **LONG IN LINGUA INGLESE**!  
  La procedura diagnostica stava letteralmente confrontando la descrizione italiana attuale di `MG87` con la descrizione inglese calcolata, generando 340.000 falsi positivi!
- **Risoluzione Definitiva (Rev. 2.2):**
  Estesa la tolleranza della condizione di restituzione:
  ```sql
  IF TRIM(UPPER(ISNULL(@Sezione, ''))) IN ('SHORT', '')
      SET @Descrizione = TRIM(@DescrizioneBreve);
  ```
  In questo modo la funzione restituisce la descrizione breve italiana sia se invocata con `'SHORT'`, sia con `''`, sia con `NULL`. Con questa correzione, famiglie come `026%`, `VEI%`, `T--%`, `D--%` hanno visto azzerarsi le discrepanze fittizie, passando dal 70% a **0 (ZERO)** discrepanze reali.

---

## 5. REGOLE DI BUSINESS PER IL CALCOLO E LO SPEZZAMENTO DELLE DESCRIZIONI

Le seguenti regole sono vincolanti per qualsiasi implementazione:

### 5.1 Regole di Spezzamento Intelligente (`SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI`)
1. **Priorità alla Descrizione Primaria:** Se la stringa utile misura $\le 70$ caratteri, si alloca per intero su `DescrizionePrimaria` con terminatore `CR+LF` finale.
2. **Soglia di Tolleranza 71–72 Caratteri:** Se misura esattamente 71 o 72 caratteri, occupa per intero il campo fisico senza spezzarsi e senza aggiungere il terminatore `CR+LF` (per evitare overflow oltre 72 byte).
3. **Presidio Unità di Misura:** Lo spezzamento non deve **mai** separare un valore numerico dalla sua unità di misura. Rifiutare spazi che precedono direttamente `mm%`, `mt%`, `in%`, virgole `,%` o frazioni numeriche `'[0-9]/%'` (es. `1 1/2"`).
4. **Presidio Simbolo Diametro `Ø`:** Non spezzare mai subito dopo `Ø` o `CHAR(216)` (es. `Ø 122,11 mm` deve restare unito).
5. **Preservazione dei CR+LF Interni:** Non rimuovere mai i ritorni a capo interni con `REPLACE`; pulire solo i margini esterni.

### 5.2 Regole di Salvaguardia Anagrafica (Sicurezza Assoluta)
1. **Esclusione Articoli Modello:** Tutte le query DML/diagnostiche devono includere il filtro:
   ```sql
   AND NOT EXISTS (
       SELECT 1 FROM dbo.VPRT_ARTICOLI_MODELLO AS mod WITH (NOLOCK)
       WHERE mod.CM15_DITTA_CG18 = ditta AND mod.CM15_CODARTMOD_MG66 = codart
   )
   ```
2. **Esclusione Articoli Fuori Configuratore:** Elaborare esclusivamente articoli censiti nel configuratore commerciale (`INNER JOIN dbo.CM15_CONFGCOMM`). Gli articoli a disegno cliente o inseriti manualmente non devono mai essere toccati da automatismi.

---

## 6. CATALOGO DEI COMPONENTI E SCRIPT NEL WORKSPACE

Tutti i componenti risiedono in `c:\Users\marco\OneDrive\Documenti\READYTEC\TMV\VSCODE - TMV\DESCRIZIONI ARTICOLI\`:

| Nome File | Tipo Oggetto | Ruolo e Descrizione Operativa |
| :--- | :--- | :--- |
| `SFSO_TMV_DESCRIZIONE_GEMINI.sql` | Scalare FN (Rev. 2.2) | Motore algoritmico centrale. Calcola la stringa completa grezza Short o Long. Supporta `@Sezione` in `('SHORT', '', NULL)` e `'LNG'/'LONG'`. |
| `SFSO_TMV_SPLIT_DESCRIZIONE_GEMINI.sql` | Table-Valued FN (Rev. 2.1) | Funzione mTVF di smart-split a 70/72 car. con presidi dimensionali e preservazione CRLF. |
| `SO_DIFF_DESCRIZIONI_GEMINI.sql` | Tabella DDL | Tabella globale di staging per l'intero archivio aziendale con indici su prefisso e motivo. |
| `VPSO_DIFF_DESCRIZIONI_GEMINI.sql` | Vista DDL | Vista di sintesi aggregata per Ditta, Prefisso e MotivoDifferenza. |
| `SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI.sql` | Stored Procedure (Rev. 3.2) | Motore diagnostico universale. Scansiona 650k articoli in chunk per prefisso in ~7-8 minuti. |
| `SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI.sql` | Stored Procedure (Rev. 2.1) | Motore esecutivo di bonifica. Opera a batch transazionali (default 5.000 rec/commit) in modalità `@DryRun = 1` o `@DryRun = 0`. |
| `SPRT_TMV_AGG_DESCR_ART.sql` | Stored Procedure (Rev. 3.0) | Revisione conservativa della SP batch originaria di Gamma Enterprise per recepire le nuove funzioni senza rompere i job schedulati. |
| `MASTER_DEPLOY_PRODUZIONE_AGGIORNAMENTO_DESCRIZIONI_GEMINI.sql` | Script Deploy | Script cumulativo idempotente per l'installazione iniziale di tutti i componenti sul DB di produzione. |
| `PATCH_FIX_ERRORE_8632_PRODUZIONE_GEMINI.sql` | Patch SQL | Script di correzione per riconversione mTVF e risoluzione errore 8632. |
| `PATCH_FIX_FORMATTAZIONE_DADI_GEMINI.sql` | Patch SQL | Script di ripristino CRLF e ricalcolo selettivo rapido per famiglia dadi `D--%`. |
| `LANCIO_TEST_FULL_RUN_DIAGNOSTICA_GEMINI.sql` | Script Operativo | Esegue il ricalcolo diagnostico totale in modalità TEST (Dry-Run) con suite di 5 CHECK finali. |
| `ESECUZIONE_AGGIORNAMENTO_FINALE_MG87_GEMINI.sql` | Script Operativo | Esegue l'aggiornamento massivo reale su `MG87_ARTDESC` a blocchi da 5.000 record con verifiche di conformità. |
| `ROLLBACK_TOTALE_MG87_GEMINI.sql` | Script Ripristino | Ripristina 100% lo stato originale dell'archivio da backup audit e svuota le tabelle di staging. |
| `TABELLA_CONTROLLO_UT_RT05_GEMINI.md` | Documento UT | Tabella riassuntiva dei minimi normativi concordati con l'Ufficio Tecnico per filettature metriche (M110..M160). |
| `DOC_TECNICO_INSIEME_TMV_AGG_DESCR_ART_GEMINI.md` | Documento Tecnico | Documentazione tecnica e architetturale dell'Insieme batch ImpExp Gamma Enterprise. |

---

## 7. RUNBOOK OPERATIVO PER SVILUPPATORI E AGENTI FUTURI

### 7.1 Come Eseguire una Diagnosi Mirata su una Singola Famiglia
Per testare modifiche o verificare una determinata famiglia (es. solo tiranti TDP `TDP%` o viti VEI `VEI%`) senza scansionare l'intero database:
```sql
USE [DBTMV];
GO

EXEC dbo.SPSO_TMV_CHECK_DIFF_DESCRIZIONI_GEMINI 
    @Ditta              = 1,
    @FiltroFamiglia     = 'TDP%', -- Scansiona solo prefissi corrispondenti
    @PulisciTabella     = 0,      -- Non svuotare il resto dello staging
    @SoloConDifferenze  = 1;      -- Registra solo record disallineati
GO
```

### 7.2 Come Verificare i Dati di Audit con i Controlli di Qualità
```sql
-- Sintesi globale per anomalia
SELECT 
    MotivoDifferenza,
    SUM(TotaleArticoli)       AS TotaleArticoli,
    SUM(TotShortDaAggiornare) AS ShortDaAggiornare,
    SUM(TotLongDaAggiornare)  AS LongDaAggiornare,
    SUM(TotLongDaInserire)    AS LongDaInserire
FROM dbo.VPSO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
GROUP BY MotivoDifferenza
ORDER BY TotaleArticoli DESC;

-- Controllo specifico su un articolo
SELECT CodiceArticolo, ShortAttuale, ShortNuovo, LongAttuale, LongNuovo, MotivoDifferenza
FROM dbo.SO_DIFF_DESCRIZIONI_GEMINI WITH (NOLOCK)
WHERE CodiceArticolo = 'TDP04B7-M1254-';
```

### 7.3 Come Applicare la Bonifica Esecutiva (Scrittura su DB)
```sql
USE [DBTMV];
GO

EXEC dbo.SPSO_TMV_ADEGUA_DESCRIZIONI_GEMINI
    @Ditta              = 1,
    @DryRun             = 0,    -- MODALITÀ EFFETTIVA: Scrive su MG87_ARTDESC
    @Prefisso           = NULL, -- NULL = Tutto il DB; oppure 'TDP', 'D--', ecc.
    @MotivoDifferenza   = NULL, -- NULL = Tutti i motivi; oppure 'BONIFICA_REFUSO_UNS'
    @AlimentaRT12       = 0,
    @BatchSize          = 5000, -- Transazioni a blocchi protetti
    @RicalcolaAudit     = 0;    -- Usa i dati già calcolati in SO_DIFF_DESCRIZIONI_GEMINI
GO
```

### 7.4 Procedura di Emergenza (Rollback)
In caso di anomalie riscontrate dopo una bonifica effettiva, eseguire immediatamente:  
📄 [`ROLLBACK_TOTALE_MG87_GEMINI.sql`](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/ROLLBACK_TOTALE_MG87_GEMINI.sql)  
Lo script ripristinerà i valori antecedenti di `ShortAttuale` e `LongAttuale` direttamente dalla tabella di audit `SO_DIFF_DESCRIZIONI_GEMINI`, cancellando le righe inserite ex-novo.

---
*Fine documento Knowledge Base SOLVERIS GEMINI.*
