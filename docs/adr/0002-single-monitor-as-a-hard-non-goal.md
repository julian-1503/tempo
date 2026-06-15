# 2. Single monitor as a hard non-goal

Date: 2026-06-15

## Status

Accepted

## Context

Most tiling window managers treat multi-monitor support as a core feature, carrying
significant complexity: per-monitor workspace assignment, monitor hotplug handling,
focus/mouse transitions across displays, and the "Displays have separate Spaces" setting
interacting with workspace emulation.

Tempo's author works exclusively on a single monitor and wants the tool to *encourage* that
workflow rather than merely tolerate it. Performance is a standing requirement, and
multi-monitor bookkeeping is pure overhead for a single-monitor user.

## Decision

**Single monitor is a hard non-goal.** Tempo assumes exactly one display. We do not just
disable multi-monitor features — we omit the concept entirely from the model and engine:
no per-monitor workspace assignment, no monitor-change callbacks, no cross-display focus
logic.

## Consequences

- **Positive:** a smaller, faster engine with fewer edge cases; a simpler mental model;
  and code that never pays for monitor handling it doesn't use.
- **Positive:** removes a class of bugs (focus loss on hotplug, workspace/monitor binding).
- **Negative:** Tempo is unusable as-is for multi-monitor setups. This is intentional.
- **Reversal cost:** high. Adding monitors later means threading a monitor dimension
  through workspaces, Scenes, routing, and the engine — effectively a redesign. We choose
  to pay that cost only if the requirement ever genuinely changes.
