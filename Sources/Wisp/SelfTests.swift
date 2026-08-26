import AppKit
import Carbon.HIToolbox

/// In-process smoke tests for the pure-logic parts of Wisp.
///
/// Run with: `swift run Wisp --test`
///
/// Why hand-rolled instead of XCTest / Swift Testing: both need Xcode-
/// bundled SDKs, which means anyone with just Command Line Tools can't
/// run them. This harness needs only the Swift toolchain.
///
/// Coverage is limited to types that don't need a running NSApplication:
/// SmartEditing, Headings parsing, HotKey display + Carbon-modifier
/// conversion, the Theme / FontSize enums, palette token relationships,
/// and Typography font resolution. Anything that touches NSTextView, Carbon
/// hotkey registration, or the panel needs integration / UI testing —
/// out of scope here.
enum SelfTests {
    static func run() -> Never {
        var passed = 0
        var failures: [String] = []

        func check(_ name: String, _ assertion: @autoclosure () -> Bool) {
            if assertion() {
                passed += 1
            } else {
                failures.append(name)
                print("✗ \(name)")
            }
        }

        // MARK: - SmartEditing: horizontal rule trigger

        check("HR trigger '---'", SmartEditing.isHorizontalRuleTrigger("---"))
        check("HR trigger '  ---  '", SmartEditing.isHorizontalRuleTrigger("  ---  "))
        check("HR not '--'", !SmartEditing.isHorizontalRuleTrigger("--"))
        check("HR not '----'", !SmartEditing.isHorizontalRuleTrigger("----"))
        check("HR not '--- hello'", !SmartEditing.isHorizontalRuleTrigger("--- hello"))
        check("HR not 'hello ---'", !SmartEditing.isHorizontalRuleTrigger("hello ---"))
        check("HR not ''", !SmartEditing.isHorizontalRuleTrigger(""))

        // MARK: - SmartEditing: list markers (unordered)

        check("list '- foo' → '- '",  SmartEditing.nextListMarker(for: "- foo") == "- ")
        check("list '* foo' → '* '",  SmartEditing.nextListMarker(for: "* foo") == "* ")
        check("list '+ foo' → '+ '",  SmartEditing.nextListMarker(for: "+ foo") == "+ ")
        check("list '- ' (empty) → ''", SmartEditing.nextListMarker(for: "- ") == "")

        // MARK: - SmartEditing: list markers (ordered numeric)

        check("list '1. foo' → '2. '",  SmartEditing.nextListMarker(for: "1. foo") == "2. ")
        check("list '9. foo' → '10. '", SmartEditing.nextListMarker(for: "9. foo") == "10. ")
        check("list '99. foo' → '100. '", SmartEditing.nextListMarker(for: "99. foo") == "100. ")
        check("list '1. ' (empty) → ''", SmartEditing.nextListMarker(for: "1. ") == "")

        // MARK: - SmartEditing: list markers (ordered alphabetic)

        check("list 'A. foo' → 'B. '", SmartEditing.nextListMarker(for: "A. foo") == "B. ")
        check("list 'Y. foo' → 'Z. '", SmartEditing.nextListMarker(for: "Y. foo") == "Z. ")
        check("list 'Z. foo' → nil",   SmartEditing.nextListMarker(for: "Z. foo") == nil)
        check("list 'a. foo' → 'b. '", SmartEditing.nextListMarker(for: "a. foo") == "b. ")
        check("list 'y. foo' → 'z. '", SmartEditing.nextListMarker(for: "y. foo") == "z. ")
        check("list 'z. foo' → nil",   SmartEditing.nextListMarker(for: "z. foo") == nil)

        // MARK: - SmartEditing: non-list lines

        check("list 'plain' → nil",  SmartEditing.nextListMarker(for: "Just some text") == nil)
        check("list '' → nil",       SmartEditing.nextListMarker(for: "") == nil)
        check("list '-foo' → nil",   SmartEditing.nextListMarker(for: "-foo") == nil)

        // MARK: - SmartEditing: HR constant

        check("horizontalRule = '---'", SmartEditing.horizontalRule == "---")

        // MARK: - HorizontalRuleLayoutManager.isHorizontalRuleLine

        check("isHRLine '---' → true",
              HorizontalRuleLayoutManager.isHorizontalRuleLine("---"))
        check("isHRLine '----' → true",
              HorizontalRuleLayoutManager.isHorizontalRuleLine("----"))
        check("isHRLine '─' x 40 → true (legacy)",
              HorizontalRuleLayoutManager.isHorizontalRuleLine(
                String(repeating: "─", count: 40)))
        check("isHRLine '---' + '─' x 5 → true (mixed)",
              HorizontalRuleLayoutManager.isHorizontalRuleLine(
                "---" + String(repeating: "─", count: 5)))
        check("isHRLine '--' → false (only 2 chars)",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine("--"))
        check("isHRLine '' → false",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine(""))
        check("isHRLine '---x' → false (trailing char)",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine("---x"))
        check("isHRLine 'x---' → false (leading char)",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine("x---"))
        check("isHRLine '-- -' → false (space inside)",
              !HorizontalRuleLayoutManager.isHorizontalRuleLine("-- -"))

        // MARK: - Headings parser

        check("headings '' → []", "".extractHeadings().isEmpty)
        check("headings prose only → []", "hello world\nno headings".extractHeadings().isEmpty)

        let single = "# Hello".extractHeadings()
        check("'# Hello' count == 1", single.count == 1)
        check("'# Hello' name = Hello", single.first?.name == "Hello")
        check("'# Hello' level = 1", single.first?.level == 1)
        check("'# Hello' lineStart = 0", single.first?.lineStart == 0)

        let nested = "# A\n## B\n### C".extractHeadings()
        check("nested count == 3", nested.count == 3)
        check("nested levels", nested.map(\.level) == [1, 2, 3])
        check("nested names",  nested.map(\.name) == ["A", "B", "C"])

        check("'#NoSpace' → []", "#NoSpace".extractHeadings().isEmpty)
        check("'# ' empty title → []", "# ".extractHeadings().isEmpty)
        check("'##  ' empty title → []", "##  ".extractHeadings().isEmpty)

        let mixed = """
        # First
        some prose
        ## Second
        more prose
        # Third
        """.extractHeadings()
        check("mixed names", mixed.map(\.name) == ["First", "Second", "Third"])
        check("mixed levels", mixed.map(\.level) == [1, 2, 1])

        let h6 = "###### Six".extractHeadings()
        check("six hashes level=6", h6.first?.level == 6)
        check("six hashes name=Six", h6.first?.name == "Six")

        let dupTitles = "# A\n# B\n# C".extractHeadings()
        check("ids unique by lineStart", Set(dupTitles.map(\.id)).count == 3)

        // MARK: - HotKey

        check("HotKey.default keyCode = Space",
              HotKey.default.keyCode == UInt32(kVK_Space))
        check("HotKey.default modifiers = option",
              HotKey.default.modifiers == UInt32(optionKey))
        check("HotKey.default display = '⌥Space'",
              HotKey.default.displayString == "⌥Space")

        let cmdShiftP = HotKey(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        check("⇧⌘P display", cmdShiftP.displayString == "⇧⌘P")

        let allMods = HotKey(
            keyCode: UInt32(kVK_ANSI_F),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        check("⌃⌥⇧⌘F display order", allMods.displayString == "⌃⌥⇧⌘F")

        let unknown = HotKey(keyCode: 9999, modifiers: UInt32(cmdKey))
        check("unknown keyCode falls back",
              unknown.displayString == "⌘Key9999")

        check("carbonModifiers cmd",
              HotKey.carbonModifiers(from: [.command]) == UInt32(cmdKey))
        check("carbonModifiers option+shift",
              HotKey.carbonModifiers(from: [.option, .shift])
              == UInt32(optionKey | shiftKey))
        check("carbonModifiers all",
              HotKey.carbonModifiers(from: [.command, .option, .shift, .control])
              == UInt32(cmdKey | optionKey | shiftKey | controlKey))
        check("carbonModifiers empty",
              HotKey.carbonModifiers(from: []) == 0)

        // MARK: - FontSize

        check("FontSize.small  → 17pt", FontSize.small.pointSize == 17)
        check("FontSize.medium → 20pt", FontSize.medium.pointSize == 20)
        check("FontSize.large  → 24pt", FontSize.large.pointSize == 24)
        check("FontSize cycles small→medium",  FontSize.small.next == .medium)
        check("FontSize cycles medium→large",  FontSize.medium.next == .large)
        check("FontSize cycles large→small",   FontSize.large.next == .small)
        check("FontSize.small.rawValue", FontSize.small.rawValue == "small")
        check("FontSize.medium.rawValue", FontSize.medium.rawValue == "medium")
        check("FontSize.large.rawValue", FontSize.large.rawValue == "large")

        // MARK: - Theme

        check("Theme.dark.rawValue",  Theme.dark.rawValue == "dark")
        check("Theme.light.rawValue", Theme.light.rawValue == "light")

        check("ThemePreference.light.next is dark",
              ThemePreference.light.next == .dark)
        check("ThemePreference.dark.next is system",
              ThemePreference.dark.next == .system)
        check("ThemePreference.system.next is light",
              ThemePreference.system.next == .light)
        // Raw values stay compatible with the pre-system-mode storage
        // format so existing "Theme" defaults still load.
        check("ThemePreference.light.rawValue",
              ThemePreference.light.rawValue == "light")
        check("ThemePreference.dark.rawValue",
              ThemePreference.dark.rawValue == "dark")
        check("ThemePreference.system.rawValue",
              ThemePreference.system.rawValue == "system")

        // MARK: - Palette tokens

        // Assert the *relationships* the design depends on, not the hex
        // literals — restating a literal two files from where it's
        // declared catches nothing and turns every retune into a
        // two-file edit. NSColor's own == is used deliberately: it
        // compares across color spaces, where component-wise comparison
        // would call a device-RGB and an sRGB color equal, and it
        // returns false on a semantic color instead of trapping.

        /// Relative luminance, for the "is this lighter than that" checks.
        func luminance(_ c: NSColor) -> CGFloat {
            guard let rgb = c.usingColorSpace(.sRGB) else { return 0 }
            return 0.2126 * rgb.redComponent
                + 0.7152 * rgb.greenComponent
                + 0.0722 * rgb.blueComponent
        }
        /// Same hue, ignoring alpha — for "is this a wash of that".
        func sameHue(_ a: NSColor, _ b: NSColor) -> Bool {
            a.withAlphaComponent(1) == b.withAlphaComponent(1)
        }

        let dark = Palette.for(.dark)
        let light = Palette.for(.light)

        // Tokens are pinned to sRGB, not device RGB: device components are
        // consumed unconverted, so the same literal paints differently on
        // a P3 panel than on an sRGB monitor.
        check("dark accent is pinned to sRGB",
              dark.accent == rgb(0x4ECBDF))
        check("light accent is pinned to sRGB",
              light.accent == rgb(0xEC3013))
        check("device RGB is not accepted as equal to the sRGB token",
              dark.accent != NSColor(
                  deviceRed: 0x4E / 255.0, green: 0xCB / 255.0,
                  blue: 0xDF / 255.0, alpha: 1
              ))

        // Chips are raised, so they read lighter than the paper behind
        // them. Inverting this makes a find bar look like a recess.
        check("dark surface is lighter than panel",
              luminance(dark.surface) > luminance(dark.panel))
        check("light surface is lighter than panel",
              luminance(light.surface) > luminance(light.panel))

        // The light panel is a translucent tint over vibrancy; `panel` has
        // to record what that composites to, or modal backdrops step over
        // the live panel instead of matching it.
        check("light panel matches the chrome tint it composites from",
              luminance(light.panel) >= luminance(Chrome.for(.light).tintColor))

        // Selection is an accent wash; the find match is deliberately a
        // different hue, so the current match stays tellable from a
        // selection sitting next to it.
        for (name, p) in [("dark", dark), ("light", light)] {
            check("\(name) selection is a wash of the accent",
                  sameHue(p.selection, p.accent) && p.selection.alphaComponent < 1)
            check("\(name) find match is not the accent hue",
                  !sameHue(p.findHighlight, p.accent))
            check("\(name) find match is a wash",
                  p.findHighlight.alphaComponent < 1)
        }

        // Rules and borders sit on vibrancy whose luminance tracks the
        // desktop, so they have to be alpha rather than opaque.
        for (name, p) in [("dark", dark), ("light", light)] {
            check("\(name) rule is translucent", p.rule.alphaComponent < 1)
            check("\(name) border is a hairline", p.border.alphaComponent <= 0.15)
        }

        // Errors must not read as an accent hint.
        check("dark danger differs from accent", !sameHue(dark.danger, dark.accent))
        check("light danger differs from accent", !sameHue(light.danger, light.accent))

        // Text tiers stay ordered against their own background.
        check("dark muted sits between panel and text",
              luminance(dark.panel) < luminance(dark.muted))
        check("dark text is brighter than muted",
              luminance(dark.text) > luminance(dark.muted))
        check("light text is darker than muted",
              luminance(light.text) < luminance(light.muted))

        // MARK: - Chrome

        check("chrome light tint is translucent so vibrancy stays alive",
              Chrome.for(.light).tintColor.alphaComponent < 1)
        check("chrome dark tint is translucent so vibrancy stays alive",
              Chrome.for(.dark).tintColor.alphaComponent < 1)
        check("chrome light appearance aqua",
              Chrome.for(.light).appearance == .aqua)
        check("chrome dark appearance darkAqua",
              Chrome.for(.dark).appearance == .darkAqua)

        // MARK: - Typography

        check("notes family name", Typography.notesFamily == "Inter Nerd Font")
        check("ui family name", Typography.uiFamily == "Inter Nerd Font Propo")

        let body = Typography.notesFont(20)
        check("notesFont keeps requested size", body.pointSize == 20)
        check("uiFont keeps requested size", Typography.uiFont(20).pointSize == 20)
        if Typography.notesInstalled {
            check("notesFont resolves the Nerd Font",
                  body.familyName == "Inter Nerd Font")
        } else {
            check("notesFont falls back off the Nerd Font",
                  body.familyName != "Inter Nerd Font")
        }

        // Heading styling and ⌘B derive scaled bold from the base
        // descriptor. Assert the trait actually resolved — a face that
        // came back non-bold would silently unbold every heading.
        let derived = NSFont(
            descriptor: body.fontDescriptor.withSymbolicTraits(.bold), size: 24
        )
        check("symbolic-trait derivation yields a 24pt face",
              derived?.pointSize == 24)
        check("symbolic-trait derivation actually yields bold",
              derived?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        // MARK: - LaunchAtLogin
        // Smoke-only: SMAppService talks to a system daemon and `swift
        // run` can't actually register, so we verify the API contract
        // (returns a Bool, idempotent no-op for current state) without
        // mutating real state.

        let launchBefore = LaunchAtLogin.isEnabled
        check("LaunchAtLogin.isEnabled is bool",
              launchBefore == true || launchBefore == false)
        LaunchAtLogin.setEnabled(launchBefore)
        check("LaunchAtLogin.setEnabled(current) is no-op",
              LaunchAtLogin.isEnabled == launchBefore)

        // MARK: - LaunchSource

        check("LaunchSource: nil userInfo → user-initiated (fallback)",
              LaunchSource.isUserInitiated(launchUserInfo: nil))
        check("LaunchSource: empty userInfo → user-initiated (fallback)",
              LaunchSource.isUserInitiated(launchUserInfo: [:]))
        check("LaunchSource: isDefault=true → user-initiated",
              LaunchSource.isUserInitiated(
                  launchUserInfo: [LaunchSource.isDefaultLaunchKey: true]))
        check("LaunchSource: isDefault=false → not user-initiated",
              !LaunchSource.isUserInitiated(
                  launchUserInfo: [LaunchSource.isDefaultLaunchKey: false]))
        check("LaunchSource: NSNumber(true) bridges → user-initiated",
              LaunchSource.isUserInitiated(
                  launchUserInfo: [LaunchSource.isDefaultLaunchKey: NSNumber(value: true)]))
        check("LaunchSource: NSNumber(false) bridges → not user-initiated",
              !LaunchSource.isUserInitiated(
                  launchUserInfo: [LaunchSource.isDefaultLaunchKey: NSNumber(value: false)]))
        check("LaunchSource: unrelated key → falls back to user-initiated",
              LaunchSource.isUserInitiated(launchUserInfo: ["SomeOtherKey": false]))

        // MARK: - Updater throttle

        let now = Date()
        check("Updater.shouldCheck nil lastChecked → true",
              Updater.shouldCheck(now: now, lastCheckedAt: nil, throttle: 60))
        check("Updater.shouldCheck just-now → false",
              !Updater.shouldCheck(
                now: now, lastCheckedAt: now, throttle: 60))
        check("Updater.shouldCheck 30s ago, 60s throttle → false",
              !Updater.shouldCheck(
                now: now,
                lastCheckedAt: now.addingTimeInterval(-30),
                throttle: 60))
        check("Updater.shouldCheck 60s ago, 60s throttle → true",
              Updater.shouldCheck(
                now: now,
                lastCheckedAt: now.addingTimeInterval(-60),
                throttle: 60))
        check("Updater.shouldCheck 120s ago, 60s throttle → true",
              Updater.shouldCheck(
                now: now,
                lastCheckedAt: now.addingTimeInterval(-120),
                throttle: 60))

        // MARK: - Updater.buttonAction

        let stubURL = URL(string: "https://example.com/wisp.zip")!
        check("buttonAction(.idle) = noop",
              Updater.buttonAction(for: .idle) == .noop)
        check("buttonAction(.available) = startDownload",
              Updater.buttonAction(for: .available(version: "0.1.36", zipURL: stubURL))
                == .startDownload)
        check("buttonAction(.downloading) = noop",
              Updater.buttonAction(for: .downloading(version: "0.1.36"))
                == .noop)
        check("buttonAction(.pending) = applyAndRestart",
              Updater.buttonAction(for: .pending(version: "0.1.36"))
                == .applyAndRestart)

        // MARK: - StorageLocation

        check("StorageLocation.scratchpadFilename = scratchpad.md",
              StorageLocation.scratchpadFilename == "scratchpad.md")
        check("StorageLocation.backupPrefix = scratchpad-local-backup-",
              StorageLocation.backupPrefix == "scratchpad-local-backup-")

        let probeFolder = URL(fileURLWithPath: "/tmp/wisp-probe")
        let composed = StorageLocation.scratchpadURL(in: probeFolder)
        check("scratchpadURL(in:) ends with scratchpad.md",
              composed.lastPathComponent == "scratchpad.md")
        check("scratchpadURL(in:) is inside the chosen folder",
              composed.deletingLastPathComponent().standardizedFileURL.path
                == probeFolder.standardizedFileURL.path)

        check("defaultFolder ends with /Wisp",
              StorageLocation.defaultFolder.lastPathComponent == "Wisp")

        // Backup filename: deterministic by date input, no colons (so it
        // works on filesystems that disallow them), starts with the
        // shared prefix.
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let backup = StorageLocation.backupFilename(at: fixedDate)
        check("backupFilename starts with prefix",
              backup.hasPrefix(StorageLocation.backupPrefix))
        check("backupFilename ends with .md",
              backup.hasSuffix(".md"))
        check("backupFilename contains no colons",
              !backup.contains(":"))

        // MARK: - PanelFrameStore.isUsable

        let mainScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let extScreen = NSRect(x: 1440, y: 0, width: 1920, height: 1080)

        check("frame fully on screen → usable",
              PanelFrameStore.isUsable(
                NSRect(x: 100, y: 100, width: 800, height: 640),
                onScreens: [mainScreen]))
        check("frame on second screen → usable",
              PanelFrameStore.isUsable(
                NSRect(x: 1600, y: 100, width: 800, height: 640),
                onScreens: [mainScreen, extScreen]))
        check("frame on now-missing screen → not usable",
              !PanelFrameStore.isUsable(
                NSRect(x: 1600, y: 100, width: 800, height: 640),
                onScreens: [mainScreen]))
        check("frame mostly off-screen but >minVisible showing → usable",
              PanelFrameStore.isUsable(
                NSRect(x: 1300, y: 100, width: 800, height: 640),
                onScreens: [mainScreen]))
        check("frame with only a sliver on-screen → not usable",
              !PanelFrameStore.isUsable(
                NSRect(x: 1380, y: 100, width: 800, height: 640),
                onScreens: [mainScreen]))
        check("degenerate tiny frame → not usable",
              !PanelFrameStore.isUsable(
                NSRect(x: 100, y: 100, width: 50, height: 50),
                onScreens: [mainScreen]))
        check("no screens at all → not usable",
              !PanelFrameStore.isUsable(
                NSRect(x: 100, y: 100, width: 800, height: 640),
                onScreens: []))

        // MARK: - TextSearch

        check("search empty query → no matches",
              TextSearch.matches(in: "hello world", query: "").isEmpty)
        check("search no match → empty",
              TextSearch.matches(in: "hello world", query: "zzz").isEmpty)

        let oneHit = TextSearch.matches(in: "hello world", query: "world")
        check("search single match count", oneHit.count == 1)
        check("search single match location", oneHit.first?.location == 6)
        check("search single match length", oneHit.first?.length == 5)

        let manyHits = TextSearch.matches(in: "the cat sat on the mat", query: "at")
        check("search 'at' → 3 matches", manyHits.count == 3)
        check("search 'at' locations",
              manyHits.map(\.location) == [5, 9, 20])

        check("search is case-insensitive",
              TextSearch.matches(in: "Hello HELLO hello", query: "hello").count == 3)

        // Overlapping pattern advances correctly (no infinite loop, no
        // double-count): "aa" in "aaaa" → matches at 0 and 2.
        let overlap = TextSearch.matches(in: "aaaa", query: "aa")
        check("search overlapping 'aa' in 'aaaa' → 2", overlap.count == 2)
        check("search overlapping locations", overlap.map(\.location) == [0, 2])

        // MARK: - ReleaseNotes highlights

        let body1 = """
        - ⌘F to find in your notes
        - Wisp remembers its window size and position

        <!--wisp:more-->

        Update via the in-app card, or `brew upgrade --cask wisp`.
        - this bullet is below the marker and must be ignored
        """
        let h1 = ReleaseNotes.highlights(from: body1)
        check("notes: two highlights above marker", h1.count == 2)
        check("notes: first bullet stripped",
              h1.first == "⌘F to find in your notes")
        check("notes: second bullet stripped",
              h1.last == "Wisp remembers its window size and position")

        check("notes: intro prose (non-bullet) ignored",
              ReleaseNotes.highlights(from: "Some intro line\n- only this\n").count == 1)

        check("notes: old verbose body with no bullets → empty",
              ReleaseNotes.highlights(from: "Just a paragraph of prose.\nMore prose.").isEmpty)

        check("notes: empty body → empty", ReleaseNotes.highlights(from: "").isEmpty)

        check("notes: '*' bullets supported",
              ReleaseNotes.highlights(from: "* one\n* two").count == 2)

        let capped = (1...10).map { "- item \($0)" }.joined(separator: "\n")
        check("notes: capped at maxHighlights",
              ReleaseNotes.highlights(from: capped).count == ReleaseNotes.maxHighlights)

        // MARK: - Summary

        let total = passed + failures.count
        print("\n\(passed)/\(total) passed")
        if !failures.isEmpty {
            print("\(failures.count) failure(s):")
            for f in failures { print("  · \(f)") }
            exit(1)
        }
        exit(0)
    }
}
