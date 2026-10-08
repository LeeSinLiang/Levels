# Island UI direction

Scope: replace the misplaced menu bar popover with the user's requested Dynamic Island style presentation, keeping all audio functionality.

The user subsequently requested both presentations. The mixer's native options menu now includes a saved Display Mode choice. Menu Bar Popover uses a compact 400-point charcoal body, native arrow anchored to the full menu bar button bounds, a close button, and mint activity labels. Switching removes the previous presentation and retains the same audio model and levels. Dynamic Island retains the geometry and behavior described below.

The compact black island wraps the Mac's actual camera housing, with a mixer glyph on its left and a real active-client count on its right. A short pointer dwell or click expands it downward. The expanded body contains the title, output menu and system slider, app sliders and mute, and options. Core controls begin below the reported safe top inset. There is no popover arrow.

Use a black surface, restrained mint accent for controls/status, SF system typography, and aligned percentage labels. No simulated audio meters. Search appears when enough visible apps need it, and remains available while a query is entered. Long lists scroll rather than push controls off-screen.

Apps currently playing audio precede idle apps, with alphabetical order within each group. Preserve app identity and saved levels as activity changes reorder the list.

Collapse with the header button, Escape, or an outside click. Expansion animates from the same top anchor and respects Reduce Motion. The borderless auxiliary panel preserves the current app's focus until a control needs keyboard input. Prefer the built-in notched screen when present; a separate floating pill is the fallback when only external displays are available.

Acceptance: inspect actual expanded and collapsed states on the built-in display, verify menus and the expanded controls are fully visible below the notch, and check many-app scrolling. Geometry checks also cover non-notched screens and negative display coordinates. The audio processing engine is outside this visual change.
