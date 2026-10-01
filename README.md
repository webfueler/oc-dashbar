# oc-dashbar

Native macOS menu bar shell for the oc-dash dashboard. An `NSStatusItem` whose
popover holds a `WKWebView` pointed at the dashboard's `/widget` page.

The page itself lives in the oc-dash repository, and the dashboard ships as a
separate package (`@webfueler/oc-dash`). This repository is the shell around
it: status item, popover, URL, app bundle, and nothing else.

## Download

Releases are on GitHub: <https://github.com/webfueler/oc-dashbar/releases/latest>.
That `latest` link is the current release and always will be, so it is the one to
bookmark rather than a version number. The current one is 1.1.0, its two assets
are `oc-dashbar-1.1.0.zip` and `oc-dashbar-1.1.0.zip.sha256`, and later releases
carry their own version in those same two names.

```sh
shasum -a 256 -c oc-dashbar-1.1.0.zip.sha256   # prints: oc-dashbar-1.1.0.zip: OK
unzip oc-dashbar-1.1.0.zip
mv oc-dashbar.app /Applications/               # or drag it there in Finder
```

The archive carries no `._*` or `__MACOSX` entries, so the `unzip` above produces
exactly the bundle and nothing else. That is deliberate: those entries are what
make a bundle fail `codesign --verify --deep --strict` with "a sealed resource is
missing or invalid" after extraction, and they only appear if the archive was
built without `--norsrc`. `Scripts/release.sh` refuses to publish a zip that has
them.

Earlier releases stay on the same page under their own tags. 1.0.0 is the only
one without an app icon, and both of them predate the transparent panel.

### The first launch is stopped by Gatekeeper

The app is ad-hoc signed (`codesign -s -`) and not notarized, because there is
no Apple Developer membership behind this project. macOS quarantines the
downloaded copy, so the first launch is refused before the status item ever
appears. Any one of these gets past it:

1. In Finder, right-click (or Control-click) `oc-dashbar.app`, choose Open,
   then click Open in the dialog. macOS remembers the exception.
2. System Settings, then Privacy & Security, then Security, then Open Anyway
   next to the oc-dashbar entry.
3. In a terminal, before the first launch: `xattr -dr com.apple.quarantine
   /Applications/oc-dashbar.app`. Once macOS has evaluated a copy it locks the
   flag, so this route has to run before the first double-click; the two
   routes above work either way.

None of them changes the app. The workflow is the standard exception macOS
offers for software its owner chose to run, and it has to be a human at the
machine: nothing in the bundle can lift its own quarantine.

Once it is running the item is a waveform icon in the menu bar with today's spend
beside it. There is no Dock icon and no app menu.

### What the app needs to show anything

The zip is the shell only. It loads the widget page that oc-dash serves, so:

- macOS 26 (Tahoe) or newer. The zip declares `LSMinimumSystemVersion 26.0`.
- Something that can run the dashboard: Node 22+ with `npx`, or a global
  install (`npm i -g @webfueler/oc-dash`).
- A dashboard running: `npx @webfueler/oc-dash@latest server start`. If none
  is, the shell shows an offline page whose start button runs that command.
- opencode2 on the machine with session data, for the dashboard to have
  numbers.

The rest of this file is about how the two halves find each other, what the
start button does, and why the glass looks the way it does.

## Requirements

macOS 26 (Tahoe) or newer. No dependencies, no build system beyond SwiftPM and
`Scripts/build-app.sh`.

The floor is 26 because the popover paints `NSGlassEffectView`, which is macOS 26
and nothing older, and because a floor of 26 lets the code name one material
rather than choosing between two at runtime. The cost is stated plainly: a
macOS 15 machine cannot launch this app. The floor rose from 15 to 26 when the
material arrived; keeping 15 would mean a runtime choice between two materials.

## Build, run, test, lint

```sh
swift build                     # debug
swift build -c release          # release, what the app bundle uses
swift test                      # XCTest-less swift-testing suite in Tests/
./Scripts/build-app.sh          # assembles and ad-hoc signs build/oc-dashbar.app
./Scripts/build-app.sh debug    # same, from the debug build
open build/oc-dashbar.app       # run the bundle
xcrun swift-format lint -r Sources Tests   # xcrun is required, not on PATH
```

