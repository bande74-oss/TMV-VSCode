using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Tmv.Nke.Connector.Configuration;
using Tmv.Nke.Connector.Services;

namespace Tmv.Nke.Connector.Workers;

public class MassiveIngestionWorker : BackgroundService
{
    private readonly IQueueRepository _queueRepository;
    private readonly IExecutionCoordinator _coordinator;
    private readonly NkeSettings _settings;
    private readonly ILogger<MassiveIngestionWorker> _logger;

    public MassiveIngestionWorker(
        IQueueRepository queueRepository,
        IExecutionCoordinator coordinator,
        IOptions<NkeSettings> options,
        ILogger<MassiveIngestionWorker> logger)
    {
        _queueRepository = queueRepository;
        _coordinator = coordinator;
        _settings = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        int intervalSeconds = _settings.MassiveScanIntervalSeconds > 60 ? _settings.MassiveScanIntervalSeconds : 600;
        int lookbackDays = _settings.MassiveScanLookbackDays > 0 ? _settings.MassiveScanLookbackDays : 15;

        _logger.LogInformation("Avvio MassiveIngestionWorker (Intervallo: {Interval}s, Lookback: {Days} giorni)...",
            intervalSeconds, lookbackDays);

        // Attesa iniziale di 15 secondi all'avvio
        await Task.Delay(15000, stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                _logger.LogInformation("Avvio scansione massiva ordini per alimentazione coda NKE...");

                var newQueued = await _coordinator.ExecuteExclusivelyAsync(async () =>
                {
                    return await _queueRepository.ExecuteMassiveIngestionAsync(lookbackDays, stoppingToken);
                }, TimeSpan.FromSeconds(30), stoppingToken);

                _logger.LogInformation("Scansione massiva completata: {Count} nuove richieste accodate in RT13_NKE.", newQueued);
            }
            catch (TimeoutException tex)
            {
                _logger.LogWarning("Scansione massiva saltata per lock occupato: {Msg}", tex.Message);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Errore durante l'esecuzione della scansione massiva.");
            }

            // Attesa del prossimo intervallo schedulato
            await Task.Delay(TimeSpan.FromSeconds(intervalSeconds), stoppingToken);
        }

        _logger.LogInformation("MassiveIngestionWorker arrestato.");
    }
}
