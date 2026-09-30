import AppKit

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Mirrors LSUIElement from Info.plist so the bare SwiftPM binary, which
        // has no bundle, also stays out of the Dock and has no app menu.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
