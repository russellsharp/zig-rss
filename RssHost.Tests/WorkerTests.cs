using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using RssHost;
using Xunit;

namespace RssHost.Tests;

public class WorkerOptionsTests
{
    [Fact]
    public void DefaultIntervalMs_Is1000()
    {
        var opts = new WorkerOptions();

        Assert.Equal(1000, opts.IntervalMs);
    }

    [Fact]
    public void IntervalMs_CanBeSet()
    {
        var opts = new WorkerOptions { IntervalMs = 5000 };

        Assert.Equal(5000, opts.IntervalMs);
    }
}

public class WorkerTests
{
    private static Worker CreateWorker(IProcessHandler? handler = null,
                                       int intervalMs = 100,
                                       ILogger<Worker>? logger = null)
    {
        logger ??= new Mock<ILogger<Worker>>().Object;
        handler ??= new Mock<IProcessHandler>().Object;
        var options = Options.Create(new WorkerOptions { IntervalMs = intervalMs });
        return new Worker(logger, options, handler);
    }

    [Fact]
    public async Task StartAsync_LogsOnStart()
    {
        // Arrange
        var loggerMock = new Mock<ILogger<Worker>>();
        var worker = CreateWorker(logger: loggerMock.Object);
        using var cts = new CancellationTokenSource();
        cts.Cancel(); // cancel immediately so ExecuteAsync exits right away

        // Act
        await worker.StartAsync(cts.Token);

        // Assert
        loggerMock.Verify(
            x => x.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("onStart")),
                It.IsAny<Exception?>(),
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.Once);
    }

    [Fact]
    public async Task StopAsync_LogsOnFinish()
    {
        // Arrange
        var loggerMock = new Mock<ILogger<Worker>>();
        var worker = CreateWorker(logger: loggerMock.Object);
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        await worker.StartAsync(cts.Token);

        // Act
        await worker.StopAsync(cts.Token);

        // Assert
        loggerMock.Verify(
            x => x.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("onFinish")),
                It.IsAny<Exception?>(),
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.Once);
    }

    [Fact]
    public async Task ExecuteAsync_CallsHandlerCheckProcess()
    {
        // Arrange
        var handlerMock = new Mock<IProcessHandler>();
        handlerMock
            .Setup(h => h.MaintainProcess(It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var worker = CreateWorker(handler: handlerMock.Object, intervalMs: 50);
        using var cts = new CancellationTokenSource();

        // Start worker, allow one tick, then cancel
        cts.CancelAfter(TimeSpan.FromMilliseconds(200));

        try
        {
            await worker.StartAsync(cts.Token);
            await Task.Delay(Timeout.Infinite, cts.Token);
        }
        catch (OperationCanceledException) { }
        finally
        {
            await worker.StopAsync(CancellationToken.None);
        }

        // Assert: handler was called at least once during execution
        handlerMock.Verify(h => h.MaintainProcess(It.IsAny<CancellationToken>()), Times.AtLeastOnce);
    }

    [Fact]
    public async Task ExecuteAsync_WithCancelledToken_ExitsImmediately()
    {
        // Arrange
        var handlerMock = new Mock<IProcessHandler>();
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        var worker = CreateWorker(handler: handlerMock.Object);

        // Act
        await worker.StartAsync(cts.Token);

        // Assert: no invocation since token was already cancelled
        handlerMock.Verify(h => h.MaintainProcess(It.IsAny<CancellationToken>()), Times.Never);
    }
}
