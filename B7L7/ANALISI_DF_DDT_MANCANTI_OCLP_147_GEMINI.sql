/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione : 23/09/2026 15:20
Autore                  : SOLVERIS - Bandera Marco
Progetto                : TMV - Controllo Congruità Flusso ImpExp TMV-LPM (Generazione DF-ORDINECLP)
Oggetto SQL             : Query Diagnostica di Analisi e Quadratura Documentale
Nome File               : ANALISI_DF_DDT_MANCANTI_OCLP_147_GEMINI.sql
Ambiente Database       : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Questo script nasce per monitorare, tracciare e sottoporre ad audit la tenuta del processo automatico
governato dall'Insieme ImpExp 'TMV-LPM' (Passaggio 1, Tracciato 'TMV-LPM').

CONTESTO AZIENDALE:
Ogni qualvolta l'azienda registra a sistema un documento di carico merci di acquisto di tipo
'DF-DDT' (DDT di acquisto da fornitore di materia prima), per tutte le righe articolo la cui codifica
inizia per 'TD' (Trafilato/Pelato/Tondo) e contiene le sequenze 'B7-' o 'B7M' (leghe speciali ASTM A193 B7),
il processo aziendale standard prevede l'emissione automatica di un corrispondente Ordine di Conto
Lavoro Passivo 'DF-ORDINECLP' intestato al fornitore terzista 147 (L.P.M. SNC DI MOLINARI VINCENZO & C.).

L'Insieme batch 'TMV-LPM' esegue tale operazione interrogando la vista di frontiera:
  [dbo].[VPRT_CERTIFICATI_CLONA_B7]
filtrando le righe non ancora collegate tramite la clausola:
  [IE25_WHERE] = 'DO30_DITTA_CG18_OCLP IS NULL'

SCOPO DELL'INDAGINE:
Identificare in modo univoco e puntuale tutti i documenti 'DF-DDT' e le rispettive righe corpo/lotto
che NON risultano collegate ad alcun 'DF-ORDINECLP' sul fornitore 147 all'interno della tabella
di raccordo 'DO33_DOCCORPORIF' (storno righe).

RISULTANZE DELL'ANALISI SUL DATABASE:
1. Orizzonte Temporale Storico (Ante 16/03/2024):
   - L'automatismo 'TMV-LPM' è entrato in funzione a metà marzo 2024 (primo ordine OCLP storico: 11/04/2024).
   - Tutti i DDT del 2023 (298 righe) e del primo bimestre 2024 (70 righe) non hanno OCLP poiché
     gestiti con la precedente operatività manuale/esterna.
2. Periodo Operativo Attivo (Dal 16/03/2024 ad oggi):
   - Su un totale di 924 righe candidate, ben 916 sono state elaborate con successo (99,13%).
   - Esattamente 8 righe (distribuite su 7 documenti DDT) risultano prive del legame OCLP.
   - Diagnosi delle cause:
     * 7 righe (su 6 DDT) mancano della "Data Certificato Fornitore" sul lotto (CO5L_DATA1 IS NULL).
       Essendo tale campo preteso come obbligatorio dal filtro della vista VPRT_CERTIFICATI_CLONA_B7
       (CO5L_DATA1 IS NOT NULL), la riga viene ignorata dal batch notturno.
     * 1 riga (DDT 709 del 2026 riga 4, spezzata su 2 lotti) è stata vittima di un disallineamento
       di puntamento in DO33, dove i lotti sono confluiti sotto la riga 3 dell'ordine 163 anziché la riga 4.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (23/09/2026 - SOLVERIS): Stesura iniziale della query di controllo per identificazione
  e classificazione delle anomalie di mancata generazione OCLP verso fornitore 147.
====================================================================================================
*/

