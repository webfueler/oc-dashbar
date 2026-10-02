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
        #expect(StartServer.byHand == "npx @webfueler/oc-dash@latest server start")
        #expect(html.contains("npx @webfueler/oc-dash@latest server start"))
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

    // MARK: - Transparency

    /// The help page paints no ground of its own, so the panel's material and the
    /// desktop show through it.
    ///
    /// This is the same change mission 095 made to the widget page, asserted
    /// rather than described because a background can come back in a single line
    /// and nobody would notice until a screenshot did.
    ///
    /// The check is on the whole document rather than on one rule, because the
    /// ground this mission removed was two declarations: `background: Canvas` on
    /// the body, and a translucent fill on the button. A test that only looked at
    /// `body` would pass with the button's fill still there, and a fill on the
    /// most prominent control on the page is still a ground for that control.
    @Test("the document paints no background at all, so the panel's material shows through it")
    func noBackground() {
        #expect(!html.lowercased().contains("background"))
        // The two that were there, named so the failure says what came back.
        // `Canvas` on its own would be wrong to assert: `CanvasText` is a colour
        // the page still uses and it contains the same substring.
        #expect(!html.contains("background: Canvas"))
        #expect(!html.contains("rgba(127, 127, 127, 0.18)"))
        // And the two system keywords are still there as inks, which is the point
        // of the change: the page lost its ground, not its palette.
        #expect(html.contains("color: CanvasText"))
        #expect(html.contains("color: LinkText"))
    }

    @Test("no scrim, no tint and no text shadow either")
    func noScrimOrTint() {
        // The Captain declined this trade for the widget page, so the help page
        // does not get it either. A text shadow is the quiet way contrast gets
        // bought, and a pseudo-element scrim is the quiet way a page grows a
        // background it does not declare.
        #expect(!html.contains("text-shadow"))
        #expect(!html.contains("box-shadow"))
        #expect(!html.contains("::before"))
        #expect(!html.contains("::after"))
        #expect(!html.contains("opacity:"))
        #expect(!html.lowercased().contains("filter:"))
    }

    @Test("the page is transparent with no URL too, not only on the path that has one")
    func transparentOnEveryPath() {
        // Both call sites build the same document, but they take different
        // arguments, and the retry paragraph is the one that varies. Checking
        // only the URL-carrying variant would leave the other one unpinned.
        #expect(!OfflinePage.html(tried: nil, registryPath: registry).lowercased().contains("background"))
        #expect(
            !OfflinePage.html(tried: tried, registryPath: registry, waitSeconds: 1).lowercased().contains("background")
        )
    }

    /// The inks still come from the system, which is what makes the page legible
    /// against whatever is behind the panel.
    ///
    /// Pinned because removing the body's background also removes the context
    /// that made `CanvasText` resolve, and a later edit that replaced these with
    /// fixed hex values would make the page unreadable on one of the two
    /// appearances while still looking right in a screenshot of the other.
    @Test("the inks are still the system's, so they follow the appearance behind the panel")
    func inksFollowTheAppearance() {
        #expect(html.contains("color-scheme: light dark"))
        #expect(html.contains("color: CanvasText"))
        #expect(html.contains("color: LinkText"))
        #expect(html.contains("--dim"))
        // Both appearances are still served, so the page does not go fixed.
        #expect(html.contains("@media (prefers-color-scheme: dark)"))
    }
}
