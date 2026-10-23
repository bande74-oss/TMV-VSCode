using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Tmv.Nke.Connector.Configuration;
using Tmv.Nke.Connector.Models;

namespace Tmv.Nke.Connector.Services;

public class QueueRepository : IQueueRepository
{
    private readonly NkeSettings _settings;
    private readonly ILogger<QueueRepository> _logger;

    public QueueRepository(IOptions<NkeSettings> options, ILogger<QueueRepository> logger)
    {
        _settings = options.Value;
        _logger = logger;
    }

    private IDbConnection CreateConnection()
    {
        return new SqlConnection(_settings.ConnectionString);
    }

    public async Task<QueueItem?> GetNextPendingItemAsync(CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        const string sql = @"
            SELECT TOP 1 
                RT13_GUID, RT13_DITTA_CG18, RT13_CODART_MG66, RT13_OPZIONE_MG5E,
                MG87_GUID, DESCRIZIONE, RT13_INSERT_DATETIME, RT13_CALL_DATETIME,
                RT13_SOVRASCRIVI, RT13_FILE_GENERATO, RT13_NUM_TENTATIVI
            FROM dbo.RT13_NKE WITH (NOLOCK)
            WHERE RT13_NUM_TENTATIVI < @MaxRetries
            ORDER BY 
                CASE WHEN RT13_CALL_DATETIME IS NULL THEN 0 ELSE 1 END ASC,
                RT13_INSERT_DATETIME ASC;";

        return await conn.QueryFirstOrDefaultAsync<QueueItem>(new CommandDefinition(sql, new { MaxRetries = _settings.MaxRetries }, cancellationToken: ct));
    }

    public async Task<DateTime?> GetLastCallTimeAsync(CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        const string sql = @"
            SELECT MAX(UltimoMomento) FROM (
                SELECT MAX(RT13_CALL_DATETIME) AS UltimoMomento FROM dbo.RT13_NKE WITH (NOLOCK)
                UNION ALL
                SELECT MAX(MOMENTO_CHIAMATA) AS UltimoMomento FROM dbo.RT13_NKE_LOG_DETAIL_GEMINI WITH (NOLOCK)
            ) t;";

        return await conn.ExecuteScalarAsync<DateTime?>(new CommandDefinition(sql, cancellationToken: ct));
    }

    public async Task RecordAttemptAsync(Guid mg87Guid, NkeCallResult result, int currentAttempts, CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        if (conn.State != ConnectionState.Open) conn.Open();

        const string updateSql = @"
            UPDATE dbo.RT13_NKE
            SET RT13_NUM_TENTATIVI = RT13_NUM_TENTATIVI + 1,
                RT13_CALL_DATETIME = GETDATE()
            WHERE MG87_GUID = @mg87Guid;";

        const string logSql = @"
            INSERT INTO dbo.RT13_NKE_LOG_DETAIL_GEMINI (
                MG87_GUID, MOMENTO_CHIAMATA, LATENCY_MS, HTTP_STATUS,
                RICHIESTA_JSON, RISPOSTA_JSON, ESITO_GENERATO, MESSAGGIO_ERRORE,
                OPERATORE, IP_CLIENT
            ) VALUES (
                @mg87Guid, GETDATE(), @LatencyMs, @HttpStatus,
                @RequestJson, @ResponseJson, 0, @ErrorMessage,
                'DISPATCHER_RETRY_' + CAST(@currentAttempts AS VARCHAR), '127.0.0.1'
            );";

        await conn.ExecuteAsync(new CommandDefinition(updateSql, new { mg87Guid }, cancellationToken: ct));
        await conn.ExecuteAsync(new CommandDefinition(logSql, new 
        { 
            mg87Guid, 
            result.LatencyMs, 
            result.HttpStatus, 
            result.RequestJson, 
            result.ResponseJson, 
            result.ErrorMessage,
            currentAttempts
        }, cancellationToken: ct));
    }

