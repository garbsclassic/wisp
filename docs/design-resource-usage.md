# Editor revision and rendering work

[`DocumentAnalysis`](../Sources/WispCore/DocumentAnalysis.swift) is the shared revision for the note's text, block classification, headings, and caret line index. Code ranges are derived lazily from the same revision when spelling needs them. The model and text view share the revision rather than deriving independent navigation and styling data.

The text storage's character-edit notification invalidates the text view's analysis. Attribute changes do not invalidate it. [`Editor.Coordinator`](../Sources/Wisp/Editor.swift) obtains the current analysis for list renumbering and publishes only the final post-renumber revision. Initial loading and disk replacement construct complete revisions. Unchanged assignments preserve the existing revision; equality here means identical UTF-16 units, because canonically equivalent Swift strings can have different TextKit offsets.

Editor synchronization compares revision identity first. The caret footer caches its result by revision and offset, binary-searches line starts, and counts graphemes only within the current line. Line numbering preserves the existing LF-based behavior, including CRLF and the empty line after a trailing newline.

An external replacement with different text clears the note's undo history: its saved ranges refer to the previous contents and cannot safely apply to the replacement. Local edit handoffs, unchanged reloads, and style changes retain history. A failed note read leaves the editor read-only until a successful reload, so edits cannot create a dirty buffer that blocks recovery from the read error.

## Local rendering with a full fallback

The text view keeps the last styled revision and the pending character edit until styling finishes. A single edit wholly within an unindented plain line can restyle that line when both revisions establish unchanged block context. Setext heading content is excluded. The local pass uses the same inline renderer as the full pass and preserves AppKit attributes outside the renderer's own keys.

Structural edits, line-boundary changes, indented content, multiple character edits in one transaction, and uncertain boundaries use the full renderer. The indentation restriction matters because list rendering tracks continuations independently of Markdown block classification. Non-LF line separators also require care: the inline patterns can match across them, so the local path requires LF boundaries or document edges. Theme, font, source-mode changes, and document replacements always use complete restyling.

The full renderer remains the reference for differential tests. Extending local styling to lists, headings, rules, or fences requires establishing both old and new dependencies and proving equivalent attributes. Incremental block parsing is a separate optimization.

## Transient find state

The current note match uses layout-manager temporary background attributes, above stored Markdown highlights. Navigation removes the previous temporary range and paints the next range without rescanning markup. A character edit clears temporary find backgrounds before the model publishes freshly searched ranges. Theme and document changes repaint the match. Dismissal releases the result array and resets derived match state while preserving the query.

## Hidden footer

The panel publishes its visibility to the model on show and through the common hide teardown. The modified-time footer mounts its periodic timeline only while visible; showing refreshes the relative time immediately. The editor, file watcher, and hotkey registration remain mounted and active.

## Measurement boundary

[`ResourceBenchmarkTests`](../Tests/WispTests/ResourceBenchmarkTests.swift) provides opt-in release workloads with disposable notes. `WISP_BENCHMARK=1` measures editing, caret lookup, find painting, parsing, full styling, and search at several document sizes with LF and CRLF. `WISP_LIFECYCLE=1` measures a disposable hosting window before summon, while visible, after hiding, and through help/find/visibility cycles. Run the filtered suite through `scripts/test.sh -c release` with an SDK supported by the local toolchain.

These measurements describe synchronous AppKit/model work and process counters. They do not establish end-to-end keyboard latency, rendering-server cost, allocation stack attribution, or a leak. In-process malloc-zone high-water counters are platform-dependent; use the [allocation profiling workflow](plan-resource-usage.md#allocation-profiling-workflow) for allocation stacks and peak live allocations. Keep undo history and the mounted editor unless further profiling justifies a behavior-preserving change.

The allocation driver builds optimized production sources with a separate entry point, omitting AppDelegate services. It exercises scripted edits, undo, rendered note/help find navigation, and non-key panel visibility, then releases the window and model. It does not reproduce native typing cadence, selection dragging, paste, or normal key-panel input. Treat those as separate interactive workloads.

Heading navigation is a separate retention boundary: the header's eager row instantiates all H1/H2 buttons even when the scroll view clips most of them. Evaluate heading-row virtualization before deferring construction of the entire editor; deferring the editor shifts its cold-start cost until summon without reducing the mounted row's cost.
