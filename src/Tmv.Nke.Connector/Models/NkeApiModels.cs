using System.Text.Json.Serialization;

namespace Tmv.Nke.Connector.Models;

public class NkeMasterData
{
    [JsonPropertyName("Master")]
    public string Master { get; set; } = string.Empty;

    [JsonPropertyName("Typology")]
    public string Typology { get; set; } = string.Empty;

    [JsonPropertyName("Rules")]
    public List<string> Rules { get; set; } = new();
}

public class NkeRequestPayload
{
    [JsonPropertyName("Id")]
    public Guid Id { get; set; }

    [JsonPropertyName("MasterDataArray")]
    public List<NkeMasterData> MasterDataArray { get; set; } = new();

    [JsonPropertyName("ParametersArray")]
    public List<object> ParametersArray { get; set; } = new() { new object() };

    /// <summary>
    /// Costruisce il codice Master formattato a 31 caratteri atteso da NKE e Autodesk Inventor
    /// esattamente conforme alla logica legacy di SPRT_NKE_SCHED.
    /// </summary>
    public static string FormatMasterCode(string codArt, string opzione)
    {
        var artClean = (codArt ?? string.Empty).Trim();
        var part1 = artClean.Length >= 5 ? artClean.Substring(0, 5) : artClean.PadRight(5, '-');
        var part2 = artClean.Length >= 6 ? artClean.Substring(artClean.Length - 6) : artClean.PadLeft(6, '-');

        var optPadded = ((opzione ?? string.Empty) + "-----------------").Replace(' ', '-');
        var optPart1 = optPadded.Length >= 5 ? optPadded.Substring(0, 5) : optPadded.PadRight(5, '-');
        var optPart2 = optPadded.Length >= 17 ? optPadded.Substring(11, 6) : "------";

        return $"{part1}---{part2}{optPart1}------{optPart2}";
    }

    public static NkeRequestPayload Create(Guid guid, string codArt, string opzione)
    {
        var master = FormatMasterCode(codArt, opzione);
        var typology = master.Length >= 3 ? master.Substring(0, 3) : "---";

        return new NkeRequestPayload
        {
            Id = guid,
            MasterDataArray = new List<NkeMasterData>
            {
                new()
                {
                    Master = master,
                    Typology = typology,
                    Rules = new List<string>()
                }
            },
            ParametersArray = new List<object> { new object() }
        };
    }
}

public class NkeCallResult
{
    public bool Success { get; set; }
    public int HttpStatus { get; set; }
    public int LatencyMs { get; set; }
    public string RequestJson { get; set; } = string.Empty;
    public string ResponseJson { get; set; } = string.Empty;
    public string? ErrorMessage { get; set; }
    public bool IsTimeout { get; set; }
}

