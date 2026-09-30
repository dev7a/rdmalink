#!/usr/bin/env python3
"""Check the built site in site/dist before it is published.

    python3 site/build.py && python3 site/check.py

Exits 1 with one line per problem unless all of these hold:
- dist/index.html exists: lang="en", one <h1>, the section headings in order, no skipped heading level.
- Every src, href, srcset, data, *-src attribute and CSS url() is a relative URL to a file in dist, so
  the site works under /rdmalink/, from localhost and from file://. The exceptions are <a href> to an
  https page, and <link rel="canonical">, which must be the site's own URL. Every #fragment names an id
  on the page.
- Nothing loads from another origin: no absolute or protocol-relative URL on anything but a link, no
  @import, no inline <script>, no absolute URL in the site's own scripts and stylesheet, and the page
  carries the expected Content-Security-Policy. og:image and twitter:image are this site's URL for a
  file in dist.
- assets/vendor/three.r128.min.js has the pinned SRI hash.
- Nothing is left over from the design canvas ({{, /_blob/, x-dc, dc-import) or from the build (a
  placeholder that was not filled).
- The version in the page is the newest release in CHANGELOG.md.
- Ids are unique, aria-labelledby points at one, and every <img> has alt, width and height.
- The page and the site's own scripts use no character outside the fonts' latin subsets (what Google
  Fonts serves as "latin"), so no glyph falls back to another font.
Standard library only.
"""
import base64
import hashlib
import html
import html.parser
import pathlib
import re
import sys
import urllib.parse

SITE = pathlib.Path(__file__).resolve().parent
DIST = SITE / "dist"
sys.dont_write_bytecode = True  # no __pycache__ in the checkout
sys.path.insert(0, str(SITE))
from build import CHANGELOG, release_version  # noqa: E402

CANONICAL = "https://dev7a.github.io/rdmalink/"
THREE = "assets/vendor/three.r128.min.js"
THREE_SRI = "sha384-CI3ELBVUz9XQO+97x6nwMDPosPR5XvsxW2ua7N1Xeygeh1IxtgqtCkGfQY9WWdHu"
CSP = ("default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
       "font-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'")
H1 = "Cable your Macs together without a loop."
H2 = [
    "With Thunderbolt Bridge, a second cable makes a loop.",
    "The Macs it knows, port by port.",
    "Three steps for each cable.",
    "RDMALink only changes the Mac it runs on.",
    "It changes only the ports you choose, and it can undo that.",
    "Works on Macs with Thunderbolt 5.",
    "Install",
]
LEFTOVERS = ["{{", "/_blob/", "x-dc", "dc-import", "<!-- build:", "/* build:"]
TEXT = {".html", ".css", ".js", ".txt", ".svg", ".json", ".md"}
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
CSS_URL = re.compile(r"url\(\s*(['\"]?)(.*?)\1\s*\)")
# The unicode-range of Google Fonts' latin subset, which the three .woff2 files are.
LATIN = [(0x0000, 0x00FF), (0x0131, 0x0131), (0x0152, 0x0153), (0x02BB, 0x02BC), (0x02C6, 0x02C6),
         (0x02DA, 0x02DA), (0x02DC, 0x02DC), (0x0304, 0x0304), (0x0308, 0x0308), (0x0329, 0x0329),
         (0x2000, 0x206F), (0x20AC, 0x20AC), (0x2122, 0x2122), (0x2191, 0x2191), (0x2193, 0x2193),
         (0x2212, 0x2212), (0x2215, 0x2215), (0xFEFF, 0xFEFF), (0xFFFD, 0xFFFD)]

problems = []


def problem(message):
    problems.append(message)


