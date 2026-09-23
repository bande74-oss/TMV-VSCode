# Documento Tecnico e Funzionale: Analisi, Reingegnerizzazione e Ottimizzazione del Flusso Dati B7 $\rightarrow$ L7 per il Planning MRP

**Autore:** SOLVERIS - Bandera Marco  
**Ambiente:** Microsoft SQL Server 2017 (MSSQL 14.0.2120.1) - Database `DBTMV`  
**Oggetto Target:** Vista di Produzione `[dbo].[VPRT_PLANNING_B7_TO_L7]` (Revisione 2)  
**Modulo Applicativo:** Modulo B7L7 - Tracciato Configurabile `TMV-PLANNING-04` (Generazione Ordini Fornitore Fittizi B7 $\rightarrow$ L7)

---

## PARTE 1: LOGICHE DI BUSINESS E CONTESTO AZIENDALE

### 1.1 Il Contesto Manifatturiero e Metallurgico TMV: Acciai B7 vs L7/L7M
TMV opera con elevata specializzazione nella produzione meccanica di tiranti, prigionieri e componenti di bulloneria ad alte prestazioni destinate a settori ad altissima criticità operativa (valvole per condotte sottomarine, impianti chimici, raffinerie, compressori per l'Oil & Gas ed energia). In tali ambiti, la scelta della materia prima metallica è governata da rigidi standard internazionali (ASTM / ASME):

1. **Acciaio ASTM A193 Grado B7**:
   - È un acciaio legato al cromo-molibdeno (AISI 4140/4142 bonificato) ad elevata resistenza meccanica, largamente impiegato per servizi a temperature medio-alte (fino a oltre 400°C).
   - Costituisce lo standard de facto dell'officina: viene acquistato dalle acciaierie in grandi quantitativi continui sotto forma di barre tonde laminate o trafilate/pelate (articoli con prefissi `TDP`, `TDL`, `TDR`, `TDF`). TMV mantiene un consistente stock a magazzino e decine di ordini di acquisto aperti con consegne scaglionate nel tempo.
2. **Acciaio ASTM A320 Grado L7 e L7M**:
   - È anch'esso un acciaio legato al cromo-molibdeno, ma è specificamente certificato e collaudato per **servizio a basse temperature (applicazioni criogeniche)** fino a **-101°C**.
   - Oltre alle caratteristiche di resistenza a trazione e snervamento, la norma impone severe **prove di resilienza all'impatto ad intaglio (Charpy V-Notch Impact Test)** a -101°C, oltre a stringenti limiti di durezza massima (particolarmente restrittivi nel grado `L7M`, destinato ad ambienti acidi e corrosivi H2S secondo NACE MR0175).

### 1.2 La Fungibilità Controllata e il Limite dell'MRP Standard
Nella realtà operativa di TMV, una barra di acciaio acquistata originariamente come grado B7 possiede una composizione chimica base del tutto affine a quella del grado L7. Qualora il lotto di colata sia stato prodotto con adeguati trattamenti termici e superi con successo le prove di resilienza a -101°C (o venga qualificato tramite idoneo ciclo di bonifica/collaudo interno), **la barra B7 può essere formalmente e tecnicamente utilizzata per produrre tiranti o prigionieri destinati ad ordini cliente di grado L7 o L7M**.

Tuttavia, il motore standard di **Pianificazione dei Fabbisogni dei Materiali (MRP)** di TeamSystem Gamma Enterprise ragiona in modo deterministico e rigido per singolo codice articolo (`MG66_CODART`):
- Se l'ufficio commerciale acquisisce ordini cliente per articoli finiti in `L7`, l'MRP calcola il fabbisogno dipendente di materia prima grezza `L7` (es. `TDP00L7-M20-G-`).
- L'MRP standard confronta tale fabbisogno **esclusivamente** con le giacenze e gli ordini fornitore aperti sul codice esatto `TDP00L7-M20-G-`.
- Poiché l'azienda acquista e tiene a scorta prevalentemente barre `B7` (es. `TDP00B7-M20-G-`), l'MRP vedrebbe la materia prima `L7` costantemente in rottura di stock, generando una pletora di **proposte di acquisto non necessarie e premature**, pur avendo a magazzino centinaia di quintali di barre B7 perfettamente utilizzabili.

### 1.3 Il Meccanismo degli "Ordini Fornitore Ombra / Fittizi" (`DF-ORDINE-B7L7`)
Per superare questa limitazione senza dover stravolgere il motore core di Gamma Enterprise, ReadyTec e TMV hanno architettato una brillante soluzione basata su **ordini fornitore ombra**:
1. Viene istituito un tipo documento gestionale specifico denominato **`DF-ORDINE-B7L7`** (TipoDoc 22, Sezionale 'IN').
2. Attraverso il modulo dei tracciati configurabili di Gamma Enterprise, è stato creato il tracciato batch **`TMV-PLANNING-04`** (*"TMV - genera ordini Fittizi B7 TO L7"*).
3. Tale tracciato legge i dati estratti dalla vista `[dbo].[VPRT_PLANNING_B7_TO_L7]` e crea o aggiorna automaticamente ordini fornitore in cui:
   - I codici articolo B7 vengono traslati nel corrispondente codice L7 (sostituzione dinamica di `B7-` con `L7-` e di `B7M` con `L7M`).
   - Gli ordini a fornitore aperti mantengono il fornitore reale e la data di consegna prevista.
   - La giacenza fisica presente a magazzino viene convertita in un ordine fittizio con consegna immediata (data odierna).
4. Quando successivamente viene lanciata la simulazione MRP (`MRP-BASE` o `PLAN1`), l'algoritmo rileva gli ordini `DF-ORDINE-B7L7` come **disponibilità futura o immediata di materiale L7**, coprendo i fabbisogni reali della produzione ed evitando riordini errati.

### 1.4 La Composizione del Flusso Dati e il Ruolo del Fornitore Fittizio `99999999`
La vista è strutturata su tre canali logici distinti:
- **Canale 1 (Ordini Fornitore Aperti)**: Interroga gli ordini reali di acquisto (`DF-ORDINE`) non ancora completamente evasi (`DO72_FLGDAEVADERE = 1`), proiettando le quantità residue ancora da consegnare con le rispettive date contrattuali concordate con le acciaierie.
- **Canale 2 (Disponibilità Fisica a Magazzino)**: Interroga i progressivi di magazzino (`MG70_MAGPROQTA`) isolando la giacenza attuale positiva (`MG70_QGIACATT > 0`). Poiché il magazzino fisico non è un fornitore esterno, il sistema convenziona l'uso del **Fornitore Fittizio `99999999`**: il tracciato `TMV-PLANNING-04` riceve questo fornitore e genera l'ordine fittizio numero **`99999`** con data di consegna pari alla data odierna a mezzanotte (merce pronta all'uso).
- **Canale 3 (Sentinella di Garanzia per Reset dell'Ordine `99999`)**:
  Introdotto il 29/04/2025 da BM, questo canale inserisce forzatamente una riga a quantità zero con fornitore `99999999` e articolo base `'TDP'`.  
  **Perché questo passaggio è vitale?**  
  Se durante l'attività produttiva tutte le giacenze B7 venissero consumate (giacenza zero), il Canale 2 non restituirebbe alcuna riga. Senza il Canale 3, il fornitore `99999999` sparirebbe completamente dalla vista. Di conseguenza, il tracciato `TMV-PLANNING-04` non processerebbe il fornitore 99999999 e **non andrebbe a toccare né a sovrascrivere il vecchio ordine fittizio 99999** generato il giorno precedente. Nel sistema rimarrebbe attivo un ordine fittizio con giacenze fantasma, falsando l'intero piano di approvvigionamento dell'azienda. Con la sentinella a quantità zero, l'ordine 99999 viene sempre aggiornato/azzerato anche in totale assenza di stock.

### 1.5 L'Impatto Economico del Bug Risolto: Il Caso dei 15.000 Pezzi Dispersi
Nel corso della nostra analisi approfondita sul database reale `DBTMV`, è emersa un'anomalia critica nella logica originaria:  
La vista utilizzava l'operatore **`UNION`** semplice per aggregare i tre rami anziché `UNION ALL`.  
In SQL Server, `UNION` esegue una deduplicazione matematica implicita (*Sort / Distinct*) su tutte le colonne proiettate:
$$\text{Tupla} = \langle \text{Ditta}, \text{TipoCF}, \text{CliFor}, \text{CodArt}, \text{Opzione}, \text{DataCons}, \text{DataConsInt}, \text{QtaRes} \rangle$$
Qualora un fornitore reale avesse registrato **due righe d'ordine distinte** (magari su ordini diversi emessi in mesi differenti) per lo stesso articolo, con la medesima data di consegna contrattuale e la stessa quantità residua, la clausola `UNION` scartava silenziosamente la seconda riga.

**L'impatto accertato in produzione:**
- **Fornitore 2203**: Due righe d'ordine distinte per barre `TDP00B7-P34-C-` (Ordine n. 448 del 10/03/2026 riga 27 e Ordine n. 777 dell'11/05/2026 riga 6), entrambe con consegna `06/11/2026` e residuo `10.000 pz`. La `UNION` scartava 10.000 pezzi.
- **Fornitore 2403**: Due righe d'ordine distinte per barre `TDP00B7-M16-G-`, entrambe con consegna `09/04/2027` e residuo `5.000 pz`. La `UNION` scartava 5.000 pezzi.
- **Totale Dispersione**: **15.000 pezzi** di materie prime ordinate regolarmente alle acciaierie sparivano dal piano MRP, inducendo i pianificatori a ritenere l'azienda scoperta e inducendo potenzialmente ad acquisti ridondanti.  
Con la reingegnerizzazione a `UNION ALL`, il 100% della disponibilità è stata recuperata con esattezza chirurgica.

---

## PARTE 2: SCELTE TECNICHE, STRUTTURE DATI E DIAGNOSTICA PRESTAZIONALE

### 2.1 Mappatura delle Strutture Dati Coinvolte
L'architettura del flusso si appoggia a sei tabelle primarie di Gamma Enterprise:
- **`DO11_DOCTESTATA`**: Testata degli ordini fornitore (`DO11_TIPODOC = 22`, `DO11_DOCUM_MG36 = 'DF-ORDINE'`). Chiavi di seek: `DO11_DITTA_CG18 = 1`.
- **`DO30_DOCCORPO`**: Righe dei documenti d'ordine. Filtri applicati sul codice articolo (`DO30_CODART_MG66 LIKE '%B7%'` e prefisso nei tre caratteri `IN ('TDP','TDL','TDR','TDF')`).
- **`DO31_DOCCORPOORD`**: Dati di avanzamento temporale degli ordini (`DO31_DATACONS`, `DO31_DATACONSINT`).
- **`DO72_DOCCORPOSTATO`**: Stato di evasione gestionale della riga (`DO72_FLGDAEVADERE = 1` e `DO72_QTA1RES > 0`).
- **`MG70_MAGPROQTA`**: Progressivi di magazzino. Parametri per giacenza fisica attuale: `MG70_TIPOPROG = 1` (deposito/variante), `MG70_ANNO = 0` (esercizio corrente), `MG70_TIPOQTA = 1` (giacenza ordinaria), `MG70_QGIACATT > 0`.
- **`MG87_ARTDESC`**: Anagrafica descrizioni e verifica esistenza articoli (`MG87_LINGUA_MG52 = ''`). Utilizzata in `INNER JOIN` sul codice convertito per validare che l'articolo L7 di destinazione sia effettivamente codificato in anagrafica aziendale.
- **`CG18_ANADITTABASE`**: Anagrafica ditta base aziendale (`CG18_DITTA = 1`), impiegata come generatore deterministico a costo zero del record sentinella.
- **`IE25_TRACCIATI` / `IE26_TRACCIATIRIGHE` / `IE27_TRACCIATICAMPI`**: Tabelle dizionario del motore di integrazione Gamma che ospitano la definizione del tracciato `TMV-PLANNING-04`.

### 2.2 Analisi Tecnica: Risoluzione del Bug `UNION` $\rightarrow$ `UNION ALL`
Nel piano d'esecuzione della vista originaria, l'operatore `UNION` introduceva un operatore bloccante di tipo **Sort (Distinct Sort)** o **Hash Match (Aggregate)** con Memory Grant dinamico.  
Oltre a consumare risorse di calcolo per ordinare 228 righe e calcolare gli hash delle stringhe, causava l'aggregazione non voluta delle righe con medesima impronta.

Poiché:
1. Le righe del **Ramo 1** possiedono fornitori reali (nessun fornitore reale è censito come `99999999`).
2. Le righe del **Ramo 2** possiedono esclusivamente il fornitore fittizio `99999999` e quantità sempre strettamente positive (`QGIACATT > 0`).
3. La riga del **Ramo 3** possiede il fornitore fittizio `99999999`, articolo `'TDP'` e quantità rigorosamente pari a `0`.

I tre rami risultano **ontologicamente disgiunti e mutuamente esclusivi**: l'adozione di `UNION ALL` è la scelta architetturalmente perfetta, poiché azzera il costo dell'ordinamento in memoria e previene ogni perdita di righe d'ordine fornitore.

### 2.3 Rimozione del Collo di Bottiglia CLR .NET `FORMAT()`
Nella vista storica, per assegnare la data odierna alle giacenze fisiche venivano utilizzate le espressioni:
```sql
-- CODICE ORIGINALE (INEFFICIENTE)
FORMAT(GETDATE(),'yyyy-MM-dd 00:00:00.000') AS DO31_DATACONS
```
In SQL Server, la funzione `FORMAT()` non è una funzione T-SQL nativa interna, bensì un wrapper che effettua una chiamata di interoperabilità verso il motore **CLR .NET** (*Common Language Runtime*).
Inoltre, `FORMAT()` restituisce un tipo `NVARCHAR(4000)`.  
Poiché il primo ramo della vista definisce le colonne di tipo `DATETIME`, SQL Server era costretto a:
1. Convertire la data nativa `GETDATE()` in stringa `NVARCHAR` via CLR.
2. Riconvertire la stringa `NVARCHAR` in `DATETIME` durante la costruzione del set della `UNION`.

**Soluzione Adottata:**
```sql
-- CODICE OTTIMIZZATO SOLVERIS GEMINI
CAST(CAST(GETDATE() AS DATE) AS DATETIME) AS DO31_DATACONS
```
Questa sintassi esegue una doppia conversione binaria nativa a livello di CPU C++ interno del motore MSSQL, troncando l'orario a `00:00:00.000` con costo di calcolo infinitesimale e perfetta concordanza di tipo.

### 2.4 Reingegnerizzazione Deterministica del Record Sentinella (Ramo 3)
La revisione del 29/04/2025 implementava il Canale 3 interrogando `MG70_MAGPROQTA` con `MG70_QGIACATT = 0` in join con `MG87_ARTDESC`:
```sql
-- CODICE ORIGINALE RAMO 3 (FRAGILE E DISPENDIOSO)
SELECT DISTINCT MG70_DITTA_CG18, 1, 99999999, 'TDP', '', FORMAT(GETDATE(), ...), 0
FROM MG70_MAGPROQTA 
INNER JOIN MG87_ARTDESC ON ...
WHERE MG70_CODART_MG66 LIKE '%B7%' AND MG70_QGIACATT = 0
```
Tale query presentava due rischi:
1. **Rischio di Assenza Record**: Se a seguito di una chiusura di esercizio o di una manutenzione archivi le righe con giacenza zero venissero depennate, la query restituirebbe **0 righe**, vanificando lo scopo per cui era stata creata.
2. **I/O Inutile**: Eseguiva una scansione su `MG70` e `MG87` scartando tutti i dati letti tramite un `DISTINCT` forzato su costanti.

**Soluzione Adottata:**  
Il record sentinella viene generato direttamente interrogando la tabella anagrafica ditta `dbo.CG18_ANADITTABASE`:
```sql
-- NUOVO RAMO 3 DETERMINISTICO E GARANTITO
SELECT	
    CG18.CG18_DITTA AS DO30_DITTA_CG18,
    CAST(1 AS DECIMAL(1,0)) AS DO11_TIPOCF_CG44,
    CAST(99999999 AS DECIMAL(8,0)) AS DO11_CLIFOR_CG44,
    'TDP' AS DO30_CODART_MG66,
    CAST('' AS VARCHAR(20)) AS DO30_OPZIONE_MG5E,
    CAST(CAST(GETDATE() AS DATE) AS DATETIME) AS DO31_DATACONS,
    CAST(CAST(GETDATE() AS DATE) AS DATETIME) AS DO31_DATACONSINT,
    CAST(0 AS DECIMAL(14,3)) AS DO72_QTA1RES
FROM dbo.CG18_ANADITTABASE CG18 WITH (NOLOCK)
WHERE CG18.CG18_DITTA = 1;
```
La presenza del record è garantita al 100% (la ditta 1 esiste sempre) con **1 singola lettura logica** e 0 ms di CPU.

### 2.5 Ottimizzazione Indici e Sargability
Nel Ramo 1, la clausola WHERE originale filtrava unicamente `DO11_DOCUM_MG36 = 'DF-ORDINE'`.  
Poiché `DO11_DOCUM_MG36` non è la chiave primaria degli indici di `DO11_DOCTESTATA`, il query optimizer non riusciva ad utilizzare gli indici covering.  
Inserendo esplicitamente:
```sql
WHERE DO11.DO11_DITTA_CG18 = 1
  AND DO11.DO11_TIPODOC    = 22             -- Ordini Fornitore
  AND DO11.DO11_DOCUM_MG36 = 'DF-ORDINE'
```
L'ottimizzatore sfrutta l'indice composito `IDX02_DO11` (`DO11_DITTA_CG18, DO11_TIPODOC, DO11_STIPODOC`), trasformando una pesante scansione in un rapidissimo **Index Seek**.

### 2.6 Benchmark Prestazionale e Risultati Quantitativi

I test eseguiti sul database di produzione `DBTMV` (MSSQL 2017) mediante lo script [TEST_BENCHMARK_PLANNING_B7_TO_L7_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/B7L7/TEST_BENCHMARK_PLANNING_B7_TO_L7_GEMINI.sql) hanno prodotto le seguenti risultanze:

| Metrica di Valutazione | Vista Originale Pre-Fix (Rev. 1) | Vista Aggiornata in Produzione (Rev. 2) | Delta / Guadagno |
| :--- | :---: | :---: | :---: |
| **Righe Totali Estratte** | 226 | **228** | **+2 righe recuperate** |
| **Quantità Residua Totale** | 2.157.947,29 pz | **2.172.947,29 pz** | **+15.000,00 pz recuperati** |
| **Tempo di CPU (Worker Time)** | ~2.150 ms | **~140 ms** | **-93,5% tempo CPU** |
| **Tempo di Risposta (Elapsed Time)** | ~2.780 ms | **~180 ms** | **15x più veloce** |
| **Letture Logiche I/O** | 115.591 pagine | **< 4.200 pagine** | **-96,3% di I/O su disco/cache** |
| **Operatori Bloccanti in Memoria** | Sort (Distinct) con Grant | **Nessuno (Stream Concatenation)** | **Zero overhead memoria** |
| **Rischio Lock di Tabella** | Presente (no NOLOCK) | **Zero (WITH (NOLOCK) su tutte le tabelle)** | Concorrenza totale |

### 2.7 Strategia di Rilascio e Piena Retrocompatibilità con `TMV-PLANNING-04`
Per garantire la totale trasparenza operativa, la coerenza storica con l'architettura del database e azzerare ogni rischio di fermo produzione:
1. È stato aggiornato direttamente l'oggetto di produzione **`[dbo].[VPRT_PLANNING_B7_TO_L7]`** (documentato nel file [`VPRT_PLANNING_B7_TO_L7.sql`](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/B7L7/VPRT_PLANNING_B7_TO_L7.sql)).
2. In questo modo, il tracciato `TMV-PLANNING-04` continua ad interrogare nativamente il nome a cui è associato nelle tabelle dizionario `IE25_TRACCIATI`, beneficiando immediatamente del ripristino dei 15.000 pezzi e dell'abbattimento dei tempi di elaborazione senza richiedere interventi sui flussi ERP.

