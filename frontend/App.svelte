<script lang="ts">
  import Greeting from './Greeting.svelte';
</script>

<main class="app">
  <header class="app-header">
    <p class="eyebrow">Nimri framework</p>
    <h1>Greeting</h1>
    <p class="app-description">A generated, type-safe binding from Svelte to Nim.</p>
  </header>

  <section class="greeting" aria-label="Greeting">
    <Greeting />
  </section>
</main>
