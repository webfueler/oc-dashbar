import AppKit
import Testing

@testable import oc_dashbar

/// Every test here is about when the preparation runs rather than about what
/// it sets: the bug they guard was an ordering bug. `PanelMaterialTests`
/// already asserts the three properties, and it kept passing all through the
/// bug, because it calls the helper on a window it made itself.
@Suite("Popover window preparation")
struct PopoverWindowPreparationTests {
    /// The case that lost. Before the first `show()` there is no window, and
    /// "no window" must not read as "already prepared", or the first open comes
    /// up unprepared and only the second one repairs it.
    @Test("no window is not a prepared window")
    func noWindowIsNotPrepared() {
        var applied = 0
        let result = PopoverWindowPreparation.prepare(window: nil, alreadyPrepared: nil) { _ in
            applied += 1
        }
        #expect(!result.ran)
        #expect(result.prepared == nil)
        #expect(applied == 0)
    }

    @Test("the first open prepares the window the popover just built")
    @MainActor
    func firstOpenPrepares() {
        let window = makeWindow()
        var applied = 0
        let result = PopoverWindowPreparation.prepare(window: window, alreadyPrepared: nil) { window in
            window.prepareForTranslucentPanel()
            applied += 1
        }
        #expect(result.ran)
        #expect(result.prepared === window)
        #expect(applied == 1)
        // The same ground `PanelMaterialTests` checks, reached through the
        // ordering rule rather than by calling the helper directly.
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
    }

    @Test("a second show of the same panel does not prepare it again")
    @MainActor
    func reusedPanelIsNotPreparedTwice() {
        let window = makeWindow()
        var applied = 0
        let first = PopoverWindowPreparation.prepare(window: window, alreadyPrepared: nil) { _ in
            applied += 1
        }
        let second = PopoverWindowPreparation.prepare(window: window, alreadyPrepared: first.prepared) { _ in
            applied += 1
        }
        #expect(first.ran)
        #expect(!second.ran)
        #expect(applied == 1)
    }

    /// The one that a first version of the fix got wrong, and that only a real
    /// popover in a real session caught: a skip has to keep reporting the window
    /// as prepared. Returning nil for a skip made the caller clear its own flag,
    /// so the second open logged `prepared=false` and the first open's success
    /// looked like it had been thrown away.
    @Test("a skip still reports the window as prepared, so the flag survives a correct skip")
    @MainActor
    func skipKeepsTheFlagPointingAtTheWindow() {
        let window = makeWindow()
        var applied = 0
        let first = PopoverWindowPreparation.prepare(window: window, alreadyPrepared: nil) { _ in
            applied += 1
        }
        let second = PopoverWindowPreparation.prepare(window: window, alreadyPrepared: first.prepared) { _ in
            applied += 1
        }
        #expect(second.prepared === window)
        #expect(!second.ran)
        #expect(applied == 1)
    }

    @Test("a show that builds a fresh window is prepared again rather than skipped")
    @MainActor
    func freshPanelIsPreparedAgain() {
        let first = makeWindow()
        let second = makeWindow()
        #expect(first !== second)
        var applied = 0
        let firstResult = PopoverWindowPreparation.prepare(window: first, alreadyPrepared: nil) { _ in
            applied += 1
        }
        let secondResult = PopoverWindowPreparation.prepare(
            window: second,
            alreadyPrepared: firstResult.prepared
        ) { _ in
            applied += 1
        }
        #expect(firstResult.prepared === first)
        #expect(secondResult.ran)
        #expect(secondResult.prepared === second)
        #expect(applied == 2)
    }

    /// The flag is a weak reference on the delegate's side, so a panel AppKit
    /// has torn down must leave nothing recorded. Recording it anyway would make
    /// the next show skip a window it has never prepared.
    @Test("a window that is gone leaves nothing recorded, so the next show prepares again")
    @MainActor
    func tornDownWindowIsNotStillPrepared() {
        let window = makeWindow()
        let result = PopoverWindowPreparation.prepare(window: nil, alreadyPrepared: window) { _ in }
        #expect(!result.ran)
        #expect(result.prepared == nil)
    }

    @Test("the flag the log prints starts false, or it would print true before anything ran")
    @MainActor
    func freshDelegateIsNotPrepared() {
        #expect(!AppDelegate().popoverWindowPrepared)
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(origin: .zero, size: Config.panelSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }
}
