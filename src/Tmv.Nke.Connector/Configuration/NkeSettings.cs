namespace Tmv.Nke.Connector.Configuration;

public class NkeSettings
{
    public string ConnectionString { get; set; } = string.Empty;
    public string NkeApiEndpoint { get; set; } = "http://192.168.1.138:7171/configure";
    public int CooldownSeconds { get; set; } = 30;
    public int HttpTimeoutSeconds { get; set; } = 10;
    public int MaxRetries { get; set; } = 3;
    public int MassiveScanIntervalSeconds { get; set; } = 600; // 10 minuti
    public int MassiveScanLookbackDays { get; set; } = 15;
    public int Port { get; set; } = 5050;
}

