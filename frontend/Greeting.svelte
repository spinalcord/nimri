<script lang="ts">
  import { greet } from 'rpc/commands/greeting';
  import { type SomeEnumType } from 'rpc/types';
  import { determineEnumType } from 'rpc/commands/greeting';
  
  let name = 'Mara';
  let message = '';

  async function callGreeting() {
    message = (await greet(name)).message;
  }

  async function outputSomeEnumtype(typeValue: SomeEnumType) {
    determineEnumType(typeValue)
  }


</script>

<article class="greeting-card">
  <label>
    Name
    <input bind:value={name} />
  </label>
  <button on:click={callGreeting}>Greet</button>
  <button on:click={() => outputSomeEnumtype("Bar")}>Greet</button>
  {#if message}<output>{message}</output>{/if}
</article>
