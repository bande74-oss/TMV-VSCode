# Knowledge Base & Contesto Tecnico: Adeguamento Cicli ODL e Integrazione MES OverOne

**Cartella di Riferimento:** `DIBALOC/ADEGUAMENTO_CICLI_MES_ODL`  
**Autore:** SOLVERIS - Bandera Marco  
**Target Environment:** MS SQL Server 14.0.2120.1 (SQL Server 2017) / Istanza `NB-BANDERA\SQL2019` / Database `DBTMV`  
**Gestionale:** Gamma Enterprise (TeamSystem)  
**MES Esterno:** OverOne (tracciato `TMV-MES-ODL-CSV` su tabella `IE25`)  

---

## 1. Mappa Concettuale delle Entità Coinvolte

```
                      +-----------------------------+
                      |      DO11_DOCTESTATA        |
                      |  DO11_NUMREG_CO99, GUID     |
                      +--------------+--------------+
                                     |
             +-----------------------+-----------------------+
             |                                               |
             v                                               v
+-------------------------+                     +-------------------------+
|   CO4H_STATIATTUALI     |                     |      DO30_DOCCORPO      |
| CO4H_IDSTATO_CO4C (10056)                     |  DO30_PROGRIGA (1..N)   |
| CO4H_IDFLUSSO_CO4B(10012)                     |  DO30_IDDISBA_PD95      |
+------------+------------+                     +------------+------------+
             |                                               |
             v (trigger TRG_..._UPD)                         +-----------------------------+
+-------------------------+                                  |                             |
|   CO4I_STATISTORICO     |                                  v                             v
| CO4I_IDSTATO_CO4C       |                     +-------------------------+   +-------------------------+
| (10056=DaEsp,10057=Esp) |                     |       PD48_CICLI        |   |   DO46_DOCCORORDDET     |
+-------------------------+                     |  PD48_IDDISBA_PD95      |   |  DO46_PROGRIGA (1..N)   |
                                                |  PD48_IDCICLO (PK Ident)|<--+  DO46_IDCICLO_PD48 (FK) |
                                                |  PD48_SEQFASE (10..40)  |   |  DO46_CODSEQFASE        |
                                                |  PD48_CODFORN_CG44(2682)|   |  DO46_INDSTATOORD       |
                                                |  PD48_CODREP_PD07(R300) |   |  DO46_QTA1CONSOLID      |
                                                +-------------------------+   |  DO46_GUID              |
                                                                              +------------+------------+
                                                                                           |
                                                                                           v
                                                                              +-------------------------+
                                                                              | RT15_OVERONE_AVANZAMENTI|
                                                                              | Avanzamenti MES reali   |
                                                                              +-------------------------+
```

---

## 2. Il Master Pattern di Produzione (7 Fasi)

Il ciclo corretto che ogni riga dell'ODL deve avere è definito sulla riga 1 (`DO46_PROGRIGA = 1`):

| SeqFase (`DO46_CODSEQFASE` / `PD48_SEQFASE`) | CodFase (`DO46_CODFASE` / `PD48_CODFASE_PD12`) | Descrizione Fase | Reparto | Fornitore / Conto Lavoro |
| :--- | :--- | :--- | :--- | :--- |
| **10** | `4031` | TAGLIO | R100 | Interno |
| **15** | `1480` | VERNICIATURA POLVERI / TRATTAMENTO | **R300** | **2682** (Conto Lavoro C34 = 1) |
| **16** | `4001` | CONTROLLO QUALITA' | R100 | Interno |
| **20** | `4011` | LAVORAZIONE MECCANICA | R200 | Interno |
| **30** | `4021` | PREMONTAGGIO | R200 | Interno |
| **35** | `4001` | COLLAUDO FINALE | R100 | Interno |
| **40** | `4021` | IMBALLO / SPEDIZIONE | R200 | Interno |

---

## 3. Descrizione degli Script Realizzati

### Script 1: `AdeguamentoCiclo_DO46_GEMINI.sql`
- **Scopo:** Allineare i cicli di produzione per tutte le righe dell'ODL senza distruggere i dati storici.
- **Parametri di Testata:**
  ```sql
  DECLARE @DITTA int = 1;
  DECLARE @NUMREG_CO99 char(12) = '202600184219';
  DECLARE @DryRun bit = 1; -- 1 = Simulazione protetta, 0 = Esecuzione reale
  ```
- **Fase A (PD48_CICLI):**
  - Elimina le sole fasi spurie non nel pattern.
  - Esegue l'UPDATE delle fasi esistenti (impostando fornitore `2682` e reparto `R300` su fase `1480`).
  - Esegue l'INSERT delle fasi mancanti su tutte le distinte base `DO30_IDDISBA_PD95` dell'ODL con nuovi `PD48_IDCICLO` e `PD48_GUID`.
- **Fase B (DO46_DOCCORORDDET - Smart UPSERT):**
  - **Fasi vergini non nel pattern:** eliminate.
  - **Fasi con avanzamenti (`DO46_INDSTATOORD > 1`, `DO46_QTA1CONSOLID > 0` o record in `RT15`):** PROTETTE da cancellazione; subiscono solo l'UPDATE del puntatore `DO46_IDCICLO_PD48 = P.PD48_IDCICLO`.
  - **Fasi mancanti:** inserite ex-novo con quantità lette da `DO30_QTA1`.

