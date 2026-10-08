# Releasing Levels

The downloadable artifact is a universal DMG containing Levels.app, an Applications shortcut and a Start Here guide. It requires macOS 14.2 or later. Users do not need Swift, Xcode, a terminal, an audio driver, or an installer.

## Local test download

```sh
zsh scripts/test.sh
zsh scripts/package-release.sh --development
```

This produces `dist/Levels-0.1.0-universal-test.dmg` and a SHA-256 checksum. The app is ad-hoc signed with hardened runtime. The DMG and guide explicitly disclose that it is a test build. A downloaded copy can require Apple's per-app **Open Anyway** flow; it is not a notarized public release. Do not tell users to disable Gatekeeper or remove quarantine flags.

## Public release

Install a valid **Developer ID Application** certificate with its private key in the macOS Keychain. Configure a `notarytool` Keychain profile using Apple's documented authentication workflow. Keep certificates and credentials outside this repository. The scripts accept an identity's full certificate name or SHA-1 fingerprint; they do not export keys or store account passwords.

```sh
export LEVELS_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export LEVELS_NOTARY_PROFILE='levels-notary'
zsh scripts/test.sh
zsh scripts/package-release.sh --release
```

The release command refuses to run without both settings and a valid Developer ID Application identity. It builds arm64 and x86_64, creates a universal app, enables hardened runtime with the Core Audio input entitlement, signs with a secure timestamp, submits the exact app archive to Apple, staples its ticket, and assesses it with Gatekeeper. It then creates and signs the DMG, submits that image to Apple, staples its ticket, validates it and writes the final checksum. Failure at any stage stops packaging; no test build is silently substituted for a release. Notarization uploads the app and disk image to Apple's notary service.

Developer ID builds use `Resources/Levels.entitlements`, which enables only `com.apple.security.device.audio-input`, matching the Core Audio input capability in Apple's tap sample and [Audio Input entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input). The local test build keeps the ad-hoc hardened-runtime configuration verified interactively. The route explicitly suppresses physical input channels; the app does not request microphone consent or capture microphone input.

Apple's requirements: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), and [Opening apps safely](https://support.apple.com/102445).

## Check the exact download

Mount the final DMG read-only, verify its app signature, copy Levels.app into a test Mac's Applications folder, eject the DMG, and launch that installed copy. Test an actual quarantined download of the public artifact on a separate Mac/account; launching an unquarantined local build does not establish Gatekeeper acceptance.

Check first-use System Audio Recording consent, a real app's audible attenuation, mute, resetting levels, both display modes, persisted choices after relaunch and restored original audio after quit. Test Intel hardware and macOS 14.2 separately before claiming runtime coverage; the universal binary alone proves only that both slices compiled. Bluetooth reconnects, USB/HDMI, sleep/wake and permission revocation remain hardware release checks.

## Compatibility and publication

The product, executable, package target and source directory are named Levels. `local.soundmixer.app` remains the bundle identifier deliberately so the original app's preferences carry over. Private audio-route UIDs share that namespace for filtering. Changing the signing identity or rebuilding an ad-hoc binary can still require renewed audio consent. Quit an older Sound Mixer copy before opening Levels.

Build directories, DMGs, generated icon PNGs and private UI review captures are ignored by Git. Publish the final DMG and matching checksum as release assets only after separate authorization. Git initialization and a local commit do not authorize a remote push. Before public source publication, choose a source license; no license has been assumed.
