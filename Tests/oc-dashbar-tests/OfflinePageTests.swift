import Foundation
import Testing

@testable import oc_dashbar

/// The offline page has a start control, and these tests pin the three things
/// on it that are contracts: the verb it emits, the command line that names the
/// published package, and the diagnostics. The bounded wait is pinned as
/// structure here (one timer, the configured bound, a visible give-up state);
/// its behaviour over time is driven in a browser rather than asserted onto a
/// string, because that is where the page runs.
@Suite("Offline page")
struct OfflinePageTests {
    private let tried = URL(string: "http://127.0.0.1:4022/widget")!
    private let registry = "/Users/someone/.local/state/oc-dash/service.json"

    private var html: String { OfflinePage.html(tried: tried, registryPath: registry) }

    @Test("the start control emits the verb the shell intercepts")
    func startControl() {
        // The literal, spelled out rather than read back from Config, for the
        // same reason the navigation tests spell two URLs out: the string the
        // page emits is the contract and Config can always be changed to agree
        // with itself.
        #expect(html.contains("oc-dash://start-server"))
        #expect(html.contains(Config.startURLString))
        #expect(html.contains("id=\"start\""))
        #expect(html.contains("Start the dashboard"))
    }

    @Test("the command line names the published package, not the bare name that is a 404")
    func commandLine() {
        #expect(StartServer.byHand == "npx @webfueler/oc-dash server start")
        #expect(html.contains("npx @webfueler/oc-dash server start"))
    }

    @Test("the diagnostics name the port tried and the registry file consulted")
    func diagnostics() {
        #expect(html.contains("Port tried: 4022"))
        #expect(html.contains(registry))
    }

    @Test("with nothing resolved the port line says so rather than naming a port nobody tried")
    func diagnosticsWithoutAURL() {
        let page = OfflinePage.html(tried: nil, registryPath: registry)
        #expect(page.contains("Port tried: none"))
        // The link itself, not prose: the no-URL give-up line must not mention
        // a control the page does not carry, which the next test covers.
        #expect(!page.contains(">Try again</a>"))
    }

    @Test("the retry link still points at the URL whose load failed")
    func retryLink() {
        #expect(html.contains("<a href=\"http://127.0.0.1:4022/widget\">Try again</a>"))
    }

    @Test("a registry path with markup in it is escaped rather than injected")
    func escaping() {
        let page = OfflinePage.html(tried: nil, registryPath: "/tmp/a&b/<c>")
        #expect(page.contains("/tmp/a&amp;b/&lt;c&gt;"))
        #expect(!page.contains("/tmp/a&b/<c>"))
    }

    @Test("the wait is one bounded timer at the configured bound, never an interval")
    func waitIsBounded() {
        #expect(Config.startWatchTimeout == 25)
        #expect(html.components(separatedBy: "setTimeout").count - 1 == 1)
        #expect(!html.contains("setInterval"))
        #expect(html.contains("var wait = \(Int(Config.startWatchTimeout) * 1000);"))
        #expect(html.contains("window.setTimeout(giveUp, wait)"))
    }

    @Test("the give-up state exists: it speaks and it hands the manual controls back")
    func giveUpExists() {
        // The temporal half of this, the state actually appearing after the
        // wait, is not asserted here; it is driven by clicking the real button
        // in a browser.
        #expect(html.contains("Gave up waiting after \(Int(Config.startWatchTimeout)) seconds."))
        #expect(html.contains("button.disabled = false"))
        #expect(html.contains("Start again"))
    }

    @Test("the give-up line points only at controls the page actually has")
    func giveUpNamesOnlyPresentControls() {
        #expect(html.contains("Try again, or run the command in a terminal"))
        // No URL means no retry link, so the line must not send the reader to
        // a control that is not on the page.
        let withoutURL = OfflinePage.html(tried: nil, registryPath: registry)
        #expect(withoutURL.contains("Run the command in a terminal to see what it says."))
        #expect(!withoutURL.contains("Try again"))
    }

    @Test("the waiting state is visible, so a click does not look ignored")
    func waitingIsVisible() {
        #expect(html.contains("status.hidden = false"))
        #expect(html.contains("Starting the dashboard."))
    }

    @Test("the page cannot observe the dashboard, so it cannot claim the start worked")
    func cannotObserve() {
        #expect(!html.contains("fetch("))
        #expect(!html.contains("XMLHttpRequest"))
        #expect(!html.contains("location.reload"))
    }

    @Test("the compressed bound a test uses is the same page code")
    func compressedBound() {
        #expect(OfflinePage.html(tried: nil, registryPath: registry, waitSeconds: 1).contains("var wait = 1000;"))
    }
}
