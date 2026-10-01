<!--
Published as the GitHub Release notes by Scripts/release.sh:
  gh release create <tag> --notes-file Scripts/release-notes.md
Edit this file in place for each release.
-->

oc-dashbar is a macOS menu bar shell for the [oc-dash](https://github.com/webfueler/oc-dash) dashboard. It puts a status item in the menu bar; the popover behind it holds a webview pointed at the dashboard's `/widget` page. The numbers come from oc-dash, and this app is the frame around them.

## 1.1.0: a transparent panel and today's money in the menu bar

Three things a person can see, and no migration.

**The panel is transparent.** Your desktop shows through it. There is no frosted
slab in the middle of the screen any more; the widget floats on the wallpaper
and only its own content is drawn. This is a change to how the panel composites
rather than to what it shows, and it is the reason this is a minor release rather
than a patch.

It works by telling WebKit not to paint a background behind the page. The knob
that does that is a private one, undocumented in any header on the SDK, written
by name rather than by a compile-checked property. It is called out in the code
because it matters: if a future macOS stops honouring it, this app will launch
normally and the panel will be opaque again, with nothing in the log saying why.
The README says what to look at if you ever see that.

**Today's spend sits in the menu bar**, to the right of the icon, as `$12.34`,
refreshed every 30 seconds on the same clock the widget page itself refreshes
on. It is the server's own `costText`, byte for byte: nothing on this side
parses it, reformats it or compares it to zero, so a day with no spend reads
`$0.00` and a large one reads `$1,234,567.90` rather than being abbreviated or
rounded.

When there is no figure to show, the space is empty rather than showing a dash, a
zero, a question mark or the last number it saw. A stale number is a lie with a
timestamp on it. The cases that mean "no figure" are separate in the log, so an
empty menu bar is never ambiguous between "the dashboard is not running", "the
dashboard answered but had nothing for today", and "the request failed":

```
[oc-dashbar] today money: GET http://127.0.0.1:4021/api/summary?range=today&context=none
[oc-dashbar] today money: title is now $12.34, admitted=1 skipped=0
[oc-dashbar] today money: hidden, costText was missing, null or blank, admitted=2 skipped=0
```

The figure asks whichever server the panel is reading, resolved by the same
three-step rule the panel uses, and re-resolved on every tick rather than once at
launch, so a dashboard you restart or move to another port is picked up while the
widget sits in the menu bar. One request at a time, ever: a tick that arrives
while the last one is still in flight is skipped, not queued, so a slow server
cannot become a pile of requests.

**A Dashboard button opens the dashboard in your browser.** The widget page's
footer button sends `oc-dash://open`, the shell takes it, and it hands the URL to
your real browser. The app never navigates its own webview away to do it, so the
panel stays exactly as it was. Only loopback addresses are accepted, and the
shell writes the request to the log either way:

```
[oc-dashbar] open intent received: http://127.0.0.1:4021/
```

Nothing else changed. The popover size, the widget URL, the order the dashboard
is found in, the start control and the quit control all behave as they did in
1.0.1. 1.0.1 and 1.0.0 stay downloadable under their own tags.

The app is `LSUIElement`, so there is no Dock tile. Quit from the widget's own
quit control.

## Install

Download `oc-dashbar-1.1.0.zip` and `oc-dashbar-1.1.0.zip.sha256` from
<https://github.com/webfueler/oc-dashbar/releases/latest>, then:

```sh
shasum -a 256 -c oc-dashbar-1.1.0.zip.sha256
unzip oc-dashbar-1.1.0.zip
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
- A dashboard running: `npx @webfueler/oc-dash@latest server start`. When it is not, the shell shows its own offline page with a start button that runs the same command, and the menu bar figure stays empty until one is.
- opencode2 on the machine with session data, for the dashboard to have numbers to show.

## After launch

The status item is a waveform icon in the menu bar, with today's spend beside it
once the dashboard has answered. There is no Dock icon and no app menu, so quit
from the widget's own quit control. The dashboard keeps running after the shell
quits; the shell does not own it.
