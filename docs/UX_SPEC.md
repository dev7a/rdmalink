# RDMALink — Final UX Specification

**Product:** RDMALink (`com.dev7a.RDMALink`) — a free, notarized, non-sandboxed macOS 27 utility (SwiftUI + RealityKit), distributed from GitHub.
**Job:** Prepare one or more Thunderbolt 5 ports **on the Mac it is running on** so they can carry RDMA over Thunderbolt, and be able to put everything back.
**Audience for this document:** designers building high-fidelity mockups, then engineers implementing. Every quoted string is final copy and may be pasted verbatim.

**Build milestones referenced in this document are `ML0`, `ML1`, `ML2`, `ML3`. They are internal labels for the build plan only. They never appear in the interface, in copy, in window titles, in a progress rail, or in a status bar. The shipped app's only progress indicator is a text label of the form "Step 2 of 3".**

Copy is US English. Every string is a separate localizable resource; no sentence is assembled by concatenation. Position names and locator phrases are separate strings so they can be re-worded per language.

---

## 1. North star & tone

### 1.1 North star

> It feels like a patient, well-made tool that already knows your Mac: it turns the Mac around so you can see the right port, tells you exactly what it is about to change, asks once, and can put everything back.

### 1.2 What the app is, structurally

Migration Assistant fused with System Settings. A linear assistant that **explains before it acts, checks preconditions itself, and never asks the user to promise anything it could measure**, wrapped around a calm status hub you return to and can read at a glance on the fifth launch.

The RealityKit model is the hero because it is the fastest way to answer *"which physical hole do I put the cable in."* It is therefore wordless, lit like a product shot and not a toy: no idle spinning, no particles, no floor reflections, no sound. Every motion in the scene is either feedback for something the user did, or the app narrating its own camera move **in words first** ("Turning the Mac around").

### 1.3 Tone rules (binding on all copy)

1. **Sentence case for all body, headlines, labels, and list rows. Title Case for buttons.** Counts are words, in a button or a counter as in a sentence: `Set Up Two Ports`, **Two ports selected**, **Setting up three ports**.
2. **The app never says "I", "we" or "let's".** When a sentence needs someone to act, that someone is **RDMALink**; otherwise say what happens ("Watching every port."). It is a competent tool, not a mascot or a colleague. No exclamation marks anywhere in the app. No jokes at the user's expense. No "Oops."
3. **Never scary.** No red fills, no alarm banners, no sirens, no "WARNING". A refusal is a closed door with the handle pointed out, not an alarm.
4. **Never a promise the app could measure.** There is not one attestation checkbox and not one "I have checked that…" button in the entire app. If the app can observe it, the app observes it.
5. **No escape hatch.** There is no "Continue Anyway", no "I understand the risks", no option-key bypass, and no disabled-but-present primary button on a refusal — a refusal removes the primary action entirely, because a disabled button is still an invitation to hunt for the modifier key.
6. **No technical name is shown unless "Show technical names" is on.** Interface names (`en6`), bridge names (`bridge0`), and exact service names are hidden by default. Two exceptions, both deliberate: the `fe80::` address is always shown in full, because it is the payoff and tools need every character of it; and every "Copy Details" payload on a failure refusal includes the technical names regardless of the toggle, because at that point the user needs them.
7. **Plain physical language.** "Back, far left", not "Port 4". "A dock or a display", not "a non-Mac PCIe endpoint". "Put it back", not "revert configuration".
8. **Honest about the two things it cannot do**: the RDMA system switch and the restart. It says so, points at the setting, and notices the moment it's on.
9. **Never mentions the other Mac's state as if it knew it.** The app models the machine it runs on and nothing else.
10. **Never claims a change it hasn't verified.** "Everything is back" is printed only after bridge membership has been read back.
11. **An ellipsis means there is more to do before the command is done.** A button or menu item ends in … when clicking it cannot finish the command its words name, because it opens somewhere the user still has to decide or do something first. That place is a sheet (`Adopt…`, `Restore…`, `Return to Bridge…`, `Stop Managing…`), a window (`Settings…`), a save panel (`Save Diagnostics File…`), the set-up assistant (`Set Up Port…`, `Set Up…`, `Set Up Again…`), Identify's watch (`Identify Port…`, `Identify Again…`), or a system setting only the user can switch (`Turn It On…`). A command that is finished on the click carries none, whatever it opens. Such a command acts in place (`Check Again`, `Copy Address`, `Show Me`, `Forget This Note`), names the opening itself (`Open Network Settings`, `Show in Finder`, `Show Notes in Finder`), shows something and asks nothing (`Change Log`, `What This All Means`, `What to Do on the Other Mac`), moves between steps (`Continue`, `Back`, `Try Again`), or ends something (`Done`, `Cancel`, `Quit`). macOS's password dialog doesn't count: a button that raises it commits the command, so Review's `Set Up Port` and a sheet's `Restore` carry none — the opener has the ellipsis, the committer doesn't. Prose that names a button drops the ellipsis ("Set Up Again takes the port out of the bridge"), and so does a VoiceOver custom action (§8.2) — except a line that points at a row's button by its exact title, as R27's routing lines do ("Restore… puts it back"), so the words and the button match.
12. **"Thunderbolt Bridge" is a name, so it takes no article** — `Leave Thunderbolt Bridge`, "returns the port to Thunderbolt Bridge", "The port has left Thunderbolt Bridge" — except in the membership phrase **In the Thunderbolt Bridge**, where it reads as a place. "The bridge", lower case, is the ordinary noun and keeps its article.

---

## 2. Window & navigation model

### 2.1 One window

One window, no sidebar, no tabs, no document model, no menu bar extra, no notifications, no dock badge, no background agent. RDMALink is a tool you open, not a thing that lives on your Mac.

- **Title:** `RDMALink`
- **Window subtitle** (set as soon as the model is known): `Studio — Mac Studio (M3 Ultra)` — the Mac's own sharing name, an em dash, the model and chip. The model is the catalogue's name for the identifier, or the product family macOS itself publishes for the Mac when the catalogue has none, and plain `Mac` only when neither exists.
- **Default size** 1000 × 720 pt, so a six-port hub fits without scrolling. **Minimum** 840 × 600 pt. Resizable, remembers frame, not full-screen-oriented.

### 2.2 Toolbar

Unified toolbar, two items, nothing else. No step indicator, no branding, no rail, no "This Mac" badge: that the app only ever changes the Mac it runs on is implied by everything on screen, and the window subtitle already names the machine.

| Position | Item | Symbol | Tooltip | Behavior |
|---|---|---|---|---|
| Trailing | `Check Again` | `arrow.clockwise` | **Check this Mac's ports and settings again** | Re-runs the full probe. Always enabled. A reassurance, not a requirement — a one-second state diff runs underneath at all times. Its shortcut, ⌘R, belongs to the View menu's `Check Again` (§2.7), which does the same thing; the button declares none of its own. |
| Trailing | `Help` | `questionmark` | **Learn what RDMALink changes and why** | Opens the Help menu's first item. The plain `questionmark`, not the circled one: the toolbar group already draws the container. |

The toolbar's tooltips are verb-first, sentence case, no period.

### 2.3 Body layout

A horizontal split: **STAGE** on the left, **ASSISTANT COLUMN** on the right.

- Default split: stage 58 %, column 42 %. Stage minimum 460 pt, column minimum 380 pt.
- The divider **is** draggable (a standard thin split divider) and the position is remembered. `Reset View` (⇧⌘0) returns the split to 58/42 and the camera to its resting pose. Declaring the model the hero and then forbidding anyone to give it more room is restraint one notch past usefulness.

**STAGE** — the `RealityView`, edge-to-edge, with two floating controls and nothing else — three while §S8 is up on a recognized Mac and the stage is wider than §8.5's strip:

