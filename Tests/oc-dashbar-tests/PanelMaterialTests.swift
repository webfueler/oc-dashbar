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
    @Test("glass-regular is the default and the panel is translucent, which is the choice itself")
    func defaultChoice() {
        #expect(Config.translucentPanel)
        #expect(Config.panelMaterialVariant == .glassRegular)
        #expect(Config.panelMaterialVariant.materialKind == .glass)
        #expect(Config.buildsPanelMaterial)
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
                variant: Config.PanelMaterialVariant.forKind(kind),
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

    /// The whole point of the harness, asserted from a session with no window
    /// server: every variant builds the class and the style it names, so a
    /// screenshot that comes back flat is a fact about the rendering and not
    /// about a switch that went the wrong way.
    @Test("every variant builds the class, style and tint it names")
    @MainActor
    func everyVariantBuilds() throws {
        for variant in Config.PanelMaterialVariant.allCases {
            let page = NSView(frame: NSRect(origin: .zero, size: Config.panelSize))
            let material = PanelMaterialView(
                variant: variant,
                frame: page.frame,
                cornerRadius: Config.panelCornerRadius
            )
            material.install(page)
            switch variant.materialKind {
            case .glass:
                let glass = try #require(material.subviews.first as? NSGlassEffectView)
                #expect(glass.contentView === page)
                #expect(glass.cornerRadius == Config.panelCornerRadius)
                switch variant {
                case .glassRegular:
                    #expect(glass.style == .regular)
                    // The control stays untinted. `tintColor` is nullable and
                    // nothing in the shell assigns it, so this asserts the
                    // variant did not quietly invent one.
                    #expect(glass.tintColor == nil)
                case .glassRegularNoTint:
                    #expect(glass.style == .regular)
                    #expect(glass.tintColor == .clear)
                case .glassClear:
                    #expect(glass.style == .clear)
                    #expect(glass.tintColor == nil)
                default:
                    Issue.record("\(variant.rawValue) named glass but is not a glass variant")
                }
            case .visualEffect:
                let vibrancy = try #require(material.subviews.first as? NSVisualEffectView)
                #expect(vibrancy.subviews.first === page)
                #expect(vibrancy.material == .popover)
                #expect(
                    vibrancy.blendingMode
                        == (variant == .visualEffectWithinWindow ? .withinWindow : .behindWindow)
                )
            case nil:
                // The variant that settles the screenshot. No effect view, and
                // the page is a direct subview of the wrapper rather than
                // nested one level down inside a material that is not there.
                #expect(material.subviews.count == 1)
                #expect(material.subviews.first === page)
                #expect(material.subviews.first as? NSGlassEffectView == nil)
                #expect(material.subviews.first as? NSVisualEffectView == nil)
            }
        }
    }

    /// The two maps between a variant and a class have to stay inverses, or the
    /// test above and the log line disagree about what is on screen.
    @Test("a variant names the class it builds, and the class names back a variant")
    func kindAndVariantAgree() {
        for variant in Config.PanelMaterialVariant.allCases {
            guard let kind = variant.materialKind else {
                #expect(variant == .none)
                continue
            }
            #expect(variant.materialKind == Config.PanelMaterialVariant.forKind(kind).materialKind)
        }
        #expect(PanelMaterialKind.allCases.count == 2)
        #expect(Config.PanelMaterialVariant.forKind(.glass) == .glassRegular)
        #expect(Config.PanelMaterialVariant.forKind(.visualEffect) == .visualEffectBehindWindow)
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

    // MARK: - The chevron band
    //
    // The seam was a difference in layer count, not in material: AppKit installs
    // its own NSGlassView across the whole popover including the chevron, and our
    // material only covered the content rect inside it, so the arrow band showed
    // one glass layer and the body showed two. The fix is to reach the material
    // past the content rect by the chevron inset, so the layer count is the same
    // everywhere across the popover's shape.
    //
    // These assert the geometry that makes that true. They do not and cannot
    // assert the shade: AppKit's material does not render into a bitmap
    // faithfully, so a test can say which view covers which rect and nothing
    // about how that rect looks.

    @Test("the chevron inset is the measured 13, and it is per side rather than the 26 the window grows by")
    func chevronInsetIsTheMeasuredBand() {
        #expect(Config.popoverChevronInset == 13.0)
        #expect(Config.popoverChevronInset > 0)
    }

    @Test("the material covers the whole popover shape, and the window is the content size grown by twice the inset")
    func materialCoversTheWholeShape() {
        // What a popover at Config.panelSize puts on screen, measured on a live
        // popover: the window is 366x446 and the content view is 340x420 at 13,13.
        let windowSize = NSSize(
            width: Config.panelSize.width + 2 * Config.popoverChevronInset,
            height: Config.panelSize.height + 2 * Config.popoverChevronInset
        )
        #expect(windowSize == NSSize(width: 366, height: 446))

        let bounds = NSRect(origin: .zero, size: Config.panelSize)
        let materialFrame = bounds.insetBy(dx: -Config.popoverChevronInset, dy: -Config.popoverChevronInset)
        // Overflowed on every side, and big enough to be the whole window once it
        // is placed at the content rect's offset inside it.
        #expect(materialFrame == NSRect(x: -13, y: -13, width: 366, height: 446))
        #expect(materialFrame.contains(bounds.insetBy(dx: 1, dy: 1)))
        // Not merely "big enough": exactly the window, with nothing spilling past
        // the popover's own shape.
        #expect(materialFrame.size == windowSize)
    }

    @Test("installed, the material overflows its container and the page stays at the container's own bounds")
    @MainActor
    func materialOverflowsAndThePageDoesNot() throws {
        let page = NSView(frame: NSRect(origin: .zero, size: Config.panelSize))
        let material = PanelMaterialView(
            variant: Config.panelMaterialVariant,
            frame: page.frame,
            cornerRadius: Config.panelCornerRadius
        )
        material.install(page)
        let container = NSView(frame: NSRect(origin: .zero, size: Config.panelSize))
        container.addSubview(material)
        container.layoutSubtreeIfNeeded()
        let expectedMaterialFrame = container.bounds.insetBy(
            dx: -Config.popoverChevronInset,
            dy: -Config.popoverChevronInset
        )

        // The page is at the content rect, which is the panel's visible rect and
        // is not what this change is allowed to touch.
        #expect(page.frame == container.bounds)
        #expect(page.frame.size == Config.panelSize)

        switch Config.panelMaterialVariant.materialKind {
        case .glass:
            let glass = try #require(material.subviews.first as? NSGlassEffectView)
            // Overflowed, so the chevron band is inside our material rather than
            // only inside AppKit's.
            #expect(glass.frame == expectedMaterialFrame)
            #expect(glass.frame.contains(container.bounds))
            // The page is still the glass's contentView, so the documented
            // relationship survives; the private holder AppKit put it in is what
            // carries the content rect.
            #expect(glass.contentView === page)
        case .visualEffect:
            let vibrancy = try #require(material.subviews.first as? NSVisualEffectView)
            #expect(vibrancy.frame == expectedMaterialFrame)
            #expect(page.frame == container.bounds)
        case nil:
            // `none` paints nothing, so there is nothing to reach past the content
            // rect and the page is the container's only subview.
            #expect(material.subviews.count == 1)
            #expect(material.subviews.first === page)
            #expect(page.frame == container.bounds)
        }
    }

    @Test("the relationship survives a resize: still covered, still the same page rect relative to the container")
    @MainActor
    func relationshipSurvivesAResize() throws {
        let page = NSView(frame: NSRect(origin: .zero, size: Config.panelSize))
        let material = PanelMaterialView(
            variant: Config.panelMaterialVariant,
            frame: page.frame,
            cornerRadius: Config.panelCornerRadius
        )
        material.install(page)
        let container = NSView(frame: NSRect(origin: .zero, size: Config.panelSize))
        container.autoresizingMask = [.width, .height]
        material.autoresizingMask = [.width, .height]
        container.addSubview(material)
        container.layoutSubtreeIfNeeded()

        for size in [
            NSSize(width: 440, height: 520),
            NSSize(width: 240, height: 320),
            Config.panelSize,
        ] {
            container.frame = NSRect(origin: .zero, size: size)
            container.layoutSubtreeIfNeeded()

            // The page tracks the container, exactly as it did before this change.
            #expect(page.frame == container.bounds)
            // And the material still reaches past it on every side, so the layer
            // count is still equal across the whole shape at the new size.
            guard let materialView = material.subviews.first else { continue }
            #expect(
                materialView.frame
                    == container.bounds.insetBy(
                        dx: -Config.popoverChevronInset,
                        dy: -Config.popoverChevronInset
                    )
            )
            #expect(materialView.frame.contains(container.bounds))
        }
    }

    @Test("the inset is read off a popover, not hard-coded, and the read refuses anything that is not a chevron")
    @MainActor
    func insetIsReadNotAssumed() {
        // No window at all, which is every window-server-free case including this
        // suite's. nil means "keep the constant", never a guess.
        #expect(PanelMaterialView.measuredChevronInset(in: nil) == nil)

        // A window that is not a panel. An NSPopover's window is, and this is the
        // half of the guard that keeps the arithmetic from reading some other
        // window's chrome as an arrow.
        let plainWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: Config.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        #expect(!(plainWindow is NSPanel))
        #expect(PanelMaterialView.measuredChevronInset(in: plainWindow) == nil)

        // A panel whose band is not the same width on every edge, which is a
        // title bar rather than a chevron. nil again rather than 32.
        let titledPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Config.panelSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        #expect(PanelMaterialView.measuredChevronInset(in: titledPanel) == nil)

        // A panel with no band at all, because its content view is the whole
        // window. nil, so the constant is not replaced by zero.
        let flushPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Config.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        #expect(PanelMaterialView.measuredChevronInset(in: flushPanel) == nil)
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
