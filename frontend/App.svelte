<script lang="ts">
  import { loadGreeting } from './commands/greeting';

  let name = 'Mara';
  let greeting = '';
  let loading = false;

  async function load() {
    loading = true;
    try {
      greeting = (await loadGreeting(name)).some_message;
    } finally {
      loading = false;
    }
  }
</script>

<main>
  <input bind:value={name} />
  <button on:click={load} disabled={loading}>
    {loading ? 'Loading…' : 'Load greeting'}
  </button>

  <p>{greeting}</p>
</main>

<style></style>
