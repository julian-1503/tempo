# Tempo — Context & Glossary

A fast, single-monitor macOS window manager focused on workspace orchestration and
app placement, with tiling preserved as a first-class (but secondary) capability.
Inspired by the workspace/automation ergonomics of keyboard-driven tiling WMs.

## Core identity

Tempo is **workspace/placement-first**, not tiling-first. The primary job: boot up,
pick a **Scene**, and every app flies to its assigned workspace; apps not in the Scene
stay hidden. Tiling within a workspace is supported but secondary.

## Glossary

- **Scene** — A named, switchable profile of app→workspace assignments + visibility.
  Tempo-specific concept (AeroSpace has no equivalent; "Scene" is a coined term, runner-up
  "Profile"). Deliberately NOT called "layout" to avoid collision with tiling-layout below.
  Model (decided):
  - Workspaces are a **global, stable namespace** with permanent jump keybindings
    (a given key always jumps to the same workspace, across all Scenes → muscle memory).
  - A Scene declares: (1) **assignments** (apps / browser-windows-by-title → workspaces);
    (2) **visibility** — apps not assigned in the active Scene are **hidden** (real
    app-hide); workspaces a Scene doesn't use are simply empty;
    (3) *(later)* per-workspace tiling layout + workspace focused on activation.
  - **Exactly one Scene active at a time.** Switching = re-place assigned apps + hide
    the rest. Navigation keys stay constant across Scenes.
  - Default policy: **hide-unassigned** (presentation-safe). A per-Scene toggle may later
    allow a looser "park unassigned in a catch-all" mode.
  - **Pulling a new app into the current workspace at runtime is ephemeral** (forgotten on
    Scene switch); a CLI/keybind can **persist** it into the active Scene.

- **Tiling layout** — The on-screen arrangement algorithm within a single workspace:
  side-by-side panes (tiles), accordion (stacked/switchable), and floating windows.
  This is the conventional WM meaning of "layout". Always qualify as "tiling layout".

- **Workspace** — A virtual desktop holding a set of windows. Single monitor only.
  Users assign apps to workspaces and jump between them. Windows can be moved between
  workspaces. **Model: emulated** — all windows live in one real macOS Space; inactive
  workspaces' windows are moved off-screen via the Accessibility API (AeroSpace-style).
  No native macOS Spaces, no private APIs, no SIP disable.

- **Hidden (Scene-hidden)** — An app excluded from the current Scene. Distinct from
  "inactive workspace": inactive-workspace windows are merely off-screen (still in
  Cmd-Tab/Mission Control), whereas Scene-hidden apps get a real macOS app-hide
  (`NSApplication.hide`, like Cmd-H) so they vanish from the switcher and screen
  capture — this is what makes Scenes presentation-safe (anti-leak).

## Hard constraints / non-goals

- **Single monitor only.** Multi-monitor control is an explicit non-goal — the design
  should actively encourage a single-monitor workflow.

## Capabilities to preserve (from current AeroSpace usage)

- Auto-route apps to workspaces on launch (`on-window-detected`-style rules).
- Route **browser windows by title** to workspaces (ChessDev→B, Allpoint→A, ChatGPT→C,
  APM Help→Q). This is central, not incidental.
- Side-by-side panes and accordion switching within a workspace.
- Floating windows (e.g. config/settings dialogs).
- Move windows between workspaces; pull a new app into the current workspace.

## Motivating goals

- **Performance** — must be noticeably faster than the current setup.
- **Anti-leak / focus protection** — new browser windows (often opened by AI agents)
  must NOT yank the user out of their current workspace. Hidden apps must stay hidden.
- **AI-friendly CLI** — tweak config / build Scenes via CLI; LLM can author Scenes and
  generate visualizations of them.

## Tech foundation (decided)

- **Engine: Swift**, driving the macOS Accessibility API. Non-negotiable for latency.
- **Packaging: one self-contained Swift binary** (engine + CLI). Single toolchain.
- **Reuse boundary:** reimplement AeroSpace's *techniques* (off-screen positioning,
  AX-API workarounds, dialog detection); never copy its GPLv3 source. No AeroSpace
  references in the public repo.

## Window matching & anti-leak (decided)

