/*
====================================================================================================
Cartiglio Narrativo di Sviluppo SQL - Standard SOLVERIS
====================================================================================================
Data e Ora di Creazione : 23/09/2026 15:58
Autore                  : SOLVERIS - Bandera Marco
Progetto                : TMV - Correzione e Quadratura Documentale Flusso ImpExp TMV-LPM
Oggetto SQL             : Script DML di Bonifica e Sgancio Lotti Intrusi su OCLP 163 del 2026
Nome File               : SGANCIO_LOTTI_INTRUSI_OCLP_163_GEMINI.sql
Ambiente Database       : DBTMV (MSSQL 14.0.2120.1 - SQL Server 2017)
----------------------------------------------------------------------------------------------------
DESCRIZIONE AD ALTISSIMO DETTAGLIO ED OBIETTIVO DI BUSINESS:
Questo script esegue l'operazione di 'sgancio' (disaccoppiamento) dei due lotti intrusi:
  - TDP2604/0047 (Q.tà 1.587 kg)
  - TDP2604/0045 (Q.tà 5.395 kg)
erroneamente finiti all'interno della tabella lotti corpo documento 'DO52_DOCCORPOLOT' sotto la
Riga 2 dell'Ordine di Conto Lavoro Passivo DF-ORDINECLP n. 163 del 21/04/2026 (NumReg: 202600080307).

CONTESTO DELL'ANOMALIA:
A causa del progressivo lotti non azzerato nel DDT 709 del 20/04/2026 (dove la riga 4 riportava
progressivi lotti 2 e 3 anziché 1), il tracciato batch ImpExp 'TMV-LPM' non ha creato la riga 4
sull'ordine OCLP, ma ha accodato i due lotti come lotti aggiuntivi della riga 3 del DDT (riga 2 OCLP).
Di conseguenza:
  - La Riga 2 di OCLP 163 aveva una quantità di riga pari a 1.463 kg, ma registrava ben 8.445 kg di lotti!
  - I due lotti da 1.587 kg e 5.395 kg non sono mai stati movimentati verso LPM, non compaiono in nessun
    DDTCLAVINV né DDTCLAVCAR, e sono fisicamente e contabilmente fermi in magazzino.

AZIONE ESEGUITA:
Lo script rimuove in modo chirurgico i due record dalla tabella 'dbo.DO52_DOCCORPOLOT', ripristinando
la quadratura della riga 2 di OCLP 163 (che torna a riportare unicamente il lotto TDP2604/0044 da 1.463 kg).
Questo 'sgancia' i due lotti e libera la riga 4 del DDT 709, che viene così riacquisita dalla vista
'VPRT_CERTIFICATI_CLONA_B7' pronta per la regolare emissione dell'OCLP da 6.982 kg al fornitore 147.

SICUREZZA E MODALITA' DRY-RUN:
- @DryRun = 1 (Default): Simula l'operazione, visualizza i record target e annulla qualsiasi modifica.
- @DryRun = 0: Esegue la rimozione effettiva all'interno di una transazione sicura con TRY...CATCH.
----------------------------------------------------------------------------------------------------
STORICO REVISIONI (Change Log Narrativo):
- Rev. 1.0 (23/09/2026 - SOLVERIS - Bandera Marco): Stesura iniziale dello script di bonifica lotti intrusi.
====================================================================================================
*/

SET NOCOUNT ON;

DECLARE @DryRun BIT = 0; -- Impostare a 0 per applicare le modifiche, 1 per sola simulazione
DECLARE @Ditta DECIMAL(2,0) = 1;
DECLARE @NumRegOCLP DECIMAL(12,0) = 202600080307; -- DF-ORDINECLP n. 163 del 2026
DECLARE @RigaOCLP INT = 2;

