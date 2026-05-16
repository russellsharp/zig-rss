#pragma warning disable CA1416 // Validate platform compatibility

using System.Diagnostics;
using RssHost;


//pass around cancellation token source

const string HOST_NAME = "RssHost";

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddWindowsService(options =>
{
    options.ServiceName = HOST_NAME;
});
builder.Services.AddServices();
builder.Services.AddOptions();
builder.AddLogging(HOST_NAME);
var host = builder.Build();
host.Run();


public static class BuildExtensions
{
    public static HostApplicationBuilder? AddLogging(this HostApplicationBuilder? builder, string hostName)
    {
        ArgumentNullException.ThrowIfNull(builder);
        builder.Logging.ClearProviders();
        builder.Logging.AddConsole();
        if (OperatingSystem.IsWindows())
        {
            builder.Logging.AddEventLog(settings =>
            {
                settings.SourceName = hostName;
                settings.LogName = "Application";
            }).SetMinimumLevel(LogLevel.Trace);
        }
        return builder;
    }

    public static IServiceCollection AddServices(this IServiceCollection services)
    {
        return services.AddHostedService<Worker>()
                       .AddSingleton<IProcessHandler, ProcessHandler>();
    }

    public static IServiceCollection? AddOptions(this IServiceCollection services)
    {
        services.AddOptions<ProcessHandlerOptions>().BindConfiguration(nameof(ProcessHandlerOptions));
        services.AddOptions<WorkerOptions>().BindConfiguration(nameof(WorkerOptions));
        return services;
    }
}