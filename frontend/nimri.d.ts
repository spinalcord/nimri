type NimriInvokeRequest = {
  requestId: string;
  command: string;
  args: Record<string, unknown>;
};

type NimriAcceptedResponse = {
  kind: 'accepted';
  requestId: string;
};

type NimriResultResponse = {
  kind: 'result';
  requestId: string;
} & (
  | { ok: true; value: unknown }
  | { ok: false; error: string }
);

type NimriStreamEvent =
  | { kind: 'streamValue'; requestId: string; value: unknown }
  | { kind: 'streamComplete'; requestId: string }
  | { kind: 'streamError'; requestId: string; error: string };

interface Window {
  nimri: {
    invoke(request: NimriInvokeRequest): Promise<
      NimriAcceptedResponse | NimriResultResponse
    >;
    cancel(requestId: string): Promise<NimriResultResponse>;
    onResult(listener: (response: NimriResultResponse) => void): () => void;
    onStreamEvent(listener: (event: NimriStreamEvent) => void): () => void;
    onSidecarError(listener: (message: string) => void): () => void;
  };
}
