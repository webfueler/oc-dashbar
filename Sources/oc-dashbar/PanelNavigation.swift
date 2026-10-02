import Foundation

/// What one navigation means to this shell, decided without touching anything.
///
/// The page cannot terminate the app, cannot start a process and cannot open a
/// browser window, so the widget's controls emit their intent as navigations to
/// a custom scheme and this is the other end of that handoff. Three verbs and a
/// list of things to refuse, and the rule behind all three is the same narrow
/// one: this shell acts on itself and on nothing else. oc-dash is not
/// supervised by this shell and never was, so a quit here terminates this
/// process and leaves the dashboard on 4021 exactly as it found it, and a start
/// here spawns one process and never looks at it again.
///
/// The open verb is the first one that takes a value out of the page and acts
/// on it, which is why its target is validated rather than matched. See
/// `openTarget(in:)`.
///
/// The decision is a pure function of `(url, quitRequestsHandled,
/// startRequestsHandled)` because that is the only shape a test can drive from
/// a session with no window server, where no WKWebView navigates. `Config` is
/// read inside rather than passed in because every value in it is a
/// compile-time constant, so nothing here is hidden state; the alternative is
/// five arguments at the one call site.
///
/// Renamed from `QuitNavigation` when the second verb arrived: the old name
/// described one of the two answers and would have been a lie the next time
/// someone looked for the other one.
enum PanelNavigation {
    /// The answers a navigation can get. Only one of them navigates.
    enum Decision: Equatable {
        /// The page asked the app to quit. Cancel the load, then terminate.
        ///
        /// `request` counts quit URLs answered so far plus this one, so the
        /// first is 1. The count is carried in the value rather than left to the
        /// caller's log because whether a quit is the first or the second is
        /// part of the answer, not decoration.
        case quit(request: Int)

        /// The page asked the app to start the dashboard. Cancel the load, then
        /// spawn once. Counted the same way as a quit, and for the same reason:
        /// a second click is a second request and the log should be able to say
        /// which one this was. The shell does not deduplicate them. The page
        /// owns the arm that makes a double click a confirmation rather than
        /// two starts, and a second click is a second explicit ask.
        case startServer(request: Int)

        /// The page asked the app to open a URL in the user's browser. Cancel
        /// the load, then hand the URL to the system.
        ///
        /// Carries the validated `URL` rather than a count. Unlike the other two
        /// verbs nothing here is deduplicated, and the log line that names the
        /// URL is worth more than an ordinal that invites somebody to assume the
        /// shell is counting opens for a reason.
        case openInBrowser(URL)

        /// The page reported that the dashboard is no longer answering. Cancel
        /// the load, then show this shell's own help page.
        ///
        /// Not counted, unlike quit and start, and that is the point rather than
        /// an omission: those two are requests a person made twice, and which
        /// one is part of the answer. This one is a report about the state of
        /// the world, so a second one carries no more information than the first
        /// and an ordinal would only invite somebody to look for deduplication
        /// that is not wanted.
        case showOfflinePage

        /// Our own scheme, but not a verb we answer, so it is a URL the page
        /// should not have produced. Cancelled. Never navigated.
        case cancelUnknownHost(String)

        /// A scheme this panel has no business loading, such as `mailto:` or
        /// `javascript:`. Cancelled. Never navigated.
        case cancelForeignScheme(String)

        /// An ordinary page load: the widget itself, the offline page's retry
        /// link, or WebKit's own `about:blank`. Allowed.
        case allow
    }

    /// Decides one navigation.
    ///
    /// `url` is nil when WebKit reports a navigation with no URL, which happens
    /// for internal documents. Nil is allowed rather than cancelled: there is no
    /// scheme to be unrecognised, and cancelling WebKit's own document would
    /// blank the panel rather than protect it.
    static func decide(for url: URL?, quitRequestsHandled: Int, startRequestsHandled: Int = 0) -> Decision {
        guard let url, let scheme = url.scheme?.lowercased(), !scheme.isEmpty else {
            return .allow
        }
        if scheme == Config.quitScheme {
            if isVerbURL(url, host: Config.quitHost) {
                return .quit(request: quitRequestsHandled + 1)
            }
            if isVerbURL(url, host: Config.startHost) {
                return .startServer(request: startRequestsHandled + 1)
            }
            if isVerbURL(url, host: Config.openHost) {
                return openTarget(in: url).map(Decision.openInBrowser) ?? .cancelUnknownHost(url.absoluteString)
            }
            if isVerbURL(url, host: Config.offlineHost) {
                return .showOfflinePage
            }
            return .cancelUnknownHost(url.absoluteString)
        }
        if Config.navigableSchemes.contains(scheme) {
            return .allow
        }
        return .cancelForeignScheme(scheme)
    }

    /// Whether a URL on our scheme is one of our verbs, and which one.
    ///
    /// Matched on host and path rather than on `absoluteString`, because
    /// `oc-dash://quit` and `oc-dash://quit/` are the same intent and are not
    /// equal as `URL` values, and a page that appends a slash should not
    /// silently stop working. Scheme and host are compared lowercased because
    /// `URL` keeps the case the page wrote, and both are case-insensitive per
    /// RFC 3986.
    ///
    /// The path is constrained to empty or "/" for every verb, so
    /// `oc-dash://quit/extra` and `oc-dash://start-server/extra` are not ours.
    /// One host means one action, and a wider match would let a typo in the
    /// page's URL construction become a way to terminate the app or a second
    /// way to start it. The query is not part of the match; the open verb reads
    /// its target out of the query afterwards, in `openTarget(in:)`. The offline
    /// verb ignores the query for the same reason it ignores a path: a report
    /// that the dashboard is gone does not carry a payload, and ignoring one
    /// means a page that adds a cache-buster cannot fail to be heard.
    ///
    /// The quit half of this is worth saying because it is the one that can
    /// end the process: relaxing this to a host-only match would turn
    /// `oc-dash://quit/extra` into a working kill switch.
    private static func isVerbURL(_ url: URL, host: String) -> Bool {
        guard url.host?.lowercased() == host else { return false }
        return url.path.isEmpty || url.path == "/"
    }

    /// The target the page asked to open, or nil when it named nothing this
    /// shell will hand to the system.
    ///
    /// Decoded by `URLComponents.queryItems`, which percent-decodes the key and
    /// the value and splits on `&` and `=` itself, so a target that contains
    /// either of those is not cut in half and a repeated `url` key is not
    /// confused with the value.
    ///
    /// Decoded exactly once. `URL(string:)` canonicalises an escaped string rather
    /// than expanding it, so `%2525` stays `%2525` through the parse below and
    /// nothing in this path decodes a second time. Verified rather than assumed,
    /// because a second decode is the kind of thing a future edit to the parse
    /// would reintroduce without looking like a change to validation.
    ///
    /// The scheme and host checks are on the parsed `URL`, not on the string.
    /// `URL.host` is the authority after `@` and before the path, which is the
    /// only reading that cannot be talked around by a string that merely
    /// contains a loopback address.
    private static func openTarget(in url: URL) -> URL? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let item = components.queryItems?.first(where: { $0.name == Config.openTargetQueryKey }),
            let value = item.value,
            let target = URL(string: value),
            let scheme = target.scheme?.lowercased(),
            let host = target.host?.lowercased(),
            Config.openTargetSchemes.contains(scheme),
            Config.openTargetHosts.contains(host)
        else { return nil }
        return target
    }
}