- **Bottom-center:** the face selector — a segmented control inside a Liquid Glass capsule (`.glassEffect(.regular, in: .capsule)`), Maps-style. `Back / Front` on Mac Studio and Mac mini; `Left / Right` on notebooks (`Back` is offered only if that face carries ports; on current notebooks it does not, so it is absent rather than empty). Hidden entirely when the model has one relevant face (Mac mini with no cable in front). On an unrecognized Mac (R31) the stage has no chrome at all: no selector, no Fit or Reset View, no legend, no callout.
- **Bottom-trailing:** two small borderless buttons in one Liquid Glass capsule, icons on both: `Fit` (`arrow.up.left.and.arrow.down.right`) and `Reset View` (`arrow.counterclockwise`).
- **Top-trailing, §S8 only:** the `Other Mac:` pop-up with its label, in one Liquid Glass capsule, above where the ghost second Mac settles and across from the legend (§S8 **The other Mac's picture**). It is there only while §S8 holds the working area on a recognized Mac — never on the hub, in the set-up assistant or on an unrecognized Mac — and it comes and goes with the ghost. Below 900 pt, where the stage is §8.5's 180 pt strip, it is not on the stage: it stands in §S8's working area instead.
- These are the stage's only controls, so they are the ones drawn in Liquid Glass, as macOS draws controls floating over content. Under Reduce Transparency they fall back to an opaque `.windowBackground` capsule, and under Increase Contrast they gain a hairline (§3.6). The narration capsule (top-center) and the receptacle callout float too, but they are labels, not controls, and stay on `.regularMaterial` (§3.1). A label gives way to a control, never the reverse: while the pop-up is on the stage, the narration capsule is set just below the pop-up's row whenever, centered, it would come within 8 pt of it; the callout drops below its receptacle's row rather than reach it; and the legend does not move into its corner (§4.8).

**ASSISTANT COLUMN** — a `VStack` on `.windowBackground` with 24 pt margins, in fixed bands, top to bottom, numbered as the rest of this document cites them:

1. **Step label.** It has no band of its own: `Step 2 of 3` in `.caption` secondary sits trailing on the first line of the screen's headline, on its baseline, and there is no separate step title. Every screen's headline therefore starts at the top of band 2, at the same height as the hub's — the assistant, the change log and the other-Mac screen alike — so going from the hub into a run and back moves nothing but the words. When a refusal card replaces a screen, its headline is the screen's and carries the label (§6.1). The label is a **label, never a progress bar**, and it is absent on the hub, the change log, the other-Mac screen and settings. It counts the screens of the current run, and the count is fixed when the run opens and never changes: a run opened by a control that doesn't name a port — the footer's `Set Up Port…` or ⌘N — opens on the picker and has three steps (Choose, Review, Ready); a run opened by a control that names its port — a row's `Set Up…` or `Set Up Again…`, the drift row, the change log, R30, a double-click on the model — opens on Review and has two (§S4). Setting up (S6) keeps Review's label while it runs.
2. **Working area.** `.title2` semibold headline, `.body` secondary explanatory text, then the step's controls (grouped inset lists, `Form` rows, value blocks). This is the only band that changes between steps. When it is taller than the room band 3 leaves it, it scrolls, and the edge with more past it fades rather than cut a line in half. It has no button row of its own: a screen's own buttons live in band 4. What stays here is what belongs to one line — an inline action beside its words (a row's button, the Checked group's `Check Again`, `Copy Address`, `Show Me`, S4's `Identify Port…`), or, while the stage is §8.5's strip, §S8's `Other Mac:` pop-up beside its label — and refusal cards, which carry their own row (§6.1).
3. **The port list.** A permanent, grouped inset list of **every receptacle on this Mac** — Thunderbolt and USB-only alike — in physical order, grouped by face (`Back`, `Front`, or `Left side`, `Right side`). It is present on every screen of the main window, in every step. **It never reorders and never resizes a row; only badges, subtitles, and trailing controls change**, cross-fading in 180 ms. It has two densities:
   - **Full** (hub, Choose a port, Identify): symbol, title, `.callout` secondary subtitle carrying state and bridge membership, optional trailing borderless button in the accent color (none on a row the picker lets you choose, §S4). Every small inline action beside a row's words — a port row's, a situation row's, a This Mac row's `Turn It On…` and `Tell Me More`, a check row's, the Checked group's `Check Again`, a change-log entry's, Ready's `Turn It On…` and `Copy Address`, `Show Me` — takes the accent the same way, so it reads as something to click and not as one more gray label. So does S4's borderless `Identify Port…` above the list, at its regular size, and the hub's link row under the list, at caption size (§S1): every clickable word in the column is one color, the user's accent, and none of them is the system's link blue. A disabled one is drawn in `.tertiary` instead of the accent, as a row's set-up button is while two Macs are connected (§S1, §3.1), so it never reads as clickable when it isn't.
   - **Compact** (RDMA, preflight, review, apply, done, other Mac, change log): symbol, title, and a short trailing badge only. Same rows, same order, same place, less ink.
   - It scrolls independently if it cannot fit; it is never truncated away.
4. **Footer.** A separator, then `Back` leading and the primary button trailing with `.keyboardShortcut(.defaultAction)`. A screen's own buttons all live here, in one order: the way back leading, the default trailing, and any others just before the default — S7's `What to Do on the Other Mac` · `Done`, S4b's `Identify Again…` · `Choose from List` before its answer's default. While §S8 or §S11 holds the working area this band is that screen's footer — §S8's `Copy These Steps` · `Done`, §S11's `Show Notes in Finder` · `Save Diagnostics File…` · `Done` — and the hub's footer and its link row step aside until that `Done`, so the window never has two button rows or two defaults. `Back` only moves between steps — Review back to the picker, in a run that opened on the picker — and never dismisses. On a run's first screen, the picker or Review alike, going back would leave the assistant, so the same button reads `Cancel` and returns to where the run started: the hub, or the change log if the run started there. Either way it is `.cancelAction`, except on the picker while a card is up, where Escape puts the card away first (§8.3). On S6 it is hidden, running or refused: the burst can't be interrupted, and a refused S6's card holds every way out (§S6). Between them, contextual `.caption` secondary text where a step needs it (**Two ports selected**). Directly **above** the separator, when the primary is disabled, the reason is printed in `.callout` `.primary`, led by the attention symbol — `exclamationmark.circle`, hierarchical, `.orange` — which is hidden from VoiceOver because the words carry the meaning. The text itself is never orange (§3.1).

### 2.4 Why the list is always there

Selecting a row highlights the matching receptacle on the model; hovering or selecting a receptacle highlights the row. The mapping is always live in both directions, on every screen. The model is an accelerator; the list is the canonical, complete truth about this machine, and it is never more than a glance away — not behind a step transition, not behind a sheet, not collapsed into a chip.

### 2.5 Transitions

The wizard advances by replacing **only the working area** with a push transition (leading-edge slide, 0.25 s, `.smooth`). The stage stays put and re-poses; the port list stays put and re-densifies; the footer stays put and re-labels. The model is continuous across every step, which is what makes the app feel like one place rather than eight screens.

The hub (steady state) uses the identical layout, with the footer holding `Set Up Port…` instead of `Continue`, so there is no shape change between browsing and configuring.

### 2.6 Sheets

The app draws sheets for exactly four things: **Adopt**, **Restore**, **Restore All Ports** and **What This All Means**. The system owns the rest: the macOS authorization dialog, and the save panel for a diagnostics file with its failure alert (§S12). Everything else — including every refusal — appears inline in the working area, so the port list and the model stay visible and can point at the thing in the way. Sheets are 480–520 pt wide, standard `.sheet`, headline, body, content, right-aligned button row.

- **A sheet that acts opens over the assistant only on the picker, and only for the route the picker itself names**: a dimmed row's `Restore…`, `Return to Bridge…` or `Adopt…` (§S4). Nothing else opens a sheet over Identify (S4b), Review, Setting up or Ready, except §S13's What This All Means (`RDMALink Help` ⌘?, the toolbar's `Help`), which only reads and leaves the run where it is (§2.7). A sheet raised over the picker opens no second sheet and no second run: its refusals leave out `Stop Managing…` and `Set Up Again…` there (§6.2 R19, R28, R30).
- **A sheet is never replaced from outside it.** While one of the window's sheets is up — on the hub or over the picker — every Port menu item, View › `Change Log`, and Help's `RDMALink Help` and `Save Diagnostics File…` are unavailable: a sheet never stacks on a sheet, and a command that replaced one could drop its checklist mid-burst. Only the sheet's own buttons open another in its place — R19's, R28's and R30's `Stop Managing…`, R30's `Set Up Again…` — and never while its checklist runs.
- **A refusal raised inside a sheet** (§6.1 rule 1) keeps that shape: its buttons sit bottom-trailing like every other sheet's button row. The same refusal card in the working area keeps its row leading.
- **One word for leaving a sheet.** `Cancel` leaves a sheet without doing what it asks — before anything has happened, or, after a partial restore (R20), with the note kept — in every sheet and every one of its refusals; `Done` closes it after something finished, or after reading. No sheet names its way out any other way.
- **A sheet's button row has one order.** The trailing slot is the default's, and `Cancel` sits just before it. A row with no default puts `Cancel` in the trailing slot. The rows in §S9, §S10 and §6.2 list the default first; where each button sits is this rule's.
- **A button row too wide for its sheet breaks onto two lines**, both trailing: the last two buttons, the default's place among them, keep the bottom line, and the rest sit on the line above. No button title is ever truncated.
- **A sheet's default button is never an action that removes something the user didn't ask to remove.** Where the button in the default slot would be one of those — R21's `Remove Service Only`; R28's `Stop Managing…`, which forgets the note that makes putting the port back possible; the same `Stop Managing…` in R30's adopted-note form, which forgets the note when the user asked for a Restore; the stop-managing form's own `Stop Managing` for a note that records the bridges the port came from (a drifted port's, when it has any), which forgets the only way back (§S10); and §S9's `Adopt` on a port RDMALink set up before, whose service has since been replaced by hand, when the old note it replaces records those bridges — the sheet has no default at all and Return presses nothing.
- **Escape is the way out.** Every sheet closes on Escape, as a macOS sheet does. `Cancel` is the sheet's `.cancelAction`, wherever in the row it sits, and every refusal raised inside a sheet keeps it in its row, so the way out is also a button (§6.1 rule 10). A sheet whose only button is `Done` — What This All Means, a Restore sheet's confirmation — closes on Escape too. The one time Escape does nothing is while a sheet's work is running: nothing on screen then is a control, and Escape would be a cancel the app cannot honor (§S6). For the same reason the window's close button and File › Close are unavailable while a sheet's checklist runs, and quitting waits until its last step lands (§S10). No sheet has two defaults or two cancels.
- **A sheet taller than the window scrolls its content; its button row does not.** Every sheet fits a window at §2.1's 600 pt minimum.

### 2.7 Menus

| Menu | Items |
|---|---|
| **RDMALink** | About RDMALink · Settings… ⌘, · Services · Hide · Quit RDMALink ⌘Q |
| **Edit** | Undo ⌘Z (text fields only) · Cut/Copy/Paste — Copy works on the address, on every refusal's details, and on the change log |
| **Port** | Set Up Port… ⌘N · Identify Port… ⌘I · Adopt… · Restore… · Restore All Ports… · Return to Bridge… · Stop Managing… — every item present on every Mac and unavailable when it has nothing to act on; on an unrecognized Mac (R31) all of them are unavailable. `Restore…` is available only when it means one port — the port in hand, or the only noted one — so `Restore All Ports…` is the one name the menu gives the all-ports sheet (§2.8). While the set-up assistant is up nothing here re-enters the run: on the picker, with Identify down and no sheet up, the only items available are the route the picker names for a dimmed row (that row's `Restore…`, `Return to Bridge…` or `Adopt…` — the row last clicked, whose line R27 printed, because the picker's own selection is always a port it can choose) and `Identify Port…`, which starts the picker's Identify (§S4b); on Identify, Review, Setting up and Ready the menu offers nothing. While one of the window's sheets is up it offers nothing either (§2.6) |
| **View** | Check Again ⌘R · — · Back ⌘1 · Front ⌘2 · Left Side ⌘3 · Right Side ⌘4 · Fit ⌘0 · Reset View ⇧⌘0 · Show Technical Names / Hide Technical Names ⌘T · Hide Legend / Show Legend ⌘K · Change Log ⌘L (unavailable while the set-up assistant or one of the window's sheets is up) |
| **Window** | standard |
| **Help** | RDMALink Help ⌘? (unavailable while one of the window's sheets is up) · — · What to Do on the Other Mac (unavailable while the set-up assistant is up) · Save Diagnostics File… (saved as §S12 describes; unavailable while the set-up assistant or one of the window's sheets is up) |

The two View items that switch something on and off are one idiom: a button whose title says what it will do — `Show Technical Names`, which then reads `Hide Technical Names`, and `Hide Legend`, which then reads `Show Legend` — never a checkmark. (Settings keeps its switch, labelled **Show technical names**.) The face items are the other idiom, a group of views of which one is showing, as Finder's View › as Icons … as Gallery are: nouns, in the port list's own face names, with a checkmark on the face the stage is turned to, and unavailable on a Mac that has no ports on that face. `RDMALink Help` opens §S13, whose first section is what RDMA over Thunderbolt is, so the Help menu has no second item for it. `Check Again` ⌘R is the first of the app's View items — after the system's toolbar items, above the face items and a divider — and the one home of ⌘R; the toolbar's `Check Again` runs the same re-check. Settings is a separate small window with a single General pane and therefore **no tab bar**, per HIG.

**Nothing re-enters a run.** While the set-up assistant is up, a command that would start a second run, open a sheet or take the working area is unavailable rather than queued. A sheet that acts opens over the assistant only on the picker, and only for the route the picker itself names (§2.6). `Change Log` and `What to Do on the Other Mac` would take the working area the assistant holds, and `Save Diagnostics File…` would put its save panel over the run as a sheet (§S12), so they wait for it to close. `RDMALink Help` ⌘? is the one exception: What This All Means opens over any step of the run, because it only reads and leaves the run where it is (§2.6).

### 2.8 Persistent affordances

- **Restore is never hidden.** Whenever any restorable note exists — one that records a set-up to undo; a return record (§7.5) is not one — the footer of the hub carries `Restore…` as a plain button beside the primary, and the Port menu's `Restore All Ports…` is enabled. You never have to find a row first. The two `Restore…`s split one way: the footer's means the port in hand, or the only noted one, and otherwise opens Restore All Ports, because nothing beside it offers that sheet; the Port menu's means one port or is unavailable, because `Restore All Ports…` sits right under it and one sheet has one name there. The one exception is an unrecognized Mac (§6.2 R31): the footer holds `Quit` alone, and those two menu items are present and unavailable, like every Port menu item there (§2.7). While the set-up assistant is up the menu leaves the run alone instead (§2.7): the hub's footer is not on screen, `Restore All Ports…` waits, and `Restore…` means only the picker's routed row, when `Restore…` is the route the picker names for it.
- **Unfinished business survives quitting** and appears as a row on the hub the next launch, phrased as a situation and not an alarm: a port that needs putting back by hand, a restart still owed, a port that drifted.

---

## 3. Visual language

### 3.1 Color — semantic tokens only

No custom brand color. No gradients in chrome. The palette is the system's, expressed as named tokens so the mockups and the code agree.

| Token | Value | Used for |
|---|---|---|
| `surface.window` | `.windowBackground` | assistant column, stage background |
| `surface.grouped` | `.controlBackground` | grouped inset lists, value blocks |
| `text.primary` | `.primary` | headlines, row titles |
| `text.secondary` | `.secondary` | body copy, row subtitles |
| `text.tertiary` | `.tertiary` | technical suffixes, disabled rows, disabled inline actions |
| `accent` | **the user's system accent color** (blue by default) | selection, the ready ring, the default button, the configured state, inline borderless actions |
| `attention` | `.orange` | warning **symbols** in the panel only — never text: system orange measures 2.3:1 on the light window background, and text needs 4.5:1. A warning sentence is `.primary` or `.secondary`, led by its orange symbol. Orange means **the user needs to act**, and it is used for exactly that: the reason above a footer separator, an unsatisfied check, drift, a port that needs putting back by hand, RDMA over Thunderbolt switched off (or on and waiting for the restart only the user can do), and a refusal whose way through is the user's to take (R5, R11, R14, R20, R24). A line that only informs — nothing plugged in yet, a dock or a display in the port — carries no symbol at all (§S4, §S5), and a refusal with nothing for the user to do, R22's, keeps `.secondary`. |
| `stop` | `.red` | **used nowhere.** Restore is not styled destructive, because it restores. There is no destructive confirmation in this app. |
| `material.floating` | Liquid Glass, `.glassEffect(.regular)` | the floating stage controls — the face selector, the `Fit` / `Reset View` pair and, while §S8 is up, its `Other Mac:` pop-up |
| `material.label` | `.regularMaterial` | the labels that float over the stage — the narration capsule and the receptacle callout |

**Nothing on the 3D model is ever orange, red, green, or any hue carrying meaning.** Warning is a panel job. A colored hole is unreadable at a glance and fails color-blind users. On the model, meaning is carried entirely by **ring geometry** (see §4).

### 3.2 Type — San Francisco throughout

| Role | Style |
|---|---|
| Headline | `.title2.weight(.semibold)` |
| Headline of a refusal card nested under a screen's own headline (§6.1) | `.headline` |
| Body | `.body`, `.foregroundStyle(.secondary)` |
| Section header | `.footnote`, secondary (standard grouped `Form` header) |
| List row title | `.body` |
| List row detail | `.callout`, secondary |
| Step counter, selection counter | `.caption`, secondary |
| Technical suffix (toggle on) | `.caption`, tertiary |
| The `fe80::` address | `.body.monospaced()`, selectable |
| Timestamps in the change log | `.callout`, secondary |

No display face, no letterspacing, no all-caps, no custom fonts. All text uses system text styles and scales with Dynamic Type.

### 3.3 Iconography — SF Symbols, `.medium`, hierarchical, always paired with text

| Meaning | Symbol |
|---|---|
| Nothing plugged in | `circle.dashed` |
| A device that is not a Mac | `cable.connector` |
| A Mac, link coming up | `bolt.horizontal.circle` |
| A Mac, linked | `bolt.horizontal.circle.fill` |
| USB-only receptacle | `cable.connector.horizontal`, `.tertiary` |
| Member of a bridge | `link` |
| Ready for RDMA (set up by RDMALink) | `checkmark.circle.fill`, accent |
| Ready for RDMA (adopted) | `checkmark.seal.fill`, accent |
| Set up outside RDMALink | `checkmark.circle`, `.secondary` |
| Needs a look (drift) | `exclamationmark.circle`, `.orange` |
| Needs putting back by hand | `hand.raised`, `.orange` |
| A check in progress | `circle.dotted` |
| A satisfied check / completed step | `checkmark.circle.fill`, accent |
| An unsatisfied check | `exclamationmark.circle`, `.orange` |
| The password moment | `lock.shield` |
| Identify | `hand.point.up.left` |
| Restore | `arrow.uturn.backward` |
| Change log | `list.bullet.rectangle` |

No custom glyphs. **No Thunderbolt trade-dress mark anywhere**, in the UI or on the model.

**The app icon.** An Icon Composer icon (`App/AppIcon.icon`), so macOS renders it in Liquid Glass like its own and makes the dark, tinted and clear appearances itself; a flat pre-rendered picture looks like a sticker beside them. Two layers. The background is a light aluminium-silver fill, lighter at the top, in the family of Apple's own utilities. The foreground is one object: a single Thunderbolt receptacle drawn large, about 70 % of the canvas wide, as clean vector shapes — the rounded slot with its dark interior, and the accent ring of a port that is ready. No painted glow, shadow or highlight: the system's glass supplies those. Nothing else: no cable, bolt, Thunderbolt mark, text or Mac silhouette. It has to read at 16 pt as a blue ring around a dark slot on silver.

### 3.4 3D materials and lighting

- **One generic rounded-box chassis per archetype.** Correct proportions and correct receptacle placement. No logo, no engraved text, no trade dress of any kind, and no vent pattern beyond a soft inset — except the Mac Studio's perforated back grille, drawn as a hole field in the recess tone above the port row, which carries no logo and no trade dress.
- **No stand-in.** An unrecognized Mac gets no chassis at all: the stage shows R31's block (§6.2) where the model would be. A plain box would still be a picture of a Mac the app does not know, and every hole on it a claim.
- `PhysicallyBasedMaterial`, roughness 0.38, metallic 0.85, base color the aluminium's own silver (0.78 luminance) in **both** appearances. There is no dark Mac Studio or Mac mini, and macOS does not report a MacBook Pro's finish, so silver is the honest default everywhere: **dark mode changes the light, never the metal.**
- **Receptacles are true geometry** — a 3 mm-scale inset slot with a darker interior — so an unlit port reads as a hole and not a sticker. USB-only receptacles use their correct, slightly different geometry with a matte, non-reflective interior, so they look different before anyone explains why.
- **Lighting:** one neutral studio IBL (≈900 lux equivalent) plus a single key `DirectionalLight` from upper-left for a defined top edge; a soft contact shadow on an invisible ground plane. No mirror reflection, no floor grid, no diorama.
- **In dark mode** the IBL swaps to a dimmer neutral, the chassis keeps its silver, a cool rim light carries the silhouette, the ink tone of the rings adapts so they still read against the metal, and the accent ring brightens one step to hold contrast.
- **The stage background is `.windowBackground`** with a very shallow radial lift behind the chassis, in **both** appearances. The stage follows the system theme like every other surface; it is never a permanently dark slab inside a light window.
- **Camera:** `PerspectiveCamera`, 35 mm-equivalent. Orbit constrained to ±35° elevation so the user can never end up under the machine; roll locked; dolly limited to a 1.4× range **and floored** so a receptacle's on-screen hit target never falls below 24 × 24 pt (see §8).

### 3.5 Motion — three verbs only

1. **Camera moves.** 0.7 s, ease-in-ease-out, along a spherical arc with a simultaneous 4 % dolly-out and back. **Always preceded or accompanied by a line of copy naming the move.**
2. **State changes.** Rings, ribbons and glows cross-fade in 150 ms with `.smooth`. No bounce, no overshoot.
3. **Progress.** The segmented ring closes clockwise, one gap per **real completed step**, never on a timer, so a stall looks like a stall.

Nothing loops except the "link coming up" breath (1.6 s, 8 → 18 % opacity) and the Identify shimmer, and both stop the instant they have an answer. Nothing in the app flashes faster than 1.6 s; nothing exceeds three flashes per second. **No audio. No haptics.**

### 3.6 Light / dark and the accessibility appearances

- Full light/dark support, driven by the system, including the stage.
- **Increase Contrast:** every ring track goes from 1.5 pt to 3 pt and gains a contrasting halo; the receptacle interior's contrast against the chassis rises; every list badge gains a 1 pt border; every floating control capsule on the stage gains a hairline.
- **Reduce Transparency:** every floating control capsule on the stage becomes opaque.
- **Reduce Motion:** camera arcs become a 100 ms cross-fade between fixed poses **with the same spoken and written narration**; the Identify shimmer becomes a static dim ring; the apply ring steps between five static states; the ribbon retraction becomes an opacity change; the address appears rather than fading; §S8's ghost changes to the Mac just chosen rather than cross-fading.
- **Differentiate Without Color** is the default behavior, not a mode (see §4.6).

---

## 4. The 3D model & port states

### 4.1 Principle: two axes, never conflated, plus interaction on top

Every receptacle carries up to **three concentric ring tracks**, drawn just outside the slot geometry at 1.5 pt (3 pt under Increase Contrast):

| Track | Answers | Radius |
|---|---|---|
| **Inner — hardware** | What is physically plugged in right now | closest to the slot |
| **Outer — configuration** | What the network settings say about this port | one ring-width out |
| **Interaction** | Hover / selection / focus | outermost, accent |

Collapsing "a Mac is plugged in" and "this port is configured" into a single indicator is exactly how people misread network state. The app refuses to.

Only three tones are ever used on the model: `.secondary`, `accent`, and the unlit recess.

### 4.2 Inner track — what is plugged in (four states)

**1. Empty**
- Model: **no inner ring.** Receptacle interior at its darkest, reading as a hole.
- Panel: `circle.dashed` · **"Nothing plugged in"**
- Selectable. Preparing an empty port is legitimate; the panel says the address arrives later.

**2. A device that is not a Mac (dock, display, drive)**
- Model: a short neutral plug stub fills the receptacle mouth in a matte grey that deliberately does **not** match the chassis, so it reads as foreign. **No inner ring.**
- Panel: `cable.connector` · **"A device is connected — not a Mac"** · detail **"This looks like a dock or a display."**
- **Selectable.** A dock or display on a port is a fact, not a problem: changing the port's network service does not disturb DisplayPort alt mode or USB data. The review screen carries an informational line, not a block.

**3. A Mac is here, the link is still coming up**
- Model: plug stub plus a thin `.secondary` inner ring **breathing** between 8 % and 18 % opacity on a 1.6 s cycle — slow enough to read as "working on it", never as an alarm.
- Panel: `bolt.horizontal.circle` · **"Another Mac is here. The link is still coming up."**

**4. A Mac is linked**
- Model: plug stub plus a **steady** `.secondary` inner ring at full opacity, plus a short **light thread** that leaves the receptacle along the cable direction and fades out 40 pt from the frame edge. It is one continuous tube — a smooth curve with the sag of a real cable, tapering gently and fading along its length — never a chain of visible segments. The thread is the only ornament in the entire scene, and it exists only when a real Mac is really linked, which is what keeps it honest. While §S8's handoff draws its line, no receptacle draws a thread of its own: the line is its port's cable, and it has to be the only link on the stage — two cables from one receptacle, or a second one beside it, read as two links.
- Panel: `bolt.horizontal.circle.fill` · **"Linked to another Mac"**

### 4.3 Outer track — what the configuration says (five states)

**In a bridge — segmented ring.** Four arcs with four gaps, `.secondary`. Reads as "attached to something else." Membership in a second, inactive bridge looks **identical on the model** — the model shows the fact, the panel carries the count:
- `link` · **"In the Thunderbolt Bridge"**
- `link` · **"In two bridges, including one that isn't in use"**

A port in a bridge that has never been set up, with no service of its own, carries the trailing button `Set Up…` (§S1).

This segmented ring is the same geometry that **closes during apply** and **re-opens during restore**, so the whole lifecycle of a port is one shape.

**Standalone, no service — no outer ring.** Panel detail: **"Not in any bridge"** · trailing buttons `Set Up…` and `Return to Bridge…` (§S1, §7.5).

**Ready for RDMA — a solid, unbroken accent ring** at full opacity with a soft bloom, and no glyph of any kind on the model. Panel: `checkmark.circle.fill` accent · **"Ready for RDMA"** with the `fe80::` address on the detail line.

*Provenance is a panel matter, not a model matter.* A port RDMALink set up and a port RDMALink adopted are both simply **ready**, and the model says so identically; the panel distinguishes them (`checkmark.circle.fill` vs `checkmark.seal.fill`, and the words **"set up by you, looked after by RDMALink"**). The model states facts about the hardware and its configuration; who made the configuration is history, and history lives in the panel and the change log.

**Set up outside RDMALink (adopt candidate) — a solid double-hairline ring** in `.secondary`: complete, like the ready state, but drawn as two thin concentric hairlines rather than one solid ring, and not in accent, because it is not RDMALink's. Panel: `checkmark.circle` `.secondary` · **"Set up outside RDMALink"** · trailing button `Adopt…`

**Needs a look (drift) — a dashed ring** in `.secondary`. The service RDMALink created has gone from a port that was in no bridge when it was set up, or the port is back in a bridge, or its service has been edited or replaced — replaced even by exactly what RDMALink would have made, which is ready but isn't RDMALink's until the port is adopted (§S9). Panel: `exclamationmark.circle` `.orange` · **"Not set up any more"**. Drift is only ever about a setup RDMALink made or adopted. A port whose note records the bridges it came from, and that is now in no bridge and has no service — R11's or R20's kept note, or a service RDMALink made that was removed by hand — needs putting back by hand; it wears the same dashed ring, and its panel says so in its own words: `hand.raised` `.orange` · **"Needs putting back by hand"**, with `Restore…` (§S1).

**Returned to the bridge — the plain bridged ring.** A port RDMALink itself put back into Thunderbolt Bridge (§7.5) while its note is still there. Provenance is a panel matter: the ring says only that the port is in the bridge. Panel: `arrow.uturn.backward.circle` `.secondary` · **"Returned by RDMALink"** · trailing button `Set Up Again…`. (Not "back in the bridge": `Back` is a face name, and the row's membership phrase already says the port is in the bridge.) It is not drift and raises no situation row.

### 4.4 The bridge ribbon

Bridge membership is additionally drawn as a **soft translucent ribbon** arcing across the chassis surface between the members of the same bridge, in `.secondary` tone at low opacity. An **inactive** bridge draws the same ribbon at 40 % of that opacity with a marginally cooler value.

The ribbon appears on hover, on selection, throughout review, apply, and restore, and whenever the port list's bridge row is hovered. It is **tone and geometry, never a color channel**: it adds no hue, and it never replaces the segmented ring, which remains the primary state signal.

The ribbon is what makes the hardest rule in the product visible rather than merely stated — *a port must be out of **every** bridge, even an inactive one*. During apply, the ribbon detaches from the chosen receptacle and retracts into the remaining members, in the same beat that the first gap in the segmented ring closes.

### 4.5 USB-only receptacles

Modeled with the correct, slightly different geometry and a matte, non-reflective interior.

- They **never take a ring** of any kind. They never take a hover glow. The cursor becomes `.operationNotAllowed` over them — the model refuses before the panel has to explain.
- If a cable is physically in one, it is the only place a plug stub appears on that face, and the hub shows a tip row unprompted.
- Panel: `cable.connector.horizontal` `.tertiary` · **"USB only — this one isn't Thunderbolt"**. The row is dimmed to 45 % and is not selectable.
- Clicking one produces the USB copy inline (R3), never a disabled-button dead end.

### 4.6 Interaction track, and the no-color rule

- **Hover:** a 45 %-opacity accent ring outside the state rings, fading in over 150 ms, plus the matching list row highlights.
- **Selection:** 2 pt full accent with a soft bloom.
- **Keyboard focus:** a distinct focus halo, visually separate from both hover and selection.
- Interaction **sits on top of state and never replaces it.** A selected bridged port shows all three: accent selection outermost, segmented `.secondary` outer track, breathing or steady inner track — which is precisely the situation the review screen is about to resolve.

**Differentiate Without Color is the default behavior.** Every state on the model is a distinct ring **geometry** (none / breathing / steady / segmented / solid / double hairline / dashed) and every state in the panel is a distinct SF Symbol **plus words**. Nothing anywhere in the app depends on hue, so nothing is lost in greyscale.

### 4.7 Position names

Always physical, never numeric unless nothing better exists.

| Hardware | Names, in physical order |
|---|---|
| Mac Studio, 4 TB5 (M4 Max / M5 Max) | `Back, far left` · `Back, middle left` · `Back, middle right` · `Back, far right` · `Front, left` (USB only) · `Front, right` (USB only) |
| Mac Studio, 6 TB5 (M3 Ultra / M5 Ultra) | the same back four, plus `Front, left` · `Front, right` (both Thunderbolt) |
| Mac mini (M4 / M4 Pro / M5 Pro / M6) | `Back, left` · `Back, middle` · `Back, right` · `Front, left` (USB only) · `Front, right` (USB only) |
| MacBook Pro 14/16 | `Left side, rear` · `Left side, front` · `Right side` |
| Unrecognized Mac (R31), or a recognized Mac whose positions are unavailable | `Thunderbolt port 1` … `Thunderbolt port N`; on a recognized Mac **Identify is promoted** to compensate |

**Recognition.** A Mac is recognized by its model identifier when the catalogue lists it. Otherwise it is recognized by two facts it states itself: the product family macOS publishes for it (`Mac Studio`, `Mac mini`, `MacBook Pro`) together with a Thunderbolt receptacle layout that matches that family's table exactly, receptacle for receptacle — every reported position has a name in the table, no two share one, and no table position is missing. Both must agree. When either is absent or differs, the Mac is unrecognized and the app is in R31's read-only mode: no model, numbered ports, and nothing changed. Nothing is ever inferred from the chip or from the port count alone.

With **Show technical names** on, a `.caption` tertiary suffix is appended to the row's detail line only — `en6` — and nowhere else. **No text is ever drawn on the 3D model, regardless of this toggle.**

---

### 4.8 The legend and the receptacle callout

The rings say what the words say; two small aids make sure nobody has to guess which is which.

**Legend.** A `.caption` `.secondary` list in the stage's top-leading corner, one line per outer-ring shape **present on this Mac right now**, glyph first: the ring geometries themselves at small scale. Their labels are the panel's own words — **In a bridge** · **Standalone** · **Set up outside RDMALink** · **Ready for RDMA** · **Needs a look**. Nothing about the inner track, nothing about selection, no title. One line joins them, last, only while §S8's handoff is up: a small faint box and **The other Mac**, naming the ghost second Mac, because nothing is ever written on the ghost itself; the line comes and goes with the ghost. It keeps that box and those words whatever §S8's `Other Mac:` pop-up draws the ghost as: the pop-up already names the model, and the legend names the part it plays. Its label is a name for a picture, not a word from the panel, and the ghost it names is a sighted aid like the rings: §S8's screen says the same in words. The legend is shown whenever the rings are live, hidden with View › **Hide Legend** ⌘K (which then reads **Show Legend**), and the choice is remembered. It never overlaps a receptacle: it yields to the model by moving to the top-trailing corner when the chassis reaches under it and that corner is clear — while §S8's `Other Mac:` pop-up holds that corner the legend stays where it is, and the handoff has pulled this Mac back into the leading third, clear of it.

**Callout.** Resting on a receptacle (300 ms, as a tooltip) or moving keyboard focus to it shows a small callout beside it with **the row's title and detail line, verbatim** — "Back, far left" over "Nothing plugged in · In the Thunderbolt Bridge" — and, when technical names are on, the row's technical line too. A USB-only receptacle's callout is its own subtitle, **USB only — this one isn't Thunderbolt**. The callout fades with the hover, says nothing the list does not say, and is never the only place a fact lives. It never covers §S8's `Other Mac:` pop-up: where it would reach it above the receptacle's row, it drops below the row instead. Neither the legend nor the callout exists on an unrecognized Mac (R31), which has no rings.

## 5. Screen-by-screen specification

> Screens are listed in the order a first-time user meets them. The internal milestone label is given for the build plan only and is never shown.

---

### S0 — Getting to know this Mac *(ML0)*

**Purpose.** Cover the 0.3–2 s hardware and network probe without a splash screen, and establish the stage as the place where the truth about this Mac lives.

**Layout.** The full window appears immediately in its final shape — nothing jumps when the probe resolves. The port list band shows skeleton rows (three generic rows until the receptacle count is known, then the real count with empty badges). The working area shows a small inline `ProgressView` beside the headline and one body line. **The footer holds no buttons at all**, so the user is never tempted to click through a scan.

**Copy.**
- Headline: **Getting to know this Mac**
- Body: **Checking the Thunderbolt ports, the network, and whether RDMA is turned on.**
- Slow state (after 3 s), replaces body: **Still looking. Some Thunderbolt information takes a few seconds to arrive.**
- Window subtitle, as soon as it's known: **Studio — Mac Studio (M3 Ultra)**

**States.** Probing (default, under 3 s) · Slow probe (over 3 s) · Hardware readable but model unrecognized → hub in generic mode · Cannot read Thunderbolt hardware → R24 · macOS older than 27 → R25.

**3D behavior.** The correct chassis is present from the first frame at its resting three-quarter pose, facing the default face (back for desktops, left for notebooks), receptacles unlit and slightly recessed. No rotation, no float, no idle animation. When the probe completes, the receptacles **wake left to right with a 60 ms stagger over roughly 300 ms** — a single readable beat that says *found them all* — then stillness. It happens once per launch and never repeats. Under Reduce Motion they appear together.

---

### S1 — Overview (the hub) *(ML0 read-only, ML1 entry point; also the steady state on every later launch)*

**Purpose.** What this Mac is, whether RDMA is on, which ports exist and what each is doing, what has already been set up, and what — if anything — is unfinished.

**Layout.** Stage live. Working area: headline, one body line, then a grouped inset **This Mac** section of three read-only rows, plus any situation rows. Port list in **full** density below it. Footer: `Quit` as a plain button at the leading edge — the hub is the place people arrive back at when the work is done, and `Set Up Port…` is an offer, not a demand, so the way out is beside it and not only in the menu — then, trailing, `Set Up Port…` as the default button with `Restore…` as a plain button beside it whenever a restorable note exists (§2.8). While the change log (§S11) or the other-Mac screen (§S8) holds the working area, band 4 is that screen's own footer, ending in its `Done`, and this footer — `Quit`, `Restore…`, `Set Up Port…` and the link row under the list — steps aside until `Done` brings it back (§2.3 band 4). `Quit` quits the app exactly as ⌘Q does, asks nothing, and is present in every hub state, R23 and R31 included; it appears on no other screen. A `.caption` link row under the list, in the accent like every inline action in the column (§2.3 band 3): `Change Log` · `What This All Means`.

**Primary action.** `Set Up Port…`, the same words as the Port menu's ⌘N, however many ports are already ready. It always opens the picker, as step 1 of 3, with the port selected here already chosen when set-up can take it (§S4).

**Copy — headlines and body**
- First run headline: **Set up a Thunderbolt link**
- First run body: **RDMALink prepares one Thunderbolt port on this Mac so it can carry RDMA straight to another Mac. You'll do the same on the other Mac afterwards.**
- One port ready: **One port is ready for RDMA**
- Two or more ready: **Two ports are ready for RDMA**
- Steady-state body. It agrees with the headline: it names every ready port, in physical order, and says which have a Mac linked and which are waiting for one.
  - One port: **Back, far left is set up and linked. Nothing else on this Mac was changed.** · **Back, far left is set up and waiting for a Mac. Nothing else on this Mac was changed.**
  - Several, all alike: **Back, far left and Back, far right are set up and linked. Nothing else on this Mac was changed.** · **Back, far left and Back, far right are set up and waiting for a Mac. Nothing else on this Mac was changed.**
  - Several, some linked: **Back, far left is set up and linked, and Back, far right is set up and waiting for a Mac. Nothing else on this Mac was changed.** — each half in the plural when it names more than one port (**Back, far left and Front, left are set up and linked, and Back, far right is set up and waiting for a Mac.**)
  - **Nothing else on this Mac was changed.** is left off whenever a note RDMALink keeps says it changed something else on this Mac — a port it returned to the bridge (§7.5), a drifted port, a port that needs putting back by hand. The sentence is only ever printed when it is true (§1.3 rule 10).

**Copy — "This Mac" section**
- Section header: **This Mac**
- **RDMA over Thunderbolt — On**
- **RDMA over Thunderbolt — Off. Turn it on to finish.** *[Turn It On…]*
- **RDMA over Thunderbolt — Off** — with no button, on R23's and R31's read-only hubs: RDMALink sets nothing up there, so there is nothing to finish
- **RDMA over Thunderbolt — On after you restart**
- **RDMA over Thunderbolt — On, but no RDMA devices appeared** *[Tell Me More]*
- **Thunderbolt Bridge — Four ports are members**
- **Thunderbolt Bridge — Not in use**
- **Thunderbolt Bridge — Two bridges, one of them unused**
- **Ports ready for RDMA — None yet**
- **Ports ready for RDMA — Back, far left**
- **Ports ready for RDMA — Back, far left and Back, far right**
- **Ports ready for RDMA — None by RDMALink · five set up outside it** (only ports set up outside RDMALink are ready — a drifted port whose service was replaced by hand with a full match among them; counts are spelled out, and "one set up outside it" in the singular)
- **Ports ready for RDMA — Back, far left · two more set up outside RDMALink** (both kinds; "one more" in the singular)

**Copy — situation rows** (appear above the port list, at most one of each, in this order)
- Needs a hand: **Back, far left needs putting back by hand.** *[Show Me]*
- Drift: **Back, far left isn't set up any more.** · detail: **The network service RDMALink made is gone — it may have been removed in System Settings.** *[Set Up Again…]* *[Stop Managing…]* — the first button is the port row's own, so a drifted port with a service of its own offers `Restore…` or `Adopt…` here as its row does, or nothing when its row offers nothing, never `Set Up Again…`; the second opens S10's stop-managing form, which forgets the note, changes nothing, and — when the note records the bridges the port came from — says RDMALink won't be able to put the port back afterwards (§S10); and the detail line is left off while the service RDMALink made is still there, edited.
- Restart owed: **RDMA is switched on and waiting for a restart. Restart whenever it suits you.**
- USB tip: **There's a cable in a front port. Those carry USB, not Thunderbolt. Move it to one of the four ports on the back and RDMALink will follow along.**
- Two Macs tip: **Two Macs are connected. Leave just one cable in place while you set up — two can send Ethernet traffic around in a loop.** Shown only when R1 would fire — two ports with a Mac on the end share a bridge — and never for cables on standalone ports.

**Copy — port list section and rows**
- Section headers: **Thunderbolt ports** · **Back** · **Front** · **Left side** · **Right side**
- Subtitles — **Nothing plugged in** · **A device is connected — not a Mac** · **Another Mac is here. The link is still coming up.** · **Linked to another Mac** · **USB only — this one isn't Thunderbolt**
- Membership appended after a middle dot: **· In the Thunderbolt Bridge** · **· In two bridges, including one that isn't in use** · **· Not in any bridge**
- Ready: **Ready for RDMA · fe80::a2d1:73b4:9e0c:5f16%en6**
- Ready, adopted: **Ready for RDMA · set up by you, looked after by RDMALink**
- Ready, nothing attached: **Ready for RDMA · the address appears when a Mac arrives**
- Never set up (a Thunderbolt port with no setup and no service of its own): the link-state subtitle and the membership phrase *[Set Up…]* — out of every bridge, it carries **Return to Bridge…** after it (§7.5).
- Set up elsewhere: **Set up outside RDMALink** *[Adopt…]*
- Drifted: **Not set up any more** *[Set Up Again…]* — except a drifted port with a service of its own (a near match, with IPv4 or IPv6 set otherwise, §S9; a fixed IPv4 address; or a full match made by hand after the service RDMALink made went), which splits by identity: when the service is still the one RDMALink made, edited by hand since, the row offers **Restore…**, which raises R28 and says what changed; when it is a new service made by hand, a near match or a full match, the row offers **Adopt…** (§S9) — or no button at all when Adopt can't take it either: a fixed IPv4 address, or a service on a port still in a bridge (R16). None of them offers **Set Up Again…**: set-up routes a port with a service of its own to Adopt and never plans it (R27), and refuses a fixed IPv4 address (R16). A full match standing where RDMALink's service used to be is ready, but it isn't RDMALink's: the row stays drift until the port is adopted, and never reads **Ready for RDMA** with `Restore…`, which would claim a set-up RDMALink no longer has.
- Needs putting back by hand (a note that records the bridges the port came from — kept by R11 or R20, for example, or left behind when the service RDMALink made was removed in System Settings — over a port that is now in no bridge and has no service): **Needs putting back by hand** *[Restore…]*, with `hand.raised` in `.orange` (§3.3). Never a set-up button: setting it up would write a fresh note over the only record of where the port came from, and Core refuses to (R20).
- Returned to the bridge by RDMALink (§7.5), note still there: **Returned by RDMALink** *[Set Up Again…]* — the link-state subtitle and the membership phrase stay (**Returned by RDMALink · Nothing plugged in · In the Thunderbolt Bridge**); this is not drift and adds no situation row.
- Trailing buttons, by state: *[Set Up…]* · *[Adopt…]* · *[Restore…]* · *[Return to Bridge…]* · *[Stop Managing…]* · *[Set Up Again…]*
- Every Thunderbolt port that can be set up carries exactly one set-up button on its row — **Set Up…** if it has never been set up, **Set Up Again…** if its setup has gone or RDMALink returned it to the bridge — so every port that can be set up visibly can be; a row with no button reads as a port that can't be. A port that has never been set up but has a service of its own is not one set-up takes, and carries no **Set Up…**: S9's near match is offered **Adopt…**, and R16's port is refused — and so is a port with a service of its own that is still in a bridge, which Adopt can't take either (§7.3), so its row carries no button at all. A row's set-up button, either one, is the footer's **Set Up Port…** for that one port, on the same terms — and so is the drift situation row's **Set Up Again…**, and so are the change log's and R30's, which appear only when the port's own row offers that set-up action: absent in R23's and R31's read-only modes, and disabled while two Macs are connected, with the reason printed above the footer separator: **Unplug one of the two cables to set up a port.** Every one of them goes through one door, which refuses whenever the footer's would be disabled. A button that names its port opens Review for it directly, as step 1 of 2; the footer's opens the picker (§S4). Two set-up buttons side by side are never on different terms.
- Adopted or set up elsewhere (any port that is out of the bridge and that RDMALink did not set up): the row carries **Return to Bridge…**, so putting a port back never depends on how it was removed. A port RDMALink set up carries **Restore…** instead, which returns it exactly.

**Copy — buttons**
- **Quit** · **Set Up Port…** · **Set Up…** (on a row, which already names the port; the footer and the Port menu keep **Set Up Port…**) · **Set Up Again…** · **Restore…** · **Stop Managing…** · **Check Again** · **Change Log** · **What This All Means** · **Turn It On…** · **Tell Me More** · **Show Me**
- `Stop Managing…` forgets RDMALink's note for a port that is still on this Mac and changes nothing on it: an adopted port's, a return record's, or a drifted port's. It always opens S10's stop-managing form, which says what goes. It is never offered on a port RDMALink set up that is still ready, whose way back is `Restore…`, nor on one that needs putting back by hand, whose note is the only record of where it came from. A note for a port that is not on this Mac any more has nothing to manage and is cleared from the change log with `Forget This Note` (§S11).

**Copy — Thunderbolt 4 mode**
- Headline: **Nothing to configure here**
- Body: **This Mac has Thunderbolt 4 ports. RDMA over Thunderbolt needs Thunderbolt 5, so there's nothing for RDMALink to set up. You're welcome to look around — everything you see is real.**
- The footer's primary button is **absent**, not disabled, and so is every row's set-up button, `Set Up…` and `Set Up Again…` alike. `Identify Port…` remains available in the Port menu, because it changes nothing and the app is still a useful map.
- With RDMA switched off, the This Mac row reads **RDMA over Thunderbolt — Off** and carries no `Turn It On…`: there is nothing here for it to finish.

**Copy — Unrecognized Mac (R31)**
- Headline: **RDMALink doesn't recognize this Mac**
- Body: **RDMALink only draws, and only changes, Macs it knows — and this isn't one of them. So there's no picture, and nothing here will be changed. The ports below are listed the way macOS reports them, and everything you see is real.**
- The footer holds `Quit` and nothing else, and no row has a button: nothing that writes — set-up, Restore, Adopt, Return to Bridge, Stop Managing — is offered in the window. The Port menu keeps its shape, as menus do: every item is present and unavailable, `Identify Port…` included, because there is no model for it to point at. The stage shows R31's block (§6.2) in place of a model.
- With RDMA switched off, the This Mac row reads **RDMA over Thunderbolt — Off** and carries no `Turn It On…`, as on a Thunderbolt 4 Mac.

**States.** First run with RDMA on · First run with RDMA off · Restart pending · One or more ready · An adoptable port present · A drifted port present · A port needing a hand · Cable in a USB-only port · Two Macs connected (the tip row appears, and `Set Up Port…` and every set-up button on a row — `Set Up…` and `Set Up Again…` — are **disabled** with the reason printed above the footer separator, **Unplug one of the two cables to set up a port.**) · Thunderbolt 4 read-only (R23) · Unrecognized Mac read-only (R31) · Live update arrives.

**3D behavior.** Fully live. On an unrecognized Mac (R31) there is no model and the rows have nothing to light. Every receptacle carries its tracks. Hovering a row lifts the matching receptacle's glow to 40 %; hovering a receptacle highlights the row; hovering a bridge-membership subtitle draws the ribbon. Clicking a receptacle selects its row; double-clicking a configurable one — a port set-up can take, by the same test as its row's **Set Up…** — opens Review for it, exactly as that button does (§S4).

The camera **holds** the resting three-quarter pose and never moves on its own here, with exactly one exception: if a port on a face you are not looking at changes state, the other face-selector segment takes a small accent dot and the working area offers a single inline line — **"Something changed on the back."** *[Show Me]* — which is the only camera move the app ever makes unasked, and it is asked.

---

### S2 — Turn on RDMA over Thunderbolt *(ML0)*

**Purpose.** Explain the one thing the app cannot do, hand off to System Settings, and be waiting when the user comes back from the restart. Reached from the hub's status row. Until this screen is built, that row's `Turn It On…` opens System Settings › Privacy & Security › Developer Tools directly.

**Layout.** The stage dims to 40 % opacity and desaturates — the model is not the subject here, and saying so visually is more honest than hiding it. Working area: headline, body, a numbered three-step list in a grouped inset box, then a live **Right now** row. Port list in compact density, also dimmed. Footer, in §2.3 band 4's one order: `Done` leading — the way back to the hub, and Escape's — then `Set Up Ports First…` and `Check Again` just before `Open System Settings`, the default, trailing. The helper line about `Set Up Ports First…` sits in the working area, under the **Right now** row, so band 4 stays one row of buttons.

**Copy.**
- Headline: **Turn on RDMA over Thunderbolt**
- Body: **This one is a system setting, so it lives in System Settings and needs a restart. RDMALink can't flip it for you — but it will notice the moment it's on.**
- Step 1: **Open System Settings, then Privacy & Security, then Developer Tools.**
- Step 2: **Turn on RDMA over Thunderbolt.**
- Step 3: **Restart this Mac. RDMALink will be right here.**
- Right now — off: **Right now — off**
- Right now — pending: **Right now — on, waiting for a restart**
- Right now — on: **Right now — on, and the RDMA devices are here**
- Restart-pending headline: **Almost there**
- Restart-pending body: **RDMA is switched on, but it only takes effect after a restart. Restart whenever it suits you and come back.**
- On headline: **RDMA over Thunderbolt is on**
- On body: **Good. Now get a port ready for it.**
- Welcome-back headline (first launch after the restart): **Welcome back. RDMA over Thunderbolt is on.**
- Welcome-back body: **The RDMA devices are here now — one for each Thunderbolt controller. That was the part only you could do.**
- On-but-nothing-appeared headline: **RDMA is on, but no RDMA devices appeared**
- On-but-nothing-appeared body: **That usually means this Mac, or this version of macOS, doesn't offer RDMA over Thunderbolt. Setting up a port is still harmless and still undoable — it just won't have anything to carry yet.**
- Fallback when System Settings won't open: **RDMALink couldn't open System Settings. Here are the steps to follow by hand.** *[Copy These Steps]*
- Buttons: **Open System Settings** · **Check Again** · **Set Up Ports First…** · **Done** · **Copy These Steps** — `Set Up Ports First…` opens the set-up assistant, where the choosing is still to do, so it carries the ellipsis (§1.3 rule 11)
- Helper line, in the working area under the **Right now** row: **You can prepare the ports now and turn RDMA on later. RDMALink will remind you.**

**States.** Off · On in NVRAM but no devices yet · On and devices present (this screen is skipped entirely unless the user navigated here deliberately) · On after a restart but still no devices → R22 · Still off after a restart · System Settings could not be opened.

**3D behavior.** The model stays on screen at 40 % opacity and zero saturation, still and quiet, as a reminder of where you are rather than a participant. No rings, no hover. When the user returns and the app re-detects, color and opacity come back over 300 ms — the visual equivalent of picking up where it left off.

---

### S3 — The four checks *(ML1 — evaluated on S5, not a screen of their own)*

**Purpose.** Check every hard rule the app can measure, so the user is never asked to promise something. **Nothing here is a checkbox, and nothing here can be waved through.** The checks are not a screen: a page of four green ticks with a Continue button asks nothing of anyone, so they live at the top of S5 as its **Checked** group, collapsed when every one is satisfied and expanded when one is not.

**Rows.** Each row: symbol (`checkmark.circle.fill` accent when satisfied, `exclamationmark.circle` `.orange` when not, `circle.dotted` while checking), a title, a `.callout` secondary line carrying the **actual finding**, and a trailing borderless action button only where one helps. Any port a check refers to takes a soft attention ring on the stage.

**Copy.**
- Group label, all satisfied (the collapsed disclosure's one line): **Checked: one cable, nothing mounted, another way in, room for the undo note.**
- Group label, something unsatisfied: **Checked — one thing to sort out first** / **Checked — two things to sort out first** / **Checked — three things to sort out first** / **Checked — four things to sort out first**

| # | Title | Satisfied | Unsatisfied | Button |
|---|---|---|---|---|
| 1 | **One Thunderbolt cable to another Mac** | **Just one, in Back, far left. Perfect.** / **No other Mac is connected yet. That's fine — you can prepare a port now and plug in later.** / **Cables in Back, far left and Back, far right, and no bridge holds more than one of them — nothing can loop.** (two or more cables whose ports share no bridge: a finished set-up) | **Two Macs are connected, on Back, far left and Back, far right. Unplug one and RDMALink will pick this back up.** / **Both ends of one cable are in this Mac, on Back, far left and Back, far right. Unplug one end and put it in the other Mac.** | — |
| 2 | **Nothing mounted over Thunderbolt** | **Nothing is mounted. Good.** | **The volume Vault is mounted over Thunderbolt. Eject it in Finder so nothing gets interrupted.** | **Show in Finder** |
| 3 | **Another way to reach this Mac** | **Wi-Fi is connected, so changing a Thunderbolt port won't cut you off.** | **Right now, Thunderbolt is the only way this Mac is reachable. Changing a port can briefly interrupt the whole bridge — not just that one port — so connect Wi-Fi or Ethernet before RDMALink touches it.** | **Open Network Settings** |
| 4 | **Room to save an undo note** | **RDMALink can save its notes, so anything it changes can be put back.** | **RDMALink can't write its notes folder, so it couldn't put things back afterwards. It won't change anything it can't undo.** | **Show Notes in Finder** |

- Reasons printed above S5's footer separator while a check is unsatisfied (the default button is disabled, not removed, because these clear by themselves): **Unplug one of the two cables to continue.** · **Unplug one end of that cable to continue.** · **Eject Vault to continue.** · **Connect Wi-Fi or Ethernet to continue.** · **RDMALink needs somewhere to save its notes before it can continue.**
- Button, in the group's header while something is unsatisfied: **Check Again**

**States.** All four satisfied (collapsed) · Two Macs connected (R1) · Cable looped back into this Mac (R2) · No Mac connected (satisfied, with the gentle note) · A volume mounted over Thunderbolt (R4) · Only reachable over Thunderbolt (R5, **hard refusal**) · Baseline folder unwritable (R14, **hard refusal**) · Managed by a configuration profile (R13, hard refusal, replaces the whole of S5's working area) · Re-checking (rows animate individually, the default button greys for the duration) · A check flips live (unplugging the second cable satisfies row 1 in the same beat, with no click).

**3D behavior.** When a check names a port, that receptacle takes a 1.5 pt attention ring in `.secondary` and a single 1.6 s breath, and the camera turns to the face it is on if it isn't already visible — with the working area printing **"Turning the Mac around"** for the duration of the move. With two Macs connected, both receptacles ring simultaneously and a faint light thread leaves each one, **making the loop visible rather than described**; when the user unplugs one, its ring and thread fade and the check flips to satisfied in the same beat, with no click.

---

### S4 — Choose a port *(ML1 single port; ML2 multi-select, Identify, USB trap, all archetypes)*

**Purpose.** Turn *"which hole"* into a two-second decision by making the model and the list one selection.

**Layout.** Stage is the subject: full strength, face selector visible, hover states live. Working area: headline, body, the pre-selection rationale line if there is one, then a borderless `Identify Port…` button, left-aligned. The button declares no shortcut of its own: ⌘I is the Port menu's, and on this screen it starts the same Identify (§S4b, §2.7). The port list is in **full** density and every row is a selection target; non-selectable rows are dimmed with an explanatory subtitle. A row that can be chosen carries **no button** here: choosing it is the action, and the hub's `Set Up…` or `Set Up Again…` beside it would be a second way into the run already under way. A dimmed row keeps only the route this screen names for it: `Restore…` on a port RDMALink set up that is already ready, that needs putting back by hand, or whose own service RDMALink made has been edited since; `Return to Bridge…` on an adopted port that is already ready, which has no exact Restore (§7.3); `Adopt…` on a port set up by hand and out of every bridge, near matches included. R16's row — a service RDMALink didn't make that it can't adopt either, a fixed IPv4 address or a service on a port still in a bridge — and a USB-only row keep none: their answer is the card a click raises. That route is the one sheet this screen lets open over it, and the Port menu offers it — for the dimmed row last clicked — and nothing else of the kind (§2.6, §2.7). Footer: `Cancel` (Escape; the picker is a run's first step, so its way out leaves the assistant, and `Back` would promise a step that isn't there — with a card up, Escape first puts the card away and leaves the selection as it was, and only the next Escape leaves), `Continue` as the default (disabled until a selectable port is chosen), and **Two ports selected** in `.caption` secondary on the leading side when more than one is chosen, the count spelled out (**Three ports selected**).

**When this screen appears.** The run's shape is fixed when it starts, and so is its step count (§2.3 band 1). The footer's `Set Up Port…` and the Port menu's ⌘N name no port, so they always open the run here, as step 1 of 3. When there is an obvious port it is already chosen: the port selected on the hub, when set-up can take it — the same test a row's `Set Up…` uses — with no line, because the user chose it; otherwise **pre-selection**: exactly one port set-up can take has a Mac linked, so RDMALink picks it and states the reason on this screen in words rather than assuming it. `Continue` is then live at once. A control that names its port — a row's `Set Up…` on a port that has never been set up, `Set Up Again…` on a drifted or returned one, the drift situation row, the change log's and R30's `Set Up Again…`, a double-clicked receptacle — never opens this screen: its run opens on S5 with that port, as step 1 of 2, and has no picker in it, so its first screen's leading button is `Cancel`. A port that set-up can't take is never offered a set-up control; if one reaches S5 anyway, S5 says why.

**After this screen the choice is frozen.** On S5, S6 and S7 no row and no receptacle is a selection target: clicking one does nothing, the chosen port alone carries the accent ring and its badge, and the others are dimmed — the list and the model are status there, not a picker.

**Copy.**
- Headline: **Which port should carry RDMA?**
- Body (desktop): **Click a port on the model, or pick one from the list. If it's on the other side, RDMALink will turn the Mac around.**
- Body (notebook): **Click a port on the model, or pick one from the list. Use the selector below the model to see the other side.**
- Pre-selection line (shown on this screen while RDMALink's pick is still the selection; it goes the moment the user chooses): **RDMALink has picked Back, middle left for you, because that's the port with another Mac on the end of it. Choose a different one if you'd rather.**
- Pre-selection line (two candidates, shown while nothing is chosen): **Two ports have a Mac on the end. RDMALink hasn't picked for you — choose the one with the cable you mean.**
- Selectable subtitles: **Linked to another Mac · In the Thunderbolt Bridge** · **Nothing plugged in · In the Thunderbolt Bridge** · **Another Mac is here. The link is still coming up.** · **A device is connected — not a Mac · Not in any bridge**
- Dimmed subtitles: **USB only — this one isn't Thunderbolt** · **Already ready for RDMA** · **Set up outside RDMALink** (a port that needs putting back by hand, one whose own service was edited since, and R16's keep the hub's subtitle, which already says why)
- Inline message, USB receptacle clicked: **That's a USB port. The front ports on this Mac carry USB, not Thunderbolt — move the cable to one of the four on the back and RDMALink will follow along.** *[Show Thunderbolt Ports]*
- Informational line, dock or display attached: **There's a dock or a display in this port. It'll keep working exactly as it does now — RDMA will use the port once a Mac is on the other end.** With more than one port chosen each line names its port: **There's a dock or a display in Back, far left. It'll keep working exactly as it does now — RDMA will use the port once a Mac is on the other end.**
- Informational line, nothing attached: **Nothing is plugged into this port yet. That's fine — the address appears when a Mac arrives.** With more than one port chosen: **Nothing is plugged into Back, far left yet. That's fine — the address appears when a Mac arrives.**
- The informational lines are `.callout` secondary with no symbol — they only inform, and orange means the user needs to act (§3.1) — and each fact has one sentence, the same one here and on S5.
- Multi-select note: **RDMALink will prepare both, one after the other, from the same password.** · three or more: **RDMALink will prepare all three, one after the other, from the same password.**
- Live-change line while selected: **Something changed on Back, middle left while you were choosing. It's still selected — have a look before you continue.**
- Buttons: **Identify Port…** · **Continue** · **Cancel** · **Show Thunderbolt Ports**
- Selection counter: **Two ports selected** · **Three ports selected**

**States.** Nothing selected · Pre-selected from the hub (no line) · Pre-selected with reason · One selected · Several selected (⌘-click / ⇧-click) · USB receptacle clicked (R3) · Already-ready port clicked (row reads **Already ready for RDMA** and offers `Restore…`, or `Return to Bridge…` when RDMALink adopted it) · Needs-a-hand port (dimmed, reads **Needs putting back by hand** and offers `Restore…`; never selectable, never pre-selected) · Hand-configured port out of every bridge clicked, a near match included (routes to Adopt, S9 — **never to set-up**) · RDMALink's own service edited since (dimmed, offers `Restore…`, which raises R28) · Port with a foreign static-IPv4 service, or with a service of its own while it is still in a bridge (R16) · Port in an unreadable bridge (R15) · Dock or display attached (allowed, informational) · Identify active (S4b) · Live event mid-selection. (An unrecognized Mac never reaches this screen: R31 offers no set-up.)

**3D behavior.** Hovering a Thunderbolt receptacle fades in a 1.5 pt accent ring at 45 % over 150 ms and highlights the row; the bridge ribbon appears for its bridge. Hovering a **USB-only** receptacle produces no ring ever; instead the receptacle dims 15 % and the cursor takes `.operationNotAllowed`. Clicking selects: the ring goes to full accent, 2 pt, with a soft bloom, and stays. Multi-select shows several full rings.

Choosing a port on a hidden face triggers the narrated camera arc. The face selector maps to real geometry. On a machine with a linked Mac, the light thread from that receptacle stays visible throughout selection, so the user can literally follow the cable they can see behind the desk.

---

### S4b — Identify a port *(ML2)*

**Purpose.** Resolve the one thing nothing on screen can resolve — which physical socket holds the cable in your hand — by letting the hardware answer.

**Layout.** A modal *state* within S4, not a sheet. The port list dims to 30 % and becomes non-interactive; the working area swaps to the Identify copy with a live status line and a small indeterminate `ProgressView`. The stage stays fully live and becomes the whole point. Footer: `Cancel` leading (also Escape) and a contextual default button that appears only once there is an answer, with the answer's other buttons — `Identify Again…`, `Choose from List` — just before it (§2.3 band 4). The working area holds no buttons of its own.

**Detection is two-beat, and belt-and-braces.** Beat one is any receptacle transitioning away from device-present; beat two is any receptacle transitioning back. **Beat one alone is already a usable answer and is reported immediately** — a user who wanders off holding the cable still has what they came for. Because docks and displays may never emit an event, the watcher does not rely on events alone: a one-second state diff runs underneath, and the success state is identical whichever detector catches it.

**Copy.**
- Headline: **Unplug it and plug it back in**
- Body: **Take the cable out of the port you want to use, wait a moment, then put it back. RDMALink watches every port and lights up the one that moved.**
- Status, watching: **Watching all six ports…** / **Watching all four ports…** / **Watching all three ports…** — any other count spelled out the same way
- Status, unplug seen: **Got it — that's Back, far right. Plug it back in whenever you're ready.**
- Replug headline: **That's the one**
- Replug body: **Back, far right. If that's not what you expected, try again — no harm done.**
- Nudge at 30 s after an unplug: **Still waiting for it to come back. Take your time.**
- Ambiguous (two receptacles change within the same ~400 ms): **Two ports changed at the same moment** · **RDMALink would only be guessing which one you meant, and it would rather not. Try again — one cable at a time.**
- USB-only identified: **That's a USB port** · **Back, far right isn't it — that's Front, left, and the front ports on this Mac carry USB, not Thunderbolt. Try one of the ports on the back.**
- Timeout headline (60 s, nothing seen): **RDMALink didn't see anything change**
- Timeout body: **Some devices don't announce themselves, and an empty port has nothing to announce. Choose a port from the list instead — or try again with a Mac on the other end.**
- Buttons: **Use This Port** · **Identify Again…** · **Choose from List** · **Cancel** — `Identify Again…` starts the watch over, and the unplugging is still the user's to do (§1.3 rule 11)

**States.** Watching · Unplug seen · Replug seen · Unplug seen, no replug after 30 s · Nothing after 60 s · Ambiguous · USB-only identified · Caught by state diff rather than event (identical success) · Cancelled (returns to S4 with the previous selection intact).

**3D behavior.** Every eligible receptacle carries a slow, in-phase shimmer — a 1.6 s opacity breath between 8 % and 18 % on a thin ring — which reads as *listening*, not *loading*. The camera pulls back to fit the whole chassis and, on machines with ports on two faces, moves to a three-quarter pose from which both faces are partly visible, so a change anywhere will be seen.

The instant an unplug lands, **every other shimmer stops dead** and the changed receptacle takes a steady `.secondary` ring — the silence around the answer is the feedback. On replug it blooms to full accent over 250 ms with a single 8 % scale pulse **on the ring only**, the camera arcs square on, and the list row selects itself. Under Reduce Motion the shimmer is a static dim ring and the bloom is a cross-fade.

Identify is **read-only, needs no password, and is always available** — including on Thunderbolt 4 Macs. Inside the assistant it is this screen's alone: `Identify Port…` above the list and the Port menu's ⌘I both start it on the picker, and nothing starts it on Review, Setting up or Ready, where the choice is frozen. On the hub the Port menu's `Identify Port…` still turns the model to the selected port and breathes it once; running this watch there is owed (§10). It is not offered on an unrecognized Mac (R31) — its Port menu item is there and unavailable: with no model there is nothing for it to point at, and the numbered rows already say what macOS says. It also defuses the identical-Macs trap directly: it answers about **this** Mac only, using **this** Mac's hardware events, so it cannot be confused by the twin on the shelf.

---

### S5 — Here's what will change *(ML1 — review)*

**Purpose.** The promise screen. Everything the app is about to do, in plain words, with the technical truth one checkbox away, and the last chance to back out before any password is asked for.

**Layout.** Stage holds the selected receptacle(s) lit and centered, camera square on the face. Working area: headline, one body line, then the **Checked** group (S3: one collapsed disclosure line when all four are satisfied, the four rows when one is not), then **one grouped inset section per selected port**, headed by the position name. Each section has four rows; each row is a symbol, a title, a `.callout` secondary sentence, and a **before → after pair of chips**. Below the sections: a footnote, a collapsed `What RDMALink won't touch` disclosure, and a `Show technical names` checkbox bound to the same preference as Settings' switch and the View menu's item, with the technical lines beneath it while it is on. It is a toggle and not a disclosure because that is what it is: turning it on shows technical names everywhere, not only here, and a disclosure triangle only ever reveals what is under it. Port list compact, frozen (S4), with the target port(s) marked **About to change**. No pre-selection line: whatever chose the port, the choice was made before this screen (§S4). Footer: `Back` to the picker in a run that opened there, or `Cancel` in a run that opened here, which returns to where the run started (§2.3 band 4), and a default button naming exactly what it will do; pressing it asks macOS for the password straight away — there is no screen between this one and the work. While the plan is being read the headline and the body are already there — they say nothing that depends on it — with a small spinner where the Checked group and the sections will go.

**Copy.**
- Headline: **Here's what will change**
- Body: **Nothing has happened yet. When you're ready, macOS will ask for an administrator's name and password once — it doesn't have to be yours, and RDMALink never sees or stores it — and every change is made in one go.**
- Section header: **Back, far left**

| Row | Title | Body | Chips |
|---|---|---|---|
| 1 | **Save how to undo this** | **Before anything else, RDMALink writes down exactly how this port looks today. If it can't write that note, it won't change a thing.** | **Nothing saved → Saved** |
| 2 | **Leave Thunderbolt Bridge** | **This port is a member of Thunderbolt Bridge. RDMALink removes just this port. The bridge itself stays exactly as it is, with its other ports.** | **In the bridge → Standalone** |
| 3 | **Get its own network service** | **A new service called RDMA — Back, far left. Nothing else on this Mac uses it.** | **Doesn't exist → Created** |
| 4 | **Turn IPv4 off, IPv6 to link-local** | **That's all RDMA needs, and it keeps this port off your ordinary network.** | **IPv4 automatic, IPv6 automatic → IPv4 off, IPv6 link-local only** |

- Row 2 variant, two bridges: **It's also in an unused bridge, Thunderbolt Bridge 2. RDMALink removes it from that one too — a port has to be out of every bridge, even one that isn't being used.** Chips: **In two bridges → Standalone**
- Row 2 variant, not in a bridge: **This port isn't in any bridge, so there's nothing to remove.** Chips: **Standalone → Standalone**
- Footnote: **Your Wi-Fi, your Ethernet, and every other network service are untouched.**
- Disclosure label: **What RDMALink won't touch**
- Disclosure content: **Your other Thunderbolt ports. Thunderbolt Bridge itself — RDMALink never deletes or recreates a bridge, it only removes a member. Wi-Fi. Ethernet. File sharing, the firewall, and everything else on this Mac. The RDMA system setting, which is yours to switch.**
- Warning row, RDMA off, led by the orange `exclamationmark.circle` — turning it on is the user's to do (§3.1): **RDMA over Thunderbolt is still off. The port will be ready; RDMA will start using it after you turn that on and restart.**
- Informational lines, under the port's section, drawn as §S4 draws them — `.callout` secondary, no symbol — and in §S4's own sentences, one per fact: nothing attached, **Nothing is plugged into this port yet. That's fine — the address appears when a Mac arrives.** · a dock or a display, **There's a dock or a display in this port. It'll keep working exactly as it does now — RDMA will use the port once a Mac is on the other end.**
- Checkbox label: **Show technical names**
- Lines beneath it while it is on: **Interface en6 · New service RDMA — Back, far left · Removing from bridge0: members en5, en6, en7, en8 → en5, en7, en8 · Also removing from bridge1: members en6, en9 → en9 · IPv4 configuration: Off · IPv6 configuration: Link-local only · RDMALink records the service it creates by its identifier, not its name, so renaming it later doesn't confuse anything.**
- Buttons: **Set Up Port** · **Set Up Two Ports** (the count spelled out: **Set Up Three Ports**) · **Back** · **Cancel**

**Hover-to-preview.** Hovering a change row previews it on the model, silently and reversibly:
- Hovering **Save how to undo this** → a small bookmark glyph fades in at the stage's trailing edge.
- Hovering **Leave Thunderbolt Bridge** → the ribbon links from this receptacle to the other members **fade away** in front of you, and the segmented ring's gaps widen a hair.
- Hovering **Get its own network service** → a small accent node fades in beside the receptacle.
- Hovering **Turn IPv4 off…** → the node gains a single hairline ring.

You can watch each sentence mean something before you agree to it.

**States.** Reading the plan (headline and body, and a spinner below them) · Single port, one bridge · Single port, an active and an inactive bridge · Single port, no bridge · Several ports · Technical names shown · A warning or an informational line present (never blocking) · A check unsatisfied (R1, R2, R4 — the Checked group expands, the default button is **disabled** with the reason above the separator, and it clears live) · A refusal present (R5, R13, R14, R15, R16 — the section is **replaced** by the refusal and **the default button is removed entirely**, not disabled) · A port that routes to Adopt (R27: a service of its own, which set-up never plans) — its section is replaced by a card over R27's line for that port, with no button of its own, and a headline that follows the route: S9's **This port is already set up** for a port that is set up properly, S9's **Nearly a match** for a near match, and R28's **This port's service isn't the one RDMALink made any more** for RDMALink's own service edited since — given a fixed IPv4 address included, which Core, seeing the address and not whose service it is, answers with R16; a service of its own on a port still in a bridge, or a fixed IPv4 address on a service RDMALink didn't make, is R16's card instead. The footer's leading button is the way out, and the review is never an empty one with nothing to press · A port that needs putting back by hand (R20, which set-up raises after the password and before anything is written) — R20's headline and body with the orange symbol and no Steps paragraph, its row `Open Network Settings` (default) · `Copy Details`; the footer's leading button is the way out · Topology changed since S4 → R17 · OS password dialog up (the working area dims 20 % and says nothing over it) · Permission refused or cancelled → R6 / R7, back here with the selection intact.

**3D behavior.** The camera moves square on to the face carrying the selection and frames it; unselected receptacles fade to 25 %, so the scene shows the subject and its context and nothing else. The selected port's outer ring is drawn as the **open segmented ring** — four arcs with four gaps — because the port is still a bridge member, and the gaps are exactly what will close during apply. This is the one piece of visual foreshadowing in the app, and it costs nothing to read.

---

### S6 — Setting up *(ML1 — apply)*

**Purpose.** Perform every write in a single burst inside the 30-second credential window, showing real progress and never offering a cancel the app cannot honor. The password was asked for by S5's default button; this screen begins the moment macOS hands back the permission.

**Layout.** The step label stays S5's. The footer's buttons **disappear entirely** — there is no control the app cannot honor — and they stay gone if the run is refused: a refused S6's card holds every way out, so the footer never offers a second one that re-plans over what the card says (R8, R10, R11). Any other refusal that lands here (R9, R12, R14) keeps its own row and gains `Done` at the end of it; its `Check Again` reads this Mac again and returns to S5 the way `Try Again` does, planning only the ports that did not land — nothing was written for the port it is about. R11's `Check Again` is the one that stays: it reads this Mac again in place and never leaves S6 (§6.2 R11). `Done` on a card here closes the assistant and is Escape's. The card replaces the screen, so its headline leads it and carries the step label (§2.3 band 1). After a partial run — one port landed before another stopped — the ports that landed are listed under the card, one line each in S7's words (**Back, far left is ready**), and the card leaves off its rollback line: the run did change something, and a summary never rounds up (§S10). The working area shows a headline, a body, and a live checklist in a grouped inset list, one row per write, each `circle.dotted` while pending, a small `ProgressView` while running, `checkmark.circle.fill` when done, with a status line beneath.

**Copy.**
- Headline: **Setting up Back, far left** / **Setting up two ports** / **Setting up three ports**
- Body: **A few seconds. Your other network connections stay up the whole time.**

| Step | Pending | Running | Done |
|---|---|---|---|
| 1 | **Save how to undo this** | **Saving how to undo this…** | **Saved how to undo this** |
| 2 | **Leave Thunderbolt Bridge** | **Leaving Thunderbolt Bridge…** | **Left Thunderbolt Bridge** |
| 3 | **Get its own network service** | **Getting its own network service…** | **Got its own network service, RDMA — Back, far left** |
| 4 | **Turn IPv4 off, IPv6 to link-local** | **Turning IPv4 off, IPv6 to link-local…** | **Turned IPv4 off, IPv6 to link-local** |
| 5 | **Check it's out of every bridge** | **Checking every bridge…** | **Out of every bridge** |

Steps 1 to 4 are Review's four rows, word for word: the pending label is the row's title, and the running and done labels are its own words in the -ing and past forms, so what the user read on S5 is what they watch happen here. Step 2 comes once for each bridge the port leaves, named as System Settings names it (**Leave Thunderbolt Bridge 2**), and not at all for a port in no bridge. Step 5, the check, is a row of its own.

- Status line: **You can undo all of this afterwards, from the main window.**
- Rollback status line: **Something didn't take. Putting the port back exactly as it was…**
- Completion line, printed under the last checkmark before the screen advances: **Done. That took 1.8 seconds.**

**A write is never cut off.** From the moment macOS's password dialog is asked for until the last step lands, the window's close button and File › Close ⌘W are unavailable: the burst starts writing the instant the password is accepted, before anything on screen could turn them off, and a dialog left behind a closed window would still write. The way out of the dialog is the dialog's own Cancel. Once writing has started, quitting waits until the last step lands and then quits: the checklist already on screen is the feedback, and the burst is bounded by the credential's thirty seconds. While only the dialog is up nothing has been written, so quitting then ends the app and the request with it.

**The undo note is step 1, not step 5.** If it cannot be written, nothing is changed at all (R14). The gate that protects every other promise goes first, and the screen says so.

**States.** Running · Second port of two · A step failed → automatic rollback, checklist reverses with a returning symbol → R10 · Credential expired mid-burst → rollback → R8 · Rollback succeeded → R10's screen · Rollback failed → R11, which never returns to S5 · `Try Again` after a run where some ports landed → S5 plans only the ports that did not · Another app holds the network lock → R12 · All steps done → advances to S7 about 400 ms after the last checkmark settles.

**3D behavior.** The selected receptacle's segmented ring **closes its gaps one by one** as each real step completes, ending as a solid accent ring; in the same beat as the first gap closes, the bridge ribbon detaches from this receptacle and retracts into the remaining members. Nothing else in the scene moves; the camera is locked for the duration so the eye has one place to be. If rollback runs, **the ring re-opens its gaps in reverse at the same pace and the ribbon springs back** — an honest and oddly calming thing to watch. Under Reduce Motion the ring steps between five static states.

---

### S7 — Ready *(ML1 — the payoff)*

**Purpose.** Deliver the `fe80::` address, plus an honest picture of what is and isn't finished, and point at the other Mac.

**Layout.** Stage: the camera eases back a step; the configured receptacle holds a solid accent ring with a soft bloom. Working area: headline, body, then a prominent **value block** — a rounded rect of `.controlBackground` containing a `.caption` secondary label, the address in `.body.monospaced()` and selectable, and a borderless `Copy Address` button on the trailing edge — then a small grouped list of status rows, then the footnote. Port list compact, with this port now reading **Ready**. Footer: `What to Do on the Other Mac` as a plain button, which opens §S8 about the port this run set up, and `Done` as the default.

**Copy.**
- Headline: **Back, far left is ready**
- Body: **The port has left Thunderbolt Bridge and has its own link-local address. It'll carry RDMA as soon as the other Mac is set up the same way.**
- Value label: **Address for this link**
- Value: **fe80::a2d1:73b4:9e0c:5f16%en6**
- Footnote: **The part after the % is this port's system name. The tools that take an address need the whole thing, so copy it as it is.**
- Status rows: **RDMA over Thunderbolt — On** · **RDMA over Thunderbolt — Off. Turn it on and restart to finish.** *[Turn It On…]* · **RDMA device — Ready** · **RDMA device — Not here yet. It usually appears after a restart.** · **The other Mac — Not set up yet**
- Nothing-attached headline: **Back, far left is ready and waiting**
- Nothing-attached body: **There's no address yet — one appears the moment another Mac is connected to this port. Leave this window open and you'll see it arrive.**
- Link-coming-up body: **Another Mac is here and the link is still coming up. The address usually takes a few seconds.**
- Buttons: **Copy Address** → **Copied** (for two seconds, then quietly back) · **What to Do on the Other Mac** · **Done**

**States.** Linked, address present · Nothing attached (the screen stays live and waits) · Link coming up · RDMA off · RDMA on but no device for this interface · Several ports configured (one value block per port, stacked) · Address arrives while the user is looking · Copied.

**3D behavior.** The camera eases back and up by a few degrees to a calm resting pose and stops. The configured receptacle's ring is solid accent with a gentle bloom; if a Mac is linked, the light thread leaves the receptacle and fades at the frame edge, so the finished state in the app matches the cable the user can see. When an address arrives later on an empty port, the ring brightens one step and the thread appears in the same 250 ms as the address fades in — **one event, two places**.

---

### S8 — Now the other Mac *(ML3)*

**Purpose.** Close the loop the app cannot cross. Reached from S7 or from the Help menu, whose item is unavailable while the set-up assistant is up (§2.7). **This is a screen, not a sheet**, because the stage does the talking.

**Layout.** Working area: headline, body, a numbered four-step list, a quiet note and a quiet honesty line, which the live line joins when the far end answers. Band 4 is this screen's own footer — `Copy These Steps`, then `Done` as the default, trailing — and the hub's footer and its link row step aside until `Done` (§2.3 band 4, §S1). The stage performs the handoff, and carries the one control that changes it: a pop-up button in its top-trailing corner that says which Mac the other one is, for the stage's picture of it — or, while the stage is §8.5's strip, that pop-up stands in the working area, between the note and the honesty line (**The other Mac's picture**).

**Whose link.** The screen is about one port, *this link*, and step 4, the live line and the stage all mean that port and no other. Reached from S7's `What to Do on the Other Mac`, it is the port that run just set up — the first in physical order when the run set up several — for as long as this Mac reports that port, ready or not, whatever the other ports are doing; once this Mac no longer reports it, the Help menu's rule decides. Reached from the Help menu, it is the port selected on the stage when the screen opens, if that port is ready; otherwise the first ready port that has an address, or the first ready port when none has one yet. The Help menu's rule never picks a port set up outside RDMALink, which is not RDMALink's to hand out (§7.3). When no port qualifies — from the Help menu with no ready port, or from S7 once the run's port is gone and none is ready — step 4 has no address to give, and the stage draws no line.

**Copy.**
- Headline: **Now the other Mac**
- Body: **RDMALink only ever changes the Mac it's running on. There's no connection between the two — you do the same thing over there, by hand, and that's the whole trick.**
- Step 1: **Copy RDMALink across, or download it again on the other Mac.**
- Step 2: **Open it and walk the same short path.**
- Step 3: **Pick the port with the other end of this cable in it. Identify makes that painless.**
- Step 4, with this link's own address: **When both sides are done, each Mac has its own address on this link. This one is fe80::a2d1:73b4:9e0c:5f16%en6.**
- Step 4, when this link has no address yet: **When both sides are done, each Mac has its own address on this link. This one's address appears as soon as a Mac is connected.**
- Note: **Leave this one cable connected while you're over there — and keep it to one cable between the pair.**
- Pop-up label: **Other Mac:** · items: **Any Mac** (the default) · **MacBook Pro** · **Mac Studio** · **Mac mini**
- Honesty line: **RDMALink can only see this Mac. Nothing it did crossed that cable — that's deliberate.**
- Live line when a Mac answers at the far end of this link — this port's own, never another port's: **Something answered on this link. That's a good sign — the other end is awake.**
- Buttons: **Copy These Steps** → **Copied** · **Done**

**The other Mac's picture.** On the stage, in its top-trailing corner — above where the ghost settles, across from the legend — a pop-up button introduced by the label **Other Mac:**, the two in one Liquid Glass capsule like the stage's other controls, opaque under Reduce Transparency and with a hairline under Increase Contrast (§2.3, §3.6). One choice among four, so a pop-up and not a row of buttons: **Any Mac**, the default, then **MacBook Pro**, **Mac Studio** and **Mac mini**. On the stage it keeps one width, its widest item's, whichever is chosen: its trailing edge is pinned to the corner, so a pop-up that sized itself to each choice would move its label and its leading edge under the pointer every time, and only the name inside it changes. Choosing an item finishes the command, so none ends in an ellipsis (§1.3 rule 11). It changes the stage's picture of the other Mac and nothing else — not the steps, not what `Copy These Steps` copies, and nothing on this Mac — and the choice is remembered across launches. **Any Mac** draws the featureless box. Each of the others draws that family's own chassis from the same catalogue this Mac's comes from, as a current Thunderbolt 5 model of it: the Mac Studio (M5 Max), the Mac mini (M5 Pro) and the 14-inch MacBook Pro (M5 Pro or M5 Max). The items name families, never a chip, because the picture is of a shape and the app knows nothing more about the other machine. It is on the stage because the stage's picture is all it changes, and it sits above the ghost it changes. It is there only while this screen is up on a recognized Mac, and it comes and goes with the ghost: it fades in as the ghost arrives and out as the ghost leaves, over 150 ms, and under Reduce Motion it simply appears and goes. It is a standard pop-up button: VoiceOver reads its label, **Other Mac:**, and its value, and with keyboard navigation on, Tab reaches it and Space opens it. Nothing else on the stage covers it: the legend stays out of its corner, the narration capsule sets itself below it rather than meet it, and the callout drops below its receptacle's row rather than reach it (§2.3, §4.8). Below 900 pt the stage is §8.5's 180 pt strip, which the pair fills from top to bottom, so there the pop-up leaves the stage for the working area — the same pop-up and the same choice, below the note and above the honesty line, so the live line, arriving under that line when the far end answers, never moves it. At the smallest windows the headline, the body and the four steps fill what band 2 is given there, so the pop-up, with the note and the honesty line, starts below band 2's fold, which fades to show there is more (§2.3 band 2): it is reached by scrolling band 2, and with Tab like any control. That is the trade the strip makes: the strip has no room for it, and band 3, which is never truncated away, has none to give. On an unrecognized Mac (R31) the stage draws no model and no ghost, so the pop-up is not there, on the stage or in the working area.

**3D behavior — the ghost second Mac.** The camera turns to the face this link's port is on, then pulls back and pans so this Mac occupies the leading third of the stage. A ghost of the other Mac at 40 % opacity — a **featureless rounded box**, or the chassis the `Other Mac:` pop-up names — slides in from the trailing side with a single thin connecting line from that port to it. **The line is that port's cable**, so exactly one link reads — this port to the other Mac: while the line is up no receptacle draws its own light thread (§4.2) — not that port beside the line, and not a linked neighbour, whose thread would read as a second cable — and every other receptacle recedes to 25 %, its rings and plug with it, as unselected receptacles do on S5. That port becomes the selection as the handoff opens, so the list and the stage agree about what the screen is about (§2.4). A receptacle the user selects while the screen is up — in the list, on the model, or through a Port menu item that turns to its port — comes forward, as a selection does; the line stays this link's, and no thread comes back. With no such port (**Whose link**) the ghost still arrives, with no line, nothing receding, the selection where it was and every thread where it was. The near port carries its solid accent ring; the far port is hollow and unlit. On the box it sits low on the edge nearest this Mac; on a chosen model it is that model's Thunderbolt port nearest this Mac on the face a cable usually goes into — the back of a Mac Studio or a Mac mini, the left side of a MacBook Pro. Hollow and unlit is all it says: it claims no knowledge of which port the user will use. **The ghost stays featureless unless the user says which Mac it is**, and even then it carries no port states — no ring but the far port's, no plug, no thread, no lit status light — and nothing is written on it or on this Mac. A chosen model is its shell and the holes in it — a MacBook Pro's base and open lid, with no screen or keyboard laid on them — ghosted exactly as the box is, at the same 40 % and with no shadow: drawn from the user's word and the catalogue, never from anything the app observes, it is still explicitly *a Mac the app can't see*. The legend names it instead: while the handoff is up it gains one line, a small faint box and **The other Mac**, which goes when the ghost does (§4.8). Changing the pop-up while the screen is up redraws the ghost in place with a short cross-fade — under Reduce Motion it simply changes — and the camera frames the new pair as the handoff first did. A ghost that fits where the box stood is given the box's room, so this Mac keeps its place and its size beside a Mac mini's small box as beside a Mac Studio; the camera pulls back further only for a ghost that needs it, so a MacBook Pro's open lid stays in frame. The line moves to the new far port with it. When the far end answers on the link, a returning pulse travels back along the line and blooms at the near receptacle, once. That is the only animation in the app that means *the other Mac exists*, and it lands without a word of copy.

---

### S9 — Adopt a port *(ML2)*

**Purpose.** Recognize a port someone already configured by hand and take responsibility for it **without touching it**, so the app can keep an honest record.

**Layout.** Sheet, 500 pt wide, raised from the port's row in the hub or from S4. Headline, body, a grouped inset list of four findings rows (symbol, label, value), a note, then buttons.

**Copy — full match.**
- Headline: **This port is already set up**
- Body: **Back, far right isn't in any bridge and already has its own service with IPv4 off and IPv6 link-local only. That's exactly what RDMALink would have made. Adopt it and RDMALink will keep an eye on it — without changing a thing.**
- Findings: **Service — Thunderbolt Bridge Free** · **IPv4 — Off** · **IPv6 — Link-local only** · **Bridge membership — None**
- Note: **Adopting changes nothing and needs no password. RDMALink is only writing itself a note.**
- Honesty note: **One thing to be straight about: RDMALink never saw this port before, so it doesn't know which bridge it came from. There's no exact "put it back" for an adopted port — Return to Bridge does the ordinary thing instead, and Stop Managing leaves the port exactly as it is.** That is why the picker names `Return to Bridge…`, not `Restore…`, for an adopted port that is already ready (§S4, R27).
- Honesty note, on a port RDMALink set up before (§S1's drifted port: the service RDMALink made is gone, and the one there now, exactly what RDMALink would have made, was made by hand): **One thing to be straight about: RDMALink set this port up before, but the service it made is gone and this one was made by hand. Adopting looks after this one and replaces RDMALink's old note for the port. There's no exact "put it back" for an adopted port — Return to Bridge does the ordinary thing instead, and Stop Managing leaves the port exactly as it is.** When that old note records the bridges the port came from, its second sentence reads **Adopting looks after this one and replaces RDMALink's old note for the port, so RDMALink won't know which bridge the port came from any more.** — adopting then forgets the only way back, as the stop-managing form does for the same note (§S10), so the form has **no default**: its row is `Adopt` · `Cancel`, `Cancel` trailing, and Return presses nothing (§2.6).
- Honesty note, on a port RDMALink returned to the bridge (§7.5) that has left the bridge since and been given this service by hand: **One thing to be straight about: RDMALink returned this port to the bridge before, but the port has left the bridge since and this service was made by hand. Adopting looks after this one and replaces RDMALink's note of that return. There's no exact "put it back" for an adopted port — Return to Bridge does the ordinary thing instead, and Stop Managing leaves the port exactly as it is.** `Adopt` stays the default: a return record describes nothing current once its port has moved on (§7.5 step 5), and it records no bridges the port came from, so adopting forgets no way back (§2.6).
- Buttons: **Adopt** · **Cancel** (no default over an old note that records the bridges the port came from, above)
- Confirmation: **Adopted. Back, far right is in RDMALink's care now.**

**Copy — near match. The app does not adjust a service it did not create.**
- Headline: **Nearly a match**
- Body: **Back, far right is out of every bridge and has its own service, but IPv6 is set to Automatic rather than Link-local only. RDMALink didn't make this service, so it won't rewrite it — but here's exactly what to change, and RDMALink adopts the port the moment it matches.**
- Steps: **In System Settings, open Network, choose Thunderbolt Bridge Free, then Details, then TCP/IP. Set Configure IPv6 to Link-local only. Set Configure IPv4 to Off.**
- Buttons: **Open Network Settings** · **Copy These Steps** · **Cancel**
- After an adopt that is refused or fails: **Copy Details** · **Cancel**, with no default (§2.6)
- Watcher line: **RDMALink keeps looking, and offers to adopt the port the moment it matches.**

**States.** Full match · Full match on a port RDMALink set up before (its own honesty note; no default when the old note records bridges) · Full match on a port RDMALink returned to the bridge before (its own honesty note) · Near match · Not a match at all (no `Adopt…` button is ever offered; the hub subtitle simply describes what it found) — a service of its own on a port that is still in a bridge is not a match at all either, because Adopt is only for a port out of every bridge (§7.3), so R16 answers for it; nor is the service RDMALink made, edited by hand since, which is RDMALink's own and which `Restore…` answers for (§S1, R28) · Adopted (the sheet closes and the hub row changes in place) · Already adopted (the row's trailing button reads `Stop Managing…`).

**The sheet follows the port.** While it is up and nothing is running, a change to the port that makes it the other form changes the sheet: a near match put right in System Settings with the sheet still open becomes the full match, `Adopt` and all, which is the watcher line's promise kept where the user is looking. A port that stops being either form keeps the one on screen: a near match keeps its steps, which still apply, and a full match keeps `Adopt`, because pressing it reads the port again and adopts only what that reading finds — a port that no longer matches is refused with **Nothing has been changed.**, and no note is written. A reading that fails for a moment is no change to the port, and moves nothing. Once `Adopt` is pressed the sheet shows its answer and nothing else.

**3D behavior.** Before the sheet appears, the camera turns to the port in question and rings it with the **double-hairline `.secondary`** ring — adopting something you cannot see is how mistakes happen. On Adopt, the double hairline resolves into a single solid accent ring over 250 ms, which is the entire ceremony.

---

### S10 — Restore a port *(ML1)*

**Purpose.** Put a port back exactly as it was found, verify it landed, and only then forget the baseline.

**Layout.** Sheet, 500 pt wide, from a row's `Restore…` button, the hub footer, the change log, or the Port menu — or, over the picker, a dimmed row's `Restore…` or `Return to Bridge…`, the one route that screen names for it (§2.6, §S4). A headline that asks about **this port** without naming it — the camera has already turned to the port and ringed it, and a position name at the head of a question reads as part of the verb ("Put Back, far left…", "Return Back, far right…") — then a body that names the port and the moment the baseline was taken, a grouped list of exactly what will happen, then buttons. While the sheet reads this Mac, its headline is already there, over a small spinner. After `Restore`, the headline says what is happening instead of asking (**Putting this port back**), and the sheet's content is replaced by the same live checklist pattern as S6, including the password step, with one status line beneath it: **Every other setting stays as it is.**

**A write is never cut off** (§S6). From macOS's password dialog until the last step lands — Restore, Return to Bridge and Restore All alike — the window's close button and File › Close ⌘W are unavailable, and once writing has started quitting waits until the last step lands. While only the dialog is up nothing has been written, so quitting then ends the app and the request with it; the dialog's own Cancel is the way back.

**Copy.**
- Headline: **Put this port back the way it was?** · while it runs: **Putting this port back**
- Body: **RDMALink will delete the service it made and return Back, far left to Thunderbolt Bridge — exactly as it was on 3 September at 14:21.**
- Rows: **Delete the service RDMA — Back, far left** · **Add the port back to Thunderbolt Bridge** · **Check that it really is back, then forget the whole thing** · **Leave every other setting alone**
- Note: **RDMALink matches the service by its identifier, not its name, so it only ever deletes the one it made — even if it's been renamed since.**
- Note: **Your RDMA system setting isn't RDMALink's to touch, so it stays exactly as it is.**
- Note (two bridges): **The port goes back into both bridges it belonged to, including the unused one.**
- Buttons: **Restore** · **Cancel**
- Steps: **Deleting the service…** · **Returning the port to Thunderbolt Bridge…** · **Checking that it's back…**
- Status line under the checklist while it runs: **Every other setting stays as it is.**
- Success headline: **Everything is back**
- Success body: **Back, far left is a member of Thunderbolt Bridge again, and RDMALink has forgotten it. Nothing else on this Mac was touched.**
- Service-already-gone line: **The service RDMALink made isn't there any more — someone removed it already. It'll just get the bridge membership back.**
- Half-done headline: **Not quite back yet** (see R20)
- Foreign-port headline (a port RDMALink did not set up, adopted or not): **Return this port to Thunderbolt Bridge?** · while it runs: **Returning this port to Thunderbolt Bridge**
- Foreign-port body: **RDMALink didn't set up Back, far right, so it can't put things back exactly as they were — but it can do the ordinary thing: add the port to Thunderbolt Bridge and remove the standalone service it has now. It writes down what it found first, so you can set the port up again afterwards.**
- Foreign-port rows: **Add the port to Thunderbolt Bridge** · **Delete the service Thunderbolt 6 — RDMALink didn't make this one, and a bridge member can't keep its own service** · **Check that it really is in the bridge** · **Leave every other setting alone**
- Foreign-port button: **Return to Bridge**
- Foreign-port success: **Back, far right is in Thunderbolt Bridge** · **The port is a member of Thunderbolt Bridge again and its standalone service is gone. Set Up Again is one click away if you change your mind.**
- Foreign port with **no** standalone service (a port taken out of the bridge by hand and left bare): body **RDMALink didn't set up Back, far right, so it can't put things back exactly as they were — but it can do the ordinary thing: add the port to Thunderbolt Bridge. It writes down what it found first, so you can set the port up again afterwards.** · rows **Add the port to Thunderbolt Bridge** · **Check that it really is in the bridge** · **Leave every other setting alone** (no delete row, no delete step) · success **Back, far right is in Thunderbolt Bridge** · **The port is a member of Thunderbolt Bridge again. Set Up Again is one click away if you change your mind.**
- No bridge exists: headline **There's no Thunderbolt Bridge to return it to** · body **This Mac has no Thunderbolt Bridge at the moment. RDMALink never creates one — recreate it in System Settings, under Network › Manage Virtual Interfaces, and RDMALink will offer the return the moment it exists.** · buttons **Open Network Settings** · **Cancel**
- Stop-managing headline (an adopted port, a return record or a drifted port: the port keeps what it has, only the note goes): **Stop managing this port?** · while it runs: **Forgetting this port's note**
- Stop-managing body: **Stopping just means RDMALink forgets its note for Back, far right. The port and its settings stay exactly as they are.**
- Stop-managing body, for a note that records the bridges the port came from — a drifted port's: **Stopping just means RDMALink forgets its note for Back, far right. The port and its settings stay exactly as they are. RDMALink won't be able to put it back afterwards.** The form then has **no default**: its row is `Stop Managing` · `Cancel`, `Cancel` trailing, and Return presses nothing (§2.6).
- Stop-managing button: **Stop Managing**
- Stop-managing confirmation: **Done. Back, far right is exactly as it was a moment ago — RDMALink is simply no longer keeping an eye on it.**
- Restore All headline: **Put every port back?** · while it runs: **Putting every port back**
- Restore All body: **Two ports will return to Thunderbolt Bridge and their services will be deleted. One password covers both. RDMALink does them one at a time and stops at the first thing that looks wrong.**
- Restore All partial summary: **One port is back. Back, far right didn't finish — its undo note has been kept, so you can try that one again.**

**States.** Ready to restore · Foreign port (Return to Bridge) · Adopted port (Return to Bridge, or Stop Managing) · Drifted port (Stop Managing; no default when its note records the bridges it came from) · A volume mounted over this link (R4 — `Restore` is not offered) · Restoring · Verifying bridge membership (an explicit step, never an assumption) · Verified (baseline deleted) · Service deleted but membership not restored → R20, **baseline deliberately kept** · Baseline missing or unreadable → R19 · Original bridge no longer exists → R21 · Restore All (one sheet, one password, sequential, per-port results, a partial-success summary that never rounds up).

**3D behavior.** The camera turns to the port and rings it in accent. As the restore runs, the solid ring **re-opens into the four-arc segmented ring** and the bridge ribbon springs back out and reattaches — the visual inverse of set-up, which makes *back where it was* literal. On verified success, the segmented ring settles to the ordinary bridge-member state over 400 ms and the camera eases back to the resting pose. If verification fails, **the ring stops half-open and stays that way**, matching the copy exactly.

---

### S11 — Change log *(ML3)*

**Purpose.** An always-available, timestamped, plain-English, **append-only** record of everything RDMALink has done to this Mac, each with its own way back.

**Layout.** Reached with `Change Log` on the hub, `⌘L`, or the View menu — never while the set-up assistant is up (§2.7); a run started from an entry's `Set Up Again…` returns here when it ends. The working area is replaced by the headline, a body line that says where the notes live, and a scrolling list, newest first. With no entries yet the empty sentence takes the body line's place. Each entry: date and time, the port's position name, one sentence, and a trailing action. Undone entries stay, greyed, with the action replaced by a note. The port list stays in place beside it. Band 4 is the log's own footer — `Show Notes in Finder` · `Save Diagnostics File…` · `Done`, the default trailing — and the hub's footer and its link row step aside until `Done` (§2.3 band 4, §S1).

**Copy.**
- Headline: **What RDMALink has changed on this Mac**
- Body: **RDMALink keeps one small note per port, in your Library folder. They're only notes — they don't change anything on their own.**
- Empty, in the body's place: **Nothing yet. When RDMALink changes something, it'll be listed here with a way back.**
- Entry: **3 September, 14:21 — Back, far left** · **Took it out of Thunderbolt Bridge and gave it its own service, with IPv4 off and IPv6 link-local only.** *[Restore…]*
- Entry: **3 September, 14:40 — Back, far right** · **Adopted. RDMALink noted how it was already set up and changed nothing.** *[Stop Managing…]*
- Entry (returned to the bridge, §7.5): **20 September, 11:40 — Back, far left** · **Put it back in Thunderbolt Bridge and removed its standalone service.** *[Set Up Again…]* — with no standalone service: **Put it back in Thunderbolt Bridge.** The button is the port row's own set-up action, in the row's words — `Set Up Again…`, or `Set Up…` once the port has moved on from the return — shown only while that row offers one and on the footer's terms (§S1): absent when the row offers none, absent in R23, disabled while two Macs are connected.
- Undone entry: **Already put back on 3 September at 15:10.**
- Returned entry after the port is set up again, or adopted: **Set up again on 20 September at 11:52.**
- Adopted entry after the port is returned to the bridge: **Put back in the bridge on 20 September at 11:40.**
- Stopped entry: **RDMALink stopped looking after this port on 3 September at 15:12.**
- Vanished port: **This port isn't on this Mac any more, so there's nothing left to put back. The note stays until you clear it.** *[Forget This Note]*
- Buttons: **Show Notes in Finder** · **Save Diagnostics File…** (saved as §S12 describes) · **Done**

**3D behavior.** The model rests at 70 % brightness. **Hovering a log entry lights the receptacle it refers to** at full brightness with a thin ring, so history is spatial — you can scroll the log and watch the ports light up in the order things happened. Entries for ports that no longer exist produce no highlight, and the row says so rather than leaving you hunting.

---

### S12 — Settings *(ML0 / ML3)*

**Purpose.** The one preferences surface. A single pane, so per HIG **no toolbar and no tab bar**.

**Layout.** Separate window, 480 pt wide, height to fit. One `Form` with `.formStyle(.grouped)`: a section of one toggle with `.callout` help text beneath it, and a section with buttons. There is no update check: the app never contacts anything, and a toggle that claimed to would be a promise it does not keep (§1.3 rule 10).

**Copy.**
- Toggle: **Show technical names** · Help: **Adds names like en6 and the exact service names next to each port. The link address always shows in full, because tools need every character of it. Nothing is ever written on the picture of your Mac.**
- Button: **Show Notes in Finder** · Help: **RDMALink keeps one small note per port it set up. That note is what makes putting things back possible — it's safe to back up and safe to leave alone.**
- Button: **Save Diagnostics File…** · Help: **A plain text file with what RDMALink can see on this Mac and what it has changed: the model, the chip, the macOS build, the ports, and any step that failed. No personal information, and nothing is sent anywhere — it's yours to keep or share.**

**Saving a diagnostics file** works the same from all three places that offer it — here, the change log (§S11) and the Help menu (§2.7). The save panel is a sheet on the window it was asked from, and stands on its own only when no window is open. A sheet never stacks on a sheet, and an app-wide panel over one is the same stacking by another name: the Help menu's item is unavailable while the main window has a sheet up — and while the set-up assistant is up, since nothing opens a sheet over a run but What This All Means (§2.6, §2.7) — and a panel or alert asked for on a window that already has one waits for it to close. A file that can't be written is never a silent failure: an alert on the same window — or on its own if that window has closed in the meantime — says **The diagnostics file couldn't be saved.**, with the system's own reason as its informative text and one **OK** button — the alert only informs, so `OK` is the right single answer. Nothing is printed inline, in Settings or anywhere else.

**States.** Default · Technical names on (the main window updates live, no relaunch) · No notes saved yet (`Show Notes in Finder` is disabled, and its tooltip says why: **RDMALink hasn't set up a port on this Mac yet, so there are no notes to show.**). An available button has no tooltip: its help is printed beneath it, and a tooltip would only repeat it (§8.4).

**3D behavior.** None. Settings has no 3D content, and adding any would be exactly the sort of gimmick this app avoids.

---

### S13 — What this all means *(Help)*

**Purpose.** One short explainer for the curious that never becomes required reading. Reached from the hub and from the Help menu.

**Layout.** Sheet, 560 pt wide, four short sections, one flat 2D illustration of two Macs and one cable (**not** the 3D model — the sheet is reading material, and mixing the live model in would imply the drawings are about this particular Mac). `Done`, the default; Escape closes the sheet too (§2.6).

The headline, the illustration, the sections and the closing line scroll inside a region at most 480 pt tall; `Done` sits beneath it, outside the scroll, so the sheet is never taller than a window at §2.1's 600 pt minimum allows once the toolbar is taken off (§2.6).

**The illustration.** Two plain rounded slabs — no logo, no trade dress, no product likeness — each with four small Thunderbolt receptacles along its facing edge. On each Mac the three receptacles still in the bridge are tied together by a soft translucent ribbon labelled **Thunderbolt Bridge** in `.caption` secondary; the fourth stands apart, ringed in the accent. One accent cable, a smooth curve with a gentle sag, runs between the two ringed receptacles, with **fe80::** set in `.caption` monospaced secondary above its middle. Those are the only words on it. Hairline strokes and control-background fills; the accent is used for the ring, the cable and, optionally, one small dot that travels slowly along the cable — stilled under Reduce Motion, and the picture is complete without it. It says what the four sections say, in one glance: the bridge stays, one port leaves it, one cable, one address.

**Copy.**
- Headline: **What this all means**
- **RDMA over Thunderbolt** — **RDMA lets two Macs move data between them without troubling either one's processor very much. Over a Thunderbolt 5 cable that's quick enough to feel like a local disk. Tools like exo and MLX clusters use it.**
- **Why take the port out of Thunderbolt Bridge?** — **The bridge joins your Thunderbolt ports into one ordinary network, which is lovely for file sharing and wrong for this. RDMA wants a cable that belongs to it alone, so RDMALink gives the port its own service and leaves the bridge otherwise untouched. A port has to be out of every bridge, even one that isn't switched on.**
- **Why only one cable between two Macs?** — **The bridge works like a hub: whatever arrives on one Thunderbolt port is sent out of all the others. So a second Thunderbolt connection between the same two Macs — or a ring of Macs — with those ports still in the bridge gives traffic a way to go round and round for ever, eating processor time and dragging the network down. Apple says so in its technote on RDMA over Thunderbolt. One cable, no loop.**
- Under that section, a `.caption` link: **Apple's technote on RDMA over Thunderbolt** → `https://developer.apple.com/documentation/technotes/tn3205-low-latency-communication-with-rdma-over-thunderbolt` (TN3205, which says a bridge forwards like a hub, that a loop lets frames travel indefinitely, and to keep looped ports out of the bridge). Opens in the default browser; the only link on the sheet.
- **That fe80:: address** — **It's a link-local IPv6 address. It only means anything down that one cable, which is exactly the point — the port is now its own small private network. That's also why IPv4 can be off entirely.**
- Closing line: **You don't need to know any of this to use RDMALink.**
- Button: **Done**

---

## 6. Refusals & errors

### 6.1 The shape of every refusal

Documented once so they all read the same.

1. **Inline in the working area**, never a sheet — so the port list and the model stay visible and can point at the thing in the way. (The only exception is a refusal raised inside the Restore or Adopt sheet, which stays in that sheet.)
2. A hierarchical SF Symbol in `.secondary` or `.orange`. **Never a filled red badge, never a full-bleed alarm.**
3. A headline that **names the situation**, never scolds and never says "Error". A card that replaces the screen — S5's, a refused S6's, R24's and R25's on the hub, one that takes a sheet's place — carries the screen's headline in `.title2` semibold, and in the assistant the step label rides on it (§2.3 band 1). A card nested under a screen's own headline — the picker's R3, R16 and R26, the hub's R3 tip and R22, a refusal under the Adopt sheet's headline — steps its headline down to `.headline`, so no screen has two headlines of equal weight; its symbol and its paragraph stay as they are.
4. One short paragraph of plain-language *why*, including the real-world consequence, naming the exact port or volume in the same words used everywhere else in the app.
5. **The primary action is always a real action** — open the right settings pane, turn the model to the right port, show something in Finder, or re-check. **There is never a "Continue Anyway", never an "I understand the risks", never a hidden modifier key.** Where the condition is physical, the refusal has **no button at all**: it watches itself and clears.
6. **On the review screen the primary button is removed, not disabled.**
7. Every refusal that follows a partial write **states the rollback first**, before explaining anything else: its rollback line sits under its headline, ahead of its paragraph, so the headline still leads the screen (§2.3 band 1).
8. `Copy Details` appears on every failure refusal and always includes the technical names regardless of the "Show technical names" toggle, plus the model, the chip, the macOS build, the failing step and the underlying reason — and nothing else. It is the same payload as `Save Diagnostics File…`.
9. Self-clearing refusals cross-fade to a single line — **"Sorted. Carrying on."** — and the flow continues by itself.
10. A way out always remains, so the only ways out of a refusal are backwards or fixing the cause. In the working area it is the footer's leading button — `Back`, or `Cancel` on a run's first screen (§2.3 band 4) — and a card never repeats it: no `Back`, `Cancel` or second way out in a card's own row — save one, R16's `Choose Another Port` on S5 in a run that opened on the picker, which names where it goes: it is `Back` to the picker, under the name of what the user does there (§6.2 R16). The one exception to the footer's being the way out is a refused S6, where the footer's leading button is hidden and the card holds every way out, `Done` among them (§S6). In a sheet the way out is in the card's row (§2.6).

**Shared strings:** **Nothing has been changed.** · **RDMALink is watching — once this is sorted it carries straight on.** · **Sorted. Carrying on.** · **Check Again** · **Copy Details** → **Copied**

### 6.2 The refusals

---

**R1 — Two Macs are connected (loop risk).** *Blocks preflight and any apply.* Fires when two or more receptacles with a Mac on the end are members of the same bridge, in the kernel or in the saved network settings. A port that is already standalone forwards nothing, so two cables on two standalone ports — a finished set-up — never trip it.
- Headline: **Two Macs are connected**
- Body: **Thunderbolt Bridge forwards Ethernet between Macs, and two cables between the same pair can send traffic around in a loop. Unplug one cable and RDMALink will pick this back up — the other one can go back in when you're done.**
- Detail: **Back, far left and Back, far right each have a Mac on the end.**
- Buttons: none.
- **Recovery:** both receptacles ring and show their light threads so the user can **see** the loop; the check flips to satisfied the moment one cable is pulled, with no click. No bypass exists anywhere in the interface.

---

**R2 — Both ends of one cable are in this Mac.** *Blocks preflight and any apply.*
- Headline: **Both ends of that cable are in this Mac**
- Body: **Back, far left and Back, far right are talking to each other — the cable goes out of this Mac and straight back in. It's harmless, but it isn't a link to anywhere. Unplug one end and put it in the other Mac.**
- Buttons: none; self-clearing.
- **Recovery:** both receptacles ring and a single light thread is drawn between them, arcing across the chassis — the one time a thread connects two ports of the same machine.

---

**R3 — A cable is in a USB-only port.** *A non-blocking tip on the hub; a hard refusal on click in Choose a port.*
- Headline: **That's a USB port**
- Body: **The front ports on this Mac carry USB, not Thunderbolt. Move the cable to one of the four Thunderbolt ports on the back and RDMALink will follow along.**
- Body (Mac mini): **The two ports at the front of a Mac mini carry USB, not Thunderbolt. The three on the back are the Thunderbolt ones.**
- Buttons: **Show Thunderbolt Ports** (default in Choose a port; a plain button in the hub's tip, because the hub footer's primary is already that window's one default) · **Check Again**
- **Recovery:** the camera arcs to the back face and breathes the eligible receptacles once, in sequence; when the cable reappears in a Thunderbolt port the tip dismisses itself with **"Got it — that's a Thunderbolt port. Carry on."**

---

**R4 — Something is still mounted over Thunderbolt.** *Blocks preflight and blocks Restore.*
- Headline: **Something is still using this link**
- Body: **The volume Vault is mounted over Thunderbolt. Eject it in Finder so nothing gets interrupted, then RDMALink will carry on.**
- Detail (multiple): **Vault and Scratch are mounted over Thunderbolt.**
- Buttons: **Show in Finder** (default)
- Busy line: **Finder says something still has a file open on it. Quitting whatever is using it usually does the trick.**
- **Recovery:** Finder is brought forward with the volume selected; the check clears automatically on unmount. The receptacle carrying the volume takes an attention ring so the abstract volume has a physical place.

---

**R5 — This is how you're connected right now.** *Hard refusal at preflight and at review.*
- Headline: **This is how you're connected right now**
- Body: **Right now, Thunderbolt is the only way this Mac is reachable. Removing a port from a bridge can briefly interrupt the whole bridge — not just that one port — so this would cut you off half-way through. Connect Wi-Fi or Ethernet first, then come straight back.**
- Buttons: **Open Network Settings** (default) · **Check Again**
- **Recovery:** clears itself the instant another route appears. At review the default button is **removed entirely**, so there is nothing to click. This is a refusal for **any** Thunderbolt-bridge route, not only the chosen port — the bridge may blink as a whole.

---

**R6 — This account can't change network settings.**
- Headline: **This account can't change network settings**
- Body: **macOS only lets an administrator rearrange network connections. Log in as an administrator, or ask someone who is to sit down for thirty seconds — that's genuinely all it takes. The name and password don't have to be yours.**
- Buttons: **Open Users & Groups** (default). The footer's leading button is the way back (§6.1 rule 10).

---

**R7 — No administrator permission given.**
- Headline: **No changes were made**
- Body: **Without an administrator's permission RDMALink can't touch the bridge — and it didn't. Everything is exactly as it was. Try again whenever you're ready; the name and password don't have to be yours.**
- Buttons: **Try Again** (default). The footer's leading button is the way back (§6.1 rule 10).
- **Recovery:** returns to S5 with the selection intact. `Try Again` brings back what will change; `Set Up Port` asks again.

---

**R8 — The permission expired mid-burst.**
- Headline: **That took a moment too long**
- Body: **The permission macOS gives RDMALink lasts about thirty seconds, and it ran out before every change went through — so RDMALink put the port back exactly as it was. Try again; it usually flies through.**
- Buttons: **Try Again** (default) · **Done** · **Copy Details**. The footer's leading button is hidden (§S6): the card holds every way out.
- **Recovery:** the reversed checklist stays on screen as proof of the rollback. `Try Again` returns to S5 after re-verifying the world, planning only the ports that did not land; `Done` closes the assistant — nothing is left half-changed: the port the card is about is as it was, and any port that landed before it stays set up and is listed under the card (§S6).

---

**R9 — macOS wouldn't release the port from the bridge.**
- Headline: **macOS wouldn't let go of that port**
- Body: **RDMALink couldn't remove Back, far left from Thunderbolt Bridge, so it stopped and changed nothing at all. You can take it out by hand in System Settings, under Network — open the three-dot menu, choose Manage Virtual Interfaces, open Thunderbolt Bridge and remove just this port. Come back after that and RDMALink will offer to adopt it.**
- Buttons: **Open Network Settings** (default) · **Check Again** · **Copy Details**

---

**R10 — The service couldn't be created; rolled back.**
- Headline: **Put back, safely**
- Body: **The new service wouldn't create, so RDMALink returned the port to Thunderbolt Bridge. Nothing has been left half-done, and it checked before telling you.**
- Buttons: **Try Again** (default) · **Done** · **Copy Details**. The footer's leading button is hidden (§S6): the card holds every way out.
- **Recovery:** the ring re-opens its gaps and the ribbon reattaches on the model while the checklist reverses, so the rollback is **visible rather than claimed**. `Try Again` returns to S5 after re-verifying the world, planning only the ports that did not land; `Done` closes the assistant — nothing is left half-changed: the port the card is about is as it was, and any port that landed before it stays set up and is listed under the card (§S6).

---

**R11 — Rollback itself failed.** *The most serious state in the app, and the only one that asks the user to do something by hand.*
- Headline: **One thing needs your hand**
- Body: **RDMALink took Back, far left out of Thunderbolt Bridge, then couldn't finish — and couldn't put it back either. Nothing is broken, but the port is currently in neither place. Open System Settings, under Network, choose Manage Virtual Interfaces, open Thunderbolt Bridge, and add the port back. Here is exactly how it was.**
- Findings block (always shown, technical names included): **Bridge: Thunderbolt Bridge (bridge0) · Members before: en5, en6, en7, en8 · Members now: en5, en7, en8 · The port to add back: en6 — Back, far left**
- Buttons: **Open Network Settings** (default) · **Copy Details** · **Check Again** · **Done**. The footer's leading button is hidden (§S6), and R11 never returns to S5: planning the port again would write a fresh note over the one that says how it was. So its `Check Again`, unlike the one other refusals carry on S6, reads this Mac again in place and stays on S6 — a read, never a plan and never a write — and once the port has been added back by hand, the port list and the model show it in the bridge. `Done` closes the assistant, and the hub's needs-a-hand row takes over (§S1).
- **Recovery:** the baseline is **kept**; the hub carries the persistent row **"Back, far left needs putting back by hand"** *[Show Me]*, with `Restore…` on the port's row. The row is observed, never remembered: the moment the port is seen back in a bridge it stops needing a hand, and the row says what is true then (§7.4). The change log entry stays live with its action intact.

---

**R12 — Another app is editing the network.**
- Headline: **Something else has the network open**
- Body: **System Settings, or another app, is editing the network configuration right now. RDMALink won't write over it — two things writing network settings at once is how configurations get mangled. Close that and RDMALink will try again.**
- Buttons: **Check Again** (default) · **Quit System Settings** (shown only when System Settings is the holder). The footer's leading button is the way back (§6.1 rule 10).
- **Recovery:** macOS doesn't say who holds the network or when they let go, so the card doesn't pretend to watch. `Check Again` reads this Mac again and brings back what will change — on S5 in place, and from a refused S6 by returning to S5 the way `Try Again` does (§S6) — so `Set Up Port` can ask again once the other app has closed; if something still has the network open, R12 comes back. In a sheet, `Check Again` puts back the sheet's plan the same way.

---

**R13 — This Mac's network settings are managed.** *Blocks the entire configure path.*
- Headline: **This Mac's network settings are managed for you**
- Body: **A configuration profile on this Mac owns the network setup, and it will quietly put back anything RDMALink changes. Better to say so now than have you wonder later why the link keeps vanishing. Whoever manages this Mac can make an exception for Thunderbolt.**
- Buttons: **Show Profile** (default) · **Copy Details for IT**. The footer's leading button is the way back (§6.1 rule 10).
- **Recovery:** none offered, and no override. The refusal re-checks on window focus. Identify, the model, and the port list all keep working, so the app is still a useful map.

---

**R14 — RDMALink can't save its undo note.** *Hard gate. Fires at preflight and again immediately before the first write.*
- Headline: **RDMALink can't write down how things are right now**
- Body: **RDMALink's notes live in your Library folder, and it can't save there at the moment — which means it couldn't put things back afterwards. It won't change anything it can't undo.**
- Detail: **2 KB is all it needs. There's 0 bytes free on Macintosh HD.** / **The folder isn't writable.**
- Buttons: **Check Again** (default) · **Show Notes in Finder** · **Copy Details**
- **This is the refusal that protects every other promise in the app, and it comes before the password, not after.**

---

**R15 — There's a bridge here RDMALink can't read.** *Blocks review for that port.*
- Headline: **There's a bridge here RDMALink can't make sense of**
- Body: **Back, far left belongs to a bridge whose settings RDMALink can't read properly, and a port has to be out of every bridge — even one that isn't switched on — before it can carry RDMA. RDMALink won't guess at this. Have a look in Network settings, under Manage Virtual Interfaces, and RDMALink checks again when you're back.**
- Buttons: **Open Network Settings** (default) · **Check Again** · **Copy Details**

---

**R16 — This port already has a setup RDMALink didn't make.** *Blocks selection; distinct from Adopt, and from the service RDMALink made given a fixed IPv4 address since, which is RDMALink's and routes to `Restore…` and R28 (R27).*
- Headline: **This port already has a setup RDMALink didn't make**
- Body: **There's a service on Back, far left with a fixed IPv4 address on it. It isn't RDMALink's and it isn't what a link needs, and RDMALink won't quietly rewrite something you or someone else set up on purpose. Remove it in Network settings if it's stale, or choose another port.**
- Body, a service of its own on a port still in a bridge — which neither set-up nor Adopt can take (§7.3): **There's a service of its own on Back, far left, and the port is still in a bridge. It isn't RDMALink's and it isn't what a link needs, and RDMALink won't quietly rewrite something you or someone else set up on purpose. Remove it in Network settings if it's stale, or choose another port.**
- Buttons: **Open Network Settings** (default) · **Choose Another Port** · **Copy Details** — `Choose Another Port` only in a run that has a picker in it.
- **Recovery:** on the picker, `Choose Another Port` puts the card away and leaves you on the picker, as clicking a port that works does; only `Cancel` leaves the assistant (§2.3 band 4). Raised on S5 in a run that opened on the picker, it is `Back` to the picker. Raised on S5 in a run that opened there, the card is **Open Network Settings** (default) · **Copy Details**: that run never had a picker, and the footer's `Cancel` is the way out.

---

**R17 — The arrangement changed while you were reading.**
- Headline: **Something moved**
- Body: **A cable changed while this was on screen, so what you just read isn't true any more. RDMALink stopped before doing anything rather than act on old information.**
- Buttons: **Take Another Look** (default)
- **Recovery:** `Take Another Look` reads this screen again in place, in either run shape — what the user is reading is captured afresh and the plan is read again — with the changed port breathing once. The new plan, or its card, says what is true now; the footer's leading button stays the way to choose again or to leave.

---

**R18 — RDMALink doesn't know its way around this version of macOS.** *Blocks the entire configure path.*
- Headline: **RDMALink doesn't know its way around this version of macOS**
- Body: **RDMALink knows how to take a port out of Thunderbolt Bridge on macOS 27.0 through 27.2, and this Mac is on 27.3. Rather than guess with your network settings, RDMALink stops here.**
- Body, second paragraph: **You can do it by hand in System Settings: under Network, open Manage Virtual Interfaces and remove the port from Thunderbolt Bridge, then set IPv4 to Off and IPv6 to Link-local only on the port's own service. Come back afterwards and RDMALink will recognize it and offer to look after it.**
- Buttons: **Open Network Settings** (default) · **Open Download Page** · **Copy Details**. `Open Download Page` opens RDMALink's releases page in the browser — another app, exactly what it names, so no ellipsis; RDMALink itself still contacts nothing (§S12).
- **Recovery:** manual configuration, then Adopt. Identify, the model, the port list and the change log all keep working; only the configure path is closed.

---

**R19 — The undo note is missing or unreadable.** *At Restore.*
- Headline: **RDMALink can't remember how this looked**
- Body: **The note RDMALink wrote down for Back, far left is missing, and it won't guess at your network settings. You can remove the service in System Settings, under Network, and add the port back to Thunderbolt Bridge yourself.**
- Buttons: **Open Network Settings** (default) · **Cancel** · **Copy These Steps** · **Stop Managing…**. `Cancel` closes the sheet and changes nothing (§6.1 rule 10, §2.6). `Stop Managing…` is the Port menu's, R28's and R30's command under the same name: it opens the stop-managing form. Over the picker the row has no `Stop Managing…`: a sheet there opens no second sheet (§2.6).
- **Recovery:** `Stop Managing…` clears only RDMALink's own record and touches nothing on the system, and its confirmation says exactly that.

---

**R20 — The bridge doesn't have it back yet.** *At Restore.*
- Headline: **Not quite back yet**
- Body: **The service is gone, but Thunderbolt Bridge isn't listing Back, far left yet. RDMALink has kept your undo note, so nothing is lost and it can try again whenever you like.**
- Steps: **Try Again usually does it: RDMALink waits for the port to settle and writes the membership afresh. If it still isn't back, open System Settings › Network, choose Manage Virtual Interfaces, open Thunderbolt Bridge and add Back, far left yourself.**
- Buttons: **Try Again** (default) · **Cancel** · **Open Network Settings** · **Copy These Steps**. `Cancel` closes the sheet; the undo note is kept and the hub still offers `Restore…`, so closing loses nothing (§6.1 rule 10, §2.6).
- **Recovery:** the baseline is **never** deleted until verification passes. The change log entry keeps its `Restore…` action. The ring on the model stops half-open and stays that way, matching the copy.
- **Set-up raises it too.** The state R11 and R20 leave behind — a note that records the bridges the port came from, and a port in no bridge with no service — is the hub's needs-a-hand row, which offers `Restore…` and never a set-up (§S1). Should a set-up reach such a port anyway, it refuses with R20 after the password and before anything is written, rather than write a fresh note over the only record of where the port came from. On S5 that is R20's headline and body with the orange symbol and no Steps paragraph — its `Try Again` is the Restore sheet's, which S5 doesn't have; its row is `Open Network Settings` (default) · `Copy Details`, and the footer's leading button is the way out (§6.1 rule 10).

---

**R21 — The bridge it came from doesn't exist any more.** *At Restore.*
- Headline: **The bridge it came from doesn't exist any more**
- Body: **Thunderbolt Bridge has been removed since RDMALink set this port up. It can still delete the service it made — that part is squarely its own — but it won't recreate a bridge, because that's a bigger decision than undoing its own work.**
- Buttons: **Remove Service Only** · **Cancel** (Escape), `Cancel` trailing. **No default**: the user asked for the port to be put back whole, and the one action on offer deletes the service without putting it back, so Return presses nothing (§2.6). `Remove Service Only` is a plain button, not a red one — `stop` stays unused (§3.1).
- Confirmation: **The service is gone and the port is standalone. RDMALink has kept your note, in case you rebuild that bridge and want the rest put back.**

---

**R22 — RDMA is on, but no RDMA devices appeared.** *Not a block.*
- Headline: **RDMA is on, but no RDMA devices appeared**
- Body: **That usually means this Mac, or this version of macOS, doesn't actually offer RDMA over Thunderbolt. Setting up a port is still harmless and still undoable — it just won't have anything to carry yet.**
- Buttons, on S2: **Continue** (default) · **Check Again** · **Copy Details**. On the hub, behind the This Mac row's `Tell Me More`: **Check Again** · **Copy Details** — the footer's `Set Up Port…` is the way on, and the window keeps its one default.
- **Recovery:** proceeds, and the hub keeps an honest status row rather than pretending.

---

**R23 — This Mac's Thunderbolt is version 4.** *Read-only mode, not an error.*
- Headline: **Nothing to configure here**
- Body: **This Mac has Thunderbolt 4 ports. RDMA over Thunderbolt needs Thunderbolt 5, so there's nothing for RDMALink to set up. You're welcome to look around — everything you see is real.**
- Buttons: **Quit** only. The set-up buttons — the footer's **Set Up Port…** and every row's **Set Up…** and **Set Up Again…** — are **absent**, not disabled.
- **Recovery:** the model, the port list, Identify and the change log all still work, so the app remains useful as a map.

---

**R24 — RDMALink can't see the Thunderbolt hardware.**
- Headline: **RDMALink can't see this Mac's Thunderbolt hardware**
- Body: **macOS isn't reporting any Thunderbolt controllers, which RDMALink needs before it will touch anything. A restart often sorts this out.**
- Buttons: **Check Again** (default) · **Copy Details** · **Quit**
- After three failures, the body gains: **Three tries, same result. Restarting usually clears this up.**
- **Recovery:** no partial mode. Without hardware truth the app does nothing at all.

---

**R25 — RDMALink needs a newer macOS.**
- Headline: **RDMALink needs macOS 27**
- Body: **RDMA over Thunderbolt arrived in macOS 27, and the way RDMALink edits the network is only safe there. On this version it won't make changes.**
- Buttons: **Quit** (default)
- **Recovery:** none offered, and no read-only mode either, because the detection itself isn't trustworthy on older systems.

---

**R26 — Every Thunderbolt port is occupied.** *A dead end handled kindly at Choose a port, not a refusal.*
- Headline: **Every Thunderbolt port has something in it**
- Body: **There's a display in Back, far left and docks in the other three. You can still prepare any of them — or free up the one you want for the link.**
- Buttons: none; the card watches and clears itself.

---

**R27 — Routing, not refusing.** A click on a dimmed row in Choose a port that has a route of its own never produces a refusal. It prints one line that states a fact and names the row's own button — the route the picker names (§S4) — and nothing opens until that button is pressed:
- A port RDMALink set up that is **already ready**: the row reads **Already ready for RDMA** and offers `Restore…`. Line: **This one's already a link. Restore… puts it back.**
- An **adopted** port that is already ready: the row reads **Already ready for RDMA** and offers `Return to Bridge…`, because an adopted port has no exact Restore (§7.3). Line: **This one's already a link, looked after by RDMALink. Return to Bridge… puts it in Thunderbolt Bridge.**
- A port **set up by hand**, exactly as RDMALink would have made it — a port RDMALink set up before included, once the service it made is gone and this one stands in its place (§S1): the row reads **Set up outside RDMALink** and offers `Adopt…`. Line: **This one was set up by hand, and properly. Adopt… looks after it without changing it.**
- A **near match** set up by hand, out of every bridge (§S9): the row reads **Set up outside RDMALink** and offers `Adopt…`. Line: **This one was set up by hand, but not quite the way a link needs. Adopt… shows what to change.**
- A port that **needs putting back by hand** (§S1): the row keeps **Needs putting back by hand** and offers `Restore…`. Line: **This one needs putting back by hand. Restore… puts it back.**
- A port whose **own service, the one RDMALink made, was edited by hand since** — nearly a match now, or given a fixed IPv4 address: the row keeps **Not set up any more** and offers `Restore…`, which raises R28. Line: **RDMALink set this one up, and it's been changed since. Restore… shows what changed.**

A service of its own on a port **still in a bridge** is not routed: Adopt can't take it (§7.3), so a click raises R16's card, as a fixed IPv4 address on a service RDMALink didn't make does.

The same answer reaches Review only if something slipped past these rows, and there it is a card (§S5) over the port's line, with no button of its own, headed as the route is: S9's **This port is already set up** for a port that is set up properly, S9's **Nearly a match** for a near match, and R28's **This port's service isn't the one RDMALink made any more** for RDMALink's own service edited since, a fixed IPv4 address on it included. **There is no path anywhere in the app that rewrites a service the app did not create.**

---

**R28 — The service RDMALink made isn't the one it made any more.** *At Restore, before anything is deleted.*
- Headline: **This port's service isn't the one RDMALink made any more**
- Body: **The service RDMALink created on Back, far left has been changed since — it's carrying settings RDMALink didn't put there, and it won't quietly delete something you've made your own. Remove it yourself in Network settings if you're done with it, or Stop Managing leaves everything exactly where it is.**
- Body over the picker, where the row has no `Stop Managing…`: the same, ending **…Remove it yourself in Network settings if you're done with it.**
- Detail: the differences, as a list: **IPv4 is Manual, IPv6 is Automatic.**
- Body when the service RDMALink made has gone from the port and one set up by hand stands there instead — the drifted port §S1 offers `Adopt…` or nothing for, which only the footer's `Restore…`, the Port menu's or Restore All Ports reaches: **The service RDMALink created on Back, far left isn't there any more, and the one on the port now was set up by hand. RDMALink won't delete a service it didn't make, so it can't put the port back the way it was while that one is there. Remove it yourself in Network settings if you're done with it, or Stop Managing leaves everything exactly where it is.** Over the picker it ends at the advice, as above. No detail line: nothing RDMALink made has changed. Once that service is gone, `Restore…` puts the port back.
- Buttons: **Stop Managing…** · **Open Network Settings** · **Cancel** (Escape), `Cancel` trailing. **No default**: the user asked for the port to be put back, and `Stop Managing…` forgets the note that makes that possible, so Return presses nothing (§2.6). Over the picker the row has no `Stop Managing…` — a sheet there opens no second sheet (§2.6) — and `Open Network Settings`, which removes nothing, is its default, with `Cancel` before it.
- **Recovery:** RDMALink matches its service by identifier, never by name, so a renamed service is still its own; only a changed configuration is refused, or a service RDMALink didn't make standing in its place. The note is kept.

---

**R29 — There's no Thunderbolt Bridge to return it to.** *At Return to Bridge.* The copy is S10's no-bridge form (headline, body and buttons there). RDMALink never creates a bridge.

---

**R30 — That note only records a return.** *At Restore, reached only from the command line or a stale sheet: the hub never offers Restore for a return record (§7.5).*
- Headline: **Nothing to put back**
- Body: **RDMALink's note for Back, far left only records that it put the port back in Thunderbolt Bridge. There's nothing to undo — Set Up Again takes the port out of the bridge, and Stop Managing forgets the note.**
- Buttons: **Set Up Again…** (default) · **Stop Managing…** · **Cancel**, drawn `Stop Managing…` · `Cancel` · `Set Up Again…` (§2.6). `Set Up Again…` is the port row's own set-up action, offered only while that row offers one and on the footer's terms (§S1): absent when the row offers none or in R23 — the row is then `Stop Managing…` · `Cancel` with no default and `Cancel` trailing, as in the adopted form below — and disabled while two Macs are connected. Over the picker neither it nor `Stop Managing…` is offered (§2.6).
- Adopted note (§7.3: an adopted port has no bridge history and nothing to put back): body **RDMALink's note for Back, far left only records that it adopted the port as it found it. There's nothing to undo — Stop Managing forgets the note, and the port keeps its setup.** · buttons **Stop Managing…** · **Cancel** (Escape). **No default**: the user asked for a Restore, not for the note to go, and `Stop Managing…` forgets it, so Return presses nothing (§2.6).
- **Recovery:** the note is kept; nothing is written.

---

**R31 — RDMALink doesn't recognize this Mac.** *Read-only mode, not an error. Fires when neither rule in §4.7 recognizes the Mac; never on a Mac the identifier catalogue lists.*
- Headline: **RDMALink doesn't recognize this Mac**
- Body: **RDMALink only draws, and only changes, Macs it knows — and this isn't one of them. So there's no picture, and nothing here will be changed. The ports below are listed the way macOS reports them, and everything you see is real.**
- Stage: no model. In its place, centred, an unavailable-content block in the system's own style: symbol `desktopcomputer.trianglebadge.exclamationmark`, title **No picture for this Mac**, description **RDMALink doesn't recognize it, so it won't draw one.** No selector, legend, callout or view buttons.
- Buttons: **Quit** only. In the window, set-up, Restore, Adopt, Return to Bridge and Stop Managing are all **absent**, not disabled — RDMALink writes nothing on a Mac it does not recognize, notes included (§1.3 rule 5). Identify is not offered. The Port menu is the exception to *absent*, because a menu that empties itself is a thing to hunt for: every item stays and every one is unavailable, `Identify Port…` included (§2.7). R31 never reaches the assistant — an unrecognized Mac offers no set-up — and if it did, its card would carry no button and no watching line, because it never clears; the footer's `Cancel` is the way out.
- Every operation refuses with this code as well, so the command-line tool's previews and `refusals` say the same thing; the app hiding the buttons is not the only guard.
- **Recovery:** the port list (numbered, §4.7) and the change log still work. A newer RDMALink may know this Mac.

---

## 7. Adopt, Undo, steady-state status

### 7.1 The baseline (undo note)

Written **before the first write** and shown as step 1 of the apply checklist. If it cannot be written, **nothing is changed at all** (R14).

It records, per port:
- **Every bridge** the port belonged to — active and inactive — the bridge's identity, and its full member list before the change.
- Whether any network service already existed on that interface, its identifier and its position in the service order.
- The port's IPv4 and IPv6 configuration.
- **The identifier of the service RDMALink creates, captured at creation time.**
- A timestamp, which appears verbatim in the Restore copy: **"exactly as it was on 3 September at 14:21"**. Times are the user's locale's short time — **14:21**, or **2:21 PM** where the locale keeps a 12-hour clock — never a 12-hour hour without its AM/PM.

**Matching is by identifier, never by name.** A service the user renames afterwards is still recognized as RDMALink's; a service the user creates that happens to share RDMALink's name is never mistaken for it. This is stated in the review screen's technical names and in the Restore sheet.

Baselines live in Application Support, are listed in the change log, and can be revealed in Finder. The copy always says plainly: **"They're only notes — they don't change anything on their own."**

### 7.2 What Restore does

1. Deletes **only** the service RDMALink created, matched by identifier.
2. Returns the port to **every** bridge it belonged to, including inactive ones, **never deleting or recreating a bridge** — the bridge is always someone else's object and only membership is ever touched. The review, restore and refusal copy all repeat this.
3. **Re-reads bridge membership and verifies it.** This is an explicit, visible step — **"Checking that it's back…"** — not an assumption.
4. **Only after verification passes** does it delete the baseline and print **"Everything is back"**.

If the service is gone but membership has not returned, the baseline is **deliberately kept**, the copy says so plainly (R20), the change log entry keeps its action, and the hub carries a persistent row until it resolves. There is no force, no "clear it anyway", no hidden cleanup.

Restore uses the same one-password burst as set-up and the same visible checklist.

### 7.3 Adopt

A port configured by hand that matches what RDMALink would have made — out of every bridge, its own service, IPv4 off, IPv6 link-local only — is offered `Adopt…`, never reconfiguration.

- Adopting **changes nothing** and **needs no password**. It writes a note so the port appears in the status, the change log and the address list alongside ports RDMALink set up.
- **An adopted port has no exact Restore**, because an adopted note records no bridge the port came from — RDMALink never saw one, or let its old note go when it adopted the port (below) — and RDMALink will not invent a history it has no record of. It offers **Return to Bridge…** instead (§7.5), which does the ordinary thing rather than the remembered thing, and **Stop Managing**, which removes RDMALink's own record and changes nothing on the system.
- **A near match is never adjusted.** RDMALink did not create that service and will not rewrite it; it shows exactly what differs, hands over the steps, offers `Open Network Settings` and `Copy These Steps`, and keeps watching — adopting the moment the port matches.
- **A port RDMALink set up before can be adopted too**, once the service RDMALink made is gone and a matching one made by hand stands in its place (§S1's drift). Adopting replaces RDMALink's old note with the adopted one, and the sheet says so; when the old note records the bridges the port came from, that record goes with it, so `Adopt` is not the sheet's default (§S9, §2.6). The service RDMALink made, edited by hand since, is still RDMALink's and is never adopted: `Restore…` answers for it (R28).

### 7.5 Return to Thunderbolt Bridge

Any port that is out of the bridge can be put back, whoever took it out —
System Settings, the old script, or RDMALink. The row's **Return to Bridge…**
opens the S10 sheet in its foreign-port form.

1. An undo note is written first, recording the port, the standalone service
   RDMALink found (identifier, name, IPv4/IPv6 configuration) and the bridge
   it will join. Without the note, nothing is changed (R14).
2. The standalone service is deleted. When RDMALink did not create it, the
   sheet names it and says so in its own row; a bridge member cannot keep its
   own service, so there is no half-way option. When there is no service at
   all, the row, the step and every sentence about it are omitted (S10's
   no-service form).
3. The port is added as a member of the existing Thunderbolt Bridge. With more
   than one bridge, the one named Thunderbolt Bridge wins; with none, the sheet
   stops and hands off to System Settings (RDMALink never creates a bridge).
4. Membership is read back from the kernel and verified before the sheet says
   the port is in the bridge; on a miss the note is kept and R20 applies.
5. The change log records the return (**Put it back in Thunderbolt Bridge…**,
   S11), the note stays so the row can offer **Set Up Again…**, and the row
   reads **Returned by RDMALink** (§4.3). A returned note is not one `Restore…`
   lists — the port already has everything the note describes — and it is not
   drift; **Stop Managing…** in the Port menu clears it (its sheet says
   exactly what that means: only the note goes), and setting the port up
   again — or adopting it, should it be set up by hand meanwhile — replaces
   it.

### 7.4 Steady state

The hub is the steady state and needs no explaining on the fifth launch: three read-only **This Mac** rows over the live port list, with each ready port's `fe80::` address on its detail line.

- **Status is live.** Link state, bridge membership, service and address changes — including changes made in System Settings while RDMALink is open — land in the row and on the receptacle in place within a second, with a 180 ms badge cross-fade that never reorders or resizes a row, and nothing else moves.
- Because docks and displays may not raise events, `Check Again` sits permanently in the toolbar **and** a quiet one-second state diff runs underneath anyway, so the toolbar button is a reassurance rather than a requirement.
- If something changes on a face you are not looking at, the other face-selector segment takes a small accent dot and the panel offers a single inline `Show Me`. The app narrates rather than grabs.
- **Drift is news, not failure.** If the port is back in a bridge, or its service has been edited or replaced, or a service RDMALink created has disappeared from a port that was in no bridge when it was set up, the row reads **"Not set up any more"**, the hub carries **"Back, far left isn't set up any more"** with `Set Up Again…` and `Stop Managing…` — `Restore…`, `Adopt…` or nothing in place of `Set Up Again…` for a drifted port with a service of its own, as its row offers (§S1) — and **a stale baseline is never silently reapplied to a world that moved.** When the service RDMALink created has gone from a port it took out of a bridge, and the port is in no bridge now and has no service of its own, that is not drift: the row reads **Needs putting back by hand** with `Restore…`, whoever removed the service, because setting the port up again would overwrite the only record of its bridges (§S1). A service made by hand in its place makes it drift: its row offers `Adopt…`, or nothing for a fixed IPv4 address, as above, and a `Restore…` from the footer or the Port menu answers with R28, because putting the port back would mean deleting a service RDMALink didn't make. A port RDMALink returned to the bridge (§7.5) is not drift either: its row reads **Returned by RDMALink** and nothing is raised.
- **Unfinished business survives quitting** and is shown as a hub row the next launch, phrased as a situation rather than an alarm: a port needing a hand, a restart still owed, a drifted port, an adoptable port.
- The **change log is append-only.** Undone entries stay, greyed, marked **"Already put back on 3 September at 15:10."** The record of what this app did to this Mac is never quietly rewritten.
- There is no menu bar extra, no notification, no dock badge and no background agent.

---

## 8. Accessibility

### 8.1 The 3D is never the only path

The port list in the assistant column is **complete, canonical, and present on every screen**. Every selection, every state, every action — set up, Identify, Adopt, Restore, Stop Managing, Forget — is reachable without touching the model. The model is an accelerator, which is exactly what lets it be the hero without being a barrier.

### 8.2 VoiceOver

- The `RealityView` is an accessibility **container** with one element per receptacle, in physical order. The container's summary label is read on focus: **"Mac Studio, back face. Four Thunderbolt ports."**
- Each receptacle element is labelled with its position, kind and state and no more: **"Back, far left. Thunderbolt port. Linked to another Mac. Member of Thunderbolt Bridge."** Its *value* carries the address when configured.
- Custom actions per element: **Select**, **Show Me**, and each of the row's own buttons, by their titles without the ellipsis (§1.3 rule 11) — **Set Up**, **Set Up Again**, **Adopt**, **Restore**, **Return to Bridge**, **Stop Managing** — offered on the row's own terms: absent where the row's button is absent, unavailable where it is disabled. Identify is not one of them: it finds a port the user can't name, so it has no meaning on a port already in focus.
- **Camera moves are announced** with `.announcement` notifications using **the same words the panel shows**: "Turning the Mac around. Now showing the back." A VoiceOver user is told exactly what a sighted user is shown.
- Live state changes are announced **politely**, so they can never interrupt someone mid-sentence. Refusals are announced **assertively**, once, because they stop the flow.
- During Identify every detected change posts an announcement — **"Cable removed from Back, far right"**, **"Found Back, far right"** — which makes Identify arguably better with VoiceOver than without.
- The apply and restore checklists announce each step as its checkmark lands.
- The `fe80::` address is spoken grouped in fours, with the `%` suffix spelled out.

### 8.3 Keyboard

Full keyboard access throughout, with real, visible focus rings — including on the 3D receptacles, which take a focus halo visually distinct from both hover and selection.

| Key | Action |
|---|---|
| Tab / ⇧Tab | Move between stage, port list and footer |
| ← → (stage focused) | Move between receptacles in physical order, camera leaning to follow |
| ↑ ↓ (stage focused) | Switch faces |
| Space | Select |
| Return | Primary / default button |
| Escape | Cancel any sheet, refusal or Identify — always backwards, never forwards, one layer at a time: on the picker with a card up it puts the card away first and keeps the selection, and only then leaves; on a refused S6 it is the card's `Done` (§S6) |
| ⌘1 ⌘2 ⌘3 ⌘4 | Back / Front / Left Side / Right Side, with a checkmark on the face showing (§2.7) |
| ⌘0 / ⇧⌘0 | Fit / Reset View |
| ⌘N | Set Up Port… (the picker, §S4; unavailable while the assistant or a sheet is up) |
| ⌘I | Identify Port… (the Port menu's; on the picker it starts Identify, §S4b; unavailable while a sheet is up) |
| ⌘T | Show Technical Names / Hide Technical Names |
| ⌘K | Hide Legend / Show Legend |
| ⌘L | Change Log (unavailable while the assistant or a sheet is up) |
| ⌘R | Check Again (View menu) |
| ⌘? | RDMALink Help (unavailable while a sheet is up) |
| ⌘C | Copy (address, refusal details, log entry) |
| ⌘, | Settings |

Every default button is `.keyboardShortcut(.defaultAction)` and every cancel is `.cancelAction`. No dialog in the app needs a mouse.

### 8.4 Pointer targets

Every receptacle's hit target is **at least 24 × 24 pt in screen space**, enforced by an invisible proxy collider, and **the camera dolly is floored** so a port can never become un-clickable at any zoom the user can reach. Standard cursors throughout, including `.operationNotAllowed` over USB-only receptacles. No tooltip repeats the text it sits on: S7's address footnote is on screen in full and carries none.

### 8.5 Dynamic Type and layout

All text uses system text styles and scales to Accessibility XXL. **Below 900 pt of width, or at the largest text sizes, the layout reflows to a single column**: the stage collapses to a 180 pt strip at the top showing the relevant face, and the port list plus working area take the rest — the same content, the same copy, the same order, never a different app. The one control the stage carries on §S8, the `Other Mac:` pop-up, stands in the working area while the stage is a strip, because the pair fills the strip (§S8 **The other Mac's picture**). Nothing is truncated without a tooltip carrying the full string.

**The `fe80::` address wraps at a colon group and is never truncated with an ellipsis.** A half-shown address is worse than a wrapped one.

### 8.6 Motion, contrast, transparency

- **Reduce Motion:** camera arcs become a 100 ms cross-fade between fixed poses with identical narration; the Identify shimmer becomes a static dim ring; the apply ring steps between five static states; the ribbon retraction becomes an opacity change; the address appears rather than fading; the waking-ports beat becomes a simultaneous appearance; §S8's ghost changes to the Mac just chosen rather than cross-fading. **Nothing that carries meaning lives only in motion** — every pulse has a text twin in the panel.
- **Increase Contrast:** every ring track goes 1.5 → 3 pt with a contrasting halo; badges gain a 1 pt border; receptacle interiors gain contrast against the chassis.
- **Reduce Transparency:** every floating control capsule on the stage becomes opaque.
- **Differentiate Without Color:** the default behavior, not a mode. Every model state is a distinct ring geometry; every panel state is a distinct SF Symbol plus words. No meaning anywhere depends on hue.

### 8.7 Voice Control

Every receptacle carries a speakable name matching its visible label, and every button's accessibility label equals its visible title, so **"click Back far left"** and **"click Set Up Port"** both work.

### 8.8 Cognitive load and safety

One decision per screen. No timers and no countdowns anywhere except the 60-second Identify watch, which is generous, announced in words rather than numbers, repeatable with one click, and harmless to miss. No auto-advancing destructive step. No color-coded urgency. No red alarm surfaces. **No audio and no haptics.** No dialog ever asks a question whose answer isn't visible on the screen behind it. Nothing in the app flashes faster than three times per second, and nothing pulses faster than 1.6 s.

### 8.9 Localization

All copy is localizable with no concatenated sentences. Position names and locator phrases are separate strings so **"second from the left as you look at the back"** can be rewritten per language. Every technical string — the address, the interface name, the diagnostics — is selectable and copyable.

---

## 9. Delight moments

1. **"Turning the Mac around."** The panel says it, then the camera arcs 180° over 0.7 s with a small dolly out and back, and the ports you need are facing you. It is the single most useful sentence in the app, and it feels like someone lifting the machine off the desk for you.
2. **The ports wake up.** When the opening probe finishes, the receptacles light in physical order with a 60 ms stagger — one readable beat that says *found all six* — then complete stillness. Once per launch, never repeated.
3. **The ribbon lets go.** Bridged ports are visibly tied together by a soft arc across the chassis. The instant the first write lands, the ribbon detaches from the chosen port and retracts into the others. A concept nobody enjoys reading about, understood in half a second without a word.
4. **The ring closes as the work gets done.** Four arcs, four gaps; each gap closes as a real step completes, ending as one unbroken accent ring. Progress you can read from across the room, mapped to geometry rather than to a bar, and honest enough that a stall looks like a stall.
5. **The rollback runs backwards.** If something fails, the same ring re-opens its gaps at the same pace and the ribbon springs back while the checklist reverses. Watching a mistake being undone in front of you is more reassuring than any sentence about it.
6. **Identify's moment of silence.** The instant a port is unplugged, every other port's shimmer stops dead and only the one that moved keeps a ring — the app going quiet around the answer. When the cable goes back in, it blooms and the list row selects itself: **"That's the one."**
7. **The light thread.** A port linked to a real Mac grows a short soft thread of light leaving the receptacle in the cable's direction, fading at the frame edge. It is the only ornament in the entire scene, and it appears only when a real link really exists — which is exactly why it feels earned rather than decorative.
8. **Hover-to-preview.** Point at "Leave Thunderbolt Bridge" on the review screen and the ribbon links to the other members fade away in front of you; point at "Get its own network service" and a small node appears beside the receptacle. You watch each sentence happen before you agree to it.
9. **The address arrives.** `fe80::a2d1:73b4:9e0c:5f16%en6` fades in over 250 ms with a hair of scale, once, and `Copy Address` goes live. After a flow made entirely of plain English, one line of pure technical truth lands as a reward.
10. **"Done. That took 1.8 seconds."** Four ticks land in a little over a second, the ring closing one shade per tick so the checklist and the hardware finish together — and then the app tells you the actual elapsed time. A small, confident brag that makes the whole thing feel light.
11. **Waiting with you.** Finish a port with nothing plugged in and the app doesn't send you away — *"Leave this window open and you'll see it arrive."* — and when the cable goes in, the ring brightens, the thread appears and the address fades in, all in the same 250 ms.
12. **The wordless second Mac.** At the handoff, your machine slides aside and a ghost of the other one fades in beside it — a featureless box, or, once you've said which Mac it is, that Mac's own shape, just as faint: near port lit, far port hollow, one thin line between them, and every other port stepping back so that one line is the only link on the stage. It says *half done* with nothing written on either Mac — the legend's **The other Mac** is the only word about it on the stage — and it never pretends to know anything about that other machine beyond what you told it. When the far end finally answers, a pulse travels back along the line and blooms at your port.
13. **The change log lights the ports.** Scroll the log and hover an entry, and the receptacle it refers to lights up on the model. History becomes spatial — you can watch the last three weeks of your desk replay in order.
14. **"Copied."** The button swaps to a checkmark and the word for two seconds, then quietly goes back. No toast, no banner, no sound.
15. **"Everything is back."** Restore ends with the segmented ring settling to ordinary bridge grey, the ribbon reattached, the camera easing to the resting pose it opened with, and four words that mean the app kept its promise.
16. **An unrecognized Mac gets a clear answer, not a guess.** When neither rule in §4.7 recognizes the Mac there is no stand-in and no set-up: the stage says so in place of a model, the port list stays live and numbered, and RDMALink changes nothing — read-only, exactly as R23 (§6.2 R31). A picture of a Mac the app does not know, or a change made on one, would be a guess presented as knowledge.

---

## 10. Open UX questions for the user

1. **Near-match Adopt.** The spec currently forbids the app from changing a single setting on a service it did not create: a port that is out of every bridge but has IPv6 set to Automatic gets instructions and a watcher, not an "Adjust and Adopt" button. That is the most consistent reading of the rule, but it is also the most friction for the likeliest real case (you set it up by hand on the other Mac last month and got one field wrong). **Do we hold the line, or do we allow a single, explicitly itemized, one-password adjustment with its own review screen?**

2. **Unknown macOS builds (R18).** The whole configure path rests on a private SystemConfiguration SPI. The spec pins it to a tested range and stops on anything outside it, offering manual steps and then Adopt. That is the safest behavior and the most annoying one — every macOS point release breaks the app until we ship. **Do you want a hard stop, a hard stop with a Settings escape for your own machines, or a "probe the SPI and verify the result before trusting it" approach that would let the app run on untested builds when the probe succeeds?**

3. **Thunderbolt-only management (R5).** The spec makes this a **hard refusal**, not a warning, on the grounds that removing a member can briefly bounce the whole bridge rather than just that port. That means someone driving a headless Mac Studio over Thunderbolt Bridge alone cannot use the app at all until they attach Wi-Fi or Ethernet. **Is that the right call for your own rigs, or is the bridge-bounce risk small enough that a strongly-worded warning plus explicit consent is acceptable?**

4. **How many ports in one password burst.** The credential lasts about 30 s. One port takes roughly 1.8 s; multi-select currently allows any number. **Should there be a cap (say three) after which the app splits into a second password prompt with its own review, or should it try them all and rely on R8's rollback if the window closes?** Related: if port 1 succeeds and port 2 fails, should port 1's changes stand (currently yes, with a per-port result summary) or roll back too?

5. **Terminology and one default.** Three words are load-bearing and worth your ear: **"Restore"** vs **"Put It Back"** (warmer, longer, harder to localize); **"Identify Port…"** vs **"Find It for Me"** (friendlier, less standard); **"Adopt"** vs **"Look After This Port"**. And one behavioral default: **should `Set Up Port…` be offered at all when nothing is plugged into any Thunderbolt port?** The spec currently offers it, on the grounds that preparing a port before the cable arrives is legitimate — but it does mean a brand-new user can complete the whole flow and see no address.

6. **Identify on the hub runs S4b (follow-up).** On the picker, `Identify Port…` and the Port menu's ⌘I start §S4b's watch. On the hub the Port menu's `Identify Port…` still turns the model to the port already selected and breathes it once, which answers a question the user didn't ask; the watch belongs there too, with hub copy of its own (no `Use This Port` or `Choose from List`), on Thunderbolt 4 Macs as well. Owed.
