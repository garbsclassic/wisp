# Fix the audit findings

## Outcome and scope

Address findings 1–12 from the repository audit, starting with note preservation and config writes. Keep the single-note app, JSON5 config, existing editing rules, and current dependencies. Follow the deliberate editing choices in [intent.md](intent.md).

The implementation must preserve existing notes and config text when a read, backup, or write fails. No sync merge engine, general persistence framework, new preferences, or compatibility layer is needed.

## Work

### 1. Note persistence and folder changes — findings 1, 2, 3, 6, 11

- [ ] Fix [StorageLocation](../Sources/WispCore/StorageLocation.swift) so a destination read and local backup must succeed before the old note can be removed. Keep successful migration behavior; never overwrite an existing backup.
- [ ] Update [EditorModel](../Sources/Wisp/EditorView.swift) to distinguish a missing note from a failed read, and unsaved local edits from a clean buffer. Quit must not rewrite a clean note or overwrite one that failed to load.
- [ ] Report save errors, retain unsaved state after failure, and flash the save indicator only after a successful write. Handle a failed final save before accepting termination in [AppDelegate](../Sources/Wisp/AppDelegate.swift).
- [ ] Reconcile pending saves with folder changes and quit. Serialize writes or otherwise ensure an older task cannot overwrite a newer save or clear its unsaved state.
- [ ] Reload when the modification time differs, including an older restored timestamp. Make explicit Refresh force a read while preserving unsaved local edits.
- [ ] Reconcile folder-change failures across [Settings](../Sources/Wisp/Settings.swift), the model, and the watcher: update the active location only after required operations succeed. Check Reset Scratchpad Folder for the same data-preservation issues.
- [ ] Add temporary-file tests for migrations and their failures in [StorageTests](../Tests/WispCoreTests/StorageTests.swift), and tests of the actual model save/reload/quit lifecycle.

Acceptance: a failed destination read, backup, config update, or note write must leave recoverable local text and existing disk content intact. A clean quit must preserve an external edit. Restoring an older file must be visible after Refresh. An earlier save completion must not mark newer edits saved.

Resolve the model test boundary first: determine whether a small app test target can import the existing executable through [Package.swift](../Package.swift) without starting an application. Move only the required persistence logic into WispCore if direct tests cannot exercise it; do not restructure the UI to make the tests work.

### 2. Config text preservation — findings 4, 5

- [ ] Fix primitive-value boundaries in [JSONTextEdit](../Sources/WispCore/JSONTextEdit.swift) so trailing line and block comments remain outside the replaced value, including comments containing commas or braces.
- [ ] Extend targeted updates to insert absent keys into valid config text, including missing nested objects. Preserve unrelated values, comments, order, and indentation.
- [ ] Change [ConfigStore.update](../Sources/WispCore/ConfigStore.swift) to validate the edited result before writing and reject unreadable or malformed existing files. Reserve full-file encoding for creating a missing config.
- [ ] Reconcile [Settings](../Sources/Wisp/Settings.swift) mutations with write failures so callers can distinguish a persisted change from a failed one.
- [ ] Replace the existing full-rewrite expectation and add focused cases in [ConfigStoreTests](../Tests/WispCoreTests/ConfigStoreTests.swift).

Acceptance: changing `fontScale` beside `1 /* keep, this */` must leave valid JSON5 and preserve the comment. The first panel-size save and updates to partial configs must preserve unrelated text. Updating malformed or unreadable config must fail without replacing its contents.

### 3. Editing boundaries — findings 7, 8

- [ ] Apply the existing nine-digit counting limit to [SmartEditing.nextListMarker](../Sources/WispCore/SmartEditing.swift). Leave longer numeric markers unchanged rather than overflowing or restarting at one; check Return and SmartPaste callers.
- [ ] Make [LineEdits.rewriteLines](../Sources/WispCore/LineEdits.swift) process an empty selected line once. Check bullet/checklist toggles, indent/outdent, selection mapping, and no-op handling in [NotesTextView](../Sources/Wisp/NotesTextView.swift).
- [ ] Add focused regressions in [SmartEditingTests](../Tests/WispCoreTests/SmartEditingTests.swift) and [LineEditsTests](../Tests/WispCoreTests/LineEditsTests.swift).

Acceptance: Return after `Int.max` or a longer numeric marker must not crash or invent a new number. Bullet/checklist shortcuts must work in an empty document and on its trailing empty line, with valid caret positions and undo behavior.

### 4. Search and live fonts — findings 9, 10

- [ ] Recompute search matches when the active document changes, including local edits, disk reloads, and changes to the help document. Preserve the current match index where possible and clear an invalid highlight.
- [ ] Include font families in [MinimalTextEditor.BodyStyle](../Sources/Wisp/MinimalTextEditor.swift) and its [EditorView](../Sources/Wisp/EditorView.swift) caller so a config reload restyles existing text and typing attributes.
- [ ] Add model assertions for stale search results and focused checks for font-only style changes. Inspect the rendered behavior in both themes.

Acceptance: counts and Next/Previous navigation must match the current document after an edit or reload. Changing only `fonts.notes` or `fonts.code` must update the existing note without another edit, zoom change, or relaunch.

### 5. Small deletions — finding 12

- [ ] Recheck references, then delete unused `PanelPositioner.resize` and `View.arrowCursor` from [PanelPositioner](../Sources/Wisp/PanelPositioner.swift) and [CursorHelpers](../Sources/Wisp/CursorHelpers.swift).

## Verification and delivery

- [ ] Delegate substantial regression-test work to `tester` with bounded test-file ownership. Keep tests alongside each behavior change rather than postponing them to the end.
- [ ] Run [scripts/test.sh](../scripts/test.sh) with the current CLT SDK. Require the full suite for completion; a filtered run is only partial verification. Resolve permission or toolchain blockers without treating them as app defects.
- [ ] Have `reviewer` inspect the persistence/config changes and cross-component behavior before completion; resolve actionable findings and rerun affected checks.
- [ ] Verify folder switching, failed saves, Refresh, quit, empty-line shortcuts, search, font reload, and undo in the running app. Use temporary notes for destructive failure scenarios, and measure UI changes in light and dark themes.
- [ ] Build and install through [scripts/install.sh](../scripts/install.sh), then verify the installed bundle and the changed behaviors. Installation and rendered verification are required for implementation completion.
- [ ] Keep related fixes in coherent commits. Remove completed work from this plan and retain lasting rationale only where it helps future decisions.

No new config keys, login-item changes, or bundle identity changes are planned. If implementation requires any of these, update the scope before proceeding and include the corresponding managed-config and installation work.