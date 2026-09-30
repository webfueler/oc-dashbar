import Foundation
import Testing

@testable import oc_dashbar

/// The point of these is the contract with the widget's two controls, so most
/// of them are about what the decision must NOT do: allow a URL this shell does
/// not understand. A helper test would have passed against an implementation
/// that returned an action for every URL.
@Suite("Panel navigation")
struct PanelNavigationTests {
    private func decide(_ string: String?, quit: Int = 0, start: Int = 0) -> PanelNavigation.Decision {
        PanelNavigation.decide(
            for: string.flatMap(URL.init(string:)),
            quitRequestsHandled: quit,
            startRequestsHandled: start
        )
    }

    @Test("the quit URL answers quit, and nothing else does")
    func quitURL() {
        #expect(decide(Config.quitURLString) == .quit(request: 1))
    }

    /// The regression guard for the scheme mismatch, paired with
    /// `oldSchemeIsCancelled` below. The page emits `oc-dash://quit` and the
    /// shell moved to it, so this is the URL that has to terminate the process.
    ///
    /// Spelled as a literal rather than only through Config, because the string
    /// the page emits is the whole contract and Config can always be changed to
    /// agree with itself.
    @Test("the scheme the page emits quits")
    func pageSchemeQuits() {
        #expect(decide("oc-dash://quit") == .quit(request: 1))
        #expect(decide("oc-dash://quit/") == .quit(request: 1))
    }

    /// The other half of the pair. The shell used to answer `ocdashbar://quit`,
    /// a name this shell invented and the page never emitted, so the page's quit
    /// did nothing until the two sides were compared. That old name must now be
    /// refused, which for this shell means it is no longer its own scheme at
    /// all: it falls through to the foreign-scheme arm and is cancelled there.
    /// Nothing navigates it either way.
    @Test("the scheme the shell used to answer is cancelled, not honoured")
    func oldSchemeIsCancelled() {
        #expect(decide("ocdashbar://quit") == .cancelForeignScheme("ocdashbar"))
        #expect(decide("ocdashbar://quit") != .quit(request: 1))
        #expect(decide("ocdashbar://quit/") == .cancelForeignScheme("ocdashbar"))
    }

    @Test("a trailing slash is the same intent, because URL equality is not")
    func trailingSlash() {
        #expect(decide("oc-dash://quit/") == .quit(request: 1))
        // The reason this test exists: these two are not the same URL, so
        // matching on absoluteString would have made the first one stop working.
        #expect(URL(string: "oc-dash://quit")! != URL(string: "oc-dash://quit/")!)
        #expect(decide("oc-dash://quit/") == decide("oc-dash://quit"))
    }

    @Test("scheme and host are matched case-insensitively, as RFC 3986 says")
    func caseInsensitive() {
        #expect(decide("OC-Dash://QUIT") == .quit(request: 1))
        #expect(decide("oc-dash://Quit") == .quit(request: 1))
    }

    @Test("a second quit is still answered, and it counts")
    func repeatedQuit() {
        #expect(decide(Config.quitURLString, quit: 1) == .quit(request: 2))
        #expect(decide(Config.quitURLString, quit: 7) == .quit(request: 8))
    }

    @Test("a query string does not change the intent, the quit carries no data")
    func quitWithQuery() {
        #expect(decide("oc-dash://quit?confirm=1") == .quit(request: 1))
    }

    /// The case that matters most for our own scheme. A URL that is ours but is
    /// not one of the two verbs must never navigate: a page that guesses wrong
    /// should quit nothing and start nothing rather than something.
    @Test("an unknown host on our own scheme is cancelled, never navigated")
    func unknownHostIsCancelled() {
        for url in ["oc-dash://nope", "oc-dash://reopen", "oc-dash://", "oc-dash:quit"] {
            #expect(decide(url) == .cancelUnknownHost(url))
        }
    }

    /// One host means one action. A path under the quit host is a different URL
    /// and a widened match would turn a page-side typo into a way to terminate
    /// the app. The same constraint holds for the start host, or
    /// `oc-dash://quit/extra` becomes a second kill switch.
    @Test("a path under the quit host is cancelled rather than treated as quit")
    func pathUnderQuitHostIsCancelled() {
        #expect(decide("oc-dash://quit/extra") == .cancelUnknownHost("oc-dash://quit/extra"))
        #expect(decide("oc-dash://quit/extra/a/b") == .cancelUnknownHost("oc-dash://quit/extra/a/b"))
    }

