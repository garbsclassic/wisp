import AppKit
import Darwin
import SwiftUI
import Testing
import WispCore

@testable import Wisp

/// Opt in with WISP_BENCHMARK=1 scripts/test.sh -c release --filter ResourceBenchmark.
@Suite("ResourceBenchmark", .serialized)
@MainActor
struct ResourceBenchmarkTests {
    @Test func workloads() throws {
        guard ProcessInfo.processInfo.environment["WISP_BENCHMARK"] == "1" else { return }
        _ = NSApplication.shared
        let style = Editor.BodyStyle(
            theme: .dark, fontScale: 1, indent: Indent(), isSourceView: false, rule: .line)
        let rows = [
            "# Heading", "plain prose café 👋 é", "**bold** _italic_ ==marked== `code`",
            "- item", "  continuation", "", "```swift", "let x = 1", "```", "",
        ]
        for count in [100, 3_000, 30_000] {
            for newline in ["\n", "\r\n"] {
                let text =
                    (0..<count).map { rows[$0 % rows.count] }.joined(separator: newline) + "tail"
                let (_, view) = NotesTextView.makeScrollView()
                view.string = text
                var published = text
                let coordinator = Editor.Coordinator(
                    onEdit: { published = $0.text },
                    caretOffset: .constant(0), style: style)
                view.delegate = coordinator
                Editor.restyle(view, style: style)
                let note = Notification(name: NSText.didChangeNotification, object: view)
                measure("edit", count, newline) {
                    view.textStorage!.replaceCharacters(
                        in: NSRange(location: view.textStorage!.length, length: 0), with: "x")
                    coordinator.textDidChange(note)
                }
                measure("caret", count, newline) {
                    _ = view.documentAnalysis().caretPosition(at: view.textStorage!.length - 1)
                }
                measure("find", count, newline) {
                    Editor.applyFindHighlight(
                        to: view, range: NSRange(location: view.textStorage!.length - 2, length: 1),
                        theme: .dark, scroll: false)
                }
                measure("parse", count, newline) {
                    let ns = view.string as NSString
                    _ = MarkdownBlocks(ns).headings(in: ns)
                }
                measure("full_style", count, newline) {
                    Editor.restyle(view, style: style)
                }
                measure("search", count, newline) {
                    _ = TextSearch.matches(in: view.string, query: "code")
                }
                #expect(!published.isEmpty)
            }
        }
    }

    /// The window is disposable and doesn't use the production frame/defaults domain.
    @Test func lifecycle() throws {
        guard ProcessInfo.processInfo.environment["WISP_LIFECYCLE"] == "1" else { return }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wisp-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = String(repeating: "prose **bold** ==marked== 🐈\n", count: 100)
        try text.write(
            to: StorageLocation.scratchpadURL(in: folder), atomically: true, encoding: .utf8)
        let configURL = root.appendingPathComponent("wisp.jsonc")
        try ConfigStore.write(
            WispConfig(scratchpadFolder: folder.path, footerStatus: .modified), at: configURL)
        let settings = Wisp.Settings(configFileURL: configURL)
        let model = EditorModel(settings: settings)
        let host = NSHostingView(rootView: EditorView(model: model))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        idle("hidden_before_summon")
        let start = DispatchTime.now().uptimeNanoseconds
        model.isPanelVisible = true
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        print(
            "RESOURCE first_summon_ms=\(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)"
        )
        idle("visible")
        model.text += "edited"
        try model.flushSave()
        pump(0.1)
        model.isPanelVisible = false
        window.orderOut(nil)
        idle("hidden_after_edit")
        model.isPanelVisible = true
        window.orderFrontRegardless()
        for cycle in 0..<3 {
            measure("help_find_visibility_cycle_\(cycle)", 100, "\n") {
                model.showHelp = true
                pump(0.02)
                model.openFind()
                model.findQuery = "key"
                model.findNext()
                model.dismissFind()
                model.showHelp = false
                model.isPanelVisible = false
                window.orderOut(nil)
                model.isPanelVisible = true
                window.orderFrontRegardless()
                pump(0.02)
            }
        }
    }

    private func idle(_ name: String) {
        let before = resources()
        pump(16)
        let after = resources()
        print(
            "RESOURCE idle=\(name) seconds=16 cpu_ms=\(after.cpu - before.cpu) "
                + "wakeups=\(after.wakeups - before.wakeups) footprint=\(after.footprint) heap=\(after.heap)"
        )
    }

    private func pump(_ seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: end) }
    }

    private func measure(_ name: String, _ lines: Int, _ newline: String, body: () -> Void) {
        var samples: [Double] = []
        let before = resources()
        for _ in 0..<12 {
            let start = DispatchTime.now().uptimeNanoseconds
            autoreleasepool { body() }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        let after = resources()
        samples.sort()
        print(
            "RESOURCE \(name) lines=\(lines) newline=\(newline == "\n" ? "LF" : "CRLF") "
                + "median_ms=\(samples[6]) p95_ms=\(samples[11]) "
                + "cpu_ms=\(after.cpu - before.cpu) wakeups=\(after.wakeups - before.wakeups) "
                + "footprint=\(after.footprint) heap=\(after.heap) peak_heap=\(after.peakHeap)")
    }

    private func resources() -> (
        cpu: Double, wakeups: UInt64, footprint: UInt64,
        heap: Int, peakHeap: Int
    ) {
        var power = task_power_info_data_t()
        var powerCount = mach_msg_type_number_t(
            MemoryLayout<task_power_info_data_t>.size / MemoryLayout<integer_t>.size)
        let powerResult = withUnsafeMutablePointer(to: &power) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(powerCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &powerCount)
            }
        }
        var vm = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        precondition(powerResult == KERN_SUCCESS && vmResult == KERN_SUCCESS)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu =
            Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
        var heap = malloc_statistics_t()
        malloc_zone_statistics(nil, &heap)
        return (
            cpu,
            power.task_interrupt_wakeups, vm.phys_footprint,
            heap.size_in_use, heap.max_size_in_use
        )
    }

}
