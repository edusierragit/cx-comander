# cx commander

Tiny PowerShell session commander for Codex CLI.

`cx` reads local Codex session files from `~\.codex\sessions`, shows a clearer picker, lets you pin sessions that should survive reboots, and restores them with `codex resume <session_id>`.

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

```powershell
cx list
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

`cx restore` restores pinned sessions. These are the sessions shown by:

```powershell
cx active
```

`cx restore 10` restores the latest 10 non-closed sessions from:

```powershell
cx list
```

`-DryRun` prints what would be opened without opening tabs.

## Tabs

When Windows Terminal is available, `cx restore` opens sessions in tabs using:

```powershell
wt -w 0 new-tab ...
```

If Windows Terminal is not available, it falls back to separate PowerShell windows.

## Restore Order

Pinned sessions restore in pin order, based on the timestamp stored when you run `cx pin`.

Recent restores, such as `cx restore 10`, restore by latest activity, matching `cx list`.

Windows Terminal does not expose the previous tab order to this script, so `cx` cannot recover the exact tab order from before a crash unless the sessions were pinned in that order.

## State

The user state lives in:

```powershell
~\.codex\memories\cx-state.json
```

`cx` never deletes Codex sessions. `close` and `unpin` only update this local cx state.
