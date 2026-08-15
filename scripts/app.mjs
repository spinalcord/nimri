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
const frontendDirectory = join(projectDirectory, 'frontend');
const isWindows = process.platform === 'win32';
const applicationBinary = join(projectDirectory, isWindows ? 'main.exe' : 'main');
const electronCli = join(
  projectDirectory,
  'node_modules',
  'electron',
  'cli.js',
);
const electronRuntime = join(
  projectDirectory,
  'node_modules',
  'electron',
  'dist',
  isWindows ? 'electron.exe' : 'electron',
);
const forgeCli = join(
  projectDirectory,
  'node_modules',
  '@electron-forge',
  'cli',
  'dist',
  'electron-forge.js',
);
const forgePackagerCompatibility = join(
  projectDirectory,
  'scripts',
  'forge-packager-compat.cjs',
);
const viteCli = join(
  frontendDirectory,
  'node_modules',
  'vite',
  'bin',
  'vite.js',
);
const sidecarResourceDirectory = join(
  projectDirectory,
  '.nimcache',
  'electron-resources',
  'sidecar',
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
  const {
    captureOutput = false,
    cwd = projectDirectory,
    environment = process.env,
  } = options;

  return new Promise((resolveProcess, rejectProcess) => {
    const child = spawn(command, arguments_, {
      cwd,
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
    child.on('error', (error) => rejectProcess(new ProcessError(
      `Failed to start ${command}: ${error.message}`,
    )));
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

async function compileApplication(options = {}) {
  const {
    environment = process.env,
    output = applicationBinary,
    release = false,
    nimcache = join(projectDirectory, '.nimcache', 'main'),
  } = options;
  const arguments_ = ['c', '--threads:on'];
  if (release) {
    arguments_.push('-d:release');
  }
  arguments_.push(`--nimcache:${nimcache}`);
  arguments_.push(`-o:${output}`, 'main.nim');
  await runProcess('nim', arguments_, { environment });
}

async function runApplicationMode(mode) {
  await compileApplication();
  await runProcess(applicationBinary, [mode]);
}

function waitForVite(viteProcess) {
  return new Promise((resolveReady, rejectReady) => {
    let settled = false;
    const finish = (callback, value) => {
      if (settled) {
        return;
      }
      settled = true;
      callback(value);
    };
    viteProcess.stdout.setEncoding('utf8');
    viteProcess.stderr.setEncoding('utf8');
    viteProcess.stdout.on('data', (chunk) => {
      process.stdout.write(chunk);
      if (chunk.includes('http://127.0.0.1:5173/')) {
        finish(resolveReady);
      }
    });
    viteProcess.stderr.on('data', (chunk) => process.stderr.write(chunk));
    viteProcess.on('error', (error) => finish(
      rejectReady,
      new ProcessError(`Failed to start Vite: ${error.message}`),
    ));
    viteProcess.on('close', (exitCode, signal) => finish(
      rejectReady,
      new ProcessError(
        `Vite stopped before becoming ready (${signal ?? exitCode}).`,
        exitCode ?? 1,
      ),
    ));
  });
}

async function stopChild(child) {
  if (child === null || child.exitCode !== null || child.signalCode !== null) {
    return;
  }
  await new Promise((resolveStopped) => {
    const timeout = setTimeout(() => {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill('SIGKILL');
      }
    }, 1_500);
    child.once('close', () => {
      clearTimeout(timeout);
      resolveStopped();
    });
    child.kill();
  });
}

async function runDevelopment() {
  await compileApplication();
  await runProcess(applicationBinary, ['generate']);

  const viteProcess = spawn(process.execPath, [viteCli], {
    cwd: frontendDirectory,
    env: process.env,
    shell: false,
    stdio: ['inherit', 'pipe', 'pipe'],
  });
  let electronProcess = null;
  let interrupted = false;
  const handleSignal = () => {
    interrupted = true;
    electronProcess?.kill();
    viteProcess.kill();
  };
  process.once('SIGINT', handleSignal);
  process.once('SIGTERM', handleSignal);

  try {
    await waitForVite(viteProcess);
    electronProcess = spawn(process.execPath, [electronCli, projectDirectory], {
      cwd: projectDirectory,
      env: process.env,
      shell: false,
      stdio: 'inherit',
    });
    await new Promise((resolveElectron, rejectElectron) => {
      electronProcess.on('error', (error) => rejectElectron(new ProcessError(
        `Failed to start Electron: ${error.message}`,
      )));
      electronProcess.on('close', (exitCode, signal) => {
        if (exitCode === 0 || interrupted) {
          resolveElectron();
          return;
        }
        rejectElectron(new ProcessError(
          `Electron stopped with ${signal ?? `exit code ${exitCode}`}.`,
          exitCode ?? 1,
        ));
      });
    });
  } finally {
    process.removeListener('SIGINT', handleSignal);
    process.removeListener('SIGTERM', handleSignal);
    await Promise.all([
      stopChild(electronProcess),
      stopChild(viteProcess),
    ]);
  }
}

async function runTests() {
  const testDirectory = await mkdtemp(join(tmpdir(), 'nimri-test-'));
  try {
    const testSidecar = join(
      testDirectory,
      isWindows ? 'nimri-sidecar.exe' : 'nimri-sidecar',
    );
    await compileApplication({
      output: testSidecar,
      nimcache: join(testDirectory, 'nimcache', 'sidecar'),
    });
    for (const testSource of [
      'tests/test_nimri_rpc.nim',
      'tests/test_frontend_bindings.nim',
      'tests/test_frontend_e2e.nim',
    ]) {
      const testName = basename(testSource, extname(testSource));
      const testBinary = join(
        testDirectory,
        isWindows ? `${testName}.exe` : testName,
      );
      await runProcess('nim', [
        'c',
        '--threads:on',
        `--nimcache:${join(testDirectory, 'nimcache', testName)}`,
        `-o:${testBinary}`,
        testSource,
      ]);
      await runProcess(testBinary, [], {
        environment: {
          ...process.env,
          NIMRI_TEST_SIDECAR: testSidecar,
        },
      });
    }
    await runProcess(process.execPath, [
      process.env.npm_execpath,
      'run',
      'check',
      '--workspace',
      'frontend',
    ]);
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
      isWindows ? 'nimri-bootstrap.exe' : 'nimri-bootstrap',
    );
    await compileApplication({
      environment,
      output: bootstrapBinary,
      nimcache: join(buildDirectory, 'nimcache-bootstrap'),
    });
    await runProcess(bootstrapBinary, ['generate'], { environment });
    await runProcess(process.execPath, [
      process.env.npm_execpath,
      'run',
      'build',
      '--workspace',
      'frontend',
    ], { environment });

    await rm(sidecarResourceDirectory, { force: true, recursive: true });
    await mkdir(sidecarResourceDirectory, { recursive: true });
    const sidecarBinary = join(
      sidecarResourceDirectory,
      isWindows ? 'nimri-sidecar.exe' : 'nimri-sidecar',
    );
    await compileApplication({
      environment,
      output: sidecarBinary,
      release: true,
      nimcache: join(buildDirectory, 'nimcache-release'),
    });
    if (isWindows) {
      for (const runtimeDll of windowsRuntimeDlls) {
        await copyFile(
          join(runtimeDirectory, runtimeDll),
          join(sidecarResourceDirectory, runtimeDll),
        );
      }
    }

    await rm(binDirectory, { force: true, recursive: true });
    await runProcess(electronRuntime, [
      '--require',
      forgePackagerCompatibility,
      forgeCli,
      'package',
    ], {
      environment: {
        ...environment,
        ELECTRON_RUN_AS_NODE: '1',
      },
    });
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

  if (mode === 'serialize' || mode === 'generate') {
    await runApplicationMode(mode);
  } else if (mode === 'run' || mode === 'dev') {
    await runDevelopment();
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
