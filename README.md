# oc-dashbar

Native macOS menu bar shell for the oc-dash dashboard. An `NSStatusItem` whose
popover holds a `WKWebView` pointed at the dashboard's `/widget` page.

The page itself lives in the oc-dash repository, and the dashboard ships as a
separate package (`@webfueler/oc-dash`). This repository is the shell around
it: status item, popover, URL, app bundle, and nothing else.

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

The status item only shows up once the app runs. `LSUIElement` keeps it out of
the Dock, so there is no window to look for and no way to quit it from the
Finder. Use Activity Monitor, or `killall oc-dashbar`.

## Configuration

| Variable | Effect |
| --- | --- |
| `OC_DASHBAR_URL` | Overrides the widget URL and stops the search below it. Defaults to nothing; the fallback is the registry, then port 4021. |
| `XDG_STATE_HOME` | Which state directory the registry is read from. Defaults to `$HOME/.local/state`. |
| `OC_DASHBAR_OPEN_ON_LAUNCH` | Test hook. `1` opens the panel at launch, so the webview can be driven without a mouse click. |

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

The popover composites a real system material behind the webview, so a page with
a transparent ground shows the desktop through it. Four values in
`Config.swift`, no environment variables, because they are decisions and not
per-run settings:

| Value | Default | What it does |
| --- | --- | --- |
| `translucentPanel` | `true` | The switch. `false` builds no material and leaves the popover opaque, which is AppKit's default. |
| `panelMaterial` | `.glass` | `.glass` is `NSGlassEffectView`. `.visualEffect` is the older `NSVisualEffectView`, still present on macOS 26, so the two can be compared without moving the floor. |
| `panelMaterialOpacity` | `1.0` | The material view's own alpha, clamped to 0...1. Lower values fade the rim and highlight too. |
| `panelCornerRadius` | `8.0` | AppKit's own default for glass. The popover's curve is AppKit's and is not readable from code. |

The shell owns the material. The page owns whether the panel is actually
translucent: `/widget` has to drop its own opaque `html, body` and `.widget`
backgrounds in oc-dash, and a panel that looks solid with a transparent page
means the CSS is still painting.

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

Both verbs are matched on a lowercased scheme and host, and only with an empty
or "/" path, so `oc-dash://quit/` and `OC-Dash://QUIT` are the same intent while
`oc-dash://quit/extra` and `oc-dash://start-server/extra` are not. Anything else
on the `oc-dash` scheme, any scheme outside `http`, `https` and `about`, and the
retired `ocdashbar` scheme, are cancelled and never navigated. One log line, on
stderr:

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
Sources/oc-dashbar/AppDelegate.swift  status item, popover, webview, offline page
Tests/oc-dashbar-tests/            config, discovery, material and ordering tests, incl. cross-repo contracts
Scripts/build-app.sh               the whole "build system"
```

## Rules

- The shell does not poll and does not start, stop or supervise oc-dash. The
  page owns its refresh. There is no launch agent, no login item, no retry loop.
  Re-reading the registry once per popover open is a lookup on a user action,
  not a timer. The start verb is one spawn on one explicit click and then the
  shell is done with it, which is a spawn and not supervision.
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
