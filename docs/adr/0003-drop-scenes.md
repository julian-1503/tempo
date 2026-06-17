# 3. Drop the Scene concept

Date: 2026-06-17

## Status

Accepted (supersedes the scene/routing parts of ADR-0001 and the v1 plan in CONTEXT.md).

## Context

v0.1 of Tempo shipped a **Scene** abstraction — a named profile of
`app → workspace` assignments plus a visibility policy (`hideUnassigned`):

```json
{
  "name": "main",
  "hideUnassigned": true,
  "assignments": [
    { "match": { "bundleId": "com.brave.Browser", "titleRegex": "Allpoint$" },
      "workspace": "A" }
  ]
}
```

The model was clean on paper: pick a scene, the daemon routes new windows + hides
the rest. In practice it accumulated subtle failure modes:

1. **Browser title timing.** Chrome opens a new window with no profile suffix in
   the title, then fills it in after navigation. A title-regex match evaluated at
   creation time misroutes the window; a match evaluated later races with the
   user's own placement.
2. **Per-app rule conflicts.** Multiple rules over the same bundle (Chrome by
   Julian profile vs apmhelp vs Allpoint vs bare bundleId fallback) made the
   "where does this new Chrome window go?" question depend on rule order, regex
   anchoring, and timing — all of which Julian got wrong on the studio (new
   profile → workspace 1 instead of 7).
3. **Scene switching.** Migrating windows between scenes flickered (unhide-then-
   rehide), and a vestigial one-shot `SceneApplier` from v0 fought the daemon's
   runtime scene logic during refactors.
4. **Authorship cost.** Each scene needed hand-crafted bundle ids + title regexes.
   "Make a new scene for X" was a real cognitive task, not a one-liner.
5. **Concept overhead.** Half of TempoCore (Router/Matching/Planner/SceneStore/
   SceneCodec/Commands/PlacementsCodec) existed to serve the Scene model. The
   marketplace `tempo` SKILL.md was ~80% scene authoring. CONTEXT.md treated
   Scene as the central concept.

Julian's stated need: switch workspaces fast, move windows by chord, keep
muscle memory from AeroSpace. Scenes were doing more than that need required.

## Decision

**Remove the Scene type entirely** from TempoCore, the daemon, the CLI, the
dotfiles, and the marketplace skill. New windows land in whichever workspace is
active at the time they appear; the user moves them around with
`alt+shift+<key>`. No routing rules, no `hideUnassigned`, no scene files, no
`tempo scene …` subcommands, no `state.json` writer, no `tempo query windows`.

`tempo.toml` keeps `default_workspace` and gains `workspaces = [...]` — a menu
filter for the Switch-Workspace submenu. Chord bindings work for any 1–9/A–Z
label regardless of that list.

This is shipped as **v0.2.0** (breaking).

## Alternatives considered

- **Keep scenes, fix the routing bug.** Walk back the Chrome-profile title
  matching: anchor regexes, debounce, re-evaluate on title change. Rejected:
  it papers over the concept-overhead problem (#5) without removing it.
- **Keep the Scene type, stop wiring it through the daemon.** Smaller diff but
  leaves dead code in TempoCore and a confusing half-feature. Rejected.
- **Keep scenes as opt-in via a new config flag.** Doubles the surface area:
  every feature now has a "with scenes" and "without scenes" path. Rejected.

## Consequences

- **Positive:** ~half of TempoCore deleted (Scene, Assignment, WindowMatch,
  Router, Matching, Planner, SceneStore, SceneCodec, Commands,
  PlacementsCodec, RoutingDecision, PlacedWindow, WindowPlacement,
  PlacementPlan), the shell's `SceneApplier` and `AXWindowSource` gone, ~37
  tests gone. The Chrome-routing bug evaporates because there are no rules to
  conflict.
- **Positive:** the model fits in one paragraph. New contributors don't need to
  learn what a Scene is or how matchers tie-break.
- **Negative (accepted):** no presentation-safe mode. Hiding apps from screen
  capture (`NSApplication.hide`) is gone with `hideUnassigned`. If we miss it,
  it can come back as a single chord toggle ("hide every app except the
  focused one") — but as a feature, not a model.
- **Negative (accepted):** no app-to-workspace persistence. If Julian wants
  Slack always on `I`, he opens it from `I` (or moves it once after launch).
  This is the AeroSpace `workspace-to-monitor-force-assignment`-less default.
- **Reversal cost:** medium. The git tag `v0.1.10` is the last version with
  scenes; the model can be revived from history if the trade-off was wrong.
  The deletion is intentional, not lossy.
