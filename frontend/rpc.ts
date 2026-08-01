// FIX: Remove the unused RPC response type.

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

type PendingStreamRead<T> = {
  resolve: (result: IteratorResult<T>) => void;
  reject: (reason: Error) => void;
};

type StreamEvent =
  | { kind: 'value'; value: unknown }
  | { kind: 'complete' }
  | { kind: 'error'; error: string };

export interface NimriStream<T> extends AsyncIterableIterator<T> {
  cancel(): Promise<void>;
}

type WebUiWindow = Window & {
  __invoke?: (request: string) => Promise<string> | string;
  __nimriRpcCancel?: (requestId: string) => Promise<string> | string;
  __nimriRpcComplete?: (requestId: string, response: unknown) => void;
  __nimriRpcStreamEvent?: (requestId: string, event: unknown) => void;
};

const BRIDGE_STARTUP_TIMEOUT_MS = 2_000;
const BRIDGE_RETRY_DELAY_MS = 20;
const pendingRequests = new Map<string, PendingRequest>();
const activeStreams = new Map<string, NimriStreamImplementation<unknown>>();

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function callBridge(
  bindingName: '__invoke' | '__nimriRpcCancel',
  payload: string,
): Promise<string> {
  const deadline = Date.now() + BRIDGE_STARTUP_TIMEOUT_MS;

  while (Date.now() < deadline) {
    const bridge = (window as WebUiWindow)[bindingName];
    if (typeof bridge === 'function') {
      try {
        return await bridge(payload);
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

function asError(reason: unknown): Error {
  return reason instanceof Error ? reason : new Error(String(reason));
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

class NimriStreamImplementation<T> implements NimriStream<T> {
  private requestId: string | null = null;
  private startPromise: Promise<boolean> | null = null;
  private cancelPromise: Promise<void> | null = null;
  private readonly values: T[] = [];
  private readonly pendingReads: PendingStreamRead<T>[] = [];
  private terminalError: Error | null = null;
  private completed = false;
  private canceled = false;
  private iteratorClaimed = false;
  private directReadStarted = false;

  constructor(
    private readonly command: string,
    private readonly args: Record<string, unknown>,
  ) {}

  [Symbol.asyncIterator](): AsyncIterableIterator<T> {
    if (this.iteratorClaimed || this.directReadStarted) {
      throw new Error('A NimriStream can only be consumed once.');
    }
    this.iteratorClaimed = true;
    return this;
  }

  next(): Promise<IteratorResult<T>> {
    if (!this.iteratorClaimed) {
      this.directReadStarted = true;
    }

    if (this.values.length > 0) {
      return Promise.resolve({ value: this.values.shift()!, done: false });
    }
    if (this.terminalError !== null) {
      return Promise.reject(this.terminalError);
    }
    if (this.completed || this.canceled) {
      return Promise.resolve({ value: undefined, done: true });
    }

    const result = new Promise<IteratorResult<T>>((resolve, reject) => {
      this.pendingReads.push({ resolve, reject });
    });
    this.start();
    return result;
  }

  async return(): Promise<IteratorResult<T>> {
    await this.cancel();
    return { value: undefined, done: true };
  }

  cancel(): Promise<void> {
    if (this.cancelPromise !== null) {
      return this.cancelPromise;
    }
    if (this.completed || this.terminalError !== null) {
      this.cancelPromise = Promise.resolve();
      return this.cancelPromise;
    }

    this.canceled = true;
    this.values.length = 0;
    this.resolvePendingDone();

    if (this.requestId === null || this.startPromise === null) {
      this.cancelPromise = Promise.resolve();
      return this.cancelPromise;
    }

    activeStreams.delete(this.requestId);
    const requestId = this.requestId;
    this.cancelPromise = this.startPromise.then(async (accepted) => {
      if (!accepted) {
        return;
      }
      const rawResponse = await callBridge('__nimriRpcCancel', requestId);
      let response: unknown;
      try {
        response = JSON.parse(rawResponse) as unknown;
      } catch {
        throw new Error('The Nim RPC cancellation response is not valid JSON.');
      }
      if (typeof response !== 'object' || response === null
          || !('ok' in response) || response.ok !== true) {
        throw new Error('The Nim RPC cancellation response is invalid.');
      }
    });
    return this.cancelPromise;
  }

  receive(event: StreamEvent): void {
    if (this.canceled || this.completed || this.terminalError !== null) {
      return;
    }

    switch (event.kind) {
      case 'value': {
        const value = event.value as T;
        const pending = this.pendingReads.shift();
        if (pending) {
          pending.resolve({ value, done: false });
        } else {
          this.values.push(value);
        }
        break;
      }
      case 'complete':
        this.completed = true;
        this.removeFromActiveStreams();
        this.resolvePendingDone();
        break;
      case 'error':
        this.terminalError = new Error(event.error);
        this.removeFromActiveStreams();
        this.rejectPending(this.terminalError);
        break;
    }
  }

  private start(): void {
    if (this.startPromise !== null) {
      return;
    }

    this.requestId = crypto.randomUUID();
    activeStreams.set(
      this.requestId,
      this as unknown as NimriStreamImplementation<unknown>,
    );
    this.startPromise = this.open(this.requestId).catch((reason: unknown) => {
      this.fail(asError(reason));
      return false;
    });
  }

  private async open(requestId: string): Promise<boolean> {
    let request: string;
    try {
      request = JSON.stringify({
        requestId,
        command: this.command,
        args: this.args,
      });
    } catch (reason) {
      throw asError(reason);
    }

    const rawResponse = await callBridge('__invoke', request);
    let response: unknown;
    try {
      response = JSON.parse(rawResponse) as unknown;
    } catch {
      throw new Error('The Nim RPC stream response is not valid JSON.');
    }

    if (typeof response !== 'object' || response === null) {
      throw new Error('The Nim RPC stream response has an invalid shape.');
    }
    if ('kind' in response) {
      const accepted = response as Partial<AcceptedResponse>;
      if (accepted.kind === BridgeResponseKind.Accepted
          && accepted.requestId === requestId) {
        return true;
      }
      throw new Error('The Nim RPC stream acceptance response is invalid.');
    }
    if ('ok' in response && response.ok === false
        && 'error' in response && typeof response.error === 'string') {
      throw new Error(response.error);
    }
    throw new Error('The Nim RPC stream response has an invalid shape.');
  }

  private fail(error: Error): void {
    if (this.canceled || this.completed || this.terminalError !== null) {
      return;
    }
    this.terminalError = error;
    this.removeFromActiveStreams();
    this.rejectPending(error);
  }

  private removeFromActiveStreams(): void {
    if (this.requestId !== null
        && activeStreams.get(this.requestId) === this) {
      activeStreams.delete(this.requestId);
    }
  }

  private resolvePendingDone(): void {
    for (const pending of this.pendingReads.splice(0)) {
      pending.resolve({ value: undefined, done: true });
    }
  }

  private rejectPending(error: Error): void {
    for (const pending of this.pendingReads.splice(0)) {
      pending.reject(error);
    }
  }
}

function parseStreamEvent(event: unknown): StreamEvent | null {
  if (typeof event !== 'object' || event === null || !('kind' in event)) {
    return null;
  }
  if (event.kind === 'value' && 'value' in event) {
    return { kind: 'value', value: event.value };
  }
  if (event.kind === 'complete') {
    return { kind: 'complete' };
  }
  if (event.kind === 'error'
      && 'error' in event && typeof event.error === 'string') {
    return { kind: 'error', error: event.error };
  }
  return null;
}

(window as WebUiWindow).__nimriRpcStreamEvent = (
  requestId: string,
  rawEvent: unknown,
): void => {
  const stream = activeStreams.get(requestId);
  if (!stream) {
    return;
  }
  const event = parseStreamEvent(rawEvent);
  if (event === null) {
    stream.receive({
      kind: 'error',
      error: 'The Nim RPC stream event has an invalid shape.',
    });
    return;
  }
  stream.receive(event);
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

    void callBridge('__invoke', request)
      .then((rawResponse) => handleBridgeResponse(requestId, rawResponse))
      .catch((reason: unknown) => {
        const pending = pendingRequests.get(requestId);
        if (!pending) {
          return;
        }
        pendingRequests.delete(requestId);
        pending.reject(
          asError(reason),
        );
      });
  });
}

export function invokeStream<T>(
  command: string,
  args: Record<string, unknown> = {},
): NimriStream<T> {
  return new NimriStreamImplementation<T>(command, args);
}
