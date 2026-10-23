using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Tmv.Nke.Connector.Configuration;
using Tmv.Nke.Connector.Models;

namespace Tmv.Nke.Connector.Services;

public class NkeApiClient : INkeApiClient
{
    private readonly HttpClient _httpClient;
    private readonly NkeSettings _settings;
    private readonly ILogger<NkeApiClient> _logger;

    public NkeApiClient(HttpClient httpClient, IOptions<NkeSettings> options, ILogger<NkeApiClient> logger)
    {
        _httpClient = httpClient;
        _settings = options.Value;
        _logger = logger;

        _httpClient.Timeout = TimeSpan.FromSeconds(_settings.HttpTimeoutSeconds > 0 ? _settings.HttpTimeoutSeconds : 10);
        _httpClient.DefaultRequestHeaders.Accept.Clear();
        _httpClient.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    }

    public async Task<NkeCallResult> SendConfigurationAsync(NkeRequestPayload payload, CancellationToken ct = default)
    {
        var result = new NkeCallResult();
        var sw = Stopwatch.StartNew();

        string jsonPayload = JsonSerializer.Serialize(payload);
        result.RequestJson = jsonPayload;

        try
        {
            using var content = new StringContent(jsonPayload, Encoding.UTF8, "application/json");
            _logger.LogInformation("Invio richiesta NKE verso {Endpoint} per GUID {Guid}...", _settings.NkeApiEndpoint, payload.Id);

            using var response = await _httpClient.PostAsync(_settings.NkeApiEndpoint, content, ct);
            sw.Stop();
            result.LatencyMs = (int)sw.ElapsedMilliseconds;
            result.HttpStatus = (int)response.StatusCode;

            string responseBody = await response.Content.ReadAsStringAsync(ct);
            result.ResponseJson = responseBody;

            if (response.IsSuccessStatusCode)
            {
                // Analisi semantica del body: intercetta errori applicativi iLogic anche con HTTP 200
                if (ContainsApplicationError(responseBody, out var semanticError))
                {
                    result.Success = false;
                    result.ErrorMessage = $"NKE 200 OK con errore applicativo nel body: {semanticError}";
                    _logger.LogWarning("Risposta NKE HTTP 200 ma contenente errore applicativo: {Error}", semanticError);
                }
                else
                {
                    result.Success = true;
                    _logger.LogInformation("Generazione CAD NKE completata con successo in {Elapsed} ms (HTTP {Status})", result.LatencyMs, result.HttpStatus);
                }
            }
            else
            {
                result.Success = false;
                result.ErrorMessage = $"HTTP {result.HttpStatus}: {response.ReasonPhrase} - {responseBody}";
                _logger.LogError("Errore HTTP da NKE: {Status} - {Reason}", result.HttpStatus, response.ReasonPhrase);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            _logger.LogInformation("Chiamata NKE annullata per arresto del servizio.");
            throw;
        }
        catch (Exception tex) when (tex is TaskCanceledException || tex is TimeoutException)
        {
            sw.Stop();
            result.LatencyMs = (int)sw.ElapsedMilliseconds;
            result.IsTimeout = true;
            result.HttpStatus = 408; // Request Timeout
            result.Success = false;
            result.ErrorMessage = $"Timeout chiamata WebAPI NKE dopo {result.LatencyMs} ms: {tex.Message}";
            _logger.LogError("Timeout chiamata NKE per GUID {Guid} dopo {Elapsed} ms", payload.Id, result.LatencyMs);
        }
        catch (Exception ex)
        {
            sw.Stop();
            result.LatencyMs = (int)sw.ElapsedMilliseconds;
            result.Success = false;
            result.HttpStatus = 500;
            result.ErrorMessage = $"Eccezione di comunicazione con NKE: {ex.Message}";
            _logger.LogError(ex, "Eccezione durante la chiamata NKE per GUID {Guid}", payload.Id);
        }

        return result;
    }

    public async Task<bool> CheckHealthAsync(CancellationToken ct = default)
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(1500));
            using var req = new HttpRequestMessage(HttpMethod.Get, _settings.NkeApiEndpoint);
            using var resp = await _httpClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool ContainsApplicationError(string json, out string errorMessage)
    {
        errorMessage = string.Empty;
        if (string.IsNullOrWhiteSpace(json)) return false;

        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            if (root.ValueKind == JsonValueKind.Object)
            {
                if (root.TryGetProperty("error", out var errProp) || root.TryGetProperty("Error", out errProp))
                {
                    errorMessage = errProp.ToString();
                    return true;
                }

                if (root.TryGetProperty("success", out var succProp) && succProp.ValueKind == JsonValueKind.False)
                {
                    errorMessage = root.TryGetProperty("message", out var msgProp) ? msgProp.GetString() ?? "Success is false" : "Success is false";
                    return true;
                }

                if (root.TryGetProperty("exception", out var exProp) || root.TryGetProperty("Exception", out exProp))
                {
                    errorMessage = exProp.ToString();
                    return true;
                }
            }
        }
        catch
        {
            // Se non è un JSON valido ma testo semplice, controlla se contiene parole chiave di errore
            if (json.Contains("exception", StringComparison.OrdinalIgnoreCase) ||
                json.Contains("error", StringComparison.OrdinalIgnoreCase) ||
                json.Contains("failed", StringComparison.OrdinalIgnoreCase))
            {
                errorMessage = json.Length > 200 ? json.Substring(0, 200) : json;
                return true;
            }
        }

        return false;
    }
}

