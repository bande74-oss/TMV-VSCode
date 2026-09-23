# VERBALE TECNICO DI VERIFICA E TRACCIABILITÀ DATI

```text
========================================================================================
OGGETTO:             Verbale di Analisi Tracciabilità Documentale e Risoluzione Colata
DOCUMENTO SORGENTE:  DC-PREDDT N. 5289 del 31/08/2026 (NumReg: 202600177517)
COMMITTENTE:         EMERSON PROCESS MANAGEMENT PVT. LTD. (Codice Cli/For: 3822)
AMBIENTE / DATABASE: MSSQL 14.0.2120.1 (SQL Server 2017) / [DBTMV]
AUTORE:              SOLVERIS - Bandera Marco
DATA REDAZIONE:      2026-09-23 10:15
STATO:               BOZZA PER REVISIONE SUCCESSIVA (IN ATTESA DI ELEMENTI UTENTE)
========================================================================================
```

---

## 1. Obiettivo dell'Indagine

Il presente verbale formalizza l'attività di indagine relazionale e di quadratura dati eseguita sul database aziendale `[DBTMV]`, a seguito dell'analisi della formula Crystal Report:

```crystal
iif(trim({VPRT_ODL_REPORT.COLATA_TIMBRARE}) <> '', trim({VPRT_ODL_REPORT.COLATA_TIMBRARE}), {VPRT_ODL_REPORT.COLATA})
```

L'indagine ha preso come campione d'analisi il documento di preparazione spedizione **`DC-PREDDT` N. 5289 del 31/08/2026** (`DO11_DITTA_CG18 = 1`, `DO11_NUMREG_CO99 = '202600177517'`), isolando le sole righe aventi **quantità $\ge 10$**.

Per ciascuna di esse è stata risalita a ritroso l'intera catena documentale:
$$\text{Pre-DDT} \longrightarrow \text{Ordine Cliente (OC)} \longrightarrow \text{Ordine di Lavoro (ODL)} \longrightarrow \text{Scarico Produzione (INT-SCARPROD)} \longrightarrow \text{Lotti (DO52 / MG4G)}$$

---

## 2. Sintesi delle Evidenze e Risoluzione della Formula

1. **Campo `COLATA_TIMBRARE` su Riga Ordine Cliente (`DO36_DOCCORPOEST.DO36_ALFST1`):**
   - Tutte le **6 righe** con quantità $\ge 10$ presentano il campo `DO36_ALFST1` **`NULL` / vuoto**.
   - **Significato di business:** Nessuna riga d'ordine commerciale ha subito una forzatura o indicazione manuale preventiva di una colata specifica da parte dell'ufficio commerciale / vendite.
2. **Comportamento della Formula Crystal Report:**
   - Essendo `COLATA_TIMBRARE` non valorizzato, la formula ha operato il **fallback automatico** sul campo `COLATA`.
3. **Origine del Campo `COLATA` (`dbo.SPRT_LTT_FAKE`):**
   - La funzione scalare `[dbo].[SPRT_LTT_FAKE]`, interrogata con parametro `'COLATA'`, ha risalito tramite `DO33` il documento di scarico effettivo della produzione (`DO11_TIPODOC = 24`, `DO11_STIPODOC = 5`, documento `INT-SCARPROD`).
   - Il valore esposto nel report coincide al 100% con la descrizione del lotto (`MG4G.MG4G_DESCLOTTO`) registrata nella tabella dei lotti movimentati nello scarico (`DO52_DOCCORPOLOT`).

---

## 3. Tabella Estremi Dati Estratti (Raccordo Completo)

