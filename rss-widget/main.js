const { app, BrowserWindow, ipcMain, shell, screen } = require("electron");
const fs = require("fs/promises");
const path = require("path");

const bundledConfigPath = path.join(__dirname, "config", "feeds.json");
const siblingConfigPath = path.join(path.dirname(process.execPath), "feeds.json");
const DEFAULT_FAILED_REFRESH_INTERVAL_MINUTES = 5;
const DEFAULT_REQUEST_TIMEOUT_SECONDS = 30;

async function resolveConfigPath(configPath) {
  if (configPath) return configPath;

  try {
    await fs.access(siblingConfigPath);
    console.log(`[feeds] Using sibling config file: ${siblingConfigPath}`);
    return siblingConfigPath;
  } catch {
    console.debug(`[feeds] Sibling config not found, falling back to bundled config: ${bundledConfigPath}`);
    return bundledConfigPath;
  }
}

function cleanText(value) {
  if (typeof value !== "string") return "";
  return value.replace(/\s+/g, " ").trim();
}

function truncateTo(value, maxLen) {
  if (value.length <= maxLen) return value;
  return `${value.slice(0, maxLen).trimEnd()}...`;
}

function toDisplaySubject(entry) {
  // Priority: title > description (with CDATA extraction) > subject
  const candidates = [
    typeof entry.title === "string" ? entry.title : "",
    typeof entry.description === "string" ? extractCdata(entry.description) : "",
    typeof entry.subject === "string" ? entry.subject : "",
  ];
  for (const raw of candidates) {
    const clean = cleanText(stripHtml(raw));
    if (clean) return truncateTo(clean, 100);
  }
  return "(No subject)";
}

async function loadConfig(configPath) {
  const resolvedConfigPath = await resolveConfigPath(configPath);
  console.log(`[feeds] Loading config from: ${resolvedConfigPath}`);
  console.debug(`[feeds] Looking for feeds.json at: ${resolvedConfigPath}`);

  let json;
  try {
    json = await fs.readFile(resolvedConfigPath, "utf8");
  } catch (err) {
    console.error(`[feeds] Failed to read config at: ${resolvedConfigPath}`, err);
    throw err;
  }

  const parsed = JSON.parse(json);
  if (!parsed || typeof parsed !== "object") throw new Error("Config must be a JSON object.");
  if (typeof parsed.serviceUrl !== "string" || !parsed.serviceUrl) throw new Error("Config must include a non-empty serviceUrl.");
  if (!Array.isArray(parsed.requests)) throw new Error("Config must include requests as an array.");
  parsed.refreshIntervalMinutes = Number.isFinite(parsed.refreshIntervalMinutes)
    ? Math.max(1, Math.floor(parsed.refreshIntervalMinutes))
    : 30;
  parsed.refreshIntervalFailedMinutes = Number.isFinite(parsed.refreshIntervalFailedMinutes)
    ? Math.max(1, Math.floor(parsed.refreshIntervalFailedMinutes))
    : DEFAULT_FAILED_REFRESH_INTERVAL_MINUTES;
  parsed.requestTimeoutSeconds = Number.isFinite(parsed.requestTimeoutSeconds)
    ? Math.max(1, Math.floor(parsed.requestTimeoutSeconds))
    : DEFAULT_REQUEST_TIMEOUT_SECONDS;
  return parsed;
}

// The service serialises std.ArrayList as { items: [...], capacity: N }.
// Unwrap it, or return the value as-is if it is already a plain array.
function unwrapList(value) {
  if (Array.isArray(value)) return value;
  if (value && Array.isArray(value.items)) return value.items;
  return [];
}

// Extract text from CDATA sections, or return the raw string if none are present.
function extractCdata(text) {
  const matches = [...text.matchAll(/<!\[CDATA\[(.*?)\]\]>/gs)];
  if (matches.length > 0) return matches.map((m) => m[1]).join(" ");
  return text;
}

// Strip HTML tags and decode the most common HTML entities found in RSS subjects.
function stripHtml(text) {
  return text
    .replace(/<[^>]*>/g, "")          // remove tags
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#8217;/g, "\u2019")
    .replace(/&#8220;/g, "\u201C")
    .replace(/&#8221;/g, "\u201D")
    .replace(/&#8230;/g, "\u2026")
    .replace(/&#\d+;/g, (m) => String.fromCharCode(parseInt(m.slice(2), 10)))
    .replace(/\s+/g, " ")
    .trim();
}

function flattenEntries(summaries) {
  const flattened = [];
  for (const summary of summaries) {
    const entries = unwrapList(summary.entries);
    for (const entry of entries) {
      flattened.push({
        feedTitle: cleanText(summary.title) || "Feed",
        subject: stripHtml(toDisplaySubject(entry)),
        link: cleanText(entry.link),
        published: cleanText(entry.published),
      });
    }
  }
  return flattened;
}

async function fetchFeeds(configPath) {
  const config = await loadConfig(configPath);
  const body = JSON.stringify({ requests: config.requests });

  const controller = new AbortController();
  const timeoutMs = config.requestTimeoutSeconds * 1000;
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  let response;
  try {
    response = await fetch(config.serviceUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      signal: controller.signal,
    });
  } catch (err) {
    if (err && err.name === "AbortError") {
      throw new Error(`Request timed out after ${config.requestTimeoutSeconds} seconds.`);
    }
    throw err;
  } finally {
    clearTimeout(timeoutId);
  }

  const text = await response.text();
  if (!response.ok) throw new Error(`Service error (${response.status}): ${text}`);

  let payload;
  try { payload = JSON.parse(text); }
  catch { throw new Error(`Service returned non-JSON: ${text}`); }

  // The service wraps every ArrayList as { items: [...], capacity: N }.
  // Accept either a plain array or the wrapped shape.
  const summaries = Array.isArray(payload)
    ? payload
    : Array.isArray(payload?.items)
      ? payload.items
      : null;

  if (!summaries) throw new Error("Unexpected service response shape.");

  return { serviceUrl: config.serviceUrl, entries: flattenEntries(summaries) };
}

function createWindow() {
  const { width: sw, height: sh } = screen.getPrimaryDisplay().workAreaSize;
  const w = Math.max(320, Math.floor(sw * 0.15));
  const h = Math.max(320, Math.floor(sh * 0.15));

  const win = new BrowserWindow({
    title: " ",
    width: w, height: h,
    minWidth: 320, minHeight: 320,
    resizable: true,
    autoHideMenuBar: true,
    backgroundColor: "#1c1f22",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  win.setTitle(" ");
  win.loadFile(path.join(__dirname, "renderer", "index.html"));
}

ipcMain.handle("feeds:refresh", async (_e, configPath) => fetchFeeds(configPath));

ipcMain.handle("feeds:load-config", async (_e, configPath) => {
  const resolvedConfigPath = await resolveConfigPath(configPath);
  const cfg = await loadConfig(resolvedConfigPath);
  return {
    configPath: resolvedConfigPath,
    serviceUrl: cfg.serviceUrl,
    requestCount: cfg.requests.length,
    refreshIntervalMinutes: cfg.refreshIntervalMinutes,
    refreshIntervalFailedMinutes: cfg.refreshIntervalFailedMinutes,
  };
});

ipcMain.handle("link:open", async (_e, url) => {
  if (typeof url !== "string" || !url.startsWith("http")) throw new Error("Invalid URL");
  await shell.openExternal(url);
  return true;
});

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on("window-all-closed", () => { if (process.platform !== "darwin") app.quit(); });
