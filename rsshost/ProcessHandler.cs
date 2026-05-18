#pragma warning disable IDE0063 // Use simple 'using' statement
#pragma warning disable IDE0290 // Use primary constructor

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Dynamic;
using System.Linq;
using System.Threading.Tasks;
using System.Diagnostics;
using System.Security.Principal;
using System.Diagnostics.CodeAnalysis;
using System.Linq.Expressions;
using Microsoft.Extensions.Options;

namespace RssHost;

public sealed class ProcessHandlerOptions
{
    //should not include the file extension or it will not work
    public string ProcessName
    {
        get;
        init;
    } = "";

    public string Executable
    {
        get;
        init;
    } = "";

    public int WaitMs
    {
        get;
        init;
    } = 1000;

    public string Address
    {
        get;
        init;
    } = "127.0.0.1";

    public int Port
    {
        get;
        init;
    } = 8089;

    public bool EnableLogging
    {
        get;
        init;    
    } = true;

    public override string ToString()
    {
        return $"ProcessHandlerOptions: '{ProcessName}' '{Executable}' '{WaitMs}'";
    }
}

public interface IProcessHandler
{
    Task MaintainProcess(CancellationToken token);
}

public class ProcessHandler : IProcessHandler
{
    private readonly ProcessHandlerOptions _config;

    private readonly ILogger _logger;

    public ProcessHandler(IOptions<ProcessHandlerOptions> options, ILogger<ProcessHandler> logger)
    {
        _config = options.Value;
        _logger = logger;
    }

    public async Task MaintainProcess(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            var processes = Process.GetProcessesByName(_config.ProcessName);

            ArgumentNullException.ThrowIfNull(processes);

            if (processes.Length < 1)
            {
                _logger.LogInformation("Process, {processName}, not found.  Creating new instance", _config.ProcessName);
                await CreateProcess(token);
            }
            await Task.Delay(_config.WaitMs, token);
        }
    }

    private async Task CreateProcess(CancellationToken token)
    {
        try
        {
            var startInfo = new ProcessStartInfo()
            {
                FileName = _config.Executable,
                CreateNoWindow = true, // Run in the background
                Arguments = $"enableLogging={_config.EnableLogging} host={_config.Address} port={_config.Port}",
            };

            using (var process = Process.Start(startInfo))
            {
                ArgumentNullException.ThrowIfNull(process);
                _logger.LogInformation($"Creatred process with Id: {process.Id}, {process.ProcessName}, Arguments: {startInfo.Arguments}");
                await process.WaitForExitAsync(token);
                _logger.LogInformation($"Process Id: {process.Id} has exited or service is exiting.");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("Error while trying to create new process instance: {error}", ex);
        }
    }
}
