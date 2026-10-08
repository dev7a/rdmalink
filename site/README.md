# RDMALink website

The source of <https://dev7a.github.io/rdmalink/>: one static page in plain HTML,
CSS and JavaScript. There are no dependencies. The build and the check use only
the Python standard library, and the published page loads nothing from another
origin: the fonts, three.js and the screenshots are served from the site
itself. Links to GitHub and Apple are ordinary links.

## Build, check and preview

From the repository root:

```sh
python3 site/build.py && python3 site/check.py && python3 -m http.server -d site/dist 8000
```

Then open <http://localhost:8000/>.

- `build.py` deletes `site/dist` and copies `site/src` into it. It fills three
  placeholders on the way: the two Why diagrams in `index.html`
  (`<!-- build:why-bridge -->`, `<!-- build:why-rdmalink -->`), their CSS in
  `styles.css` (`/* build:why-css */`), and the version in the hero
  (`<!-- build:version -->`). The version is the newest released heading in
  `CHANGELOG.md` (`## 0.3.8 — 2026-09-29 …`); `## Unreleased` is skipped, and
  the build fails if there is no release. The same input always gives
  byte-identical output.
- `check.py` fails with one line per problem unless the page has its headings,
  every URL in the markup and the CSS is relative and names a file in `dist`,
  nothing loads from another origin, the CSP is the expected one, three.js
  matches its pinned hash, nothing is left over from the design canvas or the
  build, and the page's version is the changelog's. Its docstring has the full
  list.
- The page also works when `site/dist/index.html` is opened as a file. Chrome
  then logs CORS errors for the three font preloads, because a `file://` page
  has no origin; the fonts still load. Use the server above to preview.

`.github/workflows/pages.yml` runs the same build and check on every pull
request that touches the site, and on `main` it publishes `site/dist` to GitHub
Pages. `docs/ARCHITECTURE.md` ("Website") describes the workflow.

## What is where

```
site/
  build.py            src → dist, standard library only
  check.py            the checks above
  tools/why.py        the two animated Why diagrams: markup and CSS
  src/
    index.html        the page, with the build placeholders
    styles.css        every style; dark by default, light under prefers-color-scheme
    motion.js         in <head>: html.js, the WebGL check (html.gl), the cue for the hero's opening, the reveals,
                      the How it works story, the keys that page through a pinned sequence
    site.js           the Why diagrams' Pause buttons
    mac-scene.js      the Macs in three.js (createMacKit, createMacScene), pixelRatio and loadThree
    hero.js           the hero's Mac Studio and the lanes that run into its ports
    why3d.js          the Why diagrams in 3D
    viewer.js         the 3D viewer and the See it sequence: picker, hover label, keyboard, fallback
    assets/
      fonts/          Geist, Geist Mono, Instrument Serif (latin), with their licences
      shots/          screenshots of the app, 2000 × 1433, dark and light
      shots/1000/     the same at 1000 px wide, for srcset
      vendor/         three.js r128, with its MIT licence
      icon-512.png    the app icon; icon-32.png and icon-64.png are the same, smaller
  dist/               the built site (not committed)
```

- **The page.** Top to bottom: the hero, How it works, Why, See it, Then the
  other Mac, What it changes, Macs and Install. The header's links follow the
  same order. The beam, the accent line, closes the hero, right above How it
  works.
- **Layout.** At 1200 px and wider the page is the design's desktop artboard
  (1440 wide, content 1280 max, 80 px gutters); at 480 px and narrower it is
  the phone artboard (390 wide). In between every size runs from its phone
  value to its desktop value through one custom property, `--fluid`, and the
  columns fold at 1199, 1023, 899 and 639 px. The header of `styles.css`
  explains the formula.
- **Theme.** Dark by default; `prefers-color-scheme: light` switches every
  colour, the screenshots (`<picture>` sources) and the 3D scene, live. The
  accent is `#3d8bff`; the colours derived from it are CSS variables with the
  rule that made each one.
