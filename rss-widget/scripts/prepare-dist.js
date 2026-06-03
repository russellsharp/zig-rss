const fs = require("fs/promises");
const path = require("path");
const { execFileSync } = require("child_process");

const projectRoot = path.resolve(__dirname, "..");
const winUnpackedDir = path.join(projectRoot, "release", "win-unpacked");
const processName = "RSS Widget.exe";
const processCandidates = [processName, "rsswidget-portable.exe"];
const maxCleanupAttempts = 12;
const retryDelayMs = 500;

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function stopRunningUnpackedWidgetOnWindows() {
    if (process.platform !== "win32") return;

    const normalizedRoot = projectRoot.replace(/\\/g, "\\\\");
    const command = [
        `$root = '${normalizedRoot}'`,
        `$target = Join-Path $root 'release\\win-unpacked'`,
        `$procs = Get-CimInstance Win32_Process -Filter \"Name = '${processName}'\"`,
        "foreach ($p in $procs) {",
        "  if ($p.ExecutablePath -and $p.ExecutablePath.StartsWith($target, [System.StringComparison]::OrdinalIgnoreCase)) {",
        "    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue",
        "    Write-Host \"[dist] Stopped running process: $($p.ExecutablePath)\"",
        "  }",
        "}",
    ].join("; ");

    try {
        execFileSync(
            "powershell",
            ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
            { stdio: "inherit" },
        );
    } catch (err) {
        console.warn("[dist] Unable to verify/stop running unpacked widget process. Continuing.");
        if (err && err.message) console.warn(`[dist] ${err.message}`);
    }

    for (const name of processCandidates) {
        try {
            execFileSync("taskkill", ["/F", "/T", "/IM", name], { stdio: "ignore" });
            console.log(`[dist] taskkill issued for ${name}`);
        } catch {
            // Ignore when no matching process exists.
        }
    }
}

async function cleanWinUnpackedDir() {
    for (let attempt = 1; attempt <= maxCleanupAttempts; attempt += 1) {
        try {
            await fs.rm(winUnpackedDir, { recursive: true, force: true });
            console.log(`[dist] Cleaned ${winUnpackedDir}`);
            return;
        } catch (err) {
            const isRetryable = err && (err.code === "EBUSY" || err.code === "EPERM");
            if (!isRetryable || attempt === maxCleanupAttempts) {
                console.error(`[dist] Failed to clean ${winUnpackedDir}:`, err);
                process.exitCode = 1;
                return;
            }

            console.warn(`[dist] Cleanup attempt ${attempt}/${maxCleanupAttempts} failed with ${err.code}. Retrying...`);
            await sleep(retryDelayMs);
        }
    }
}

(async () => {
    stopRunningUnpackedWidgetOnWindows();
    await cleanWinUnpackedDir();
})();
