# Documento Tecnico e Funzionale: Analisi, Architettura e Reingegnerizzazione dell'Insieme ImpExp TMV_AGG_DESCR_ART

**Autore:** SOLVERIS - Bandera Marco  
**Ambiente Database:** Microsoft SQL Server 2017 (MSSQL 14.0.2120.1) - Database `DBTMV`  
**Oggetto Target:** Insieme Batch ImpExp `TMV_AGG_DESCR_ART` (Tracciati `TMV_AGG_DESART1`, `TMV_AGG_DESART2`, `TMV_AGG_DESART3`)  
**Directory di Progetto:** `@[DESCRIZIONI ARTICOLI]`  
**Data di Revisione:** 23/09/2026  

---

## SOMMARIO ESECUTIVO

Il presente documento descrive in modo organico, esaustivo e dettagliato l'architettura tecnica e le logiche applicative dell'Insieme di Import/Export **`TMV_AGG_DESCR_ART`**, attivo all'interno dell'ERP **TeamSystem Gamma Enterprise** per la gestione della produzione metalmeccanica di TMV.

L'Insieme batch governa il ciclo di vita anagrafico e descrittivo di tutti gli articoli generati o variati tramite il **Configuratore Commerciale** (`CM15_CONFGCOMM`), garantendo:
1. L'estrazione strettamente incrementale (delta) degli articoli inseriti o modificati a partire dai registri di tracciamento anagrafico (`MO13_LOGARTICOLI`) rispetto all'ultimo watermark temporale memorizzato (`RT14_VARIABILI_READYTEC`).
2. La generazione e composizione algoritmica automatica delle descrizioni tecniche standard (lingua italiana `''`) e internazionali (lingua estera `'LNG'`) in `MG87_ARTDESC`, mediante la funzione scalare `dbo.SPRT_TMV_DESCRIZIONE`, con troncamento protetto a salvaguardia delle parole e applicazione di post-correttivi per dadi e filettature.
3. Il completamento delle caratteristiche operative di base: ereditarietà della matrice varianti (`MG6B_GESVARART`) dall'articolo modello omologo, impostazione dei vincoli sulla variante 4 (`A3`) per barre tonde a disegno (`TONDI-DXXX`) o standard, e creazione dei dati dimensionali/imballo nella tabella di confezionamento `MG68_CONFART` propedeutici al modulo di Packing List (`PKL`).

---

## PARTE 1: LOGICHE DI BUSINESS E CONTESTO AZIENDALE

### 1.1 Il Contesto Produttivo TMV: Fabbricazione su Commessa e Nomenclatura Tecnica
TMV produce e commercializza componenti metallici ad altissima precisione (tiranti, prigionieri interamente o parzialmente filettati, dadi esagonali e pesanti, barre filettate, linguette per trasmissioni meccaniche e viteria speciale) destinati principalmente all'industria petrolchimica, valvole offshore, centrali termoelettriche e gasdotti.

In questo settore, un articolo non è un prodotto statico da scaffale, ma una combinazione combinatoria di parametri fisici, metallurgici e dimensionali:
- **Tipologia Costruttiva:** Tirante (`TDP`, `TDR`, `TDL`), Barra (`TDF`), Dado Metrico/Pollice (`DADI`), Vite a cava esagonale, Linguetta (`KB-`), ecc.
- **Grado Materiale / Lega:** Acciai legati da bonifica (ASTM A193 B7, ASTM A320 L7/L7M), acciai inossidabili (B8, B8M, 316, Duplex, Superduplex), leghe di nichel (Inconel, Monel).
- **Dimensioni Filettatura:** Diametro nominale (metrico M o frazionario in pollici P) e relativo Passo (passo grosso, passo fine UNF/UNC, o passi speciali a disegno).
- **Varianti Opzionali Operative:**
  - *Opzione A0:* Lunghezza utile (es. `L100-`, `L250-`).
  - *Opzione A1 / A2:* Trattamenti superficiali e rivestimenti protettivi anticorrosione (es. Zincatura elettrolitica, Zincatura a caldo `HDG`, Alluminatura `ALU`, Bruniti `BRU`, Xylan/PTFE, Dacromet).
  - *Opzione A3:* Diametro tornito speciale su barre e tondi (`TONDI-DXXX`) o dimensione caratteristica.
  - *Opzione A4:* Altezza o spessore speciale.

