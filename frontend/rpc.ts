type InvokeResponse<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

type WebUiWindow = Window & {
  __invoke?: (request: string) => Promise<string> | string;
};

const BRIDGE_STARTUP_TIMEOUT_MS = 2_000;
const BRIDGE_RETRY_DELAY_MS = 20;

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

export async function invoke<T>(
  command: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const rawResponse = await callBridge(JSON.stringify({ command, args }));

  let response: InvokeResponse<T>;
  try {
    response = JSON.parse(rawResponse) as InvokeResponse<T>;
  } catch {
    throw new Error('The Nim RPC response is not valid JSON.');
  }

  if (!response.ok) {
    throw new Error(response.error);
  }

  return response.value;
}
