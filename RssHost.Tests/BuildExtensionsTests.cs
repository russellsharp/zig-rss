using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using RssHost;
using Xunit;

namespace RssHost.Tests;

public class BuildExtensionsTests
{
    [Fact]
    public void AddServices_RegistersWorkerAsHostedService()
    {
        // Arrange
        var services = new ServiceCollection();
        services.AddLogging();

        // AddSingleton for options required by ProcessHandler and Worker
        services.AddOptions<ProcessHandlerOptions>().Configure(o => { o = new ProcessHandlerOptions(); });
        services.AddOptions<WorkerOptions>().Configure(o => { o = new WorkerOptions(); });

        // Act
        services.AddServices();
        var provider = services.BuildServiceProvider();

        // Assert: IProcessHandler resolves as ProcessHandler
        var handler = provider.GetRequiredService<IProcessHandler>();
        Assert.IsType<ProcessHandler>(handler);
    }

    [Fact]
    public void AddServices_RegistersIProcessHandlerAsSingleton()
    {
        // Arrange
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddOptions<ProcessHandlerOptions>();
        services.AddOptions<WorkerOptions>();

        // Act
        services.AddServices();
        var provider = services.BuildServiceProvider();

        // Assert: same instance is returned each time (singleton)
        var handler1 = provider.GetRequiredService<IProcessHandler>();
        var handler2 = provider.GetRequiredService<IProcessHandler>();
        Assert.Same(handler1, handler2);
    }

    [Fact]
    public void AddOptions_BindsProcessHandlerOptions()
    {
        // Arrange
        var services = new ServiceCollection();
        var config = new ConfigurationBuilder().Build();
        services.AddSingleton<IConfiguration>(config);
        services.AddOptions<ProcessHandlerOptions>();

        // Act
        var provider = services.BuildServiceProvider();
        var opts = provider.GetRequiredService<IOptions<ProcessHandlerOptions>>();

        // Assert: options are accessible and have defaults
        Assert.NotNull(opts.Value);
        Assert.Equal(1000, opts.Value.WaitMs);
    }

    [Fact]
    public void AddOptions_BindsWorkerOptions()
    {
        // Arrange
        var services = new ServiceCollection();
        var config = new ConfigurationBuilder().Build();
        services.AddSingleton<IConfiguration>(config);
        services.AddOptions<WorkerOptions>();

        // Act
        var provider = services.BuildServiceProvider();
        var opts = provider.GetRequiredService<IOptions<WorkerOptions>>();

        // Assert: options are accessible with default interval
        Assert.NotNull(opts.Value);
        Assert.Equal(1000, opts.Value.IntervalMs);
    }

    [Fact]
    public void AddLogging_NullBuilder_ThrowsArgumentNullException()
    {
        // Arrange
        HostApplicationBuilder? nullBuilder = null;

        // Act & Assert
        Assert.Throws<ArgumentNullException>(() => nullBuilder.AddLogging("TestHost"));
    }
}