### 1.2 La Necessità di Standardizzazione Automatica delle Descrizioni
Data la vastità delle combinazioni (milioni di codici potenziali), l'ufficio tecnico e commerciale di TMV opera attraverso il modulo **Configuratore Commerciale di Gamma Enterprise**.  
Tuttavia, l'operatore che compone l'articolo non può redigere manualmente la descrizione tecnica:
- Un errore di battitura su un diametro, un passo o una classe di tolleranza causerebbe gravissimi contenziosi legali, non conformità di collaudo o il blocco dei carichi all'estero.
- I clienti multinazionali richiedono che su Documenti di Trasporto (DDT), Fatture e Certificati 3.1 compaiano contemporaneamente la **descrizione tecnica in lingua italiana** e la **descrizione tecnica in lingua inglese (lingua 'LNG')**, rigorosamente conformi agli standard internazionali (ASTM, ASME B18.2.1, ISO, DIN).
- I campi anagrafici di Gamma Enterprise hanno vincoli stringenti: il campo primario `MG87_DESCART` è vincolato a un massimo di **70 caratteri**. Una descrizione tecnica di un tirante supera frequentemente i 120-150 caratteri. Se la stringa venisse troncata banalmente al 70° carattere, una parola tecnica vitale (es. `HDG`, `Tolerance after coating`, `42CrMo4`) verrebbe spezzata a metà (es. `TOLERANCE AFTER COA`), generando un testo incomprensibile e poco professionale.

### 1.3 Il Ciclo della Pipeline Batch Schedulata: Insieme `TMV_AGG_DESCR_ART`
L'insieme batch `TMV_AGG_DESCR_ART` viene eseguito in background dallo **Schedulatore di Sistema Gamma Enterprise** (utente `TeamSa`) con cadenza regolare (ogni due ore nei giorni lavorativi).

La pipeline è rigorosamente sequenziale e comprende tre passaggi logici:

```
[ Inizio Batch TMV_AGG_DESCR_ART ]
                |
                v
+-------------------------------------------------------------+
| PASSAGGIO 1: TMV_AGG_DESART1                                |
| 1. Pre-comando: DELETE FROM RT12_AGG_DESCR_ART             |
| 2. Lettura Vista VPRT_TMV_AGG_DESCR_ART (Delta Log MO13)    |
| 3. Caricamento righe individuate in RT12_AGG_DESCR_ART      |
| 4. Post-comando: UPDATE RT14 con GETDATE()                  |
+-------------------------------------------------------------+
                |
                v
+-------------------------------------------------------------+
| PASSAGGIO 2: TMV_AGG_DESART2                                |
| 1. Pre-comando: EXEC SPRT_TMV_AGG_DESCR_ART                 |
|    - Elimina articoli non presenti in CM15 da RT12          |
|    - Calcola descrizione SHORT (italiano) -> MG87 ('')      |
|    - Calcola descrizione LONG (inglese) -> MG87 ('LNG')     |
|    - Tronca a max 70 car. su ultimo spazio prima del car.73 |
|    - Salva eccedenza in MG87_DESCARTEST                     |
|    - Post-correzione DADI: "Min." -> "Mag."                 |
|    - Post-correzione Filettature: 14UNF -> 12UNF            |
+-------------------------------------------------------------+
                |
                v
+-------------------------------------------------------------+
| PASSAGGIO 3: TMV_AGG_DESART3                                |
| 1. Pre-comando: EXEC SPRT_TMV_AGG_ARTICOLI_VARIE            |
|    - Invocazione SPRT_TMV_ATTIVA_VAR (Clonazione Varianti)  |
|    - Impostazione Variante A3: TONDI-DXXX per barre con 'D' |
|    - Impostazione Variante A3: STANDARD per altri articoli  |
|    - Inizializzazione Confezione Default 'CD' in MG68       |
+-------------------------------------------------------------+
                |
                v
[ Fine Batch - Articoli Pienamente Operativi ]
```

---

## PARTE 2: SCELTE TECNICHE, ARCHITETTURA DATI E DIAGNOSTICA

