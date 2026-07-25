import { greet } from 'commands/greeting';

void greet('Mara');

// @ts-expect-error The generated wrapper requires the Nim argument.
void greet();

// @ts-expect-error Nim string parameters only accept strings.
void greet(32);
