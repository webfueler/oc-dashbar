import AppKit
import Testing

@testable import oc_dashbar

/// These lock the material choice: glass, behind a flag, with the deployment
/// floor in `Package.swift` doing the guarding rather than an `if #available`.
/// If that floor ever moves back to 15, the unguarded `NSGlassEffectView`
/// reference in `PanelMaterial.swift` stops compiling before anything in here
/// can pass.
@Suite("Panel material")
struct PanelMaterialTests {
    @Test("glass is the default and the panel is translucent, which is the choice itself")
    func defaultChoice() {
        #expect(Config.translucentPanel)
        #expect(Config.panelMaterial == .glass)
        #expect(Config.panelMaterialOpacity == 1.0)
        #expect(Config.panelMaterialAlpha == 1.0)
    }

    @Test("the class named in Config is really the class that ships, string lookups catch a rename")
    func classNameExists() {
        #expect(NSClassFromString("NSGlassEffectView") != nil)
        #expect(NSClassFromString("NSVisualEffectView") != nil)
    }

    @Test("both kinds build, and each hosts the page the way its own API documents")
    @MainActor
    func bothKindsBuild() throws {
        #expect(PanelMaterialKind.allCases.count == 2)
        for kind in PanelMaterialKind.allCases {
            let page = NSView(frame: NSRect(origin: .zero, size: Config.panelSize))
            let material = PanelMaterialView(
                kind: kind,
                frame: page.frame,
                cornerRadius: Config.panelCornerRadius
            )
            material.install(page)

            // The material is the only thing in the wrapper, so the page cannot
            // have been dropped on the floor.
            #expect(material.subviews.count == 1)
            switch kind {
            case .glass:
                let glass = try #require(material.subviews.first as? NSGlassEffectView)
                // NSGlassEffectView.h guarantees only contentView lands inside
                // the effect, so that is where the page has to be.
                #expect(glass.contentView === page)
                #expect(glass.cornerRadius == Config.panelCornerRadius)
                #expect(glass.style == .regular)
            case .visualEffect:
                let vibrancy = try #require(material.subviews.first as? NSVisualEffectView)
                #expect(vibrancy.subviews.first === page)
                // .popover is what NSVisualEffectView.h documents for the
                // background of an NSPopover window; .behindWindow is what
                // blends with the area behind the window.
                #expect(vibrancy.material == .popover)
                #expect(vibrancy.blendingMode == .behindWindow)
            }
        }
    }

    @Test("the opacity knob is clamped, so a typo cannot reach a view property")
    func opacityIsClamped() {
        #expect(Config.clampedOpacity(0) == 0)
        #expect(Config.clampedOpacity(0.42) == 0.42)
        #expect(Config.clampedOpacity(1) == 1)
        #expect(Config.clampedOpacity(-0.5) == 0)
        #expect(Config.clampedOpacity(2) == 1)
        #expect(Config.clampedOpacity(.nan) == 1)
        #expect(Config.clampedOpacity(.infinity) == 1)
        #expect(Config.clampedOpacity(-.infinity) == 1)
    }

    @Test("the corner radius is the one AppKit ships, so the popover keeps its own curve until a human says otherwise")
    func cornerRadius() {
        #expect(Config.panelCornerRadius == 8.0)
        #expect(Config.panelCornerRadius >= 0)
    }

    @Test("the popover window stops painting its own ground and takes the app's effective appearance")
    @MainActor
    func windowStopsPaintingItsOwn() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Config.panelSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // AppKit's own default, asserted before the call: if it ever changes,
        // the test should say so rather than quietly pass.
        #expect(window.isOpaque)
        window.prepareForTranslucentPanel()
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
        #expect(window.appearance === NSApplication.shared.effectiveAppearance)
    }
}
