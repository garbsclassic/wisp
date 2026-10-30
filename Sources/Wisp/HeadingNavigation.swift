import Foundation
import WispCore

/// UI identity belongs to the navigation session, not a heading's changing text offsets.
struct HeadingNavigation: Equatable {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let heading: Heading
        var title: String { heading.name }
    }

    private(set) var items: [Item] = []

    mutating func update(from previous: DocumentAnalysis, to next: DocumentAnalysis) {
        let headings = next.headings.filter { $0.level <= 2 }
        if items.count == headings.count,
            zip(items, headings).allSatisfy({ sameLabel($0.heading, $1) })
        {
            items = zip(items, headings).map { Item(id: $0.id, heading: $1) }
            return
        }

        // Only changed heading content needs text comparison; prose edits take the path above.
        let old = previous.text as NSString
        let new = next.text as NSString
        var start = 0
        while start < min(old.length, new.length),
            old.character(at: start) == new.character(at: start)
        {
            start += 1
        }
        var suffix = 0
        while suffix < min(old.length, new.length) - start,
            old.character(at: old.length - suffix - 1)
                == new.character(at: new.length - suffix - 1)
        {
            suffix += 1
        }
        let oldEnd = old.length - suffix
        let delta = new.length - old.length
        let indices = Dictionary(uniqueKeysWithValues: headings.enumerated().map {
            ($0.element.lineStart, $0.offset)
        })
        var identities: [Int: UUID] = [:]
        var edited: [Item] = []
        for item in items {
            let target: Int?
            if item.heading.end <= start {
                target = item.heading.lineStart
            } else if item.heading.lineStart >= oldEnd {
                target = item.heading.lineStart + delta
            } else {
                target = nil
            }
            if let target, let index = indices[target], sameLabel(item.heading, headings[index]) {
                identities[index] = item.id
            } else {
                edited.append(item)
            }
        }
        var unmatched = headings.indices.filter { identities[$0] == nil }
        // A shared Markdown marker can put an insertion boundary inside an unchanged heading.
        let oldLabels = Dictionary(grouping: edited, by: { Label($0.heading) })
        let newLabels = Dictionary(grouping: unmatched, by: { Label(headings[$0]) })
        var matched: Set<UUID> = []
        for (label, indices) in newLabels where indices.count == 1 {
            guard let candidates = oldLabels[label], candidates.count == 1 else { continue }
            identities[indices[0]] = candidates[0].id
            matched.insert(candidates[0].id)
        }
        edited.removeAll { matched.contains($0.id) }
        unmatched.removeAll { identities[$0] != nil }
        if edited.count == 1, unmatched.count == 1 {
            identities[unmatched[0]] = edited[0].id
        }
        let oldCounts = items.reduce(into: [Label: Int]()) {
            $0[Label($1.heading), default: 0] += 1
        }
        let newCounts = headings.reduce(into: [Label: Int]()) {
            $0[Label($1), default: 0] += 1
        }
        // Identical duplicates give no evidence of which item was inserted or removed.
        let ambiguousLabels = Set(newCounts.keys.filter { label in
            let oldCount = oldCounts[label, default: 0]
            let newCount = newCounts[label, default: 0]
            return oldCount != newCount && max(oldCount, newCount) > 1
        })
        // Multiple changed headings have no unambiguous correspondence after a replacement.
        items = headings.enumerated().map {
            let id = ambiguousLabels.contains(Label($0.element)) ? nil : identities[$0.offset]
            return Item(id: id ?? UUID(), heading: $0.element)
        }
    }

    private func sameLabel(_ lhs: Heading, _ rhs: Heading) -> Bool {
        lhs.level == rhs.level && lhs.name == rhs.name
    }

    private struct Label: Hashable {
        let level: Int
        let name: String

        init(_ heading: Heading) {
            level = heading.level
            name = heading.name
        }
    }
}