### 2.1 Mappa delle Tabelle Coinvolte
L'ecosistema dell'Insieme `TMV_AGG_DESCR_ART` poggia sull'interazione coordinata tra tabelle standard di Gamma Enterprise e tabelle personalizzate (`RT...`):

| Tabella | Origine | Ruolo e Funzione Architetturale |
| :--- | :--- | :--- |
| **`RT12_AGG_DESCR_ART`** | Personalizzata SOLVERIS | Tabella di frontiera e semaforo di elaborazione. Contiene la lista degli articoli `(DITTA, CODART, OPZIONE)` selezionati dal passo 1 e consumati dai passi 2 e 3. |
| **`RT14_VARIABILI_READYTEC`** | Personalizzata SOLVERIS | Memorizza parametri globali. La riga con chiave `SPRT_TMV_AGG_DESCR_ART` conserva il timestamp dell'ultimo ciclo batch completato. |
| **`MO13_LOGARTICOLI`** | Standard Gamma | Registro di audit trail di Gamma Enterprise. I trigger applicativi vi registrano gli eventi di inserimento/modifica (`INDTIPOOP = 0`) sui campi `MG66_DTCREAZ` e `MG87_DESCART`. |
| **`MG66_ANAGRART`** | Standard Gamma | Anagrafica articoli principale di Gamma Enterprise. |
| **`MG87_ARTDESC`** | Standard Gamma | Tabella delle descrizioni per lingua. Memorizza `MG87_DESCART` (70 car.), `MG87_DESCARTEST` (1672 car.) per la lingua vuota `''` e la lingua internazionale `'LNG'`. |
| **`CM15_CONFGCOMM`** | Standard Gamma | Testata delle configurazioni commerciali. Associa il codice articolo anagrafico all'articolo modello teorico (`CM15_CODARTMOD_MG66`). |
| **`CM17_CATCONFIG`** | Standard Gamma | Valori assegnati alle categorie commerciali per la specifica configurazione (Cat. 1=Tipologia, 2=Minorazione, 3=Materiale, 4=Diametro, 5=Passo). |
| **`CM01_CATEGORIECOMM`** | Standard Gamma | Catalogo delle categorie del configuratore commerciale. |
| **`CM02_VALORICATCOMM`** | Standard Gamma | Valori ammissibili per ciascuna categoria commerciale con relative descrizioni tecniche di base. |
| **`MG6B_GESVARART`** | Standard Gamma | Matrice delle varianti abilitate per ciascun articolo: definisce se la variante è attiva, il raggruppamento ammesso, l'obbligatorietà e i valori di default. |
| **`MG5E_OPZIONI`** | Standard Gamma | Anagrafica dei valori delle opzioni varianti (es. lunghezze `L...`, codici rivestimento `HDG`, `ALU`, ecc.). |
| **`MG68_CONFART`** | Standard Gamma | Confezioni e pesi dell'articolo: contiene il codice confezione (es. `'CD'`), unità di misura di peso (`KG`), dimensioni (`MM`) e volume (`CM3`). |
| **`RT03_DESCRALTER`** | Personalizzata SOLVERIS | Tabella di decodifica per descrizioni alternative in lingua inglese di tipologie, materiali e minorazioni in base al sistema Metrico o Pollici. |
| **`RT04_DESCRALTER_OPZ`** | Personalizzata SOLVERIS | Tabella di traduzione descrittiva delle varianti di trattamento (A1, A2) in lingua inglese. |
| **`RT05_DESCR_DIAM_PASSO`** | Personalizzata SOLVERIS | Tabella per la formattazione combinata e normalizzata di diametro e passo nominale o speciale. |

---

### 2.2 Analisi Dettagliata dei Componenti SQL e dei Tracciati

#### 2.2.1 Tracciato `TMV_AGG_DESART1` e Vista `dbo.VPRT_TMV_AGG_DESCR_ART`
- **Sorgente:** Vista `dbo.VPRT_TMV_AGG_DESCR_ART`.
- **Destinazione:** Tabella `dbo.RT12_AGG_DESCR_ART`.
- **Comando Pre:** `DELETE FROM RT12_AGG_DESCR_ART`.
- **Comando Post:** `UPDATE RT14_VARIABILI_READYTEC SET RT14_DATE_VALUE = GETDATE() WHERE RT14_VARNAME = 'SPRT_TMV_AGG_DESCR_ART'`.

