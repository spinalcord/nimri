import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { delimiter, dirname, extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  app,
  BrowserWindow,
  ipcMain,
  protocol,
  session,
} from 'electron';

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const isDevelopment = !app.isPackaged;
const isWindows = process.platform === 'win32';
const developmentOrigin = 'http://127.0.0.1:5173';
const releaseUrl = 'nimri://app/';
const maximumRequestIdLength = 128;
const shutdownTimeoutMilliseconds = 1_500;
const readyTimeoutMilliseconds = 10_000;
const channels = Object.freeze({
  invoke: 'nimri:invoke',
  cancel: 'nimri:cancel',
  result: 'nimri:result',
  streamEvent: 'nimri:stream-event',
  sidecarError: 'nimri:sidecar-error',
});
const contentTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.ico', 'image/x-icon'],
  ['.jpeg', 'image/jpeg'],
  ['.jpg', 'image/jpeg'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.webp', 'image/webp'],
  ['.woff', 'font/woff'],
  ['.woff2', 'font/woff2'],
]);
const releaseContentSecurityPolicy = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self'",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'none'",
  "frame-ancestors 'none'",
].join('; ');
const developmentContentSecurityPolicy = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data:",
  "font-src 'self' data:",
  `connect-src 'self' ws://127.0.0.1:5173 ${developmentOrigin}`,
  "object-src 'none'",
  "base-uri 'none'",
  "frame-ancestors 'none'",
].join('; ');

protocol.registerSchemesAsPrivileged([{
  scheme: 'nimri',
  privileges: {
    secure: true,
    standard: true,
    supportFetchAPI: true,
    corsEnabled: false,
  },
}]);

function isPlainObject(value) {
  return typeof value === 'object'
    && value !== null
    && !Array.isArray(value)
    && Object.getPrototypeOf(value) === Object.prototype;
}

function validateRequestId(requestId) {
  if (typeof requestId !== 'string'
      || requestId.length === 0
      || requestId.length > maximumRequestIdLength) {
    throw new Error('RPC requestId must be a non-empty, bounded string.');
  }
}

function validateInvokeRequest(request) {
  if (!isPlainObject(request)) {
    throw new Error('RPC invoke payload must be an object.');
  }
  const keys = Object.keys(request).sort();
  if (keys.join(',') !== 'args,command,requestId') {
    throw new Error('RPC invoke payload has unexpected fields.');
  }
  validateRequestId(request.requestId);
  if (typeof request.command !== 'string' || request.command.length === 0) {
    throw new Error('RPC command must be a non-empty string.');
  }
  if (!isPlainObject(request.args)) {
    throw new Error('RPC args must be an object.');
  }
}

function senderIsTrusted(event, mainWindow) {
  if (mainWindow === null
      || event.sender !== mainWindow.webContents
      || event.senderFrame !== mainWindow.webContents.mainFrame) {
    return false;
  }

  try {
    const senderUrl = new URL(event.senderFrame.url);
    if (isDevelopment) {
      return senderUrl.origin === developmentOrigin;
    }
    return senderUrl.protocol === 'nimri:' && senderUrl.hostname === 'app';
  } catch {
    return false;
  }
}

function validateSidecarMessage(message) {
  if (!isPlainObject(message) || typeof message.kind !== 'string') {
    throw new Error('The Nim sidecar emitted an invalid message.');
  }
  if (message.kind === 'ready') {
    return;
  }

  validateRequestId(message.requestId);
  switch (message.kind) {
    case 'accepted':
    case 'streamComplete':
      return;
    case 'result':
      if (typeof message.ok !== 'boolean') {
        break;
      }
      if (message.ok ? !('value' in message) : typeof message.error !== 'string') {
        break;
      }
      return;
    case 'streamValue':
      if ('value' in message) {
        return;
      }
      break;
    case 'streamError':
      if (typeof message.error === 'string') {
        return;
      }
      break;
    default:
      break;
  }
  throw new Error(`The Nim sidecar emitted an invalid ${message.kind} message.`);
}

class NimSidecar {
  child = null;
  buffer = '';
  pendingResponses = new Map();
  readyResolve = null;
  readyReject = null;
  readyTimer = null;
  expectedExit = false;

  constructor(onEvent, onUnexpectedExit) {
    this.onEvent = onEvent;
    this.onUnexpectedExit = onUnexpectedExit;
  }

