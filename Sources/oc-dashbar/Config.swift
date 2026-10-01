import AppKit

/// The handful of values that define the shell. Everything here is constant or
/// read once per panel open, so the app's behaviour is easy to reason about and
/// easy to assert in tests.
enum Config {
    /// The page the panel loads, on the default port. Single source of truth for
    /// the fallback: the status item, the log lines, the offline page and the
    /// tests all read this or `resolvedWidgetURL(environment:)`.
    static let defaultWidgetURLString = "http://127.0.0.1:4021/widget"

    /// The path the panel loads, as a path and not as part of a URL string.
    /// Appending it to whatever base the registry names is why the registry
    /// stores a base URL and not this path: oc-dash does not know what the
    /// widget loads, and should not have to.
    static let widgetPath = "/widget"

    /// Environment override for `defaultWidgetURLString`, so the panel can be
    /// pointed at a throwaway server during testing without editing code, e.g.
    /// `OC_DASHBAR_URL=http://127.0.0.1:4022/widget`.
    static let urlEnvironmentKey = "OC_DASHBAR_URL"

    /// Where oc-dash writes the registry, and the two rules that decide it.
    ///
    /// The names and the fallback belong to the oc-dash repository and are
    /// repeated here so both sides can be diffed. They are here, with the other
    /// knobs, for the same reason as `quitScheme`: a value shared by two
    /// repositories belongs in one named place on each side.
    static let stateHomeEnvironmentKey = "XDG_STATE_HOME"
    static let homeStateDirectory = ".local/state"
    static let registryDirectoryName = "oc-dash"
    static let registryFileName = "service.json"

    /// Custom URL scheme the widget's quit control navigates to, and the host
    /// on it. The page that emits it lives in oc-dash, so these two strings are
    /// the entire contract between the repositories. They are here, with the
    /// other knobs, because reconciling the two sides should be a diff of two
    /// lines and not a search through both trees.
    ///
    /// The scheme is `oc-dash`, the name the page actually emits, and not a name
    /// this shell picked for itself: the shell once answered a different name
    /// the page never emitted, so the page's quit did nothing, and the page's
    /// name won. A URL scheme is data, and the only value of this constant
    /// that matters is the one the page produces.
    static let quitScheme = "oc-dash"
    static let quitHost = "quit"

    /// The one URL this shell answers: `<quitScheme>://<quitHost>`.
    static var quitURLString: String { "\(quitScheme)://\(quitHost)" }

    /// The second verb, on the same scheme. The widget's start control
    /// navigates to `oc-dash://start-server` and this shell spawns the
    /// dashboard once. Same scheme as `quitScheme` and deliberately not a
    /// second one: the page emits both, so there is one string to reconcile
    /// across the two repositories rather than two.
    static let startHost = "start-server"

    /// The URL the start control emits: `<quitScheme>://<startHost>`.
    static var startURLString: String { "\(quitScheme)://\(startHost)" }

    /// The third verb, on the same scheme, and the first one that carries data.
    /// The widget's "open in browser" control navigates to
    /// `oc-dash://open?url=<percent-encoded http or https URL>` and this shell
    /// hands that URL to the system instead of loading it.
    static let openHost = "open"

    /// The URL the open control emits with no target, which is what the offline
    /// page and any test that does not care about the target can write. Written
    /// from `quitScheme` on purpose, like the two above: it is the same scheme
    /// so the two repositories reconcile on one string.
    static var openURLString: String { "\(quitScheme)://\(openHost)" }

    /// The binaries the start verb looks for on the login shell's PATH, in
    /// this order, and stops at the first one found.
    ///
    /// An installed `oc-dash` wins over `npx` because `npx` is a resolver that
    /// may go to the network on the first run of a version it has never seen,
    /// and a global install does not. `npx` is the fallback for the machine
    /// where the package was never installed globally, which is the machine
    /// this feature mostly exists for.
    static let startBinaryNames = ["oc-dash", "npx"]

    /// The package `npx` has to run, as the published name.
    ///
    /// Not a bare `oc-dash`. `npm view oc-dash` answers `404 Not Found`, so a
    /// bare name is a name that does not exist on the registry and npx would
    /// fail on it on every machine. Checked against the live registry on
    /// 2026-09-30; the package is `@webfueler/oc-dash`, which is also the
    /// string oc-dash prints in every error message of its own.
    static let startPackageName = "@webfueler/oc-dash"