-- =================================================================================================
-- SEZIONE 1: RIEPILOGO STATISTICO AGGREGATO PER ANNO E PERIODO OPERATIVO
-- =================================================================================================
SELECT 
    YEAR(T.DO11_DATADOC) AS [Anno_DDT],
    CASE 
        WHEN T.DO11_DATADOC >= '2024-03-16' THEN 'Periodo Attivo (Post 16/03/2024)' 
        ELSE 'Storico Ante Automazione' 
    END AS [Fase_Processo],
    COUNT(*) AS [Totale_Righe_Candidate_DDT],
    COUNT(DISTINCT T.DO11_NUMREG_CO99) AS [Totale_DDT_Distinti],
    SUM(CASE WHEN OCLP.DO30_NUMREG_CO99 IS NOT NULL THEN 1 ELSE 0 END) AS [Righe_Elaborate_Con_OCLP],
    SUM(CASE WHEN OCLP.DO30_NUMREG_CO99 IS NULL THEN 1 ELSE 0 END) AS [Righe_Anomale_Senza_OCLP],
    CAST(ROUND(SUM(CASE WHEN OCLP.DO30_NUMREG_CO99 IS NOT NULL THEN 1.0 ELSE 0.0 END) * 100.0 / COUNT(*), 2) AS NUMERIC(5,2)) AS [Perc_Successo]
FROM dbo.DO11_DOCTESTATA T WITH (NOLOCK)
INNER JOIN dbo.DO30_DOCCORPO C WITH (NOLOCK)
    ON T.DO11_DITTA_CG18 = C.DO30_DITTA_CG18 
    AND T.DO11_NUMREG_CO99 = C.DO30_NUMREG_CO99
LEFT JOIN (
    -- Subquery di verifica legame con Ordine di Conto Lavoro Passivo intestato al fornitore 147
    SELECT DISTINCT 
        R.DO33_DITTA_CG18,
        R.DO33_NUMREGRIF_CO99,
        R.DO33_PROGRIGARIF_DO30,
        C_OCLP.DO30_NUMREG_CO99
    FROM dbo.DO33_DOCCORPORIF R WITH (NOLOCK)
    INNER JOIN dbo.DO30_DOCCORPO C_OCLP WITH (NOLOCK)
        ON R.DO33_DITTA_CG18 = C_OCLP.DO30_DITTA_CG18 
        AND R.DO33_NUMREG_CO99 = C_OCLP.DO30_NUMREG_CO99 
        AND R.DO33_PROGRIGA = C_OCLP.DO30_PROGRIGA
    INNER JOIN dbo.DO11_DOCTESTATA T_OCLP WITH (NOLOCK)
        ON C_OCLP.DO30_DITTA_CG18 = T_OCLP.DO11_DITTA_CG18 
        AND C_OCLP.DO30_NUMREG_CO99 = T_OCLP.DO11_NUMREG_CO99
    WHERE T_OCLP.DO11_DOCUM_MG36 = 'DF-ORDINECLP'
      AND T_OCLP.DO11_TIPOCF_CG44 = 1
      AND T_OCLP.DO11_CLIFOR_CG44 = '147'
) OCLP
    ON C.DO30_DITTA_CG18 = OCLP.DO33_DITTA_CG18 
    AND C.DO30_NUMREG_CO99 = OCLP.DO33_NUMREGRIF_CO99 
    AND C.DO30_PROGRIGA = OCLP.DO33_PROGRIGARIF_DO30
WHERE T.DO11_DOCUM_MG36 = 'DF-DDT'
  AND C.DO30_INDTIPORIGA = 0
  AND C.DO30_CODART_MG66 LIKE 'TD%'
  AND (C.DO30_CODART_MG66 LIKE '%B7-%' OR C.DO30_CODART_MG66 LIKE '%B7M%')
GROUP BY 
    YEAR(T.DO11_DATADOC),
    CASE 
        WHEN T.DO11_DATADOC >= '2024-03-16' THEN 'Periodo Attivo (Post 16/03/2024)' 
        ELSE 'Storico Ante Automazione' 
    END
ORDER BY [Anno_DDT] DESC;

-- =================================================================================================
-- SEZIONE 2: DETTAGLIO PUNTUALE DELLE RIGHE ANOMALE (PERIODO ATTIVO DAL 16/03/2024 AD OGGI)
-- =================================================================================================
SELECT 
    T.DO11_NUMDOC AS [Num_DDT],
    CONVERT(VARCHAR(10), T.DO11_DATADOC, 103) AS [Data_DDT],
    T.DO11_CLIFOR_CG44 AS [Cod_Fornitore_DDT],
    C.DO30_PROGRIGA AS [Riga_DDT],
    RTRIM(C.DO30_CODART_MG66) AS [Cod_Articolo],
    RTRIM(C.DO30_DESCART) AS [Descrizione_Articolo],
    C.DO30_QTA1 AS [Quantita_DDT],
    ISNULL(L.DO52_CODLOTTO_MG4G, 'NESSUN LOTTO') AS [Codice_Lotto],
    CONVERT(VARCHAR(10), CO5L.CO5L_DATA1, 103) AS [Data_Certificato_Lotto],
    CASE 
        WHEN L.DO52_CODLOTTO_MG4G IS NULL THEN 'Manca Lotto su riga DDT'
        WHEN CO5L.CO5L_DATA1 IS NULL THEN 'Blocco Vista: Data Certificato mancante su anagrafica lotto (CO5L_DATA1 IS NULL)'
        ELSE 'Disallineamento legame storno DO33 / Multi-lotto'
    END AS [Diagnosi_Causa_Mancata_Generazione]
