# Changelog

All notable changes to Klipt. Newest first.

## [1.9.4] — 2026-10-05

### Fixed
- Pinned text could quietly lose its pin and disappear days later. Copying the
  same text again replaced the pinned clip with a fresh unpinned one — and
  re-copying is exactly what you do with text worth pinning. Once unpinned it
  was no longer protected from the 100-per-type limit or from expiry. Only text
  was affected, since only text is deduplicated.

## [1.9.3] — 2026-10-04

### Fixed
- Klipt only looked for updates when it launched. Since it lives in the menu
  bar and is rarely quit, that meant it checked once and then never again, and
  new versions could sit unnoticed for weeks. It now checks every day while
  running.
- The update offer no longer appears while the tray is open, where it would
  steal focus and close what you were looking at.

## [1.9.2] — 2026-10-03

### Fixed
- The Mac you copied *on* also turned orange, as if the clip had arrived from
  somewhere else. Klipt keeps 100 clips per type but nothing was removed from
  iCloud, so trimmed clips were re-downloaded and announced again as new.
- Clicking the menu bar icon now clears the orange. Previously you had to open
  the tray, copy or paste something, or wait five minutes.

## [1.9.1] — 2026-10-03

### Changed
- The menu bar icon now turns orange when a clip arrives from another Mac,
  instead of showing a small dot. It goes back to normal when you open the
  tray, copy or paste anything, or after five minutes.

### Fixed
- Nothing visibly changed in the menu bar when a clip arrived. The dot was
  being drawn, but in the same colour as the icon and on top of it, so it was
  invisible.

## [1.9.0] — 2026-10-03

### Added
- Screenshots, images and files now sync between your Macs too, not just text.
  Files up to 25 MB travel; anything larger stays on the machine you copied it
  on, since it would be your own iCloud storage being spent.

### Fixed
- Clips created by dropping onto the tray, or captured as screenshots, were
  never synced — only ones copied to the clipboard were.

## [1.8.0] — 2026-10-03

### Added
- Sync between your Macs. Turn it on in Settings and text clips travel to
  your other Macs through your own iCloud, encrypted end to end so that not
  even Apple can read them. Off by default; files and images stay on the
  machine you copied them on.
- The menu bar icon pulses and keeps a small dot when a clip arrives from
  another Mac, so you know it landed without opening the tray. The dot clears
  when you open the tray, copy or paste anything, or after five minutes.
- Clips show which Mac they came from.

## [1.7.0] — 2026-10-03

### Changed
- Klipt now updates itself from GitHub Releases instead of Sparkle. The app
  checks once a day, shows you what changed, and installs on request —
  verifying the signature, the developer and Apple's notarisation before it
  replaces anything.

### Removed
- Sparkle and the appcast feed it polled.

## [1.6.0] — 2026-08-17

### Added
- Press space on a file clip for a full Quick Look preview. Images, PDFs and
  documents render properly instead of showing a generic icon.
- Double-click a file clip to open it in its default app, or hold Option to
  reveal it in Finder.
- Settings shows the exact build you're running.

### Changed
- Klipt is signed and notarised by Apple, so it opens with a single click.

## [1.5.0] — 2026-07-27

### Changed
- Klipt is now free. Clipboard history up to 30 days is unlocked for everyone.

### Removed
- License activation and the in-app purchase flow.