    public async Task CompleteSuccessAsync(Guid mg87Guid, NkeCallResult result, CancellationToken ct = default)
    {
        using var conn = (SqlConnection)CreateConnection();
        await conn.OpenAsync(ct);
        using var tran = conn.BeginTransaction();

        try
        {
            // 1. Aggiorna stato file generato su RT13_NKE prima della cancellazione
            const string updateSql = @"
                UPDATE dbo.RT13_NKE
                SET RT13_FILE_GENERATO = 1,
                    RT13_CALL_DATETIME = GETDATE()
                WHERE MG87_GUID = @mg87Guid;";
            await conn.ExecuteAsync(updateSql, new { mg87Guid }, tran);

            // 2. Cancella riga (innesca trigger RT13_AFTER_DELETE che archivia in RT13_NKE_LOG con RT13_FILE_GENERATO = 1)
            const string deleteSql = "DELETE FROM dbo.RT13_NKE WHERE MG87_GUID = @mg87Guid;";
            await conn.ExecuteAsync(deleteSql, new { mg87Guid }, tran);

            // 3. Storicizza nel log di audit avanzato
            const string logSql = @"
                INSERT INTO dbo.RT13_NKE_LOG_DETAIL_GEMINI (
                    MG87_GUID, MOMENTO_CHIAMATA, LATENCY_MS, HTTP_STATUS,
                    RICHIESTA_JSON, RISPOSTA_JSON, ESITO_GENERATO, MESSAGGIO_ERRORE,
                    OPERATORE, IP_CLIENT
                ) VALUES (
                    @mg87Guid, GETDATE(), @LatencyMs, @HttpStatus,
                    @RequestJson, @ResponseJson, 1, NULL,
                    'DISPATCHER_AUTO', '127.0.0.1'
                );";
            await conn.ExecuteAsync(logSql, new 
            { 
                mg87Guid, 
                result.LatencyMs, 
                result.HttpStatus, 
                result.RequestJson, 
                result.ResponseJson 
            }, tran);

            tran.Commit();
        }
        catch
        {
            tran.Rollback();
            throw;
        }
    }

    public async Task MoveToDeadLetterAsync(Guid mg87Guid, NkeCallResult result, CancellationToken ct = default)
    {
        using var conn = (SqlConnection)CreateConnection();
        await conn.OpenAsync(ct);
        using var tran = conn.BeginTransaction();

        try
        {
            // 1. Marca come non generato
            const string updateSql = @"
                UPDATE dbo.RT13_NKE
                SET RT13_FILE_GENERATO = 0,
                    RT13_CALL_DATETIME = GETDATE()
                WHERE MG87_GUID = @mg87Guid;";
            await conn.ExecuteAsync(updateSql, new { mg87Guid }, tran);

            // 2. Cancella dalla coda attiva per sbloccare la FIFO
            const string deleteSql = "DELETE FROM dbo.RT13_NKE WHERE MG87_GUID = @mg87Guid;";
            await conn.ExecuteAsync(deleteSql, new { mg87Guid }, tran);

            // 3. Registra nel log dettagliato l'errore definitivo
            const string logSql = @"
                INSERT INTO dbo.RT13_NKE_LOG_DETAIL_GEMINI (
                    MG87_GUID, MOMENTO_CHIAMATA, LATENCY_MS, HTTP_STATUS,
                    RICHIESTA_JSON, RISPOSTA_JSON, ESITO_GENERATO, MESSAGGIO_ERRORE,
                    OPERATORE, IP_CLIENT
                ) VALUES (
                    @mg87Guid, GETDATE(), @LatencyMs, @HttpStatus,
                    @RequestJson, @ResponseJson, 0, @ErrorMessage,
                    'DISPATCHER_DEAD_LETTER', '127.0.0.1'
                );";
            await conn.ExecuteAsync(logSql, new 
            { 
                mg87Guid, 
                result.LatencyMs, 
                result.HttpStatus, 
                result.RequestJson, 
                result.ResponseJson, 
                ErrorMessage = result.ErrorMessage ?? "Raggiunto limite massimo di 3 tentativi falliti"
            }, tran);

            tran.Commit();
        }
        catch
        {
            tran.Rollback();
            throw;
        }
    }

    public async Task<IEnumerable<QueueItemDto>> GetActiveQueueAsync(CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        const string sql = @"
            SELECT 
                q.MG87_GUID             AS [Guid],
                q.RT13_CODART_MG66      AS [CodiceArticolo],
                q.RT13_OPZIONE_MG5E     AS [Variante],
                q.DESCRIZIONE           AS [Descrizione],
                q.RT13_INSERT_DATETIME  AS [DataInserimento],
                q.RT13_CALL_DATETIME    AS [UltimaChiamata],
                q.RT13_NUM_TENTATIVI    AS [Tentativi],
                q.RT13_SOVRASCRIVI      AS [Sovrascrivi],
                STRING_AGG(CONCAT('CO ', d.DO11_NUMDOC, ' R.', d.DO30_PROGRIGA), ', ') WITHIN GROUP (ORDER BY d.DO11_NUMDOC, d.DO30_PROGRIGA) AS [DocumentiCollegati],
                STRING_AGG(d.RAGIONE_SOCIALE, ', ') AS [ClientiCollegati]
            FROM dbo.RT13_NKE q WITH (NOLOCK)
            LEFT JOIN dbo.RT13_NKE_DOCS_GEMINI d WITH (NOLOCK)
                ON q.MG87_GUID = d.MG87_GUID
            GROUP BY 
                q.MG87_GUID, q.RT13_CODART_MG66, q.RT13_OPZIONE_MG5E, q.DESCRIZIONE,
                q.RT13_INSERT_DATETIME, q.RT13_CALL_DATETIME, q.RT13_NUM_TENTATIVI, q.RT13_SOVRASCRIVI
            ORDER BY q.RT13_INSERT_DATETIME ASC;";

        return await conn.QueryAsync<QueueItemDto>(new CommandDefinition(sql, cancellationToken: ct));
    }

