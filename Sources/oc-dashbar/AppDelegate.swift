import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var webView: WKWebView?
    /// How many times `show()` has been called this launch. In the log, because
    /// "the first open" and "the second open" is the distinction that decides
    /// whether the preparation ran on the open a screenshot was taken from.
    private var showCount = 0
    /// How many quit URLs this launch has already answered. Held so the
    /// decision can count them and so the log can say which request this is.
    private var quitRequestCount = 0

    /// Start URLs answered so far, counted the same way and for the same
    /// reason. The shell does not deduplicate: one click is one spawn, and a
    /// second click is a second explicit ask. The page owns the arm that makes
    /// a double click a confirmation rather than two starts.
    private var startRequestCount = 0

    /// Quit URLs answered so far. Exposed for the test that starts at zero,
    /// the same way `popoverWindowPrepared` is.
    var quitRequestsAnswered: Int { quitRequestCount }
    /// Start URLs answered so far, exposed for the same reason.
    var startRequestsAnswered: Int { startRequestCount }

    /// Terminating the app, behind a closure so a test can drive the whole
    /// decision switch and watch the quit arm happen without ending the test
    /// run. Production behaviour is exactly what it was: `NSApp.terminate`,
    /// deferred, called from the same place.
    var termination: () -> Void = { NSApp.terminate(nil) }

    /// What a start does, behind a closure for the same reason. Production
    /// behaviour is the queue hop and one `StartServer.start` per call.
    var startAction: (Int) -> Void = { request in
        DispatchQueue.global(qos: .userInitiated).async { StartServer.start(request: request) }
    }

    /// What an open does, behind a closure for the same reason as the two above:
    /// production behaviour is the call, and a test can substitute a recorder so
    /// the whole switch runs without a browser appearing on screen.
    var openAction: (URL) -> Void = { url in NSWorkspace.shared.open(url) }

    /// The popover window the preparation has already run on. Weak because the
    /// popover owns the panel, and identity rather than a Bool because AppKit
    /// does not promise to reuse it. See `PopoverWindowPreparation`.
    private weak var preparedWindow: NSWindow?

    /// Whether the current popover window has been prepared. In the log because
    /// `window.isOpaque` cannot answer the question on its own: on macOS 26 a
    /// popover panel is already non-opaque before this shell touches it, so
    /// `prepared=` is the only field here that says whether our code ran.
    var popoverWindowPrepared: Bool { preparedWindow != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeOwnActivation()
        installStatusItem()
        installPopover()
        // Logged, not resolved. The resolution happens per open, so whatever is
        // printed here is only what this launch looked like, and the per-open
        // line is the one that says what the panel is actually showing. Reading
        // the registry once here is still worth it: it names the file the shell
        // will consult on every open, which is the question a stale registry
        // raises.
        let atLaunch = Config.resolveWidgetURL(
            environment: ProcessInfo.processInfo.environment,
            registryText: ServiceRegistry.currentText()
        )
        Log.info(
            "launched: panel \(Int(Config.panelSize.width))x\(Int(Config.panelSize.height))pt, "
                + "nonActivatingPanel=\(Config.nonActivatingPanel), "
                + "material=\(Config.translucentPanel ? Config.panelMaterial.rawValue : "none"), "
                + "materialAlpha=\(Config.panelMaterialAlpha), "
                + "url=\(atLaunch.url?.absoluteString ?? "unresolved"), "
                + "registry=\(ServiceRegistry.currentPath())"
        )
        if Config.opensPanelOnLaunch {
            // Deferred so the status item exists before the panel anchors to it.
            DispatchQueue.main.async { [weak self] in self?.presentPopover() }
        }
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Config.statusItemAutosaveName
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: Config.statusItemSymbolName,
                accessibilityDescription: Config.statusItemTooltip
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = Config.statusItemTooltip
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        else {
            Log.info("warning: status item has no button, the popover has nothing to anchor to")
        }
        // `behavior` is deliberately left at its default so the item cannot be
        // dragged out of the menu bar.
        statusItem = item
    }

    // MARK: - Popover

    private func installPopover() {
        let container = NSView(frame: NSRect(origin: .zero, size: Config.panelSize))
        container.autoresizingMask = [.width, .height]

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: container.bounds, configuration: configuration)
        view.autoresizingMask = [.width, .height]
        view.navigationDelegate = self
        // Documented API (macOS 12+): the colour WebKit paints behind the page.
        // The undocumented `drawsBackground` KVC key on WKWebViewConfiguration
        // is deliberately not used.
        view.underPageBackgroundColor = .clear

        // The material is the bottom of the stack and the page is hosted inside
        // it, so the page's transparent pixels composite over a real system
        // material. With `Config.translucentPanel` false none of this is built
        // and the page goes straight into the container, which is AppKit's
        // opaque popover default.
        if Config.translucentPanel {
            let material = PanelMaterialView(
                kind: Config.panelMaterial,
                frame: container.bounds,
                cornerRadius: Config.panelCornerRadius
            )
            material.autoresizingMask = [.width, .height]
            material.alphaValue = Config.panelMaterialAlpha
            material.install(view)
            container.addSubview(material)
        }
        else {
            container.addSubview(view)
        }
        webView = view

        let popover = NSPopover()
        popover.behavior = .transient
        let host = NSViewController()
        host.view = container
        popover.contentViewController = host
        // Set after contentViewController, because assigning that sizes the
        // popover to the hosted view and would otherwise win the race.
        popover.contentSize = Config.panelSize
        self.popover = popover
    }

    /// Prepares the popover's window and returns whether it did anything.
    ///
    /// Called after `show()` and never before it. NSPopover has no public
    /// `window` and builds its panel inside `show()`, so a call made ahead of
    /// the show finds nothing on the first open, and the panel came up
    /// unprepared on exactly the first open until this order was fixed.
    ///
    /// After the show there is no window to race. It exists synchronously by
    /// the time `show()` returns, and no pixels are drawn in between, because
    /// AppKit does not composite until this run loop pass ends.
    @discardableResult
    private func preparePopoverWindow() -> Bool {
        let result = PopoverWindowPreparation.prepare(
            window: popover?.contentViewController?.view.window,
            alreadyPrepared: preparedWindow
        ) { window in
            if Config.nonActivatingPanel, !window.styleMask.contains(.nonactivatingPanel) {
                window.styleMask.insert(.nonactivatingPanel)
                Log.info("applied .nonactivatingPanel to the popover window")
            }
            guard Config.translucentPanel else { return }
            // The window stops painting its own ground. The reasons live on
            // `prepareForTranslucentPanel()`, which a test can call on a real window.
            window.prepareForTranslucentPanel()
        }
        preparedWindow = result.prepared
        return result.ran
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
            Log.info("popover closed by status item click")
            return
        }
        presentPopover()
    }

    private func presentPopover() {
        guard let popover, let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Below the show, where the window exists. Above it, the first open
        // found nothing to prepare.
        preparePopoverWindow()
        showCount += 1
        loadWidgetForThisOpen()
        // The material and the window state are in the log because they are the
        // two things a screenshot of a broken panel cannot distinguish. Whether
        // the material looks right is not in here because I cannot see it.
        //
        // `showCount`, `shown` and `prepared` are there so that one run settles
        // it. `prepared` is the field that says our code ran.
        // `windowOpaque` is kept because a change there is still worth seeing,
        // but it cannot carry the answer: a macOS 26 popover panel reports
        // `isOpaque == false` before this shell has touched it.
        // `shown` is there so a failed show cannot be misread as a skipped
        // preparation, which is the one way `prepared=false` could be innocent.
        Log.info(
            "popover show #\(showCount), size \(Int(popover.contentSize.width))x\(Int(popover.contentSize.height))pt, "
                + "material=\(Config.translucentPanel ? Config.panelMaterial.rawValue : "none"), "
                + "shown=\(popover.isShown), prepared=\(popoverWindowPrepared), "
                + "windowOpaque=\(String(describing: popover.contentViewController?.view.window?.isOpaque)), "
                + "app is active: \(NSApp.isActive)"
        )
    }

    // MARK: - Loading

    /// The URL the webview was last pointed at. Tracked here rather than read
    /// back from `webView.url`, which is nil while the offline page is up and
    /// would make every open after a failure look like the first one.
    private var loadedWidgetURL: URL?

    /// Resolves the widget URL again on this open and loads only if it is not
    /// the one already in the webview.
    ///
    /// Re-resolving per open rather than once at launch is deliberate. A URL
    /// resolved at launch is stale for the life of the process: the dashboard
    /// can be started, stopped, or moved to another port
    /// while this widget sits in the menu bar, and the user has no reason to
    /// relaunch a menu bar app in order to click it again. Re-reading costs one
    /// 90-byte file read per user action.
    ///
    /// Nothing here is a retry loop. A reload happens when the resolved URL
    /// changed, which is the dashboard having moved, not the shell hoping the
    /// dashboard came back. The page still owns its own refresh, and a panel
    /// showing the offline page is retried by clicking "Try again".
    private func loadWidgetForThisOpen() {
        let resolution = Config.resolveWidgetURL(
            environment: ProcessInfo.processInfo.environment,
            registryText: ServiceRegistry.currentText()
        )
        let registryPath = ServiceRegistry.currentPath()
        switch Config.decideLoad(resolution, showing: loadedWidgetURL) {
        case .load(let url):
            loadedWidgetURL = url
            Log.info(registryLine(resolution, registryPath: registryPath) + ", loading")
            webView?.load(URLRequest(url: url))
        case .keepShowing(let url):
            Log.info("still on \(url.absoluteString), not reloading")
        case .showOfflinePage:
            loadedWidgetURL = nil
            // Only reachable through a blank or whitespace-only
            // `OC_DASHBAR_URL`. The registry and the default both always resolve
            // to something, so this line naming the override is not a guess.
            Log.info(
                "\(Config.urlEnvironmentKey) is set but blank, nothing to resolve, showing the offline page"
            )
            webView?.loadHTMLString(offlinePage(for: nil), baseURL: nil)
        }
    }

    /// One line per load, saying which of the three sources won and, when the
    /// registry lost, why.
    ///
    /// The "why" is the load-bearing part. A registry naming a process that has
    /// gone looks exactly like a broken widget from the outside, and "used the
    /// default instead" is not an explanation.
    ///
    /// Only called when there is a URL to load, so `url` is never nil here and
    /// the `.unusable` source cannot reach this switch.
    private func registryLine(_ resolution: Config.WidgetURLResolution, registryPath: String) -> String {
        let url = resolution.url?.absoluteString ?? "unresolved"
        switch resolution.registry {
        case .won(let port, let pid):
            return "widget \(url) from the registry \(registryPath) (port \(port), pid \(pid))"
        case .deadProcess(let pid):
            return "registry \(registryPath) names dead pid \(pid), not using it, falling back to \(url)"
        case .rejected(let reason):
            return "registry \(registryPath) is unusable (\(reason)), not using it, falling back to \(url)"
        case .absent:
            return "widget \(url) from the built-in default, no registry file at \(registryPath)"
        case nil:
            return "widget \(url) from \(Config.urlEnvironmentKey), registry not read"
        }
    }

    // MARK: - Quit, start and open

    /// The other end of the widget's controls. The page navigates to
    /// `Config.quitURLString`, `Config.startURLString` or
    /// `Config.openURLString` with a target in its query; each decision is
    /// cancelled so WebKit never tries to load a scheme no handler owns, and
    /// the action happens afterwards.
    ///
    /// Both actions are deferred off this callback by one turn of the main
    /// queue. WebKit is mid-callback when the handler returns, and tearing the
    /// process down underneath it is how a shell ends up as a crash report
    /// instead of a quit. The decision handler has already said `.cancel` by
    /// then, so nothing is half-loaded.
    ///
    /// What is deliberately not here: any stop, kill or signal of oc-dash.
    /// This shell has never supervised the
    /// dashboard. A quit terminates this process and leaves oc-dash on 4021
    /// exactly as it found it, and a start spawns one process and never looks
    /// at it again. `oc-dash server stop` stays the only thing that stops it.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let decision = PanelNavigation.decide(
            for: navigationAction.request.url,
            quitRequestsHandled: quitRequestCount,
            startRequestsHandled: startRequestCount
        )
        switch decision {
        case .allow:
            decisionHandler(.allow)
        case .cancelUnknownHost(let url):
            // Logged rather than silent. A page emitting this has a bug or an
            // out-of-date shell half, and either way it is worth seeing.
            Log.info(
                "cancelled \(url): our scheme, but not \(Config.quitHost), \(Config.startHost) or \(Config.openHost)"
            )
            decisionHandler(.cancel)
        case .cancelForeignScheme(let scheme):
            Log.info("cancelled \(scheme): a scheme this panel does not load")
            decisionHandler(.cancel)
        case .quit(let request):
            decisionHandler(.cancel)
            act(on: .quit(request: request))
        case .startServer(let request):
            decisionHandler(.cancel)
            act(on: .startServer(request: request))
        case .openInBrowser(let url):
            decisionHandler(.cancel)
            act(on: .openInBrowser(url))
        }
    }

    /// What the shell does about a decision, with WebKit out of the way.
    ///
    /// Split out of the delegate so a test can drive the whole switch with the
    /// two values a real navigation would have carried. `WKNavigationAction`
    /// cannot be built, which is the whole reason `PanelNavigation` is a pure
    /// function of a URL.
    func act(on decision: PanelNavigation.Decision) {
        switch decision {
        case .allow, .cancelUnknownHost, .cancelForeignScheme:
            break
        case .quit(let request):
            quitRequestCount = request
            Log.info("quit intent received, request #\(request), terminating oc-dashbar")
            DispatchQueue.main.async { [termination] in termination() }
        case .startServer(let request):
            startRequestCount = request
            Log.info(
                "start intent received, request #\(request), from \(Config.startURLString),"
                    + " one spawn and no supervision after it"
            )
            // Off the main thread and off WebKit's callback: this spawns a
            // login shell and then a server, and waits on the first. The panel
            // stays up and the page owns its own feedback, which is why the
            // page half has a sent state at all.
            startAction(request)
        case .openInBrowser(let url):
            Log.info("open intent received: \(url.absoluteString)")
            openAction(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The webview's own URL, not the one we asked for. After a move between
        // dashboards this is where a redirect shows up.
        Log.info("loaded \(webView.url?.absoluteString ?? "unknown url")")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }

    private func handleNavigationFailure(_ error: Error) {
        let failure = error as NSError
        // -999 is NSURLErrorCancelled, which WebKit reports for the load that a
        // newer load supersedes. It is not an outage and must stay quiet.
        guard failure.domain == NSURLErrorDomain, failure.code != NSURLErrorCancelled else { return }
        Log.info("navigation failed (\(failure.code)): \(failure.localizedDescription), showing the offline page")
        // The retry link points at the URL that just failed, not at a freshly
        // resolved one. Those can differ after a move between dashboards, and
        // the page belongs to whichever attempt actually failed.
        webView?.loadHTMLString(offlinePage(for: loadedWidgetURL), baseURL: nil)
    }

    /// A self-contained page, so a dashboard that is down still explains itself.
    /// The retry link is a plain anchor to the widget URL, so retrying is a real
    /// navigation made by the user, not a shell side retry loop. The start
    /// control is the same shape: a navigation to `Config.startURLString` that
    /// the delegate above intercepts. `OfflinePage` owns the document so the
    /// copy, the command line and the bounded wait have tests of their own.
    private func offlinePage(for url: URL?) -> String {
        OfflinePage.html(tried: url, registryPath: ServiceRegistry.currentPath())
    }

    // MARK: - Focus measurement

    /// Whether the app steals focus cannot be driven headlessly, so instead of
    /// guessing we log every time oc-dashbar itself becomes the active
    /// application.
    private func observeOwnActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app == NSRunningApplication.current
            else { return }
            Log.info("oc-dashbar became the active application, focus left the previous app")
        }
    }
}