**Logica di Estrazione:**
La vista effettua un'interrogazione incrementale su `MG87_ARTDESC` incrociata con `MG66_ANAGRART` e `CM15_CONFGCOMM`.  
Il filtro incrementale è garantito dal matching con la tabella `MO13_LOGARTICOLI`:
```sql
SELECT MO13_DITTA_CG18, MO13_CODART_MG66, ISNULL(MO13_OPZIONE_MG5E, '') AS MO13_OPZIONE_MG5E, MAX(MO13_DATALOG) AS MO13_DATALOG
FROM dbo.MO13_LOGARTICOLI WITH (NOLOCK)
WHERE (MO13_FIELDNAME = 'MG87_DESCART' OR MO13_FIELDNAME = 'MG66_DTCREAZ') 
  AND (MO13_INDTIPOOP = 0)
GROUP BY MO13_DITTA_CG18, MO13_CODART_MG66, ISNULL(MO13_OPZIONE_MG5E, '')
HAVING MAX(MO13_DATALOG) >= ULTIMA_DATA_EXEC.RT14_DATE_VALUE
```
Inoltre, il secondo ramo di `UNION` intercetta gli articoli la cui descrizione contiene `'ARTICOLO MODELLO'` ma che non compaiono come modelli in `VPRT_ARTICOLI_MODELLO`, bonificandoli tempestivamente.

#### 2.2.2 Tracciato `TMV_AGG_DESART2` e Stored Procedure `dbo.SPRT_TMV_AGG_DESCR_ART`
- **Comando Pre:** `EXEC SPRT_TMV_AGG_DESCR_ART`.
- **Tabella di appoggio:** `CG18_ANADITTABASE` (fittizia).

**Algoritmo di Composizione e Troncamento Intelligente:**
La procedura richiama la funzione scalare `dbo.SPRT_TMV_DESCRIZIONE` richiedendo prima la modalità `'SHORT'` e successivamente la modalità `'LONG'`.  
Poiché `MG87_DESCART` accetta fino a 70 caratteri, la procedura adotta la seguente formula matematica:
$$\text{PosizioneSpazio} = 73 - \text{CHARINDEX}(' ', \text{REVERSE}(\text{LEFT}(\text{Stringa}, 73)), 0)$$
- `LEFT(Stringa, 73)` isola i primi 73 caratteri.
- `REVERSE(...)` inverte la sottostringa per individuare il primo spazio dalla fine.
- `CHARINDEX(' ', ...)` calcola l'indice dello spazio a ritroso.
- Sottraendo questo valore da 73, si ottiene la posizione esatta dell'ultimo spazio naturale, garantendo che nessuna parola tecnica venga spezzata.
- La porzione eccedente viene trimmata e salvata su `MG87_DESCARTEST`.

**Post-Correttivi Specifici di Business:**
1. *Dadi Metrici e in Pollici:* Sostituzione sistematica di `'Min.'` con `'Mag.'` in virtù del fatto che nei dadi la tolleranza di filettatura è una maggiorazione per ospitare il rivestimento protettivo e consentire l'avvitamento sul perno.
2. *Famiglia Tiranti P1-- con suffisso F- o FS:* Sostituzione di `'14UNF'` con `'12UNF'`, necessaria per correggere una discrepanza nei passi filettatura generati dall'algoritmo combinatorio delle categorie commerciali.

#### 2.2.3 Tracciato `TMV_AGG_DESART3` e Stored Procedure `dbo.SPRT_TMV_AGG_ARTICOLI_VARIE`
- **Comando Pre:** `EXEC SPRT_TMV_AGG_ARTICOLI_VARIE`.
- **Tabella di appoggio:** `CG18_ANADITTABASE` (fittizia).

Questa procedura esegue tre attività essenziali:
1. Chiama `dbo.SPRT_TMV_ATTIVA_VAR` per ereditare la matrice delle varianti.
2. Configura la variante 4 (`A3`):
   - Per le barre tonde (`TDP`, `TDR`, `TDL`, `TDF` con il 9° carattere uguale a `'D'`), assegna il raggruppamento `'TONDI-DXXX'`, rendendola obbligatoria (`MG6B_INDOBBLIG = 1`) con default `'000'`.
   - Per gli altri articoli, imposta il raggruppamento `'STANDARD'` disabilitando l'obbligatorietà.
