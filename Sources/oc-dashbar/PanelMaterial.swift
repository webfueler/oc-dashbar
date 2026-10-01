import AppKit

/// The two system materials the popover can composite over. Which one runs is a
/// value in `Config`, never a decision made here.
///
/// The two classes have no shared base and no shared material API, so the shell
/// wraps both in one view. The single structural difference between them, where
/// the page is hosted, is the whole of the divergence.
enum PanelMaterialKind: String, CaseIterable {
    /// `NSGlassEffectView`: the macOS 26 material, and the default, because the
    /// deployment floor in `Package.swift` is macOS 26.
    case glass

    /// `NSVisualEffectView`: the material that predates Liquid Glass. It is
    /// still present on macOS 26, so it stays selectable as a comparison
    /// without moving the floor.
    case visualEffect
}

/// A view that paints one system material and hosts the page inside it.
///
/// Glass is why this class exists rather than a raw `NSGlassEffectView` dropped
/// into the popover. `NSGlassEffectView.h` says it "only guarantees the
/// `contentView` will be placed inside the glass effect; arbitrary subviews
/// aren't guaranteed specific behavior with regard to z-order in relation to the
/// content view or glass effect." Hosting the page the way that header
/// documents keeps the popover's view tree one shape for both materials.
final class PanelMaterialView: NSView {
    private enum Effect {
        case glass(NSGlassEffectView)
        case visualEffect(NSVisualEffectView)
    }

    private let effect: Effect

    /// How far the material reaches past this view's bounds, per edge. The
    /// chevron band's width, and it is what makes the material cover the whole
    /// popover shape rather than only the content rect inside it.
    ///
    /// Starts at the measured constant because there is no window to measure
    /// against until the popover shows, and is corrected in `viewDidMoveToWindow`
    /// when there is one.
    private var chevronInset: CGFloat

    init(kind: PanelMaterialKind, frame: NSRect, cornerRadius: CGFloat) {
        self.chevronInset = Config.popoverChevronInset
        switch kind {
        case .glass:
            self.effect = .glass(Self.makeGlass(frame: frame, cornerRadius: cornerRadius))
        case .visualEffect:
            let vibrancy = NSVisualEffectView(frame: frame)
            // `.popover` is documented in NSVisualEffectView.h as "the material
            // used in the background of NSPopover windows", which is what this
            // is. It also steps around AppKit's default, which is
            // `.appearanceBased`, deprecated in 10.14 with the note "use a
            // specific semantic material instead".
            //
            // `.behindWindow` is documented as "blend with the area behind the
            // window (such as the Desktop or other windows)", and is also
            // AppKit's default here. It is named rather than inherited because
            // it is the load-bearing half: the popover window is made
            // non-opaque so there is a desktop to blend with.
            //
            // `state` is left alone. `.active` is AppKit's default and is what
            // we want: the panel should not grey out when it loses focus.
            vibrancy.material = .popover
            vibrancy.blendingMode = .behindWindow
            self.effect = .visualEffect(vibrancy)
        }
        super.init(frame: frame)
        switch effect {
        case .glass(let glass):
            addSubview(glass)
        case .visualEffect(let vibrancy):
            addSubview(vibrancy)
        }
    }

    /// The chevron band, read off the live popover rather than assumed.
    ///
    /// `popover.contentSize` does not account for the arrow, so the window is
    /// larger than the content view on every edge and the difference is the band.
    /// Two conditions keep this from reading something that is not a chevron:
    /// the window has to be a panel, which is what an `NSPopover` puts up, and all
    /// four edges have to agree. A titled window fails the second test on its own
    /// and reads nil rather than 32, which is the title bar.
    ///
    /// No `hasFullSizeContent` and no `safeAreaInsets`: this SDK's
    /// `safeAreaInsets` is zero on a popover unless `hasFullSizeContent` is on,
    /// and turning it on is the mechanism that moves the page. Measured across
    /// three content sizes, so this is a read of the real thing and not a
    /// formula in disguise.
    static func measuredChevronInset(in window: NSWindow?) -> CGFloat? {
        guard let window, window is NSPanel,
            let content = window.contentView, let frameView = content.superview
        else { return nil }
        let rect = content.convert(content.bounds, to: frameView)
        let bounds = frameView.bounds
        let edges = [
            rect.minX - bounds.minX,
            bounds.maxX - rect.maxX,
            rect.minY - bounds.minY,
            bounds.maxY - rect.maxY,
        ]
        // A chevron band is the same width on every edge. Anything else is some
        // other window's chrome and is not ours to compensate for.
        guard let narrowest = edges.min(), let widest = edges.max(),
            narrowest > 0, widest - narrowest < 0.5
        else { return nil }
        return narrowest
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let measured = Self.measuredChevronInset(in: window),
            measured != chevronInset
        else { return }
        chevronInset = measured
        layoutMaterial()
    }

