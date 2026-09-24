/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione/Modifica : 24/09/2026 16:55
Autore                           : SOLVERIS - Bandera Marco
Progetto                         : TMV - Gestione e Normalizzazione Automatica Descrizioni Articoli
Oggetto SQL                      : Script DML Popolamento e Normalizzazione dbo.RT05_DESCR_DIAM_PASSO
Nome File                        : RT05_POPOLAMENTO_METRICI_MANCANTI_GEMINI.sql
Ambiente Database                : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Il presente script DML nasce per risolvere la carenza e l'allineamento dei dati anagrafici di 
decodifica nella tabella 'dbo.RT05_DESCR_DIAM_PASSO', impiegata dalle procedure e funzioni di
composizione delle descrizioni articoli (in primis 'dbo.SPRT_TMV_DESCRIZIONE' e la nuova
'dbo.SFSO_TMV_DESCRIZIONE_GEMINI') per il calcolo del diametro effettivo delle barre tonde grezze 
pelate/trafilate (famiglie 'TDP', 'TDR', 'TDL', 'TDF').

CONTESTO OPERATIVO E REVISIONE TECNICA (FEEDBACK UFFICIO TECNICO - Nicola Beccalori e Luca):
Nella versione preliminare (Rev. 1.0) il diametro base barra era stato calcolato secondo la formula
teorica standard:
    Diametro Base Barra = Diametro Nominale - Delta Filettatura
A seguito dell'analisi congiunta con l'Ufficio Tecnico (Nicola Beccalori / Luca), è emerso che in officina
e nei processi di lavorazione meccanica (pelatura, trafilatura e successiva filettatura/rullatura)
NON si deve mai adottare il massimo teorico, bensì il MINIMO DA NORMATIVA, per evitare che la barra
risulti sovradimensionata e impedisca il montaggio o l'avanzamento degli utensili ("non va su niente").

FORMULA UFFICIALE DI CALCOLO MINIMO DA NORMATIVA UT:
    Diametro Base Barra (RT05_DIAMETRO) = (Diametro Nominale - Delta Passo) - 0,23 mm
ove 0,23 mm è la tolleranza sottratta per garantire la lavorabilità al limite inferiore consentito.

DELTA PER PASSO:
- Passo 3 mm (Codice '3-'): Delta = 2,00 mm  --> RT05_DIAMETRO = (Nominale - 2,00) - 0,23
- Passo 4 mm (Codice '4-'): Delta = 2,66 mm  --> RT05_DIAMETRO = (Nominale - 2,66) - 0,23
- Passo 6 mm (Codice 'G-' sotto M125 o '6-'): Delta = 3,98 mm  --> RT05_DIAMETRO = (Nominale - 3,98) - 0,23
- Passo 8 mm (Codice 'G-' da M125 in poi): Delta = 5,40 mm  --> RT05_DIAMETRO = (Nominale - 5,40) - 0,23

CALCOLO DELLA DESCRIZIONE FINALE DELL'ARTICOLO (con eventuale minorazione barra):
    Diametro Finale = RT05_DIAMETRO - (Minorazione / 10)

ESEMPIO PRATICO CASO PILOTA (Articolo TDP04B7-M1254- con minorazione 04 = 0,40 mm):
    Nominale M125, Passo 4 mm (Codice '4-')
    Delta Filetto = 2,66 mm
    Diametro Base Barra RT05 = (125 - 2,66) - 0,23 = 122,34 - 0,23 = 122,11 mm
    Diametro Finale Calcolato = 122,11 - (4 / 10) = 122,11 - 0,40 = 121,71 mm
    Descrizione Risultante: 'Ø 121,71mm' (in sostituzione del vecchio testo grezzo di fallback 'M125 4').

