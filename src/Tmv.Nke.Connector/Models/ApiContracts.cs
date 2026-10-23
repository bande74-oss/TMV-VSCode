namespace Tmv.Nke.Connector.Models;

public class SimulateOrderRequest
{
    public int? NumDoc { get; set; }
    public short? AnnoDoc { get; set; }
    public string? SezDoc { get; set; }
    public int GiorniIndietro { get; set; } = 15;
}

public class ForceOrderRequest
{
    public int NumDoc { get; set; }
    public short? AnnoDoc { get; set; }
    public string? SezDoc { get; set; }
    public bool ForzaReinvio { get; set; }
    public string Operatore { get; set; } = "UfficioTecnico";
}

public class ServiceStatusDto
{
    public string ServiceName { get; set; } = "TMV.NKE.Service";
    public string Version { get; set; } = "1.0.0";
    public TimeSpan Uptime { get; set; }
    public bool DatabaseConnected { get; set; }
    public bool NkeReachable { get; set; }
    public bool IsCoordinatorBusy { get; set; }
    public DateTime ServerTime { get; set; } = DateTime.Now;
}

public class ApiResponse<T>
{
    public bool Success { get; set; }
    public T? Data { get; set; }
    public string? Message { get; set; }

    public static ApiResponse<T> Ok(T data, string? message = null) => new() { Success = true, Data = data, Message = message };
    public static ApiResponse<T> Fail(string message) => new() { Success = false, Message = message };
}