FROM dbo.DO11_DOCTESTATA T WITH (NOLOCK)
INNER JOIN dbo.DO30_DOCCORPO C WITH (NOLOCK)
    ON T.DO11_DITTA_CG18 = C.DO30_DITTA_CG18 
    AND T.DO11_NUMREG_CO99 = C.DO30_NUMREG_CO99
LEFT JOIN dbo.DO52_DOCCORPOLOT L WITH (NOLOCK)
    ON C.DO30_DITTA_CG18 = L.DO52_DITTA_CG18 
    AND C.DO30_NUMREG_CO99 = L.DO52_NUMREG_CO99 
    AND C.DO30_PROGRIGA = L.DO52_PROGRIGA
LEFT JOIN dbo.MG4G_ANAGRLOTTI M WITH (NOLOCK)
    ON L.DO52_DITTA_CG18 = M.MG4G_DITTA_CG18 
    AND L.DO52_CODART_MG66 = M.MG4G_CODART_MG66 
    AND L.DO52_OPZIONE_MG5E = M.MG4G_OPZIONE_MG5E 
    AND L.DO52_CODLOTTO_MG4G = M.MG4G_CODLOTTO
LEFT JOIN dbo.CO5L_ATTRIBUTIDEN CO5L WITH (NOLOCK)
    ON M.MG4G_GUID = CO5L.CO5L_GUID
LEFT JOIN (
    SELECT DISTINCT 
        R.DO33_DITTA_CG18,
        R.DO33_NUMREGRIF_CO99,
        R.DO33_PROGRIGARIF_DO30
    FROM dbo.DO33_DOCCORPORIF R WITH (NOLOCK)
    INNER JOIN dbo.DO30_DOCCORPO C_OCLP WITH (NOLOCK)
        ON R.DO33_DITTA_CG18 = C_OCLP.DO30_DITTA_CG18 
        AND R.DO33_NUMREG_CO99 = C_OCLP.DO30_NUMREG_CO99 
        AND R.DO33_PROGRIGA = C_OCLP.DO30_PROGRIGA
    INNER JOIN dbo.DO11_DOCTESTATA T_OCLP WITH (NOLOCK)
        ON C_OCLP.DO30_DITTA_CG18 = T_OCLP.DO11_DITTA_CG18 
        AND C_OCLP.DO30_NUMREG_CO99 = T_OCLP.DO11_NUMREG_CO99
    WHERE T_OCLP.DO11_DOCUM_MG36 = 'DF-ORDINECLP'
      AND T_OCLP.DO11_TIPOCF_CG44 = 1
      AND T_OCLP.DO11_CLIFOR_CG44 = '147'
) OCLP
    ON C.DO30_DITTA_CG18 = OCLP.DO33_DITTA_CG18 
    AND C.DO30_NUMREG_CO99 = OCLP.DO33_NUMREGRIF_CO99 
    AND C.DO30_PROGRIGA = OCLP.DO33_PROGRIGARIF_DO30
WHERE T.DO11_DOCUM_MG36 = 'DF-DDT'
  AND C.DO30_INDTIPORIGA = 0
  AND C.DO30_CODART_MG66 LIKE 'TD%'
  AND (C.DO30_CODART_MG66 LIKE '%B7-%' OR C.DO30_CODART_MG66 LIKE '%B7M%')
  AND T.DO11_DATADOC >= '2024-03-16'
  AND OCLP.DO33_NUMREGRIF_CO99 IS NULL
ORDER BY T.DO11_DATADOC DESC, T.DO11_NUMDOC DESC, C.DO30_PROGRIGA;

