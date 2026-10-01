import AppKit
import Testing
import WebKit

@testable import oc_dashbar

/// The point of these is not the URL parsing, it is locking the contract this
/// shell shares with the oc-dash /widget page. If a number here changes, the
/// oc-dash side has to change with it.
@Suite("Config")
struct ConfigTests {
    @Test("default widget URL points at 4021 /widget")
    func defaultWidgetURL() {
        #expect(Config.resolvedWidgetURL(environment: [:])?.absoluteString == "http://127.0.0.1:4021/widget")
        #expect(Config.defaultWidgetURLString == "http://127.0.0.1:4021/widget")
    }

    @Test("environment override wins, so the panel can point at a scratch server")
    func environmentOverride() {
        let environment = [Config.urlEnvironmentKey: "http://127.0.0.1:4022/widget"]
        #expect(Config.resolvedWidgetURL(environment: environment)?.absoluteString == "http://127.0.0.1:4022/widget")
    }

    @Test("blank or unparseable override resolves to nil instead of a silent blank panel")
    func unusableOverride() {
        #expect(Config.resolvedWidgetURL(environment: [Config.urlEnvironmentKey: "   "]) == nil)
        #expect(Config.resolvedWidgetURL(environment: [Config.urlEnvironmentKey: ""]) == nil)
    }

    /// The cross-repo contract, same reason as the URL above: the page in
    /// oc-dash emits this exact string and this shell answers it. If either
    /// side changes it, this test is where the mismatch shows up.
    ///
    /// This test once caught a real mismatch: both sides were written without
    /// reading each other, the page kept the name it emits, and the shell moved
    /// to meet it.
    @Test("the quit URL is oc-dash://quit, and it decodes to the scheme and host the shell matches")
    func quitURL() {
        #expect(Config.quitScheme == "oc-dash")
        #expect(Config.quitHost == "quit")
        #expect(Config.quitURLString == "oc-dash://quit")
        let parsed = URL(string: Config.quitURLString)
        #expect(parsed?.scheme == Config.quitScheme)
        #expect(parsed?.host == Config.quitHost)
        // The page's URL has no path, so the path constraint in QuitNavigation
        // has to accept the empty case or the real URL would not quit.
        #expect(parsed?.path == "")
    }

    @Test("the open URL is oc-dash://open, and its allowlist is http and https on loopback")
    func openURL() {
        #expect(Config.openHost == "open")
        #expect(Config.openURLString == "oc-dash://open")
        let parsed = URL(string: Config.openURLString)
        #expect(parsed?.scheme == Config.quitScheme)
        #expect(parsed?.host == Config.openHost)
        // The page's URL has no path, so the path constraint in PanelNavigation
        // has to accept the empty case or the real URL would not open.
        #expect(parsed?.path == "")
        #expect(Config.openTargetQueryKey == "url")
        #expect(Config.openTargetSchemes == ["http", "https"])
        #expect(Config.openTargetHosts == ["127.0.0.1", "localhost", "::1"])
        // Two different rules, deliberately. `navigableSchemes` lets the webview
        // reach any http or https host on any machine, which is fine for a page
        // load inside the panel and is not fine for a hand-off to the Captain's
        // real browser. This assertion fails if either set is ever made to reuse
        // the other, which is the mistake this pair is easiest to make.
        #expect(Config.openTargetSchemes != Config.navigableSchemes)
    }

    @Test("http, https and about navigate; nothing else does")
    func navigableSchemes() {
        #expect(Config.navigableSchemes == ["http", "https", "about"])
    }

    @Test("panel stays 340x420 until the oc-dash page says otherwise")
    func panelSize() {
        #expect(Config.panelSize == NSSize(width: 340, height: 420))
    }

    /// The one this panel's transparency now rests on, and the one that fails
    /// loudly rather than quietly.
    ///
    /// The write is by string, so nothing in the build notices a macOS that
    /// drops the key: the code still compiles, the app still launches, and the
    /// panel is simply opaque again. This is the failure mode, and it is why it
    /// needs a test rather than a comment. The underscored selector is what has
    /// to be asked about, because the obvious name is not implemented and a test
    /// written against it would pass on a WebKit that had thrown the key away.
    @Test("the private key the panel's transparency depends on is still on WKWebView")
    @MainActor
    func webviewDrawsBackgroundKeyIsStillOnThisSDK() {
        #expect(Config.webviewDrawsBackgroundKey == "drawsBackground")
        #expect(Config.webviewDrawsBackgroundSelector == "_setDrawsBackground:")
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        #expect(view.responds(to: NSSelectorFromString(Config.webviewDrawsBackgroundSelector)))
    }

    /// The default, not a variant, because there is no variant any more.
    ///
    /// Nothing is set in the environment to get here, which is the point: this
    /// drives the one function `installPopover()` calls and reads the key back
    /// off a real webview, so it is the shipped behaviour under test rather than
    /// a copy of it. The read before the call is what makes the read after it
    /// mean something, and it doubles as the record that WebKit still defaults
    /// this on, which is the slab the whole key exists to remove.
    @Test("with nothing set anywhere, the webview is told not to paint its own background")
    @MainActor
    func webviewBackgroundIsTransparentByDefault() {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let before = view.value(forKey: Config.webviewDrawsBackgroundKey) as? NSNumber
        #expect(before?.boolValue == true)
        AppDelegate.applyWebviewCompositing(to: view)
        let after = view.value(forKey: Config.webviewDrawsBackgroundKey) as? NSNumber
        #expect(after?.boolValue == false)
    }
}
