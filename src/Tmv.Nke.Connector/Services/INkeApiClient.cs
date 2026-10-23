using Tmv.Nke.Connector.Models;

namespace Tmv.Nke.Connector.Services;

public interface INkeApiClient
{
    Task<NkeCallResult> SendConfigurationAsync(NkeRequestPayload payload, CancellationToken ct = default);
    Task<bool> CheckHealthAsync(CancellationToken ct = default);
}

