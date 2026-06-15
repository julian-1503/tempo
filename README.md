# Tempo

A fast, single-monitor macOS window manager focused on **workspace orchestration and app
placement**, with tiling as a secondary capability.

The core idea: boot up, pick a **Scene**, and every app flies to its assigned workspace —
apps that don't belong to the Scene stay hidden. Keep multiple Scenes for different
contexts (work, a side project, a presentation) and switch between them instantly.

> Single monitor only — by design. See [ADR 0002](docs/adr/0002-single-monitor-as-a-hard-non-goal.md).

## Why

- **Workspace-first.** The job isn't tiling for its own sake; it's getting the right apps
  into the right workspaces so you can jump around fast.
- **Anti-leak.** New windows (including ones opened by AI agents) never yank you out of
  your current workspace, and Scene-hidden apps stay out of the window switcher and screen
  capture — so you don't accidentally reveal something while presenting.
- **AI-friendly.** A CLI with `--json` everywhere lets an assistant read your live window
  state, author Scenes against a published schema, and visualize them.
- **Fast.** Emulated workspaces via the Accessibility API — no SIP changes, no private
  APIs. See [ADR 0001](docs/adr/0001-emulated-workspaces-over-native-spaces.md).

## Concepts

- **Workspace** — a virtual desktop holding windows, with a stable jump key. Workspaces are
  a fixed, named set (e.g. `A`, `B`, `C`, `1`–`9`).
- **Scene** — a named, switchable profile of app→workspace assignments plus visibility.
  Exactly one Scene is active at a time. Apps not assigned in the active Scene are hidden.
- **Tiling layout** — within a workspace: `tiles`, `accordion`, or `floating`.

See [CONTEXT.md](CONTEXT.md) for the full glossary and design decisions.

## Status

Early development. The pure core (`TempoCore`) is built and tested (30 tests):

- **Router** — window→workspace routing with the global focus-protection guarantee
  (bundle-id › composite › title matching, specificity tie-break, dialog-floating).
- **Planner** — Scene activation: per-window placement + which apps to hide.
- **Scene persistence** — JSON load/save with validation, file-backed `SceneStore`.
- **Commands** — `query windows`, `scene list/show/render`, and snapshot-from-placements.
- **CLI** — `tempo version | scene list | scene show <name> | scene render <name>` work today.

**Not yet built:** the Accessibility-API engine — the real `WindowSource`, window
mover/off-screen positioning, workspace switcher, app-hide, plus the menu bar and
keybindings. These require a logged-in desktop and Accessibility permission to run, so
`tempo query windows`, `scene apply`, and `scene create --from-current` currently report
that the engine is missing.

## Build

```sh
swift build
swift test

# Try the working commands against a scratch home:
export TEMPO_HOME=$(mktemp -d) && mkdir -p "$TEMPO_HOME/scenes"
swift run tempo scene render <name>   # after placing a <name>.json in $TEMPO_HOME/scenes
```

## License

MIT — see [LICENSE](LICENSE).