  start() {
    if (this.child !== null) {
      throw new Error('The Nim sidecar is already running.');
    }

    const executable = isDevelopment
      ? join(projectDirectory, isWindows ? 'main.exe' : 'main')
      : join(process.resourcesPath, 'sidecar',
        isWindows ? 'nimri-sidecar.exe' : 'nimri-sidecar');
    const environment = { ...process.env };
    const sidecarDirectory = dirname(executable);
    const pathKey = Object.keys(environment).find(
      (key) => key.toLowerCase() === 'path',
    ) ?? (isWindows ? 'Path' : 'PATH');
    environment[pathKey] = sidecarDirectory
      + (environment[pathKey] ? `${delimiter}${environment[pathKey]}` : '');

    this.child = spawn(executable, ['serve'], {
      cwd: sidecarDirectory,
      env: environment,
      shell: false,
      stdio: ['pipe', 'pipe', 'pipe'],
      windowsHide: true,
    });
    this.child.stdout.setEncoding('utf8');
    this.child.stderr.setEncoding('utf8');
    this.child.stdout.on('data', (chunk) => this.consumeOutput(chunk));
    this.child.stderr.on('data', (chunk) => process.stderr.write(chunk));
    this.child.on('error', (error) => this.handleExit(error));
    this.child.on('close', (code, signal) => {
      const reason = signal === null
        ? `exit code ${code}`
        : `signal ${signal}`;
      this.handleExit(new Error(`The Nim sidecar stopped with ${reason}.`));
    });

    return new Promise((resolveReady, rejectReady) => {
      this.readyResolve = resolveReady;
      this.readyReject = rejectReady;
      this.readyTimer = setTimeout(() => {
        this.handleExit(new Error('The Nim sidecar did not become ready in time.'));
      }, readyTimeoutMilliseconds);
    });
  }

  request(message) {
    if (this.child === null || this.child.exitCode !== null
        || this.child.stdin.destroyed) {
      return Promise.reject(new Error('The Nim sidecar is unavailable.'));
    }
    if (this.pendingResponses.has(message.requestId)) {
      return Promise.reject(new Error(
        `RPC request '${message.requestId}' is already awaiting a response.`,
      ));
    }

    return new Promise((resolveResponse, rejectResponse) => {
      this.pendingResponses.set(message.requestId, {
        resolve: resolveResponse,
        reject: rejectResponse,
      });
      this.child.stdin.write(`${JSON.stringify(message)}\n`, (error) => {
        if (!error) {
          return;
        }
        const pending = this.pendingResponses.get(message.requestId);
        if (pending) {
          this.pendingResponses.delete(message.requestId);
          pending.reject(error);
        }
      });
    });
  }

  consumeOutput(chunk) {
    this.buffer += chunk;
    while (true) {
      const lineEnd = this.buffer.indexOf('\n');
      if (lineEnd < 0) {
        return;
      }
      const line = this.buffer.slice(0, lineEnd).trimEnd();
      this.buffer = this.buffer.slice(lineEnd + 1);
      if (line.length === 0) {
        continue;
      }

      let message;
      try {
        message = JSON.parse(line);
        validateSidecarMessage(message);
      } catch (error) {
        this.handleExit(error instanceof Error ? error : new Error(String(error)));
        return;
      }
      this.routeMessage(message);
    }
  }

  routeMessage(message) {
    if (message.kind === 'ready') {
      if (this.readyResolve === null) {
        this.handleExit(new Error('The Nim sidecar sent a duplicate ready message.'));
        return;
      }
      clearTimeout(this.readyTimer);
      const resolveReady = this.readyResolve;
      this.readyResolve = null;
      this.readyReject = null;
      resolveReady();
      return;
    }

    if (message.kind === 'accepted' || message.kind === 'result') {
      const pending = this.pendingResponses.get(message.requestId);
      if (pending) {
        this.pendingResponses.delete(message.requestId);
        pending.resolve(message);
        return;
      }
    }
    this.onEvent(message);
  }

  handleExit(error) {
    if (this.child === null) {
      return;
    }
    const wasExpected = this.expectedExit;
    const child = this.child;
    this.child = null;
    clearTimeout(this.readyTimer);
    if (this.readyReject !== null) {
      this.readyReject(error);
      this.readyResolve = null;
      this.readyReject = null;
    }
    for (const pending of this.pendingResponses.values()) {
      pending.reject(error);
    }
    this.pendingResponses.clear();
    if (!child.killed && child.exitCode === null) {
      child.kill();
    }
    if (!wasExpected) {
      this.onUnexpectedExit(error);
    }
  }

  async stop() {
    if (this.child === null) {
      return;
    }
    this.expectedExit = true;
    const child = this.child;
    child.stdin.end();

    await new Promise((resolveStopped) => {
      const timeout = setTimeout(() => {
        if (child.exitCode === null) {
          child.kill();
        }
      }, shutdownTimeoutMilliseconds);
      child.once('close', () => {
        clearTimeout(timeout);
        resolveStopped();
      });
    });
  }
}

