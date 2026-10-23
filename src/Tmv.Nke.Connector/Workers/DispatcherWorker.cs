using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Tmv.Nke.Connector.Configuration;
using Tmv.Nke.Connector.Models;
using Tmv.Nke.Connector.Services;

namespace Tmv.Nke.Connector.Workers;

public class DispatcherWorker : BackgroundService
{
    private readonly IQueueRepository _queueRepository;
    private readonly INkeApiClient _nkeApiClient;
    private readonly NkeSettings _settings;
    private readonly ILogger<DispatcherWorker> _logger;

    public DispatcherWorker(
        IQueueRepository queueRepository,
        INkeApiClient nkeApiClient,
        IOptions<NkeSettings> options,
        ILogger<DispatcherWorker> logger)
    {
        _queueRepository = queueRepository;
        _nkeApiClient = nkeApiClient;
        _settings = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Avvio DispatcherWorker Coda NKE (Cooldown: {Cooldown}s, MaxRetries: {Retries})...", 
            _settings.CooldownSeconds, _settings.MaxRetries);

        // Breve pausa all'avvio per consentire all'host di completare l'inizializzazione
        await Task.Delay(2000, stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // 1. Verifica Cooldown rispetto all'ultima chiamata inviata
                var lastCall = await _queueRepository.GetLastCallTimeAsync(stoppingToken);
                if (lastCall.HasValue)
                {
                    var elapsed = DateTime.Now - lastCall.Value;
                    var remainingSeconds = _settings.CooldownSeconds - elapsed.TotalSeconds;

                    if (remainingSeconds > 0)
                    {
                        var waitMs = Math.Min((int)(remainingSeconds * 1000), 5000);
                        if (waitMs > 500)
                        {
                            _logger.LogDebug("In attesa cooldown NKE ({Remaining:F1}s rimanenti)...", remainingSeconds);
                            await Task.Delay(waitMs, stoppingToken);
                            continue;
                        }
                    }
                }

                // 2. Prelievo del prossimo elemento pendente dalla coda
                var item = await _queueRepository.GetNextPendingItemAsync(stoppingToken);
                if (item == null)
                {
                    // Coda vuota: attesa prima del prossimo controllo
                    await Task.Delay(10000, stoppingToken);
                    continue;
                }

                _logger.LogInformation("Processamento elemento coda: Articolo {Art}, Variante {Var}, GUID {Guid} (Tentativo {Tentativo}/{Max})",
                    item.RT13_CODART_MG66.Trim(), item.RT13_OPZIONE_MG5E.Trim(), item.MG87_GUID, item.RT13_NUM_TENTATIVI + 1, _settings.MaxRetries);

                // 3. Costruzione payload deterministico conforme a NKE
                var payload = NkeRequestPayload.Create(item.MG87_GUID, item.RT13_CODART_MG66, item.RT13_OPZIONE_MG5E);

                // 4. Invio asincrono a WebAPI NKE
                var result = await _nkeApiClient.SendConfigurationAsync(payload, stoppingToken);

                // 5. Gestione esito e avanzamento stato
                if (result.Success)
                {
                    await _queueRepository.CompleteSuccessAsync(item.MG87_GUID, result, stoppingToken);
                    _logger.LogInformation("Disegno generato con successo e completato per GUID {Guid}", item.MG87_GUID);
                }
                else
                {
                    int nextAttempt = item.RT13_NUM_TENTATIVI + 1;
                    if (nextAttempt >= _settings.MaxRetries)
                    {
                        _logger.LogError("Raggiunti {Max} tentativi falliti per GUID {Guid}. Spostamento in Dead-Letter.", _settings.MaxRetries, item.MG87_GUID);
                        await _queueRepository.MoveToDeadLetterAsync(item.MG87_GUID, result, stoppingToken);
                    }
                    else
                    {
                        _logger.LogWarning("Tentativo {Tentativo} fallito per GUID {Guid}: {Error}. Verrà ritentato al prossimo ciclo.",
                            nextAttempt, item.MG87_GUID, result.ErrorMessage);
                        await _queueRepository.RecordAttemptAsync(item.MG87_GUID, result, nextAttempt, stoppingToken);
                    }
                }

                // Pausa post-chiamata per rispettare la serializzazione Inventor
                await Task.Delay(TimeSpan.FromSeconds(_settings.CooldownSeconds), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Errore non gestito nel ciclo del DispatcherWorker. Ripresa tra 10 secondi.");
                await Task.Delay(10000, stoppingToken);
            }
        }

        _logger.LogInformation("DispatcherWorker terminato regolarmente.");
    }
}
