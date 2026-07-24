type InvokeResponse<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

enum BridgeResponseKind {
  Accepted = 'accepted',
}

type AcceptedResponse = {
  kind: BridgeResponseKind.Accepted;
  requestId: string;
};

type PendingRequest = {
  resolve: (value: unknown) => void;
  reject: (reason: Error) => void;
};

type WebUiWindow = Window & {
  __invoke?: (request: string) => Promise<string> | string;
  __nimriRpcComplete?: (requestId: string, response: unknown) => void;
};

const BRIDGE_STARTUP_TIMEOUT_MS = 2_000;
const BRIDGE_RETRY_DELAY_MS = 20;
const pendingRequests = new Map<string, PendingRequest>();

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function callBridge(request: string): Promise<string> {
  const deadline = Date.now() + BRIDGE_STARTUP_TIMEOUT_MS;

  while (Date.now() < deadline) {
    const bridge = (window as WebUiWindow).__invoke;
    if (typeof bridge === 'function') {
      try {
        return await bridge(request);
      } catch (reason) {
        const bridgeIsConnecting = reason instanceof Error
          && reason.message === 'WebSocket is not connected';
        if (!bridgeIsConnecting) {
          throw reason;
        }
      }
    }

    await delay(BRIDGE_RETRY_DELAY_MS);
  }

  throw new Error('The WebUI bridge is unavailable.');
}

function protocolError(requestId: string, message: string): void {
  const pending = pendingRequests.get(requestId);
  if (!pending) {
    return;
  }

  pendingRequests.delete(requestId);
  pending.reject(new Error(message));
}

function completeRequest(requestId: string, response: unknown): void {
  const pending = pendingRequests.get(requestId);
  if (!pending) {
    return;
  }

  if (typeof response !== 'object' || response === null
      || !('ok' in response) || typeof response.ok !== 'boolean') {
    protocolError(requestId, 'The Nim RPC response has an invalid shape.');
    return;
  }

  if (response.ok) {
    if (!('value' in response)) {
      protocolError(requestId, 'The Nim RPC response has no value.');
      return;
    }
    pendingRequests.delete(requestId);
    pending.resolve(response.value);
    return;
  }

  if (!('error' in response) || typeof response.error !== 'string') {
    protocolError(requestId, 'The Nim RPC error response is invalid.');
    return;
  }
  pendingRequests.delete(requestId);
  pending.reject(new Error(response.error));
}

function handleBridgeResponse(requestId: string, rawResponse: string): void {
  if (!pendingRequests.has(requestId)) {
    return;
  }

  let response: unknown;
  try {
    response = JSON.parse(rawResponse) as unknown;
  } catch {
    protocolError(requestId, 'The Nim RPC response is not valid JSON.');
    return;
  }

  if (typeof response === 'object' && response !== null
      && 'kind' in response) {
    const accepted = response as Partial<AcceptedResponse>;
    if (accepted.kind !== BridgeResponseKind.Accepted
        || accepted.requestId !== requestId) {
      protocolError(requestId, 'The Nim RPC acceptance response is invalid.');
    }
    return;
  }

  completeRequest(requestId, response);
}

(window as WebUiWindow).__nimriRpcComplete = (
  requestId: string,
  response: unknown,
): void => {
  completeRequest(requestId, response);
};

export function invoke<T>(
  command: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const requestId = crypto.randomUUID();

  return new Promise<T>((resolve, reject) => {
    pendingRequests.set(requestId, {
      resolve: (value) => resolve(value as T),
      reject,
    });

    let request: string;
    try {
      request = JSON.stringify({ requestId, command, args });
    } catch (reason) {
      pendingRequests.delete(requestId);
      reject(reason instanceof Error ? reason : new Error(String(reason)));
      return;
    }

    void callBridge(request)
      .then((rawResponse) => handleBridgeResponse(requestId, rawResponse))
      .catch((reason: unknown) => {
        const pending = pendingRequests.get(requestId);
        if (!pending) {
          return;
        }
        pendingRequests.delete(requestId);
        pending.reject(
          reason instanceof Error ? reason : new Error(String(reason)),
        );
      });
  });
}
