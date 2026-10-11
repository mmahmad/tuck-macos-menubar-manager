# Tuck

A small macOS menu bar manager. Tuck hides third-party menu bar icons behind a single icon, so the
ones you care about stop disappearing behind the notch, and gives you a searchable list of
everything in the menu bar.

- **Hides third-party icons** to the left of a thin divider; system items (Wi-Fi, Sound, Battery, …) stay visible.
- **Searchable panel** listing every menu bar item, grouped into Hidden, Behind the Notch, Visible and System. Fuzzy search, ↑/↓ to select, Return to open, Esc to close.
- **Opens hidden items in place**: choosing a hidden item puts just that icon on the menu bar, opens it, and tucks it away again after a configurable delay (30 seconds by default).
- ⌘-drag icons across the divider to choose what is hidden; click the divider to show or hide everything.

Requires macOS 14 or later. Developed and tested on macOS 26.

## Install

### From a release

1. Download `Tuck-<version>.zip` from [Releases](../../releases), unzip it, and move `Tuck.app` to `/Applications`.
2. The app is not notarized, so macOS will refuse to open it the first time. Either clear the quarantine flag:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Tuck.app
   ```

   or try to open it once, then go to System Settings → Privacy & Security and click **Open Anyway**.
3. Launch Tuck and grant it **Accessibility** access when prompted (System Settings → Privacy & Security → Accessibility). Tuck appears in the menu bar once access is granted.

Release builds are ad-hoc signed, so macOS asks for Accessibility access again after each update.

### From source

Needs Xcode (or the Swift toolchain it ships).

```bash
./build.sh install
```

This builds `build/Tuck.app`, copies it to `/Applications` and launches it. If a code-signing identity is
in your keychain it is used, which keeps the Accessibility grant valid across rebuilds.

## How it works

- **Hiding** uses the same trick as Hidden Bar: the divider is a status item that grows to 10,000 points wide, pushing everything on its left off screen.
- **Listing and opening** items goes through the Accessibility API (`AXExtrasMenuBar` of each running app).
- **Moving** a single icon across the divider replays a ⌘-drag as synthetic mouse events addressed to the icon's window. This relies on undocumented event fields and could break in a future macOS release; if a move fails, Tuck falls back to revealing the whole hidden section.

## Settings

In the panel's gear menu: how long an opened item stays on the menu bar, whether system items are kept
visible, and launch at login.

Launching with `-debug YES` logs what Tuck sees in the menu bar to `~/Library/Logs/Tuck.log`.