`Scripts/release.sh` wraps that list for a release. It runs the four commands
above as its gate, builds and stamps the bundle, writes
`build/oc-dashbar-<version>.zip` and its `.sha256`, tags `v<version>`, pushes
main and the tag, then creates the GitHub Release from
`Scripts/release-notes.md`. It needs `gh` logged in; without that it stops
after the push and prints the one `gh release create` command left to run.

The status item only shows up once the app runs. `LSUIElement` keeps it out of
the Dock, so there is no window to look for and no way to quit it from the
Finder. Use Activity Monitor, or `killall oc-dashbar`.

## Configuration

| Variable | Effect |
| --- | --- |
| `OC_DASHBAR_URL` | Overrides the widget URL and stops the search below it. Defaults to nothing; the fallback is the registry, then port 4021. It also moves the menu bar figure, which asks whichever server the panel is reading. |
| `XDG_STATE_HOME` | Which state directory the registry is read from. Defaults to `$HOME/.local/state`. |
| `OC_DASHBAR_OPEN_ON_LAUNCH` | Test hook. `1` opens the panel at launch, so the webview can be driven without a mouse click. |
| `OC_DASHBAR_MATERIAL` | Diagnostic hook. One of `glass-regular` (the default), `glass-regular-notint`, `glass-clear`, `visualEffect-behind`, `visualEffect-within`, `none`. Unset or unrecognised means `glass-regular`, which is the supported look; the other five exist so a panel that has gone opaque can be bisected, and `none` is the one that answers it, because it drops the material view and varies nothing else. |

```sh
OC_DASHBAR_URL=http://127.0.0.1:4123/widget OC_DASHBAR_OPEN_ON_LAUNCH=1 \
  ./build/oc-dashbar.app/Contents/MacOS/oc-dashbar
```

## Finding the dashboard

The panel needs to know where oc-dash is listening. It has no way to find out
for itself, so the shell resolves the URL on every open of the popover, in this
order, highest first:

1. `OC_DASHBAR_URL`. An explicit override wins and the registry is not even
   read.
2. The registry file written by `oc-dash server start`, if it is present, parses,
   and the `pid` it names is a live process.
3. `Config.defaultWidgetURLString`, which is port 4021.

The registry lives at `$XDG_STATE_HOME/oc-dash/service.json`, or
`~/.local/state/oc-dash/service.json` when `XDG_STATE_HOME` is unset, and holds
the four keys the other side writes:

```json
{ "port": 4021, "pid": 12345, "url": "http://127.0.0.1:4021", "version": "0.1.8" }
```

That path and shape belong to oc-dash, not to this repository, and they are the
same convention `@opencode/client` uses for `opencode/service.json`. Both sides
name them in one place so a mismatch is a diff rather than a search.

The file's `url` is a base URL and the shell appends `/widget`, so oc-dash never
has to know what the panel loads.

Two things are refused rather than believed. A `pid` that is not running means
the file is stale, and a file naming a dead process is worse than no file, so it
is ignored and the reason goes in the log:

```
[oc-dashbar] registry /Users/you/.local/state/oc-dash/service.json names dead pid 4242, not using it, falling back to http://127.0.0.1:4021/widget
```

A file that does not parse, or whose `port` and `url` disagree, is refused whole.
Half a file is not a URL. The file is never deleted here: oc-dash wrote it and
oc-dash removes it.

The resolution happens per open, not once at launch. A URL resolved at launch is
stale for the life of the process, and the dashboard can be started, stopped or
moved to another port while this widget sits in the menu bar. A reload only
happens when the resolved URL changed, which is the dashboard having moved, not
the shell hoping it came back. The page still owns its own refresh.

The shell still does not start, stop or supervise anything. Discovery is a file
read and a `kill(pid, 0)`. The one exception is the start control below, and it
is one spawn on one click, never touched again.

## Today's money in the menu bar

The status item's title is the server's `costText`, byte for byte. Nothing on
this side parses it, reformats it or compares it to zero, so a day with no spend
reads `$0.00` and a large one reads `$1,234,567.90`. There is no formatter here
on purpose: `Intl.NumberFormat` rounds ties away from zero and neither
`String(format:)` nor `NumberFormatter` reproduces that, so a formatter on this
side would be a correctness risk dressed as a tidy-up.

