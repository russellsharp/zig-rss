const { test, afterEach } = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const { JSDOM } = require("jsdom");

const rendererPath = path.join(__dirname, "..", "renderer", "renderer.js");
const originalSetInterval = global.setInterval;
const originalClearInterval = global.clearInterval;

let activeDom = null;

function flush() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function createDom() {
  const dom = new JSDOM(
    `<!doctype html><body>
      <button id="refreshBtn">Refresh</button>
      <ul id="entryList"></ul>
      <p id="statusText">Waiting for first refresh…</p>
      <p id="serviceInfo">Loading config…</p>
    </body>`,
    { url: "https://example.test" }
  );

  global.window = dom.window;
  global.document = dom.window.document;
  global.Event = dom.window.Event;
  activeDom = dom;

  return dom;
}

async function loadRendererWith(api, timerSpies = null) {
  window.rssWidget = api;

  const timers =
    timerSpies ||
    {
      setInterval: () => 1,
      clearInterval: () => {},
    };

  global.setInterval = timers.setInterval;
  global.clearInterval = timers.clearInterval;

  delete require.cache[rendererPath];
  require(rendererPath);

  await flush();
  await flush();
}

afterEach(() => {
  global.setInterval = originalSetInterval;
  global.clearInterval = originalClearInterval;
  delete require.cache[rendererPath];

  if (activeDom) {
    activeDom.window.close();
    activeDom = null;
  }

  delete global.window;
  delete global.document;
  delete global.Event;
});

test("renderer init shows config details and renders entries", async () => {
  const dom = createDom();

  const opened = [];
  await loadRendererWith({
    loadConfig: async () => ({
      serviceUrl: "http://localhost:5000/feed",
      requestCount: 2,
      refreshIntervalMinutes: 10,
    }),
    refreshFeeds: async () => ({
      entries: [
        { subject: "First", link: "https://example.com/one" },
        { subject: "Second", link: "" },
      ],
    }),
    openLink: async (url) => {
      opened.push(url);
    },
  });

  const serviceInfo = document.getElementById("serviceInfo").textContent;
  const statusText = document.getElementById("statusText").textContent;

  assert.match(serviceInfo, /http:\/\/localhost:5000\/feed/);
  assert.match(serviceInfo, /2 feeds/);
  assert.match(serviceInfo, /auto-refresh 10m/);
  assert.equal(statusText, "Loaded 2 entries.");

  const rows = [...document.querySelectorAll("#entryList li")];
  assert.equal(rows.length, 2);
  assert.equal(rows[0].querySelector(".entry-subject").textContent, "First");
  assert.equal(rows[0].querySelector(".entry-link").textContent, "Link");
  assert.equal(rows[1].querySelector(".entry-subject").textContent, "Second");
  assert.equal(rows[1].querySelector(".entry-link"), null);

  rows[0].querySelector(".entry-link").dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  await flush();
  assert.deepEqual(opened, ["https://example.com/one"]);

});

test("renderer shows empty and error states when refresh fails", async () => {
  const dom = createDom();

  await loadRendererWith({
    loadConfig: async () => ({
      serviceUrl: "http://localhost:5000/feed",
      requestCount: 1,
      refreshIntervalMinutes: 30,
    }),
    refreshFeeds: async () => {
      throw new Error("Boom");
    },
    openLink: async () => {},
  });

  const firstItem = document.querySelector("#entryList li");
  assert.ok(firstItem);
  assert.equal(firstItem.className, "empty-state");
  assert.equal(firstItem.textContent, "Unable to load entries.");
  assert.equal(document.getElementById("statusText").textContent, "Boom");

});

test("renderer schedules auto refresh and refresh button triggers reload", async () => {
  const dom = createDom();

  let refreshCalls = 0;
  const timerCalls = [];
  const timers = {
    setInterval: (fn, ms) => {
      timerCalls.push(ms);
      return 42;
    },
    clearInterval: () => {},
  };

  await loadRendererWith(
    {
      loadConfig: async () => ({
        serviceUrl: "http://localhost:5000/feed",
        requestCount: 1,
        refreshIntervalMinutes: 7,
      }),
      refreshFeeds: async () => {
        refreshCalls += 1;
        return { entries: [] };
      },
      openLink: async () => {},
    },
    timers
  );

  assert.deepEqual(timerCalls, [7 * 60 * 1000]);
  assert.equal(refreshCalls, 1);

  document.getElementById("refreshBtn").click();
  await flush();
  assert.equal(refreshCalls, 2);
  assert.equal(document.getElementById("statusText").textContent, "Loaded 0 entries.");

});