BEGIN TRY
    BEGIN TRANSACTION;

    PRINT '==================================================================================';
    PRINT 'FASE 1: VERIFICA PRELIMINARE RECORD PRESENTI PRIMA DELLA BONIFICA';
    PRINT '==================================================================================';
    
    SELECT 
        'STATO ATTUALE' AS [Contesto],
        DO52_DITTA_CG18,
        DO52_NUMREG_CO99,
        DO52_PROGRIGA,
        DO52_PROG,
        RTRIM(DO52_CODART_MG66) AS DO52_CODART_MG66,
        RTRIM(DO52_CODLOTTO_MG4G) AS DO52_CODLOTTO_MG4G,
        DO52_QTA1,
        CASE 
            WHEN DO52_CODLOTTO_MG4G IN ('TDP2604/0047', 'TDP2604/0045') THEN 'DA ELIMINARE (INTRUSO)'
            ELSE 'DA CONSERVARE (LEGITTIMO)'
        END AS [Azione_Prevista]
    FROM dbo.DO52_DOCCORPOLOT WITH (NOLOCK)
    WHERE DO52_DITTA_CG18 = @Ditta
      AND DO52_NUMREG_CO99 = @NumRegOCLP
      AND DO52_PROGRIGA = @RigaOCLP;

    PRINT '==================================================================================';
    PRINT 'FASE 2: ELIMINAZIONE CHIRURGICA DEI LOTTI INTRUSI';
    PRINT '==================================================================================';

    DELETE FROM dbo.DO52_DOCCORPOLOT
    WHERE DO52_DITTA_CG18 = @Ditta
      AND DO52_NUMREG_CO99 = @NumRegOCLP
      AND DO52_PROGRIGA = @RigaOCLP
      AND DO52_CODLOTTO_MG4G IN ('TDP2604/0047', 'TDP2604/0045');

    DECLARE @RigheEliminate INT = @@ROWCOUNT;
    PRINT 'Record lotti eliminati: ' + CAST(@RigheEliminate AS VARCHAR(10));

    IF @RigheEliminate <> 2
    BEGIN
        RAISERROR('ATTENZIONE: Numero di record eliminati (%d) diverso da quello atteso (2). Rollback!', 16, 1, @RigheEliminate);
    END;

    PRINT '==================================================================================';
    PRINT 'FASE 3: VERIFICA POST-ELIMINAZIONE (STATO FINALE)';
    PRINT '==================================================================================';

    SELECT 
        'STATO RESIDUO' AS [Contesto],
        DO52_DITTA_CG18,
        DO52_NUMREG_CO99,
        DO52_PROGRIGA,
        DO52_PROG,
        RTRIM(DO52_CODART_MG66) AS DO52_CODART_MG66,
        RTRIM(DO52_CODLOTTO_MG4G) AS DO52_CODLOTTO_MG4G,
        DO52_QTA1
    FROM dbo.DO52_DOCCORPOLOT
    WHERE DO52_DITTA_CG18 = @Ditta
      AND DO52_NUMREG_CO99 = @NumRegOCLP
      AND DO52_PROGRIGA = @RigaOCLP;

    IF @DryRun = 1
    BEGIN
        PRINT '----------------------------------------------------------------------------------';
        PRINT 'MODALITA DRY-RUN ATTIVA: ESECUZIONE DEL ROLLBACK (NESSUNA MODIFICA PERMANENTE)';
        PRINT '----------------------------------------------------------------------------------';
        ROLLBACK TRANSACTION;
    END
    ELSE
    BEGIN
        PRINT '----------------------------------------------------------------------------------';
        PRINT 'MODALITA REALE ATTIVA: ESECUZIONE DEL COMMIT (MODIFICHE CONSOLIDATE SU DATABASE)';
        PRINT '----------------------------------------------------------------------------------';
        COMMIT TRANSACTION;
    END

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState INT = ERROR_STATE();

    PRINT '!!! ERRORE RISCONTRATO DURANTE L''ESECUZIONE: ' + @ErrorMessage;
    RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END CATCH;
GO

