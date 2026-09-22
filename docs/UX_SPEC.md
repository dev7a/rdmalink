# RDMALink — Final UX Specification

**Product:** RDMALink (`com.dev7a.RDMALink`) — a free, notarized, non-sandboxed macOS 27 utility (SwiftUI + RealityKit), distributed from GitHub.
**Job:** Prepare one or more Thunderbolt 5 ports **on the Mac it is running on** so they can carry RDMA over Thunderbolt, and be able to put everything back.
**Audience for this document:** designers building high-fidelity mockups, then engineers implementing. Every quoted string is final copy and may be pasted verbatim.

**Build milestones referenced in this document are `ML0`, `ML1`, `ML2`, `ML3`. They are internal labels for the build plan only. They never appear in the interface, in copy, in window titles, in a progress rail, or in a status bar. The shipped app's only progress indicator is a text label of the form "Step 2 of 3".**

Copy is US English. Every string is a separate localizable resource; no sentence is assembled by concatenation. Position names and locator phrases are separate strings so they can be re-worded per language.

---

## 1. North star & tone

### 1.1 North star

> It feels like a patient friend who already knows your Mac, turns it around so you can see the right port, tells you exactly what it is about to change, asks once, and can put everything back.

### 1.2 What the app is, structurally

Migration Assistant fused with System Settings. A linear assistant that **explains before it acts, checks preconditions itself, and never asks the user to promise anything it could measure**, wrapped around a calm status hub you return to and can read at a glance on the fifth launch.

The RealityKit model is the hero because it is the fastest way to answer *"which physical hole do I put the cable in."* It is therefore wordless, lit like a product shot and not a toy: no idle spinning, no particles, no floor reflections, no sound. Every motion in the scene is either feedback for something the user did, or the app narrating its own camera move **in words first** ("Let me turn it around").

### 1.3 Tone rules (binding on all copy)

1. **Sentence case for all body, headlines, labels, and list rows. Title Case for buttons.**
2. **The app speaks in the first person, sparingly.** "I'll wait." "Let me turn it around." "I can't see the other Mac from here." It is a competent colleague, not a mascot. No exclamation marks anywhere in the app. No jokes at the user's expense. No "Oops."
3. **Never scary.** No red fills, no alarm banners, no sirens, no "WARNING". A refusal is a closed door with the handle pointed out, not an alarm.
4. **Never a promise the app could measure.** There is not one attestation checkbox and not one "I have checked that…" button in the entire app. If the app can observe it, the app observes it.
5. **No escape hatch.** There is no "Continue Anyway", no "I understand the risks", no option-key bypass, and no disabled-but-present primary button on a refusal — a refusal removes the primary action entirely, because a disabled button is still an invitation to hunt for the modifier key.
6. **No technical name is shown unless "Show technical names" is on.** Interface names (`en6`), bridge names (`bridge0`), and exact service names are hidden by default. Two exceptions, both deliberate: the `fe80::` address is always shown in full, because it is the payoff and tools need every character of it; and every "Copy Details" payload on a failure refusal includes the technical names regardless of the toggle, because at that point the user needs them.
7. **Plain physical language.** "Back, far left", not "Port 4". "A dock or a display", not "a non-Mac PCIe endpoint". "Put it back", not "revert configuration".
8. **Honest about the two things it cannot do**: the RDMA system switch and the restart. It says so, points at the setting, and notices the moment it's on.
9. **Never mentions the other Mac's state as if it knew it.** The app models the machine it runs on and nothing else.
10. **Never claims a change it hasn't verified.** "Everything is back" is printed only after bridge membership has been read back.

---

## 2. Window & navigation model

### 2.1 One window

One window, no sidebar, no tabs, no document model, no menu bar extra, no notifications, no dock badge, no background agent. RDMALink is a tool you open, not a thing that lives on your Mac.

- **Title:** `RDMALink`
- **Window subtitle** (set as soon as the model is known): `Studio — Mac Studio (M3 Ultra)` — the Mac's own sharing name, an em dash, the model and chip. The model is the catalogue's name for the identifier, or the product family macOS itself publishes for the Mac when the catalogue has none, and plain `Mac` only when neither exists.
- **Default size** 1000 × 720 pt, so a six-port hub fits without scrolling. **Minimum** 840 × 600 pt. Resizable, remembers frame, not full-screen-oriented.

### 2.2 Toolbar

Unified toolbar, two items, nothing else. No step indicator, no branding, no rail, no "This Mac" badge: that the app only ever changes the Mac it runs on is implied by everything on screen, and the window subtitle already names the machine.

| Position | Item | Symbol | Behavior |
|---|---|---|---|
| Trailing | `Check Again` | `arrow.clockwise` | Re-runs the full probe. Always enabled. A reassurance, not a requirement — a one-second state diff runs underneath at all times. |
| Trailing | `Help` | `questionmark.circle` | Opens the Help menu's first item. |

### 2.3 Body layout

A horizontal split: **STAGE** on the left, **ASSISTANT COLUMN** on the right.

- Default split: stage 58 %, column 42 %. Stage minimum 460 pt, column minimum 380 pt.
- The divider **is** draggable (a standard thin split divider) and the position is remembered. `Reset View` (⌘0) returns the split to 58/42 and the camera to its resting pose. Declaring the model the hero and then forbidding anyone to give it more room is restraint one notch past usefulness.

**STAGE** — the `RealityView`, edge-to-edge, with two floating controls and nothing else:

- **Bottom-center:** the face selector — a segmented control inside a `Capsule` of `.regularMaterial`, Maps-style. `Back / Front` on Mac Studio and Mac mini; `Left / Right` on notebooks (`Back` is offered only if that face carries ports; on current notebooks it does not, so it is absent rather than empty). Hidden entirely when the model has one relevant face (Mac mini with no cable in front). On an unrecognized Mac (R31) the stage has no chrome at all: no selector, no Fit or Reset View, no legend, no callout.
- **Bottom-trailing:** two small borderless buttons, `Fit` (`arrow.up.left.and.arrow.down.right`) and `Reset View`.

**ASSISTANT COLUMN** — a `VStack` on `.windowBackground` with 24 pt margins, in four fixed bands, top to bottom:

1. **Header row.** Step title leading, `Step 2 of 3` in `.caption` secondary trailing. It is a **label, never a progress bar**, and it is absent on the hub, the change log, and settings. It counts the screens of the current run: a set-up that opens on the picker has three steps (Choose, Review, Ready); one whose port was already chosen on the hub, or picked for the user because exactly one port has a Mac on the end, opens on Review and has two. Setting up (S6) keeps Review's label while it runs.
2. **Working area.** `.title2` semibold headline, `.body` secondary explanatory text, then the step's controls (grouped inset lists, `Form` rows, value blocks). This is the only band that changes between steps.
3. **The port list.** A permanent, grouped inset list of **every receptacle on this Mac** — Thunderbolt and USB-only alike — in physical order, grouped by face (`Back`, `Front`, or `Left side`, `Right side`). It is present on every screen of the main window, in every step. **It never reorders and never resizes a row; only badges, subtitles, and trailing controls change**, cross-fading in 180 ms. It has two densities:
   - **Full** (hub, Choose a port, Identify): symbol, title, `.callout` secondary subtitle carrying state and bridge membership, optional trailing borderless button.
   - **Compact** (RDMA, preflight, review, apply, done, other Mac, change log): symbol, title, and a short trailing badge only. Same rows, same order, same place, less ink.
   - It scrolls independently if it cannot fit; it is never truncated away.
4. **Footer.** A separator, then `Back` leading and the primary button trailing with `.keyboardShortcut(.defaultAction)`. Between them, contextual `.caption` secondary text where a step needs it (`2 ports selected`). Directly **above** the separator, when the primary is disabled, the reason is printed in `.callout` `.orange`.

### 2.4 Why the list is always there

Selecting a row highlights the matching receptacle on the model; hovering or selecting a receptacle highlights the row. The mapping is always live in both directions, on every screen. The model is an accelerator; the list is the canonical, complete truth about this machine, and it is never more than a glance away — not behind a step transition, not behind a sheet, not collapsed into a chip.

### 2.5 Transitions

The wizard advances by replacing **only the working area** with a push transition (leading-edge slide, 0.25 s, `.smooth`). The stage stays put and re-poses; the port list stays put and re-densifies; the footer stays put and re-labels. The model is continuous across every step, which is what makes the app feel like one place rather than eight screens.

The hub (steady state) uses the identical layout, with the footer holding `Set Up a Port…` instead of `Continue`, so there is no shape change between browsing and configuring.

### 2.6 Sheets

Sheets are used for exactly five things: **Adopt**, **Restore**, **Restore All Ports**, the macOS authorization dialog (system-owned), and **What This All Means**. Everything else — including every refusal — appears inline in the working area, so the port list and the model stay visible and can point at the thing in the way. Sheets are 480–520 pt wide, standard `.sheet`, headline, body, content, right-aligned button row.

### 2.7 Menus

| Menu | Items |
|---|---|
| **RDMALink** | About RDMALink · Settings… ⌘, · Services · Hide · Quit RDMALink ⌘Q |
| **Edit** | Undo ⌘Z (text fields only) · Cut/Copy/Paste — Copy works on the address, on every refusal's details, and on the change log |
| **Port** | Set Up a Port… ⌘N · Identify a Port… ⌘I · Adopt… · Restore… · Restore All Ports… · Return to Bridge… · Stop Managing… |
| **View** | Back ⌘1 · Front ⌘2 · Left ⌘3 · Right ⌘4 · Fit ⌘0 · Reset View ⇧⌘0 · Show Technical Names ⌘T · Hide Legend / Show Legend ⌘K · Change Log ⌘L |
| **Window** | standard |
| **Help** | RDMALink Help · What RDMA over Thunderbolt Is · What to Do on the Other Mac · Save a Diagnostics File… |

`⌘R` re-checks (same as `Check Again`). Settings is a separate small window with a single General pane and therefore **no tab bar**, per HIG.

### 2.8 Persistent affordances

- **Restore is never hidden.** Whenever any restorable note exists — one that records a set-up to undo; a return record (§7.5) is not one — the footer of the hub carries `Restore…` as a plain button beside the primary, and the Port menu's `Restore…` and `Restore All Ports…` are enabled. You never have to find a row first.
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
| `text.tertiary` | `.tertiary` | technical suffixes, disabled rows |
| `accent` | **the user's system accent color** (blue by default) | selection, the ready ring, the default button, the configured state |
| `attention` | `.orange` | warning text and warning symbols **in the panel only** |
| `stop` | `.red` | **used nowhere.** Restore is not styled destructive, because it restores. There is no destructive confirmation in this app. |
| `material.floating` | `.regularMaterial` | the two floating stage controls |

**Nothing on the 3D model is ever orange, red, green, or any hue carrying meaning.** Warning is a panel job. A colored hole is unreadable at a glance and fails color-blind users. On the model, meaning is carried entirely by **ring geometry** (see §4).

