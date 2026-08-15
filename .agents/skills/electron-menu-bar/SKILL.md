---
name: electron-menu-bar
description: Remove or restore the native Electron application menu bar in this Nimri desktop project. Use when users ask to hide, remove, show, or re-enable the menu at the top of the application window.
---

# Electron Menu Bar

Edit `electron/main.mjs`.

## Remove

Import `Menu` from `electron` and call this at the beginning of `startApplication`:

```js
Menu.setApplicationMenu(null);
```

## Restore

Remove the `Menu` import and the `Menu.setApplicationMenu(null);` call. Electron then uses its default native menu again.

## Validate

Run:

```bash
node --check electron/main.mjs
```
