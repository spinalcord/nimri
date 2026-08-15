const { contextBridge, ipcRenderer } = require('electron');

const channels = Object.freeze({
  invoke: 'nimri:invoke',
  cancel: 'nimri:cancel',
  result: 'nimri:result',
  streamEvent: 'nimri:stream-event',
  sidecarError: 'nimri:sidecar-error',
});

contextBridge.exposeInMainWorld('nimri', Object.freeze({
  invoke: (request) => ipcRenderer.invoke(channels.invoke, request),
  cancel: (requestId) => ipcRenderer.invoke(channels.cancel, requestId),
  onResult: (listener) => {
    const handler = (_event, response) => listener(response);
    ipcRenderer.on(channels.result, handler);
    return () => ipcRenderer.removeListener(channels.result, handler);
  },
  onStreamEvent: (listener) => {
    const handler = (_event, streamEvent) => listener(streamEvent);
    ipcRenderer.on(channels.streamEvent, handler);
    return () => ipcRenderer.removeListener(channels.streamEvent, handler);
  },
  onSidecarError: (listener) => {
    const handler = (_event, message) => listener(message);
    ipcRenderer.on(channels.sidecarError, handler);
    return () => ipcRenderer.removeListener(channels.sidecarError, handler);
  },
}));