### 3.2 Type — San Francisco throughout

| Role | Style |
|---|---|
| Headline | `.title2.weight(.semibold)` |
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

**The app icon.** One drawing, a link seen head-on: on a full-bleed graphite gradient (the stage's dark background, a little lighter at the top), two closed metal plug ends face each other across the middle of the icon, left and right, each about a quarter of the icon wide — a dark chamfered block with a rounded back and a thin lit rim on its facing end, drawn in the stage's chassis tones, with no opening in it. Between the rims runs one straight beam of accent light, level, thick, brightest at its core and glowing softly at its edges, carrying three small brighter marks along its length like packets in flight. Nothing else: no bolt, no Thunderbolt mark, no ring, no receptacle opening, no text, no Mac silhouette. The artwork is a plain square; the system applies the icon's shape and finish, so nothing is pre-rounded. It has to read at 16 pt as two dark blocks and one blue bar, which is why the plugs are large and the beam is thick; the packet marks may drop out at small sizes.

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
- **Increase Contrast:** every ring track goes from 1.5 pt to 3 pt and gains a contrasting halo; the receptacle interior's contrast against the chassis rises; every list badge gains a 1 pt border; both floating capsules gain a hairline.
- **Reduce Transparency:** both floating capsules become opaque.
- **Reduce Motion:** camera arcs become a 100 ms cross-fade between fixed poses **with the same spoken and written narration**; the Identify shimmer becomes a static dim ring; the apply ring steps between five static states; the ribbon retraction becomes an opacity change; the address appears rather than fading.
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
- Model: plug stub plus a **steady** `.secondary` inner ring at full opacity, plus a short **light thread** that leaves the receptacle along the cable direction and fades out 40 pt from the frame edge. It is one continuous tube — a smooth curve with the sag of a real cable, tapering gently and fading along its length — never a chain of visible segments. The thread is the only ornament in the entire scene, and it exists only when a real Mac is really linked, which is what keeps it honest.
- Panel: `bolt.horizontal.circle.fill` · **"Linked to another Mac"**

### 4.3 Outer track — what the configuration says (five states)

**In a bridge — segmented ring.** Four arcs with four gaps, `.secondary`. Reads as "attached to something else." Membership in a second, inactive bridge looks **identical on the model** — the model shows the fact, the panel carries the count:
- `link` · **"In the Thunderbolt Bridge"**
- `link` · **"In two bridges, including one that isn't in use"**

This segmented ring is the same geometry that **closes during apply** and **re-opens during restore**, so the whole lifecycle of a port is one shape.

**Standalone, no service — no outer ring.** Panel detail: **"Not in any bridge"**.

**Ready for RDMA — a solid, unbroken accent ring** at full opacity with a soft bloom, and no glyph of any kind on the model. Panel: `checkmark.circle.fill` accent · **"Ready for RDMA"** with the `fe80::` address on the detail line.

*Provenance is a panel matter, not a model matter.* A port RDMALink set up and a port RDMALink adopted are both simply **ready**, and the model says so identically; the panel distinguishes them (`checkmark.circle.fill` vs `checkmark.seal.fill`, and the words **"set up by you, looked after by RDMALink"**). The model states facts about the hardware and its configuration; who made the configuration is history, and history lives in the panel and the change log.

**Set up outside RDMALink (adopt candidate) — a solid double-hairline ring** in `.secondary`: complete, like the ready state, but drawn as two thin concentric hairlines rather than one solid ring, and not in accent, because it is not RDMALink's. Panel: `checkmark.circle` `.secondary` · **"Set up outside RDMALink"** · trailing button `Adopt…`

**Needs a look (drift) — a dashed ring** in `.secondary`. The service RDMALink created has gone, or the port is back in a bridge. Panel: `exclamationmark.circle` `.orange` · **"Not set up any more"**. Drift is only ever about a setup RDMALink made or adopted.

**Returned to the bridge — the plain bridged ring.** A port RDMALink itself put back into Thunderbolt Bridge (§7.5) while its note is still there. Provenance is a panel matter: the ring says only that the port is in the bridge. Panel: `arrow.uturn.backward.circle` `.secondary` · **"Back in the bridge"** · trailing button `Set It Up Again`. It is not drift and raises no situation row.

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
| Mac mini (M4 Pro) | `Back, left` · `Back, middle` · `Back, right` · `Front, left` (USB only) · `Front, right` (USB only) |
| MacBook Pro 14/16 | `Left side, rear` · `Left side, front` · `Right side` |
| Unrecognized Mac (R31), or a recognized Mac whose positions are unavailable | `Thunderbolt port 1` … `Thunderbolt port N`; on a recognized Mac **Identify is promoted** to compensate |

**Recognition.** A Mac is recognized by its model identifier when the catalogue lists it. Otherwise it is recognized by two facts it states itself: the product family macOS publishes for it (`Mac Studio`, `Mac mini`, `MacBook Pro`) together with a Thunderbolt receptacle layout that matches that family's table exactly, receptacle for receptacle — every reported position has a name in the table, no two share one, and no table position is missing. Both must agree. When either is absent or differs, the Mac is unrecognized and the app is in R31's read-only mode: no model, numbered ports, and nothing changed. Nothing is ever inferred from the chip or from the port count alone.

With **Show technical names** on, a `.caption` tertiary suffix is appended to the row's detail line only — `en6` — and nowhere else. **No text is ever drawn on the 3D model, regardless of this toggle.**

---

### 4.8 The legend and the receptacle callout

The rings say what the words say; two small aids make sure nobody has to guess which is which.

**Legend.** A `.caption` `.secondary` list in the stage's top-leading corner, one line per outer-ring shape **present on this Mac right now**, glyph first: the ring geometries themselves at small scale. Labels are the panel's own words — **In a bridge** · **Standalone** · **Set up outside RDMALink** · **Ready for RDMA** · **Needs a look**. Nothing about the inner track, nothing about selection, no title. It is shown whenever the rings are live, hidden with View › **Hide Legend** ⌘K (which then reads **Show Legend**), and the choice is remembered. It never overlaps a receptacle: it yields to the model by moving to the top-trailing corner when the chassis reaches under it.

**Callout.** Resting on a receptacle (300 ms, as a tooltip) or moving keyboard focus to it shows a small callout beside it with **the row's title and detail line, verbatim** — "Back, far left" over "Nothing plugged in · In the Thunderbolt Bridge" — and, when technical names are on, the row's technical line too. A USB-only receptacle's callout is its own subtitle, **USB only — this one isn't Thunderbolt**. The callout fades with the hover, says nothing the list does not say, and is never the only place a fact lives. Neither the legend nor the callout exists on an unrecognized Mac (R31), which has no rings.

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

**3D behavior.** The correct chassis is present from the first frame at its resting three-quarter pose, facing the default face (back for desktops, left for notebooks), receptacles unlit and slightly recessed. No rotation, no float, no idle animation. When the probe completes, the receptacles **wake left to right with a 60 ms stagger over roughly 300 ms** — a single readable beat that says *I found them all* — then stillness. It happens once per launch and never repeats. Under Reduce Motion they appear together.

---

### S1 — Overview (the hub) *(ML0 read-only, ML1 entry point; also the steady state on every later launch)*

**Purpose.** What this Mac is, whether RDMA is on, which ports exist and what each is doing, what has already been set up, and what — if anything — is unfinished.

**Layout.** Stage live. Working area: headline, one body line, then a grouped inset **This Mac** section of three read-only rows, plus any situation rows. Port list in **full** density below it. Footer: `Quit` as a plain button at the leading edge — the hub is the place people arrive back at when the work is done, and "Set Up Another Port…" is an offer, not a demand, so the way out is beside it and not only in the menu — then, trailing, `Set Up a Port…` as the default button with `Restore…` as a plain button beside it whenever any baseline exists. `Quit` quits the app exactly as ⌘Q does, asks nothing, and is present in every hub state, R23 and R31 included; it appears on no other screen. A `.caption` secondary link row under the list: `Change Log` · `What This All Means`.

**Primary action.** `Set Up a Port…` (first run) / `Set Up Another Port…` (once at least one port is ready).

**Copy — headlines and body**
- First run headline: **Let's set up a Thunderbolt link**
- First run body: **RDMALink prepares one Thunderbolt port on this Mac so it can carry RDMA straight to another Mac. You'll do the same on the other Mac afterwards.**
- One port ready: **One port is ready for RDMA**
- Two or more ready: **Two ports are ready for RDMA**
- Steady-state body: **Back, far left is set up and linked. Nothing else on this Mac was changed.**
- Steady-state body, nothing attached: **Back, far left is set up and waiting for a Mac. Nothing else on this Mac was changed.**

**Copy — "This Mac" section**
- Section header: **This Mac**
- **RDMA over Thunderbolt — On**
- **RDMA over Thunderbolt — Off. Turn it on to finish.** *[Turn It On…]*
- **RDMA over Thunderbolt — On after you restart**
- **RDMA over Thunderbolt — On, but no RDMA devices appeared** *[Tell Me More]*
- **Thunderbolt Bridge — Four ports are members**
- **Thunderbolt Bridge — Not in use**
- **Thunderbolt Bridge — Two bridges, one of them unused**
- **Ports ready for RDMA — None yet**
- **Ports ready for RDMA — Back, far left**
- **Ports ready for RDMA — Back, far left and Back, far right**
- **Ports ready for RDMA — None by RDMALink · five set up outside it** (only ports set up outside RDMALink are ready; counts are spelled out, and "one set up outside it" in the singular)
- **Ports ready for RDMA — Back, far left · two more set up outside RDMALink** (both kinds; "one more" in the singular)

**Copy — situation rows** (appear above the port list, at most one of each, in this order)
- Needs a hand: **Back, far left needs putting back by hand.** *[Show Me]*
- Drift: **Back, far left isn't set up any more.** · detail: **The network service RDMALink made is gone — it may have been removed in System Settings.** *[Set It Up Again]* *[Forget This Port]*
- Restart owed: **RDMA is switched on and waiting for a restart. Restart whenever it suits you.**
- USB tip: **There's a cable in a front port. Those carry USB, not Thunderbolt. Move it to one of the four ports on the back and I'll follow along.**
- Two Macs tip: **Two Macs are connected. Leave just one cable in place while we work — two can send Ethernet traffic around in a loop.** Shown only when R1 would fire — two ports with a Mac on the end share a bridge — and never for cables on standalone ports.

**Copy — port list section and rows**
- Section headers: **Thunderbolt ports** · **Back** · **Front** · **Left side** · **Right side**
- Subtitles — **Nothing plugged in** · **A device is connected — not a Mac** · **Another Mac is here. The link is still coming up.** · **Linked to another Mac** · **USB only — this one isn't Thunderbolt**
- Membership appended after a middle dot: **· In the Thunderbolt Bridge** · **· In two bridges, including one that isn't in use** · **· Not in any bridge**
- Ready: **Ready for RDMA · fe80::a2d1:73b4:9e0c:5f16%en6**
- Ready, adopted: **Ready for RDMA · set up by you, looked after by RDMALink**
- Ready, nothing attached: **Ready for RDMA · the address appears when a Mac arrives**
- Set up elsewhere: **Set up outside RDMALink** *[Adopt…]*
- Drifted: **Not set up any more** *[Set It Up Again]*
- Returned to the bridge by RDMALink (§7.5), note still there: **Back in the bridge** *[Set It Up Again]* — the link-state subtitle and the membership phrase stay; this is not drift and adds no situation row.
- Trailing buttons, by state: *[Adopt…]* · *[Restore…]* · *[Return to Bridge…]* · *[Stop Managing…]* · *[Set It Up Again]*
- Adopted or set up elsewhere (any port that is out of the bridge and that RDMALink did not set up): the row carries **Return to Bridge…**, so putting a port back never depends on how it was removed. A port RDMALink set up carries **Restore…** instead, which returns it exactly.

**Copy — buttons**
- **Quit** · **Set Up a Port…** · **Set Up Another Port…** · **Restore…** · **Check Again** · **Change Log** · **What This All Means** · **Turn It On…** · **Show Me** · **Forget This Port**

**Copy — Thunderbolt 4 mode**
- Headline: **Nothing to configure here**
- Body: **This Mac has Thunderbolt 4 ports. RDMA over Thunderbolt needs Thunderbolt 5, so there's nothing for RDMALink to set up. You're welcome to look around — everything you see is real.**
- The footer's primary button is **absent**, not disabled. `Identify a Port…` remains available in the Port menu, because it changes nothing and the app is still a useful map.

**Copy — Unrecognized Mac (R31)**
- Headline: **I don't recognize this Mac**
- Body: **RDMALink only draws, and only changes, Macs it knows — and this isn't one of them. So there's no picture, and nothing here will be changed. The ports below are listed the way macOS reports them, and everything you see is real.**
- The footer holds `Quit` and nothing else, and no row has a button: nothing that writes — set-up, Restore, Adopt, Return to Bridge, Stop Managing — is offered, and `Identify a Port…` is absent from the Port menu because there is no model for it to point at. The stage shows R31's block (§6.2) in place of a model.

**States.** First run with RDMA on · First run with RDMA off · Restart pending · One or more ready · An adoptable port present · A drifted port present · A port needing a hand · Cable in a USB-only port · Two Macs connected (the tip row appears and `Set Up a Port…` is **disabled** with the reason printed above the footer separator) · Thunderbolt 4 read-only (R23) · Unrecognized Mac read-only (R31) · Live update arrives.

**3D behavior.** Fully live. On an unrecognized Mac (R31) there is no model and the rows have nothing to light. Every receptacle carries its tracks. Hovering a row lifts the matching receptacle's glow to 40 %; hovering a receptacle highlights the row; hovering a bridge-membership subtitle draws the ribbon. Clicking a receptacle selects its row; double-clicking a configurable one starts set-up for it.

The camera **holds** the resting three-quarter pose and never moves on its own here, with exactly one exception: if a port on a face you are not looking at changes state, the other face-selector segment takes a small accent dot and the working area offers a single inline line — **"Something changed on the back."** *[Show Me]* — which is the only camera move the app ever makes unasked, and it is asked.

---

### S2 — Turn on RDMA over Thunderbolt *(ML0)*

**Purpose.** Explain the one thing the app cannot do, hand off to System Settings, and be waiting when the user comes back from the restart. Reached from the hub's status row, or automatically as the first step of set-up when RDMA is off.

**Layout.** The stage dims to 40 % opacity and desaturates — the model is not the subject here, and saying so visually is more honest than hiding it. Working area: headline, body, a numbered three-step list in a grouped inset box, then a live **Right now** row. Port list in compact density, also dimmed. Footer: `Open System Settings` as the default, `Check Again` beside it, and `Set Up Ports First` as a borderless link-styled button on the far leading edge.

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
- On body: **Good. Now let's get a port ready for it.**
- Welcome-back headline (first launch after the restart): **Welcome back. RDMA over Thunderbolt is on.**
- Welcome-back body: **I can see the RDMA devices now — one for each Thunderbolt controller. That was the part only you could do.**
- On-but-nothing-appeared headline: **RDMA is on, but no RDMA devices appeared**
- On-but-nothing-appeared body: **That usually means this Mac, or this version of macOS, doesn't offer RDMA over Thunderbolt. Setting up a port is still harmless and still undoable — it just won't have anything to carry yet.**
- Fallback when System Settings won't open: **I couldn't open System Settings. Here are the steps to follow by hand.** *[Copy Steps]*
- Buttons: **Open System Settings** · **Check Again** · **Set Up Ports First** · **Copy Steps**
- Helper under `Set Up Ports First`: **You can prepare the ports now and turn RDMA on later. RDMALink will remind you.**

**States.** Off · On in NVRAM but no devices yet · On and devices present (this screen is skipped entirely unless the user navigated here deliberately) · On after a restart but still no devices → R22 · Still off after a restart · System Settings could not be opened.

**3D behavior.** The model stays on screen at 40 % opacity and zero saturation, still and quiet, as a reminder of where you are rather than a participant. No rings, no hover. When the user returns and the app re-detects, color and opacity come back over 300 ms — the visual equivalent of *right, where were we*.

---

### S3 — The four checks *(ML1 — evaluated on S5, not a screen of their own)*

**Purpose.** Check every hard rule the app can measure, so the user is never asked to promise something. **Nothing here is a checkbox, and nothing here can be waved through.** The checks are not a screen: a page of four green ticks with a Continue button asks nothing of anyone, so they live at the top of S5 as its **Checked** group, collapsed when every one is satisfied and expanded when one is not.

**Rows.** Each row: symbol (`checkmark.circle.fill` accent when satisfied, `exclamationmark.circle` `.orange` when not, `circle.dotted` while checking), a title, a `.callout` secondary line carrying the **actual finding**, and a trailing borderless action button only where one helps. Any port a check refers to takes a soft attention ring on the stage.

**Copy.**
- Group label, all satisfied (the collapsed disclosure's one line): **Checked: one cable, nothing mounted, another way in, room for the undo note.**
- Group label, something unsatisfied: **Checked — one thing to sort out first** / **Checked — two things to sort out first** / **Checked — three things to sort out first** / **Checked — four things to sort out first**

| # | Title | Satisfied | Unsatisfied | Button |
|---|---|---|---|---|
| 1 | **One Thunderbolt cable to another Mac** | **Just one, in Back, far left. Perfect.** / **No other Mac is connected yet. That's fine — you can prepare a port now and plug in later.** / **Cables in Back, far left and Back, far right, and no bridge holds more than one of them — nothing can loop.** (two or more cables whose ports share no bridge: a finished set-up) | **Two Macs are connected, on Back, far left and Back, far right. Unplug one and I'll pick this back up.** / **Both ends of one cable are in this Mac, on Back, far left and Back, far right. Unplug one end and put it in the other Mac.** | — |
| 2 | **Nothing mounted over Thunderbolt** | **Nothing is mounted. Good.** | **The volume Vault is mounted over Thunderbolt. Eject it in Finder so nothing gets interrupted.** | **Show in Finder** |
| 3 | **Another way to reach this Mac** | **Wi-Fi is connected, so changing a Thunderbolt port won't cut you off.** | **Right now, Thunderbolt is the only way this Mac is reachable. Changing a port can briefly interrupt the whole bridge — not just that one port — so connect Wi-Fi or Ethernet before we touch it.** | **Open Network Settings** |
| 4 | **Room to save an undo note** | **RDMALink can save its notes, so anything it changes can be put back.** | **RDMALink can't write its notes folder, so it couldn't put things back afterwards. It won't change anything it can't undo.** | **Show the Notes Folder** |

- Reasons printed above S5's footer separator while a check is unsatisfied (the default button is disabled, not removed, because these clear by themselves): **Unplug one of the two cables to continue.** · **Unplug one end of that cable to continue.** · **Eject Vault to continue.** · **Connect Wi-Fi or Ethernet to continue.** · **RDMALink needs somewhere to save its notes before it can continue.**
- Button, in the group's header while something is unsatisfied: **Check Again**

**States.** All four satisfied (collapsed) · Two Macs connected (R1) · Cable looped back into this Mac (R2) · No Mac connected (satisfied, with the gentle note) · A volume mounted over Thunderbolt (R4) · Only reachable over Thunderbolt (R5, **hard refusal**) · Baseline folder unwritable (R14, **hard refusal**) · Managed by a configuration profile (R13, hard refusal, replaces the whole of S5's working area) · Re-checking (rows animate individually, the default button greys for the duration) · A check flips live (unplugging the second cable satisfies row 1 in the same beat, with no click).

**3D behavior.** When a check names a port, that receptacle takes a 1.5 pt attention ring in `.secondary` and a single 1.6 s breath, and the camera turns to the face it is on if it isn't already visible — with the working area printing **"Let me turn it around"** for the duration of the move. With two Macs connected, both receptacles ring simultaneously and a faint light thread leaves each one, **making the loop visible rather than described**; when the user unplugs one, its ring and thread fade and the check flips to satisfied in the same beat, with no click.

---

### S4 — Choose a port *(ML1 single port; ML2 multi-select, Identify, USB trap, all archetypes)*

**Purpose.** Turn *"which hole"* into a two-second decision by making the model and the list one selection.

**Layout.** Stage is the subject: full strength, face selector visible, hover states live. Working area: headline, body, the pre-selection rationale line if there is one, then a borderless `Identify a Port…` button, left-aligned. The port list is in **full** density and every row is a selection target; non-selectable rows are dimmed with an explanatory subtitle. Footer: `Back`, `Continue` as the default (disabled until a selectable port is chosen), and `2 ports selected` in `.caption` secondary on the leading side when more than one is chosen.

**When this screen appears.** The choice is made at the beginning, and only once. A port clicked on the hub before `Set Up a Port…`, a double-clicked receptacle, or a row's own set-up action skips this screen: the run opens on S5 with that port. So does **pre-selection**: if nothing was chosen and exactly one port has a Mac linked, it is picked, the run opens on S5, and the reason is stated there in words rather than assumed — `Back` from S5 is this screen, for anyone who'd rather choose. Otherwise the run opens here.

**After this screen the choice is frozen.** On S5, S6 and S7 no row and no receptacle is a selection target: clicking one does nothing, the chosen port alone carries the accent ring and its badge, and the others are dimmed — the list and the model are status there, not a picker.

**Copy.**
- Headline: **Which port should carry RDMA?**
- Body (desktop): **Click a port on the model, or pick one from the list. If it's on the other side, I'll turn the Mac around.**
- Body (notebook): **Click a port on the model, or pick one from the list. Use the selector below the model to see the other side.**
- Pre-selection line (shown on S5 when the pick was made for the user): **I've picked Back, middle left for you, because that's the port with another Mac on the end of it. Choose a different one if you'd rather.**
- Pre-selection line (two candidates): **Two ports have a Mac on the end. I haven't picked for you — choose the one with the cable you mean.**
- Selectable subtitles: **Linked to another Mac · In the Thunderbolt Bridge** · **Nothing plugged in · In the Thunderbolt Bridge** · **Another Mac is here. The link is still coming up.** · **A device is connected — not a Mac · Not in any bridge**
- Dimmed subtitles: **USB only — this one isn't Thunderbolt** · **Already ready for RDMA** · **Set up outside RDMALink**
- Inline message, USB receptacle clicked: **That's a USB port. The front ports on this Mac carry USB, not Thunderbolt — move the cable to one of the four on the back and I'll follow along.** *[Turn the Mac Around]*
- Informational line, dock attached: **There's a dock in this port. RDMALink can still prepare it — it will carry RDMA once a Mac is on the other end.**
- Informational line, nothing attached: **Nothing is plugged in here yet. That's fine — the address appears when a Mac arrives.**
- Multi-select note: **RDMALink will prepare both, one after the other, from the same password.**
- Live-change line while selected: **Something changed on Back, middle left while you were choosing. It's still selected — have a look before you continue.**
- Buttons: **Identify a Port…** · **Continue** · **Back** · **Turn the Mac Around**
- Selection counter: **2 ports selected**

**States.** Nothing selected · Pre-selected with reason · One selected · Several selected (⌘-click / ⇧-click) · USB receptacle clicked (R3) · Already-ready port clicked (row reads **Already ready for RDMA** and offers `Restore…`) · Hand-configured port clicked (routes to Adopt, S9 — **never to set-up**) · Port with a foreign static-IPv4 service (R16) · Port in an unreadable bridge (R15) · Dock or display attached (allowed, informational) · Identify active (S4b) · Live event mid-selection. (An unrecognized Mac never reaches this screen: R31 offers no set-up.)

**3D behavior.** Hovering a Thunderbolt receptacle fades in a 1.5 pt accent ring at 45 % over 150 ms and highlights the row; the bridge ribbon appears for its bridge. Hovering a **USB-only** receptacle produces no ring ever; instead the receptacle dims 15 % and the cursor takes `.operationNotAllowed`. Clicking selects: the ring goes to full accent, 2 pt, with a soft bloom, and stays. Multi-select shows several full rings.

Choosing a port on a hidden face triggers the narrated camera arc. The face selector maps to real geometry. On a machine with a linked Mac, the light thread from that receptacle stays visible throughout selection, so the user can literally follow the cable they can see behind the desk.

---

### S4b — Identify a port *(ML2)*

**Purpose.** Resolve the one thing nothing on screen can resolve — which physical socket holds the cable in your hand — by letting the hardware answer.

**Layout.** A modal *state* within S4, not a sheet. The port list dims to 30 % and becomes non-interactive; the working area swaps to the Identify copy with a live status line and a small indeterminate `ProgressView`. The stage stays fully live and becomes the whole point. Footer: `Cancel` leading (also Escape) and a contextual default button that appears only once there is an answer.

**Detection is two-beat, and belt-and-braces.** Beat one is any receptacle transitioning away from device-present; beat two is any receptacle transitioning back. **Beat one alone is already a usable answer and is reported immediately** — a user who wanders off holding the cable still has what they came for. Because docks and displays may never emit an event, the watcher does not rely on events alone: a one-second state diff runs underneath, and the success state is identical whichever detector catches it.

**Copy.**
- Headline: **Unplug it and plug it back in**
- Body: **Take the cable out of the port you want to use, wait a moment, then put it back. I'll watch every port and light up the one that moved.**
- Status, watching: **Watching all six ports…** / **Watching all four ports…** / **Watching all three ports…**
- Status, unplug seen: **Got it — that's Back, far right. Plug it back in whenever you're ready.**
- Replug headline: **That's the one**
- Replug body: **Back, far right. If that's not what you expected, try again — no harm done.**
- Nudge at 30 s after an unplug: **Still waiting for it to come back. Take your time.**
- Ambiguous (two receptacles change within the same ~400 ms): **Two ports changed at the same moment** · **I'd only be guessing which one you meant, and I'd rather not. Let's try again — one cable at a time.**
- USB-only identified: **That's a USB port** · **Back, far right isn't it — that's Front, left, and the front ports on this Mac carry USB, not Thunderbolt. Try one of the ports on the back.**
- Timeout headline (60 s, nothing seen): **I didn't see anything change**
- Timeout body: **Some devices don't announce themselves, and an empty port has nothing to announce. Pick a port from the list instead — or try again with a Mac on the other end.**
- Buttons: **Use This Port** · **Identify Again** · **Pick from the List** · **Cancel**

**States.** Watching · Unplug seen · Replug seen · Unplug seen, no replug after 30 s · Nothing after 60 s · Ambiguous · USB-only identified · Caught by state diff rather than event (identical success) · Cancelled (returns to S4 with the previous selection intact).

**3D behavior.** Every eligible receptacle carries a slow, in-phase shimmer — a 1.6 s opacity breath between 8 % and 18 % on a thin ring — which reads as *listening*, not *loading*. The camera pulls back to fit the whole chassis and, on machines with ports on two faces, moves to a three-quarter pose from which both faces are partly visible, so a change anywhere will be seen.

The instant an unplug lands, **every other shimmer stops dead** and the changed receptacle takes a steady `.secondary` ring — the silence around the answer is the feedback. On replug it blooms to full accent over 250 ms with a single 8 % scale pulse **on the ring only**, the camera arcs square on, and the list row selects itself. Under Reduce Motion the shimmer is a static dim ring and the bloom is a cross-fade.

Identify is **read-only, needs no password, and is always available** — including on Thunderbolt 4 Macs. It is not offered on an unrecognized Mac (R31): with no model there is nothing for it to point at, and the numbered rows already say what macOS says. It also defuses the identical-Macs trap directly: it answers about **this** Mac only, using **this** Mac's hardware events, so it cannot be confused by the twin on the shelf.

---

### S5 — Here's what will change *(ML1 — review)*

**Purpose.** The promise screen. Everything the app is about to do, in plain words, with the technical truth one disclosure away, and the last chance to back out before any password is asked for.

**Layout.** Stage holds the selected receptacle(s) lit and centered, camera square on the face. Working area: headline, one body line, the pre-selection line when the pick was made for the user (S4), then the **Checked** group (S3: one collapsed disclosure line when all four are satisfied, the four rows when one is not), then **one grouped inset section per selected port**, headed by the position name. Each section has four rows; each row is a symbol, a title, a `.callout` secondary sentence, and a **before → after pair of chips**. Below the sections: a footnote, a collapsed `What I Won't Touch` disclosure, and a `Show technical names` disclosure bound to the same preference as Settings. Port list compact, frozen (S4), with the target port(s) marked **About to change**. Footer: `Back` (to S4), and a default button naming exactly what it will do; pressing it asks macOS for the password straight away — there is no screen between this one and the work.

**Copy.**
- Headline: **Here's what will change**
- Body: **Nothing has happened yet. When you're ready, macOS will ask for an administrator's name and password once — it doesn't have to be yours, and RDMALink never sees or stores it — and every change is made in one go.**
- Section header: **Back, far left**

| Row | Title | Body | Chips |
|---|---|---|---|
| 1 | **Save how to undo this** | **Before anything else, RDMALink writes down exactly how this port looks today. If it can't write that note, it won't change a thing.** | **Nothing saved → Saved** |
| 2 | **Leave the Thunderbolt Bridge** | **This port is a member of Thunderbolt Bridge. RDMALink removes just this port. The bridge itself stays exactly as it is, with its other ports.** | **In the bridge → Standalone** |
| 3 | **Get its own network service** | **A new service called RDMA — Back, far left. Nothing else on this Mac uses it.** | **Doesn't exist → Created** |
| 4 | **Turn IPv4 off, IPv6 to link-local** | **That's all RDMA needs, and it keeps this port off your ordinary network.** | **IPv4 automatic, IPv6 automatic → IPv4 off, IPv6 link-local only** |

- Row 2 variant, two bridges: **It's also in an unused bridge, Thunderbolt Bridge 2. RDMALink removes it from that one too — a port has to be out of every bridge, even one that isn't being used.** Chips: **In two bridges → Standalone**
- Row 2 variant, not in a bridge: **This port isn't in any bridge, so there's nothing to remove.** Chips: **Standalone → Standalone**
- Footnote: **Your Wi-Fi, your Ethernet, and every other network service are untouched.**
- Disclosure label: **What I Won't Touch**
- Disclosure content: **Your other Thunderbolt ports. The Thunderbolt Bridge itself — RDMALink never deletes or recreates a bridge, it only removes a member. Wi-Fi. Ethernet. File sharing, the firewall, and everything else on this Mac. The RDMA system setting, which is yours to switch.**
- Warning row, RDMA off: **RDMA over Thunderbolt is still off. The port will be ready; RDMA will start using it after you turn that on and restart.**
- Warning row, nothing attached: **Nothing is plugged into this port yet. It'll be ready and waiting.**
- Warning row, dock attached: **There's a dock or a display in this port. It'll keep working exactly as it does now — RDMA will use the port once a Mac is on the other end.**
- Disclosure label: **Show technical names**
- Disclosure content: **Interface en6 · New service RDMA — Back, far left · Removing from bridge0: members en5, en6, en7, en8 → en5, en7, en8 · Also removing from bridge1: members en6, en9 → en9 · IPv4 configuration: Off · IPv6 configuration: Link-local only · RDMALink records the service it creates by its identifier, not its name, so renaming it later doesn't confuse anything.**
- Buttons: **Set Up Port** · **Set Up 2 Ports** · **Back**

**Hover-to-preview.** Hovering a change row previews it on the model, silently and reversibly:
- Hovering **Save how to undo this** → a small bookmark glyph fades in at the stage's trailing edge.
- Hovering **Leave the Thunderbolt Bridge** → the ribbon links from this receptacle to the other members **fade away** in front of you, and the segmented ring's gaps widen a hair.
- Hovering **Get its own network service** → a small accent node fades in beside the receptacle.
- Hovering **Turn IPv4 off…** → the node gains a single hairline ring.

You can watch each sentence mean something before you agree to it.

**States.** Single port, one bridge · Single port, an active and an inactive bridge · Single port, no bridge · Several ports · Pre-selected for the user · Technical names expanded · A warning present (never blocking) · A check unsatisfied (R1, R2, R4 — the Checked group expands, the default button is **disabled** with the reason above the separator, and it clears live) · A refusal present (R5, R13, R14, R15, R16 — the section is **replaced** by the refusal and **the default button is removed entirely**, not disabled) · Topology changed since S4 → R17 · OS password dialog up (the working area dims 20 % and says nothing over it) · Permission refused or cancelled → R6 / R7, back here with the selection intact.

**3D behavior.** The camera moves square on to the face carrying the selection and frames it; unselected receptacles fade to 25 %, so the scene shows the subject and its context and nothing else. The selected port's outer ring is drawn as the **open segmented ring** — four arcs with four gaps — because the port is still a bridge member, and the gaps are exactly what will close during apply. This is the one piece of visual foreshadowing in the app, and it costs nothing to read.

---

### S6 — Setting up *(ML1 — apply)*

**Purpose.** Perform every write in a single burst inside the 30-second credential window, showing real progress and never offering a cancel the app cannot honor. The password was asked for by S5's default button; this screen begins the moment macOS hands back the permission.

**Layout.** The step label stays S5's. The footer's buttons **disappear entirely** — there is no control the app cannot honor. The working area shows a headline, a body, and a live checklist in a grouped inset list, one row per write, each `circle.dotted` while pending, a small `ProgressView` while running, `checkmark.circle.fill` when done, with a status line beneath.

**Copy.**
- Headline: **Setting up Back, far left** / **Setting up two ports**
- Body: **A few seconds. Your other network connections stay up the whole time.**

| Step | Pending | Running | Done |
|---|---|---|---|
| 1 | **Save how to undo this** | **Saving how to undo this…** | **Saved** |
| 2 | **Remove from Thunderbolt Bridge** | **Removing from Thunderbolt Bridge…** | **Removed from Thunderbolt Bridge** |
| 3 | **Create the RDMA service** | **Creating the service…** | **Created RDMA — Back, far left** |
| 4 | **Turn IPv4 off, IPv6 to link-local** | **Setting the addresses…** | **IPv4 off, IPv6 link-local only** |
| 5 | **Check it's out of every bridge** | **Checking every bridge…** | **Out of every bridge** |

- Status line: **You can undo all of this afterwards, from the main window.**
- Rollback status line: **Something didn't take. Putting the port back exactly as it was…**
- Completion line, printed under the last checkmark before the screen advances: **Done. That took 1.8 seconds.**

**The undo note is step 1, not step 5.** If it cannot be written, nothing is changed at all (R14). The gate that protects every other promise goes first, and the screen says so.

**States.** Running · Second port of two · A step failed → automatic rollback, checklist reverses with a returning symbol → R10 · Credential expired mid-burst → rollback → R8 · Rollback succeeded → R10's screen · Rollback failed → R11 · Another app holds the network lock → R12 · All steps done → advances to S7 about 400 ms after the last checkmark settles.

**3D behavior.** The selected receptacle's segmented ring **closes its gaps one by one** as each real step completes, ending as a solid accent ring; in the same beat as the first gap closes, the bridge ribbon detaches from this receptacle and retracts into the remaining members. Nothing else in the scene moves; the camera is locked for the duration so the eye has one place to be. If rollback runs, **the ring re-opens its gaps in reverse at the same pace and the ribbon springs back** — an honest and oddly calming thing to watch. Under Reduce Motion the ring steps between five static states.

---

### S7 — Ready *(ML1 — the payoff)*

**Purpose.** Deliver the `fe80::` address, plus an honest picture of what is and isn't finished, and point at the other Mac.

**Layout.** Stage: the camera eases back a step; the configured receptacle holds a solid accent ring with a soft bloom. Working area: headline, body, then a prominent **value block** — a rounded rect of `.controlBackground` containing a `.caption` secondary label, the address in `.body.monospaced()` and selectable, and a borderless `Copy Address` button on the trailing edge — then a small grouped list of status rows, then the footnote. Port list compact, with this port now reading **Ready**. Footer: `What to Do on the Other Mac` as a plain button and `Done` as the default.

**Copy.**
- Headline: **Back, far left is ready**
- Body: **The port has left the Thunderbolt Bridge and has its own link-local address. It'll carry RDMA as soon as the other Mac is set up the same way.**
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

**Purpose.** Close the loop the app cannot cross. Reached from S7 or from the Help menu. **This is a screen, not a sheet**, because the stage does the talking.

**Layout.** Working area: headline, body, a numbered four-step list, a quiet note, and a button row. The stage performs the handoff.

**Copy.**
- Headline: **Now the other Mac**
- Body: **RDMALink only ever changes the Mac it's running on. There's no connection between the two — you do the same thing over there, by hand, and that's the whole trick.**
- Step 1: **Copy RDMALink across, or download it again on the other Mac.**
- Step 2: **Open it and walk the same short path.**
- Step 3: **Pick the port with the other end of this cable in it. Identify makes that painless.**
- Step 4: **When both sides are done, each Mac has its own address on this link. This one is fe80::a2d1:73b4:9e0c:5f16%en6.**
- Step 4, address not known yet: **When both sides are done, each Mac has its own address on this link. This one's address appears as soon as a Mac is connected.**
- Note: **Leave this one cable connected while you're over there — and keep it to one cable between the pair.**
- Honesty line: **I can only see this Mac. Nothing I did crossed that cable — that's deliberate.**
- Live line when the far end answers: **Something answered on this link. That's a good sign — the other end is awake.**
- Buttons: **Copy These Steps** → **Copied** · **Done**

**3D behavior — the ghost second Mac.** The camera pulls back and pans so this Mac occupies the leading third of the stage. A **featureless rounded box** at 40 % opacity slides in from the trailing side with a single thin connecting line between the two. The near port carries its solid accent ring; the far port is hollow and unlit. Nothing is written on either box, and **the ghost never gains detail, ever** — it is explicitly *a Mac I can't see*. When the far end answers on the link, a returning pulse travels back along the line and blooms at the near receptacle, once. That is the only animation in the app that means *the other Mac exists*, and it lands without a word of copy.

---

### S9 — Adopt a port *(ML2)*

**Purpose.** Recognize a port someone already configured by hand and take responsibility for it **without touching it**, so the app can keep an honest record.

**Layout.** Sheet, 500 pt wide, raised from the port's row in the hub or from S4. Headline, body, a grouped inset list of four findings rows (symbol, label, value), a note, then buttons.

**Copy — full match.**
- Headline: **This port is already set up**
- Body: **Back, far right isn't in any bridge and already has its own service with IPv4 off and IPv6 link-local only. That's exactly what RDMALink would have made. Adopt it and RDMALink will keep an eye on it — without changing a thing.**
- Findings: **Service — Thunderbolt Bridge Free** · **IPv4 — Off** · **IPv6 — Link-local only** · **Bridge membership — None**
- Note: **Adopting changes nothing and needs no password. RDMALink is only writing itself a note.**
- Honesty note: **One thing to be straight about: RDMALink never saw this port before, so it doesn't know which bridge it came from. There's no exact "put it back" for an adopted port — Return to Bridge does the ordinary thing instead, and "stop looking after it" leaves the port exactly as it is.**
- Buttons: **Adopt** · **Leave As Is**
- Confirmation: **Adopted. Back, far right is in RDMALink's care now.**

**Copy — near match. The app does not adjust a service it did not create.**
- Headline: **Nearly a match**
- Body: **Back, far right is out of every bridge and has its own service, but IPv6 is set to Automatic rather than Link-local only. RDMALink didn't make this service, so it won't rewrite it — but here's exactly what to change, and it'll adopt the port the moment it matches.**
- Steps: **In System Settings, open Network, choose Thunderbolt Bridge Free, then Details, then TCP/IP. Set Configure IPv6 to Link-local only. Set Configure IPv4 to Off.**
- Buttons: **Open Network Settings** · **Copy These Steps** · **Leave As Is**
- Watcher line: **I'll keep looking. When it matches, I'll offer to adopt it.**

**States.** Full match · Near match · Not a match at all (no `Adopt…` button is ever offered; the hub subtitle simply describes what it found) · Adopted (the sheet closes and the hub row changes in place) · Already adopted (the row's trailing button reads `Stop Managing…`).

**3D behavior.** Before the sheet appears, the camera turns to the port in question and rings it with the **double-hairline `.secondary`** ring — adopting something you cannot see is how mistakes happen. On Adopt, the double hairline resolves into a single solid accent ring over 250 ms, which is the entire ceremony.

---

### S10 — Restore a port *(ML1)*

**Purpose.** Put a port back exactly as it was found, verify it landed, and only then forget the baseline.

**Layout.** Sheet, 500 pt wide, from a row's `Restore…` button, the hub footer, the change log, or the Port menu. Headline naming the port, body naming the moment the baseline was taken, a grouped list of exactly what will happen, then buttons. After `Restore`, the sheet's content is replaced by the same live checklist pattern as S6, including the password step.

**Copy.**
- Headline: **Put Back, far left the way it was?**
- Body: **RDMALink will delete the service it made and return the port to Thunderbolt Bridge — exactly as it was on 3 September at 14:21.**
- Rows: **Delete the service RDMA — Back, far left** · **Add the port back to Thunderbolt Bridge** · **Check that it really is back, then forget the whole thing** · **Leave every other setting alone**
- Note: **RDMALink matches the service by its identifier, not its name, so it only ever deletes the one it made — even if it's been renamed since.**
- Note: **Your RDMA system setting isn't RDMALink's to touch, so it stays exactly as it is.**
- Note (two bridges): **The port goes back into both bridges it belonged to, including the unused one.**
- Buttons: **Restore** · **Cancel**
- Steps: **Deleting the service…** · **Returning the port to Thunderbolt Bridge…** · **Checking that it's back…**
- Success headline: **Everything is back**
- Success body: **Back, far left is a member of Thunderbolt Bridge again, and RDMALink has forgotten it. Nothing else on this Mac was touched.**
- Service-already-gone line: **The service RDMALink made isn't there any more — someone removed it already. It'll just get the bridge membership back.**
- Half-done headline: **Not quite back yet** (see R20)
- Foreign-port headline (a port RDMALink did not set up, adopted or not): **Return Back, far right to Thunderbolt Bridge?**
- Foreign-port body: **RDMALink didn't set this port up, so it can't put things back exactly as they were — but it can do the ordinary thing: add the port to Thunderbolt Bridge and remove the standalone service it has now. It writes down what it found first, so you can set the port up again afterwards.**
- Foreign-port rows: **Add the port to Thunderbolt Bridge** · **Delete the service Thunderbolt 6 — RDMALink didn't make this one, and a bridge member can't keep its own service** · **Check that it really is in the bridge** · **Leave every other setting alone**
- Foreign-port button: **Return to Bridge**
- Foreign-port success: **Back, far right is in Thunderbolt Bridge** · **The port is a member of Thunderbolt Bridge again and its standalone service is gone. Set It Up Again is one click away if you change your mind.**
- Foreign port with **no** standalone service (a port taken out of the bridge by hand and left bare): body **RDMALink didn't set this port up, so it can't put things back exactly as they were — but it can do the ordinary thing: add the port to Thunderbolt Bridge. It writes down what it found first, so you can set the port up again afterwards.** · rows **Add the port to Thunderbolt Bridge** · **Check that it really is in the bridge** · **Leave every other setting alone** (no delete row, no delete step) · success **Back, far right is in Thunderbolt Bridge** · **The port is a member of Thunderbolt Bridge again. Set It Up Again is one click away if you change your mind.**
- No bridge exists: headline **There's no Thunderbolt Bridge to return it to** · body **This Mac has no Thunderbolt Bridge at the moment. RDMALink never creates one — recreate it in System Settings, under Network › Manage Virtual Interfaces, and I'll offer the return the moment it exists.** · buttons **Open Network Settings** · **Cancel**
- Stop-managing headline (adopted port, keep the setup, forget the note): **Stop looking after Back, far right?**
- Stop-managing body: **Stopping just means RDMALink forgets its note. The port and its settings stay exactly as they are.**
- Stop-managing button: **Stop Managing**
- Stop-managing confirmation: **Done. Back, far right is exactly as it was a moment ago — RDMALink is simply no longer keeping an eye on it.**
- Restore All headline: **Put every port back?**
- Restore All body: **Two ports will return to Thunderbolt Bridge and their services will be deleted. One password covers both. RDMALink does them one at a time and stops at the first thing that looks wrong.**
- Restore All partial summary: **One port is back. Back, far right didn't finish — its undo note has been kept, so you can try that one again.**

**States.** Ready to restore · Foreign port (Return to Bridge) · Adopted port (Return to Bridge, or Stop Managing) · A volume mounted over this link (R4 — `Restore` is not offered) · Restoring · Verifying bridge membership (an explicit step, never an assumption) · Verified (baseline deleted) · Service deleted but membership not restored → R20, **baseline deliberately kept** · Baseline missing or unreadable → R19 · Original bridge no longer exists → R21 · Restore All (one sheet, one password, sequential, per-port results, a partial-success summary that never rounds up).

**3D behavior.** The camera turns to the port and rings it in accent. As the restore runs, the solid ring **re-opens into the four-arc segmented ring** and the bridge ribbon springs back out and reattaches — the visual inverse of set-up, which makes *back where it was* literal. On verified success, the segmented ring settles to the ordinary bridge-member state over 400 ms and the camera eases back to the resting pose. If verification fails, **the ring stops half-open and stays that way**, matching the copy exactly.

---

### S11 — Change log *(ML3)*

**Purpose.** An always-available, timestamped, plain-English, **append-only** record of everything RDMALink has done to this Mac, each with its own way back.

**Layout.** Reached with `Change Log` on the hub, `⌘L`, or the Help menu. The working area is replaced by a scrolling list, newest first. Each entry: date and time, the port's position name, one sentence, and a trailing action. Undone entries stay, greyed, with the action replaced by a note. The port list stays in place beside it. A footer line states where the notes live.

**Copy.**
- Headline: **What RDMALink has changed on this Mac**
- Empty: **Nothing yet. When RDMALink changes something, it'll be listed here with a way back.**
- Entry: **3 September, 14:21 — Back, far left** · **Took it out of Thunderbolt Bridge and gave it its own service, with IPv4 off and IPv6 link-local only.** *[Restore…]*
- Entry: **3 September, 14:40 — Back, far right** · **Adopted. RDMALink noted how it was already set up and changed nothing.** *[Stop Managing…]*
- Entry (returned to the bridge, §7.5): **20 September, 11:40 — Back, far left** · **Put it back in Thunderbolt Bridge and removed its standalone service.** *[Set It Up Again]* — with no standalone service: **Put it back in Thunderbolt Bridge.**
- Undone entry: **Already put back on 3 September at 15:10.**
- Returned entry after the port is set up again, or adopted: **Set up again on 20 September at 11:52.**
- Adopted entry after the port is returned to the bridge: **Put back in the bridge on 20 September at 11:40.**
- Stopped entry: **RDMALink stopped looking after this port on 3 September at 15:12.**
- Vanished port: **This port isn't on this Mac any more, so there's nothing left to put back. The note stays until you clear it.** *[Forget This Note]*
- Footnote: **RDMALink keeps one small note per port, in your Library folder. They're only notes — they don't change anything on their own.**
- Buttons: **Show the Notes in Finder** · **Save a Diagnostics File…** · **Done**

**3D behavior.** The model rests at 70 % brightness. **Hovering a log entry lights the receptacle it refers to** at full brightness with a thin ring, so history is spatial — you can scroll the log and watch the ports light up in the order things happened. Entries for ports that no longer exist produce no highlight, and the row says so rather than leaving you hunting.

---

### S12 — Settings *(ML0 / ML3)*

**Purpose.** The one preferences surface. A single pane, so per HIG **no toolbar and no tab bar**.

**Layout.** Separate window, 480 pt wide, height to fit. One `Form` with `.formStyle(.grouped)`: a section of one toggle with `.callout` help text beneath it, and a section with buttons. There is no update check: the app never contacts anything, and a toggle that claimed to would be a promise it does not keep (§1.3 rule 10).

**Copy.**
- Toggle: **Show technical names** · Help: **Adds names like en6 and the exact service names next to each port. The link address always shows in full, because tools need every character of it. Nothing is ever written on the picture of your Mac.**
- Button: **Reveal Notes in Finder** · Help: **RDMALink keeps one small note per port it set up. That note is what makes putting things back possible — it's safe to back up and safe to leave alone.**
- Button: **Save a Diagnostics File…** · Help: **A plain text file with what RDMALink can see on this Mac and what it has changed: the model, the chip, the macOS build, the ports, and any step that failed. No personal information, and nothing is sent anywhere — it's yours to keep or share.**

**States.** Default · Technical names on (the main window updates live, no relaunch) · No notes saved yet (`Reveal Notes in Finder` is disabled with a help tooltip).

**3D behavior.** None. Settings has no 3D content, and adding any would be exactly the sort of gimmick this app avoids.

---

### S13 — What this all means *(Help)*

**Purpose.** One short explainer for the curious that never becomes required reading. Reached from the hub, from the address footnote, and from the Help menu.

**Layout.** Sheet, 560 pt wide, four short sections, one flat 2D illustration of two Macs and one cable (**not** the 3D model — the sheet is reading material, and mixing the live model in would imply the drawings are about this particular Mac). `Done`.

**The illustration.** Two plain rounded slabs — no logo, no trade dress, no product likeness — each with four small Thunderbolt receptacles along its facing edge. On each Mac the three receptacles still in the bridge are tied together by a soft translucent ribbon labelled **Thunderbolt Bridge** in `.caption` secondary; the fourth stands apart, ringed in the accent. One accent cable, a smooth curve with a gentle sag, runs between the two ringed receptacles, with **fe80::** set in `.caption` monospaced secondary above its middle. Those are the only words on it. Hairline strokes and control-background fills; the accent is used for the ring, the cable and, optionally, one small dot that travels slowly along the cable — stilled under Reduce Motion, and the picture is complete without it. It says what the four sections say, in one glance: the bridge stays, one port leaves it, one cable, one address.

**Copy.**
- Headline: **What this all means**
- **RDMA over Thunderbolt** — **RDMA lets two Macs move data between them without troubling either one's processor very much. Over a Thunderbolt 5 cable that's quick enough to feel like a local disk. Tools like exo and MLX clusters use it.**
- **Why take the port out of Thunderbolt Bridge?** — **The bridge joins your Thunderbolt ports into one ordinary network, which is lovely for file sharing and wrong for this. RDMA wants a cable that belongs to it alone, so RDMALink gives the port its own service and leaves the bridge otherwise untouched. A port has to be out of every bridge, even one that isn't switched on.**
- **Why only one cable between two Macs?** — **The bridge works like a hub: whatever arrives on one Thunderbolt port is sent out of all the others. So a second Thunderbolt connection between the same two Macs — or a ring of Macs — with those ports still in the bridge gives traffic a way to go round and round for ever, eating processor time and dragging the network down. Apple says so in its technote on RDMA over Thunderbolt. One cable, no loop.**
- Under that section, a `.caption` link: **Apple's technote on RDMA over Thunderbolt** → `https://developer.apple.com/documentation/technotes/tn3205-low-latency-communication-with-rdma-over-thunderbolt` (TN3205, which says a bridge forwards like a hub, that a loop lets frames travel indefinitely, and to keep looped ports out of the bridge). Opens in the default browser; the only link on the sheet.
- **That fe80:: address** — **It's a link-local IPv6 address. It only means anything down that one cable, which is exactly what we want — the port is now its own small private network. That's also why IPv4 can be off entirely.**
- Closing line: **You don't need to know any of this to use RDMALink.**
- Button: **Done**

---

## 6. Refusals & errors

### 6.1 The shape of every refusal

Documented once so they all read the same.

1. **Inline in the working area**, never a sheet — so the port list and the model stay visible and can point at the thing in the way. (The only exception is a refusal raised inside the Restore or Adopt sheet, which stays in that sheet.)
2. A hierarchical SF Symbol in `.secondary` or `.orange`. **Never a filled red badge, never a full-bleed alarm.**
3. A headline that **names the situation**, never scolds and never says "Error".
4. One short paragraph of plain-language *why*, including the real-world consequence, naming the exact port or volume in the same words used everywhere else in the app.
5. **The primary action is always a real action** — open the right settings pane, turn the model to the right port, show something in Finder, or re-check. **There is never a "Continue Anyway", never an "I understand the risks", never a hidden modifier key.** Where the condition is physical, the refusal has **no button at all**: it watches itself and clears.
6. **On the review screen the primary button is removed, not disabled.**
7. Every refusal that follows a partial write **states the rollback first**, before explaining anything else.
8. `Copy Details` appears on every failure refusal and always includes the technical names regardless of the "Show technical names" toggle, plus the model, the chip, the macOS build, the failing step and the underlying reason — and nothing else. It is the same payload as `Save a Diagnostics File…`.
9. Self-clearing refusals cross-fade to a single line — **"Sorted. Carrying on."** — and the flow continues by itself.
10. `Back` always remains, so the only ways out of a refusal are backwards or fixing the cause.

**Shared strings:** **Nothing has been changed.** · **I'll keep watching — when this is sorted I'll carry straight on.** · **Sorted. Carrying on.** · **Check Again** · **Copy Details** → **Copied** · **Back**

### 6.2 The refusals

---

**R1 — Two Macs are connected (loop risk).** *Blocks preflight and any apply.* Fires when two or more receptacles with a Mac on the end are members of the same bridge, in the kernel or in the saved network settings. A port that is already standalone forwards nothing, so two cables on two standalone ports — a finished set-up — never trip it.
- Headline: **Two Macs are connected**
- Body: **Thunderbolt Bridge forwards Ethernet between Macs, and two cables between the same pair can send traffic around in a loop. Unplug one cable and I'll pick this back up — the other one can go back in when we're done.**
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
- Body: **The front ports on this Mac carry USB, not Thunderbolt. Move the cable to one of the four Thunderbolt ports on the back and I'll follow along.**
- Body (Mac mini): **The two ports at the front of a Mac mini carry USB, not Thunderbolt. The three on the back are the Thunderbolt ones.**
- Buttons: **Turn the Mac Around** (default) · **Check Again**
- **Recovery:** the camera arcs to the back face and breathes the eligible receptacles once, in sequence; when the cable reappears in a Thunderbolt port the tip dismisses itself with **"Got it — that's a Thunderbolt port. Carry on."**

---

**R4 — Something is still mounted over Thunderbolt.** *Blocks preflight and blocks Restore.*
- Headline: **Something is still using this link**
- Body: **The volume Vault is mounted over Thunderbolt. Eject it in Finder so nothing gets interrupted, then we'll carry on.**
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
- Buttons: **Open Users & Groups** (default) · **Back**

---

**R7 — No administrator permission given.**
- Headline: **No changes were made**
- Body: **Without an administrator's permission RDMALink can't touch the bridge — and it didn't. Everything is exactly as it was. Try again whenever you're ready; the name and password don't have to be yours.**
- Buttons: **Try Again** (default) · **Back**
- **Recovery:** returns to S5 with the selection intact; the default button asks again.

---

**R8 — The permission expired mid-burst.**
- Headline: **That took a moment too long**
- Body: **The permission macOS gives RDMALink lasts about thirty seconds, and it ran out before every change went through — so RDMALink put the port back exactly as it was. Let's go again; it usually flies through.**
- Buttons: **Try Again** (default) · **Done** · **Copy Details**
- **Recovery:** the reversed checklist stays on screen as proof of the rollback, then the flow returns to S5 after re-verifying the world.

---

**R9 — macOS wouldn't release the port from the bridge.**
- Headline: **macOS wouldn't let go of that port**
- Body: **RDMALink couldn't remove Back, far left from Thunderbolt Bridge, so it stopped and changed nothing at all. You can take it out by hand in System Settings, under Network — open the three-dot menu, choose Manage Virtual Interfaces, open Thunderbolt Bridge and remove just this port. Come back after that and RDMALink will offer to adopt it.**
- Buttons: **Open Network Settings** (default) · **Check Again** · **Copy Details**

---

**R10 — The service couldn't be created; rolled back.**
- Headline: **Put back, safely**
- Body: **The new service wouldn't create, so RDMALink returned the port to Thunderbolt Bridge. Nothing has been left half-done, and it checked before telling you.**
- Buttons: **Try Again** (default) · **Done** · **Copy Details**
- **Recovery:** the ring re-opens its gaps and the ribbon reattaches on the model while the checklist reverses, so the rollback is **visible rather than claimed**.

---

**R11 — Rollback itself failed.** *The most serious state in the app, and the only one that asks the user to do something by hand.*
- Headline: **One thing needs your hand**
- Body: **RDMALink took Back, far left out of Thunderbolt Bridge, then couldn't finish — and couldn't put it back either. Nothing is broken, but the port is currently in neither place. Open System Settings, under Network, choose Manage Virtual Interfaces, open Thunderbolt Bridge, and add the port back. Here is exactly how it was.**
- Findings block (always shown, technical names included): **Bridge: Thunderbolt Bridge (bridge0) · Members before: en5, en6, en7, en8 · Members now: en5, en7, en8 · The port to add back: en6 — Back, far left**
- Buttons: **Open Network Settings** (default) · **Copy Details** · **Check Again**
- **Recovery:** the baseline is **kept**; the hub carries the persistent row **"Back, far left needs putting back by hand"** *[Show Me]*; `Check Again` clears it the moment membership is seen again, with **"That's it — Back, far left is back in Thunderbolt Bridge."** The change log entry stays live with its action intact.

---

**R12 — Another app is editing the network.**
- Headline: **Something else has the network open**
- Body: **System Settings, or another app, is editing the network configuration right now. RDMALink won't write over it — two things writing network settings at once is how configurations get mangled. Close that and we'll try again.**
- Buttons: **Check Again** (default) · **Quit System Settings** (shown only when System Settings is the holder) · **Back**
- **Recovery:** the app polls quietly and the refusal clears itself when the lock does.

---

**R13 — This Mac's network settings are managed.** *Blocks the entire configure path.*
- Headline: **This Mac's network settings are managed for you**
- Body: **A configuration profile on this Mac owns the network setup, and it will quietly put back anything RDMALink changes. It'd rather tell you now than have you wonder later why the link keeps vanishing. Whoever manages this Mac can make an exception for Thunderbolt.**
- Buttons: **Show Me the Profile** (default) · **Copy Details for IT** · **Back**
- **Recovery:** none offered, and no override. The refusal re-checks on window focus. Identify, the model, and the port list all keep working, so the app is still a useful map.

---

**R14 — RDMALink can't save its undo note.** *Hard gate. Fires at preflight and again immediately before the first write.*
- Headline: **I can't write down how things are right now**
- Body: **RDMALink's notes live in your Library folder, and it can't save there at the moment — which means it couldn't put things back afterwards. It won't change anything it can't undo.**
- Detail: **2 KB is all it needs. There's 0 bytes free on Macintosh HD.** / **The folder isn't writable.**
- Buttons: **Check Again** (default) · **Show the Notes Folder** · **Copy Details**
- **This is the refusal that protects every other promise in the app, and it comes before the password, not after.**

---

**R15 — There's a bridge here I can't read.** *Blocks review for that port.*
- Headline: **There's a bridge here I can't make sense of**
- Body: **Back, far left belongs to a bridge whose settings RDMALink can't read properly, and a port has to be out of every bridge — even one that isn't switched on — before it can carry RDMA. It won't guess at this. Have a look in Network settings, under Manage Virtual Interfaces, and it'll check again when you're back.**
- Buttons: **Open Network Settings** (default) · **Check Again** · **Copy Details**

---

**R16 — This port already has a setup RDMALink didn't make.** *Blocks selection; distinct from Adopt.*
- Headline: **This port already has a setup RDMALink didn't make**
- Body: **There's a service on Back, far left with a fixed IPv4 address on it. It isn't RDMALink's and it isn't what a link needs, and RDMALink won't quietly rewrite something you or someone else set up on purpose. Remove it in Network settings if it's stale, or pick a different port.**
- Buttons: **Open Network Settings** (default) · **Pick a Different Port** · **Copy Details**

---

**R17 — The arrangement changed while you were reading.**
- Headline: **Something moved**
- Body: **A cable changed while this was on screen, so what you just read isn't true any more. RDMALink stopped before doing anything rather than act on old information.**
- Buttons: **Take Another Look** (default)
- **Recovery:** returns to Choose a port with the previous selection preserved where it is still valid, and the changed port highlighted with a single breath.

---

**R18 — I don't know my way around this version of macOS.** *Blocks the entire configure path.*
- Headline: **I don't know my way around this version of macOS**
- Body: **RDMALink knows how to take a port out of Thunderbolt Bridge on macOS 27.0 through 27.2, and this Mac is on 27.3. Rather than guess with your network settings, it'll stop here.**
- Body, second paragraph: **You can do it by hand in System Settings: under Network, open Manage Virtual Interfaces and remove the port from Thunderbolt Bridge, then set IPv4 to Off and IPv6 to Link-local only on the port's own service. Come back afterwards and RDMALink will recognize it and offer to look after it.**
- Buttons: **Open Network Settings** (default) · **Check for an Update** · **Copy Details**
- **Recovery:** manual configuration, then Adopt. Identify, the model, the port list and the change log all keep working; only the configure path is closed.

---

**R19 — The undo note is missing or unreadable.** *At Restore.*
- Headline: **I can't remember how this looked**
- Body: **The note RDMALink wrote down for Back, far left is missing, and it won't guess at your network settings. You can remove the service in System Settings, under Network, and add the port back to Thunderbolt Bridge yourself.**
- Buttons: **Open Network Settings** (default) · **Copy These Steps** · **Stop Managing This Port**
- **Recovery:** `Stop Managing This Port` clears only RDMALink's own record and touches nothing on the system, and its confirmation says exactly that.

---

**R20 — The bridge doesn't have it back yet.** *At Restore.*
- Headline: **Not quite back yet**
- Body: **The service is gone, but Thunderbolt Bridge isn't listing Back, far left yet. RDMALink has kept your undo note, so nothing is lost and it can try again whenever you like.**
- Steps: **Try Again usually does it: RDMALink waits for the port to settle and writes the membership afresh. If it still isn't back, open System Settings › Network, choose Manage Virtual Interfaces, open Thunderbolt Bridge and add Back, far left yourself.**
- Buttons: **Try Again** (default) · **Open Network Settings** · **Copy These Steps**
- **Recovery:** the baseline is **never** deleted until verification passes. The change log entry keeps its `Restore…` action. The ring on the model stops half-open and stays that way, matching the copy.

---

**R21 — The bridge it came from doesn't exist any more.** *At Restore.*
- Headline: **The bridge it came from doesn't exist any more**
- Body: **Thunderbolt Bridge has been removed since RDMALink set this port up. It can still delete the service it made — that part is squarely its own — but it won't recreate a bridge, because that's a bigger decision than undoing its own work.**
- Buttons: **Remove My Service Only** (default) · **Leave Everything Alone**
- Confirmation: **The service is gone and the port is standalone. RDMALink has kept your note, in case you rebuild that bridge and want the rest put back.**

---

**R22 — RDMA is on, but no RDMA devices appeared.** *Not a block.*
- Headline: **RDMA is on, but no RDMA devices turned up**
- Body: **That usually means this Mac, or this version of macOS, doesn't actually offer RDMA over Thunderbolt. Setting up a port is still harmless and still undoable — it just won't have anything to carry yet.**
- Buttons: **Continue** (default) · **Check Again** · **Copy Details**
- **Recovery:** proceeds, and the hub keeps an honest status row rather than pretending.

---

**R23 — This Mac's Thunderbolt is version 4.** *Read-only mode, not an error.*
- Headline: **Nothing to configure here**
- Body: **This Mac has Thunderbolt 4 ports. RDMA over Thunderbolt needs Thunderbolt 5, so there's nothing for RDMALink to set up. You're welcome to look around — everything you see is real.**
- Buttons: **Quit** only. The set-up button is **absent**, not disabled.
- **Recovery:** the model, the port list, Identify and the change log all still work, so the app remains useful as a map.

---

**R24 — I can't see the Thunderbolt hardware.**
- Headline: **I can't see this Mac's Thunderbolt hardware**
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
- Body: **There's a display in Back, far left and docks in the other three. You can still prepare any of them — or free up the one you want for the link and I'll be ready.**
- Buttons: none; the card watches and clears itself.

---

**R27 — Routing, not refusing.** Two cases never produce a refusal:
- A port **already ready** that is clicked in Choose a port: the row reads **Already ready for RDMA** and offers `Restore…`. Inline line: **This one's already a link. Want to see how it's doing?**
- A port **set up by hand** that is clicked: the app routes silently to Adopt (S9) with the line **This one's already done — and done properly. Let me show you what I found.** **There is no path anywhere in the app that rewrites a service the app did not create.**

---

**R28 — The service RDMALink made isn't the one it made any more.** *At Restore, before anything is deleted.*
- Headline: **This port's service isn't the one RDMALink made any more**
- Body: **The service RDMALink created on Back, far left has been changed since — it's carrying settings RDMALink didn't put there, and it won't quietly delete something you've made your own. Remove it yourself in Network settings if you're done with it, or tell RDMALink to stop looking after this port and it'll leave everything exactly where it is.**
- Detail: the differences, as a list: **IPv4 is Manual, IPv6 is Automatic.**
- Buttons: **Stop Managing…** · **Open Network Settings** · **Leave Everything Alone**
- **Recovery:** RDMALink matches its service by identifier, never by name, so a renamed service is still its own; only a changed configuration is refused. The note is kept.

---

**R29 — There's no Thunderbolt Bridge to return it to.** *At Return to Bridge.* The copy is S10's no-bridge form (headline, body and buttons there). RDMALink never creates a bridge.

---

**R30 — That note only records a return.** *At Restore, reached only from the command line or a stale sheet: the hub never offers Restore for a return record (§7.5).*
- Headline: **Nothing to put back**
- Body: **RDMALink's note for Back, far left only records that it put the port back in Thunderbolt Bridge. There's nothing to undo — Set It Up Again takes the port out of the bridge, and Stop Managing forgets the note.**
- Buttons: **Set It Up Again** (default) · **Stop Managing…** · **Cancel**
- Adopted note (§7.3: an adopted port has no bridge history and nothing to put back): body **RDMALink's note for Back, far left only records that it adopted the port as it found it. There's nothing to undo — Stop Managing forgets the note, and the port keeps its setup.** · buttons **Stop Managing…** (default) · **Cancel**
- **Recovery:** the note is kept; nothing is written.

---

**R31 — I don't recognize this Mac.** *Read-only mode, not an error. Fires when neither rule in §4.7 recognizes the Mac; never on a Mac the identifier catalogue lists.*
- Headline: **I don't recognize this Mac**
- Body: **RDMALink only draws, and only changes, Macs it knows — and this isn't one of them. So there's no picture, and nothing here will be changed. The ports below are listed the way macOS reports them, and everything you see is real.**
- Stage: no model. In its place, centred, an unavailable-content block in the system's own style: symbol `desktopcomputer.trianglebadge.exclamationmark`, title **No picture for this Mac**, description **RDMALink doesn't recognize it, so it won't draw one.** No selector, legend, callout or view buttons.
- Buttons: **Quit** only. Set-up, Restore, Adopt, Return to Bridge and Stop Managing are all **absent**, not disabled — RDMALink writes nothing on a Mac it does not recognize, notes included. Identify is not offered.
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

**Matching is by identifier, never by name.** A service the user renames afterwards is still recognized as RDMALink's; a service the user creates that happens to share RDMALink's name is never mistaken for it. This is stated in the review screen's technical disclosure and in the Restore sheet.

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
- **An adopted port has no exact Restore**, because RDMALink never saw which bridge it came from and will not invent a history it did not witness. It offers **Return to Bridge…** instead (§7.5), which does the ordinary thing rather than the remembered thing, and **Stop Managing**, which removes RDMALink's own record and changes nothing on the system.
- **A near match is never adjusted.** RDMALink did not create that service and will not rewrite it; it shows exactly what differs, hands over the steps, offers `Open Network Settings` and `Copy These Steps`, and keeps watching — adopting the moment the port matches.

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
   S11), the note stays so the row can offer **Set It Up Again**, and the row
   reads **Back in the bridge** (§4.3). A returned note is not one `Restore…`
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
- **Drift is news, not failure.** If a service RDMALink created has disappeared, or the port is back in a bridge, the row reads **"Not set up any more"**, the hub carries **"Back, far left isn't set up any more"** with `Set It Up Again` and `Forget This Port`, and **a stale baseline is never silently reapplied to a world that moved.** A port RDMALink returned to the bridge (§7.5) is not drift: its row reads **Back in the bridge** and nothing is raised.
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
- Custom actions per element: **Select**, **Identify**, **Adopt**, **Restore**, **Stop Managing** — matching whatever the row offers.
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
| Escape | Cancel any sheet, refusal or Identify — always backwards, never forwards |
| ⌘1 ⌘2 ⌘3 ⌘4 | Back / Front / Left / Right |
| ⌘0 / ⇧⌘0 | Fit / Reset View |
| ⌘N | Set Up a Port |
| ⌘I | Identify a Port |
| ⌘T | Show Technical Names |
| ⌘L | Change Log |
| ⌘R | Check Again |
| ⌘C | Copy (address, refusal details, log entry) |
| ⌘, | Settings |

Every default button is `.keyboardShortcut(.defaultAction)` and every cancel is `.cancelAction`. No dialog in the app needs a mouse.

### 8.4 Pointer targets

Every receptacle's hit target is **at least 24 × 24 pt in screen space**, enforced by an invisible proxy collider, and **the camera dolly is floored** so a port can never become un-clickable at any zoom the user can reach. Standard cursors throughout, including `.operationNotAllowed` over USB-only receptacles and `.help` on the address footnote.

### 8.5 Dynamic Type and layout

All text uses system text styles and scales to Accessibility XXL. **Below 900 pt of width, or at the largest text sizes, the layout reflows to a single column**: the stage collapses to a 180 pt strip at the top showing the relevant face, and the port list plus working area take the rest — the same content, the same copy, the same order, never a different app. Nothing is truncated without a tooltip carrying the full string.

**The `fe80::` address wraps at a colon group and is never truncated with an ellipsis.** A half-shown address is worse than a wrapped one.

### 8.6 Motion, contrast, transparency

- **Reduce Motion:** camera arcs become a 100 ms cross-fade between fixed poses with identical narration; the Identify shimmer becomes a static dim ring; the apply ring steps between five static states; the ribbon retraction becomes an opacity change; the address appears rather than fading; the waking-ports beat becomes a simultaneous appearance. **Nothing that carries meaning lives only in motion** — every pulse has a text twin in the panel.
- **Increase Contrast:** every ring track goes 1.5 → 3 pt with a contrasting halo; badges gain a 1 pt border; receptacle interiors gain contrast against the chassis.
- **Reduce Transparency:** both floating stage capsules become opaque.
- **Differentiate Without Color:** the default behavior, not a mode. Every model state is a distinct ring geometry; every panel state is a distinct SF Symbol plus words. No meaning anywhere depends on hue.

### 8.7 Voice Control

Every receptacle carries a speakable name matching its visible label, and every button's accessibility label equals its visible title, so **"click Back far left"** and **"click Set Up Port"** both work.

### 8.8 Cognitive load and safety

One decision per screen. No timers and no countdowns anywhere except the 60-second Identify watch, which is generous, announced in words rather than numbers, repeatable with one click, and harmless to miss. No auto-advancing destructive step. No color-coded urgency. No red alarm surfaces. **No audio and no haptics.** No dialog ever asks a question whose answer isn't visible on the screen behind it. Nothing in the app flashes faster than three times per second, and nothing pulses faster than 1.6 s.

### 8.9 Localization

All copy is localizable with no concatenated sentences. Position names and locator phrases are separate strings so **"second from the left as you look at the back"** can be rewritten per language. Every technical string — the address, the interface name, the diagnostics — is selectable and copyable.

---

## 9. Delight moments

1. **"Let me turn it around."** The panel says it, then the camera arcs 180° over 0.7 s with a small dolly out and back, and the ports you need are facing you. It is the single most useful sentence in the app, and it feels like someone lifting the machine off the desk for you.
2. **The ports wake up.** When the opening probe finishes, the receptacles light in physical order with a 60 ms stagger — one readable beat that says *I found all six* — then complete stillness. Once per launch, never repeated.
3. **The ribbon lets go.** Bridged ports are visibly tied together by a soft arc across the chassis. The instant the first write lands, the ribbon detaches from the chosen port and retracts into the others. A concept nobody enjoys reading about, understood in half a second without a word.
4. **The ring closes as the work gets done.** Four arcs, four gaps; each gap closes as a real step completes, ending as one unbroken accent ring. Progress you can read from across the room, mapped to geometry rather than to a bar, and honest enough that a stall looks like a stall.
5. **The rollback runs backwards.** If something fails, the same ring re-opens its gaps at the same pace and the ribbon springs back while the checklist reverses. Watching a mistake being undone in front of you is more reassuring than any sentence about it.
6. **Identify's moment of silence.** The instant a port is unplugged, every other port's shimmer stops dead and only the one that moved keeps a ring — the app going quiet around the answer. When the cable goes back in, it blooms and the list row selects itself: **"That's the one."**
7. **The light thread.** A port linked to a real Mac grows a short soft thread of light leaving the receptacle in the cable's direction, fading at the frame edge. It is the only ornament in the entire scene, and it appears only when a real link really exists — which is exactly why it feels earned rather than decorative.
8. **Hover-to-preview.** Point at "Leave the Thunderbolt Bridge" on the review screen and the ribbon links to the other members fade away in front of you; point at "Get its own network service" and a small node appears beside the receptacle. You watch each sentence happen before you agree to it.
9. **The address arrives.** `fe80::a2d1:73b4:9e0c:5f16%en6` fades in over 250 ms with a hair of scale, once, and `Copy Address` goes live. After a flow made entirely of plain English, one line of pure technical truth lands as a reward.
10. **"Done. That took 1.8 seconds."** Four ticks land in a little over a second, the ring closing one shade per tick so the checklist and the hardware finish together — and then the app tells you the actual elapsed time. A small, confident brag that makes the whole thing feel light.
11. **Waiting with you.** Finish a port with nothing plugged in and the app doesn't send you away — *"Leave this window open and you'll see it arrive."* — and when the cable goes in, the ring brightens, the thread appears and the address fades in, all in the same 250 ms.
12. **The wordless second Mac.** At the handoff, your machine slides aside and a featureless box fades in beside it: near port lit, far port hollow, one thin line between them. It says *half done* with no text at all, and it never pretends to know anything about that other machine. When the far end finally answers, a pulse travels back along the line and blooms at your port.
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

5. **Terminology and one default.** Three words are load-bearing and worth your ear: **"Restore"** vs **"Put It Back"** (warmer, longer, harder to localize); **"Identify a Port…"** vs **"Find It for Me"** (friendlier, less standard); **"Adopt"** vs **"Look After This Port"**. And one behavioral default: **should `Set Up a Port…` be offered at all when nothing is plugged into any Thunderbolt port?** The spec currently offers it, on the grounds that preparing a port before the cable arrives is legitimate — but it does mean a brand-new user can complete the whole flow and see no address.