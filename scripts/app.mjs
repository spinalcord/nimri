import { spawn } from 'node:child_process';
import {
  copyFile,
  mkdir,
  mkdtemp,
  rm,
  stat,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import {
  basename,
  delimiter,
  dirname,
  extname,
  join,
  resolve,
} from 'node:path';
import { fileURLToPath } from 'node:url';

const projectDirectory = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const isWindows = process.platform === 'win32';
const applicationBinary = join(
  projectDirectory,
  isWindows ? 'main.exe' : 'main',
);
const validModes = new Set([
  'serialize',
  'generate',
  'run',
  'dev',
  'build',
  'test',
]);
const windowsRuntimeDlls = [
  'libgcc_s_seh-1.dll',
  'libstdc++-6.dll',
  'libwinpthread-1.dll',
];

class ProcessError extends Error {
  constructor(message, exitCode = 1) {
    super(message);
    this.exitCode = exitCode;
  }
}

function runProcess(command, arguments_, options = {}) {
  const { captureOutput = false, environment = process.env } = options;

  return new Promise((resolveProcess, rejectProcess) => {
    const child = spawn(command, arguments_, {
      cwd: projectDirectory,
      env: environment,
      shell: false,
      stdio: captureOutput ? ['inherit', 'pipe', 'inherit'] : 'inherit',
    });
    let output = '';

    if (captureOutput) {
      child.stdout.setEncoding('utf8');
      child.stdout.on('data', (chunk) => {
        output += chunk;
      });
    }

    child.on('error', (error) => {
      rejectProcess(new ProcessError(
        `Failed to start ${command}: ${error.message}`,
      ));
    });
    child.on('close', (exitCode, signal) => {
      if (exitCode === 0) {
        resolveProcess(output);
        return;
      }

      const reason = signal === null
        ? `exit code ${exitCode}`
        : `signal ${signal}`;
      rejectProcess(new ProcessError(
        `${command} stopped with ${reason}.`,
        exitCode ?? 1,
      ));
    });
  });
}

async function compileApplication() {
  await runProcess('nim', ['c', '--threads:on', 'main.nim']);
}

async function runApplicationMode(mode) {
  await compileApplication();
  await runProcess(applicationBinary, [mode]);
}

async function runTests() {
  const testDirectory = await mkdtemp(join(tmpdir(), 'nimri-test-'));

  try {
    for (const testSource of [
      'tests/test_nimri_rpc.nim',
      'tests/test_frontend_bindings.nim',
    ]) {
      const testName = basename(testSource, extname(testSource));
      const testBinary = join(
        testDirectory,
        isWindows ? `${testName}.exe` : testName,
      );
      const testCache = join(testDirectory, 'nimcache', testName);

      await runProcess('nim', [
        'c',
        '--threads:on',
        `--nimcache:${testCache}`,
        `-o:${testBinary}`,
        testSource,
      ]);
      await runProcess(testBinary, []);
    }
  } finally {
    await rm(testDirectory, { force: true, recursive: true });
  }
}

async function getWindowsBuildEnvironment() {
  const dump = await runProcess(
    'nim',
    ['dump', '--dump.format:json', 'main.nim'],
    { captureOutput: true },
  );
  const nimInformation = JSON.parse(dump);

  if (!nimInformation.prefixdir) {
    throw new Error('Nim did not report its prefixdir.');
  }

  const runtimeDirectory = join(
    nimInformation.prefixdir,
    'dist',
    'mingw64',
    'bin',
  );
  for (const runtimeDll of windowsRuntimeDlls) {
    const runtimePath = join(runtimeDirectory, runtimeDll);
    const runtimeFile = await stat(runtimePath).catch(() => null);
    if (!runtimeFile?.isFile()) {
      throw new Error(`Required MinGW runtime DLL was not found: ${runtimePath}`);
    }
  }

  const environment = { ...process.env };
  const pathKey = Object.keys(environment).find(
    (key) => key.toLowerCase() === 'path',
  ) ?? 'Path';
  environment[pathKey] = runtimeDirectory
    + delimiter
    + (environment[pathKey] ?? '');

  return { environment, runtimeDirectory };
}

async function buildApplication() {
  const binDirectory = join(projectDirectory, 'bin');
  await mkdir(binDirectory, { recursive: true });
  await rm(join(binDirectory, 'frontend'), { force: true, recursive: true });

  const buildDirectory = await mkdtemp(join(tmpdir(), 'nimri-build-'));
  let environment = process.env;
  let runtimeDirectory = null;

  try {
    if (isWindows) {
      const windowsBuild = await getWindowsBuildEnvironment();
      environment = windowsBuild.environment;
      runtimeDirectory = windowsBuild.runtimeDirectory;
    }

    const bootstrapBinary = join(
      buildDirectory,
      isWindows ? 'main.exe' : 'main',
    );
    await runProcess('nim', [
      'c',
      '--threads:on',
      `--nimcache:${join(buildDirectory, 'nimcache-bootstrap')}`,
      `-o:${bootstrapBinary}`,
      'main.nim',
    ], { environment });
    await runProcess(bootstrapBinary, ['generate'], { environment });
    const npmCli = process.env.npm_execpath;
    if (!npmCli) {
      throw new Error(
        'npm did not report its CLI path. Run the build through npm.',
      );
    }
    await runProcess(process.execPath, [
      npmCli,
      'run',
      'build',
      '--workspace',
      'frontend',
    ], { environment });

    const releaseBinary = join(
      binDirectory,
      isWindows ? 'main.exe' : 'main',
    );
    await runProcess('nim', [
      'c',
      '--threads:on',
      '-d:release',
      `--nimcache:${join(buildDirectory, 'nimcache-release')}`,
      `-o:${releaseBinary}`,
      'main.nim',
    ], { environment });

    if (isWindows) {
      for (const runtimeDll of windowsRuntimeDlls) {
        await copyFile(
          join(runtimeDirectory, runtimeDll),
          join(binDirectory, runtimeDll),
        );
      }
    }
  } finally {
    await rm(buildDirectory, { force: true, recursive: true });
  }
}

async function main() {
  const [mode, ...remainingArguments] = process.argv.slice(2);
  if (!validModes.has(mode) || remainingArguments.length > 0) {
    console.error(
      'Usage: node scripts/app.mjs '
      + '[serialize|generate|run|dev|build|test]',
    );
    process.exitCode = 2;
    return;
  }

  if (mode === 'serialize' || mode === 'generate' || mode === 'run') {
    await runApplicationMode(mode);
  } else if (mode === 'dev') {
    await runApplicationMode('run');
  } else if (mode === 'test') {
    await runTests();
  } else {
    await buildApplication();
  }
}

try {
  await main();
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = error instanceof ProcessError ? error.exitCode : 1;
}