    /// The tag `npx` resolves the package by.
    ///
    /// Not decoration. Without a tag, npx parses the bare name as the range
    /// `*`, and a range matches a copy already in the current project instead
    /// of resolving the registry. A tag is resolved against the registry, so
    /// the button starts what is published now.
    static let startPackageTag = "latest"

    /// The package reference with its tag, written once: the page's command
    /// line and the npx spawn both read this string, so a tag added to one
    /// cannot be missing from the other.
    static var startPackageReference: String { "\(startPackageName)@\(startPackageTag)" }

    /// The subcommand, spelled the way oc-dash spells it in its help and in
    /// every error it prints.
    static let startSubcommand = ["server", "start"]

    /// How the login shell is invoked: `-l -i -c`.
    ///
    /// `-l` is the login part, and it is not enough on its own. zsh sources
    /// `.zshenv` and `.zprofile` for a login shell and `.zshrc` only for an
    /// interactive one, and nvm is installed by writing to `.zshrc`. Measured
    /// on this machine with the exact environment a Finder launch hands an app
    /// (`PATH=/usr/bin:/bin:/usr/sbin:/sbin`):
    ///
    ///     /bin/zsh -l -c     PATH has Homebrew, npx is NOT on it
    ///     /bin/zsh -l -i -c  PATH has Homebrew and nvm, npx IS on it
    ///
    /// So `-i` is the difference between a button that works and a button that
    /// reports oc-dash is not installed on the machine it is installed on. The
    /// cost is that an interactive shell can in principle want a terminal, so
    /// the child's stdin is `/dev/null` and the whole thing is on a deadline.
    static let loginShellFlags = ["-l", "-i", "-c"]

    /// The script the login shell runs, one labelled line per answer.
    ///
    /// Labelled rather than a bare `command -v oc-dash; command -v npx`,
    /// because a parser that has to rely on line order is a parser that one
    /// shell's habit can break. The trailing `DONE` means a shell that died
    /// halfway through is distinguishable from one that answered, which is
    /// the difference between a timeout message and a wrong PATH.
    static var loginShellScript: String {
        var lines = ["printf 'PATH=%s\\n' \"$PATH\""]
        for name in startBinaryNames {
            lines.append("printf '\(name)=%s\\n' \"$(command -v \(name) 2>/dev/null)\"")
        }
        lines.append("printf 'DONE\\n'")
        return lines.joined(separator: "\n")
    }

    /// How long the login shell gets to answer. A cold `.zshrc` can run `brew
    /// shellenv` and a version manager lookup before the first prompt, and 10
    /// seconds is past what that takes on a laptop that is not swapping. The
    /// failure mode past it is a startup file waiting for input, which is
    /// worth its own message.
    static let loginShellTimeout: TimeInterval = 10

    /// How long the spawned start is watched before this shell walks away.
    ///
    /// Long enough to see the failure, which is the point: npx resolving a
    /// package over the network, node booting, and oc-dash's own 10 second
    /// readiness deadline all have to fit in here, so 25 does. Watching is not
    /// supervising. Once this expires the process is forgotten, and a
    /// dashboard that is still running is a dashboard that started.
    static let startWatchTimeout: TimeInterval = 25

    /// How much of a child's own output is kept for a failure message. Enough
    /// for the few lines oc-dash prints when it refuses to start, which is
    /// the text that says why, and capped because the child is a server that
    /// logs every request for as long as it runs.
    static let startOutputLimit = 4096

    /// Schemes a navigation in this panel is allowed to load. Everything else
    /// is cancelled, including anything the page links to on another scheme.
    /// `about` is in here because WebKit uses it for its own documents and
    /// cancelling one would blank the panel instead of protecting it.
    static let navigableSchemes: Set<String> = ["http", "https", "about"]

    /// The query key carrying an open target. A named constant rather than a
    /// literal so the page and this shell reconcile on one line, same reason as
    /// the two hosts above.
    static let openTargetQueryKey = "url"

    /// Schemes a target may carry. `http` and `https` only, and nothing that can
    /// execute: `file:` reads the disk, `javascript:` runs in whatever handles it,
    /// `data:` is a document the shell never wrote, and any other custom scheme
    /// is a hand-off to a handler this shell does not know exists.
    static let openTargetSchemes: Set<String> = ["http", "https"]

