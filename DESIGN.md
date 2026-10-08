---
name: Levels
description: A native macOS mixer with island and menu bar popover modes.
colors:
  accent: "rgb(50% 94% 77%)"
  surface: "#000000"
  popover-surface: "rgb(8.5% 8.5% 8.5%)"
  text: "#ffffff"
  secondary: "rgb(66% 66% 66%)"
  divider: "rgb(100% 100% 100% / 12%)"
  access-surface: "rgb(9% 9% 9%)"
  search-surface: "rgb(10% 10% 10%)"
  icon-pressed: "rgb(100% 100% 100% / 14%)"
typography:
  title:
    fontFamily: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "18pt"
    fontWeight: 600
  popover-title:
    fontFamily: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "17pt"
    fontWeight: 600
  app-name:
    fontFamily: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "13pt"
    fontWeight: 500
  control:
    fontFamily: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "12pt"
    fontWeight: 500
  section:
    fontFamily: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "12pt"
    fontWeight: 600
  detail:
    fontFamily: "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  icon: "6pt"
  search: "8pt"
  access: "12pt"
spacing:
  detail: "2pt"
  small: "8pt"
  controls: "10pt"
  gutter: "22pt"
components:
  compact-island:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
  mixer-body:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text}"
    width: "430pt"
  menu-popover:
    backgroundColor: "{colors.popover-surface}"
    textColor: "{colors.text}"
    width: "400pt"
  app-row:
    typography: "{typography.app-name}"
    padding: "0 22pt"
    height: "88pt"
  app-row-error:
    typography: "{typography.app-name}"
    padding: "0 22pt"
    height: "106pt"
  search-field:
    backgroundColor: "{colors.search-surface}"
    rounded: "{rounded.search}"
    padding: "9pt"
  access-card:
    backgroundColor: "{colors.access-surface}"
    rounded: "{rounded.access}"
    padding: "14pt"
  icon-button:
    textColor: "{colors.secondary}"
    rounded: "{rounded.icon}"
  icon-button-pressed:
    backgroundColor: "{colors.icon-pressed}"
    textColor: "{colors.secondary}"
    rounded: "{rounded.icon}"
---

# Design System: Levels

## Overview

**Creative North Star: "Dynamic Island style mixer"**

Levels uses a compact black island around the camera housing, expanding downward into native macOS audio controls. Its expression comes from the silhouette, restrained mint accents, clear app identities, and aligned levels. The confirmed direction is recorded in [docs/ISLAND_DESIGN.md](docs/ISLAND_DESIGN.md); platform and native-control commitments are in [PRODUCT.md](PRODUCT.md).

This document describes the implemented island and optional menu bar popover. SwiftUI and AppKit remain the rendering authority; the sidecar's HTML examples are illustrative translations, with one CSS pixel representing one macOS point. Window-level review covered compact, expanded, and many-app states. Full-display pixel positioning was not captured; reported `NSScreen` coordinates and geometry tests support placement logic only. Saved scroll captures intermittently omit layers, while the user confirmed labels and sliders remain visible on screen.

**Key Characteristics:**

- Black island and charcoal popover with shared mint controls and status.
- System SF typography, SF Symbols, and native menus and sliders.
- A camera-housing cap above interactive mixer content.
- Fixed surrounding sections and a bounded, scrollable app list.

## Colors

The palette uses one mint accent against black, with white and gray for hierarchy. Frontmatter values preserve the normalized Swift color values without rounding them to approximate hex values.

### Primary

- **Mint accent:** slider tint, compact mixer glyph, ready-status dots, and the inactive-app reveal action.

### Neutral

- **Black surface:** the continuous island background.
- **Charcoal surface:** the native menu bar popover and optional normal mixer window.
- **White text:** primary labels, active percentage values, and compact active-app count.
- **Secondary gray:** supporting labels, status copy, options, and ordinary speaker icons.
- **White divider:** the single separator before the Apps section.
- **Access and search surfaces:** subtly lighter black surfaces for the permission card and search field.
- **Pressed icon wash:** appears only while custom icon buttons are pressed.

Warnings and app errors use native SwiftUI `Color.orange`; no fixed RGB replacement is defined. Source: [`MixerStyle` and view foregrounds](Sources/Levels/MixerView.swift).

## Typography

Use SwiftUI `.system` fonts, resolved by macOS to the system SF family. There is no separate display or brand typeface. The frontmatter's CSS stack describes this native choice for portable previews.

- **Title:** semibold (18pt), for the island header; the compact popover header uses semibold (17pt).
- **App name:** medium (13pt), one line; the empty-state headline shares this treatment.
- **Control:** medium (12pt), for output selection and percentage labels. Supporting body copy and search text use regular (12pt).
- **Section:** semibold (12pt), for “Apps.” Permission-card headings use semibold (13pt).
- **Detail:** regular (11pt), for the subtitle, app activity, errors, and footer. The compact count is medium (11pt).

Percentage labels use monospaced digits in a trailing-aligned column (40pt). SF Symbols use role-specific sizes, including the compact glyph (13pt semibold) and options glyph (16pt medium). Source: [MixerView.swift](Sources/Levels/MixerView.swift), [IslandController.swift](Sources/Levels/IslandController.swift).

## Layout

All native dimensions are macOS points. The expanded width is 430pt, capped by screen width minus 24pt. Geometry comes from `NSScreen.frame`, `visibleFrame`, `safeAreaInsets.top`, and the auxiliary areas on either side of the housing. The cap height equals the reported top inset; mixer controls start beneath it. Prefer a notched screen when one is present, otherwise use the current main screen.

