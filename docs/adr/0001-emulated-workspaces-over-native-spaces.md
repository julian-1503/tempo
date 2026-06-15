# 1. Emulated workspaces over native macOS Spaces

Date: 2026-06-15

## Status

Accepted

## Context

Tempo is a single-monitor macOS window manager whose core job is moving apps between
workspaces and switching between them instantly. We need a representation of "workspace"
(a virtual desktop holding a set of windows). macOS offers three approaches:

1. **Native Spaces / Mission Control** — the OS's own virtual desktops. There is **no
   public API** to move a window to another Space or to switch Spaces programmatically and
   reliably. Doing so requires private APIs, Space-switch animations are slow, and there is
   a hard 16-Space limit. This directly conflicts with our standing performance requirement.

2. **A scripting addition (yabai-style)** — enables real Space manipulation and tiling, but
   requires **partially disabling System Integrity Protection (SIP)**, ships a privileged
   component, and breaks on most macOS updates. It contradicts our simplicity and
   maintainability goals.

3. **Emulated workspaces** — keep every window inside one real macOS Space and represent
   workspaces ourselves. When a workspace is inactive, its windows are moved off-screen via
   the public **Accessibility (AX) API**. This is the approach AeroSpace validated.

## Decision

Tempo uses **emulated workspaces**. All windows live in a single native Space. Inactive
workspaces' windows are positioned off-screen via the Accessibility API; switching a
workspace repositions windows rather than driving Mission Control. No native Spaces, no
private APIs, no SIP changes.

This also gives us hiding "for free": an inactive workspace's windows are simply off-screen.
For Scene-hidden apps (presentation safety) we additionally issue a real app-hide
(`NSApplication.hide`) so they leave the window switcher and screen capture entirely.

## Consequences

- **Positive:** fast switching, no SIP, survives macOS updates, scriptable, and natural
  hiding that serves the anti-leak goal.
- **Negative:** macOS won't let a window be placed *fully* off-screen — a ~1px sliver can
  remain visible. We accept this known artifact.
- **Negative:** we depend on apps implementing the AX API correctly; misbehaving apps need
  per-app workarounds (reimplemented from known techniques, not copied).
- **Reversal cost:** high. The entire engine is built around repositioning windows in one
  Space. Moving to native Spaces later would be a rewrite of the core.