    /// Hosts a target may name. Loopback only, and checked on the parsed
    /// `URL.host` rather than by substring, so `127.0.0.1.example.com` and
    /// `http://127.0.0.1@example.com` are both refused by the same comparison
    /// that admits `127.0.0.1`.
    ///
    /// The panel is served by oc-dash on loopback. A page that can name any host
    /// it likes can turn a menu bar click into a request to a server the Captain
    /// does not control, from a browser he is logged in to. Loopback-only means
    /// the worst a compromised widget page can do is open a tab pointing at a
    /// process on this machine.
    ///
    /// An exact match, so every other spelling of a loopback address is refused
    /// rather than recognised: `127.0.0.1.`, `0177.0.0.1`, `2130706433` and the
    /// expanded `[0:0:0:0:0:0:0:1]` all name loopback too, and all of them fail
    /// here. A miss costs a dead click; a hit on the wrong side costs the Captain
    /// his browser.
    static let openTargetHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

    /// Panel size in points. The /widget page in oc-dash is designed for
    /// 340x420. If that page ever needs a different number, its number wins
    /// and only this line changes.
    static let panelSize = NSSize(width: 340, height: 420)

    /// SF Symbol for the status item. Template rendering makes macOS invert it
    /// for light and dark menu bars without any work from us.
    static let statusItemSymbolName = "waveform.path.ecg"
    static let statusItemTooltip = "oc-dash"

    /// Lets AppKit remember the slot the item occupies in the strip, so it
    /// does not have to be dragged back after every relaunch.
    static let statusItemAutosaveName = "oc-dashbar"

    /// How wide the status item is allowed to be.
    ///
    /// Variable rather than square, and this is load-bearing for the menu bar
    /// figure. `NSStatusItem.length` is the width of the slot, and content that
    /// does not fit inside it is clipped: under `squareLength` the button is one
    /// icon wide, so a title of `$1,234,567.90` is cut off rather than shown
    /// beside the icon. `variableLength` is the documented answer for an item
    /// with both an image and a title, and it is also what the item wants with
    /// no title at all, since the image is what sets the width then.
    ///
    /// Assigned after `statusItemAutosaveName`, on purpose. The autosave restores
    /// the saved geometry of the slot, and a length written before it would be
    /// overwritten by the value from the last launch.
    static let statusItemLength = NSStatusItem.variableLength

    /// Flip to true to make the popover a non-activating panel, so clicking
    /// into the widget does not pull focus out of whatever is being typed in.
    /// Left false: the focus behaviour could not be verified headlessly.
    static let nonActivatingPanel = false

    /// The popover stops painting its own ground and a real system material
    /// paints behind the page, so the page's translucent CSS has something to
    /// composite over.
    ///
    /// This is the switch. Set it false and the material view is never built
    /// and the popover window keeps AppKit's opaque default, which is one edit
    /// away if the panel fights the webview.
    static let translucentPanel = true

    /// Which system material, and how it is dressed. Six variants, picked with
    /// `OC_DASHBAR_MATERIAL` at launch, so one build covers every material
    /// question instead of one build per question.
    ///
    /// The first case is what the shell did before this knob existed, and it
    /// stays the fallback for an unset or unrecognised value. That matters more
    /// than the other five: a typo in an environment variable has to leave the
    /// app exactly as it was, not crash it and not silently pick a look nobody
    /// asked for.
    ///
    /// The raw values are the strings the Captain types, so the log line and the
    /// six commands read the same. They live here rather than in
    /// `PanelMaterial.swift` because this file holds every knob and no other
    /// file may hold a literal.
    enum PanelMaterialVariant: String, CaseIterable {
        /// `NSGlassEffectView`, `style = .regular`, no tint. The control, and
        /// byte-for-byte what the shell built before this enum existed.
        case glassRegular = "glass-regular"

        /// The same glass with `tintColor` set to `.clear` rather than left nil.
        /// The header describes `tintColor` as "the color the glass effect view
        /// uses to tint the background and glass effect toward" and documents no
        /// default, so nil and clear are different requests and only a rendered
        /// panel says which one AppKit honours.
        case glassRegularNoTint = "glass-regular-notint"

        /// `NSGlassEffectView`, `style = .clear`. The header calls this "Clear
        /// glass effect style" and says nothing else about it.
        case glassClear = "glass-clear"

