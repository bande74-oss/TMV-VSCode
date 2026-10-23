using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Tmv.Nke.Connector.Configuration;
using Tmv.Nke.Connector.Services;
using Tmv.Nke.Connector.Workers;

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

// Registra Client HTTP, Repository e Background Workers
builder.Services.AddHttpClient<INkeApiClient, NkeApiClient>();
builder.Services.AddSingleton<IQueueRepository, QueueRepository>();
builder.Services.AddHostedService<DispatcherWorker>();

var app = builder.Build();

app.UseDefaultFiles();
app.UseStaticFiles();

app.MapControllers();

app.Run();

