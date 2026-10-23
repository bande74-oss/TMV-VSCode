using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Tmv.Nke.Connector.Configuration;

var builder = WebApplication.CreateBuilder(args);

// Abilita l'esecuzione come Servizio Windows se installato come service, o da console se avviato manualmente
builder.Host.UseWindowsService();

// Registra opzioni di configurazione
var settings = new NkeSettings();
builder.Configuration.GetSection("NkeSettings").Bind(settings);
builder.Services.Configure<NkeSettings>(builder.Configuration.GetSection("NkeSettings"));

// Configura porta Kestrel da impostazioni
builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(settings.Port);
});

// Aggiunge servizi API e file statici
builder.Services.AddControllers();

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapControllers();

app.Run();

