const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const Module = require("node:module");

const mainPath = path.join(__dirname, "..", "main.js");

function loadMainWithMocks({ configJson, fetchImpl, screenSize } = {}) {
  const handlers = {};
  const browserWindowInstances = [];
  const appEvents = {};
  const openExternalCalls = [];

  const electronMock = {
    app: {
      setPath: () => {},
      getPath: () => path.join("C:", "Users", "test", "AppData", "Roaming"),
      whenReady: () => Promise.resolve(),
      on: (event, cb) => {
        appEvents[event] = cb;
      },
      quit: () => {},
    },
    BrowserWindow: class BrowserWindow {
      static getAllWindows() {
        return [];
      }

      constructor(options) {
        this.options = options;
        this.loadedFile = null;
        browserWindowInstances.push(this);
      }

      loadFile(filePath) {
        this.loadedFile = filePath;
      }
    },
    ipcMain: {
      handle: (channel, fn) => {
        handlers[channel] = fn;
      },
    },
    shell: {
      openExternal: async (url) => {
        openExternalCalls.push(url);
      },
    },
    screen: {
      getPrimaryDisplay: () => ({
        workAreaSize: screenSize || { width: 1000, height: 800 },
      }),
    },
  };

  const fsMock = {
    readFile: async () => {
      if (typeof configJson === "string") return configJson;
      return JSON.stringify({
        serviceUrl: "http://localhost:5000/feed",
        requests: [{ title: "Feed", url: "https://example.com" }],
      });
    },
  };

  const originalFetch = global.fetch;
  const originalLoad = Module._load;

  Module._load = function patchedLoad(request, parent, isMain) {
    if (request === "electron") return electronMock;
    if (request === "fs/promises") return fsMock;
    return originalLoad.call(this, request, parent, isMain);
  };

  global.fetch =
    fetchImpl ||
    (async () => ({
      ok: true,
      status: 200,
      text: async () => "[]",
    }));

  delete require.cache[mainPath];
  require(mainPath);

  const restore = async () => {
    await Promise.resolve();
    Module._load = originalLoad;
    global.fetch = originalFetch;
    delete require.cache[mainPath];
  };

  return {
    handlers,
    browserWindowInstances,
    openExternalCalls,
    appEvents,
    restore,
  };
}

test("registers all expected ipc handlers and creates a window on ready", async () => {
  const loaded = loadMainWithMocks();

  await Promise.resolve();

  assert.equal(typeof loaded.handlers["feeds:refresh"], "function");
  assert.equal(typeof loaded.handlers["feeds:load-config"], "function");
  assert.equal(typeof loaded.handlers["link:open"], "function");

  assert.equal(loaded.browserWindowInstances.length, 1);
  const win = loaded.browserWindowInstances[0];
  assert.equal(win.options.minWidth, 320);
  assert.equal(win.options.minHeight, 320);
  assert.equal(win.options.width, 320);
  assert.equal(win.options.height, 320);
  assert.ok(win.loadedFile.endsWith(path.join("renderer", "index.html")));

  await loaded.restore();
});

test("feeds:load-config returns defaults and preserves valid refresh interval", async () => {
  const noInterval = loadMainWithMocks({
    configJson: JSON.stringify({
      serviceUrl: "http://localhost:7777/service",
      requests: [{ title: "A", url: "https://a" }],
    }),
  });

  const resultDefault = await noInterval.handlers["feeds:load-config"](null, "custom.json");
  assert.equal(resultDefault.configPath, "custom.json");
  assert.equal(resultDefault.serviceUrl, "http://localhost:7777/service");
  assert.equal(resultDefault.requestCount, 1);
  assert.equal(resultDefault.refreshIntervalMinutes, 30);
  await noInterval.restore();

  const withInterval = loadMainWithMocks({
    configJson: JSON.stringify({
      serviceUrl: "http://localhost:7777/service",
      requests: [{ title: "A", url: "https://a" }, { title: "B", url: "https://b" }],
      refreshIntervalMinutes: 12,
    }),
  });

  const result = await withInterval.handlers["feeds:load-config"](null, null);
  assert.equal(result.requestCount, 2);
  assert.equal(result.refreshIntervalMinutes, 12);
  await withInterval.restore();
});

test("feeds:refresh posts requests and returns flattened sorted entries", async () => {
  const fetchCalls = [];
  const loaded = loadMainWithMocks({
    configJson: JSON.stringify({
      serviceUrl: "http://localhost:8888/feed",
      requests: [{ title: "One", url: "https://one" }],
    }),
    fetchImpl: async (url, init) => {
      fetchCalls.push({ url, init });
      return {
        ok: true,
        status: 200,
        text: async () =>
          JSON.stringify({
            items: [
              {
                title: "Daily Feed",
                entries: {
                  items: [
                    {
                      title: "Older",
                      link: "https://example.com/older",
                      parsedDate: "Fri, 07 Jun 2024 10:00:00 +0000",
                    },
                    {
                      description: "<![CDATA[<b>Newest &amp; Best</b>]]>",
                      link: "https://example.com/new",
                      parsedDate: "Sat, 08 Jun 2024 10:00:00 +0000",
                    },
                  ],
                },
              },
            ],
          }),
      };
    },
  });

  const result = await loaded.handlers["feeds:refresh"](null, "my-config.json");

  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].url, "http://localhost:8888/feed");
  assert.equal(fetchCalls[0].init.method, "POST");
  assert.equal(fetchCalls[0].init.headers["Content-Type"], "application/json");
  assert.equal(result.entries.length, 2);
  assert.equal(result.entries[0].subject, "Newest & Best");
  assert.equal(result.entries[0].link, "https://example.com/new");
  assert.equal(result.entries[1].subject, "Older");

  await loaded.restore();
});

test("feeds:refresh surfaces service and shape errors", async () => {
  const serviceError = loadMainWithMocks({
    fetchImpl: async () => ({
      ok: false,
      status: 503,
      text: async () => "Service unavailable",
    }),
  });

  await assert.rejects(
    () => serviceError.handlers["feeds:refresh"](null, null),
    /Service error \(503\): Service unavailable/
  );
  await serviceError.restore();

  const shapeError = loadMainWithMocks({
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      text: async () => JSON.stringify({ wrong: true }),
    }),
  });

  await assert.rejects(
    () => shapeError.handlers["feeds:refresh"](null, null),
    /Unexpected service response shape/,
  );

  await shapeError.restore();
});

test("link:open validates URL and opens external links", async () => {
  const loaded = loadMainWithMocks();

  await assert.rejects(
    () => loaded.handlers["link:open"](null, "mailto:test@example.com"),
    /Invalid URL/
  );

  const opened = await loaded.handlers["link:open"](null, "https://example.com");
  assert.equal(opened, true);
  assert.deepEqual(loaded.openExternalCalls, ["https://example.com"]);

  await loaded.restore();
});
