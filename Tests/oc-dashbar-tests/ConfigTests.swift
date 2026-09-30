import AppKit
import Testing

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

    @Test("http, https and about navigate; nothing else does")
    func navigableSchemes() {
        #expect(Config.navigableSchemes == ["http", "https", "about"])
    }

    @Test("panel stays 340x420 until the oc-dash page says otherwise")
    func panelSize() {
        #expect(Config.panelSize == NSSize(width: 340, height: 420))
    }
}
