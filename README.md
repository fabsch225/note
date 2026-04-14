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

- **Daily note header**: the heading to insert under in today’s daily note

Export uses the `obsidian` CLI from `$PATH` (no command/args configuration), and updates the daily note by:

- Reading today’s daily note
- Inserting your note *under the configured header* (without disturbing the rest of the file)
- Writing the full updated content back
- Clearing the note window after a successful export

If export fails, you’ll get an alert with the CLI’s stderr.
