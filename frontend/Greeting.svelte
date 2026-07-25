<script lang="ts">
  import { greet } from 'commands/greeting';

  let name = 'Mara';
  let message = '';

  async function callGreeting() {
    message = (await greet(name)).message;
  }
</script>

<article class="greeting-card">
  <label>
    Name
    <input bind:value={name} />
  </label>
  <button on:click={callGreeting}>Greet</button>
  {#if message}<output>{message}</output>{/if}
</article>
