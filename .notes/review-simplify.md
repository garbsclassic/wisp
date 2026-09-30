# Review: simplify

Four-angle cleanup pass (reuse, simplification, efficiency, altitude) over the whole of `main` at 33cda12, on 2026-09-29. Quality only: bugs the reviewers tripped over are listed separately at the end, and fixed only where the cleanup fixes them anyway.

## Findings

Deduplicated across the four reviews, most valuable first.

- [x] **Efficiency** — the per-keystroke restyle runs every `addAttribute` outside `beginEditing`/`endEditing`, one `processEditing` each (6,275 at 86K chars), and its nine inline passes rebuild Swift `Regex` literals over a bridged string. Measured by the reviewer on a mixed note at 86K: 206 ms per restyle, 36 ms with both fixed ([MinimalTextEditor.swift:515](../Sources/Wisp/MinimalTextEditor.swift:515), [MinimalTextEditor.swift:770](../Sources/Wisp/MinimalTextEditor.swift:770)).
- [x] **Efficiency** — `renumberLists` applies each marker fix as its own edit, and each re-enters `textDidChange`: ↵ after item 2 of a 30-item list is 29 full restyles ([NotesTextView.swift:357](../Sources/Wisp/NotesTextView.swift:357)).
- [x] **Efficiency** — per body pass (two per keystroke, one per caret move): a full compare of the bridged text in `updateNSView`, and a word count that depends only on the text; per restyle, an `NSAttributedString.size()` for every indent run and marker, and a new bold font per heading; per keystroke, `MarkdownBlocks` built for `renumber` and again for `restyleContent` ([MinimalTextEditor.swift:107](../Sources/Wisp/MinimalTextEditor.swift:107), [EditorView.swift:729](../Sources/Wisp/EditorView.swift:729), [MinimalTextEditor.swift:503](../Sources/Wisp/MinimalTextEditor.swift:503)).
- [x] **Dead code** — the main menu's keymap items have no key equivalents and the app is `.accessory`, so nothing fires them. Their selector table, about 25 `@objc` forwarders on `AppDelegate`, `validateMenuItem`, and the menu rebuild on a keymap change all go; `KeyBindingMonitor` → `perform` is the one dispatch path ([MainMenu.swift:16](../Sources/Wisp/MainMenu.swift:16), [AppDelegate.swift:125](../Sources/Wisp/AppDelegate.swift:125)).
- [x] **Altitude** — six editing verbs travel as `@Published` counters through `EditorView`, `MinimalTextEditor`, and six `updateNSView` branches, only to call a `NotesTextView` method. Call it directly on the focused notes view ([EditorView.swift:16](../Sources/Wisp/EditorView.swift:16), [MinimalTextEditor.swift:176](../Sources/Wisp/MinimalTextEditor.swift:176)).
- [x] **Reuse** — "reset, clear the background in source view, restyle content" is written in `applyPalette` and again in `textDidChange`, and the body settings it reads are copied into five `Coordinator.last*` fields ([MinimalTextEditor.swift:291](../Sources/Wisp/MinimalTextEditor.swift:291), [MinimalTextEditor.swift:770](../Sources/Wisp/MinimalTextEditor.swift:770)).
- [ ] **Reuse** — `Coordinator.replace` re-implements `NotesTextView.apply`; the typed-`---` rule is inline view code with its own line-end trim and paragraph check, beside `emDashEdit` and `ruleOnReturn` in WispCore; the keystroke check is written twice; `replaceWithHorizontalRule` paints a `.clear` the restyle already paints ([MinimalTextEditor.swift:871](../Sources/Wisp/MinimalTextEditor.swift:871), [MinimalTextEditor.swift:1043](../Sources/Wisp/MinimalTextEditor.swift:1043)).
- [ ] **Simplification** — `EditorModel` keeps `@Published` mirrors of five config values, each written back from a `didLoad`-guarded `didSet`, and `adoptSettings` re-copies them with the guard switched off ([EditorView.swift:116](../Sources/Wisp/EditorView.swift:116), [EditorView.swift:479](../Sources/Wisp/EditorView.swift:479)).
- [x] **Simplification** — `MenuBarController` takes eleven closures, five of which are `perform(action)` for a keymap action, and hand-types titles `KeymapAction.title` already has ([MenuBarController.swift:13](../Sources/Wisp/MenuBarController.swift:13)).
- [x] **Simplification** — the UserDefaults migration is a compatibility path for installs that no longer exist ([Settings.swift:173](../Sources/Wisp/Settings.swift:173)).
- [x] **Simplification** — `isHorizontalRuleLine`, `isSetextUnderline`, `setextLevel`, and `isInsideFence` are called only by tests, and `paragraphStart(above:in:)` by nothing ([SmartEditing.swift:571](../Sources/WispCore/SmartEditing.swift:571)).
- [x] **Simplification** — `StorageLocation.SwitchResult.loadedExisting` is `backupURL != nil`, `folderPath` is the folder the caller passed, and both branches of the caller adopt `newText` ([StorageLocation.swift:61](../Sources/WispCore/StorageLocation.swift:61)).
- [x] **Simplification** — `lenientValue`'s `pathPrefix` is `codingPath` spelled by hand at eleven call sites ([Config.swift:55](../Sources/WispCore/Config.swift:55)).
- [ ] **Reuse** — `HotKey` and `KeyChord` are both a key code and a Carbon mask, converted by hand in four places, with `hyperMask` defined twice and an unused `HotKey.default` ([HotKey.swift:5](../Sources/WispCore/HotKey.swift:5)).
- [ ] **Reuse** — "one indent level" is written four times across `LineEdits` and `SmartEditing`, and `isSpaceOrTab` three times ([LineEdits.swift:175](../Sources/WispCore/LineEdits.swift:175)).
- [x] **Reuse** — the border overlay's corner radius is a literal `18` that stopped matching the panel's `10` when the panel changed; the placeholder's `24` is `chromeInsetX` ([EditorView.swift:714](../Sources/Wisp/EditorView.swift:714)).
- [ ] **Simplification** — `HotKeyMonitor` routes Carbon events through an id-keyed handler table for one instance ([HotKeyMonitor.swift:13](../Sources/Wisp/HotKeyMonitor.swift:13)).
- [ ] **Reuse** — the help page's sticky header rebuilds the section-title attributes `HelpDocument.render` sets ([HelpBody.swift:119](../Sources/Wisp/HelpBody.swift:119)); the footer, help footer, and header repeat one chrome-bar style ([HelpOverlay.swift:69](../Sources/Wisp/HelpOverlay.swift:69)).
- [ ] **Reuse** — `drawMarker` and `drawChecklistBox` open with the same marker geometry `baseline(of:)` and `markerCentre(of:)` compute ([NotesLayoutManager.swift:162](../Sources/Wisp/NotesLayoutManager.swift:162)).
- [ ] **Simplification** — small ones: `ChecklistBoxIndex` is a function with a type's name, `Typography.notes` is unused, `resetStorageLocation` only forwards, `HotKeyCaptureOverlay`'s `onSuccess` and `onCancel` are the same closure, `PanelController` pins four views with four copies of the same constraints.
- [ ] **Comments** — stale comments (no file watcher, UserDefaults theme, `esc` never "escape", `build-app.sh`, `notes/designs`, "no tables", the type-size cycle) and ones narrating earlier approaches.

## Incidental bugs

Reported by the reviewers while reading; not the point of this pass.

- CRLF notes: `handleEnter` and the typed-`---` check trim only `\n`, so ↵ on an empty bullet never leaves the list and `---` never becomes a rule.
- List markers inside fenced code and frontmatter are hidden and drawn as bullets or boxes, unlike headings and rules there.
- Breaking a `==x==` run leaves its highlight painted until the next find step or theme change: the per-keystroke reset never clears `.backgroundColor`.
- A folder switch onto an existing scratchpad reports the backup as saved even when writing it failed (`try?`), then deletes the old file.