| # | Riga Pre-DDT | Articolo Finito | Q.tà | Ordine Cliente (OC) | Data OC | PO Emerson | Item PO | Colata OC (`DO36_ALFST1`) | ODL (`INT-ORDLAV`) | Data ODL | Id Disba | Scarico (`INT-SCARPROD`) | Data Scarico | Articolo Scaricato | Lotto Scaricato (`DO52_CODLOTTO`) | Colata / Descrizione Lotto (`MG4G_DESCLOTTO`) | Valore Finale Crystal Report |
| :-: | :-: | :--- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :--- | :--- | :--- | :--- |
| **1** | **2** (vis. 3) | `3ATW400370B78` | **10** | **1158** (r. 2) | 20/02/2026 | `VIB011106` | 2 | *(vuoto)* | **1587** (r. 2) | 24/02/2026 | 4178277 | **31810** (r. 1) | 25/06/2026 | `TDR--41ED75---` (var. 000) | `TDR2510/0004` | **`343029`** | **`343029`** |
| **2** | **7** (vis. 8) | `3KSA10270436` | **13** | **1158** (r. 19) | 20/02/2026 | `VIB011106` | 20 | *(vuoto)* | **1587** (r. 19) | 24/02/2026 | 4178294 | **40744** (r. 1) | 28/08/2026 | `KB_3KSA10270436` | `KB_2512/0010` | **`437861`** | **`437861`** |
| **3** | **29** (vis. 30) | `3KSA06170436` | **10** | **4002** (r. 2) | 06/07/2026 | `VIB011188` | 2 | *(vuoto)* | **5107** (r. 2) | 08/07/2026 | 5036724 | **40866** (r. 1) | 28/08/2026 | `KB_3KSA06170436` | `KB_26/25421` | **`437613`** | **`437613`** |
| **4** | **41** (vis. 42) | `3KSA10270B78` | **13** | **4345** (r. 3) | 22/07/2026 | `VIB011196` | 3 | *(vuoto)* | **5511** (r. 3) | 27/07/2026 | 5157313 | **40749** (r. 1) | 28/08/2026 | `KB_3KSA10270B78` | `KB_26/28350` | **`345056`** | **`345056`** |
| **5** | **44** (vis. 45) | `3KSA12270B78` | **10** | **4345** (r. 8) | 22/07/2026 | `VIB011196` | 8 | *(vuoto)* | **5511** (r. 8) | 27/07/2026 | 5157318 | **40303** (r. 1) | 26/08/2026 | `TDR--41ED45---` (var. 000) | `TDR2608/0008` | **`440198`** | **`440198`** |
| **6** | **69** (vis. 70) | `3KSA10270B78` | **19** | **4723** (r. 31) | 20/08/2026 | `VIB011216` | 31 | *(vuoto)* | **5938** (r. 28) | 21/08/2026 | 5349458 | **40769** (r. 1) | 28/08/2026 | `KB_3KSA10270B78` | `KB_26/28350` | **`345056`** | **`345056`** |

---

## 4. Note Tecniche sulle Tipologie di Materiale Scaricato

- **Barre Dirette a Peso/Metri (Righe 1 e 5):**
  L'ODL ha prelevato direttamente la barra commerciale trafilata (`TDR--41ED75---` e `TDR--41ED45---`), scaricando rispettivamente i lotti fornitore `TDR2510/0004` (Colata `343029`) e `TDR2608/0008` (Colata `440198`).
- **Componenti Gestiti a Kanban (Righe 2, 3, 4 e 6):**
  L'ODL ha prelevato semilavorati con codifica `KB_...`, scaricando lotti intermedi `KB_2512/0010`, `KB_26/25421` e `KB_26/28350` (con colate `437861`, `437613` e `345056`).
- **Lotto Condiviso:** Le righe 4 e 6 (pur appartenenti a due Ordini Cliente differenti, OC 4345 e OC 4723, e a due ODL distinti, 5511 e 5938) condividono lo stesso lotto componente `KB_26/28350` e di conseguenza la medesima colata `345056`.

---

## 5. Script SQL di Riferimento per Ulteriori Indagini

Lo script seguente è stato ottimizzato con le corrette condizioni relazionali (`DO33_PROGRIF = 1` e filtro specifico sui tipi documento) per impedire prodotti cartesiani o lock su tabelle transazionali:

