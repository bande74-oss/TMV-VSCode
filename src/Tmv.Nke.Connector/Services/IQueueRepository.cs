using Tmv.Nke.Connector.Models;

namespace Tmv.Nke.Connector.Services;

public interface IQueueRepository
{
    Task<QueueItem?> GetNextPendingItemAsync(CancellationToken ct = default);
    Task<DateTime?> GetLastCallTimeAsync(CancellationToken ct = default);
    Task RecordAttemptAsync(Guid mg87Guid, NkeCallResult result, int currentAttempts, CancellationToken ct = default);
    Task CompleteSuccessAsync(Guid mg87Guid, NkeCallResult result, CancellationToken ct = default);
    Task MoveToDeadLetterAsync(Guid mg87Guid, NkeCallResult result, CancellationToken ct = default);
    Task<IEnumerable<QueueItemDto>> GetActiveQueueAsync(CancellationToken ct = default);
    Task<IEnumerable<LogItemDto>> GetLogsAsync(int page = 1, int pageSize = 50, string? search = null, CancellationToken ct = default);
    Task<KpiSummaryDto> GetKpiSummaryAsync(CancellationToken ct = default);
    Task<NkePayloadDetailDto?> GetPayloadDetailAsync(long logId, CancellationToken ct = default);
    Task<IEnumerable<dynamic>> ExecuteDryRunSimulationAsync(int? numDoc, short? annoDoc, string? sezDoc, int giorniIndietro, CancellationToken ct = default);
    Task<int> ExecuteOrderForceAsync(int numDoc, short? annoDoc, string? sezDoc, bool forzaReinvio, string operatore, string ipClient, CancellationToken ct = default);
    Task<int> ExecuteMassiveIngestionAsync(int giorniIndietro, CancellationToken ct = default);
}
