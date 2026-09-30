# Changelog

What changed in each RDMALink release, newest first.

## Unreleased

- A new app icon: two lanes that come together, on deep navy.
- The M4 Mac mini (2024) has Thunderbolt 4, so RDMALink now opens
  read-only on it, as it already does on the 14-inch MacBook Pro with M4 or
  M5 and on the M6 Mac mini. Before, it offered set-up there. The M4 Pro
  Mac mini has Thunderbolt 5 and is unchanged.
- RDMALink sets up only a Mac it knows has Thunderbolt 5. A Mac it
  recognizes only by its shape and ports, such as one newer than this
  version, now opens read-only as well, and says it doesn't know the Mac's
  Thunderbolt yet. Before, it offered set-up there.

## 0.3.8 — 2026-09-29 (build 11)

- RDMALink uses about 1 % of one CPU core while it sits open, down from
  about 20–35 %. The 3D view of the Mac draws only while something on it
  moves, and not at all while the window is hidden or covered.
- The once-a-second check of the ports reads the full network state only
  when something has changed, and at least every 10 seconds. Plugging and
  unplugging a cable still shows up within a second.
- The window's minimum size is 900 × 600 points. The layout no longer
  switches to a single column with a thin strip of the 3D view, which could
  not show the whole Mac.
- In dark mode the area behind the 3D Mac is now the window's own
  background colour, a little lighter than before.

## 0.3.7 — 2026-09-27 (build 10)

- The 2026 Macs: Mac Studio (M5 Max and M5 Ultra) and Mac mini (M5 Pro and
  M6). The M6 Mac mini has Thunderbolt 4, so RDMALink opens read-only on it.
- Now the other Mac: an **Other Mac:** pop-up on the 3D view draws the
  second Mac as a MacBook Pro, Mac Studio or Mac mini instead of a plain
  box, and remembers the choice.
- A setup can't be restarted from a menu while it is open. From the
  password dialog until the last change is written, the window can't be
  closed and quitting waits. A failed setup never overwrites the saved
  undo note.
- Set Up Port… always opens the port picker, with RDMALink's suggestion
  selected. A button that names a port opens Review for that port directly.
- A pass against Apple's Human Interface Guidelines: Check Again (⌘R) in
  the View menu, one default button at a time, better text contrast, sheets
  that fit a 600-point window, Liquid Glass controls on the 3D view, and one
  name for each command.

## 0.3.6 — 2026-09-23 (build 9)

- A new app icon made in Icon Composer: a large receptacle on silver.

## 0.3.5 — 2026-09-23 (build 8)

- The app icon is the ready receptacle again, without the thread and with
  more glow.
- The README explains installing with Homebrew from the dev7a tap.

## 0.3.4 — 2026-09-22 (build 7)

- A new app icon: two plug ends and one beam of light.
- A license, a README and a security policy, and the fixes from a review
  before the repository went public.

## 0.3.3 — 2026-09-21 (build 6)

The first release on GitHub: signed with Developer ID, notarized, and built
from a signed tag by GitHub Actions.

- Sets up a Mac's Thunderbolt ports for RDMA: takes a port out of the
  Thunderbolt Bridge, gives it a link-local service of its own, and keeps a
  note of how to undo it. Return to Thunderbolt Bridge, Adopt, Restore and
  Identify cover the rest.
- A 3D view of this Mac that shows which port is which, what each one is
  connected to, and its state.
- Setup in three steps: choose the port, review the changes and the checks,
  then enter your password once.
- Recognizes a Mac by its product family and port layout. A Mac it doesn't
  recognize opens read-only.
- A help sheet on RDMA over Thunderbolt, why a port leaves the bridge, why
  two Macs want only one cable between them, and the `fe80::` address, with
  a link to Apple's technote on RDMA over Thunderbolt (TN3205).
