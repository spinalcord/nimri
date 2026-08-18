<script lang="ts">
  import { onMount } from 'svelte';
  import {
    frameworkInfo,
    loadOverview,
    streamActivity,
  } from 'rpc/commands/showcase';
  import type { ActivityEvent, ShowcaseOverview } from 'rpc/types';
  import type { NimriStream } from './rpc';

  let immediateOverview: ShowcaseOverview | null = null;
  let immediateError: string | null = null;
  let overview: ShowcaseOverview | null = null;
  let overviewError: string | null = null;
  let overviewLoading = false;
  let activityEvents: ActivityEvent[] = [];
  let activityError: string | null = null;
  let streaming = false;
  let activeStream: NimriStream<ActivityEvent> | null = null;

  onMount(() => {
    void loadFrameworkInfo();
    void refreshOverview();
  });

  async function loadFrameworkInfo() {
    try {
      immediateOverview = await frameworkInfo();
    } catch (reason) {
      immediateError = reason instanceof Error ? reason.message : String(reason);
    }
  }

  async function refreshOverview() {
    overviewLoading = true;
    overviewError = null;
    try {
      overview = await loadOverview();
    } catch (reason) {
      overviewError = reason instanceof Error ? reason.message : String(reason);
    } finally {
      overviewLoading = false;
    }
  }

  async function startActivity() {
    if (streaming) {
      return;
    }

    activityEvents = [];
    activityError = null;
    streaming = true;
    const stream = streamActivity();
    activeStream = stream;

    try {
      for await (const event of stream) {
        activityEvents = [...activityEvents, event];
      }
    } catch (reason) {
      activityError = reason instanceof Error ? reason.message : String(reason);
    } finally {
      if (activeStream === stream) {
        activeStream = null;
        streaming = false;
      }
    }
  }

  async function cancelActivity() {
    if (activeStream !== null) {
      await activeStream.cancel();
    }
  }

  function resetActivity() {
    if (!streaming) {
      activityEvents = [];
      activityError = null;
    }
  }
</script>

<main class="app">
  <header class="app-header">
    <p class="eyebrow">Nimri framework</p>
    <h1>Typed Nim ↔ Svelte RPC</h1>
    <p class="app-description">
      One compact desktop showcase for immediate commands, <code>Future[T]</code>,
      and cancellable <code>FutureStream[T]</code> values.
    </p>
  </header>

  <section class="overview-bar" aria-label="Framework information">
    {#if immediateOverview}
      <span>{immediateOverview.application}</span>
      <span>{immediateOverview.framework}</span>
      <span>{immediateOverview.transport}</span>
    {:else if immediateError}
      <span class="error">Could not load framework information: {immediateError}</span>
    {:else}
      <span>Connecting to the Nim sidecar…</span>
    {/if}
  </section>

  <div class="showcase-grid">
    <section class="showcase-card" aria-labelledby="future-title">
      <div class="card-heading">
        <div>
          <p class="card-kicker">Future[ShowcaseOverview]</p>
          <h2 id="future-title">Async overview</h2>
        </div>
        <button type="button" on:click={refreshOverview} disabled={overviewLoading}>
          {overviewLoading ? 'Loading…' : 'Load again'}
        </button>
      </div>

      {#if overviewLoading}
        <p class="state-message" aria-live="polite">Waiting for the simulated Nim data fetch…</p>
      {:else if overviewError}
        <p class="state-message error" role="alert">{overviewError}</p>
      {:else if overview}
        <dl class="overview-data">
          <div><dt>Application</dt><dd>{overview.application}</dd></div>
          <div><dt>Framework</dt><dd>{overview.framework}</dd></div>
          <div><dt>Transport</dt><dd>{overview.transport}</dd></div>
        </dl>
        <p class="state-message success">{overview.detail}</p>
      {/if}
    </section>

    <section class="showcase-card" aria-labelledby="stream-title">
      <div class="card-heading">
        <div>
          <p class="card-kicker">FutureStream[ActivityEvent]</p>
          <h2 id="stream-title">Live activity</h2>
        </div>
        <span class:live={streaming} class="stream-status">
          <span class="status-dot"></span>{streaming ? 'Live' : 'Idle'}
        </span>
      </div>

      <div class="controls" aria-label="Activity stream controls">
        <button type="button" on:click={startActivity} disabled={streaming}>Start stream</button>
        <button type="button" class="secondary" on:click={cancelActivity} disabled={!streaming}>Cancel</button>
        <button type="button" class="secondary" on:click={resetActivity} disabled={streaming}>Reset</button>
      </div>

      {#if activityError}
        <p class="state-message error" role="alert">{activityError}</p>
      {:else if activityEvents.length === 0}
        <p class="state-message">Start the stream to receive typed activity events.</p>
      {:else}
        <ol class="activity-list" aria-live="polite">
          {#each activityEvents as event}
            <li>
              <span class="phase">{event.phase}</span>
              <span>{event.message}</span>
              <time>{event.elapsedMilliseconds} ms</time>
            </li>
          {/each}
        </ol>
      {/if}
    </section>
  </div>

</main>