- **Motion.** Only `transform` and `opacity` move (and `stroke-dashoffset` for
  the hero's lanes). `motion.js` runs in `<head>`, so `html.js` is set before
  the first paint; styles.css hides what is about to come in only under
  `html.js` and without reduced motion, so the page without JavaScript, or with
  reduced motion, shows everything at once. It starts the hero's opening
  (`html.hero-go`, once the headline's font is in), fades each `[data-reveal]`
  block up as it comes into view (at once if keyboard focus gets there first;
  a block already in view under the hero as the page opens comes in after the
  hero's own parts), and pins How it works on a landscape screen at least
  1024 px wide and 560 px tall: the heading and the three steps stay while the
  scroll steps through them. A
  link to `#how` lands where they pin, with step 1 active and the beam above
  off screen. While How it works or
  See it is pinned, PageDown, PageUp and Space go from one of its moments to
  the next instead of a page at a time. Switching reduced motion on or off
  keeps the reader in the same place in the same section, though the page's
  height changes. Its comments and the ones in styles.css say how.
- **The hero.** From 1024 px the headline is on the left and a Mac Studio
  (`hero.js`) on the right. It turns to its back while the logo's two lanes
  draw in under the headline; they end on two back Thunderbolt ports, which
  leave the bridge as each lane arrives, and a pulse runs along them once; then
  nothing moves and the scene stops drawing. `mac-scene.js` projects the ports
  (`portAt`), so the lanes are built for the layout and the theme in CSS
  pixels; they come in from the window's edge however wide it is. Below
  1024 px there is no 3D Mac: the copy takes the width, and How it works, right
  under the hero, opens on the app's own picture of the Mac. The lanes are then
  a static drawing behind the headline, and three.js is not fetched for the
  hero. Without WebGL or three.js, or with reduced motion, the hero is the plain
  one: the copy, centred, with the static lanes behind the headline; `motion.js`
  checks for WebGL before the first paint (`html.gl`), so a browser without it
  never shows the 3D layout first. A lost context brings the plain hero until
  the browser restores it, and then the Mac comes back as the opening left it.
  The hero has no screenshot; `hub-dark.jpg` is the Open Graph image, and the
  hub shots are also the 3D viewer's fallback picture.
- **The Why diagrams.** `tools/why.py` writes both figures: a desktop and a
  phone variant of each drawing (a container query shows one), the Pause
  button, and the CSS animation. Its docstring explains the 18-second script,
  the broadcast times and the opening frame. Where a figure's drawing is at
  least 360 px wide, `why3d.js` replaces it with two Mac Studios in 3D and their
  cables, reading the script from why.py's drawing so the two cannot drift
  apart; the labels are HTML placed over the scene. The scene is made a step
  a frame, once the hero's opening is over or when the figures come near,
  whichever is first, so it never holds up a scroll. Phones, and the page
  without JavaScript or WebGL, keep the drawing. With reduced motion each
  figure holds one frame and the Pause buttons are hidden; the figures also
  pause while off screen (`site.js`, `why3d.js`).
- **The 3D viewer.** `viewer.js` loads three.js only when the viewer comes near
  the viewport, and the scene draws only while it is on screen and the tab is
  showing. Its idle turn slows to a stop within five seconds. At 1024 × 600
  and larger, with motion and WebGL, See it is a scroll sequence first: the
  viewer and the section's heading stay pinned while the scroll turns the Mac
  Studio from a back three-quarter view to its back
  (the heading fades out as it turns), moves in on its Thunderbolt ports and
  takes them out of the bridge one by one (`steer()` in mac-scene.js), with the
  legend's two lines as captions. Then the MacBook Pro comes in, on its two
  left ports, and turns round its front to its right one; then the Mac mini,
  on its three back ports. Their ports stay in the bridge, and the frame's own
  caption (the Mac, its chips, its ports) sits where the legend's lines were.
  Each Mac takes over from the one before through the scene's veil, at a fixed
  point in the scroll, either way. PageDown and PageUp stop at seven moments.
  The picker stays up as a progress indicator: its pressed segment is the Mac
  on screen, and a click on another one scrolls to that Mac's first stop. The
  sequence hands the viewer back on the Mac mini (picker, drag, hover, click,
  keyboard). Keyboard focus that comes into the viewer, from above or with
  Shift+Tab from below, skips to the end. Without WebGL
  (three.js is then not fetched at all), after a lost context, or without
  JavaScript, the frame shows the hub screenshot and one line of text; a
  context the browser restores brings the 3D view back, and with it the sequence
  (a reader in the section goes to its end). Turning reduced motion
  on or off restarts the scene.
- **three.js and WebGL.** `mac-scene.js` is the design canvas's
  `src/mac-scene.js`, changed only where a comment says "Site:". It is split
  into `createMacKit` (the catalogue, materials, light and `build()`) and
  `createMacScene` (a stage drawn with one kit: the viewer's and the hero's).
  `hasWebGL()` (motion.js) asks the browser once for the page, and
  `loadThree()` makes the one request for three.js, whichever of the hero, the
  Why diagrams and the viewer asks first; if it fails, all three fall back. The
  page holds at most three WebGL contexts: the hero's, the viewer's, and one
  that the two Why figures share (one renderer draws both and copies each
  picture onto its figure's own canvas); the hero hands its context back when
  reduced motion turns it off. Each draws only while it is on screen and the
  tab shows. To keep their share of the GPU's memory down, none asks for the
  high-performance GPU, a canvas draws with at most 2.4 million pixels
  (`pixelRatio()`: only the See it frame is that large, and it draws at about
  1.5× on a Retina screen), and the contact shadow's map is 512 px.
- **Security.** The page carries a Content-Security-Policy meta:
  `script-src 'self'` (so there is no inline script), `connect-src 'none'`, and
  `style-src 'self' 'unsafe-inline'` for the diagrams' inline SVG styles.
  three.js is served from the site, so it has no `integrity` attribute (an SRI
  on a same-origin file adds nothing, and it breaks `file://`); `check.py`
  checks its hash instead.

## Editing

The repository is the source now. The page was ported once from the Claude
Design canvas (`Main.dc.html`, `Mobile.dc.html`, `MacViewer`), which is only a
design reference from here on; change the site here, not there. Where the two
artboards' wording differed, the page uses the desktop artboard's.

- A new release needs no edit: the version comes from `CHANGELOG.md`.
- Screenshots: replace both sizes of a shot, dark and light. The 1000 px copies
  are made with macOS `sips`, at the same JPEG quality (85) as the originals:

  ```sh
  cd site/src/assets/shots
  for f in *.jpg; do sips -s format jpeg -s formatOptions 85 --resampleWidth 1000 "$f" --out "1000/$f"; done
  ```

- Icons: rendered from `App/AppIcon.icon` with Icon Composer's `ictool` (see
  "App icon" in `docs/ARCHITECTURE.md`), then brought down from 16 to 8 bits a
  channel, still in Display P3; `icon-64.png` is the header and footer logo at 2×.

  ```sh
  ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
  for n in 512 64 32; do
    "$ICTOOL" App/AppIcon.icon --export-image --output-file site/src/assets/icon-$n.png \
      --platform macOS --rendition Default --width $n --height $n --scale 1
    sips -s format png --matchTo "/System/Library/ColorSync/Profiles/Display P3.icc" \
      site/src/assets/icon-$n.png --out site/src/assets/icon-$n.png
  done
  ```
- three.js: a new version needs its new SHA-384 in `check.py` (`THREE`,
  `THREE_SRI`) and a check that `mac-scene.js`, `hero.js` and `why3d.js` still
  run on it.

## Assets and licences

| Asset | Source | Licence |
| --- | --- | --- |
| `fonts/geist-latin.woff2`, `fonts/geist-mono-latin.woff2` | Geist and Geist Mono, © 2024 The Geist Project Authors (github.com/vercel/geist-font): the latin subsets Google Fonts serves, variable, 400–600 and 400–500 | SIL Open Font License 1.1: `OFL-Geist.txt`, `OFL-GeistMono.txt` |
| `fonts/instrument-serif-latin.woff2` | Instrument Serif, © 2022 The Instrument Serif Project Authors (github.com/Instrument/instrument-serif): the latin subset Google Fonts serves, 400 | SIL Open Font License 1.1: `OFL-InstrumentSerif.txt` |
| `vendor/three.r128.min.js` | three.js r128, the build `docs/prototype/stage.html` pins (`sha384-CI3ELBVUz9XQO+97x6nwMDPosPR5XvsxW2ua7N1Xeygeh1IxtgqtCkGfQY9WWdHu`) | MIT, © 2010–2021 three.js authors: `vendor/three.LICENSE.txt`, the `LICENSE` of three.js at tag r128 |
| `shots/`, `icon-*.png` | Screenshots and the icon of RDMALink itself | The project's MIT license |

The page uses no characters outside the fonts' latin subsets; `check.py` makes sure of it.
