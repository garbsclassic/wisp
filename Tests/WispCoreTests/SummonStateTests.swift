import Testing

@testable import WispCore

@Suite("SummonState")
struct SummonStateTests {
    /// `chordUp` from `.summoning` ignores the modifiers, so both values pin.
    @Test("A tap — down, then up before the hold — pins", arguments: [false, true])
    func tapPins(modifiersHeld: Bool) {
        let summoning = SummonState.hidden.next(on: .chordDown, peeksImmediately: false)
        #expect(summoning == .summoning)
        let pinned = summoning.next(
            on: .chordUp(modifiersHeld: modifiersHeld), peeksImmediately: false)
        #expect(pinned == .pinned)
    }

    @Test("Down while pinned hides, regardless of peeksImmediately", arguments: [false, true])
    func downWhilePinnedHides(peeksImmediately: Bool) {
        #expect(
            SummonState.pinned.next(on: .chordDown, peeksImmediately: peeksImmediately) == .hidden)
    }

    @Test("A hold elapses a summon into a peek")
    func holdElapsesIntoPeek() {
        #expect(SummonState.summoning.next(on: .holdElapsed, peeksImmediately: false) == .peeking)
    }

    @Test("A peek's chordUp stays a peek while the modifiers are still held")
    func peekChordUpWithModifiersHeldStaysAPeek() {
        #expect(
            SummonState.peeking.next(on: .chordUp(modifiersHeld: true), peeksImmediately: false)
                == .peeking)
    }

    @Test("A peek's chordUp hides once the modifiers have already let go")
    func peekChordUpWithoutModifiersHides() {
        #expect(
            SummonState.peeking.next(on: .chordUp(modifiersHeld: false), peeksImmediately: false)
                == .hidden)
    }

    @Test("The modifiers releasing after the key hides a peek")
    func modifiersReleasedHidesAPeek() {
        #expect(SummonState.peeking.next(on: .modifiersReleased, peeksImmediately: false) == .hidden)
    }

    /// `peeksImmediately` is `peekHold: 0`. `.pinned` is left out: chordDown hides it.
    @Test(
        "peeksImmediately sends chordDown straight to peeking",
        arguments: [SummonState.hidden, .summoning, .peeking]
    )
    func peeksImmediatelySendsChordDownToPeeking(from state: SummonState) {
        #expect(state.next(on: .chordDown, peeksImmediately: true) == .peeking)
    }

    @Test(
        "togglePin pins from every non-pinned state",
        arguments: [SummonState.hidden, .summoning, .peeking]
    )
    func togglePinFromNonPinnedState(state: SummonState) {
        #expect(state.next(on: .togglePin, peeksImmediately: false) == .pinned)
    }

    @Test("togglePin from pinned hides")
    func togglePinFromPinnedHides() {
        #expect(SummonState.pinned.next(on: .togglePin, peeksImmediately: false) == .hidden)
    }

    @Test(
        "dismiss hides from every state",
        arguments: [SummonState.hidden, .summoning, .peeking, .pinned]
    )
    func dismissHidesFromEveryState(state: SummonState) {
        #expect(state.next(on: .dismiss, peeksImmediately: false) == .hidden)
    }

    @Test(
        "holdElapsed does nothing outside summoning",
        arguments: [SummonState.hidden, .peeking, .pinned]
    )
    func holdElapsedIsIgnoredOutsideSummoning(state: SummonState) {
        #expect(state.next(on: .holdElapsed, peeksImmediately: false) == state)
    }

    @Test(
        "chordUp does nothing while hidden or pinned",
        arguments: [SummonState.hidden, .pinned]
    )
    func chordUpIsIgnoredOutsideSummoningAndPeeking(state: SummonState) {
        #expect(state.next(on: .chordUp(modifiersHeld: false), peeksImmediately: false) == state)
        #expect(state.next(on: .chordUp(modifiersHeld: true), peeksImmediately: false) == state)
    }

    @Test(
        "modifiersReleased does nothing outside peeking",
        arguments: [SummonState.hidden, .summoning, .pinned]
    )
    func modifiersReleasedIsIgnoredOutsidePeeking(state: SummonState) {
        #expect(state.next(on: .modifiersReleased, peeksImmediately: false) == state)
    }
}
