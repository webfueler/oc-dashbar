import Foundation
import Testing

@testable import oc_dashbar

/// The reload bug, and the fix.
///
/// A `WKWebView` cannot be driven from this suite, so the case that would prove
/// the bug is not here; what is here is the invariant the bug came from and the
/// one the fix restores, both readable without a window. A test that needed a
/// live webview would either hang or quietly pass, and this one fails the moment
/// someone puts `nil` back.
@Suite("Offline page reload")
struct OfflinePageReloadTests {
    private let tried = URL(string: "http://127.0.0.1:4021/widget")!
    private let registry = "/Users/joaosantos/.local/state/oc-dash/service.json"

    /// The bug, pinned as the value that causes it.
    ///
    /// `loadHTMLString(_:baseURL: nil)` leaves the webview's URL as `about:blank`,
    /// and reloading `about:blank` produces an empty document. Measured with a
    /// real webview: 128 bytes of document became 39 and every element was gone,
    /// so a reload gesture while the help page was up blanked the panel instead
    /// of retrying anything.
    @Test("the help page is loaded at the URL that failed, never at about:blank")
    func loadedAtTheFailedURL() {
        let load = OfflinePage.load(tried: tried, registryPath: registry)
        #expect(load.baseURL == tried)
        #expect(load.effectiveBaseURL != URL(string: "about:blank")!)
        // Named rather than asserted as optionality, because "not nil" and "is
        // the failed URL" are different claims and only the second is the fix.
        #expect(load.effectiveBaseURL == tried)
    }

    @Test("with nothing resolved the base is nil, which is the honest answer and not a workaround")
    func nothingResolved() {
        // Reachable only from a blank or whitespace-only `Config.urlEnvironmentKey`.
        // There is no URL to reload and nothing for a base to point at, so nil is
        // correct here. Pinned so a later edit cannot quietly point it at a URL
        // that was never tried.
        let load = OfflinePage.load(tried: nil, registryPath: registry)
        #expect(load.baseURL == nil)
        #expect(load.effectiveBaseURL == URL(string: "about:blank")!)
    }

    @Test("one value carries both the document and the base, so the two cannot drift apart")
    func documentAndBaseTravelTogether() {
        // The reason this is a struct rather than two arguments: every caller
        // that shows the help page has to make the same choice about the base,
        // and the only way to guarantee that is for there to be one thing to pass.
        for candidate in [tried, nil] {
            let load = OfflinePage.load(tried: candidate, registryPath: registry)
            #expect(load.baseURL == candidate)
            #expect(load.html == OfflinePage.html(tried: candidate, registryPath: registry))
        }
    }

    /// The help page must not reach the network on its own, because it now has a
    /// real base URL and therefore a real origin.
    ///
    /// Checked on the literal rather than against a server, because a base URL
    /// only matters if something resolves against it, and this document is
    /// self-contained: an inline `<style>`, one inline `<script>`, and a retry
    /// link whose href is absolute. Measured with a logging server in front of it
    /// as well, and no request was made.
    @Test("the help page resolves nothing against its base, so the origin is never reached")
    func resolvesNothingAgainstTheBase() {
        let page = OfflinePage.load(tried: tried, registryPath: registry).html
        #expect(!page.contains("src="))
        #expect(!page.contains("<link"))
        #expect(!page.contains("@import"))
        #expect(!page.contains("url("))
        // The only anchor is the retry link, absolute, so it cannot resolve
        // against the base either.
        #expect(page.contains("<a href=\"http://127.0.0.1:4021/widget\">Try again</a>"))
        // And it cannot observe the dashboard, so the origin it now carries
        // gives it no power it did not already have.
        #expect(!page.contains("fetch("))
        #expect(!page.contains("XMLHttpRequest"))
        #expect(!page.contains("localStorage"))
        #expect(!page.contains("document.cookie"))
    }

    /// What the fix buys, stated as a test even though it needs a live webview to
    /// observe: a reload is now a retry of the failed URL rather than a reload of
    /// `about:blank`. Asserted on the inputs that decide it, so the claim is at
    /// least pinned even though the outcome is measured elsewhere.
    @Test("the base is the failed URL, which is what makes a reload a retry")
    func reloadIsARetry() {
        // Two cases the fix has to keep apart: a failed load reports the URL it
        // failed on, and the offline verb reports the URL the panel believed it
        // was showing. Both are the same URL in the ordinary case, and the code
        // passes whichever it has rather than re-resolving, so a move between
        // dashboards cannot make the help page describe a URL that was never
        // tried.
        let failedLoad = OfflinePage.load(tried: tried, registryPath: registry)
        #expect(failedLoad.baseURL == tried)
        #expect(failedLoad.html.contains("<a href=\"\(tried.absoluteString)\">Try again</a>"))
        #expect(failedLoad.html.contains("Port tried: 4021"))
    }
}