```sql
USE [DBTMV]
GO

SET NOCOUNT ON;

DECLARE @NumRegPreDDT CHAR(12) = '202600177517';
DECLARE @QtaMinima     DECIMAL(14,3) = 10.0;

SELECT 
    PRE_C.DO30_PROGRIGA                     AS [PreDDT_ProgRiga],
    PRE_C.DO30_PROGVISUASTA                 AS [PreDDT_RigaVis],
    PRE_C.DO30_CODART_MG66                  AS [PreDDT_CodArticolo],
    PRE_C.DO30_DESCART                      AS [PreDDT_Descrizione],
    PRE_C.DO30_QTA1                         AS [PreDDT_Qta],
    
    OC_T.DO11_DOCUM_MG36                    AS [OC_TipoDoc],
    OC_T.DO11_NUMDOC                        AS [OC_NumDoc],
    CONVERT(VARCHAR(10), OC_T.DO11_DATADOC, 103) AS [OC_DataDoc],
    OC_DO12.DO12_NUMVSDOC                   AS [OC_PO_Emerson],
    ISNULL(TRIM(OC_DO35.DO35_ALFPERS10), '') AS [OC_Item_PO],
    OC_C.DO30_NUMREG_CO99                   AS [OC_NumReg],
    OC_C.DO30_PROGRIGA                      AS [OC_ProgRiga],
    ISNULL(OC_DO36.DO36_ALFST1, '')         AS [OC_Colata_Timbrare_DO36],
    
    ODL_T.DO11_NUMDOC                       AS [ODL_NumDoc],
    CONVERT(VARCHAR(10), ODL_T.DO11_DATADOC, 103) AS [ODL_DataDoc],
    ODL_C.DO30_IDDISBA_PD95                 AS [ODL_IdDisba],
    
    SCAR_T.DO11_NUMDOC                      AS [Scarico_NumDoc],
    CONVERT(VARCHAR(10), SCAR_T.DO11_DATADOC, 103) AS [Scarico_DataDoc],
    DO52.DO52_CODART_MG66                   AS [Articolo_Scaricato],
    DO52.DO52_CODLOTTO_MG4G                 AS [Codice_Lotto_Scaricato],
    MG4G.MG4G_DESCLOTTO                     AS [Colata_Lotto_Scaricato],
    DO52.DO52_QTA1                          AS [Qta_Scaricata],
    
    IIF(TRIM(ISNULL(OC_DO36.DO36_ALFST1, '')) <> '', 
        TRIM(OC_DO36.DO36_ALFST1), 
        ISNULL(TRIM([dbo].[SPRT_LTT_FAKE](ODL_C.DO30_IDDISBA_PD95, 'COLATA')), '')) AS [Formula_Crystal_Colata]

FROM dbo.DO30_DOCCORPO AS PRE_C WITH (NOLOCK)
INNER JOIN dbo.DO11_DOCTESTATA AS PRE_T WITH (NOLOCK)
    ON PRE_T.DO11_DITTA_CG18 = PRE_C.DO30_DITTA_CG18
    AND PRE_T.DO11_NUMREG_CO99 = PRE_C.DO30_NUMREG_CO99

INNER JOIN dbo.DO33_DOCCORPORIF AS PRE_DO33 WITH (NOLOCK)
    ON PRE_DO33.DO33_DITTA_CG18 = PRE_C.DO30_DITTA_CG18
    AND PRE_DO33.DO33_NUMREG_CO99 = PRE_C.DO30_NUMREG_CO99
    AND PRE_DO33.DO33_PROGRIGA = PRE_C.DO30_PROGRIGA
    AND PRE_DO33.DO33_PROGRIF = 1

INNER JOIN dbo.DO30_DOCCORPO AS OC_C WITH (NOLOCK)
    ON OC_C.DO30_DITTA_CG18 = PRE_DO33.DO33_DITTA_CG18
    AND OC_C.DO30_NUMREG_CO99 = PRE_DO33.DO33_NUMREGRIF_CO99
    AND OC_C.DO30_PROGRIGA = PRE_DO33.DO33_PROGRIGARIF_DO30

INNER JOIN dbo.DO11_DOCTESTATA AS OC_T WITH (NOLOCK)
    ON OC_T.DO11_DITTA_CG18 = OC_C.DO30_DITTA_CG18
    AND OC_T.DO11_NUMREG_CO99 = OC_C.DO30_NUMREG_CO99

LEFT JOIN dbo.DO12_DOCTESTARIF AS OC_DO12 WITH (NOLOCK)
    ON OC_DO12.DO12_DITTA_CG18 = OC_T.DO11_DITTA_CG18
    AND OC_DO12.DO12_NUMREG_CO99 = OC_T.DO11_NUMREG_CO99
    AND ISNULL(OC_DO12.DO12_PROGRIF, 1) = 1

LEFT JOIN dbo.DO36_DOCCORPOEST AS OC_DO36 WITH (NOLOCK)
    ON OC_DO36.DO36_DITTA_CG18 = OC_C.DO30_DITTA_CG18
    AND OC_DO36.DO36_NUMREG_CO99 = OC_C.DO30_NUMREG_CO99
    AND OC_DO36.DO36_PROGRIGA = OC_C.DO30_PROGRIGA
    AND ISNULL(OC_DO36.DO36_PROG, 1) = 1

LEFT JOIN dbo.DO35_DOCCORPOPERS AS OC_DO35 WITH (NOLOCK)
    ON OC_DO35.DO35_DITTA_CG18 = OC_C.DO30_DITTA_CG18
    AND OC_DO35.DO35_NUMREG_CO99 = OC_C.DO30_NUMREG_CO99
    AND OC_DO35.DO35_PROGRIGA = OC_C.DO30_PROGRIGA
    AND ISNULL(OC_DO35.DO35_PROG, 1) = 1

INNER JOIN dbo.DO33_DOCCORPORIF AS OC_ODL_DO33 WITH (NOLOCK)
    ON OC_ODL_DO33.DO33_DITTA_CG18 = OC_C.DO30_DITTA_CG18
    AND OC_ODL_DO33.DO33_NUMREGRIF_CO99 = OC_C.DO30_NUMREG_CO99
    AND OC_ODL_DO33.DO33_PROGRIGARIF_DO30 = OC_C.DO30_PROGRIGA

INNER JOIN dbo.DO11_DOCTESTATA AS ODL_T WITH (NOLOCK)
    ON ODL_T.DO11_DITTA_CG18 = OC_ODL_DO33.DO33_DITTA_CG18
    AND ODL_T.DO11_NUMREG_CO99 = OC_ODL_DO33.DO33_NUMREG_CO99
    AND ODL_T.DO11_TIPODOC = 24 AND ODL_T.DO11_STIPODOC = 20

INNER JOIN dbo.DO30_DOCCORPO AS ODL_C WITH (NOLOCK)
    ON ODL_C.DO30_DITTA_CG18 = OC_ODL_DO33.DO33_DITTA_CG18
    AND ODL_C.DO30_NUMREG_CO99 = OC_ODL_DO33.DO33_NUMREG_CO99
    AND ODL_C.DO30_PROGRIGA = OC_ODL_DO33.DO33_PROGRIGA

INNER JOIN dbo.DO33_DOCCORPORIF AS ODL_SCAR_DO33 WITH (NOLOCK)
    ON ODL_SCAR_DO33.DO33_DITTA_CG18 = ODL_C.DO30_DITTA_CG18
    AND ODL_SCAR_DO33.DO33_NUMREGRIF_CO99 = ODL_C.DO30_NUMREG_CO99
    AND ODL_SCAR_DO33.DO33_PROGRIGARIF_DO30 = ODL_C.DO30_PROGRIGA

INNER JOIN dbo.DO11_DOCTESTATA AS SCAR_T WITH (NOLOCK)
    ON SCAR_T.DO11_DITTA_CG18 = ODL_SCAR_DO33.DO33_DITTA_CG18
    AND SCAR_T.DO11_NUMREG_CO99 = ODL_SCAR_DO33.DO33_NUMREG_CO99
    AND SCAR_T.DO11_TIPODOC = 24 AND SCAR_T.DO11_STIPODOC = 5

INNER JOIN dbo.DO30_DOCCORPO AS SCAR_C WITH (NOLOCK)
    ON SCAR_C.DO30_DITTA_CG18 = ODL_SCAR_DO33.DO33_DITTA_CG18
    AND SCAR_C.DO30_NUMREG_CO99 = ODL_SCAR_DO33.DO33_NUMREG_CO99
    AND SCAR_C.DO30_PROGRIGA = ODL_SCAR_DO33.DO33_PROGRIGA

LEFT JOIN dbo.DO52_DOCCORPOLOT AS DO52 WITH (NOLOCK)
    ON DO52.DO52_DITTA_CG18 = SCAR_C.DO30_DITTA_CG18
    AND DO52.DO52_NUMREG_CO99 = SCAR_C.DO30_NUMREG_CO99
    AND DO52.DO52_PROGRIGA = SCAR_C.DO30_PROGRIGA

LEFT JOIN dbo.MG4G_ANAGRLOTTI AS MG4G WITH (NOLOCK)
    ON MG4G.MG4G_DITTA_CG18 = DO52.DO52_DITTA_CG18
    AND MG4G.MG4G_CODART_MG66 = DO52.DO52_CODART_MG66
    AND MG4G.MG4G_OPZIONE_MG5E = DO52.DO52_OPZIONE_MG5E
    AND MG4G.MG4G_CODLOTTO = DO52.DO52_CODLOTTO_MG4G

WHERE PRE_C.DO30_DITTA_CG18 = 1
  AND PRE_C.DO30_NUMREG_CO99 = @NumRegPreDDT
  AND PRE_C.DO30_QTA1 >= @QtaMinima
ORDER BY PRE_C.DO30_PROGRIGA;
```

---

## 6. Questioni Aperte per gli Utenti

In previsione della sessione di verifica con gli utenti di reparto / ufficio commerciale, si evidenziano i seguenti punti di attenzione:

1. **Assenza di Colata Forzata su OC (`DO36_ALFST1` vuoto):**
   - Qualora gli utenti segnalassero che il report avrebbe dovuto stampare una colata differente rispetto a quelle certificate di produzione (`343029`, `437861`, `437613`, `345056`, `440198`), andrà verificato per quale motivo tale valore non è stato inserito in fase di inserimento dell'Ordine Cliente nel campo esteso di riga `DO36_ALFST1`.
2. **Tracciabilità dei Componenti Kanban (Semilavorati):**
   - Per 4 delle 6 righe, il materiale scaricato è un componente a codice `KB_...`. In caso di audit Emerson, verificare se il capitolato accetta il certificato del semilavorato Kanban o se richiede l'ulteriore risalita all'ODL primario di fabbricazione del tondo grezzo di partenza.

