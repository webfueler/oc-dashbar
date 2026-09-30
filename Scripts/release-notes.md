<!--
Published as the GitHub Release notes by Scripts/release.sh:
  gh release create <tag> --notes-file Scripts/release-notes.md
Edit this file in place for each release.
-->

oc-dashbar is a macOS menu bar shell for the [oc-dash](https://github.com/webfueler/oc-dash) dashboard. It puts a status item in the menu bar; the popover behind it holds a webview pointed at the dashboard's `/widget` page. The numbers come from oc-dash, and this app is the frame around them.

## Install

Download `oc-dashbar-1.0.0.zip` and `oc-dashbar-1.0.0.zip.sha256`, then:

```sh
shasum -a 256 -c oc-dashbar-1.0.0.zip.sha256
unzip oc-dashbar-1.0.0.zip
mv oc-dashbar.app /Applications/
```

Later releases carry their own version in the asset names.

## The first launch is refused by Gatekeeper

The app is ad-hoc signed (`codesign -s -`) and not notarized, because this project has no Apple Developer membership. macOS quarantines a downloaded copy, so the first launch is stopped. Any one of these gets past it:

1. In Finder, right-click (or Control-click) `oc-dashbar.app`, choose Open, then click Open in the dialog. macOS remembers the exception.
2. System Settings, then Privacy & Security, then Security, then Open Anyway next to oc-dashbar.
3. In a terminal, before the first launch: `xattr -dr com.apple.quarantine /Applications/oc-dashbar.app`. Once macOS has evaluated a copy, the flag is locked and this route stops working; the two above always do.

None of them changes the app. It is the same unsigned copy either way.

## Requirements

- macOS 26 (Tahoe) or newer. The popover paints `NSGlassEffectView`, which is a macOS 26 API, and the bundle declares `LSMinimumSystemVersion 26.0`, so an older system refuses to launch it.
- Something that can run the dashboard: Node 22+ with `npx`, or a global install (`npm i -g @webfueler/oc-dash`).
- A dashboard running: `npx @webfueler/oc-dash@latest server start`. When it is not, the shell shows its own offline page with a start button that runs the same command.
- opencode2 on the machine with session data, for the dashboard to have numbers to show.

## After launch

The status item is a waveform icon in the menu bar. There is no Dock icon and no app menu, so quit from the widget's own quit control. The dashboard keeps running after the shell quits; the shell does not own it.
