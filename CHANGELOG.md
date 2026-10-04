# Changelog

All notable changes to Klipt. Newest first.

## [1.9.1] — 2026-10-03

### Fixed
- The menu bar icon never visibly changed when a clip arrived from another
  Mac. The dot was being drawn, but in the same colour as the icon and on top
  of it, so it was invisible.

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
