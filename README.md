# Wisp

A dead-simple macOS scratchpad. ⌃⌥. to summon, type, Esc or click away to dismiss.

<p align="center">
  <img src="docs/screenshot.png" width="720" alt="Wisp">
</p>

## Install

Requires macOS 13 (Ventura) or later, Apple silicon. This is a personal fork
with no release pipeline.

```sh
./scripts/install.sh
```

Builds and copies to `/Applications/Wisp.app` (override with
`WISP_INSTALL_DIR`). Launch it, then enable **Launch at Login** from the menu
bar menu if you want it. Installing to a stable path matters for that: the
login item is recorded against the bundle's location, so running from
`dist/` means a rebuild or a move can orphan it.

```sh
./scripts/uninstall.sh            # removes the app, keeps your config
./scripts/uninstall.sh --purge    # also removes ~/.config/wisp
```

Uninstall quits the running copy first. Turn Launch at Login **off before**
uninstalling — the registration is keyed to the bundle, so deleting the app
first leaves a dangling login item.

## Features

- **⌃⌥.** to summon from anywhere (rebindable)
- **Light / dark / system** appearance — one-click cycle, follows macOS by default
- **Smart editing** — lists auto-continue, `---` becomes a divider, `**bold**` and `*italic*` render inline
- **Headings** — `#`, `##`, `###` render styled with click-to-jump navigation
- **Emoji shortcodes** — `:rocket:` `:fire:` `:heart:` `:check:` and more
- **Bold / Italic** — ⌘B / ⌘I
- **Launch at Login** — toggle in the menu bar menu
- **Plain markdown on disk** at `~/Documents/scratchpad.md`
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

| Key                     | Default                   | What it does                                                                                                                 |
| ----------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `theme`                 | `"system"`                | `light`, `dark`, or follow macOS                                                                                             |
| `fonts.notes`           | `"Inter Nerd Font"`       | The notes body face                                                                                                          |
| `fonts.ui`              | `"Inter Nerd Font Propo"` | Header, footer, and overlays                                                                                                 |
| `fontSize`              | `"medium"`                | `small` / `medium` / `large` — the ⌘1 / ⌘2 / ⌘3 cycle                                                                        |
| `fontScale`             | `1.0`                     | Multiplies every type size. Clamped to 0.6–2.5                                                                               |
| `vibrancy`              | `true`                    | Blurs whatever is behind the panel                                                                                           |
| `monitor`               | `"primary"`               | `pointer` opens on whichever display the cursor is on                                                                        |
| `dismissOnOutsideClick` | `true`                    | Clicking another app closes the panel                                                                                        |
| `position`              | `"auto"`                  | `auto` opens the panel centred, top edge a tenth down the screen, and pins it there; `manual` leaves it wherever you drag it |
| `scratchpadPath`        | `""`                      | Folder for `scratchpad.md`; empty means `~/Documents`                                                                        |
| `keymap.summon`         | `"ctrl+opt+."`            | The global chord, e.g. `cmd+shift+space`                                                                                     |
| `panel`                 | _(written on first hide)_ | Remembered `width` / `height`, plus `x` / `y` once the panel has been dragged under `manual`                                 |

Neither font is bundled — both are referenced by name, and Wisp falls back to
the system face (and says so in the footer) when one isn't installed.

Wisp rewrites only the key it changed, so hand-added comments, key order, and
indentation all survive a settings change made from the UI.

## Build

```sh
./scripts/build.sh
open dist/Wisp.app
```

```sh
./scripts/test.sh
```

No Xcode required — Command Line Tools are enough. `swift test` alone fails
with `no such module 'Testing'`: Swift Testing ships inside CLT but isn't on
the default search path, so `scripts/test.sh` points the compiler, linker,
and dyld at it.

For quick iteration without assembling a bundle:

```sh
git clone https://github.com/garbsclassic/wisp.git
cd wisp
swift run
```

## Signing

`scripts/build.sh` ad-hoc signs by default. Every rebuild relinks with a
fresh `LC_UUID`, so the code identity changes each time, which can make
macOS ask you to re-approve "Launch at Login" after a rebuild. To get a
stable identity without Xcode or a paid Apple Developer account, create a
self-signed **Code Signing** certificate in Keychain Access (Certificate
Assistant → Create a Certificate) and:

```sh
WISP_SIGN_IDENTITY="Your Cert Name" ./scripts/build.sh
```

## License

MIT — see [LICENSE](LICENSE).