    /// The twin of the test above: the start host is not widened either.
    /// `oc-dash://start-server/anything` is a URL the page was told not to
    /// emit, and a host-only match would make it a second working command that
    /// spawns a process.
    @Test("a path under the start host is cancelled rather than treated as start")
    func pathUnderStartHostIsCancelled() {
        #expect(decide("oc-dash://start-server/extra") == .cancelUnknownHost("oc-dash://start-server/extra"))
        #expect(decide("oc-dash://start-server/extra/a/b") == .cancelUnknownHost("oc-dash://start-server/extra/a/b"))
        #expect(decide("oc-dash://start-server/extra") != .startServer(request: 1))
    }

    /// The cross-repo contract, in the same shape as `ConfigTests.quitURL`.
    /// The page emits `oc-dash://start-server` and this shell has to answer
    /// exactly that.
    @Test("the start URL is oc-dash://start-server, and it is not the quit URL")
    func startURL() {
        #expect(Config.startHost == "start-server")
        #expect(Config.startURLString == "oc-dash://start-server")
        #expect(Config.startURLString != Config.quitURLString)
        let parsed = URL(string: Config.startURLString)
        #expect(parsed?.scheme == Config.quitScheme)
        #expect(parsed?.host == Config.startHost)
        // The page's URL has no path, so the path constraint has to accept the
        // empty case or the real URL would not start anything.
        #expect(parsed?.path == "")
    }

    @Test("the URL the page emits starts the dashboard")
    func pageStartURLStarts() {
        #expect(decide("oc-dash://start-server") == .startServer(request: 1))
        #expect(decide("oc-dash://start-server/") == .startServer(request: 1))
        #expect(decide("OC-Dash://Start-Server") == .startServer(request: 1))
    }

    @Test("a second start is still answered, and it counts")
    func repeatedStart() {
        #expect(decide(Config.startURLString, start: 1) == .startServer(request: 2))
        #expect(decide(Config.startURLString, start: 7) == .startServer(request: 8))
    }

    @Test("a query string does not change the start intent, it carries no data")
    func startWithQuery() {
        #expect(decide("oc-dash://start-server?port=4022") == .startServer(request: 1))
    }

    /// The two verbs are counted separately and neither counts the other. A
    /// shared counter would make the log say "start request #3" for a panel
    /// that had been quit once, which is a sentence nobody can act on.
    @Test("the two verbs count independently")
    func countersAreIndependent() {
        #expect(decide("oc-dash://quit", quit: 2, start: 9) == .quit(request: 3))
        #expect(decide("oc-dash://start-server", quit: 2, start: 9) == .startServer(request: 10))
    }

    @Test("a scheme this panel does not load is cancelled, never navigated")
    func foreignSchemeIsCancelled() {
        #expect(decide("mailto:person@example.com") == .cancelForeignScheme("mailto"))
        #expect(decide("javascript:alert(1)") == .cancelForeignScheme("javascript"))
        #expect(decide("file:///etc/passwd") == .cancelForeignScheme("file"))
    }

    @Test("the widget, a retry link and WebKit's own document all still navigate")
    func ordinaryNavigationIsAllowed() {
        #expect(decide("http://127.0.0.1:4021/widget") == .allow)
        #expect(decide("http://127.0.0.1:4022/widget") == .allow)
        #expect(decide("https://example.com/") == .allow)
        #expect(decide("about:blank") == .allow)
        // A relative URL has no scheme to be unrecognised, and the offline
        // page's retry link is exactly this shape.
        #expect(decide("/widget") == .allow)
        #expect(decide(nil) == .allow)
    }

    /// The one property worth asserting over the whole set, rather than case by
    /// case: nothing on our scheme, and no foreign scheme, ever returns allow.
    @Test("no URL that the shell cannot handle is ever allowed to navigate")
    func nothingUnhandledNavigates() {
        let refused = [
            "oc-dash://nope", "oc-dash://quit/extra", "oc-dash://start-server/extra", "oc-dash:quit",
            "mailto:a@b.c", "javascript:void(0)", "file:///etc/passwd", "data:text/html,<p>hi</p>",
            "ftp://example.com/x",
            // The shell's own retired scheme. It is foreign now and belongs in
            // this list for the same reason mailto does.
            "ocdashbar://quit",
        ]
        for url in refused {
            #expect(decide(url) != .allow, "\(url) must not be allowed to navigate")
        }
        let accepted = ["http://127.0.0.1:4021/widget", "https://example.com/", "about:blank"]
        for url in accepted {
            #expect(decide(url) == .allow, "\(url) is an ordinary load")
        }
    }

    @Test("a fresh delegate has answered no quits and no starts")
    @MainActor
    func noRequestsAtLaunch() {
        #expect(AppDelegate().quitRequestsAnswered == 0)
        #expect(AppDelegate().startRequestsAnswered == 0)
    }
}
