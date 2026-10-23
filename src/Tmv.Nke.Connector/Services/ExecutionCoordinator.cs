using Microsoft.Extensions.Logging;

namespace Tmv.Nke.Connector.Services;

public class ExecutionCoordinator : IExecutionCoordinator
{
    private readonly SemaphoreSlim _semaphore = new(1, 1);
    private readonly ILogger<ExecutionCoordinator> _logger;
    private int _isBusy = 0;

    public ExecutionCoordinator(ILogger<ExecutionCoordinator> logger)
    {
        _logger = logger;
    }

    public bool IsBusy => Interlocked.CompareExchange(ref _isBusy, 0, 0) == 1;

    public async Task<T> ExecuteExclusivelyAsync<T>(Func<Task<T>> action, TimeSpan timeout, CancellationToken ct = default)
    {
        _logger.LogDebug("Richiesta acquisizione lock esclusivo su SPSO_NKE_ALIMENTA_CODA_GEMINI...");
        var acquired = await _semaphore.WaitAsync(timeout, ct);
        if (!acquired)
        {
            throw new TimeoutException($"Impossibile acquisire il lock per l'alimentazione coda entro {timeout.TotalSeconds}s (un'altra elaborazione è già in corso).");
        }

        Interlocked.Exchange(ref _isBusy, 1);
        try
        {
            return await action();
        }
        finally
        {
            Interlocked.Exchange(ref _isBusy, 0);
            _semaphore.Release();
            _logger.LogDebug("Lock esclusivo rilasciato.");
        }
    }

    public async Task ExecuteExclusivelyAsync(Func<Task> action, TimeSpan timeout, CancellationToken ct = default)
    {
        await ExecuteExclusivelyAsync(async () =>
        {
            await action();
            return true;
        }, timeout, ct);
    }
}
