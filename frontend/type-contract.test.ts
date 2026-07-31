import { greet } from 'rpc/commands/greeting';
import type { Greeting } from 'rpc/types';

const greeting: Greeting = { message: 'Hello from TypeScript' };
void greeting;

void greet('Mara');

// @ts-expect-error The generated wrapper requires the Nim argument.
void greet();

// @ts-expect-error Nim string parameters only accept strings.
void greet(32);
