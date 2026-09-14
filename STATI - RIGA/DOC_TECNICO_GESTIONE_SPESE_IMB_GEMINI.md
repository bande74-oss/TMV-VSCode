# Documento Tecnico e Funzionale: Gestione e Monitoraggio Righe Spesa IMB (Evasione Unica) nel Flusso Documentale TMV

**Autore:** SOLVERIS - Bandera Marco  
**Data e Ora:** 2026-09-14 15:45:00  
**Ambiente:** Microsoft SQL Server 2017 (MSSQL 14.0.2120.1) - Database `DBTMV`  
**Destinazione d'Uso:** Documento di riferimento interno e base di conoscenza per future revisioni della Stored Procedure `[dbo].[SPSO_AGGIORNA_STATI_RIGA_GEMINI]` e per l'allineamento dei flussi ERP.

---

## PARTE 1: LOGICHE DI BUSINESS E CONTESTO AZIENDALE

### 1.1 Il Ruolo delle Spese di Imballo nel Ciclo di Vendita TMV
Nel modello di business di TMV, gli ordini cliente possono includere voci accessorie oltre ai componenti meccanici fisici: spese di trasporto (`TRA`), spese bolli (`BOL`), certificati di conformità e collaudo (`VARA1`), e spese di imballo speciale (`IMB`).

Tra tutte le voci di spesa censite a sistema, la spesa `IMB` riveste un'importanza strategica e contabile peculiare:
- **Regola di Evasione Unica (`MG04_INDTIPOEVAS = 1`)**: L'anagrafica delle spese (`MG04_SPESE`) impone che la spesa di imballo venga addebitata ed evasa **una sola volta** nell'intero ciclo di vita dell'ordine cliente. Questo vincolo esiste per tutelare l'azienda e il cliente: se un ordine prevede consegne parziali scaglionate nel tempo (ad esempio 5 spedizioni parziali per coprire un lotto di 10.000 prigionieri), il cliente deve pagare l'imballo contrattualizzato una sola volta, e non vederselo riaddebitato su ogni singolo DDT di spedizione.

### 1.2 La Realtà Operativa dei Flussi Documentali
Dall'analisi capillare degli archivi 2026, è emersa una chiara discrepanza tra il flusso ideale e le dinamiche operative reali:

1. **Il Ruolo del Pre-DDT (`DC-PREDDT`, TipoDoc 2)**:
   - In TMV, prima della spedizione fisica, il magazzino emette un documento interno denominato "Avviso Merce Pronta / Pre-DDT" (`DC-PREDDT`).
   - Nel **97,5% dei casi**, la riga di spesa `IMB` dell'ordine cliente viene prelevata e consumata direttamente da questo `DC-PREDDT`.
   - Poiché il modello di trasformazione imposta il flag `DO33_FLGAGGQTATRASF = 1`, la spesa `IMB` sull'ordine cliente passa immediatamente a stato "Evaso" (`DO72_FLGEVASO = 1`) già all'emissione del Pre-DDT.
   - Di conseguenza, nessun DDT di spedizione finale (`DC-DDT`, TipoDoc 1) referenzia mai direttamente la spesa dell'ordine cliente: il legame transita obbligatoriamente attraverso il Pre-DDT intermedio.