`NSStatusItem.variableLength` is load-bearing. `length` is the width of the slot
and content that does not fit is clipped, so under `squareLength` the button is
one icon wide and a title is cut off rather than shown beside it. An
`NSStatusBarButton` lays image and title out side by side, so no positioning is
needed; with an empty title the variable length collapses to the image's own
width and the control looks exactly as it did before this feature.

**Where the figure comes from.** `GET /api/summary?range=today&context=none`, on
whichever server the panel is reading. The widget URL is resolved first and its
path is replaced, its query and fragment dropped, so the figure can never end up
asking a different server than the panel just showed. A menu bar reading `$7.56`
beside a panel reading `$0.00` is indistinguishable from a bug, and this
derivation is what prevents it. `context=none` is required rather than cosmetic:
it skips the second stats call that only feeds the chart's muted context days,
and this shell renders no chart. A non-`http`/`https` scheme is refused, so a
`file:` URL cannot turn a background figure into a disk read.

**The poll.** Every 30 seconds, on the same clock the `/widget` page refreshes
on, plus one tick immediately at launch. Started at launch rather than on the
first panel open because the figure is only useful while the panel is closed, and
the immediate first tick because a menu bar that stays empty for half a minute
after every launch reads as a broken app rather than as a figure that has not
arrived yet. The timer is added for `.common` as well as `.default`, so the
figure keeps arriving while a menu is down. The server is re-resolved on every
tick rather than once at launch, for the same reason the panel re-resolves per
open: a dashboard can be restarted or moved to another port while this sits in
the menu bar. It costs one 90 byte file read per 30 seconds.

**At most one request in flight, ever.** `MoneyFetchGate` is the whole rule. A
tick that arrives while a request is in flight is skipped, not queued, so a slow
or hung server cannot become a growing pile of requests. There is no retry loop,
no backoff and no error cascade anywhere that could produce one.
`Config.moneyRequestTimeout` (10s) is what makes it recover rather than stick:
the gate alone would park every later tick behind a hung request forever.

**Nothing to show means empty, not something.** The Captain's rule is hide, and a
dash, a zero, a question mark or the last known value are all a figure of some
kind. An empty title is the one thing in a menu bar that is unambiguously
nothing. A figure from thirty seconds ago is removed rather than left up: a
stale number is a lie with a timestamp on it.

The four reasons are separate in the log, because a silently blank menu bar is
indistinguishable from a bug:

```
[oc-dashbar] today money: GET http://127.0.0.1:4021/api/summary?range=today&context=none
[oc-dashbar] today money: title is now $0.00, admitted=1 skipped=0
[oc-dashbar] today money: skipped a tick, the last request has not answered yet
[oc-dashbar] today money: hidden, request failed: The server crashed., admitted=2 skipped=0
[oc-dashbar] today money: hidden, the server answered degraded, and costText is absent on that arm, admitted=3 skipped=0
```

The two counters are on every line that changes or refuses to change the title,
so "the figure never arrived" and "the figure stopped changing" are two different
lines rather than one silence.

## Opening the dashboard in your browser

The widget's Dashboard button navigates to `oc-dash://open`. The shell cancels
that navigation and hands the URL to the real browser, leaving its own webview
exactly where it was. The scheme is the one the page emits, not a name this shell
picked, the same rule the quit and start verbs follow.

Only loopback targets are accepted: `127.0.0.1`, `localhost` and `::1`, from
`Config.openTargetHosts`. A miss costs a dead click and a hit on the wrong side
costs the Captain his browser, so a non-loopback host is refused rather than
believed. The path constraint is the other verbs' in both directions, and both
sides are matched lowercased, so `OC-Dash://OPEN/` is the same intent while
`oc-dash://open/extra` is not.

```
[oc-dashbar] open intent received: http://127.0.0.1:4021/
```

## Starting the dashboard

The widget's start control navigates to `oc-dash://start-server`. The shell
cancels that navigation and spawns the dashboard once, logs the outcome, and
never looks at the process again. It is not supervision: no retry, no timer, no
keep-alive, no restart, and nothing on the way out. `oc-dash server stop` stays
the only thing that stops a dashboard, and the shell does not stop it on quit
either.

The path constraint is the quit verb's, in both directions:
`oc-dash://start-server` and `oc-dash://start-server/` are the one verb, and
`oc-dash://start-server/anything` is cancelled and never acted on.

### The offline page carries the same control

