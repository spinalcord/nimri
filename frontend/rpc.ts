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

const pendingRequests = new Map<string, PendingRequest>();
const activeStreams = new Map<string, NimriStreamImplementation<unknown>>();

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

function completeRequest(response: NimriResultResponse): void {
  const pending = pendingRequests.get(response.requestId);
  if (!pending) {
    return;
  }

  pendingRequests.delete(response.requestId);
  if (response.ok) {
    pending.resolve(response.value);
  } else {
    pending.reject(new Error(response.error));
  }
}

function handleInvokeResponse(
  requestId: string,
  response: NimriAcceptedResponse | NimriResultResponse,
): void {
  if (response.requestId !== requestId) {
    protocolError(requestId, 'The Nim RPC response has the wrong requestId.');
    return;
  }
  if (response.kind === 'result') {
    completeRequest(response);
  }
}

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
      const response = await window.nimri.cancel(requestId);
      if (response.requestId !== requestId || !response.ok) {
        throw new Error(
          response.ok
            ? 'The Nim RPC cancellation response is invalid.'
            : response.error,
        );
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
        this.fail(new Error(event.error));
        break;
    }
  }

  fail(error: Error): void {
    if (this.canceled || this.completed || this.terminalError !== null) {
      return;
    }
    this.terminalError = error;
    this.removeFromActiveStreams();
    for (const pending of this.pendingReads.splice(0)) {
      pending.reject(error);
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
    const response = await window.nimri.invoke({
      requestId,
      command: this.command,
      args: this.args,
    });
    if (response.requestId !== requestId) {
      throw new Error('The Nim RPC stream response has the wrong requestId.');
    }
    if (response.kind === 'accepted') {
      return true;
    }
    if (!response.ok) {
      throw new Error(response.error);
    }
    throw new Error('The Nim RPC stream was not accepted.');
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
}

window.nimri.onResult(completeRequest);
window.nimri.onStreamEvent((event) => {
  const stream = activeStreams.get(event.requestId);
  if (!stream) {
    return;
  }
  switch (event.kind) {
    case 'streamValue':
      stream.receive({ kind: 'value', value: event.value });
      break;
    case 'streamComplete':
      stream.receive({ kind: 'complete' });
      break;
    case 'streamError':
      stream.receive({ kind: 'error', error: event.error });
      break;
  }
});
window.nimri.onSidecarError((message) => {
  const error = new Error(message);
  for (const pending of pendingRequests.values()) {
    pending.reject(error);
  }
  pendingRequests.clear();
  for (const stream of activeStreams.values()) {
    stream.fail(error);
  }
  activeStreams.clear();
});

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
    void window.nimri.invoke({ requestId, command, args })
      .then((response) => handleInvokeResponse(requestId, response))
      .catch((reason: unknown) => {
        const pending = pendingRequests.get(requestId);
        if (!pending) {
          return;
        }
        pendingRequests.delete(requestId);
        pending.reject(asError(reason));
      });
  });
}

export function invokeStream<T>(
  command: string,
  args: Record<string, unknown> = {},
): NimriStream<T> {
  return new NimriStreamImplementation<T>(command, args);
}
