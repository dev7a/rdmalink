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
    site.js           the Why diagrams' Pause buttons
    viewer.js         the 3D viewer: picker, hover label, keyboard, fallback
    mac-scene.js      the three.js scene the viewer draws (createMacScene)
    assets/
      fonts/          Geist, Geist Mono, Instrument Serif (latin), with their licences
      shots/          screenshots of the app, 2000 × 1433, dark and light
      shots/1000/     the same at 1000 px wide, for srcset
      vendor/         three.js r128, with its MIT licence
      icon-512.png    the app icon; icon-32.png and icon-64.png are the same, smaller
  dist/               the built site (not committed)
```

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
- **The Why diagrams.** `tools/why.py` writes both figures: a desktop and a
  phone variant of each drawing (a container query shows one), the Pause
  button, and the CSS animation. Its docstring explains the 18-second script,
  the broadcast times and the opening frame. The animation is frozen under
  `prefers-reduced-motion`, and the Pause buttons are hidden then; it also
  pauses while the figures are off screen (`site.js`).
- **The 3D viewer.** `viewer.js` loads three.js only when the viewer comes near
  the viewport, and the scene draws only while it is on screen and the tab is
  showing. Without WebGL (three.js is then not fetched at all), after a lost
  context, or without JavaScript, the frame shows the hub screenshot and one
  line of text; a context the browser restores brings the 3D view back.
  Turning reduced motion on or off restarts the scene. `mac-scene.js` is the
  design canvas's `src/mac-scene.js`, changed only where a comment says
  "Site:".
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
  `THREE_SRI`) and a check that `mac-scene.js` still runs on it.

## Assets and licences

| Asset | Source | Licence |
| --- | --- | --- |
| `fonts/geist-latin.woff2`, `fonts/geist-mono-latin.woff2` | Geist and Geist Mono, © 2024 The Geist Project Authors (github.com/vercel/geist-font): the latin subsets Google Fonts serves, variable, 400–600 and 400–500 | SIL Open Font License 1.1: `OFL-Geist.txt`, `OFL-GeistMono.txt` |
| `fonts/instrument-serif-latin.woff2` | Instrument Serif, © 2022 The Instrument Serif Project Authors (github.com/Instrument/instrument-serif): the latin subset Google Fonts serves, 400 | SIL Open Font License 1.1: `OFL-InstrumentSerif.txt` |
| `vendor/three.r128.min.js` | three.js r128, the build `docs/prototype/stage.html` pins (`sha384-CI3ELBVUz9XQO+97x6nwMDPosPR5XvsxW2ua7N1Xeygeh1IxtgqtCkGfQY9WWdHu`) | MIT, © 2010–2021 three.js authors: `vendor/three.LICENSE.txt`, the `LICENSE` of three.js at tag r128 |
| `shots/`, `icon-*.png` | Screenshots and the icon of RDMALink itself | The project's MIT license |

The page uses no characters outside the fonts' latin subsets; `check.py` makes sure of it.