        /// `NSVisualEffectView`, `material = .popover`, `blendingMode =
        /// .behindWindow`, which the header documents as "Blend with the area
        /// behind the window (such as the Desktop or other windows)". This is
        /// the branch the code's own comment describes and the one that never
        /// shipped.
        case visualEffectBehindWindow = "visualEffect-behind"

        /// The same vibrancy with `blendingMode = .withinWindow`, "Blend with
        /// the area behind the view in the window". The property doc warns "Not
        /// all materials support both blending modes, so NSVisualEffectView may
        /// fall back to a more appropriate blending mode as needed", so this can
        /// render identically to the case above.
        case visualEffectWithinWindow = "visualEffect-within"

        /// No material view at all. The page sits directly in the container.
        ///
        /// This is the one worth running first. `panelMaterialOpacity` cannot
        /// stand in for it, because the webview is installed inside the material,
        /// so zeroing the material's `alphaValue` fades the page with it and both
        /// suspects vanish in the same screenshot. Dropping the view varies one
        /// thing, and what it answers is whether the webview composites an
        /// opaque background of its own. The window is still prepared for
        /// translucency in this variant, so the only difference from
        /// `glass-regular` is the missing material.
        case none

        /// Whether this variant puts a material view in the popover. `none` is
        /// the only one that does not.
        var buildsMaterial: Bool { self != .none }
    }

    /// Environment override for `panelMaterialVariant`. Unset means
    /// `glass-regular`, which is the behaviour that shipped.
    static let materialEnvironmentKey = "OC_DASHBAR_MATERIAL"

    /// The variant in force, from the process environment.
    ///
    /// Read through `resolvedMaterialVariant(environment:)` so a test can hold a
    /// dictionary instead of a process, the same trick
    /// `resolvedWidgetURL(environment:)` uses.
    static let panelMaterialVariant = resolvedMaterialVariant(
        environment: ProcessInfo.processInfo.environment
    )

    /// Pure, so every one of the six values and both failure modes are testable
    /// without setting anything in the ambient environment. An unrecognised
    /// value falls back to `glass-regular` rather than trapping, and so does an
    /// unset one: the app is not allowed to fail to start over a typo.
    static func resolvedMaterialVariant(
        environment: [String: String]
    ) -> PanelMaterialVariant {
        guard let raw = environment[materialEnvironmentKey],
            let variant = PanelMaterialVariant(rawValue: raw)
        else { return .glassRegular }
        return variant
    }

    /// Whether the popover builds a material view for this variant. `.none`
    /// does not, and the page goes straight into the container.
    static var buildsPanelMaterial: Bool {
        translucentPanel && panelMaterialVariant.buildsMaterial
    }

    /// The KVC key on `WKWebView` that stops WebKit painting its own background
    /// behind the page. This is what makes the panel transparent: the page's
    /// transparent pixels composite with the material and the desktop instead of
    /// landing on a slab WebKit painted for itself.
    ///
    /// It is private AppKit, declared in no header on this SDK, and no public API
    /// does this job. `AppDelegate.applyWebviewCompositing(to:)` is where the
    /// write is, and the evidence for each of those claims is written down there.
    ///
    /// Unconditional, with no environment variable and no variant. Whether the
    /// panel ends up transparent is a fact about the SDK and the page's CSS, not
    /// a per-run preference, so a switch for it would be a switch whose every
    /// value is the same.
    static let webviewDrawsBackgroundKey = "drawsBackground"

    /// The Objective-C setter behind `webviewDrawsBackgroundKey`, underscored,
    /// and the probe for whether the key is still on the runtime at all.
    /// `setDrawsBackground:` is not implemented, so `responds(to:)` has to be
    /// asked about this name and not the obvious one.
    static let webviewDrawsBackgroundSelector = "_setDrawsBackground:"

    /// How strongly the material is painted, 0...1. `1.0` leaves the system
    /// material exactly as AppKit draws it. Lower values fade the material, its
    /// rim and its highlight with it, because the knob is the view's own
    /// `alphaValue`; the panel's real translucency is the page's CSS, not this
    /// number.
    static let panelMaterialOpacity: CGFloat = 1.0

