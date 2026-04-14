# NotePop

A tiny macOS SwiftUI note window that lives off the Dock/menu bar and pops up with a global hotkey.

## Build & run

- `swift build`
- `swift run NotePop`

## Build a real .app bundle

This repo is SwiftPM-based, but you can still package it as a normal macOS app bundle:

- `bash scripts/build-app-bundle.sh`

Output: `dist/NotePop.app`

## Usage

- Global hotkey: **Option + Space** (toggle show/hide)
- In-app:
  - `Cmd + Return`: export to today’s daily note
  - `Cmd + P`: pin/unpin (always on top)
  - `Cmd + ,`: open settings

## Obsidian export configuration

In Settings (Cmd+,), configure:

- **Daily note header**: the heading to insert under in today’s daily note

Export writes directly to your Obsidian vault’s daily note file (it does **not** launch Obsidian, so there are no transient Dock icons). It locates the active vault from Obsidian’s local config and uses the Daily Notes plugin settings (folder + date format) when available.

- Reading today’s daily note
- Inserting your note *under the configured header* (without disturbing the rest of the file)
- Writing the full updated content back
- Clearing the note window after a successful export

If export fails, you’ll get an alert with the error details.

## Downloadable builds (GitHub Actions)

This repo includes a GitHub Actions workflow that builds `NotePop.app` and zips it.

- For every push/PR: the zip is available as an **Actions artifact**.
- For version tags (e.g. `v0.1.0`): the workflow also publishes the zip as a **GitHub Release asset**.

To create a release:

- Create and push a tag: `git tag v0.1.0 && git push origin v0.1.0`