2. **La Gestione delle Fatture Proforma (`DC-PROFORMA`, TipoDoc 5, STipoDoc 4)**:
   - Per clienti esteri o con condizioni di pagamento anticipato (es. Bonifico Anticipato), il commerciale emette una `DC-PROFORMA` a fronte dell'ordine prima di avviare o completare la lavorazione.
   - La Proforma ha finalità contabile e finanziaria (permette al cliente di effettuare il bonifico e all'amministrazione di incassare il corrispettivo).
   - In Gamma Enterprise, la Proforma viene emessa con `DO33_FLGAGGQTATRASF = 0`: **non scala le quantità e non evade l'ordine**.
   - **Criticità Emersa**: Quando la merce è pronta e il magazzino genera il `DC-PREDDT`, il gestionale vede la spesa `IMB` ancora come "non evasa" e la ripropone nel Pre-DDT. Se l'operatore di magazzino non la rimuove manualmente, la spesa rischia di finire anche sul DDT e sulla successiva fattura di saldo/riepilogo, determinando un doppio addebito.
   - Al contrario, se l'operatore la cancella dal Pre-DDT per evitare il doppio addebito, la catena documentale standard si interrompe.

3. **Il Comportamento della Fatturazione Amministrativa**:
   - Quando il flusso automatico si interrompe (la spesa non transita nel DDT), l'amministrazione, accorgendosi della mancanza dell'imballo al momento di emettere la Fattura Riepilogativa DDT (`DC-FATRIEPDDT`), adotta spesso la prassi di **aggiungere a mano la riga di spesa direttamente in fattura**.
   - Questo intervento manuale "sana" il ricavo aziendale, ma non lascia traccia nel grafo referenziale di `DO33_DOCCORPORIF`, rendendo la riga d'ordine "orfana" a livello informatico.

---

## PARTE 2: SCELTE TECNICHE, STRUTTURE DATI E ALGORITMI DI ANALISI

### 2.1 Mappatura delle Tabelle ERP Coinvolte
- **`DO11_DOCTESTATA`**: Testata dei documenti.
  - `DO11_TIPODOC = 21`: Ordini Clienti (`DC-ORDINE`).
  - `DO11_TIPODOC = 2`: Avvisi Merce Pronta / Pre-DDT (`DC-PREDDT`).
  - `DO11_TIPODOC = 1`: Documenti di Trasporto (`DC-DDT`, `DC-DDTCLIDC`).
  - `DO11_TIPODOC IN (3, 4, 5)`: Documenti di Fatturazione (`DC-FATRIEPDDT`, `DC-FATIMDDT-ES`, `DC-FATIMM`).
- **`DO30_DOCCORPO`**: Righe dei documenti.
  - `DO30_INDTIPORIGA = 4`: Riga di tipo Spesa Accessoria.
  - `DO30_CODSPESA_MG04 = 'IMB'`: Spese di Imballo.
  - `DO30_IMPORTO`: Valore netto della riga spesa.
- **`DO33_DOCCORPORIF`**: Grafo delle referenze tra documenti (chi genera cosa).
  - Campi chiave per il seek: `DO33_DITTA_CG18`, `DO33_NUMREGRIF_CO99`, `DO33_PROGRIGARIF_DO30`.
  - Flag di aggiornamento quantità: `DO33_FLGAGGQTATRASF` (1 = evade e scala la riga monte; 0 = referenza puramente descrittiva/proforma).
- **`DO72_DOCCORPOSTATO`**: Stato di evasione della riga a livello gestionale ERP (`DO72_FLGEVASO = 1` se evaso).
- **`CO4H_STATIATTUALI`**: Tabella di destinazione del motore degli stati riga (`CO4H_IDSTATO_CO4C`).
- **`MG04_SPESE`**: Tabella anagrafica codici spesa.
  - `MG04_INDTIPOEVAS = 1`: Evasione unica (solo IMB).
  - `MG04_INDTIPOEVAS = 2`: Evasione multipla (TRA, BOL, CON, ecc.).

### 2.2 Algoritmo di Tracciamento a Tre Livelli e Rilevamento Sanatorie Manuali
Per identificare con esattezza chirurgica lo stato di fatturazione di ciascuna delle 672 righe di spesa `IMB` del 2026, è stata implementata una navigazione gerarchica combinata:

```
[LIVELLO 1]  Ordine Cliente (21) ───────────────────────────────────────────────> Fattura (3/5)
[LIVELLO 2]  Ordine Cliente (21) ───────────> Pre-DDT / DDT (2/1) ──────────────> Fattura (3/5)
[LIVELLO 3]  Ordine Cliente (21) ───> Pre-DDT (2) ───> DDT (1) ─────────────────> Fattura (3/5)
                                                             │
                                                             └──> [Fattura Merce]
                                                                       │
                                                                       └──> Controllo riga manuale:
                                                                            (C_FAT.DO30_CODSPESA_MG04 = 'IMB'
                                                                             OR C_FAT.DO30_DESCART LIKE '%IMBALL%')
```

### 2.3 Risultati Quantitativi dell'Archivio 2026 (Totale 672 Righe IMB)

| Categoria Operativa | Numero Righe | % sul Totale | Descrizione Tecnica |
| :--- | :---: | :---: | :--- |
| **1. Regolarmente Fatturate via Flusso DO33** | **506** | **75,3%** | La riga ha completato regolarmente la catena (Ordine $\rightarrow$ Pre-DDT $\rightarrow$ DDT $\rightarrow$ Fattura Differita). |
| **2. Sanate a Mano dall'Amministrazione in Fattura** | **25** | **3,7%** | La merce è stata fatturata; la riga di spesa non era transitata via DO33, ma in fattura l'operatore ha aggiunto a mano la voce di imballo. |
| **3. Critiche: Merce Fatturata ma Spesa NON Fatturata** | **10** | **1,5%** | **Perdita economica reale (1.410,00 €)**. La merce è stata spedita e fatturata, ma la spesa non è presente in fattura né via flusso né a mano. |
| **4. In Attesa Fatturazione DDT (Spedite Recenti)** | **29** | **4,3%** | Merce spedita con DDT recenti (fine agosto / settembre 2026), in attesa del ciclo di fatturazione differita di fine mese. |
| **5. In Attesa Spedizione (Avviso Merce Pronta)** | **24** | **3,6%** | Righe con Pre-DDT emesso, merce pronta sul piazzale/magazzino in attesa di ritiro. |
| **6. Ordini Aperti / In Produzione** | **78** | **11,6%** | Ordini acquisiti, in lavorazione MES o officina, nessuna spedizione ancora avvenuta. |
| **TOTALE GENERALE** | **672** | **100,0%** | **Righe di spesa IMB censite negli ordini 2026.** |

### 2.4 Accortezze Implementative (Compatibilità MSSQL 2017 e GEMINI.md)
1. **Risoluzione Collation Conflicts**:  
   La tabella di sistema `tempdb` adotta la collation `Latin1_General_CI_AS`, mentre il database `DBTMV` utilizza `Latin1_General_100_CI_AS`. Tutte le DDL di tabelle temporanee create per queste analisi devono specificare obbligatoriamente `COLLATE DATABASE_DEFAULT` su ogni colonna alfanumerica (`VARCHAR`).
2. **Copertura Indici e Performance Seek**:  
   Ogni predicato di join su `DO33_DOCCORPORIF` deve contenere obbligatoriamente `DO33_DITTA_CG18 = 1` come primo termine per consentire l'utilizzo degli indici compositi cluster/covering (`IDX_DO33_COVERING_RIF_GEMINI`), riducendo l'I/O da milioni di letture a pochi millisecondi.