    /// Puts the material where it belongs for the current inset: covering the
    /// whole popover shape, with the page still at the content rect inside it.
    ///
    /// The order matters and every step of it was measured. `contentView`
    /// assignment resizes and repositions the page into a private
    /// `ContentHolderView` and sets `translatesAutoresizingMaskIntoConstraints`
    /// to false on both it and the page, and that does not survive a frame write
    /// alone: the next layout pass throws the frame away and snaps the holder to
    /// the glass's bounds, which is what grows the panel. So `contentView` is
    /// assigned first, both views go back under autoresizing control, and only
    /// then is the glass expanded.
    private func layoutMaterial() {
        let materialFrame = bounds.insetBy(dx: -chevronInset, dy: -chevronInset)
        // The content rect, expressed in the material's own coordinates. The
        // material starts at -chevronInset, so the same rect is +chevronInset
        // from the material's origin. This is `bounds` again by the time it is
        // counted in this view's coordinates, which is the whole point: the page
        // does not move and the panel does not change size.
        let contentFrame = NSRect(
            x: chevronInset,
            y: chevronInset,
            width: bounds.width,
            height: bounds.height
        )
        switch effect {
        case .glass(let glass):
            glass.autoresizingMask = [.width, .height]
            glass.frame = materialFrame
            guard let content = glass.contentView, let holder = content.superview else { return }
            holder.translatesAutoresizingMaskIntoConstraints = true
            content.translatesAutoresizingMaskIntoConstraints = true
            holder.autoresizingMask = [.width, .height]
            holder.frame = contentFrame
            content.frame = holder.bounds
            content.autoresizingMask = [.width, .height]
        case .visualEffect(let vibrancy):
            vibrancy.autoresizingMask = [.width, .height]
            vibrancy.frame = materialFrame
            guard let content = vibrancy.subviews.first else { return }
            content.frame = contentFrame
            content.autoresizingMask = [.width, .height]
        }
    }

    /// The macOS 26 half of the fork. `@available` sits on the declaration and
    /// the call above is unguarded on purpose: with the floor at macOS 26 this
    /// compiles, and lowering `platforms:` turns this line into a build error
    /// rather than into a runtime fallback to a material nobody logged.
    @available(macOS 26.0, *)
    private static func makeGlass(frame: NSRect, cornerRadius: CGFloat) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: frame)
        glass.cornerRadius = cornerRadius
        // `.regular` is AppKit's default and is assigned so the choice is on the
        // record rather than implied.
        glass.style = .regular
        return glass
    }

    /// Puts the page inside the material, which is the one place the two
    /// materials differ: glass takes it through the documented `contentView`,
    /// vibrancy takes it as an ordinary subview, the way that class has always
    /// been used.
    func install(_ content: NSView) {
        switch effect {
        case .glass(let glass):
            glass.contentView = content
        case .visualEffect(let vibrancy):
            vibrancy.addSubview(content)
        }
        layoutMaterial()
    }

    /// Not reachable: the popover builds this view in code and nothing in the
    /// shell decodes a nib.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PanelMaterialView is built in code, never decoded")
    }
}

extension NSWindow {
    /// The window half of the material. Both materials read what is behind the
    /// window, so an opaque window leaves them nothing to work on: the page's
    /// transparent pixels would show the popover, not the desktop.
    ///
    /// This lives on `NSWindow` rather than inline in the delegate so a test
    /// can hold a real window and assert it, which is the only coverage
    /// available for this half from a session with no window server, where
    /// `NSPopover` never builds a window to point it at.
    func prepareForTranslucentPanel() {
        isOpaque = false
        backgroundColor = .clear
        // From `effectiveAppearance`, not `NSApp.appearance`, which is nil
        // unless something set it. Assigning a non-nil appearance pins the
        // window to that one rather than following the system live, and the
        // delegate reapplies this after every show, so a system appearance
        // change lands the next time the panel opens rather than never.
        appearance = NSApplication.shared.effectiveAppearance
    }
}
