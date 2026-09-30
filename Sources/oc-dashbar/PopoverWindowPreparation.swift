import AppKit

/// When the popover's window may be touched.
///
/// `NSPopover` builds its `NSWindow` lazily, inside `show()`, and documents
/// nothing about whether a later show reuses that panel or builds a fresh one.
/// Both facts are inputs to this one decision, so the decision is a pure
/// function of `(window, alreadyPrepared)` and nothing else. That is not
/// tidiness: it is the only shape a test can drive from a session with no
/// window server, where `NSPopover` builds nothing to point at.
enum PopoverWindowPreparation {
    /// Runs `apply` on `window` unless `window` is already the one that was
    /// prepared.
    ///
    /// `ran` says whether work was done. `prepared` says what the caller should
    /// now record, and it is the window on a skip as well as on a run, because a
    /// skip means the window is still prepared rather than un-prepared. Returning
    /// nil for a skip is the obvious thing to write and it is wrong: the caller
    /// assigns what comes back to its flag, so a skip clears the flag and the
    /// log then reports `prepared=false` on exactly the open where the
    /// preparation was correctly skipped.
    ///
    /// Nil in, nil out. That nil is not a prepared window, and a first version
    /// of this asked the question one step early: on the first open the popover
    /// had built nothing yet, the guard returned, and the panel came up in
    /// AppKit's default state. Called after `show()`, the window is there on
    /// every open, first included.
    ///
    /// The flag is window identity rather than a Bool so that a later show
    /// which reuses the panel costs nothing and a later show which does not is
    /// prepared again. Whether a macOS 26 popover reuses its panel was measured
    /// and it does, so the second case is handled rather than expected. A panel
    /// that has been torn down records nothing, so the open after that one
    /// prepares again instead of trusting a window nobody has.
    static func prepare(
        window: NSWindow?,
        alreadyPrepared: NSWindow?,
        apply: (NSWindow) -> Void
    ) -> (ran: Bool, prepared: NSWindow?) {
        guard let window else { return (ran: false, prepared: nil) }
        guard window !== alreadyPrepared else { return (ran: false, prepared: window) }
        apply(window)
        return (ran: true, prepared: window)
    }
}