3. Inizializza la tabella `MG68_CONFART` inserendo il record per la confezione di default `'CD'` (`PZCONF = 0`, pesi a 0, unità di misura `'KG'`, `'MM'`, `'CM3'`), sbloccando la movimentazione di magazzino e il packing list.

---

### 2.3 Rilevamento Bug Critico su `dbo.SPRT_TMV_ATTIVA_VAR` e Risoluzione

> [!CAUTION]
> **ANOMALIA BLOCCANTE RESIDENTE IN PRODUZIONE:**  
> Nella revisione del 06/12/2023 di `dbo.SPRT_TMV_ATTIVA_VAR` (curata da Bandera Marco per sostituire la vecchia tabella `RT02` con l'estrazione diretta dall'articolo modello in `MG6B`), è stata commentata la precedente dichiarazione del cursore (righe 45-89).  
> Nella nuova sezione (riga 99) è stata inserita l'istruzione `SELECT`, ma **è stata omessa la dichiarazione del cursore**:
> ```sql
> -- MANCA: DECLARE MyCursor CURSOR LOCAL FAST_FORWARD FOR
> SELECT MG6B_GESVARART.MG6B_DITTA_CG18, ...
> ...
> OPEN MyCursor; -- FALLIMENTO RUNTIME: Msg 16916 (Cursore non esistente)
> ```
> Sebbene SQL Server compili la procedura grazie alla risoluzione differita dei nomi, ad ogni esecuzione reale l'istruzione `OPEN MyCursor` fallisce con errore fatale `16916`, impedendo la clonazione delle varianti dall'articolo modello!

**Soluzioni Rilasciate nel Progetto:**
1. Nel file [SPRT_TMV_ATTIVA_VAR.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPRT_TMV_ATTIVA_VAR.sql) è stata formalmente ripristinata la dichiarazione del cursore `DECLARE MyCursor CURSOR LOCAL FAST_FORWARD FOR`, garantendo il riallineamento della procedura standard esistente.
2. Nel file [SPSO_TMV_ATTIVA_VAR_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPSO_TMV_ATTIVA_VAR_GEMINI.sql) l'intero cursore è stato **completamente eliminato** e sostituito con una singola istruzione `UPDATE` set-based con JOIN diretta, dotata di supporto nativo alla modalità **Dry-Run** (`@DryRun = 1`) e protezione transazionale `TRY...CATCH`.

---

## PARTE 3: SPECIFICHE TRACCIATI, MAPPATURA CAMPI E AUDIT TRAIL

### 3.1 Dettaglio Tracciati ImpExp (Tabelle `IE25`, `IE26`, `IE27`)

#### 3.1.1 Tracciato `TMV_AGG_DESART1`
- **Struttura:** 99 (Generica).
- **Tabella Sorgente (`IE25_TABELLAFILE`):** `VPRT_TMV_AGG_DESCR_ART` (oppure `VPSO_TMV_AGG_DESCR_ART_GEMINI`).
- **Tabella Destinazione (`IE25_TABELLA`):** `RT12_AGG_DESCR_ART`.
- **Comando Pre (`IE25_COMANDOIMP`):** `DELETE FROM RT12_AGG_DESCR_ART` (Flag `IE25_INDCOMPRE = 2`).
- **Comando Post (`IE25_COMANDOEXP`):** `UPDATE RT14_VARIABILI_READYTEC SET RT14_DATE_VALUE = GETDATE() WHERE RT14_VARNAME = 'SPRT_TMV_AGG_DESCR_ART'` (Flag `IE25_INDCOMPOST = 2`).

**Mappatura Campi (`IE27_TRACCIATICAMPI`):**
| Prog | Campo Destinazione (`IE27_NOMECAMPO`) | Colonna Sorgente (`IE27_CAMPOASSOCIATO`) | Tipo |
| :---: | :--- | :--- | :--- |
| 1 | `RT12_DITTA_CG18` | `MG87_DITTA_CG18` | Decimale (5,0) |
| 2 | `RT12_CODART_MG66` | `MG87_CODART_MG66` | Char (25) |
| 3 | `RT12_OPZIONE_MG5E` | `MG87_OPZIONE_MG5E` | Char (20) |

