/// What the summon chord has left the panel doing. Mirrors Clef's
/// `HUDController.State`: tap to pin, hold to peek.
///
/// Pure transitions only. The controller owns the timers that produce
/// `holdElapsed` and `modifiersReleased`, and the showing and hiding that
/// follow from a change.
public enum SummonState: Equatable, Sendable {
    case hidden
    /// On screen with the mode still open: the chord is down and hasn't been
    /// held long enough to be a peek, nor let go of to become a pin.
    case summoning
    /// Up for as long as the chord is held; gone when it's let go.
    case peeking
    /// Up until it's dismissed on purpose.
    case pinned

    public enum Event: Equatable, Sendable {
        case chordDown
        /// The chord's key came up. `modifiersHeld` is whether the chord's
        /// modifiers are all still down, which keeps a peek open until they
        /// lift too.
        case chordUp(modifiersHeld: Bool)
        /// The chord has been held for `peekHold`.
        case holdElapsed
        /// A peek's modifiers lifted after its key already had.
        case modifiersReleased
        /// The status item's left click, and anything else that opens the
        /// panel without a chord to time.
        case togglePin
        case dismiss
    }

    /// `peeksImmediately` is `peekHold: 0`: every summon is a peek, so the
    /// chord can never pin.
    public func next(on event: Event, peeksImmediately: Bool) -> SummonState {
        switch (self, event) {
        case (.pinned, .chordDown), (_, .dismiss), (.pinned, .togglePin):
            .hidden
        case (_, .chordDown):
            peeksImmediately ? .peeking : .summoning
        case (.summoning, .chordUp):
            .pinned
        case (.peeking, .chordUp(let modifiersHeld)):
            modifiersHeld ? .peeking : .hidden
        case (.summoning, .holdElapsed):
            .peeking
        case (.peeking, .modifiersReleased):
            .hidden
        case (_, .togglePin):
            .pinned
        default:
            self
        }
    }
}
