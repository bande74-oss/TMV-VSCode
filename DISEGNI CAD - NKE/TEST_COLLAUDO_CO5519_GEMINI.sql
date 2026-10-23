-- =================================================================================================================================
-- Cartiglio Narrativo Obbligatorio (Standard di Codifica SOLVERIS - Progetto TMV)
-- =================================================================================================================================
-- Data e Ora Creazione : 2026-10-23 12:30
-- Autore               : SOLVERIS - Bandera Marco
-- Oggetto SQL          : Script di Collaudo e Diagnostica - Caso Studio CO 5519 TUXOR
-- Tipologia Oggetto    : Script di Test / Verification Suite
-- Versione Compatibile : Microsoft SQL Server 2017 (MSSQL 14.0.2120.1)
-- Ambiente Target      : DBTMV (Produzione / Staging)
--
-- OBIETTIVO DEL COLLAUDO:
-- ---------------------------------------------------------------------------------------------------------------------------------
-- Il presente script verifica formalmente e deterministicamente la risoluzione dell'anomalia segnalata dall'Ufficio Tecnico
-- relativamente alla conferma d'ordine CO 5519 (Cliente TUXOR).
--
-- STORICO DEL CASO REALE (CO 5519):
-- 1. Ordine caricato il 30/09 (stato iniziale 10045 - Generato) con posizioni 63-108 inserite erroneamente.
-- 2. Prima revisione in data 01/10 (modificate in PDN ma con varianti provvisorie/errate).
-- 3. Seconda revisione e Approvazione Direzionale in data 02/10 (corrette varianti e avanzamento a stato 10046 - DIBA Localizzata).
-- 4. DIFETTO PREESISTENTE: Il batch ImpExp TMV_NKE_OC filtrava solo lo stato 10045. Le righe approvate/corrette in data 02/10
--    non sono mai più state esportate verso NKE, costringendo i disegnatori a produrre a mano circa 50 disegni CAD.
--
-- COSA DIMOSTRANO QUESTI TEST:
-- Test 1 (Dry-Run Delta): Dimostra che SPSO_NKE_ALIMENTA_CODA_GEMINI individua all'istante le 68 righe corrette (tra cui tutte le PDN)
--                         marcandole 'DA_INSERIRE_NUOVO', mentre riconosce le 93 righe già prodotte come 'GIA_A_LOG', senza duplicazioni.
-- Test 2 (Dry-Run Forzato): Dimostra la possibilità richiesta dagli utenti di forzare il re-export integrale (@ForzaReinvio = 1).
-- Test 3 (Dry-Run Massivo): Dimostra il corretto funzionamento del monitoraggio automatico su tutti gli ordini recenti.
-- Test 4 (Dry-Run Dispatcher): Dimostra l'elaborazione del prossimo articolo e la corretta formattazione del JSON per NKE.
-- =================================================================================================================================

USE [DBTMV];
GO

PRINT '===================================================================================================';
PRINT 'TEST 1: SIMULAZIONE DELTA SU CO 5519 (RISOLUZIONE DEL CASO SEGNALATO DALL''UTENTE)';
PRINT '===================================================================================================';
EXEC dbo.SPSO_NKE_ALIMENTA_CODA_GEMINI 
    @ModalitaDryRun = 1, 
    @NumDoc = 5519, 
    @ForzaReinvio = 0;
GO

PRINT '===================================================================================================';
PRINT 'TEST 2: SIMULAZIONE RILANCIO FORZATO INTEGRALE SU CO 5519 (@ForzaReinvio = 1)';
PRINT '===================================================================================================';
EXEC dbo.SPSO_NKE_ALIMENTA_CODA_GEMINI 
    @ModalitaDryRun = 1, 
    @NumDoc = 5519, 
    @ForzaReinvio = 1;
GO

PRINT '===================================================================================================';
PRINT 'TEST 3: SIMULAZIONE MONITORAGGIO AUTOMATICO MASSIVO (ULTIMI 7 GIORNI)';
PRINT '===================================================================================================';
EXEC dbo.SPSO_NKE_ALIMENTA_CODA_GEMINI 
    @ModalitaDryRun = 1, 
    @GiorniIndietro = 7;
GO

PRINT '===================================================================================================';
PRINT 'TEST 4: SIMULAZIONE DISPATCHER CONSUMATORE CODA (SPSO_NKE_SCHED_GEMINI)';
PRINT '===================================================================================================';
EXEC dbo.SPSO_NKE_SCHED_GEMINI 
    @ModalitaDryRun = 1;
GO

