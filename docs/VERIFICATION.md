# Local verification

## Levels test download — 2026-10-08

- Renamed the product, app bundle, executable, package target, source directory, visible title, accessibility labels, audio-route names and documentation to Levels. The existing `local.soundmixer.app` identity and preference keys remain deliberately compatible with the original mixer.
- `zsh scripts/test.sh`: all 16 audio, settings, identity and island-geometry checks passed with zero failures.
- The release build compiled arm64 and x86_64 slices. `lipo` verified both in the app copied from the DMG. `vtool -show-build` reports macOS 14.2 as the minimum for both slices. Linked libraries are Apple system frameworks and Swift libraries supplied by macOS; there are no project-path runtime dependencies.
- Strict app signature verification passed before packaging, within the read-only mounted DMG, and after copying its app to a standalone verification folder. The signature is ad-hoc with hardened runtime, not Developer ID or Apple notarization.
- `dist/Levels-0.1.0-universal-test.dmg` passed disk-image integrity verification and its SHA-256 checksum. The actual mounted contents include Levels.app, an Applications shortcut resolving to `/Applications`, Start Here.html and a test-build notice. Its executable matches the built executable byte for byte. The guide in the DMG and the app's sealed resources matches the source guide.
- After the DMG was ejected, the copied app's `--list` diagnostic exited successfully and found the built-in MacBook Air Speakers and real audio applications. This establishes standalone execution outside the disk image; it does not establish a quarantined download's Gatekeeper acceptance.
- The copied app's `--check-audio-access` diagnostic reported `unavailable` and exited with status 1 when launched directly from the command runner. A controlled copy with the Core Audio input entitlement reported the same result. The user then installed the DMG app into Applications, ejected the image, opened Levels normally and confirmed “Yes—installed and volume works.” The real installed app's own self-test reached “Mixing on this Mac.” The command-runner result is therefore not evidence of a capture failure in the installed GUI app. Developer ID builds use Apple's Core Audio input entitlement; the test build retains its verified ad-hoc configuration.
- The public release command rejected absent signing/notary settings, an ad-hoc identity, an unavailable Developer ID certificate and unknown modes with status 2 before building or uploading. No valid Developer ID identities were available. The user chose to prepare the test download. The notarized workflow is documented and implemented but has not been exercised with credentials.
- Native inspection of `/Applications/Levels.app` showed the renamed Levels header, current output, aligned controls, a real active app before idle clients and “Mixing on this Mac.” The app slider was observed at 14% while the master remained 44%; the user confirmed volume control works. A native window screenshot showed readable labels, controls, search and footer. Finder automation was unavailable, but direct Levels inspection succeeded after the user installed it.
- The installed copy switched from popover to the renamed Levels Island with the same six clients, levels and system volume. Escape collapsed it to the compact cap. The user confirmed this UI works and requested an end to computer-use testing; no further UI automation was performed.
- The final regenerated DMG was mounted read-only and its executable, Info.plist and sealed-resource manifest compared byte for byte with the working app in `/Applications/Levels.app`. All comparisons passed, along with strict signature verification, both architecture checks, the setup-guide comparison and Applications shortcut check. The verification image was ejected. Final SHA-256: `fc2a84b9f04f0b4dab40ab654489d5f8d8c69be94b02fbf77fed8de99e426406`.
- Build outputs, disk images, generated icon PNGs, private UI captures, downloaded Apple reference material and the design-hook cache are excluded from the initial source commit. Earlier UI acceptance remains recorded below.

Intel hardware, the macOS 14.2 runtime, a fresh quarantined install on another Mac/account and the hardware behaviors listed below remain separate checks. A universal build is not a claim of hardware coverage.

## Original implementation

Built and checked on 2026-10-06 on an Apple Silicon MacBook Air running macOS 26.6, using Swift 6.3.3 and Command Line Tools.

