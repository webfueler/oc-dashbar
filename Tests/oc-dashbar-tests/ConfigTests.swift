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

    @Test("the material harness has six variants, and the strings are the ones the log prints")
    func materialVariantList() {
        #expect(Config.materialEnvironmentKey == "OC_DASHBAR_MATERIAL")
        // Order as well as contents: this is the order in the handoff table, and
        // a variant that moved would mean the table and the code disagree.
        #expect(
            Config.PanelMaterialVariant.allCases.map(\.rawValue)
                == [
                    "glass-regular",
                    "glass-regular-notint",
                    "glass-clear",
                    "visualEffect-behind",
                    "visualEffect-within",
                    "none",
                ]
        )
    }

    @Test("each of the six values selects itself, so no variant is reachable only by falling back")
    func materialVariantSelectsItself() {
        for variant in Config.PanelMaterialVariant.allCases {
            #expect(
                Config.resolvedMaterialVariant(environment: [Config.materialEnvironmentKey: variant.rawValue])
                    == variant
            )
        }
    }

    @Test("unset, empty, wrong case, padded or nonsense all mean today's behaviour")
    func materialVariantFallsBack() {
        // The fallback is the point. An app that refuses to start over a typo in
        // an environment variable is worse than one that ignores it.
        #expect(Config.resolvedMaterialVariant(environment: [:]) == .glassRegular)
        #expect(Config.resolvedMaterialVariant(environment: [Config.materialEnvironmentKey: ""]) == .glassRegular)
        #expect(Config.resolvedMaterialVariant(environment: [Config.materialEnvironmentKey: "none "]) == .glassRegular)
        #expect(
            Config.resolvedMaterialVariant(environment: [Config.materialEnvironmentKey: " glass-clear"])
                == .glassRegular
        )
        // Not a case-insensitive match, on purpose: the six strings are what
        // gets typed into a shell, and a silent normalisation would make a typo
        // look like it worked.
        #expect(
            Config.resolvedMaterialVariant(environment: [Config.materialEnvironmentKey: "GLASS-CLEAR"])
                == .glassRegular
        )
        #expect(Config.resolvedMaterialVariant(environment: [Config.materialEnvironmentKey: "glass"]) == .glassRegular)
    }

    @Test("this process has the variable unset, so the default under test is the real default")
    func materialVariantDefaultHere() {
        // `swift test` runs with the ambient environment, so this covers the
        // `ProcessInfo` read that the other cases above deliberately bypass.
        #expect(Config.panelMaterialVariant == .glassRegular)
        #expect(Config.buildsPanelMaterial)
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

    @Test("only none builds no material, and none is the variant that answers the screenshot's question")
    func onlyNoneSkipsTheMaterial() {
        for variant in Config.PanelMaterialVariant.allCases {
            #expect(variant.buildsMaterial == (variant != .none))
            if variant == .none {
                #expect(variant.materialKind == nil)
            }
            else {
                #expect(variant.materialKind != nil)
            }
        }
    }
}