The served widget's button is unreachable when no dashboard is serving it,
which is the case it exists for. So the shell's own offline page carries a
start control too, wired to the same verb, plus the command line under it:
`npx @webfueler/oc-dash@latest server start`. The button is the fast path; the
command is the escape hatch for a first run that has to download the package,
a machine that is offline, or a person who wants to read the output in their
own terminal.

After a click the page waits once, for `Config.startWatchTimeout`, and then
says it gave up and hands the reader back to the manual controls. One
`setTimeout`, no `setInterval`, no request to a server. The page cannot see
whether the spawn worked, so it never claims that it did. The port that was
tried and the registry file the shell consults sit at the bottom of the page,
because those two values are the whole answer to "which port, which file".

### Why the command is found the way it is

An app launched from Finder, or with `open`, inherits almost nothing. Measured
on this machine, a Finder launch of this shell sees:

```
SHELL=/bin/zsh
PATH=/usr/bin:/bin:/usr/sbin:/sbin
```

No nvm, no Homebrew, no `/usr/local/bin`, and therefore no `npx`. So the shell
asks the login shell what its PATH is, and it spawns what it found with that
PATH rather than the one it inherited:

```
$SHELL -l -i -c 'printf ...; command -v oc-dash; command -v npx; ...'
```

`$SHELL` first, because that is what the user's own terminal uses and a
Finder-launched app does have it, with the passwd entry as the fallback for a
process that has no `SHELL` at all. The flags are `-l -i -c` and the `-i` is
not decoration: zsh sources `.zshrc`, which is where nvm installs itself, only
for an interactive shell. Measured here, from the Finder environment above:

| Command | Result |
| --- | --- |
| `/bin/zsh -l -c` | PATH has Homebrew, **no npx** |
| `/bin/zsh -l -i -c` | PATH has Homebrew and nvm, **npx found** |

The child's stdin is `/dev/null`, because an interactive shell may want a
terminal and this one has none, and the probe runs on a deadline. That deadline
is the only place in this shell that signals anything, and what it signals is
the login shell it spawned itself.

`npx` is `#!/usr/bin/env node`, so handing the child the right PATH is not
cosmetic either: spawning the absolute path that was found while leaving PATH
as Finder left it fails with `env: node: No such file or directory`.

Binaries are tried in the order `Config.startBinaryNames`, so an installed
`oc-dash` wins over `npx` and runs without asking npm to fetch anything. `npx`
is the fallback for the machine where the package was never installed globally,
and it gets the published package reference `@webfueler/oc-dash@latest`. The tag
is not decoration: a bare name reaches npx as the range `*`, which it tries to
satisfy with a copy already on the machine, while a tag is resolved against the
registry and the button starts what is published now. The bare name `oc-dash`
is a 404 on the registry.

### When it does not work, the log says which thing failed

The point of this feature is the message, so every failure mode has its own.
One line each, on stderr, with the child's own words quoted underneath:

```
[oc-dashbar] start request #1 start failed: oc-dash is not installed, and neither is npx. Asked /bin/bash -l -i -c for its PATH: 12 entries, and neither "oc-dash" nor "npx" is in it.
[oc-dashbar]   PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
[oc-dashbar]   A login shell that has never run a version manager has no node on it, which is the normal state of a machine where npm was never set up.
[oc-dashbar]   Install it once, with: npm i -g @webfueler/oc-dash
[oc-dashbar]   Or start the dashboard from a terminal: npx @webfueler/oc-dash@latest server start
```

The other seven are no login shell at all, a login shell that would not run,
one that failed, one that never answered, one that answered with no PATH in it,
a spawn that failed (a half-removed install, which is a different fix), and a
start that exited non-zero. `StartServer.Failure` is the whole list, and each
case's text is asserted in `Tests/oc-dashbar-tests/StartServerTests.swift`.

A start that is still running after `Config.startWatchTimeout`:

```
[oc-dashbar] start request #1: /Users/you/.nvm/versions/node/v22.22.2/bin/npx @webfueler/oc-dash@latest server start is still running after 25s, which is what a started server looks like. Not watching it again: oc-dash server stop is the only thing that stops it.
[oc-dashbar] start request #1, the child said:
[oc-dashbar]   oc-dash listening on http://127.0.0.1:4022
```

25 seconds is a deadline, not a poll. It is there to hear a refusal, which is
the failure this button can produce. A process still running when the deadline
expires is a process that started, and the shell forgets it there.

