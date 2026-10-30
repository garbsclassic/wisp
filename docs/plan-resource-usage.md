# Remaining resource usage investigations

The implemented revision handoff, caret lookup, find painting, and conservative local styling are described in [the editor resource design](design-resource-usage.md). The full renderer remains the fallback for structural changes.

## Broader profiling

- [ ] Measure end-to-end typing, paste/undo, selection dragging, and rapid summon/hide on the same disposable fixtures as the release harness. Attribute save latency separately from parsing and styling.
- [ ] Separate Wisp's work from rendering-server work before changing blur or animations.
- [ ] Extend the overlay soak beyond the short scripted workload to distinguish bounded framework caches from continuing observer/dispatch allocation growth. Keep scanner-reported framework cycles separate from retained Wisp model/editor objects.

## Allocation profiling workflow

Use `heap` and `malloc_history` first; Instruments is an optional graphical alternative, not a prerequisite. Enable allocation history at process launch with `MallocStackLogging=full MallocStackLoggingNoCompact=1` and an existing writable `MallocStackLoggingDirectory`. Check the host's `man malloc` for logging modes: the value `1` can select lite mode, which cannot provide historical peaks. [Apple's malloc debugging documentation](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/MallocDebug.html) describes the environment-variable mechanism. Keep these variables local to the profiling process.

Run [`scripts/profile-allocations.py`](../scripts/profile-allocations.py) through `uv run --no-project`, supplying a fresh `--output` directory outside the source checkouts. `--baseline-source` accepts a clean baseline checkout. The driver isolates config, notes, and the preferences domain, registers no global shortcuts, uses a non-key peek panel, filters external input, and verifies fixture contents at every checkpoint.

Use `--lines 100 3000 --edits 100 --overlay-cycles 50` for the common fixtures, and a separate `--lines 30000 --edits 20 --overlay-cycles 5` run to bound tracing overhead on the heading-dense stress fixture. Keep counts identical within each baseline/current pair. `--omit-heading-bar` changes only the disposable source snapshot for the heading-navigation control.

The collector saves content-free heap summaries, live allocation call trees, recorded heap-plus-VM high-water marks, leak scans, source hashes, and JSON/CSV summaries. Inspect stack coverage and symbolication before attributing allocations; startup stacks may be incomplete. A high-water mark includes startup and VM allocations and is not a heap-only peak or physical footprint.

Use scoped command approval if the execution sandbox denies process inspection. If inspection remains denied after approval, diagnose that macOS restriction separately rather than enabling broader permissions globally. Collect CPU, wakeup, and latency comparisons without stack logging, whose overhead changes those measurements. Undo can retain the edits on the redo stack; use window/model release checkpoints to assess object lifetime.

## Optional expansion, gated on profiling

- [ ] Extend local styling only where remaining edit latency warrants the added invalidation rules. Include old and new dependencies for fences, frontmatter, setext headings, list continuations/renumbering, and rule-neighbor spacing. Keep a full-pass fallback and differential attribute tests.
- [ ] Consider incremental structural classification only if its full scan remains a material bottleneck.
- [ ] Coalesce deferred selection publication only if dragging or key repeat produces a measured backlog.
- [ ] Consider query debouncing only if search itself is expensive; keep next/previous immediate and invalidate matches on edits.
- [ ] Compare eager editor construction with first-summon construction only if retained launch memory justifies the latency and action-routing changes.

Preserve event-driven file watching, debounced serialized saves, dirty-buffer protection, cached word counts, immediate summon, external reload, and undo history. Do not destroy the editor on hide or cap undo merely to lower a memory reading.

Any extension requires independent review, appropriate core/model/AppKit tests, release comparison against the same workloads, and rendered verification in both themes before installation is considered complete.