class Page(html.parser.HTMLParser):
    """Every start tag with its attributes and line, the headings' text, and the inline CSS."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.headings = []
        self.heading = None
        self.styles = []
        self.in_style = False
        self.script = None
        self.text = []

    def handle_starttag(self, tag, attrs):
        a = {k: (v if v is not None else "") for k, v in attrs}
        self.tags.append((tag, a, self.getpos()[0]))
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.heading = [int(tag[1]), ""]
        if "style" in a:
            self.styles.append(a["style"])
        if tag == "script":
            self.script = a
        self.in_style = tag == "style"

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if self.heading and tag == "h%d" % self.heading[0]:
            self.headings.append((self.heading[0], " ".join(self.heading[1].split())))
            self.heading = None
        if tag == "script":
            self.script = None
        self.in_style = False

    def handle_data(self, data):
        if self.heading:
            self.heading[1] += data.replace("\xa0", " ")
        if self.in_style:
            self.styles.append(data)
        if self.script is not None and "src" not in self.script and data.strip():
            problem(f"index.html:{self.getpos()[0]}: inline <script>; the CSP allows only files")
        self.text.append(data)


def local_file(base, url, where):
    """`url` must be relative and name a file in dist (resolved from the directory `base`)."""
    if not url or url.startswith("#"):
        return
    if SCHEME.match(url) or url.startswith("//"):
        problem(f"{where}: {url} is not a relative URL; the site loads nothing from another origin")
        return
    if url.startswith("/"):
        problem(f"{where}: {url} is root-relative; it would break under /rdmalink/ and from file://")
        return
    path = urllib.parse.unquote(url.split("#")[0].split("?")[0])
    target = (base / path).resolve()
    if DIST.resolve() not in target.parents or not target.is_file():
        problem(f"{where}: {url} is not a file in dist")


def css_urls(base, css, where):
    if re.search(r"@import\b", css):
        problem(f"{where}: @import")
    for match in CSS_URL.finditer(css):
        local_file(base, match.group(2).strip(), where)


def main():
    index = DIST / "index.html"
    if not index.is_file():
        print(f"check.py: {index} does not exist; run site/build.py first", file=sys.stderr)
        return 1
    source = index.read_text(encoding="utf-8")
    page = Page()
    page.feed(source)
    page.close()
    ids = [a["id"] for _, a, _ in page.tags if "id" in a]
    idset = set(ids)
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        problem(f"index.html: the id '{dup}' is used more than once")

    # The document and its headings.
    html_tag = next((a for t, a, _ in page.tags if t == "html"), {})
    if html_tag.get("lang") != "en":
        problem('index.html: <html> should have lang="en"')
    h1 = [text for level, text in page.headings if level == 1]
    if h1 != [H1]:
        problem(f"index.html: expected one <h1> '{H1}', found {h1}")
    h2 = [text for level, text in page.headings if level == 2]
    if h2 != H2:
        problem(f"index.html: expected the <h2>s {H2}, found {h2}")
    level = 0
    for this, text in page.headings:
        if this > level + 1:
            problem(f"index.html: the heading '{text}' skips from h{level} to h{this}")
        level = this

    # URLs in the markup.
    metas = {}
    urls = 0
    for tag, a, line in page.tags:
        where = f"index.html:{line} <{tag}>"
        if tag == "meta":
            key = a.get("property") or a.get("name") or a.get("http-equiv", "").lower()
            metas.setdefault(key, []).append(a.get("content", ""))
        if tag == "script" and "src" not in a:
            continue
        if tag == "img":
            for attr in ("alt", "width", "height"):
                if attr not in a:
                    problem(f"{where}: no {attr}")
        for ref in a.get("aria-labelledby", "").split():
            if ref not in idset:
                problem(f"{where}: aria-labelledby '{ref}' is not an id on the page")
        for attr, value in a.items():
            if attr in ("src", "href", "data", "poster", "xlink:href") or attr.endswith("-src"):
                urls += 1
                if value.startswith("#"):
                    if value[1:] not in idset:
                        problem(f"{where}: {attr}={value} names no id on the page")
                elif tag == "a" and value.startswith("https://"):
                    pass  # a link out, not a load
                elif tag == "link" and "canonical" in a.get("rel", "").split():
                    if value != CANONICAL:
                        problem(f"{where}: canonical is {value}, expected {CANONICAL}")
                else:
                    local_file(DIST, value, where)
            elif attr == "srcset":
                for candidate in value.split(","):
                    urls += 1
                    local_file(DIST, candidate.split()[0] if candidate.split() else "", where)
    for style in page.styles:
        css_urls(DIST, style, "index.html inline style")

    # What the head promises.
    if metas.get("content-security-policy") != [CSP]:
        problem(f"index.html: the Content-Security-Policy meta should be exactly: {CSP}")
    if metas.get("og:url") != [CANONICAL]:
        problem(f"index.html: og:url should be {CANONICAL}")
    for key in ("og:image", "twitter:image"):
        values = metas.get(key, [])
        if len(values) != 1 or not values[0].startswith(CANONICAL):
            problem(f"index.html: {key} should be one absolute URL under {CANONICAL}")
        else:
            local_file(DIST, values[0][len(CANONICAL):], f"index.html {key}")

    # Every file: CSS, leftovers, the site's own scripts.
    files = sorted(p for p in DIST.rglob("*") if p.is_file())
    for path in files:
        rel = path.relative_to(DIST).as_posix()
        if path.suffix not in TEXT:
            continue
        text = path.read_text(encoding="utf-8")
        for leftover in LEFTOVERS:
            if leftover in text:
                line = text[:text.index(leftover)].count("\n") + 1
                problem(f"{rel}:{line}: '{leftover}' is left over from the canvas or the build")
        if path.suffix == ".css":
            css_urls(path.parent, text, rel)
        if path.suffix in (".html", ".js") and not rel.startswith("assets/vendor/"):
            for char in sorted(set(html.unescape(text))):
                if not any(low <= ord(char) <= high for low, high in LATIN):
                    problem(f"{rel}: U+{ord(char):04X} {char!r} is outside the fonts' latin subsets")
        if path.suffix in (".js", ".css") and not rel.startswith("assets/vendor/"):
            # CSS too: url() is checked above, but image-set("https://...") and the like are not url().
            for match in re.finditer(r"https?://[^\s'\"`)]+|['\"`(]//[a-zA-Z0-9]", text):
                line = text[:match.start()].count("\n") + 1
                problem(f"{rel}:{line}: {match.group(0)}: the site's scripts and styles load nothing from another origin")

    # three.js is the file the SRI pins.
    three = DIST / THREE
    if not three.is_file():
        problem(f"{THREE} is missing")
    else:
        digest = "sha384-" + base64.b64encode(hashlib.sha384(three.read_bytes()).digest()).decode()
        if digest != THREE_SRI:
            problem(f"{THREE} is {digest}, not the pinned {THREE_SRI}")

    # The version.
    expected = release_version(CHANGELOG.read_text(encoding="utf-8"))
    stamped = re.findall(r"Version (\d+\.\d+\.\d+)", " ".join(page.text))
    if stamped != [expected]:
        problem(f"index.html: the page says Version {stamped or 'nothing'}, CHANGELOG.md's newest release is {expected}")

    if problems:
        for message in problems:
            print("check.py: " + message, file=sys.stderr)
        print(f"check.py: {len(problems)} problem(s)", file=sys.stderr)
        return 1
    print(f"check.py: OK: {len(files)} files, {urls} URLs, three.js SRI, version {expected}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