## The material

**The panel is transparent.** Your desktop shows through it. That is the whole
point of the material: the widget floats on the wallpaper rather than sitting on
a slab.

Three things have to line up for that, and the first one is the part that is not
public API.

**1. WebKit must not paint its own background.** This is the private write.
`AppDelegate.applyWebviewCompositing(to:)` sets `drawsBackground` to `false` on
the `WKWebView` by KVC. That key is in no header on this SDK, and no public API
does the job: `underPageBackgroundColor` is documented as the colour "used as the
background color under the page's content, such as for scroll bouncing areas",
which is the region *under* the content and not the region outside it, and
setting it to `.clear` changes nothing there. The view-level `isOpaque` reads
`true` on a fresh `WKWebView`, is readonly, and neither `setOpaque:` nor a KVC
write to `opaque` clears it.

**Apple may remove this key in any macOS update, without deprecating it and
without a compile error here, because the write is by string.** If the panel is
ever opaque again, read that function before looking anywhere else. Two things
follow from it:

- `ConfigTests` asserts the underscored selector `_setDrawsBackground:` is still
  on `WKWebView`. The obvious name is not implemented, so asking about that one
  would pass on a WebKit that had thrown the key away.
- The write is deliberately unguarded. A KVC write to a key the runtime no longer
  has raises `NSUnknownKeyException`, which in Swift is a trap, so a macOS that
  drops the key outright fails at launch instead of quietly shipping an opaque
  panel. What no guard catches is a key that survives and stops mattering, and
  the selector test above is what covers that half.

**2. A real system material has to be behind the page.** Four values in
`Config.swift`, no environment variables, because they are decisions and not
per-run settings:

| Value | Default | What it does |
| --- | --- | --- |
| `translucentPanel` | `true` | The switch. `false` builds no material and leaves the popover opaque, which is AppKit's default. |
| `panelMaterialVariant` | `.glassRegular` | Read from `OC_DASHBAR_MATERIAL`, a diagnostic hook. `glass-regular` is `NSGlassEffectView` with `.regular` style, which is the supported look. The other five values are there to bisect an opaque panel and are documented in the `Configuration` table above. |
| `panelMaterialOpacity` | `1.0` | The material view's own alpha, clamped to 0...1. Lower values fade the rim and highlight too. |
| `panelCornerRadius` | `8.0` | AppKit's own default for glass. The popover's curve is AppKit's and is not readable from code. |

The floor being 26 is what makes `glass-regular` the only supported value:
`NSGlassEffectView` is a macOS 26 API, so there is one code path and no runtime
choice between two materials.

**3. The material has to cover the whole popover, arrow included.**
`popover.contentSize` does not account for the chevron, so the window is the
content size grown by 13 points on every edge and the content view is centred
inside it. AppKit installs its own glass across that whole shape, so a material
that covered only the content rect left the arrow band showing one glass layer
and the body showing two: a visible seam at the top.

The fix is to reach our material past the content rect by that same inset, so the
layer count is equal everywhere across the shape. `Config.popoverChevronInset` is
13.0, **measured** on a live popover at three content sizes rather than read from
a header, because it is in none. The material view then re-measures it at run time
via `measuredChevronInset(in:)`, which asks the popover's own frame view and
accepts the answer only when the window is an `NSPanel` and all four edges agree,
so a future macOS moving the band is followed rather than hard-coded. A failed
read falls back to the constant, which costs a shade seam, not a wrong panel.

**The page owns the rest.** The shell cannot make `/widget` translucent: that page
has to drop its own opaque `html, body` and `.widget` backgrounds in oc-dash. A
panel that still looks solid with a transparent page means the CSS is painting.

The window is prepared **after** `show()`, never before. `NSPopover` builds its
`NSWindow` inside `show()`, so a call made ahead of it finds nothing on the first
open. `PopoverWindowPreparation` holds that rule as a pure function, keyed on the
identity of the window, so a show that reuses the panel costs nothing and a show
that builds a fresh one is prepared again. The open log line carries
`showCount`, `shown`, `prepared` and `windowOpaque` for the same reason: a
screenshot of a panel cannot tell you which of those ran.

## Quit

