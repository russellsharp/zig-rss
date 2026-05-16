#pragma warning disable CA1873 // Avoid potentially expensive logging

using System.Diagnostics;
using Microsoft.Extensions.Options;

namespace RssHost;

public interface IWorker
{
    Task StartAsync(CancellationToken cancellationToken);
    Task StopAsync(CancellationToken cancellationToken);
}

public sealed class WorkerOptions
{
    public int IntervalMs
    {
        get;
        init;
    } = 1000;
}

public class Worker(ILogger<Worker> logger, IOptions<WorkerOptions> options, IProcessHandler handler) : BackgroundService, IWorker
{
    public override Task StartAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("RssHost Worker: {event}", "onStart");
        return base.StartAsync(cancellationToken);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        logger.LogInformation("Worker onTick at: {time}", DateTimeOffset.Now);
        await handler.MaintainProcess(stoppingToken);
        await Task.Delay(options.Value.IntervalMs, stoppingToken);
    }

    public override Task StopAsync(CancellationToken cancellationToken)
    {
        logger.LogInformation("RssHost Worker: {event}", "onFinish");
        return base.StopAsync(cancellationToken);
    }

}
