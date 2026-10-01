import Foundation
import Testing

@testable import oc_dashbar

/// The point of these is the contract with the widget's controls, so most
/// of them are about what the decision must NOT do: allow a URL this shell does
/// not understand, or hand the page a target the system opener would open in the
/// Captain's real browser. A helper test would have passed against an
/// implementation that returned an action for every URL.
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

    // MARK: - Open in browser

    /// The cross-repo contract for the third verb, same shape as `startURL`
    /// above. The page emits `oc-dash://open?url=<encoded>` and this shell has
    /// to answer exactly that. Spelled through Config so the two repositories
    /// have one string to diff, and checked against the other two verbs because
    /// a host that collided with either would be a control that does the wrong
    /// thing rather than one that does nothing.
    @Test("the open URL is oc-dash://open, and it is neither other verb's URL")
    func openURL() {
        #expect(Config.openHost == "open")
        #expect(Config.openURLString == "oc-dash://open")
        #expect(Config.openURLString != Config.quitURLString)
        #expect(Config.openURLString != Config.startURLString)
        let parsed = URL(string: Config.openURLString)
        #expect(parsed?.scheme == Config.quitScheme)
        #expect(parsed?.host == Config.openHost)
        #expect(parsed?.path == "")
        // A query-less open is the shape a page with no target to name writes,
        // and it has to be refused rather than treated as a request to open
        // something. This is the case the Captain would hit first if the page
        // half and the shell half disagreed about whether the query is required.
        #expect(decide(Config.openURLString) == .cancelUnknownHost(Config.openURLString))
    }

    /// The string the page actually emits, percent-encoded the way
    /// `encodeURIComponent` writes it. Spelled as a literal rather than built
    /// from Config for the same reason `pageSchemeQuits` spells one out: the
    /// string the page emits is the whole contract, and Config can always be
    /// changed to agree with itself.
    @Test("the URL the page emits opens the dashboard in the browser")
    func pageOpenURLOpens() {
        let target = URL(string: "http://127.0.0.1:4021/")!
        #expect(decide("oc-dash://open?url=http%3A%2F%2F127.0.0.1%3A4021%2F") == .openInBrowser(target))
        // The trailing-slash and uppercase spellings the page might emit, both
        // of which have to keep working for the same reason they do for quit.
        #expect(decide("oc-dash://open/?url=http%3A%2F%2F127.0.0.1%3A4021%2F") == .openInBrowser(target))
        #expect(decide("OC-Dash://Open?url=http%3A%2F%2F127.0.0.1%3A4021%2F") == .openInBrowser(target))
    }

    /// Nothing to open is not an open. Every one of these names the verb and
    /// then fails to name a target, and the correct answer for all of them is
    /// the same: refuse, and log, rather than open the widget URL or guess.
    @Test("an open with no usable target is cancelled rather than opening something")
    func openWithNoTargetIsCancelled() {
        for url in [
            "oc-dash://open",
            "oc-dash://open/",
            "oc-dash://open?url=",
            "oc-dash://open?target=http%3A%2F%2F127.0.0.1%3A4021%2F",
            "oc-dash://open?http%3A%2F%2F127.0.0.1%3A4021%2F",
        ] {
            #expect(decide(url) == .cancelUnknownHost(url), "\(url) must be refused")
        }
    }

    /// A target on a scheme that can execute, or one that reaches outside this
    /// machine. The first four are the interesting ones: a loopback host is not
    /// a pass on its own, the scheme is checked first and `data:` has no host at
    /// all, so it dies on the scheme before the host is ever read. The last is
    /// the page asking the shell to hand its own quit scheme to a browser.
    ///
    /// Every value here is percent-encoded exactly as the page writes it, and
    /// the query is decoded before anything is judged, which is what makes these
    /// refusals mean something: `file%3A%2F%2F%2Fetc%2Fpasswd` only becomes
    /// `file:///etc/passwd` once decoded, and a validator that looked at the
    /// encoded string would see a scheme it does not recognise and would pass by
    /// accident rather than by design.
    @Test("a target on a scheme that can execute or can leave this machine is refused")
    func nonWebTargetIsRefused() {
        for value in [
            "file%3A%2F%2F%2Fetc%2Fpasswd",
            "javascript%3Aalert(1)",
            "data%3Atext%2Fhtml%2Cx",
            "blob%3Ahttps%3A%2F%2F127.0.0.1%2Fabc",
            "ftp%3A%2F%2Fexample.com%2Fx",
            "mailto%3Aa%40b.c",
            "oc-dash%3A%2F%2Fquit",
        ] {
            let url = "oc-dash://open?url=\(value)"
            #expect(decide(url) == .cancelUnknownHost(url), "\(value) must be refused")
        }
    }

    /// The only family of refusal that tells the scheme check apart from the host
    /// check, and therefore the only one that fails if either of them is dropped.
    ///
    /// Every other hostile target in this suite is refused by the host check on
    /// its own: `file:///etc/passwd`, `javascript:alert(1)`, `data:...` and
    /// `mailto:` carry no host at all, and `ftp://example.com` and
    /// `oc-dash://quit` carry a host that is not loopback. Deleting the scheme
    /// check alone leaves all of them refused, which I checked rather than
    /// assumed, and which is not a result.
    ///
    /// These name a loopback host on a scheme that is not http or https, so the
    /// host check admits them and only the scheme check can stop them. The first
    /// is the one that matters: `file://127.0.0.1/etc/passwd` asks the shell to
    /// hand a file URL to the Captain's real browser, on the one host the
    /// allowlist admits, so the whole scheme list is what stands between a
    /// compromised widget page and a local file opening outside the panel.
    @Test("a loopback host on a non-web scheme is still refused, which only the scheme check can do")
    func loopbackHostOnNonWebSchemeIsRefused() {
        for value in [
            "file%3A%2F%2F127.0.0.1%2Fetc%2Fpasswd",
            "javascript%3A%2F%2F127.0.0.1%2Falert(1)",
            "data%3A%2F%2F127.0.0.1%2Fx",
            "oc-dash%3A%2F%2F127.0.0.1%2Fquit",
            "ssh%3A%2F%2F127.0.0.1%2F",
        ] {
            let url = "oc-dash://open?url=\(value)"
            #expect(decide(url) == .cancelUnknownHost(url), "\(value) must be refused")
        }
    }

    /// The one that closes the exfiltration channel. A string that contains a
    /// loopback address is not a loopback target, and only the parsed host tells
    /// the difference: in the second entry `URL.host` reads past the `@` and
    /// returns `example.com`, and in the third the loopback address is in the
    /// fragment where it addresses nothing.
    ///
    /// The last four are loopback addresses written in a way this allowlist does
    /// not recognise. They are refused, and that is the safe direction to be
    /// wrong in: a refused open is a dead click, a wrong admission is a page the
    /// Captain is logged into.
    @Test("a target whose host merely contains a loopback address is refused")
    func nonLoopbackHostIsRefused() {
        for value in [
            "http%3A%2F%2F127.0.0.1.example.com%2F",
            "http%3A%2F%2F127.0.0.1%40example.com%2F",
            "http%3A%2F%2Fexample.com%2F%23127.0.0.1",
            "https%3A%2F%2Fexample.com%2F",
            "http%3A%2F%2F127.0.0.1.%2F",
            "http%3A%2F%2F0177.0.0.1%2F",
            "http%3A%2F%2F2130706433%2F",
            "http%3A%2F%2F%5B0%3A0%3A0%3A0%3A0%3A0%3A0%3A1%5D%2F",
        ] {
            let url = "oc-dash://open?url=\(value)"
            #expect(decide(url) == .cancelUnknownHost(url), "\(value) must be refused")
        }
    }

    /// The one target shape this shell will hand to the system, and the last
    /// assertion is the one that matters: the URL arrives decoded, so the page
    /// does not get to hand `NSWorkspace` something the page and the shell
    /// disagree about. The fourth entry carries a query of its own, which is
    /// what a "view all" link with a range on it looks like.
    @Test("a loopback http or https target opens, and the URL reaches the decision decoded")
    func loopbackTargetOpens() {
        #expect(
            decide("oc-dash://open?url=http%3A%2F%2F127.0.0.1%3A4021%2F")
                == .openInBrowser(URL(string: "http://127.0.0.1:4021/")!)
        )
        #expect(
            decide("oc-dash://open?url=https%3A%2F%2Flocalhost%3A4021%2F")
                == .openInBrowser(URL(string: "https://localhost:4021/")!)
        )
        #expect(
            decide("oc-dash://open?url=http%3A%2F%2F%5B%3A%3A1%5D%3A4021%2F")
                == .openInBrowser(URL(string: "http://[::1]:4021/")!)
        )
        #expect(
            decide("oc-dash://open?url=http%3A%2F%2F127.0.0.1%3A4021%2F%3Frange%3D7d")
                == .openInBrowser(URL(string: "http://127.0.0.1:4021/?range=7d")!)
        )
        // A literal `%` in the target survives the trip. The page writes `%` as
        // `%25`, so it arrives as `%2525` and has to come out the other side as
        // `%25`, not as `%`. `URL(string:)` canonicalises rather than expands,
        // so this pins that nothing along the way decoded a second time.
        #expect(
            decide("oc-dash://open?url=http%3A%2F%2F127.0.0.1%3A4021%2Fsearch%3Fq%3D100%2525")
                == .openInBrowser(URL(string: "http://127.0.0.1:4021/search?q=100%25")!)
        )
        // An open is neither of the other two verbs, whichever way round the
        // decision is read. A shared case here would mean a click could quit.
        #expect(decide("oc-dash://open?url=http%3A%2F%2F127.0.0.1%3A4021%2F") != .quit(request: 1))
        #expect(decide("oc-dash://open?url=http%3A%2F%2F127.0.0.1%3A4021%2F") != .startServer(request: 1))
    }

    /// A target this shell cannot read is refused, and refused for the boring
    /// reason: it never becomes a URL with a scheme and a host at all.
    @Test("a target that is empty or unparseable is refused")
    func unreadableTargetIsRefused() {
        for value in ["", "%25", "not%20a%20url", "http%253A%252F%252F"] {
            let url = "oc-dash://open?url=\(value)"
            #expect(decide(url) == .cancelUnknownHost(url), "\(value) must be refused")
        }
    }

    /// A bad percent-escape does not fail loudly, which is why this one is
    /// spelled out rather than left in the loop above.
    ///
    /// `URL` re-escapes the stray `%` rather than rejecting the URL, so
    /// `oc-dash://open?url=http%3A%2F%2F127.0.0.1%ZZ%2F` reaches `URL(string:)`
    /// with its query already normalised to `http%253A%252F%252F...`. Decoded
    /// once by `queryItems` that is `http%3A%2F%2F127.0.0.1%ZZ%2F`, which has
    /// no scheme, so the scheme check is what refuses it. A validator that
    /// looked for `http` in the encoded string would have found it and passed.
    ///
    /// The second assertion is the one that surprised me while writing this: the
    /// refusal is correct, and the string it carries is the canonical form rather
    /// than the string the page wrote, because `.cancelUnknownHost` carries
    /// `url.absoluteString`. The log line a refused open produces is therefore
    /// re-escaped. It still names the same URL, which is what makes it
    /// diagnosable, but it is not byte-identical to what the page emitted.
    @Test("a badly percent-escaped target is refused, and the refusal names the canonical URL")
    func badlyEscapedTargetIsRefused() {
        let page = "oc-dash://open?url=http%3A%2F%2F127.0.0.1%ZZ%2F"
        let canonical = URL(string: page)!.absoluteString
        #expect(canonical != page, "URL normalises the stray % and this test depends on that")
        #expect(decide(page) == .cancelUnknownHost(canonical))
        #expect(decide(page) != .openInBrowser(URL(string: "http://127.0.0.1:4021/")!))
    }

    @Test("a scheme this panel does not load is cancelled, never navigated")
    func foreignSchemeIsCancelled() {
        #expect(decide("mailto:person@example.com") == .cancelForeignScheme("mailto"))
        #expect(decide("javascript:alert(1)") == .cancelForeignScheme("javascript"))
        #expect(decide("file:///etc/passwd") == .cancelForeignScheme("file"))
        #expect(decide("data:text/html,<p>hi</p>") == .cancelForeignScheme("data"))
        #expect(decide("blob:https://127.0.0.1/abc") == .cancelForeignScheme("blob"))
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
        // `https://example.com/` is allowed here and
        // `oc-dash://open?url=https://example.com/` is refused, and that is not
        // a contradiction. This arm loads the page inside the panel, where it
        // stays in a webview that cannot reach the Captain's cookies or his
        // password manager. The open verb hands the URL to Launch Services
        // instead, which is a much wider door, so it gets its own rule. See
        // `nonLoopbackHostIsRefused`.
    }

    /// The one property worth asserting over the whole set, rather than case by
    /// case: nothing on our scheme, and no foreign scheme, ever returns allow.
    @Test("no URL that the shell cannot handle is ever allowed to navigate")
    func nothingUnhandledNavigates() {
        let refused = [
            "oc-dash://nope", "oc-dash://quit/extra", "oc-dash://start-server/extra", "oc-dash:quit",
            "mailto:a@b.c", "javascript:void(0)", "file:///etc/passwd", "data:text/html,<p>hi</p>",
            "ftp://example.com/x", "blob:https://127.0.0.1/abc",
            // The shell's own retired scheme. It is foreign now and belongs in
            // this list for the same reason mailto does.
            "ocdashbar://quit",
            // The open verb and its neighbours. A verb with no target and a verb
            // with a target on a path are both refused, and the last is a
            // malformed target on our own scheme: it has to read as refused
            // rather than as an unhandled open, which is the whole reason the
            // open match sits inside this scheme's arm.
            "oc-dash://open", "oc-dash://open/extra", "oc-dash://open?url=file%3A%2F%2F%2Fetc%2Fpasswd",
            "oc-dash://open?url=https%3A%2F%2Fexample.com%2F",
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