DELIBERA DEFINITIVA UFFICIO TECNICO SU PASSO GROSSO 'G-' E NUOVA CODIFICA '6-':
Da M125 in poi, la normativa unificata ISO prevede che il passo grosso standard sia 8 mm.
Come stabilito ufficialmente dall'Ufficio Tecnico (Nicola Beccalori):
1) Al passo 'G-' su diametri >= M125 viene associato SEMPRE il passo grosso normato 8 mm (Delta 5,40 mm).
2) Per filettature a passo 6 mm su diametri >= M125 viene creata e applicata la nuova codifica '6-'.
3) Per M155 (diametro speciale dove non esiste da norma il passo 8), il passo grosso naturale 'G-' è 6 mm (Delta 3,98 mm), con alias '6-'.
4) Per M110 e M120, il passo grosso naturale 'G-' è passo 6 mm.

CRITERI DI SICUREZZA ED IDEMPOTENZA (TRY...CATCH e MERGE / UPDATE+INSERT):
Lo script opera all'interno di una transazione atomica protetta da TRY...CATCH.
Utilizza un pattern MERGE / UPDATE + INSERT per aggiornare sia i record preesistenti sia per inserire
le nuove combinazioni mancanti, garantendo la rieseguibilità illimitata senza errori di PK.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (24/09/2026 09:00 - SOLVERIS - Bandera Marco):
  Creazione preliminare dello script DML transazionale per il popolamento delle combinazioni metriche
  mancanti in RT05 (M110, M120, M125, M130, M155, M160, M180) basato su massimo teorico (Nominale - Delta).
- Rev. 2.0 (24/09/2026 15:05 - SOLVERIS - Bandera Marco):
  Revisione radicale su direttiva congiunta dell'Ufficio Tecnico (Nicola Beccalori e Luca).
  Applicata la regola del MINIMO DA NORMATIVA: Diametro Base Barra = (Nominale - Delta) - 0,23 mm.
  Normalizzati i valori di RT05_DIAMETRO e RT05_DES_DIAMETRO con prefisso Unicode N'Ø' pulito.
  Predisposta la codifica passo '6-' per M110, M120, M125, M130, M155, M160, M180 in parallelo a 'G-'.
- Rev. 3.0 (24/09/2026 16:55 - SOLVERIS - Bandera Marco):
  Delibera definitiva con Ufficio Tecnico:
  - Per diametri >= M125 (M125, M130, M160, M180), al passo grosso 'G-' viene assegnato ufficialmente il passo 8 mm (Delta 5,40 mm -> Nominale - 5,63 mm).
  - La nuova codifica '6-' gestisce in modo esplicito il passo 6 mm (Delta 3,98 mm -> Nominale - 4,21 mm).
  - Per M155, confermata la natura di diametro speciale in cui 'G-' corrisponde a passo 6 mm (150,79 mm), mantenendo l'alias '6-'.
====================================================================================================
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

PRINT '================================================================================';
PRINT 'AVVIO SCRIPT POPOLAMENTO E NORMALIZZAZIONE RT05_DESCR_DIAM_PASSO (Rev. 3.0 UT)';
PRINT 'Data e Ora: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '================================================================================';

