<!--
Published as the GitHub Release notes by Scripts/release.sh:
  gh release create <tag> --notes-file Scripts/release-notes.md
Edit this file in place for each release.
-->

oc-dashbar is a macOS menu bar shell for the [oc-dash](https://github.com/webfueler/oc-dash) dashboard. It puts a status item in the menu bar; the popover behind it holds a webview pointed at the dashboard's `/widget` page. The numbers come from oc-dash, and this app is the frame around them.

## 1.2.0: the panel recovers on its own, and the help page is transparent

Three things a person can see, and no migration.

**The panel puts up its own help page when the dashboard stops answering**, not
only when a load fails. Until now the shell found out the dashboard was gone by
failing to load it. Now the widget page notices for itself, says so with
`oc-dash://offline`, and the shell answers by swapping in the same help page it
shows on a failed load. The page cannot load a document into the panel, so it
reports and the shell does the swapping. The log line says where the belief came
from, not just what happened:

```
[oc-dashbar] offline intent received, from oc-dash://offline, showing the offline page
```

The verb is answered on the same terms as the other three: the path must be empty
or `/`, a query is ignored, and a path beyond the verb is cancelled and never
acted on. It carries no target, because "the dashboard is gone" is all it says.

**The help page is transparent**, like the panel. In 1.1.0 it painted an opaque
`Canvas` background, so a dashboard that went away produced a grey slab floating
over your desktop, with none of the translucency the panel has. Every background
declaration is gone, so the help page composites over the same material the
widget does. There is no scrim behind the text and no shadow on the ink to buy
the contrast back: the text still uses the system's own `CanvasText` and
`LinkText`, so it follows your light or dark appearance on its own. If the help
page ever looks hard to read against a busy wallpaper, that is a real
observation and worth reporting, not something this release papers over.

**Try again now really tries.** This was a bug rather than a feature, found
while looking for something else and reproduced on the first attempt. The help
page used to be loaded with a nil base URL, which leaves the webview's URL as
`about:blank`, and reloading `about:blank` produces an empty document rather than
a page. Measured with a real webview: 128 bytes of document became 39 and every
element was gone, so a reload gesture while the help page was up blanked the
panel instead of retrying anything. The URL that failed is now the base, so a
reload re-navigates it. Dashboard back, you get the widget. Dashboard still down,
you get this page again through the same failure path. A reload is a retry now.

That is a new recovery behaviour and a changed offline appearance, which is why
this is 1.2.0 and not 1.1.1.

Nothing else changed. The popover is still 340x420, the dashboard is still found
in the same order, the start control, the quit control and the Dashboard button
all behave as they did in 1.1.0, and the menu bar figure still polls every 30
seconds and still shows the server's own `costText` byte for byte. 1.1.0, 1.0.1
and 1.0.0 stay downloadable under their own tags.

The app is `LSUIElement`, so there is no Dock tile. Quit from the widget's own
quit control.

## Install

Download `oc-dashbar-1.2.0.zip` and `oc-dashbar-1.2.0.zip.sha256` from
<https://github.com/webfueler/oc-dashbar/releases/latest>, then:

```sh
shasum -a 256 -c oc-dashbar-1.2.0.zip.sha256
unzip oc-dashbar-1.2.0.zip
mv oc-dashbar.app /Applications/
```

That `latest` link is always the current release, so it is the one to bookmark
rather than a version number. Later releases carry their own version in the asset
names.

The archive carries no `._*` or `__MACOSX` entries, so Info-ZIP's `unzip` above
produces exactly the bundle and nothing else. That matters: those entries are
what make a bundle fail `codesign --verify` with "a sealed resource is missing or
invalid" after extraction. If you see one, you did not get the zip from GitHub.

## The first launch is refused by Gatekeeper

The app is ad-hoc signed (`codesign -s -`) and not notarized, because this project
has no Apple Developer membership. macOS quarantines a downloaded copy, so the
first launch is stopped. Any one of these gets past it:

1. In Finder, right-click (or Control-click) `oc-dashbar.app`, choose Open, then click Open in the dialog. macOS remembers the exception.
2. System Settings, then Privacy & Security, then Security, then Open Anyway next to oc-dashbar.
3. In a terminal, before the first launch: `xattr -dr com.apple.quarantine /Applications/oc-dashbar.app`. Once macOS has evaluated a copy, the flag is locked and this route stops working; the two above always do.

None of them changes the app. It is the same unsigned copy either way.

## Requirements

- macOS 26 (Tahoe) or newer. The popover paints `NSGlassEffectView`, which is a macOS 26 API, and the bundle declares `LSMinimumSystemVersion 26.0`, so an older system refuses to launch it.
- Something that can run the dashboard: Node 22+ with `npx`, or a global install (`npm i -g @webfueler/oc-dash`). The shell never bundles the dashboard.
- A dashboard running: `npx @webfueler/oc-dash@latest server start`. When it is not, the shell shows its own help page with a start button that runs the same command, and the menu bar figure stays empty until one is.
- opencode2 on the machine with session data, for the dashboard to have numbers to show.

## After launch

The status item is a waveform icon in the menu bar, with today's spend beside it
once the dashboard has answered. The panel is transparent, so your desktop shows
through it in both states, the live widget and the help page. There is no Dock
icon and no app menu, so quit from the widget's own quit control. The dashboard
keeps running after the shell quits; the shell does not own it.