The widget's quit control navigates to `oc-dash://quit`. The shell cancels that
navigation and terminates itself. It kills nothing else: this shell has never
supervised oc-dash, so the dashboard on 4021 keeps running after the widget quits,
and it keeps running after a widget started one.

The scheme is the one the page emits, not a name this shell picked. It used to
answer `ocdashbar://quit`, which the page never emitted, so the quit control did
nothing until the two sides were compared.

All three verbs (`quit`, `start-server` and `open`) are matched on a lowercased
scheme and host, and only with an empty or "/" path, so `oc-dash://quit/` and
`OC-Dash://QUIT` are the same intent while `oc-dash://quit/extra` and
`oc-dash://start-server/extra` are not. Anything else on the `oc-dash` scheme,
any scheme outside `http`, `https` and `about`, and the retired `ocdashbar`
scheme, are cancelled and never navigated. One log line, on stderr:

```
[oc-dashbar] quit intent received, request #1, terminating oc-dashbar
```

## Layout

```
Package.swift                      SwiftPM manifest, no dependencies
Sources/oc-dashbar/Config.swift    every constant and the URL override
Sources/oc-dashbar/Log.swift       stderr + unified log
Sources/oc-dashbar/Main.swift      @main entry point
Sources/oc-dashbar/PanelMaterial.swift  the two system materials, one view
Sources/oc-dashbar/PopoverWindowPreparation.swift  when the popover's window is prepared
Sources/oc-dashbar/PanelNavigation.swift    what one navigation means: act, cancel or allow
Sources/oc-dashbar/ServiceRegistry.swift  where oc-dash registers, and whether it is trusted
Sources/oc-dashbar/StartServer.swift  the login shell PATH, the spawn, and the failure messages
Sources/oc-dashbar/OfflinePage.swift  the page shown when the dashboard is not answering
Sources/oc-dashbar/MoneyFigure.swift  the menu bar figure and the one-request-at-a-time gate
Sources/oc-dashbar/AppDelegate.swift  status item, popover, webview, offline page, money poll
Tests/oc-dashbar-tests/            config, discovery, material and ordering tests, incl. cross-repo contracts
Scripts/build-app.sh               the whole "build system"
Scripts/release.sh                 the release: gate, zip, tag, push, gh release
Scripts/release-notes.md           the text published as the release notes
```

## Rules

- The shell does not start, stop or supervise oc-dash. There is no launch agent,
  no login item, no retry loop and no keep-alive. The start verb is one spawn on
  one explicit click and then the shell is done with it.
- The one timer in this app is the menu bar figure's 30 second poll, and it
  changed what "does not poll" used to mean. It existed for the page's refresh
  and does not exist for that any more: the page owns its own refresh and always
  did. What the poll does is read one summary endpoint and write a string onto a
  button, and it cannot start, stop or restart anything. It is bounded three
  ways that matter: one request in flight at a time, a 10 second timeout, and no
  retry, so the worst case is one live request rather than a growing pile of them.
- Re-reading the registry is a lookup, not supervision, and it is what keeps the
  figure and the panel honest about which server they are talking to.
- The only signal this shell ever sends is to the login shell it spawned itself,
  when that shell stops answering a deadline. Nothing here holds a dashboard's
  pid, and there is no code that could signal one. `ServiceRegistry`'s
  `kill(pid, 0)` asks a question and delivers nothing.
- The registry path and its four JSON keys are a cross-repo contract. They are
  named in `Config.swift` on this side and by `oc-dash server start` on the
  other, and both must move together. So is the start verb's URL.
- If the dashboard is unreachable the shell shows a small offline page with a
  start control, a manual retry link and the command line. It does not try to
  fix the server, and the page's one wait after a click is bounded by
  `Config.startWatchTimeout` and visibly gives up; it never polls and never
  claims a start it cannot observe.
- Sign with `codesign -s -` only. No Developer ID, no notarization.
- The deployment floor lives in two places that must move together:
  `platforms:` in `Package.swift` and `LSMinimumSystemVersion` in
  `Scripts/build-app.sh`. The floor is also the thing that makes the material a
  single code path, so lower it and `PanelMaterial.swift` stops compiling until
  someone chooses what a macOS 15 popover paints instead.
- The panel is 340x420 points, matching what the `/widget` page is designed
  for. Change `Config.panelSize` if that contract ever moves, and move it in
  one commit with the page.

## License

MIT, the same licence as oc-dash. See `LICENSE`.
