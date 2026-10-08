# Levels

<!-- impeccable:product-schema 1 -->

## Platform

macOS, using AppKit and SwiftUI.

## Users and Purpose

The owner uses a MacBook with a camera notch, AirPods Pro, and external monitors. They want the independent application volume controls available in the Windows volume mixer, accessible quickly while other applications are in use.

## Operating Context

The user chose a menu bar interface and then preferred a Dynamic Island style presentation because the original popover arrow was misplaced and content was obscured by the notch. They now want a saved choice between the island and an updated menu bar popover. A normal window remains a secondary option.

## Capabilities and Constraints

Independent app volume and mute, remembered app levels, default output selection, and system volume. Uses public Core Audio process taps; no installed audio driver. System Audio Recording access is needed. Audio stays in memory on the Mac.

The app must derive camera-housing geometry from macOS, keep interactive content below it, and handle external displays without a notch. Preserve the working audio controls during UI changes. The user confirmed audible Chrome attenuation on AirPods Pro in this session.

## Brand Commitments

Name: Levels. Preserve the notch-aware island and offer a compact native popover anchored to its menu bar icon. The mode choice must persist after relaunch and switching must preserve audio levels. Controls retain native Mac keyboard, menu, slider, and accessibility behavior. Distribution uses a self-contained universal app in a drag-to-Applications DMG with first-use audio permission guidance. A public release must be Developer ID signed and notarized; a local test build must disclose its status.

## Evidence

The original user screenshot shows the faulty popover presentation. `docs/VERIFICATION.md` records the local audio verification. There is no public-release, notarization, broad hardware-compatibility, or latency benchmark claim.
