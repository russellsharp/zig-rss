const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("rssWidget", {
  refreshFeeds: (configPath) => ipcRenderer.invoke("feeds:refresh", configPath),
  loadConfig:   (configPath) => ipcRenderer.invoke("feeds:load-config", configPath),
  openLink:     (url)        => ipcRenderer.invoke("link:open", url),
});