### Script 2: `ImpostaStato_DaEsportare_ODL_GEMINI.sql`
- **Scopo:** Sbloccare il vincolo della vista `VPMES_ODLExport` e reimpostare l'ODL nello stato `10056` ("Da esportare").
- **Parametri di Testata:**
  ```sql
  DECLARE @DITTA int = 1;
  DECLARE @NUMREG_CO99 char(12) = '202600184219';
  DECLARE @DryRun bit = 1;
  ```
- **Operazioni:**
  1. Elimina da `CO4I_STATISTORICO` i record con stato `10057` per il `DO11_GUID`.
  2. Aggiorna `CO4H_STATIATTUALI` a `10056` con `CO4H_DATAVALIDITA = GETDATE()`.
  3. Il trigger `TRG_INSERTSTORICO_CO4H_UPD` registra automaticamente il passaggio nello storico.
  4. Verifica che `VPMES_ODLExport` restituisca tutte le 798 righe attese.

---

## 4. Trappole Tecniche e Regole Fondamentali da Ricordare

### Trappola 1: La cancellazione distruttiva di `DO46` è letale
- Se un ODL è già stato parzialmente lavorato sul MES, in `RT15_OVERONE_AVANZAMENTI` ci sono record legati a `DO46_NUMREG_CO99`, `DO46_PROGRIGA` e `DO46_CODSEQFASE`.
- In `DO46`, `DO46_INDSTATOORD = 2` e `DO46_QTA1CONSOLID > 0` indicano avanzamenti già recepiti.
- Fare una `DELETE` indiscriminata distrugge i `DO46_GUID` originali e le quantità consolidate, scollegando il MES dalla produzione reale.
- **Regola:** Usare SEMPRE lo Smart UPSERT con protezione degli avanzamenti.

### Trappola 2: Il vincolo `INNER JOIN PD48_CICLI` in `VPMES_ODLExport`
- La vista MES esegue `INNER JOIN PD48_CICLI ON PD48_IDCICLO = DO46_IDCICLO_PD48`.
- Se `DO46_IDCICLO_PD48` è `NULL` o se la fase non esiste in `PD48_CICLI` per quella specifica distinta `DO30_IDDISBA_PD95`, la fase **NON viene esportata**.
- Inoltre, il flag conto lavoro nel MES (campo 34) è calcolato come `if [PD48_CODFORN_CG44] <> 0 then 1 else 0 end`. Se la fase 1480 non ha fornitore in `PD48_CICLI`, il MES non la riconosce come conto lavoro.

### Trappola 3: Il vincolo `AND CO4I_ESPORTATO.CO4I_GUID IS NULL` in `VPMES_ODLExport`
- La vista verifica:
  ```sql
  LEFT JOIN (SELECT CO4I_GUID FROM CO4I_STATISTORICO WHERE CO4I_IDFLUSSO_CO4B = 10012 AND CO4I_IDSTATO_CO4C = 10057) AS CO4I_ESPORTATO
  ON DO11_GUID = CO4I_ESPORTATO.CO4I_GUID
  WHERE ... AND CO4I_ESPORTATO.CO4I_GUID IS NULL
  ```
- **Conseguenza:** Cambiare semplicemente lo stato attuale in `CO4H_STATIATTUALI` a `10056` NON fa riesportare l'ODL! Se la riga `10057` rimane in `CO4I_STATISTORICO`, la subquery scarta l'ordine. Va rimossa la riga `10057` da `CO4I_STATISTORICO`.

### Trappola 4: Sintassi `RAISERROR` in T-SQL
- In SQL Server, `RAISERROR` non supporta espressioni o funzioni nei parametri di sostituzione (es. `CAST(@DITTA AS INT)` genera `Msg 102 near 'CAST'`).
- Inoltre non supporta il tipo `decimal` (genera `Msg 2748`).
- **Regola:** Dichiarare `@DITTA int` e passare direttamente `@DITTA` senza `CAST`.

### Trappola 5: `Warning: Null value is eliminated by an aggregate or other SET operation`
- Non è un errore, ma un avviso informativo ANSI SQL (Warning 8153) dovuto al fatto che `VPMES_ODLExport` esegue funzioni `MAX(...)` su campi opzionali/annullabili (`DO35_ALFPERS10`, `MG65_CODBARCODE`, ecc.). Conferma che la vista sta aggregando correttamente i dati.

---

## 5. Procedura Operativa per Riutilizzo su Nuovi ODL

Se in futuro si presentasse la necessità di allineare un nuovo ODL (ad esempio se rigenerato ex-novo da Ordine Cliente):

1. **Allineamento Cicli:**
   - Aprire `AdeguamentoCiclo_DO46_GEMINI.sql`.
   - Modificare `@NUMREG_CO99 = '<NuovoNumReg>'`.
   - Eseguire prima con `@DryRun = 1` per verificare i 5 report diagnostici.
   - Modificare `@DryRun = 0` ed eseguire per applicare le modifiche.
2. **Sblocco Esportazione:**
   - Aprire `ImpostaStato_DaEsportare_ODL_GEMINI.sql`.
   - Modificare `@NUMREG_CO99 = '<NuovoNumReg>'`.
   - Eseguire prima con `@DryRun = 1` e poi con `@DryRun = 0`.
   - Verificare che il report finale confermi la visibilità di tutte le righe su `VPMES_ODLExport`.