    public async Task<IEnumerable<LogItemDto>> GetLogsAsync(int page = 1, int pageSize = 50, string? search = null, CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        var offset = (page - 1) * pageSize;

        string searchClause = string.IsNullOrWhiteSpace(search)
            ? ""
            : "AND (l.MG87_GUID LIKE @Search OR d.DO11_NUMDOC LIKE @SearchNum OR d.RAGIONE_SOCIALE LIKE @Search OR d.DO30_CODART_MG66 LIKE @Search)";

        int.TryParse(search, out int searchNum);

        string sql = $@"
            SELECT 
                l.ID_LOG                 AS [IdLog],
                l.MG87_GUID              AS [Guid],
                l.MOMENTO_CHIAMATA       AS [DataOra],
                l.LATENCY_MS             AS [LatenzaMs],
                l.HTTP_STATUS            AS [HttpStatus],
                l.ESITO_GENERATO         AS [EsitoGenerato],
                l.MESSAGGIO_ERRORE       AS [MessaggioErrore],
                l.OPERATORE              AS [Operatore],
                l.IP_CLIENT              AS [IpClient],
                ISNULL(MAX(d.DO30_CODART_MG66), '') AS [CodiceArticolo],
                ISNULL(MAX(d.DO30_OPZIONE_MG5E), '') AS [Variante],
                STRING_AGG(CONCAT('CO ', d.DO11_NUMDOC, ' R.', d.DO30_PROGRIGA), ', ') WITHIN GROUP (ORDER BY d.DO11_NUMDOC, d.DO30_PROGRIGA) AS [DocumentiCollegati],
                STRING_AGG(d.RAGIONE_SOCIALE, ', ') AS [ClientiCollegati]
            FROM dbo.RT13_NKE_LOG_DETAIL_GEMINI l WITH (NOLOCK)
            LEFT JOIN dbo.RT13_NKE_DOCS_GEMINI d WITH (NOLOCK)
                ON l.MG87_GUID = d.MG87_GUID
            WHERE 1=1 {searchClause}
            GROUP BY 
                l.ID_LOG, l.MG87_GUID, l.MOMENTO_CHIAMATA, l.LATENCY_MS,
                l.HTTP_STATUS, l.ESITO_GENERATO, l.MESSAGGIO_ERRORE, l.OPERATORE, l.IP_CLIENT
            ORDER BY l.MOMENTO_CHIAMATA DESC
            OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;";

        return await conn.QueryAsync<LogItemDto>(new CommandDefinition(sql, new 
        { 
            Offset = offset, 
            PageSize = pageSize, 
            Search = $"%{search}%", 
            SearchNum = searchNum > 0 ? searchNum : -1 
        }, cancellationToken: ct));
    }

    public async Task<KpiSummaryDto> GetKpiSummaryAsync(CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        const string sql = @"
            SELECT 
                (SELECT COUNT(*) FROM dbo.RT13_NKE WITH (NOLOCK)) AS [InCoda],
                (SELECT COUNT(*) FROM dbo.RT13_NKE_LOG_DETAIL_GEMINI WITH (NOLOCK) 
                 WHERE MOMENTO_CHIAMATA >= DATEADD(HOUR, -24, GETDATE()) AND ESITO_GENERATO = 1) AS [Inviati24h],
                (SELECT COUNT(*) FROM dbo.RT13_NKE_LOG_DETAIL_GEMINI WITH (NOLOCK) 
                 WHERE MOMENTO_CHIAMATA >= DATEADD(HOUR, -24, GETDATE()) AND ESITO_GENERATO = 0) AS [Errori24h],
                (SELECT ISNULL(AVG(CAST(LATENCY_MS AS FLOAT)), 0) FROM dbo.RT13_NKE_LOG_DETAIL_GEMINI WITH (NOLOCK) 
                 WHERE MOMENTO_CHIAMATA >= DATEADD(HOUR, -24, GETDATE()) AND LATENCY_MS > 0) AS [LatenzaMediaMs],
                (SELECT MAX(MOMENTO_CHIAMATA) FROM dbo.RT13_NKE_LOG_DETAIL_GEMINI WITH (NOLOCK)) AS [UltimaChiamata];";

        return await conn.QueryFirstOrDefaultAsync<KpiSummaryDto>(new CommandDefinition(sql, cancellationToken: ct)) ?? new KpiSummaryDto();
    }