On the measured 185 × 33pt housing, compact geometry is 273 × 41pt: housing width plus 88pt, and cap height plus 8pt. These are a local example, not hardware constants. Without a notch, the compact floating pill is 148 × 36pt with a 34pt cap, positioned 12pt below the visible screen's top edge. Horizontal placement retains 12pt screen margins and supports negative display origins.

The mixer stacks its title header (52pt), output section (80pt), divider (1pt), Apps header (42pt), optional search section (44pt), app list, and footer (44pt). An access card adds 162pt including its bottom spacing; a general message adds 56pt instead. Most sections share the 22pt horizontal gutter.

App rows are 88pt, or 106pt when an app error is present. The list grows to its content height and is bounded at 352pt; the controller reduces that allowance according to available display height, with an 88pt minimum before the overall panel frame is capped. The empty state requests up to 132pt. Only the app list scrolls, preserving the surrounding controls. Search appears above five visible apps and remains while a query is entered.

**The App Identity Rule.** Playing apps precede idle apps, with localized alphabetical ordering within each group. Rows and saved levels use stable app IDs rather than list positions; owning bundle IDs are used where available. Reordering must retain each app's values.

Sources: [IslandGeometry.swift](Sources/MixerCore/IslandGeometry.swift), [`updateLayout`](Sources/Levels/IslandController.swift), [`fixedHeight`, `rowsHeight`, and `appList`](Sources/Levels/MixerView.swift), [`visibleApps` and ID-keyed settings](Sources/Levels/MixerModel.swift), [AudioApp identity](Sources/Levels/AudioHardware.swift).

## Elevation & Depth

The AppKit panel enables the system-managed window shadow (`NSPanel.hasShadow`). No custom shadow radius, opacity, or offset is specified. Within the island, depth comes from the continuous black surface, the lighter access/search surfaces, and the divider. Native control rendering supplies its own details. Source: [IslandController.swift](Sources/Levels/IslandController.swift), [MixerView.swift](Sources/Levels/MixerView.swift).

## Shapes

The housing-attached silhouette has small top curves (5pt) and lower curves bounded at 26pt or half the panel height, whichever is smaller. The floating fallback uses 22pt top curves with the same lower rule. A clear, non-interactive gap matching the reported housing width separates the compact glyph and active count. There is no popover arrow.

Access cards, search fields, and pressed icon backgrounds use the rounded values in frontmatter. The island itself uses the custom `IslandShape` path rather than a uniform rounded rectangle. Source: [`IslandShape` and `IslandView`](Sources/Levels/IslandController.swift).

## Components

### Compact island

The left SF mixer glyph and right ready-status dot plus real playing-app count flank the housing gap. A click toggles expansion; pointer dwell (0.25s) expands without immediately reacting to a crossing pointer. The count comes from app activity, not a simulated audio meter.

### Expanded mixer

The header offers the native options menu and a collapse button. The output menu shows the selected device with middle truncation; the system slider appears when that output exposes a controllable volume, otherwise a hardware-volume instruction appears. Keep native menu, slider, keyboard, and accessibility behavior.

### Menu bar popover

The optional popover is 400pt wide and uses a charcoal surface, a mint mixer glyph in the header, and a native close button. Its arrow, corners, and outside-click dismissal belong to `NSPopover`; anchor it to the full menu bar button bounds on the lower edge. Bound the list using the space below that button on its own display. The same model supplies app levels, search, and active-first ordering. In this mode, active audio labels use mint while idle labels remain gray. The normal mixer window shares this surface.

The native options menu includes an inline **Display Mode** choice between **Dynamic Island** and **Menu Bar Popover**. Switching removes the previous presentation, opens the selected one, and saves the choice for relaunch. It does not recreate the audio model. Popover Escape dismissal uses the root view’s native exit-command handler. Source: [PopoverController.swift](Sources/Levels/PopoverController.swift), [App.swift](Sources/Levels/App.swift), [MixerPresentation.swift](Sources/Levels/MixerPresentation.swift).

### App volume row

Each row pairs the real app icon (28pt) and name with activity or error text, then a mute button, native slider, and aligned level. Muting lowers slider opacity to 0.5 and changes the level text to “Muted.” Controls are disabled until audio access is ready. Error rows include Retry; the row context menu resets that app to 100%.

### Search and access states

Search uses a plain native text field on its darker inset surface. The access card uses native small bordered/prominent buttons or a progress indicator; its copy explains the next available action. Empty states distinguish no audio apps from no search matches. The footer pairs mixing status with Reset All.

### Expansion and dismissal

Panel resizing uses AppKit ease-out (0.28s); the mixer body uses a SwiftUI opacity and upward-offset transition (8pt) with ease-out (0.2s). Both omit animation when their native Reduce Motion setting is enabled. Collapse through the header button, Escape, or an outside click. The nonactivating auxiliary panel becomes key only as needed; a hover expansion preserves the underlying app's focus. Sources: [IslandController.swift](Sources/Levels/IslandController.swift), [MixerView.swift](Sources/Levels/MixerView.swift).

## Do's and Don'ts

### Do:

- **Do** derive the housing cap and gap from the current screen's reported geometry.
- **Do** keep interactive mixer content beneath the cap and long app lists bounded.
- **Do** place playing apps first, then idle apps, alphabetically within each group, while preserving identity and levels.
- **Do** retain native control behavior, system typography, and monospaced percentage digits.
- **Do** verify visible labels and sliders in the running app when saved scroll captures omit layers.

### Don't:

- **Don't** turn the measured housing dimensions into universal constants.
- **Don't** draw a manual popover arrow, put one on the island, or add simulated audio meters. The native popover owns its arrow.
- **Don't** replace system-managed menus, controls, or shadows with invented web styling.
- **Don't** treat window captures or geometry tests as proof of full-display pixel alignment or untested hardware behavior.
