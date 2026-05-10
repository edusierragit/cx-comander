# cx commander

Tiny Windows/PowerShell session commander for Codex CLI.

`cx` reads local Codex session files from `~\.codex\sessions`, shows a clearer picker, lets you pin sessions that should survive reboots, and restores them with `codex resume <session_id>`.

## Quick Start

The easiest workflow is restoring the latest sessions:

```powershell
cx restore 10
```

That opens the latest 10 non-closed Codex sessions from `cx list`.

Use any number:

```powershell
cx restore 1
cx restore 3
cx restore 10
```

The number is a quantity, not a range. `cx restore 10` means "restore the latest 10".

Preview first without opening tabs:

```powershell
cx restore 10 -DryRun
```

Pinned sessions are optional. Use pins only when you want a curated restore list:

```powershell
cx pin
cx active
cx restore
```

## Install

Clone this repo and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Open a new terminal:

```powershell
cx list
```

The installer copies `bin\cx.ps1` to:

```powershell
%LOCALAPPDATA%\cx-commander\cx.ps1
```

It also creates `cx.ps1` and `cx.cmd` shims in:

```powershell
%APPDATA%\npm
```

That directory is added to the user `PATH` if needed.

## Usage

Most people only need:

```powershell
cx list
cx restore 10
cx restore 7 -D
cx restore 3 -Split
cx restore 10 -DryRun
```

Optional pinned workflow:

```powershell
cx active
cx pin
cx pin 3
cx unpin
cx unpin 3
cx note 3 "frontend faqs strapi"
cx restore
cx restore 10
cx restore -DryRun
cx restore 10 -DryRun
cx resume 3
cx close 3
```

## What restore does

`cx restore 10` restores the latest 10 non-closed sessions from:

```powershell
cx list
```

`cx restore` without a number restores pinned sessions. These are the sessions shown by:

```powershell
cx active
```

`-DryRun` prints what would be opened without opening tabs.

Use `-D` (division mode) to restore into split panes grouped by tabs:

```powershell
cx restore 7 -D
cx restore 7 -D -DryRun
```

`cx restore 7 -D` opens the latest 7 sessions in Windows Terminal, grouped into tabs with up to 4 panes per tab.

Example: 7 sessions becomes 2 tabs: one with 4 panes, one with 3 panes.

Use `-Split` to force all restored sessions into panes inside one Windows Terminal tab:

```powershell
cx restore 3 -Split
cx restore -Split
cx restore 3 -Split -DryRun
```

`cx restore 3 -Split` opens the latest 3 sessions in one tab split into panes.

`cx restore -Split` opens pinned sessions in one tab split into panes.

## Tabs

When Windows Terminal is available, `cx restore` opens sessions in tabs using:

```powershell
wt -w 0 new-tab ...
```

If Windows Terminal is not available, it falls back to separate PowerShell windows.

For grouped pane layouts, use:

```powershell
cx restore 7 -D
```

`-D` requires Windows Terminal. It creates a fresh split layout for the restored sessions, max 4 panes per tab. It cannot read a previous Windows Terminal layout after a crash or reboot.

For one single tab with all panes, use:

```powershell
cx restore 3 -Split
```

## Restore Order

Pinned sessions restore in pin order, based on the timestamp stored when you run `cx pin`.

Recent restores, such as `cx restore 10`, restore by latest activity, matching `cx list`.

Windows Terminal does not expose the previous tab order to this script, so `cx` cannot recover the exact tab order from before a crash unless the sessions were pinned in that order.

Windows Terminal also does not expose the previous split-pane layout to this script. `cx restore 3 -Split` creates a new deterministic split layout instead.

## Platform

Supported today:

```text
Windows + PowerShell + Codex CLI
```

macOS is not supported by the installer or tab restore yet. The core idea can be ported because Codex also stores sessions under `~/.codex`, but this repo currently uses Windows paths, `%APPDATA%`, `%LOCALAPPDATA%`, and Windows Terminal (`wt.exe`) for tabs.

## State

The user state lives in:

```powershell
~\.codex\memories\cx-state.json
```

`cx` never deletes Codex sessions. `close` and `unpin` only update this local cx state.
