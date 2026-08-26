# Wisp

A dead-simple macOS scratchpad. ⌃⌥. to summon, type, Esc or click away to dismiss.

<p align="center">
  <img src="docs/screenshot.png" width="720" alt="Wisp">
</p>

## Install

Requires macOS 13 (Ventura) or later, Apple silicon.

**Homebrew**

```sh
brew tap sulemaanhamza/wisp
brew install --cask wisp
xattr -d com.apple.quarantine /Applications/Wisp.app
```

**Direct download**

Grab the latest zip from [Releases](https://github.com/sulemaanhamza/wisp/releases), unzip, drag `Wisp.app` to `/Applications`, then:

```sh
xattr -d com.apple.quarantine /Applications/Wisp.app
```

The `xattr` step is needed because Wisp isn't signed with an Apple Developer ID — it tells macOS the app is safe to open.

## Features

- **⌃⌥.** to summon from anywhere (rebindable)
- **Light / dark / system** appearance — one-click cycle, follows macOS by default
- **Smart editing** — lists auto-continue, `---` becomes a divider, `**bold**` and `*italic*` render inline
- **Headings** — `#`, `##`, `###` render styled with click-to-jump navigation
- **Emoji shortcodes** — `:rocket:` `:fire:` `:heart:` `:check:` and more
- **Bold / Italic** — ⌘B / ⌘I
- **Launch at Login** — toggle in the menu bar menu
- **Plain markdown on disk** at `~/Library/Application Support/Wisp/scratchpad.md`
- **Sync across Macs** — point at any folder via the menu bar menu (iCloud Drive, Dropbox, Syncthing all work)
- **Hand-editable config** at `~/.config/wisp/wisp.jsonc` — see below

Click the `?` in the footer for the full keyboard shortcut list.

## Configuration

Everything Wisp persists lives in `~/.config/wisp/wisp.jsonc` (or
`$XDG_CONFIG_HOME/wisp/wisp.jsonc`), seeded with defaults on first run and
openable from **Settings…** in the menu bar menu. Comments and trailing commas
are fine — it is read as JSON5. A key that's missing takes its default; a key
that's present but the wrong shape is named in the footer rather than silently
ignored.

| Key                     | Default                                   | What it does                                                        |
| ----------------------- | ----------------------------------------- | ------------------------------------------------------------------- |
| `theme`                 | `"system"`                                | `light`, `dark`, or follow macOS                                    |
| `fonts.notes`           | `"Inter Nerd Font"`                       | The notes body face                                                 |
| `fonts.ui`              | `"Inter Nerd Font Propo"`                 | Header, footer, and overlays                                        |
| `fontSize`              | `"medium"`                                | `small` / `medium` / `large` — the ⌘1 / ⌘2 / ⌘3 cycle               |
| `fontScale`             | `1.0`                                     | Multiplies every type size. Clamped to 0.6–2.5                      |
| `vibrancy`              | `true`                                    | Blurs whatever is behind the panel                                  |
| `monitor`               | `"primary"`                               | `pointer` opens on whichever display the cursor is on               |
| `dismissOnOutsideClick` | `true`                                    | Clicking another app closes the panel                               |
| `scratchpadPath`        | `""`                                      | Folder for `scratchpad.md`; empty means Application Support         |
| `keymap.summon`         | `"ctrl+opt+."`                            | The global chord, e.g. `cmd+shift+space`                            |
| `panel`                 | _(written on first hide)_                 | Remembered `x` / `y` / `w` / `h`, in screen points                  |

Neither font is bundled — both are referenced by name, and Wisp falls back to
the system face (and says so in the footer) when one isn't installed.

Wisp rewrites only the key it changed, so hand-added comments, key order, and
indentation all survive a settings change made from the UI.

## Build from source

```sh
git clone https://github.com/sulemaanhamza/wisp.git
cd wisp
swift run
```

## Contributing

Run the test suite before sending a pull request:

```sh
swift run WispCoreTests
```

## License

MIT — see [LICENSE](LICENSE).