BEGIN TRY
    BEGIN TRANSACTION;

    -- Tabella temporanea in memoria con la matrice completa dei valori normalizzati al minimo UT
    DECLARE @NuoviValoriRT05 TABLE (
        Ditta           DECIMAL(5,0)    NOT NULL,
        ProgrMG6E_1     DECIMAL(5,0)    NOT NULL, -- 4 = Diametro
        SubcodiceMG6E_1 CHAR(25)        NOT NULL, -- Codice Diametro (es. M125)
        ProgrMG6E_2     DECIMAL(5,0)    NOT NULL, -- 5 = Passo
        SubcodiceMG6E_2 CHAR(25)        NOT NULL, -- Codice Passo (es. 4-, G-, 6-)
        Descrizione     VARCHAR(256)    NOT NULL, -- Descrizione combinata (es. M125x4)
        DesDiametro     NVARCHAR(50)    NOT NULL, -- Descr. diametro (es. Ø 122,11 mm)
        Diametro        DECIMAL(18,2)   NOT NULL, -- Diametro barra base minimo normativa
        ResilB7L7       CHAR(2)         NOT NULL  -- Resilienza B7/L7 (SI)
    );

    -- =============================================================================================
    -- DEFINIZIONE DEI VALORI SECONDO NORMATIVA E INDICAZIONI UFFICIO TECNICO:
    -- Diametro Base Barra = (Diametro Nominale - Delta Passo) - 0,23 mm
    -- =============================================================================================

    -- --- M110 ---
    -- Passo 3 mm: Delta 2.00 -> (110 - 2.00) - 0.23 = 107.77 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M110', 5, '3-', 'M110x3', N'Ø 107,77 mm', 107.77, 'SI');
    -- Passo 4 mm: Delta 2.66 -> (110 - 2.66) - 0.23 = 107.11 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M110', 5, '4-', 'M110x4', N'Ø 107,11 mm', 107.11, 'SI');
    -- Passo 6 mm (G- / 6-): Delta 3.98 -> (110 - 3.98) - 0.23 = 105.79 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M110', 5, 'G-', 'M110x6', N'Ø 105,79 mm', 105.79, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M110', 5, '6-', 'M110x6', N'Ø 105,79 mm', 105.79, 'SI');

    -- --- M120 ---
    -- Passo 3 mm: Delta 2.00 -> (120 - 2.00) - 0.23 = 117.77 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M120', 5, '3-', 'M120x3', N'Ø 117,77 mm', 117.77, 'SI');
    -- Passo 4 mm: Delta 2.66 -> (120 - 2.66) - 0.23 = 117.11 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M120', 5, '4-', 'M120x4', N'Ø 117,11 mm', 117.11, 'SI');
    -- Passo 6 mm (G- / 6-): Delta 3.98 -> (120 - 3.98) - 0.23 = 115.79 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M120', 5, 'G-', 'M120x6', N'Ø 115,79 mm', 115.79, 'SI');
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M120', 5, '6-', 'M120x6', N'Ø 115,79 mm', 115.79, 'SI');

    -- --- M125 (Articolo Target Principale TDP04B7-M1254-) ---
    -- Passo 3 mm: Delta 2.00 -> (125 - 2.00) - 0.23 = 122.77 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M125', 5, '3-', 'M125x3', N'Ø 122,77 mm', 122.77, 'SI');
    -- Passo 4 mm: Delta 2.66 -> (125 - 2.66) - 0.23 = 122.11 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M125', 5, '4-', 'M125x4', N'Ø 122,11 mm', 122.11, 'SI');
    -- Passo 8 mm (G- Normato ISO UT): Delta 5.40 -> (125 - 5.40) - 0.23 = 119.37 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M125', 5, 'G-', 'M125x8', N'Ø 119,37 mm', 119.37, 'SI');
    -- Passo 6 mm (6- Nuova Codifica UT): Delta 3.98 -> (125 - 3.98) - 0.23 = 120.79 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M125', 5, '6-', 'M125x6', N'Ø 120,79 mm', 120.79, 'SI');

    -- --- M130 ---
    -- Passo 3 mm: Delta 2.00 -> (130 - 2.00) - 0.23 = 127.77 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M130', 5, '3-', 'M130x3', N'Ø 127,77 mm', 127.77, 'SI');
    -- Passo 4 mm: Delta 2.66 -> (130 - 2.66) - 0.23 = 127.11 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M130', 5, '4-', 'M130x4', N'Ø 127,11 mm', 127.11, 'SI');
    -- Passo 8 mm (G- Normato ISO UT): Delta 5.40 -> (130 - 5.40) - 0.23 = 124.37 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M130', 5, 'G-', 'M130x8', N'Ø 124,37 mm', 124.37, 'SI');
    -- Passo 6 mm (6- Nuova Codifica UT): Delta 3.98 -> (130 - 3.98) - 0.23 = 125.79 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M130', 5, '6-', 'M130x6', N'Ø 125,79 mm', 125.79, 'SI');

    -- --- M155 (Diametro Speciale ISO: Passo Massimo Naturale 6 mm) ---
    -- Passo 3 mm: Delta 2.00 -> (155 - 2.00) - 0.23 = 152.77 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M155', 5, '3-', 'M155x3', N'Ø 152,77 mm', 152.77, 'SI');
    -- Passo 4 mm: Delta 2.66 -> (155 - 2.66) - 0.23 = 152.11 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M155', 5, '4-', 'M155x4', N'Ø 152,11 mm', 152.11, 'SI');
    -- Passo 6 mm (G- Passo Grosso Naturale M155): Delta 3.98 -> (155 - 3.98) - 0.23 = 150.79 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M155', 5, 'G-', 'M155x6', N'Ø 150,79 mm', 150.79, 'SI');
    -- Passo 6 mm (6- Alias prudenziale per nuova codifica passo 6): Delta 3.98 -> 150.79 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M155', 5, '6-', 'M155x6', N'Ø 150,79 mm', 150.79, 'SI');

    -- --- M160 ---
    -- Passo 3 mm: Delta 2.00 -> (160 - 2.00) - 0.23 = 157.77 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M160', 5, '3-', 'M160x3', N'Ø 157,77 mm', 157.77, 'SI');
    -- Passo 4 mm: Delta 2.66 -> (160 - 2.66) - 0.23 = 157.11 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M160', 5, '4-', 'M160x4', N'Ø 157,11 mm', 157.11, 'SI');
    -- Passo 8 mm (G- Normato ISO UT): Delta 5.40 -> (160 - 5.40) - 0.23 = 154.37 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M160', 5, 'G-', 'M160x8', N'Ø 154,37 mm', 154.37, 'SI');
    -- Passo 6 mm (6- Nuova Codifica UT): Delta 3.98 -> (160 - 3.98) - 0.23 = 155.79 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M160', 5, '6-', 'M160x6', N'Ø 155,79 mm', 155.79, 'SI');

    -- --- M180 ---
    -- Passo 3 mm: Delta 2.00 -> (180 - 2.00) - 0.23 = 177.77 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M180', 5, '3-', 'M180x3', N'Ø 177,77 mm', 177.77, 'SI');
    -- Passo 4 mm: Delta 2.66 -> (180 - 2.66) - 0.23 = 177.11 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M180', 5, '4-', 'M180x4', N'Ø 177,11 mm', 177.11, 'SI');
    -- Passo 8 mm (G- Normato ISO UT): Delta 5.40 -> (180 - 5.40) - 0.23 = 174.37 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M180', 5, 'G-', 'M180x8', N'Ø 174,37 mm', 174.37, 'SI');
    -- Passo 6 mm (6- Nuova Codifica UT): Delta 3.98 -> (180 - 3.98) - 0.23 = 175.79 mm
    INSERT INTO @NuoviValoriRT05 VALUES (1, 4, 'M180', 5, '6-', 'M180x6', N'Ø 175,79 mm', 175.79, 'SI');

    -- =============================================================================================
    -- OPERAZIONE 1: AGGIORNAMENTO RECORD ESISTENTI (UPDATE)
    -- =============================================================================================
    UPDATE tgt
    SET 
        tgt.RT05_DESCRIZIONE  = src.Descrizione,
        tgt.RT05_DES_DIAMETRO = src.DesDiametro,
        tgt.RT05_DIAMETRO     = src.Diametro,
        tgt.RT05_RESIL_B7L7   = src.ResilB7L7
    FROM dbo.RT05_DESCR_DIAM_PASSO AS tgt
    INNER JOIN @NuoviValoriRT05 AS src
        ON tgt.RT05_DITTA_CG18       = src.Ditta
       AND tgt.RT05_PROGR_MG6E_1     = src.ProgrMG6E_1
       AND tgt.RT05_SUBCODICE_MG6E_1 = src.SubcodiceMG6E_1
       AND tgt.RT05_PROGR_MG6E_2     = src.ProgrMG6E_2
       AND tgt.RT05_SUBCODICE_MG6E_2 = src.SubcodiceMG6E_2;

    DECLARE @RigheAggiornate INT = @@ROWCOUNT;
    PRINT 'Aggiornate ' + CAST(@RigheAggiornate AS VARCHAR(10)) + ' combinazioni preesistenti in RT05_DESCR_DIAM_PASSO.';

    -- =============================================================================================
    -- OPERAZIONE 2: INSERIMENTO RECORD MANCANTI (INSERT)
    -- =============================================================================================
    INSERT INTO dbo.RT05_DESCR_DIAM_PASSO (
        RT05_DITTA_CG18,
        RT05_PROGR_MG6E_1,
        RT05_SUBCODICE_MG6E_1,
        RT05_PROGR_MG6E_2,
        RT05_SUBCODICE_MG6E_2,
        RT05_DESCRIZIONE,
        RT05_DES_DIAMETRO,
        RT05_DIAMETRO,
        RT05_RESIL_B7L7
    )
    SELECT 
        src.Ditta,
        src.ProgrMG6E_1,
        src.SubcodiceMG6E_1,
        src.ProgrMG6E_2,
        src.SubcodiceMG6E_2,
        src.Descrizione,
        src.DesDiametro,
        src.Diametro,
        src.ResilB7L7
    FROM @NuoviValoriRT05 AS src
    WHERE NOT EXISTS (
        SELECT 1 
        FROM dbo.RT05_DESCR_DIAM_PASSO AS tgt WITH (NOLOCK)
        WHERE tgt.RT05_DITTA_CG18       = src.Ditta
          AND tgt.RT05_PROGR_MG6E_1     = src.ProgrMG6E_1
          AND tgt.RT05_SUBCODICE_MG6E_1 = src.SubcodiceMG6E_1
          AND tgt.RT05_PROGR_MG6E_2     = src.ProgrMG6E_2
          AND tgt.RT05_SUBCODICE_MG6E_2 = src.SubcodiceMG6E_2
    );

    DECLARE @RigheInserite INT = @@ROWCOUNT;
    PRINT 'Inserite ' + CAST(@RigheInserite AS VARCHAR(10)) + ' nuove combinazioni in RT05_DESCR_DIAM_PASSO.';

    -- Commit della transazione
    COMMIT TRANSACTION;
    PRINT 'Transazione confermata con successo (COMMIT).';

    -- Report di verifica dei record attualmente censiti per i diametri trattati
    PRINT '';
    PRINT '--- VERIFICA RECORD PRESENTI IN RT05 PER I DIAMETRI TRATTATI ---';
    SELECT 
        RT05_SUBCODICE_MG6E_1 AS Diametro,
        RT05_SUBCODICE_MG6E_2 AS Passo,
        RT05_DESCRIZIONE      AS Descrizione,
        RT05_DES_DIAMETRO     AS DesDiametro,
        RT05_DIAMETRO         AS DiametroBaseMinimo,
        RT05_RESIL_B7L7       AS Resilienza
    FROM dbo.RT05_DESCR_DIAM_PASSO WITH (NOLOCK)
    WHERE RT05_DITTA_CG18 = 1
      AND RT05_SUBCODICE_MG6E_1 IN ('M110', 'M120', 'M125', 'M130', 'M155', 'M160', 'M180')
    ORDER BY RT05_SUBCODICE_MG6E_1, RT05_SUBCODICE_MG6E_2;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT 'ERRORE RILEVATO durante il popolamento di RT05:';
    PRINT 'Messaggio : ' + ERROR_MESSAGE();
    PRINT 'Riga      : ' + CAST(ERROR_LINE() AS VARCHAR(10));
    PRINT 'Numero    : ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
    THROW;
END CATCH;
GO