    /// Corner radius of the material, in points. `NSGlassEffectView` defaults to
    /// 8.0, which is what this is, and AppKit's own popover radius is not
    /// readable from code. Whether the two curves agree is a click test, and
    /// this is the one edit if they do not.
    static let panelCornerRadius: CGFloat = 8.0

    /// How far the popover window's own bounds sit outside the content rect, per
    /// edge. This is the chevron band: `popover.contentSize` does not account for
    /// the arrow, so the window is the content size grown by twice this on each
    /// axis and the content view is centred inside it.
    ///
    /// **Measured, not documented.** It is in no header on this SDK. It read
    /// 13.0 at content sizes 340x420, 500x600 and 200x150, and the flatness
    /// across those three is why it is a constant and not a formula. Note that
    /// it is 13 per side and not 26: the growth is 26 in total, 13 of it on each
    /// edge, and doubling it is the natural mistake.
    ///
    /// The material view reads this at run time rather than trusting it, by
    /// measuring the gap between the popover window's frame view and the content
    /// view's rect, and this is only what it starts from and what it falls back
    /// to before a window exists. So if a future macOS moves the band, the
    /// layout follows it; if the read ever fails, this number is what the panel
    /// is built with and the mismatch is a shade seam, not a wrong panel.
    static let popoverChevronInset: CGFloat = 13.0

