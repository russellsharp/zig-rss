const refreshBtn = document.getElementById("refreshBtn");
const entryList  = document.getElementById("entryList");
const statusText = document.getElementById("statusText");
const serviceInfo = document.getElementById("serviceInfo");

const DEFAULT_FAILED_REFRESH_INTERVAL_MINUTES = 5;
let failedRefreshIntervalMinutes = DEFAULT_FAILED_REFRESH_INTERVAL_MINUTES;
let failedRefreshTimer = null;

function setStatus(message, tone = "warn") {
  statusText.textContent = message;
  statusText.classList.remove("status-ok", "status-warn", "status-danger");
  if (tone === "ok") statusText.classList.add("status-ok");
  else if (tone === "danger") statusText.classList.add("status-danger");
  else statusText.classList.add("status-warn");
}

function clearFailedRefreshTimer() {
  if (failedRefreshTimer) {
    clearTimeout(failedRefreshTimer);
    failedRefreshTimer = null;
  }
}

function isTimeoutError(err) {
  const message = (err && err.message ? String(err.message) : "").toLowerCase();
  return message.includes("timed out") || message.includes("timeout");
}

function scheduleFailedRefreshRetry() {
  clearFailedRefreshTimer();
  const delayMs = Math.max(1, failedRefreshIntervalMinutes) * 60 * 1000;
  failedRefreshTimer = setTimeout(() => {
    failedRefreshTimer = null;
    void refresh();
  }, delayMs);
}

function clearList() {
  while (entryList.firstChild) entryList.removeChild(entryList.firstChild);
}

function showEmpty(msg) {
  const li = document.createElement("li");
  li.className = "empty-state";
  li.textContent = msg;
  entryList.appendChild(li);
}

function renderEntries(entries) {
  clearList();
  if (!entries.length) { showEmpty("No feed entries were returned."); return; }

  for (const entry of entries) {
    const row = document.createElement("li");
    row.className = "entry-row";

    const subject = document.createElement("span");
    subject.className = "entry-subject";
    subject.textContent = entry.subject;
    row.appendChild(subject);

    if (entry.link) {
      const a = document.createElement("a");
      a.className = "entry-link";
      a.href = "#";
      a.textContent = "Link";
      a.addEventListener("click", async (e) => {
        e.preventDefault();
        try { await window.rssWidget.openLink(entry.link); }
        catch (err) { statusText.textContent = `Could not open link: ${err.message}`; }
      });
      row.appendChild(a);
    }

    entryList.appendChild(row);
  }
}

async function refresh() {
  clearFailedRefreshTimer();
  refreshBtn.disabled = true;
  setStatus("Refreshing feeds…", "warn");
  try {
    const result = await window.rssWidget.refreshFeeds();
    renderEntries(result.entries);
    setStatus(`Loaded ${result.entries.length} entr${result.entries.length === 1 ? "y" : "ies"}.`, "ok");
    if (result.entries.length === 0) scheduleFailedRefreshRetry();
  } catch (err) {
    clearList();
    showEmpty("Unable to load entries.");
    setStatus(err.message, "danger");
    if (isTimeoutError(err)) {
      scheduleFailedRefreshRetry();
      setStatus(
        `${err.message} Retrying in ${failedRefreshIntervalMinutes} minute${failedRefreshIntervalMinutes === 1 ? "" : "s"}.`,
        "warn",
      );
    }
  } finally {
    refreshBtn.disabled = false;
  }
}

async function init() {
  try {
    const cfg = await window.rssWidget.loadConfig();
    const intervalMinutes = Number.isFinite(cfg.refreshIntervalMinutes) ? Math.max(1, Math.floor(cfg.refreshIntervalMinutes)) : 30;
    serviceInfo.textContent = `${cfg.serviceUrl}  ·  ${cfg.requestCount} feed${cfg.requestCount === 1 ? "" : "s"}  ·  auto-refresh ${intervalMinutes}m`;
    failedRefreshIntervalMinutes = Number.isFinite(cfg.refreshIntervalFailedMinutes)
      ? Math.max(1, Math.floor(cfg.refreshIntervalFailedMinutes))
      : DEFAULT_FAILED_REFRESH_INTERVAL_MINUTES;
    setInterval(refresh, intervalMinutes * 60 * 1000);
  } catch (err) {
    serviceInfo.textContent = "Config error";
    setStatus(err.message, "danger");
  }
  refreshBtn.addEventListener("click", refresh);
  await refresh();
}

void init();