- **Focus-protection is a global guarantee:** a new window never switches the active
  workspace and never steals keyboard focus. Windows routed to a non-active workspace
  are filed off-screen silently.
- **New-window policy:** matches an assignment → route (silent if target ≠ active);
  matches nothing → show in current workspace (ephemeral, not hidden). Hide-unassigned
  applies to Scene *activation*, not to apps the user actively launches.
- **Title timing:** evaluate at window creation, re-evaluate on title change until the
  first rule match, then lock placement. Never override a user-moved window.
- **Matcher hierarchy (fast/robust first):** (1) bundle id — primary, incl. PWAs /
  site-as-app and a dedicated AI browser app; (2) AXSubrole/AXRole — floating/dialog
  detection; (3) title regex — fallback for un-appified browser windows; (4) URL match —
  opt-in slow path only (AX tree traversal / AppleScript), never on the default hot path.
- **Strategy:** encourage distinct app identity (PWAs, dedicated AI browser) over title
  matching; a CLI helper may scaffold a site-as-app. This is the real fix for AI windows.

## Config, CLI & AI integration (decided)

- **Workspaces:** a fixed, user-defined set of **named** workspaces with **stable jump
  keys**; defaults to the user's current set (A, B, C, Q, I, T, 1–7). Not dynamic.
- **Static config:** TOML (global options, keybindings, workspace list) — hand-edited.
- **Scenes:** one file per Scene under `scenes/`, validated against a published JSON
  Schema. Separate from static config so AI can author a Scene in isolation; diffable.
- **AI integration = CLI, not a special API**, with `--json` on everything:
  1. `tempo query windows --json` — read live state (bundle id, title, subrole, workspace).
  2. `tempo scene create --from-current <name>` — snapshot live arrangement into a Scene
     (first-class path; LLM starts from a snapshot, not a guess).
  3. `tempo scene apply|render <name>` — apply, and visualize (ASCII to terminal, SVG to file).

## Tiling model (decided)

- **Simplified per-workspace layout** (no nested container tree). Each workspace is in one
  mode: **tiles** (N windows split evenly, choosable split direction) or **accordion**
  (stacked/switchable). Windows can be **floating** (config dialogs auto-float via subrole).
  Nesting may be added later only if genuinely missed.

## Startup & UX (decided)

- **On launch: auto-apply the last-active (or configured default) Scene**, no prompt.
- **Scene switching: both** a menu bar item (SwiftUI `MenuBarExtra`, shows current
  Scene + workspace; doubles as a pre-screenshare "am I in the safe Scene?" check) **and**
  keybindings (binding mode for per-Scene keys). Workspace jump keys are separate/stable.

## Repo (decided)

- GitHub: **`julian-1503/tempo`**, **public**, active gh account confirmed = julian-1503.
- **License: MIT** (clean-room reimplementation; no AeroSpace code).
- Name heads-up: "Tempo" collides with Grafana Tempo / time-trackers as a product name
  (fine for personal use; a Homebrew formula may later need a different name).

## Performance principle (decided)

- No specific current bottleneck; performance is a **standing non-functional requirement**:
  Tempo must feel instant and responsive. Bias every design choice toward it (route on the
  AX creation event so windows never visibly jump; avoid per-focus-change overhead like
  mouse-warping callbacks; single monitor means monitor-handling logic is deleted entirely,
  not just disabled).

## v1 scope & build order (decided)

- **v1 — core loop:** (1) engine foundation (AX-permission onboarding, window enumeration,
  emulated workspaces, switching + stable jump keys); (2) matching + routing (bundle id →
  subrole → title) with the global focus-protection guarantee; (3) Scenes (file + JSON
  Schema, `apply` = place assigned + hide unassigned, `create --from-current` snapshot);
  (4) CLI with `--json` (`query windows`, `scene apply/create/list`).
- **v1.1:** tiling within a workspace (tiles/accordion/floating); menu bar + per-Scene keybinds.
- **v1.2+:** `scene render` visualization (ASCII/SVG); AI niceties (site-as-app scaffolding,
  schema-guided Scene authoring).
- Rationale: the 4-item core loop delivers the main objective end-to-end and is useful
  before any tiling or GUI exists.
