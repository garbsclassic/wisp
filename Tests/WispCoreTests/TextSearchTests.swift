import Foundation
import Testing

@testable import WispCore

@Suite("TextSearch")
struct TextSearchTests {
    @Test("An empty or absent query matches nothing")
    func noMatches() {
        #expect(TextSearch.matches(in: "hello world", query: "").isEmpty)
        #expect(TextSearch.matches(in: "hello world", query: "zzz").isEmpty)
    }

    @Test("A single match reports its range")
    func singleMatch() throws {
        let hit = try #require(TextSearch.matches(in: "hello world", query: "world").first)
        #expect(hit.location == 6)
        #expect(hit.length == 5)
    }

    @Test("Repeated matches come back in order")
    func manyMatches() {
        let hits = TextSearch.matches(in: "the cat sat on the mat", query: "at")
        #expect(hits.map(\.location) == [5, 9, 20])
    }

    @Test("Matching ignores case")
    func caseInsensitive() {
        #expect(TextSearch.matches(in: "Hello HELLO hello", query: "hello").count == 3)
    }

    /// Overlap is where a naive scanner either loops forever or
    /// double-counts: "aa" in "aaaa" is two matches, at 0 and 2.
    @Test("Overlapping patterns advance past each match")
    func overlapping() {
        #expect(TextSearch.matches(in: "aaaa", query: "aa").map(\.location) == [0, 2])
    }
}
