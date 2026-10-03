# Multi-machine sync and the arrival dot

Design for syncing clips between a user's own Macs. Not built yet. Written
down so the decisions behind it survive.

## What this is for

macOS already has **Universal Clipboard**: copy on one Mac, paste on another.
It is peer-to-peer over Bluetooth/Wi-Fi Direct, roughly a second, and it is
better at that job than anything we would build on iCloud. We do not compete
with it.

What it does *not* do:

- It is proximity-bound — the devices must be within Bluetooth range.
- It carries only the current clipboard, expiring after about two minutes.
- There is no history and nothing pinned.

So Klipt's sync answers a different question: **my history and my pinned items
are the same on every machine.** Pin an address on the desktop, paste it on the
laptop that evening. Latency of seconds is irrelevant to that, which is why
CloudKit is an acceptable transport and Universal Clipboard's speed is not a
target.

## Transport

CloudKit private database. It uses the Apple ID the user is already signed into,
so there is no account system, no password reset, no server to run, and the data
sits in their own iCloud rather than on ours.

Expected latency, both machines awake: **2–5 seconds** for text. Longer for
images. If the other machine is asleep it arrives on wake, which in practice is
the common case.

Two constraints that shape the implementation:

- **Silent pushes are best-effort.** The system throttles an app that pushes
  constantly, and a clipboard app is the worst case — people copy dozens of
  times a minute. Changes are debounced and coalesced over a few seconds rather
  than pushed per copy.
- **Developer ID distribution needs a provisioning profile.** CloudKit outside
  the App Store requires an App ID with iCloud enabled, a Developer ID
  provisioning profile embedded in the bundle, and
  `com.apple.developer.icloud-container-environment` set to `Production`.
  Installed copies stop running if that profile expires, so its expiry is an
  operational date, not a detail.

## What syncs

Text, links, images (screenshots included) and files up to **25 MB**. Anything
larger stays on the machine it was copied on: assets count against the user's
own iCloud storage, and a clipboard quietly uploading a disk image is not a
trade anyone agreed to. Grouped multi-file drops are not carried yet.

Images and files travel as CKAssets. Note the asymmetry with text: an Encrypted
String is end-to-end encrypted and Apple holds only ciphertext, while an asset
is encrypted in transit and at rest but not end-to-end. Text is the field most
likely to hold a password, which is why it gets the stronger guarantee.

A file's bookmark is never synced — it describes a path on the sender's disk and
means nothing anywhere else. The bytes are uploaded, written into
`Application Support/Klipt/SyncedFiles/<record id>/` on arrival, and a fresh
bookmark is made against that local copy.

**Nothing marked concealed ever syncs, or is even stored.** Password managers
flag their pasteboard writes with `org.nspasteboard.ConcealedType`. Honouring
that matters more once sync exists, because sync turns "briefly in local memory"
into "replicated to every machine and kept in the cloud" — but it is worth doing
regardless of whether sync ships.

Every clip carries the machine it came from, shown as "from MacBook Pro" beside
the timestamp. In a merged multi-machine list that is what makes the history
readable instead of confusing.

## The arrival dot

Sync is seconds, not instant, and silence reads as failure. The fix is not to be
faster — it is to make the wait legible. When a clip arrives from another
machine:

- the menu bar icon **pulses once**, for anyone looking at that moment;
- a small **dot** persists on the icon, for anyone who was not.

The dot is the part that does the work. A one-second animation you missed is
indistinguishable from nothing happening.

### Rules

**It signals inbound items only.** Flashing for your own local copies would fire
constantly, and an indicator that is always on conveys nothing.

**It means "something landed here recently", not "you have unread items".**
Clipboard history has no backlog — you never deal with a clip — so unread
semantics would leave the dot permanently lit on whichever machine you use less.
Recency expires on its own, which is what keeps it honest.

**It clears on whichever comes first:**

1. the tray is opened;
2. five minutes of the user actually being present at that machine;
3. anything is copied locally;
4. anything is pasted.

Rules 3 and 4 matter because clipboard activity means the user is engaged and
the "something arrived" signal is already stale.

**The five minutes counts presence, not wall clock.** If the clip lands while
the Mac is asleep or the user is away, the countdown does not start until the
machine wakes or the keyboard is touched — via `NSWorkspace.didWakeNotification`
and `CGEventSource.secondsSinceLastEventType`. A laptop opened the next morning
still shows the dot when the user sits down, rather than having quietly expired
at 3am, which is precisely when the signal would have been useful.

**Corollaries:**

- No dot if the tray is already open when the item lands. The row simply
  appears.
- A new arrival resets the timer rather than adding a second dot.
- Respect `accessibilityDisplayShouldReduceMotion`: skip the pulse, keep the
  dot.
- A burst — forty clips when a laptop wakes — is one pulse and one dot.
- **Never preview the contents.** A clipboard holds passwords, and briefly
  rendering one on screen is the single unrecoverable mistake available here.

## Positioning

The site currently promises, in two places, that Klipt keeps everything on your
Mac and uploads nothing. Sync contradicts that. It is resolvable — opt-in, off
by default, "your iCloud, not our servers" — but the copy has to be rewritten
deliberately rather than quietly.