    public async Task<NkePayloadDetailDto?> GetPayloadDetailAsync(long logId, CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        const string sql = @"
            SELECT 
                ID_LOG           AS [IdLog],
                MG87_GUID        AS [Guid],
                MOMENTO_CHIAMATA AS [DataOra],
                RICHIESTA_JSON   AS [RichiestaJson],
                RISPOSTA_JSON    AS [RispostaJson],
                MESSAGGIO_ERRORE AS [MessaggioErrore]
            FROM dbo.RT13_NKE_LOG_DETAIL_GEMINI WITH (NOLOCK)
            WHERE ID_LOG = @logId;";

        return await conn.QueryFirstOrDefaultAsync<NkePayloadDetailDto>(new CommandDefinition(sql, new { logId }, cancellationToken: ct));
    }

    public async Task<IEnumerable<dynamic>> ExecuteDryRunSimulationAsync(int? numDoc, short? annoDoc, string? sezDoc, int giorniIndietro, CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        var p = new DynamicParameters();
        p.Add("@ModalitaDryRun", 1);
        p.Add("@NumDoc", numDoc);
        p.Add("@AnnoDoc", annoDoc);
        p.Add("@SezDoc", sezDoc);
        p.Add("@GiorniIndietro", giorniIndietro);
        p.Add("@ForzaReinvio", 0);

        using var multi = await conn.QueryMultipleAsync(new CommandDefinition(
            "dbo.SPSO_NKE_ALIMENTA_CODA_GEMINI",
            p,
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct
        ));

        // Il secondo resultset contiene il prospetto riga per riga
        var summary = await multi.ReadAsync<dynamic>();
        var rows = await multi.ReadAsync<dynamic>();
        return rows;
    }

    public async Task<int> ExecuteOrderForceAsync(int numDoc, short? annoDoc, string? sezDoc, bool forzaReinvio, string operatore, string ipClient, CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        var p = new DynamicParameters();
        p.Add("@ModalitaDryRun", 0);
        p.Add("@NumDoc", numDoc);
        p.Add("@AnnoDoc", annoDoc);
        p.Add("@SezDoc", sezDoc);
        p.Add("@ForzaReinvio", forzaReinvio ? 1 : 0);

        var result = await conn.QueryFirstOrDefaultAsync<dynamic>(new CommandDefinition(
            "dbo.SPSO_NKE_ALIMENTA_CODA_GEMINI",
            p,
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct
        ));

        // Registra traccia di audit manuale
        const string auditSql = @"
            INSERT INTO dbo.RT13_NKE_LOG_DETAIL_GEMINI (
                MG87_GUID, MOMENTO_CHIAMATA, LATENCY_MS, HTTP_STATUS,
                RICHIESTA_JSON, RISPOSTA_JSON, ESITO_GENERATO, MESSAGGIO_ERRORE,
                OPERATORE, IP_CLIENT
            ) VALUES (
                NEWID(), GETDATE(), 0, 200,
                @Json, 'Forzatura manuale ordine inviata a coda', 1, NULL,
                @operatore, @ipClient
            );";

        string forceAuditJson = $"{{\"Azione\":\"ForzaturaOrdine\",\"NumDoc\":{numDoc},\"ForzaReinvio\":{forzaReinvio.ToString().ToLower()}}}";
        await conn.ExecuteAsync(new CommandDefinition(auditSql, new { Json = forceAuditJson, operatore, ipClient }, cancellationToken: ct));

        if (result is IDictionary<string, object> dict && dict.TryGetValue("Nuove Richieste Accodate in RT13_NKE", out var val) && val != null)
        {
            return Convert.ToInt32(val);
        }
        return 0;
    }

    public async Task<int> ExecuteMassiveIngestionAsync(int giorniIndietro, CancellationToken ct = default)
    {
        using var conn = CreateConnection();
        var p = new DynamicParameters();
        p.Add("@ModalitaDryRun", 0);
        p.Add("@NumDoc", null);
        p.Add("@GiorniIndietro", giorniIndietro);
        p.Add("@ForzaReinvio", 0);

        var result = await conn.QueryFirstOrDefaultAsync<dynamic>(new CommandDefinition(
            "dbo.SPSO_NKE_ALIMENTA_CODA_GEMINI",
            p,
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct
        ));

        if (result is IDictionary<string, object> dict && dict.TryGetValue("Nuove Richieste Accodate in RT13_NKE", out var val) && val != null)
        {
            return Convert.ToInt32(val);
        }
        return 0;
    }
}
