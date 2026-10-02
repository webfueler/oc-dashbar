import Foundation
import Testing

@testable import oc_dashbar

/// The verb that lets the page report a lost dashboard.
///
/// These pin the three things the brief names as load-bearing: the URL is
/// matched, it is one of ours rather than an unknown host, and it is answered on
/// the same terms as the two verbs beside it. The cancellation and the page swap
/// themselves live in `AppDelegate`, driven in `AppDelegateVerbTests`.
@Suite("Offline verb")
struct OfflineVerbTests {
    @Test("the verb is oc-dash://offline, spelled out rather than read back from Config")
    func verbString() {
        // The literal is the contract with oc-dash mission 109, so it is written
        // here and not read from Config: a Config change that disagreed with
        // itself would pass a test that read Config.
        #expect(Config.offlineHost == "offline")
        #expect(Config.offlineURLString == "oc-dash://offline")
        #expect(Config.quitScheme == "oc-dash")
    }

    @Test("it is the same scheme as the other verbs, so the two sides reconcile on one string")
    func sameScheme() {
        #expect(Config.offlineURLString.hasPrefix("\(Config.quitScheme)://"))
        #expect(URL(string: Config.offlineURLString)?.scheme == Config.quitScheme)
        #expect(URL(string: Config.offlineURLString)?.host == Config.offlineHost)
    }

    @Test("the verb is answered: it decides, and it does not fall through to allow or refuse")
    func matched() {
        let decision = PanelNavigation.decide(for: URL(string: Config.offlineURLString), quitRequestsHandled: 0)
        #expect(decision == .showOfflinePage)
    }

    @Test("a trailing slash is the same intent, like the other three verbs")
    func trailingSlash() {
        #expect(
            PanelNavigation.decide(for: URL(string: "oc-dash://offline/"), quitRequestsHandled: 0) == .showOfflinePage
        )
    }

    @Test("a query is ignored: the verb carries no payload and a cache-buster must not silence it")
    func queryIgnored() {
        // Unlike open, which reads its target out of the query, this verb has no
        // target. A page that appends something must still be heard.
        #expect(
            PanelNavigation.decide(for: URL(string: "oc-dash://offline?t=12345"), quitRequestsHandled: 0)
                == .showOfflinePage
        )
        #expect(
            PanelNavigation.decide(for: URL(string: "oc-dash://offline#x"), quitRequestsHandled: 0)
                == .showOfflinePage
        )
    }

    @Test("case does not matter, because scheme and host are matched lowercased")
    func caseInsensitive() {
        #expect(
            PanelNavigation.decide(for: URL(string: "OC-DASH://OFFLINE"), quitRequestsHandled: 0) == .showOfflinePage
        )
    }

    @Test("a path beyond the verb is not ours, on the same rule as quit and start")
    func extraPathRefused() {
        // The rule that keeps a typo in the page's URL construction from
        // becoming a way to swap the panel.
        #expect(
            PanelNavigation.decide(for: URL(string: "oc-dash://offline/extra"), quitRequestsHandled: 0)
                == .cancelUnknownHost("oc-dash://offline/extra")
        )
    }

    @Test("the three neighbours of the verb are still answered as themselves")
    func neighboursUnchanged() {
        // Adding a fourth verb must not have disturbed the three that existed.
        let quit = PanelNavigation.decide(for: URL(string: "oc-dash://quit"), quitRequestsHandled: 4)
        #expect(quit == .quit(request: 5))
        let start = PanelNavigation.decide(
            for: URL(string: "oc-dash://start-server"),
            quitRequestsHandled: 0,
            startRequestsHandled: 2
        )
        #expect(start == .startServer(request: 3))
        let open = PanelNavigation.decide(
            for: URL(string: "oc-dash://open?url=http%3A%2F%2F127.0.0.1%3A4021%2Fdashboard"),
            quitRequestsHandled: 0
        )
        #expect(open == .openInBrowser(URL(string: "http://127.0.0.1:4021/dashboard")!))
    }

    @Test("the offline verb is not a way to reach the open verb's validation")
    func doesNotOpenAnything() {
        // An open target smuggled onto the offline verb is refused, not honoured:
        // the verb has no target and this shell hands nothing to the system.
        let decision = PanelNavigation.decide(
            for: URL(string: "oc-dash://offline?url=file%3A%2F%2F%2Fetc%2Fpasswd"),
            quitRequestsHandled: 0
        )
        #expect(decision == .showOfflinePage)
        guard case .showOfflinePage = decision else {
            Issue.record("offline with a query must still be the offline verb")
            return
        }
        // And it is not any of the answers that act on the world.
        #expect(decision != .openInBrowser(URL(string: "file:///etc/passwd")!))
    }

    @Test("no verb loop: the help page the verb loads never emits the verb back")
    func noLoop() {
        // The loop this mission has to rule out is the page telling the shell to
        // show the page, which would show the page forever. The page is static
        // HTML, so the check is that the document contains no reference to the
        // verb at all. Measured on the shipped document in the probe; pinned here
        // so a future edit that adds one is caught by the suite.
        let page = OfflinePage.html(tried: URL(string: "http://127.0.0.1:4021/widget"), registryPath: "/r")
        #expect(!page.contains(Config.offlineURLString))
        #expect(!page.lowercased().contains("oc-dash://offline"))
        // Exactly one oc-dash URL on the page, and it is the start verb, which
        // the shell answers by spawning and never by reloading the page.
        #expect(page.components(separatedBy: "oc-dash://").count - 1 == 1)
        #expect(page.contains(Config.startURLString))
    }

    @Test("the help page carries no location assignment other than the start control")
    func noSelfNavigation() {
        // The only script-driven navigation is the start button's, and it goes to
        // the start verb. A `location.href` to the offline verb, or a reload of
        // the page itself from inside the page, is the other way a loop could
        // form and neither is present.
        let page = OfflinePage.html(tried: URL(string: "http://127.0.0.1:4021/widget"), registryPath: "/r")
        #expect(page.components(separatedBy: "window.location.href").count - 1 == 1)
        #expect(!page.contains("location.reload"))
        #expect(!page.contains("setInterval"))
    }

    @Test("a nil or empty URL is allowed, so WebKit's own documents are not cancelled")
    func internalDocumentsAllowed() {
        // Unchanged behaviour, and load-bearing: cancelling about:blank blanks
        // the panel instead of protecting it.
        #expect(PanelNavigation.decide(for: nil, quitRequestsHandled: 0) == .allow)
        #expect(PanelNavigation.decide(for: URL(string: "about:blank"), quitRequestsHandled: 0) == .allow)
    }
}
