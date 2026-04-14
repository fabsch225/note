# NotePop

A tiny macOS SwiftUI note window that lives off the Dock/menu bar and pops up with a global hotkey. You will have to build locally, as i dont have an apple developer license.

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

## Downloadable builds (manual)

This repo does not auto-build in CI.

To publish a downloadable build, build locally and push a GitHub Release:

- `chmod +x scripts/release.sh`
- `scripts/release.sh 0.1.0`

This will:

- Build `dist/NotePop.app`
- Create `dist/NotePop-v0.1.0-macOS.zip`
- Create and push a git tag `v0.1.0`
- Create a GitHub Release for that tag and upload the zip (requires GitHub CLI `gh`)

Note: without Apple code signing + notarization, macOS Gatekeeper may warn on first run. Users can usually bypass via right click → Open.