#### 3.1.2 Tracciato `TMV_AGG_DESART2`
- **Struttura:** 99.
- **Tabella Sorgente / Destinazione:** `CG18_ANADITTABASE` (Tabella fittizia per trigger batch).
- **Comando Pre (`IE25_COMANDOIMP`):** `EXEC SPRT_TMV_AGG_DESCR_ART` (o `EXEC SPSO_TMV_AGG_DESCR_ART_GEMINI @DryRun = 0`).
- **Comando Post (`IE25_COMANDOEXP`):** `NULL`.
- **Mappatura Campi:** `CG18_DITTA` $\rightarrow$ `CG18_DITTA` (Record fittizio).

#### 3.1.3 Tracciato `TMV_AGG_DESART3`
- **Struttura:** 99.
- **Tabella Sorgente / Destinazione:** `CG18_ANADITTABASE`.
- **Comando Pre (`IE25_COMANDOIMP`):** `EXEC SPRT_TMV_AGG_ARTICOLI_VARIE` (o `EXEC SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI @DryRun = 0`).
- **Comando Post (`IE25_COMANDOEXP`):** `NULL`.
- **Mappatura Campi:** `CG18_DITTA` $\rightarrow$ `CG18_DITTA` (Record fittizio).

---

### 3.2 Audit Trail e Monitoraggio Esecuzioni (`IE4C_LOGIMPEXP` / `IE4D_RECORDS`)
L'Insieme batch viene monitorato consultando le tabelle di audit di Gamma Enterprise:
- `IE4C_LOGIMPEXP`: Registra ogni singola esecuzione con `IE4C_IDIMPEXP`, data/ora (`IE4C_MOMENTO`), utente (`TeamSa`) e flag di schedulazione (`IE4C_FLGSCHEDULATO = 1`).
- `IE4D_RECORDS`: Registra il conteggio dei record elaborati (`IE4D_RISULTATO = 1` per completamento regolare, `IE4D_NOTE` riporta il conteggio dei record inseriti o tralasciati).

Query diagnostica rapida:
```sql
SELECT TOP 10 
    C.IE4C_IDIMPEXP, C.IE4C_TRACCIATO_IE25, C.IE4C_MOMENTO, C.IE4C_UTENTE,
    D.IE4D_RISULTATO, D.IE4D_NOTE
FROM dbo.IE4C_LOGIMPEXP AS C WITH (NOLOCK)
LEFT JOIN dbo.IE4D_RECORDS AS D WITH (NOLOCK) ON C.IE4C_IDIMPEXP = D.IE4D_ID_IE4C
WHERE C.IE4C_INSIEME_IE33 = 'TMV_AGG_DESCR_ART'
ORDER BY C.IE4C_MOMENTO DESC;
```

---

## INDICE DEI FILE RILASCIATI NELLA CARTELLA `@[DESCRIZIONI ARTICOLI]`

Tutti i componenti SQL e documentali sono stati generati e depositati nella cartella di lavoro:

