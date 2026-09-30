/// Tap to pin, hold to peek, as in Clef's `HUDController.State`. Timers live in the controller.
public enum SummonState: Equatable, Sendable {
    case hidden
    /// Chord down, not yet held long enough to peek nor released to pin.
    case summoning
    /// Up for as long as the chord is held; gone when it's let go.
    case peeking
    /// Up until it's dismissed on purpose.
    case pinned

    public enum Event: Equatable, Sendable {
        case chordDown
        /// The key came up; `modifiersHeld` keeps a peek open until the modifiers lift too.
        case chordUp(modifiersHeld: Bool)
        /// The chord has been held for `peekHold`.
        case holdElapsed
        /// A peek's modifiers lifted after its key already had.
        case modifiersReleased
        /// The status item's click, or anything else that opens the panel without a chord.
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
