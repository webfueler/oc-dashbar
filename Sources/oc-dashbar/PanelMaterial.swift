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

    init(kind: PanelMaterialKind, frame: NSRect, cornerRadius: CGFloat) {
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
