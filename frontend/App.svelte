<script lang="ts">
  import { onMount } from 'svelte';
  import { greet } from './commands/greeting';

  let name = 'Mara';
  let greeting = 'Press The Button to Change this text';
  let count: number = 0;


  async function refreshGreeting() {
    greeting = (await greet(name)).some_message;
  }

  // onMount(refreshGreeting);
</script>

<main>
  <h1>{greeting}</h1>

  <button on:click={refreshGreeting}>Call Nim</button>
</main>

<style></style>
