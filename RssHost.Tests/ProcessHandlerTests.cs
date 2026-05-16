using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Moq;
using RssHost;
using Xunit;

namespace RssHost.Tests;

public class ProcessHandlerOptionsTests
{
    [Fact]
    public void ToString_ReturnsExpectedFormat()
    {
        var opts = new ProcessHandlerOptions
        {
            ProcessName = "myproc",
            Executable = "myproc.exe",
            WaitMs = 500
        };

        var result = opts.ToString();

        Assert.Equal("ProcessHandlerOptions: 'myproc' 'myproc.exe' '500'", result);
    }

    [Fact]
    public void DefaultValues_AreCorrect()
    {
        var opts = new ProcessHandlerOptions();

        Assert.Equal("", opts.ProcessName);
        Assert.Equal("", opts.Executable);
        Assert.Equal(1000, opts.WaitMs);
    }

    [Fact]
    public void ToString_WithDefaultValues_ReturnsExpectedFormat()
    {
        var opts = new ProcessHandlerOptions();

        var result = opts.ToString();

        Assert.Equal("ProcessHandlerOptions: '' '' '1000'", result);
    }
}

public class ProcessHandlerTests
{
    private static ProcessHandler CreateHandler(string processName = "nonexistent_process_xyz123",
                                                string executable = "",
                                                int waitMs = 100,
                                                ILogger<ProcessHandler>? logger = null)
    {
        var options = Options.Create(new ProcessHandlerOptions
        {
            ProcessName = processName,
            Executable = executable,
            WaitMs = waitMs
        });

        logger ??= new Mock<ILogger<ProcessHandler>>().Object;
        return new ProcessHandler(options, logger);
    }

    [Fact]
    public async Task CheckProcess_CancelledTokenOnEntry_ReturnsImmediately()
    {
        // Arrange
        var handler = CreateHandler();
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        // Act - should return without throwing because the while loop exits on cancelled token
        await handler.MaintainProcess(cts.Token);
    }

    [Fact]
    public async Task CheckProcess_WhenProcessNotFound_LogsInformation()
    {
        // Arrange
        var loggerMock = new Mock<ILogger<ProcessHandler>>();
        var handler = CreateHandler(processName: "nonexistent_process_xyz123", waitMs: 50, logger: loggerMock.Object);

        using var cts = new CancellationTokenSource();

        // Cancel after a short delay to allow one iteration
        cts.CancelAfter(TimeSpan.FromMilliseconds(200));

        // Act
        try
        {
            await handler.MaintainProcess(cts.Token);
        }
        catch (OperationCanceledException)
        {
            // Expected when delay is cancelled
        }

        // Assert: logger was called at least once for missing process
        loggerMock.Verify(
            x => x.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("not found")),
                It.IsAny<Exception?>(),
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.AtLeastOnce);
    }

    [Fact]
    public void Constructor_SetsConfigAndLogger()
    {
        // Arrange & Act
        var handler = CreateHandler(processName: "test", executable: "test.exe", waitMs: 250);

        // Assert: construction succeeds without exception
        Assert.NotNull(handler);
    }
}