    /// The opacity actually handed to AppKit, as a pure function so the range is
    /// covered by a test. A non-finite value falls back to the untouched
    /// material rather than propagating a NaN into a view property.
    static func clampedOpacity(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1.0 }
        return Swift.min(Swift.max(value, 0.0), 1.0)
    }

    /// `panelMaterialOpacity` after `clampedOpacity(_:)`.
    static var panelMaterialAlpha: CGFloat { clampedOpacity(panelMaterialOpacity) }

    /// Test hook only, off by default: opens the panel at launch so the webview
    /// can be exercised without a human clicking the status item. Set
    /// `OC_DASHBAR_OPEN_ON_LAUNCH=1` alongside the URL override.
    static let openPanelEnvironmentKey = "OC_DASHBAR_OPEN_ON_LAUNCH"

    static var opensPanelOnLaunch: Bool {
        let raw = ProcessInfo.processInfo.environment[openPanelEnvironmentKey] ?? ""
        return ["1", "true", "yes"].contains(raw.lowercased())
    }

    /// Which of the three sources produced the URL, for the log. The raw values
    /// are the words the log prints rather than enum case names, so the line is
    /// readable without this file open.
    enum WidgetURLSource: Equatable {
        case environmentOverride
        case registry
        case builtInDefault
        /// Nothing usable was found anywhere, so the panel shows the offline
        /// page. Reachable only through a set-but-unusable `OC_DASHBAR_URL`.
        case unusable
    }

    /// What the registry did on the way to a URL. Every case but `won` is a
    /// reason to log, because a registry that is silently ignored is exactly
    /// the state that looks like "the widget is broken" from the outside.
    enum RegistryOutcome: Equatable {
        /// Trusted, because its pid is alive.
        case won(port: Int, pid: Int32)
        /// No file. The normal state for anyone who has not run
        /// `oc-dash server start`.
        case absent
        /// A file naming a process that is not running.
        case deadProcess(pid: Int32)
        /// A file that is there and is not usable, with the reason in words.
        case rejected(reason: String)
    }

    /// The whole resolution in one value, so the log can say where the URL came
    /// from and the delegate can decide whether to load, and so a test can
    /// assert all three without re-deriving them.
    struct WidgetURLResolution: Equatable {
        /// nil only when nothing usable was found. The delegate turns that into
        /// the offline page rather than a silent blank panel.
        let url: URL?
        let source: WidgetURLSource
        /// What the registry file did. nil when it was never read, which is
        /// what the environment override means: a person pointed this shell
        /// somewhere on purpose, and a file on disk does not get to overrule
        /// that.
        let registry: RegistryOutcome?
    }

    /// The precedence, highest first, walked from the top on every open of the
    /// panel:
    ///
    /// 1. `OC_DASHBAR_URL`, the explicit override that has always been here.
    /// 2. The registry file, if it is present, decodes, and its `pid` is a live
    ///    process.
    /// 3. `defaultWidgetURLString`, port 4021.
    ///
    /// Pure. `registryText` is the file's text or nil when there is no file, and
    /// `isProcessAlive` is injected so that both a live pid and a dead one are
    /// reachable from a test without starting or stopping anything. The default
    /// argument is the real check, because the one production caller wants the
    /// real check and the tests want the argument.
    ///
    /// The registry is not consulted at all once the override is present, so
    /// the common case costs one dictionary lookup.
    static func resolveWidgetURL(
        environment: [String: String],
        registryText: String? = nil,
        isProcessAlive: (Int32) -> Bool = ServiceRegistry.isProcessAlive
    ) -> WidgetURLResolution {
        if let raw = environment[urlEnvironmentKey] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
                // A set-but-unusable override stops here on purpose. Falling
                // through to the registry or the default would turn a typo into
                // a panel that looks like it worked, which is the harder bug to
                // find.
                return WidgetURLResolution(url: nil, source: .unusable, registry: nil)
            }
            return WidgetURLResolution(url: url, source: .environmentOverride, registry: nil)
        }

        let fallback = WidgetURLResolution(
            url: URL(string: defaultWidgetURLString),
            source: .builtInDefault,
            registry: registryText == nil ? .absent : nil
        )

        guard let registryText else { return fallback }
        switch ServiceRegistry.decode(registryText) {
        case .rejected(let reason):
            return WidgetURLResolution(
                url: fallback.url,
                source: .builtInDefault,
                registry: .rejected(reason: reason)
            )
        case .entry(let entry):
            guard isProcessAlive(entry.pid) else {
                // Not trusted, not deleted. oc-dash wrote this file and oc-dash
                // removes it, and a stale file naming a dead pid is a thing the
                // log should be able to tell someone about.
                return WidgetURLResolution(
                    url: fallback.url,
                    source: .builtInDefault,
                    registry: .deadProcess(pid: entry.pid)
                )
            }
            guard let url = widgetURL(base: entry.baseURL) else {
                return WidgetURLResolution(
                    url: fallback.url,
                    source: .builtInDefault,
                    registry: .rejected(reason: "\"url\" (\(entry.baseURL)) cannot carry \(widgetPath)")
                )
            }
            return WidgetURLResolution(url: url, source: .registry, registry: .won(port: entry.port, pid: entry.pid))
        }
    }

    /// The URL shape of `resolveWidgetURL`, for callers that only want the URL.
    /// It takes no registry text by default, so callers that pass an
    /// environment alone get exactly today's behaviour: no registry text, so
    /// no registry.
    static func resolvedWidgetURL(
        environment: [String: String],
        registryText: String? = nil,
        isProcessAlive: (Int32) -> Bool = ServiceRegistry.isProcessAlive
    ) -> URL? {
        resolveWidgetURL(environment: environment, registryText: registryText, isProcessAlive: isProcessAlive).url
    }

    /// What an open of the panel should do with the webview.
    enum WidgetLoadDecision: Equatable {
        /// Point the webview at this URL. The webview and the popover are
        /// reused and only the document inside them is replaced, which is what
        /// `WKWebView.load(_:)` documents and what makes a moving dashboard a
        /// load rather than a teardown.
        case load(URL)
        /// Already showing this URL. Reloading would discard page state, and
        /// the page owns its own refresh.
        case keepShowing(URL)
        /// Nothing resolved, so the shell's own offline page goes in.
        case showOfflinePage
    }

    /// Pure. `showing` is the URL the webview was last pointed at, tracked by
    /// the delegate rather than read back from `webView.url`, because that is
    /// nil whenever the offline page is up and every open would then look like
    /// the first one.
    static func decideLoad(_ resolution: WidgetURLResolution, showing: URL?) -> WidgetLoadDecision {
        guard let url = resolution.url else { return .showOfflinePage }
        guard showing != url else { return .keepShowing(url) }
        return .load(url)
    }

    /// The registry's base URL plus the widget path. Built from URL components
    /// so a base written with a trailing slash, a path, a query or a fragment
    /// still yields the same widget URL instead of nesting them.
    private static func widgetURL(base: URL) -> URL? {
        guard
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        components.path = widgetPath
        components.query = nil
        components.fragment = nil
        return components.url
    }

    // MARK: - Today's money in the menu bar

    /// How often the shell asks the server what today cost. 30 seconds, which is
    /// the interval the /widget page refreshes on, so the menu bar figure and
    /// the panel move on the same clock rather than drifting a minute apart.
    ///
    /// A poll and not a push, because the shell has no channel to be pushed on:
    /// it is not a websocket client and oc-dash is not offering to become one.
    static let moneyPollInterval: TimeInterval = 30

    /// How long one request may take before URLSession gives up on it.
    ///
    /// This is what makes the no-overlap rule recover rather than stick. The
    /// gate alone means a hung request parks every later tick, so a figure that
    /// froze at launch would never come back on its own. Bounded below the poll
    /// interval on purpose: at most one attempt in flight, and the next tick is
    /// still a fresh attempt rather than the tail of the last one.
    static let moneyRequestTimeout: TimeInterval = 10

    /// The summary route, on whichever server the panel is reading.
    ///
    /// A path and not part of a URL string, for the same reason `widgetPath` is:
    /// the server is named by the registry or by the override, and only the path
    /// is the shell's business.
    static let summaryPath = "/api/summary"

    /// The two query keys and their values, one constant each.
    ///
    /// `range=today` is the window. `context=none` is required rather than
    /// cosmetic: on the server it skips the second stats call that only feeds
    /// the chart's muted context days, and this shell renders no chart.
    ///
    /// `project` is deliberately not sent. The handler reads three parameters and
    /// an absent `project` is the documented way to ask for no per-project work.
    static let summaryRangeKey = "range"
    static let summaryRangeToday = "today"
    static let summaryContextKey = "context"
    static let summaryContextNone = "none"

    /// The title that means "no figure".
    ///
    /// Empty, and empty for a reason: the Captain's rule is hide, and a dash, a
    /// zero, a question mark or the last known value are all a figure of some
    /// kind. An empty title is the one thing in a menu bar that is unambiguously
    /// nothing.
    static let emptyMoneyTitle = ""

    /// Schemes the money request may speak.
    ///
    /// Its own set rather than a reuse of `navigableSchemes` or
    /// `openTargetSchemes`, because both of those answer a different question.
    /// One is what a page in the panel may navigate to, the other is what this
    /// shell may hand to the Captain's real browser. This one is what a background
    /// request of our own may be sent to, and `about` is not on it: there is no
    /// server behind `about`, so a widget URL carrying it is a mistake rather
    /// than a host.
    static let moneyRequestSchemes: Set<String> = ["http", "https"]

    /// The query string the money request sends, written from the constants
    /// above rather than as a literal, so a value that moved is visible in the
    /// URL instead of hiding in a string.
    static var summaryQuery: String {
        "\(summaryRangeKey)=\(summaryRangeToday)&\(summaryContextKey)=\(summaryContextNone)"
    }

    /// The summary URL for the server the panel is reading, derived from the URL
    /// the panel itself resolved rather than from a second port literal.
    ///
    /// This is the load-bearing derivation. The panel's URL is decided by
    /// `resolveWidgetURL` with its three-step precedence, and the figure has to
    /// ask the same server the panel just showed, or a menu bar reading $7.56
    /// beside a panel reading $0.00 is indistinguishable from a bug. So the
    /// widget URL arrives as a parameter, its path is replaced with
    /// `summaryPath`, and its query and fragment are dropped. A resolved URL
    /// carrying a path, a query or a fragment therefore still yields the same
    /// summary URL rather than nesting them, which is what `widgetURL(base:)`
    /// does for the other direction.
    ///
    /// nil means there is no server to ask, and the caller hides. That is only
    /// reachable through a set-but-unusable `OC_DASHBAR_URL`, the same state in
    /// which the panel shows its offline page, and the two hiding together is
    /// the correct answer.
    ///
    /// A non-`http`/`https` scheme is refused rather than requested. `file:`
    /// would turn a background figure into a disk read, and this shell's own
    /// `oc-dash:` verbs are not a server at all. A host is not checked: if the
    /// override points the panel at a machine that is not this one, the figure
    /// follows it there rather than quietly reporting a different server's
    /// spending, which is the disagreement the derivation exists to prevent.
    static func summaryURL(widgetBase widget: URL?) -> URL? {
        guard let widget,
            var components = URLComponents(url: widget, resolvingAgainstBaseURL: false),
            let scheme = components.scheme,
            moneyRequestSchemes.contains(scheme.lowercased())
        else { return nil }
        components.path = summaryPath
        components.query = summaryQuery
        components.fragment = nil
        return components.url
    }
}
