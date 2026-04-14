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
  - `Cmd + Return`: export via Obsidian CLI
  - `Cmd + P`: pin/unpin (always on top)
  - `Cmd + ,`: open settings

## Obsidian export configuration

In Settings (Cmd+,), configure:

- **CLI executable path**: the Obsidian CLI binary (full path recommended)
- **CLI arguments**: arguments as you’d type them in a shell; quotes are supported
- **Daily note header**: value substituted into `{header}`

If you set the CLI path to a bare command name (no `/`), it’s resolved via `$PATH`.

The app sends the note text to the CLI over **stdin**.

Because different Obsidian CLIs exist, you should set the exact command/args that work on your machine. Example pattern (adjust to your CLI):

- Args like: `daily-note append --heading "{header}" --stdin`

If export fails, you’ll get an alert with the CLI’s stderr.