1. [DOC_TECNICO_INSIEME_TMV_AGG_DESCR_ART_GEMINI.md](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/DOC_TECNICO_INSIEME_TMV_AGG_DESCR_ART_GEMINI.md) - Presente documento tecnico.
2. [RT12_AGG_DESCR_ART.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/RT12_AGG_DESCR_ART.sql) - DDL e struttura tabella di frontiera con Cartiglio Narrativo.
3. [RT14_VARIABILI_READYTEC.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/RT14_VARIABILI_READYTEC.sql) - DDL e seeding della variabile di watermark con Cartiglio Narrativo.
4. [VPRT_ARTICOLI_MODELLO.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/VPRT_ARTICOLI_MODELLO.sql) - Vista di isolamento codici modello con Cartiglio Narrativo.
5. [VPRT_TMV_AGG_DESCR_ART.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/VPRT_TMV_AGG_DESCR_ART.sql) - Vista sorgente originale revisionata con Cartiglio Narrativo e commenti prolissi.
6. [VPSO_TMV_AGG_DESCR_ART_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/VPSO_TMV_AGG_DESCR_ART_GEMINI.sql) - Vista standardizzata GEMINI ad alte prestazioni con CTE e `WITH (NOLOCK)`.
7. [SPRT_TMV_DESCRIZIONE.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPRT_TMV_DESCRIZIONE.sql) - Funzione scalare originale con documentazione di tutti i rami di configurazione.
8. [SFSO_TMV_DESCRIZIONE_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SFSO_TMV_DESCRIZIONE_GEMINI.sql) - Funzione scalare conforme agli standard SOLVERIS GEMINI (`SFSO_..._GEMINI`).
9. [SPRT_TMV_ATTIVA_VAR.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPRT_TMV_ATTIVA_VAR.sql) - Stored Procedure originale corretta con il ripristino del cursore `MyCursor`.
10. [SPSO_TMV_ATTIVA_VAR_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPSO_TMV_ATTIVA_VAR_GEMINI.sql) - Nuova Stored Procedure GEMINI set-based ad altissima velocità con supporto Dry-Run.
11. [SPRT_TMV_AGG_ARTICOLI_VARIE.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPRT_TMV_AGG_ARTICOLI_VARIE.sql) - Stored Procedure originale di completamento varianti e logistica con Cartiglio Narrativo.
12. [SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPSO_TMV_AGG_ARTICOLI_VARIE_GEMINI.sql) - Stored Procedure GEMINI con modalità Dry-Run e report diagnostico su A3 e `MG68_CONFART`.
13. [SPRT_TMV_AGG_DESCR_ART.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPRT_TMV_AGG_DESCR_ART.sql) - Stored Procedure originale di aggiornamento descrizioni con Cartiglio Narrativo.
14. [SPSO_TMV_AGG_DESCR_ART_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPSO_TMV_AGG_DESCR_ART_GEMINI.sql) - Nuova Stored Procedure GEMINI con modalità Dry-Run verbosa, gestione transazionale protetta e reporting comparativo.
15. [CONFIG_IMPEXP_TMV_AGG_DESCR_ART_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/CONFIG_IMPEXP_TMV_AGG_DESCR_ART_GEMINI.sql) - Script di audit, verifica metadati e allineamento guidato dei tracciati ImpExp.
16. [RT05_POPOLAMENTO_METRICI_MANCANTI_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/RT05_POPOLAMENTO_METRICI_MANCANTI_GEMINI.sql) - Script DML transazionale per il popolamento e la normalizzazione delle combinazioni metriche mancanti in RT05 (risoluzione anomalia diametro per TDP04B7-M1254- e oltre 3.300 articoli).
17. [SO_DIFF_DESCRIZIONI_TD_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SO_DIFF_DESCRIZIONI_TD_GEMINI.sql) - Tabella di staging e audit per il tracciamento delle discrepanze descrittive degli articoli TD.
18. [SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPSO_TMV_CHECK_DIFF_DESCRIZIONI_TD_GEMINI.sql) - Stored Procedure diagnostica per la scansione massiva e la classificazione causale di tutte le discrepanze TD.
19. [SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI.sql](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/SPSO_TMV_ADEGUA_DESCRIZIONI_TD_GEMINI.sql) - Stored Procedure di bonifica massiva e adeguamento descrizioni con supporto Dry-Run.
20. [TABELLA_CONTROLLO_UT_RT05_GEMINI.md](file:///c:/Users/marco/OneDrive/Documenti/READYTEC/TMV/VSCODE%20-%20TMV/DESCRIZIONI%20ARTICOLI/TABELLA_CONTROLLO_UT_RT05_GEMINI.md) - Scheda e tabellina di verifica umana per l'Ufficio Tecnico sui parametri diametro/passo.

---

> [!NOTE]
> ### Appendice Sorgenti (Parte 3)
> Conformemente al punto 5 delle regole di sviluppo SOLVERIS (`GEMINI.md`), tutti i codici sorgente completi sono stati archiviati nei singoli file script T-SQL collegati sopra. Su richiesta dell'utente, l'intero corpus dei codici può essere integrato in un documento cumulativo unico.

