import AppKit
import Foundation
import Testing
import WebKit

@testable import oc_dashbar

/// The offline verb's other half: the help page the shell swaps in, and the base
/// URL it is loaded at.
///
/// `webView(_:decidePolicyFor:decisionHandler:)` takes a `WKNavigationAction`,
/// which cannot be built, so the decision half is a pure function pinned in
/// `OfflineVerbTests` and the action half is pinned here. Both are driven
/// without a webview, because a `WKWebView` cannot load content under
/// `swift test`: the harness process is `swiftpm-testing-helper` and WebKit's
/// content process never answers for it. That was measured, not assumed, and it
/// is why these cases assert on values rather than on a live document. The
/// behaviour a live webview would show was measured separately against a real
/// webview and a real loopback server, and the numbers are in the report.
@Suite("Offline verb, delegate")
@MainActor
struct OfflineVerbDelegateTests {
    /// A delegate whose world-moving actions all record instead of running, so a
    /// case can prove the offline verb touched none of them.
    private func delegateThatOnlyRecords() -> (AppDelegate, () -> [String]) {
        let delegate = AppDelegate()
        var events: [String] = []
        delegate.startAction = { request in events.append("start#\(request)") }
        delegate.openAction = { url in events.append("open:\(url.absoluteString)") }
        delegate.termination = { events.append("quit") }
        return (delegate, { events })
    }

    @Test("the offline arm runs nothing: no quit, no start, no browser")
    func offlineActsAlone() {
        let (delegate, events) = delegateThatOnlyRecords()
        delegate.act(on: .showOfflinePage)
        #expect(events().isEmpty)
        #expect(delegate.quitRequestsAnswered == 0)
        #expect(delegate.startRequestsAnswered == 0)
    }

    @Test("the offline arm is not counted, so a second report is not a different answer")
    func notCounted() {
        // Quit and start carry a count because a second click is a second
        // request. This verb reports a state, so there is no count to keep and
        // nothing to compare: the delegate's counters must stay at zero after
        // any number of them.
        let (delegate, _) = delegateThatOnlyRecords()
        delegate.act(on: .showOfflinePage)
        delegate.act(on: .showOfflinePage)
        delegate.act(on: .showOfflinePage)
        #expect(delegate.quitRequestsAnswered == 0)
        #expect(delegate.startRequestsAnswered == 0)
    }

    @Test("the decision the delegate hands to WebKit is a cancellation for this verb")
    func cancelsTheNavigation() {
        // The delegate method itself cannot be driven from here, so what is
        // pinned is the decision it switches on. `.showOfflinePage` is not
        // `.allow`, and the one arm of the switch that allows a navigation is
        // the only one that does.
        let decision = PanelNavigation.decide(for: URL(string: Config.offlineURLString), quitRequestsHandled: 0)
        #expect(decision != .allow)
        #expect(decision == .showOfflinePage)
    }
}