- `zsh scripts/test.sh`: 12 regression checks passed, zero failures. This executes the actual C processing code and checks independent gain, startup mute, stereo buffer layouts, mono output, physical-input skipping, bounds, smooth gain changes, invalid samples, probe behavior, saved settings, and helper grouping.
- `zsh scripts/build-app.sh`: release build succeeded. The ad-hoc app signature passed `codesign --verify --deep --strict`. Linked dependencies are Apple system frameworks/libraries only.
- The actual menu bar popover was opened and visually inspected. Application labels, app icons, output selector, master slider, permission guidance, and volume controls were readable and unclipped. The optional normal window also opened correctly.
- Live audio inventory found MacBook Air Speakers, Humanscale USB Audio, and AirPods Pro. The default output during the interactive check was AirPods Pro. Chrome's audio helpers were grouped into one Google Chrome row; idle audio clients included Spotify, Discord, QuickTime Player, and others.
- The user granted audio access. The app then passed its real loopback permission check and enabled application sliders. This confirms that the native tap/aggregate callback received the app's own near-silent test signal on this output.
- Chrome's live slider was lowered from 100% to approximately 29%. No route error was reported, and the master volume stayed at 38% during the change. The user confirmed that Chrome became quieter while the Mac's main volume stayed the same. This verifies audible per-app attenuation on the connected AirPods Pro, beyond the UI state and regression checks.
- Chrome's mute button changed its state to Muted and then back to Audio active without a reported route error. The slider was subsequently restored to 100%, unmuted. The normal test window was closed and the app returned to its menu bar popover.
- Audible mute was not separately confirmed by the user; its UI state and zero-gain processing were checked.

Hardware behaviors not yet verified: built-in/USB output switching during playback, Bluetooth reconnects, simultaneous unrelated applications, helper replacement, sleep/wake, permission revocation, exclusive device use, and measured latency/CPU usage.

The initial command-line app launch inside the restrictive shell sandbox failed before normal desktop access. The same app launched successfully through the native desktop interface, and its read-only inventory succeeded outside the shell sandbox. That sandbox failure is not evidence of a normal app-launch failure.

## Island redesign and activity ordering

The arrow popover was replaced with a borderless AppKit panel and a native SwiftUI island. The audio tap and processing implementation was preserved.

- The regression suite now passes 16 checks with zero failures. Four additional checks cover the camera gap, compact side controls, positive/negative external-display coordinates, and display-height limits.
- The updated release build succeeded and its ad-hoc signature passed strict verification. The final app was relaunched through the native desktop interface, and audio access rechecked successfully without another permission prompt.
- Live `NSScreen` data reports the built-in display at 1710 × 1107 points, a 33-point safe top inset, and auxiliary areas ending at x=763 and starting at x=948. The island reserves that 185-point camera gap. The expanded controls begin below y=1074; compact mode is 273 × 41 points. These are geometry checks, not a composited full-display pixel inspection.
- Actual native expanded and compact window captures were inspected. The output chevron has separate spacing from the device name. Escape collapses the expanded panel, and clicking its side control reopens it. Options and output menus open successfully; the output choices appear below the cap and AirPods Pro remains selected.
- With eight audio clients displayed, the app list exposes native scrolling and the scroll position moves from 0 to 1 to reach the last four clients. The header, search, output controls and footer remain separate from the scrolling list. Saved screenshots intermittently omit some layers after scrolling. Asked whether the labels and sliders remain visible on the actual screen, the user confirmed: “Yes, everything stays visible.” This identifies the missing layers as a capture limitation rather than a user-visible scrolling defect.
- After the activity-order update, live accessibility state showed Google Chrome with “Audio active” first, followed by idle ChatGPT, Claude, Discord and the remaining clients in alphabetical order. This verifies that active apps precede idle apps in the running release. No volumes or output devices were changed for the redesign checks.
- A fresh visual reviewer returned `ship` for the compact, expanded, and many-app native window states. Whole-display pixel placement was outside that review's evidence; geometry and the user's live scrolling confirmation provide separate verification.

External-display fallback and Reduce Motion behavior are implemented and covered by geometry/code inspection; they were not separately exercised in the live desktop session.

## Saved display mode and refreshed popover

- The options menu offers an inline Display Mode choice between Dynamic Island and Menu Bar Popover. Live selection switched popover → island → popover. The prior presentation disappeared each time; eight app clients, their 100% unmuted levels, and the current output remained consistent.
- The refreshed 400-point popover was visually inspected with eight apps. Its native arrow, header glyph, close button, output selector, aligned sliders, mint active-audio label, search, bounded list, and footer were visible. Chrome appeared above the alphabetized idle apps. A capture is saved at `.impeccable/review/mac-popover.png`.
- The selected `menuPopover` value was confirmed in the app's preferences after quitting. The next app process launched successfully. The automation could not consistently bind the transient popover window after relaunch; this is not a confirmed app-launch failure, since the process remained running and popover windows dismiss on outside interaction.
- The final release compiled successfully and the regression suite still passed 16 checks with zero failures. Switching presentation keeps the existing MixerModel instance and does not call its audio-route shutdown.
- An initial Escape check failed. The popover now activates for keyboard interaction and its root SwiftUI view has an explicit exit-command dismissal handler. The user subsequently confirmed the finished update with “nice it works.” This is user acceptance of the final UI; no separate automated Escape pass is claimed.
