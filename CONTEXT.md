# Tempo — Context & Glossary

A fast, single-monitor macOS window manager. Workspaces + tiling, driven by
chord bindings. Inspired by AeroSpace's ergonomics.

## Core identity

Tempo is **workspace-first**. A workspace is a virtual desktop holding a set of
windows. The user moves windows between workspaces with chord bindings, and
within a workspace the daemon arranges them as tiles, accordion, or floats.

No routing rules, no per-app placement profiles. New windows always land in the
currently active workspace; the user moves them where they want with
`alt+shift+<key>`. The model is small enough to keep in your head.

Earlier versions had a `Scene` concept (named profiles of app→workspace
assignments). It was deleted in v0.2.0 — see `docs/adr/0003-drop-scenes.md`.

## Glossary

- **Workspace** — A virtual desktop holding a set of windows. Single monitor
  only. Identified by a label glyph (`"1"`–`"9"`, `"A"`–`"Z"` minus `H`/`J`/
  `K`/`L` which are tile-nav). Chord bindings are stable per label across the
  whole session — muscle memory matters. **Model: emulated** — all windows live
  in one real macOS Space; inactive workspaces' windows are moved off-screen via
  the Accessibility API (AeroSpace-style). No native Spaces, no private APIs.

- **Tile layout** — How a workspace's non-floating windows are arranged on
  screen. Each workspace is in one mode: **tiles** (N windows split evenly,
  horizontal or vertical orientation) or **accordion** (stacked/switchable).
  Per-workspace orientation + mode persist across switches.

- **Floating window** — A window excluded from the tile layout; keeps its own
  frame wherever the user dragged it. Dialog/floating AX subroles auto-float;
  the user can toggle any window with `alt+space`.

- **Fullscreen** — At most one window per workspace fills the workspace area,
  hiding everything else. Toggled with `alt+shift+f`. Cleared automatically when
  another tile is focused or moved.

- **Hidden window** — A window assigned to a workspace that isn't currently
  active. The daemon parks it in the off-screen corner via the AX API. Still
  visible in Cmd-Tab and Mission Control (this is the deliberate trade-off vs
  the more aggressive `NSApplication.hide` that Scenes used).

- **Paused** — Daemon escape hatch (`alt+shift+escape`). All hidden windows pop
  back on-screen so the user can work in normal-mac mode without Tempo moving
  things. The chord resumes; menu bar title flips from `T <ws>` to `⏸ <ws>`.

## Hard constraints / non-goals

- **Single monitor only.** Multi-monitor control is an explicit non-goal — the
  design should actively encourage a single-monitor workflow.
- **No app-specific routing.** New windows land in the active workspace,
  always. If the user wants Chrome on workspace B, they switch to B *then*
  open Chrome (or open it anywhere and `alt+shift+b` to move it).

## Capabilities (current)

- Switch to a workspace by chord (`alt+<key>`).
- Move the focused window to a workspace (`alt+shift+<key>`).
- Back-and-forth between the two most recent workspaces (`alt+tab`).
- Focus the neighboring tile (`alt+h/j/k/l`) and swap with it (`alt+shift+…`).
- Toggle tile orientation (`alt+/`), accordion mode (`alt+,`), float
  (`alt+space`), fullscreen (`alt+shift+f`).
- Pause/resume the daemon (`alt+shift+escape`).
- Menu-bar status: `T <ws>` (active) or `⏸ <ws>` (paused), with a
  Switch-Workspace submenu filtered by `tempo.toml`'s `workspaces` list.
- Cross-app focus follow: Cmd+Tab into a window on another workspace switches
  to that workspace instead of yanking the window out.

## Motivating goals

- **Performance** — must feel instant. Single monitor lets us delete entire
  classes of code (multi-monitor logic).
- **Anti-leak** — new windows never steal focus or switch workspaces. Windows
  open in the workspace where the user already is.

## Tech foundation (decided)

- **Engine: Swift**, driving the macOS Accessibility API. Non-negotiable for latency.
- **Packaging: one self-contained Swift binary** (engine + CLI). Single toolchain.
- **Distribution: `.app` bundle** at `~/Applications/Tempo.app`, self-signed so
  macOS TCC's Accessibility grant survives binary updates. CLI is a symlink to
  the binary inside the bundle.
- **Reuse boundary:** reimplement AeroSpace's *techniques* (off-screen
  positioning, AX-API workarounds, dialog detection); never copy its GPLv3
  source. No AeroSpace references in the public repo.

## Config & CLI

- **`tempo.toml`** (hand-edited, symlinked from dotfiles to
  `~/.config/tempo/tempo.toml`):
  ```toml
  [daemon]
  default_workspace = "1"
  workspaces = ["1", "T", "B", "Q", ...]   # menu-bar Switch Workspace submenu
  ```
- **CLI** is tiny — the daemon owns state:
  - `tempo daemon` — start the long-running daemon (launchd-managed).
  - `tempo workspace <id>` — switch via the daemon's FIFO.
  - `tempo back` — back-and-forth via the daemon.
  - `tempo debug frames|winpos|move` — AX introspection.
  - `tempo version`.

## Tiling model

- Each workspace is in one of two layout modes: **tiles** (N windows split
  evenly along the workspace's orientation axis) or **accordion** (stacked).
- Windows can be **floating** (config dialogs auto-float via AX subrole; any
  window can be toggled with `alt+space`).
- At most one **fullscreen** window per workspace.
- No nested container tree — keep it flat. Nesting may be added later if
  genuinely missed.

## Repo

- GitHub: **`julian-1503/tempo`**, public.
- **License: MIT** (clean-room reimplementation; no AeroSpace code).
