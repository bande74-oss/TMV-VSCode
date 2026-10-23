using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Tmv.Nke.Connector.Models;
using Tmv.Nke.Connector.Services;

namespace Tmv.Nke.Connector.Controllers;

[ApiController]
[Route("api")]
public class MonitorApiController : ControllerBase
{
    private static readonly DateTime StartTime = DateTime.Now;
    private readonly IQueueRepository _queueRepository;
    private readonly INkeApiClient _nkeApiClient;
    private readonly IExecutionCoordinator _coordinator;
    private readonly ILogger<MonitorApiController> _logger;

    public MonitorApiController(
        IQueueRepository queueRepository,
        INkeApiClient nkeApiClient,
        IExecutionCoordinator coordinator,
        ILogger<MonitorApiController> logger)
    {
        _queueRepository = queueRepository;
        _nkeApiClient = nkeApiClient;
        _coordinator = coordinator;
        _logger = logger;
    }

    [HttpGet("status")]
    public async Task<ActionResult<ApiResponse<ServiceStatusDto>>> GetStatus(CancellationToken ct)
    {
        bool nkeHealthy = await _nkeApiClient.CheckHealthAsync(ct);
        bool dbConnected = false;

        try
        {
            await _queueRepository.GetLastCallTimeAsync(ct);
            dbConnected = true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Errore connessione database durante health check.");
        }

        var status = new ServiceStatusDto
        {
            Uptime = DateTime.Now - StartTime,
            DatabaseConnected = dbConnected,
            NkeReachable = nkeHealthy,
            IsCoordinatorBusy = _coordinator.IsBusy,
            ServerTime = DateTime.Now
        };

        return Ok(ApiResponse<ServiceStatusDto>.Ok(status));
    }

    [HttpGet("kpis")]
    public async Task<ActionResult<ApiResponse<KpiSummaryDto>>> GetKpis(CancellationToken ct)
    {
        var kpis = await _queueRepository.GetKpiSummaryAsync(ct);
        kpis.IsNkeHealthy = await _nkeApiClient.CheckHealthAsync(ct);
        return Ok(ApiResponse<KpiSummaryDto>.Ok(kpis));
    }

    [HttpGet("queue")]
    public async Task<ActionResult<ApiResponse<IEnumerable<QueueItemDto>>>> GetQueue(CancellationToken ct)
    {
        var queue = await _queueRepository.GetActiveQueueAsync(ct);
        return Ok(ApiResponse<IEnumerable<QueueItemDto>>.Ok(queue));
    }

    [HttpGet("logs")]
    public async Task<ActionResult<ApiResponse<IEnumerable<LogItemDto>>>> GetLogs(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string? search = null,
        CancellationToken ct = default)
    {
        if (page < 1) page = 1;
        if (pageSize < 1 || pageSize > 200) pageSize = 50;

        var logs = await _queueRepository.GetLogsAsync(page, pageSize, search, ct);
        return Ok(ApiResponse<IEnumerable<LogItemDto>>.Ok(logs));
    }

    [HttpGet("logs/{id}/payload")]
    public async Task<ActionResult<ApiResponse<NkePayloadDetailDto>>> GetLogPayload(long id, CancellationToken ct)
    {
        var payload = await _queueRepository.GetPayloadDetailAsync(id, ct);
        if (payload == null)
        {
            return NotFound(ApiResponse<NkePayloadDetailDto>.Fail($"Record di log con ID {id} non trovato."));
        }
        return Ok(ApiResponse<NkePayloadDetailDto>.Ok(payload));
    }

    [HttpPost("orders/simulate")]
    public async Task<ActionResult<ApiResponse<IEnumerable<dynamic>>>> SimulateOrder([FromBody] SimulateOrderRequest req, CancellationToken ct)
    {
        try
        {
            _logger.LogInformation("Richiesta simulazione Dry-Run per Ordine {NumDoc}", req.NumDoc);
            var result = await _coordinator.ExecuteExclusivelyAsync(async () =>
            {
                return await _queueRepository.ExecuteDryRunSimulationAsync(req.NumDoc, req.AnnoDoc, req.SezDoc, req.GiorniIndietro, ct);
            }, TimeSpan.FromSeconds(30), ct);

            return Ok(ApiResponse<IEnumerable<dynamic>>.Ok(result, "Simulazione Dry-Run eseguita con successo."));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Errore durante la simulazione dell'ordine {NumDoc}", req.NumDoc);
            return StatusCode(500, ApiResponse<IEnumerable<dynamic>>.Fail(ex.Message));
        }
    }

    [HttpPost("orders/force")]
    public async Task<ActionResult<ApiResponse<int>>> ForceOrder([FromBody] ForceOrderRequest req, CancellationToken ct)
    {
        if (req.NumDoc <= 0)
        {
            return BadRequest(ApiResponse<int>.Fail("Il numero di conferma d'ordine è obbligatorio."));
        }

        string ipClient = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "127.0.0.1";
        string operatore = string.IsNullOrWhiteSpace(req.Operatore) ? "UfficioTecnico" : req.Operatore.Trim();

        try
        {
            _logger.LogInformation("Forzatura manuale richiesta da operatore {Op} (IP {IP}) per Ordine {NumDoc} (Sovrascrivi: {Over})",
                operatore, ipClient, req.NumDoc, req.ForzaReinvio);

            int queued = await _coordinator.ExecuteExclusivelyAsync(async () =>
            {
                return await _queueRepository.ExecuteOrderForceAsync(req.NumDoc, req.AnnoDoc, req.SezDoc, req.ForzaReinvio, operatore, ipClient, ct);
            }, TimeSpan.FromSeconds(30), ct);

            return Ok(ApiResponse<int>.Ok(queued, $"Operazione completata: {queued} nuove richieste accodate in RT13_NKE."));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Errore durante la forzatura dell'ordine {NumDoc}", req.NumDoc);
            return StatusCode(500, ApiResponse<int>.Fail(ex.Message));
        }
    }
}