let mainWindow = null;
let shuttingDown = false;
let shutdownComplete = false;

function sendToRenderer(channel, payload) {
  if (mainWindow !== null && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send(channel, payload);
  }
}

const sidecar = new NimSidecar(
  (message) => {
    if (message.kind === 'result') {
      sendToRenderer(channels.result, message);
    } else {
      sendToRenderer(channels.streamEvent, message);
    }
  },
  (error) => {
    sendToRenderer(channels.sidecarError, error.message);
    if (!shuttingDown) {
      shuttingDown = true;
      setImmediate(() => app.quit());
    }
  },
);

function installIpcHandlers() {
  ipcMain.handle(channels.invoke, async (event, request) => {
    if (!senderIsTrusted(event, mainWindow)) {
      throw new Error('Rejected RPC from an untrusted renderer.');
    }
    validateInvokeRequest(request);
    return sidecar.request({ kind: 'invoke', ...request });
  });
  ipcMain.handle(channels.cancel, async (event, requestId) => {
    if (!senderIsTrusted(event, mainWindow)) {
      throw new Error('Rejected RPC cancellation from an untrusted renderer.');
    }
    validateRequestId(requestId);
    return sidecar.request({ kind: 'cancel', requestId });
  });
}

function installReleaseProtocol() {
  protocol.handle('nimri', async (request) => {
    try {
      const requestUrl = new URL(request.url);
      if (requestUrl.hostname !== 'app') {
        return new Response('Not found', { status: 404 });
      }

      const frontendDirectory = resolve(app.getAppPath(), 'frontend', 'dist');
      const decodedPath = decodeURIComponent(requestUrl.pathname);
      const relativePath = decodedPath === '/'
        ? 'index.html'
        : decodedPath.replace(/^\/+/, '');
      const assetPath = resolve(frontendDirectory, relativePath);
      if (assetPath !== frontendDirectory
          && !assetPath.startsWith(`${frontendDirectory}${sep}`)) {
        return new Response('Forbidden', { status: 403 });
      }

      const contents = await readFile(assetPath);
      return new Response(contents, {
        headers: {
          'Content-Security-Policy': releaseContentSecurityPolicy,
          'Content-Type': contentTypes.get(extname(assetPath).toLowerCase())
            ?? 'application/octet-stream',
          'X-Content-Type-Options': 'nosniff',
        },
      });
    } catch {
      return new Response('Not found', { status: 404 });
    }
  });
}

function installSessionSecurity() {
  session.defaultSession.setPermissionCheckHandler(() => false);
  session.defaultSession.setPermissionRequestHandler(
    (_webContents, _permission, callback) => callback(false),
  );
  if (isDevelopment) {
    session.defaultSession.webRequest.onHeadersReceived(
      { urls: [`${developmentOrigin}/*`] },
      (details, callback) => callback({
        responseHeaders: {
          ...details.responseHeaders,
          'Content-Security-Policy': [developmentContentSecurityPolicy],
          'X-Content-Type-Options': ['nosniff'],
        },
      }),
    );
  }
}

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 640,
    show: false,
    title: 'Nimri',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: join(projectDirectory, 'electron', 'preload.cjs'),
      sandbox: true,
      webviewTag: false,
    },
  });
  mainWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  mainWindow.webContents.on('will-navigate', (event, navigationUrl) => {
    try {
      const parsedUrl = new URL(navigationUrl);
      const allowed = isDevelopment
        ? parsedUrl.origin === developmentOrigin
        : parsedUrl.protocol === 'nimri:' && parsedUrl.hostname === 'app';
      if (allowed) {
        return;
      }
    } catch {
      // Invalid navigation targets are blocked below.
    }
    event.preventDefault();
  });
  mainWindow.once('ready-to-show', () => mainWindow?.show());
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
  await mainWindow.loadURL(isDevelopment ? developmentOrigin : releaseUrl);
}

async function shutdown() {
  if (shutdownComplete) {
    return;
  }
  shuttingDown = true;
  await sidecar.stop();
  shutdownComplete = true;
}

app.on('before-quit', (event) => {
  if (shutdownComplete) {
    return;
  }
  event.preventDefault();
  void shutdown().finally(() => app.quit());
});

app.on('window-all-closed', () => app.quit());

async function startApplication() {
  installSessionSecurity();
  if (!isDevelopment) {
    installReleaseProtocol();
  }
  installIpcHandlers();
  await sidecar.start();
  await createWindow();
}

void app.whenReady().then(startApplication).catch(async (error) => {
  console.error(error instanceof Error ? error.message : error);
  await shutdown();
  app.exit(1);
});
