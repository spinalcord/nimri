// FIX: Adapt Forge 7 callback hooks to Packager 20's promise hook contract.
const packagerModule = require('@electron/packager');

const originalPackager = packagerModule.packager;
const hookOptionNames = [
  'afterComplete',
  'afterCopy',
  'afterExtract',
  'afterFinalizePackageTargets',
  'afterPrune',
];

function promiseHook(optionName, legacyHook) {
  return (hookArguments) => new Promise((resolve, reject) => {
    let completed = false;
    const done = (error) => {
      if (completed) {
        return;
      }
      completed = true;
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    };

    try {
      const arguments_ = optionName === 'afterFinalizePackageTargets'
        ? [hookArguments]
        : [
            hookArguments.buildPath,
            hookArguments.electronVersion,
            hookArguments.platform,
            hookArguments.arch,
          ];
      Promise.resolve(legacyHook(...arguments_, done)).catch(done);
    } catch (error) {
      done(error);
    }
  });
}

const compatiblePackager = (options) => {
  const adaptedOptions = { ...options };
  for (const optionName of hookOptionNames) {
    if (adaptedOptions[optionName]) {
      const hooks = Array.isArray(adaptedOptions[optionName])
        ? adaptedOptions[optionName]
        : [adaptedOptions[optionName]];
      adaptedOptions[optionName] = hooks.map(
        (hook) => promiseHook(optionName, hook),
      );
    }
  }
  return originalPackager(adaptedOptions);
};

require.cache[require.resolve('@electron/packager')].exports = {
  ...packagerModule,
  packager: compatiblePackager,
};
