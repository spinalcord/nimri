<script lang="ts">
  import { greet, streamMessages } from 'rpc/commands/greeting';
  import { type SomeEnumType } from 'rpc/types';
  import { determineEnumType } from 'rpc/commands/greeting';
  
  let name = 'Mara';
  let message = '';
  let streamValues: string[] = [];

  async function callGreeting() {
    message = (await greet(name)).message;
  }

  async function outputSomeEnumtype(typeValue: SomeEnumType) {
    determineEnumType(typeValue)
  }

  async function readStream() {
    streamValues = [];
    for await (const value of streamMessages()) {
      streamValues = [...streamValues, value];
    }
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
  <button on:click={readStream}>Read async stream</button>
  {#each streamValues as value}
    <output>{value}</output>
  {/each}
</article>
