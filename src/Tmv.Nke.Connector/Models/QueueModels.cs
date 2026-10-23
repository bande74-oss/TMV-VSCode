namespace Tmv.Nke.Connector.Models;

public class QueueItem
{
    public Guid RT13_GUID { get; set; }
    public decimal RT13_DITTA_CG18 { get; set; }
    public string RT13_CODART_MG66 { get; set; } = string.Empty;
    public string RT13_OPZIONE_MG5E { get; set; } = string.Empty;
    public Guid MG87_GUID { get; set; }
    public string DESCRIZIONE { get; set; } = string.Empty;
    public DateTime RT13_INSERT_DATETIME { get; set; }
    public DateTime? RT13_CALL_DATETIME { get; set; }
    public bool RT13_SOVRASCRIVI { get; set; }
    public bool RT13_FILE_GENERATO { get; set; }
    public int RT13_NUM_TENTATIVI { get; set; }
}

public class QueueItemDto
{
    public Guid Guid { get; set; }
    public string CodiceArticolo { get; set; } = string.Empty;
    public string Variante { get; set; } = string.Empty;
    public string Descrizione { get; set; } = string.Empty;
    public DateTime DataInserimento { get; set; }
    public DateTime? UltimaChiamata { get; set; }
    public int Tentativi { get; set; }
    public bool Sovrascrivi { get; set; }
    public string? DocumentiCollegati { get; set; }
    public string? ClientiCollegati { get; set; }
}

public class LogItemDto
{
    public long IdLog { get; set; }
    public Guid Guid { get; set; }
    public DateTime DataOra { get; set; }
    public int LatenzaMs { get; set; }
    public int HttpStatus { get; set; }
    public bool EsitoGenerato { get; set; }
    public string? MessaggioErrore { get; set; }
    public string Operatore { get; set; } = string.Empty;
    public string IpClient { get; set; } = string.Empty;
    public string CodiceArticolo { get; set; } = string.Empty;
    public string Variante { get; set; } = string.Empty;
    public string? DocumentiCollegati { get; set; }
    public string? ClientiCollegati { get; set; }
}

public class KpiSummaryDto
{
    public int InCoda { get; set; }
    public int Inviati24h { get; set; }
    public int Errori24h { get; set; }
    public double LatenzaMediaMs { get; set; }
    public DateTime? UltimaChiamata { get; set; }
    public bool IsNkeHealthy { get; set; }
}

public class NkePayloadDetailDto
{
    public long IdLog { get; set; }
    public Guid Guid { get; set; }
    public DateTime DataOra { get; set; }
    public string RichiestaJson { get; set; } = string.Empty;
    public string RispostaJson { get; set; } = string.Empty;
    public string? MessaggioErrore { get; set; }
}
