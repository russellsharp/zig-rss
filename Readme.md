# RSS Aggregator Monorepo

This repository contains a local RSS aggregation stack with three main parts:

- `rss/`: Zig HTTP service that receives feed requests and returns summarized feed entries.
- `rss-widget/`: Electron desktop widget (plus a Python UI prototype) that calls the Zig service and renders entries.
- `rsshost/` + `RssHost.Tests/`: .NET Worker Service that supervises the Zig process and can run as a Windows service.

## Repository Layout

- `rss/` - Zig service and Zig tests.
- `rss-widget/` - Electron app, renderer assets, config, and Node tests.
- `rsshost/` - .NET host process and service wiring.
- `RssHost.Tests/` - xUnit tests for the host project.
- `zig-out/` and `rss/zig-out/` - Zig build artifacts.

## Prerequisites

- Zig `0.16.0` or newer (see `rss/build.zig.zon`).
- Node.js (current LTS recommended) and npm.
- .NET SDK `10.0` (project targets `net10.0`).
- Windows is the primary target for the host service workflow.

## Quick Start (Widget + Zig Service)

1. Build and run the Zig service:

```powershell
cd rss
zig build run
```

By default, the service listens on `127.0.0.1:8089` and accepts POST requests at `/rss`.

2. In a second terminal, run the Electron widget:

```powershell
cd rss-widget
npm install
npm start
```

3. The widget reads request settings from `rss-widget/config/feeds.json`.

Default service URL in that file:

- `http://127.0.0.1:8089/rss`

## Zig Service (`rss/`)

### Build

```powershell
cd rss
zig build
```

### Run

```powershell
cd rss
zig build run
```

Optional args can be passed after `--`:

```powershell
zig build run -- port=8089 address=127.0.0.1 logEnabled=true
```

Supported request route:

- `POST /rss`

Expected request content type:

- `application/json`

### Tests

Run all default tests:

```powershell
cd rss
zig build test
```

Run module-specific test steps (defined in `build.zig`):

```powershell
zig build testXml
zig build testUtilities
zig build testRss
zig build testHost
```

## Electron Widget (`rss-widget/`)

### Install and Run

```powershell
cd rss-widget
npm install
npm start
```

### Package

```powershell
cd rss-widget
npm run dist
```

### Tests

Tests are located in `rss-widget/test/` and use Node's built-in test runner:

```powershell
cd rss-widget
node --test test/*.test.js
```

## .NET Host (`rsshost/`)

The host service monitors and restarts the Zig executable if it is not running.

Configuration is in:

- `rsshost/appsettings.json`

Important settings:

- `ProcessHandlerOptions.ProcessName`
- `ProcessHandlerOptions.Executable`
- `ProcessHandlerOptions.WaitMs`

Update `Executable` to point to your local Zig service binary path before running.

### Run Host Locally

```powershell
cd rsshost
dotnet run
```

### Build

```powershell
cd rsshost
dotnet build
```

### Tests

Run all host tests via solution:

```powershell
cd rsshost
dotnet test rsshost.sln
```

Or run only test project:

```powershell
dotnet test ..\RssHost.Tests\RssHost.Tests.csproj
```

## Logs and Diagnostics

- Zig service logging can be controlled with `logEnabled` CLI arg.
- Historical logs are stored under `rss/logs/`.
- The .NET host writes to console and Windows Event Log when applicable.

## Notes

- This repo includes both Electron (`rss-widget/main.js`) and Python (`rss-widget/app.py`) client implementations.
- The Electron client is the primary desktop widget path (via `npm start`).