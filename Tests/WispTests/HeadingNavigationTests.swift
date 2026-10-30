import Testing
import WispCore

@testable import Wisp

@Suite("Heading navigation identity")
struct HeadingNavigationTests {
    @Test("Headings keep their identity when text is inserted before them")
    func insertionBeforeHeadings() throws {
        let original = DocumentAnalysis("# First\n## Second\n### Deep\n# Third")
        var navigation = HeadingNavigation()
        navigation.update(from: DocumentAnalysis(""), to: original)
        let originalItems = navigation.items

        let prefix = "🐈e\u{301}\n"
        let edited = DocumentAnalysis(prefix + original.text)
        navigation.update(from: original, to: edited)

        #expect(navigation.items.map(\.title) == ["First", "Second", "Third"])
        #expect(navigation.items.allSatisfy { $0.heading.level <= 2 })
        #expect(navigation.items.map(\.id) == originalItems.map(\.id))
        #expect(navigation.items.map(\.heading.lineStart)
            == edited.headings.filter { $0.level <= 2 }.map(\.lineStart))
        #expect(navigation.items[0].heading.lineStart == prefix.utf16.count)
    }

    @Test("Inserting a heading preserves the other headings' identities")
    func insertedHeadingGetsNewIdentity() throws {
        let original = DocumentAnalysis("# First\n# Second\n# Third")
        var navigation = HeadingNavigation()
        navigation.update(from: DocumentAnalysis(""), to: original)
        let originalItems = navigation.items
        let edited = DocumentAnalysis("# First\n## Inserted\n# Second\n# Third")

        navigation.update(from: original, to: edited)

        #expect(navigation.items.map(\.title) == ["First", "Inserted", "Second", "Third"])
        #expect(navigation.items[0].id == originalItems[0].id)
        #expect(navigation.items[1].id != originalItems[0].id)
        #expect(navigation.items[1].id != originalItems[1].id)
        #expect(navigation.items[1].id != originalItems[2].id)
        #expect(navigation.items[2].id == originalItems[1].id)
        #expect(navigation.items[3].id == originalItems[2].id)
        #expect(navigation.items.map(\.heading.lineStart) == edited.headings.map(\.lineStart))
    }

    @Test("Renaming a heading keeps its identity and updates its title")
    func renameKeepsIdentity() throws {
        let original = DocumentAnalysis("# Start\n## Target\n# Ending")
        var navigation = HeadingNavigation()
        navigation.update(from: DocumentAnalysis(""), to: original)
        let originalItems = navigation.items
        let edited = DocumentAnalysis("# Start\n## Retitled\n# Ending")

        navigation.update(from: original, to: edited)

        #expect(navigation.items.map(\.title) == ["Start", "Retitled", "Ending"])
        #expect(navigation.items.map(\.id) == originalItems.map(\.id))
        #expect(navigation.items.map(\.heading.lineStart)
            == edited.headings.map(\.lineStart))
    }

    @Test("Duplicate titles remain distinct and keep their own identities")
    func duplicateHeadingsStayDistinct() throws {
        let original = DocumentAnalysis("# Same\n# Same\n# Last")
        var navigation = HeadingNavigation()
        navigation.update(from: DocumentAnalysis(""), to: original)
        let originalItems = navigation.items
        let edited = DocumentAnalysis("Some preface\n" + original.text)

        navigation.update(from: original, to: edited)

        #expect(navigation.items.map(\.title) == ["Same", "Same", "Last"])
        #expect(navigation.items.map(\.id) == originalItems.map(\.id))
        #expect(Set(navigation.items.map(\.id)).count == 3)
    }

    @Test("Inserting a duplicate title resets the ambiguous headings but preserves later ones")
    func insertingDuplicateTitleResetsAmbiguousIdentities() throws {
        let original = DocumentAnalysis("# Same\n# Same\n# Last")
        var navigation = HeadingNavigation()
        navigation.update(from: DocumentAnalysis(""), to: original)
        let oldSameIDs = Set(navigation.items.prefix(2).map(\.id))
        let lastID = try #require(navigation.items.last?.id)
        let edited = DocumentAnalysis("# Same\n# Same\n# Same\n# Last")

        navigation.update(from: original, to: edited)

        #expect(navigation.items.map(\.title) == ["Same", "Same", "Same", "Last"])
        #expect(oldSameIDs.isDisjoint(with: navigation.items.prefix(3).map(\.id)))
        #expect(navigation.items.last?.id == lastID)
        #expect(Set(navigation.items.map(\.id)).count == 4)
    }

    @Test("Prepending a heading preserves existing identities across its shared marker")
    func headingInsertedBeforeFirstHeading() throws {
        let original = DocumentAnalysis("# First\n## Second")
        var navigation = HeadingNavigation()
        navigation.update(from: DocumentAnalysis(""), to: original)
        let originalItems = navigation.items
        let edited = DocumentAnalysis("# Added\n" + original.text)

        navigation.update(from: original, to: edited)

        #expect(navigation.items.map(\.title) == ["Added", "First", "Second"])
        #expect(
            navigation.items.dropFirst().map(\.id)
                == [originalItems[0].id, originalItems[1].id])
        #expect(Set(navigation.items.map(\.id)).count == 3)
    }

    @Test("Deleting one heading removes only its identity")
    func deletionRemovesOneHeading() throws {
        let original = DocumentAnalysis("# First\n## Remove me\n# Last")
        var navigation = HeadingNavigation()
        navigation.update(from: DocumentAnalysis(""), to: original)
        let originalItems = navigation.items
        let edited = DocumentAnalysis("# First\n# Last")

        navigation.update(from: original, to: edited)

        #expect(navigation.items.map(\.title) == ["First", "Last"])
        #expect(navigation.items.map(\.id) == [originalItems[0].id, originalItems[2].id])
    }

    @Test("An ambiguous replacement does not transfer the old headings' identities")
    func ambiguousReplacementCreatesNewIdentities() throws {
        let original = DocumentAnalysis("# North\n## East\n# West")
        var navigation = HeadingNavigation()
        navigation.update(from: DocumentAnalysis(""), to: original)
        let oldIDs = Set(navigation.items.map(\.id))
        let replacement = DocumentAnalysis("# South\n## Center\n# Island")

        navigation.update(from: original, to: replacement)

        #expect(navigation.items.map(\.title) == ["South", "Center", "Island"])
        #expect(oldIDs.isDisjoint(with: navigation.items.map(\.id)))
        #expect(navigation.items.map(\.heading.lineStart)
            == replacement.headings.map(\.lineStart))
    }
}
