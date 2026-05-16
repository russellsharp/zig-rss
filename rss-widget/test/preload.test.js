const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const Module = require("node:module");

const preloadPath = path.join(__dirname, "..", "preload.js");

test("preload exposes rssWidget API and forwards IPC calls", async () => {
  const calls = [];
  let exposedName = "";
  let exposedApi = null;

  const electronMock = {
    contextBridge: {
      exposeInMainWorld: (name, api) => {
        exposedName = name;
        exposedApi = api;
      },
    },
    ipcRenderer: {
      invoke: async (channel, payload) => {
        calls.push([channel, payload]);
        return { channel, payload };
      },
    },
  };

  const originalLoad = Module._load;
  Module._load = function patchedLoad(request, parent, isMain) {
    if (request === "electron") return electronMock;
    return originalLoad.call(this, request, parent, isMain);
  };

  delete require.cache[preloadPath];
  require(preloadPath);

  assert.equal(exposedName, "rssWidget");
  assert.ok(exposedApi);

  await exposedApi.refreshFeeds("my-config.json");
  await exposedApi.loadConfig("config.json");
  await exposedApi.openLink("https://example.com");

  assert.deepEqual(calls, [
    ["feeds:refresh", "my-config.json"],
    ["feeds:load-config", "config.json"],
    ["link:open", "https://example.com"],
  ]);

  Module._load = originalLoad;
  delete require.cache[preloadPath];
});
