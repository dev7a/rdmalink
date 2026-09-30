#!/usr/bin/env python3
"""The two animated "Why" diagrams, as HTML fragments and CSS for site/build.py.

Adapted from the design canvas's src/why.py, which spliced the same markup into the artboards.
Here `render()` returns the markup of each figure and the CSS that drives it; build.py puts the
figures where index.html has <!-- build:why-bridge --> and <!-- build:why-rdmalink -->, and the
CSS where styles.css has /* build:why-css */. Run this file on its own to print G per variant.

The motion is CSS (the canvas runtime dropped SMIL, and CSS is what a paused frame and
prefers-reduced-motion both reach): each copy of a broadcast is a dash on a shared path
(pathLength 100) whose stroke-dashoffset is animated on its group and inherited. Both panels run
the same 18 s script, starting at the same moment:

  At each EMIT time Mac A (even k) or Mac B (odd k) sends one broadcast out of both ports. The times are
  deliberately uneven: evenly spaced, the copies going one way and the copies going the other would all
  meet at once, several times a second, and the loop would flicker instead of reading as copies.
  Left, in the bridge: each copy reaches the other Mac, its bridge passes it out of the other port, and it
  keeps going round (LAP s a lap). The count goes up when a copy turns back into the other cable. Twenty
  copies are going round after ten broadcasts; they fade at 16.6-17.4 s and the script starts again.
  Right, out of the bridge: each copy crosses its cable, stops at the other Mac (a ring), and is gone.

Every animation is delayed by -G, so the page opens on the full loop; G is picked per variant, after
the last copy has landed on the right, where no two copies on the left touch. With prefers-reduced-motion,
or after Pause, the animations are paused, which holds that frame.

Each figure carries both variants: "desktop" (the 1440 artboard's geometry) and "mobile" (the phone
artboard's, with thicker strokes and bigger type so it reads at 316 px). A container query on the figure
shows one: the mobile variant below NARROW px of drawing width, the desktop one from there up. Class,
keyframe and path id prefixes are per variant (wd-/wm-) because the geometry, and so the timing, differs.

Colours are the page's CSS variables (styles.css sets them for dark and light): --accent and
--accent-text for the RDMA side, --site-loop for the loop, and the --site-* greys.
"""
import math

T = 18.0          # script length
LAP = 3.0         # one lap of the loop
# Found by a random search (the canvas's review-tmp/emit_search.py) for the widest opening frame in both variants.
EMIT = [0.4, 1.58, 2.82, 4.02, 5.25, 6.55, 7.6, 8.91, 9.95, 11.16]
FADE = (16.6, 17.4)
# Below this drawing width (the figure's content box) the mobile variant is shown. At 480 px the desktop
# variant's smallest labels (12 of 600 units) come out at 9.6 px, the mobile one's biggest count at 40 px.
NARROW = 480

VARIANTS = {
    "desktop": dict(
        p="wd", klass="why-wide", size='width="100%" height="240"', mac_y=(40, 200), cable=(96, 168), r=8,
        port=(10, 24), ring=(18, 32), pill_w=24, pill_pad=26, inset_x=150,
        cable_w=3, body_w=5, gap_w=9, core_w=1.6, glow_w=14, streak=12, ping_r=11,
        mac_font=13, mac_label_x=100, addr_font=12, addr_y=(82, 192),
        num_font=28, num_y=136, lbl_font=12, lbl_y=155, br_font=12, br_y=216,
    ),
    "mobile": dict(
        p="wm", klass="why-narrow", size='width="316" height="126"', mac_y=(30, 210), cable=(84, 180), r=10,
        port=(14, 32), ring=(24, 42), pill_w=34, pill_pad=26, inset_x=150,
        cable_w=4, body_w=7, gap_w=12, core_w=2.2, glow_w=18, streak=16, ping_r=15,
        mac_font=22, mac_label_x=88, addr_font=22, addr_y=(68, 210),
        num_font=50, num_y=138, lbl_font=22, lbl_y=164, br_font=21, br_y=234,
    ),
}
XA, XB = 188, 412  # port centres on Mac A's right edge and Mac B's left edge
MAC_X = ((40, 150), (410, 150))
MONO = "Geist Mono, ui-monospace, monospace"
ACCENT = "var(--accent, #3d8bff)"
ACCENT_TEXT = "var(--accent-text, #3d8bff)"

LEFT_TITLE = "In Thunderbolt Bridge"
RIGHT_TITLE = "With RDMALink"
LEFT_LABEL = ("Animation: two Macs joined by two cables, with both ports on each Mac in the bridge, bridge0. Each "
              "broadcast a Mac sends goes out of both ports, the other Mac's bridge passes it on along the other "
              "cable, and the copies keep going round, twenty of them after ten broadcasts.")
RIGHT_LABEL = ("Animation: the same two Macs, each port out of the bridge as its own interface, en5 and en6, with its "
               "own fe80:: link-local address. Each copy crosses one cable, stops at the other Mac, and nothing "
               "goes round.")
# One line each on desktop, as before, so the page keeps its height.
LEFT_CAPTION = "Both ports are in the bridge, so each Mac passes traffic on to the other cable."
RIGHT_CAPTION = "Each port is out of the bridge with its own address, so nothing gets passed on."


def pct(t):
    return "%.3f%%" % (100 * t / T)


def secs(v):
    return "%.3fs" % v


def fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def build(v):
    p = v["p"]
    y1, y2 = v["cable"]
    r = v["r"]
    xa, xb = XA + r, XB - r
    run, rise, arc = xb - xa, (y2 - y1) - 2 * r, math.pi / 2 * r
    loop_len = 2 * run + 2 * rise + 4 * arc
    speed = loop_len / LAP
    # Clockwise from Mac A's top port; counter-clockwise from Mac A's bottom port. Both start heading right,
    # and Mac B's ports sit half a lap along either path.
    cw = (f"M {xa} {y1} H {xb} A {r} {r} 0 0 1 {XB} {y1 + r} V {y2 - r} A {r} {r} 0 0 1 {xb} {y2} "
          f"H {xa} A {r} {r} 0 0 1 {XA} {y2 - r} V {y1 + r} A {r} {r} 0 0 1 {xa} {y1} Z")
    ccw = (f"M {xa} {y2} H {xb} A {r} {r} 0 0 0 {XB} {y2 - r} V {y1 + r} A {r} {r} 0 0 0 {xb} {y1} "
           f"H {xa} A {r} {r} 0 0 0 {XA} {y1 + r} V {y2 - r} A {r} {r} 0 0 0 {xa} {y2} Z")
    dash = 100 * v["streak"] / loop_len
    hop_dash = 100 * v["streak"] / run
    hop = (1.02 + hop_dash / 100) * run / speed          # head from -1 to 101 + dash, at the loop's speed
    arrive = (1.01 / (1.02 + hop_dash / 100)) * hop      # head reaches the far port

    def start(k):
        return 0.5 if k % 2 else 0.0

    # Copies going the same way never touch, glow included.
    spots = sorted((start(k) - (e - EMIT[0]) / LAP) % 1 for k, e in enumerate(EMIT))
    gaps = [(b - a) for a, b in zip(spots, spots[1:])] + [1 - spots[-1] + spots[0]]
    assert min(gaps) * loop_len > v["streak"] + v["glow_w"], (min(gaps) * loop_len, v)
    # The right-hand copies going the same way never overlap on a cable.
    assert all(EMIT[k + 2] - EMIT[k] > hop for k in range(len(EMIT) - 2))

    # The opening (and reduced-motion) frame: after the last copy has landed on the right, where the
    # copies going opposite ways are furthest apart. Positions are arc lengths along the clockwise path;
    # a counter-clockwise copy at fraction g of its own path sits at s0 - g there.
    s0 = 2 * run + rise + 2 * arc

    def clearance(t):
        spans = []
        for k, e in enumerate(EMIT):
            q = (start(k) + (t - e) / LAP) % 1
            head = q * loop_len
            spans.append(((head - v["streak"]) % loop_len, v["streak"]))   # clockwise: tail behind the head
            spans.append(((s0 - head) % loop_len, v["streak"]))            # counter-clockwise: tail ahead
        best = loop_len
        for i, (a, la) in enumerate(spans):
            for b, lb in spans[i + 1:]:
                d = (b - a) % loop_len
                best = min(best, d - la if d >= la else 0, (loop_len - d) - lb if loop_len - d >= lb else 0)
        return best

    first = EMIT[-1] + arrive + 0.1
    G = max((first + i * 0.005 for i in range(300)), key=clearance)
    assert clearance(G) >= 6, clearance(G)
    assert G + 0.3 < FADE[0]

    fade_a, fade_b = FADE
    css = [
        f".{p}-lap{{animation:{p}Lap {secs(LAP)} linear infinite;animation-delay:var(--d)}}",
        f"@keyframes {p}Lap{{from{{stroke-dashoffset:{fmt(dash + 0.5)}}}to{{stroke-dashoffset:{fmt(dash + 0.5 - 100)}}}}}",
        f".{p}-run{{animation-duration:{secs(T)};animation-timing-function:linear;animation-iteration-count:infinite;animation-delay:{secs(-G)}}}",
        f".{p}-hop{{animation:{p}Hop {secs(T)} linear infinite;animation-delay:var(--d)}}",
        f"@keyframes {p}Hop{{0%{{stroke-dashoffset:{fmt(hop_dash + 1)}}}{pct(hop)},100%{{stroke-dashoffset:-101}}}}",
        f".{p}-ping{{transform-box:fill-box;transform-origin:center;opacity:0;animation:{p}Ping {secs(T)} ease-out infinite;animation-delay:var(--d)}}",
        f"@keyframes {p}Ping{{0%{{opacity:.9;transform:scale(.45)}}{pct(0.7)},100%{{opacity:0;transform:scale(1.7)}}}}",
        # The loop warms up as copies pile on, then everything fades together.
        f"@keyframes {p}Heat{{0%,{pct(EMIT[0] + arrive)}{{opacity:0}}{pct(EMIT[-1] + arrive)},{pct(fade_a)}{{opacity:1}}{pct(fade_b)},100%{{opacity:0}}}}",
    ]
    for k, e in enumerate(EMIT):
        css.append(f"@keyframes {p}On{k}{{0%,{pct(e - 0.001)}{{opacity:0}}{pct(e)},{pct(fade_a)}{{opacity:1}}{pct(fade_b)},100%{{opacity:0}}}}")
        a = e + arrive
        if k + 1 < len(EMIT):
            b = EMIT[k + 1] + arrive
            css.append(f"@keyframes {p}N{k}{{0%,{pct(a - 0.001)}{{opacity:0}}{pct(a)},{pct(b - 0.001)}{{opacity:1}}{pct(b)},100%{{opacity:0}}}}")
        else:
            css.append(f"@keyframes {p}N{k}{{0%,{pct(a - 0.001)}{{opacity:0}}{pct(a)},{pct(fade_a)}{{opacity:1}}{pct(fade_b)},100%{{opacity:0}}}}")
    # "going round" shows from the first turn back until the fade.
    a = EMIT[0] + arrive
    css.append(f"@keyframes {p}Lbl{{0%,{pct(a - 0.001)}{{opacity:0}}{pct(a)},{pct(fade_a)}{{opacity:1}}{pct(fade_b)},100%{{opacity:0}}}}")
    css.append(f"@media (prefers-reduced-motion: reduce){{.{p}-anim *{{animation-play-state:paused!important}}}}")
    css.append(f'[data-paused="true"] .{p}-anim *{{animation-play-state:paused}}')
    # site.js sets data-offscreen while the figures are out of view, so nothing restyles off screen.
    css.append(f'[data-offscreen="true"] .{p}-anim *{{animation-play-state:paused}}')

    my0, my1 = v["mac_y"]
    pw, pad = v["pill_w"], v["pill_pad"]
    pwid, phgt = v["port"]
    rwid, rhgt = v["ring"]
    cy = (my0 + my1) / 2

    def macs():
        out = [f'<rect x="{mx}" y="{my0}" width="{mw}" height="{my1 - my0}" rx="18" style="fill: var(--site-mac, #1f2125); stroke: var(--site-mac-line, #34363c);"></rect>'
               for (mx, mw) in MAC_X]
        for i, name in enumerate(("Mac A", "Mac B")):
            x = v["mac_label_x"] if i == 0 else 600 - v["mac_label_x"]
            out.append(f'<text x="{x}" y="{fmt(cy + v["mac_font"] * 0.36)}" text-anchor="middle" font-family="{MONO}" font-size="{v["mac_font"]}" style="fill: var(--site-muted, #8b8e96);">{name}</text>')
        return out

    def pill(x, heat=False):
        attrs = f'x="{fmt(x - pw / 2)}" y="{y1 - pad}" width="{pw}" height="{y2 - y1 + 2 * pad}" rx="{fmt(pw / 2)}"'
        if heat:
            return f'<rect class="{p}-run" {attrs} fill-opacity="0.22" style="fill: var(--site-loop, #ff9f0a); animation-name: {p}Heat;"></rect>'
        return f'<rect {attrs} stroke-dasharray="4 4" style="fill: var(--site-bridge, rgba(255, 255, 255, 0.05)); stroke: var(--site-bridge-line, #5a5d65);"></rect>'

    def bridge_labels(xs):
        return [f'<text x="{x}" y="{v["br_y"]}" text-anchor="middle" font-family="{MONO}" font-size="{v["br_font"]}" style="fill: var(--site-muted, #8b8e96);">bridge0</text>'
                for x in xs]

    def ports():
        return [f'<rect x="{fmt(x - pwid / 2)}" y="{fmt(y - phgt / 2)}" width="{pwid}" height="{phgt}" rx="3" style="fill: var(--site-port, #0b0c0d); stroke: var(--site-port-line, #6a6d75);"></rect>'
                for x in (XA, XB) for y in (y1, y2)]

    # A copy is four strokes of one shared path: a faint glow, a gap in the panel's colour that cuts it out
    # of the cable under it, the body, and a bright core (dark theme only). The dash offset is animated on
    # the group and inherited; each <use> takes the path from <defs>.
    def packet(ref, paint, delay, klass, dash_len):
        gap = "400" if klass == "hop" else fmt(100 - dash_len)
        return (f'<g class="{p}-{klass}" stroke-dasharray="{fmt(dash_len)} {gap}" style="--d: {secs(delay)}; {paint}">'
                f'<use href="#{p}-{ref}" stroke-width="{v["glow_w"]}" stroke-opacity="0.28"></use>'
                f'<use href="#{p}-{ref}" stroke-width="{v["gap_w"]}" style="stroke: var(--site-panel, #16171a);"></use>'
                f'<use href="#{p}-{ref}" stroke-width="{v["body_w"]}"></use>'
                f'<use href="#{p}-{ref}" stroke-width="{v["core_w"]}" stroke-opacity="0.8" style="stroke: var(--site-spark, #ffffff);"></use>'
                f'</g>')

    def defs(paths):
        return "<defs>" + "".join(f'<path id="{p}-{ref}" d="{d}" pathLength="100"></path>' for ref, d in paths) + "</defs>"

    # Left: in the bridge.
    loop = "stroke: var(--site-loop, #ff9f0a);"
    left = [defs((("cw", cw), ("ccw", ccw)))] + macs()
    left += [pill(XA), pill(XB), pill(XA, True), pill(XB, True)]
    left += [f'<path d="M {XA} {y} H {XB}" stroke-width="{v["cable_w"]}" fill="none" style="{loop}"></path>' for y in (y1, y2)]
    left.append(f'<path class="{p}-run" d="{cw}" stroke-width="{v["glow_w"] + 2}" stroke-opacity="0.2" fill="none" style="{loop} animation-name: {p}Heat;"></path>')
    left.append(f'<path class="{p}-run" d="{cw}" stroke-width="{v["cable_w"]}" stroke-opacity="0.7" fill="none" style="{loop} animation-name: {p}Heat;"></path>')
    for k, e in enumerate(EMIT):
        pair = [packet(ref, loop, e - G - start(k) * LAP, "lap", dash) for ref in ("cw", "ccw")]
        left.append(f'<g class="{p}-run" fill="none" stroke-linecap="round" style="animation-name: {p}On{k};">{"".join(pair)}</g>')
    left += ports()
    left += bridge_labels((XA, XB))
    for k, _ in enumerate(EMIT):
        left.append(f'<text class="{p}-run" x="300" y="{v["num_y"]}" text-anchor="middle" font-family="{MONO}" font-size="{v["num_font"]}" font-weight="500" style="fill: var(--site-loop-text, #ff9f0a); animation-name: {p}N{k};">{2 * (k + 1)}</text>')
    left.append(f'<text class="{p}-run" x="300" y="{v["lbl_y"]}" text-anchor="middle" font-family="{MONO}" font-size="{v["lbl_font"]}" style="fill: var(--site-secondary, #a1a3aa); animation-name: {p}Lbl;">going round</text>')

    # Right: out of the bridge. Each Mac keeps its bridge; the two ports sit outside it.
    accent = f"stroke: {ACCENT};"
    hops = [(f"{a}{i}", f"M {xa} {y} H {xb}" if a == "ab" else f"M {xb} {y} H {xa}")
            for a in ("ab", "ba") for i, y in ((1, y1), (2, y2))]
    right = [defs(hops)] + macs()
    right += [pill(v["inset_x"]), pill(600 - v["inset_x"])]
    for y in (y1, y2):
        right.append(f'<path d="M {XA} {y} H {XB}" stroke-opacity="0.16" stroke-width="{v["glow_w"]}" fill="none" style="{accent}"></path>')
        right.append(f'<path d="M {XA} {y} H {XB}" stroke-width="{v["cable_w"]}" fill="none" style="{accent}"></path>')
    copies = [packet(("ab" if k % 2 == 0 else "ba") + str(i), accent, e - G, "hop", hop_dash)
              for k, e in enumerate(EMIT) for i in (1, 2)]
    right.append('<g fill="none" stroke-linecap="round">' + "".join(copies) + "</g>")
    for x in (XA, XB):
        for y in (y1, y2):
            right.append(f'<rect x="{fmt(x - rwid / 2)}" y="{fmt(y - rhgt / 2)}" width="{rwid}" height="{rhgt}" rx="{fmt(rwid * 0.44)}" stroke-width="2" style="fill: var(--site-panel, #16171a); {accent}"></rect>')
    right += ports()
    for k, e in enumerate(EMIT):
        x = XB if k % 2 == 0 else XA
        for y in (y1, y2):
            right.append(f'<circle class="{p}-ping" cx="{x}" cy="{y}" r="{v["ping_r"]}" fill="none" stroke-width="2" style="--d: {secs(e + arrive - G)}; {accent}"></circle>')
    right += bridge_labels((v["inset_x"], 600 - v["inset_x"]))
    right.append(f'<text x="300" y="{v["num_y"]}" text-anchor="middle" font-family="{MONO}" font-size="{v["num_font"]}" font-weight="500" style="fill: {ACCENT_TEXT};">0</text>')
    right.append(f'<text x="300" y="{v["lbl_y"]}" text-anchor="middle" font-family="{MONO}" font-size="{v["lbl_font"]}" style="fill: var(--site-secondary, #a1a3aa);">going round</text>')
    for y, name in zip(v["addr_y"], ("en5", "en6")):
        right.append(f'<text x="300" y="{y}" text-anchor="middle" font-family="{MONO}" font-size="{v["addr_font"]}" style="fill: var(--site-secondary, #a1a3aa);">fe80::…%{name}</text>')

    return css, left, right, G


# The rules both variants share: which variant shows, and the Pause button (styles.css draws the figure).
COMMON_CSS = [
    ".why-fig{container-type:inline-size}",
    ".why-wide{display:block;width:100%;height:240px}",
    ".why-narrow{display:none;width:100%;height:auto;aspect-ratio:600/240}",
    f"@container (max-width: {NARROW - 0.02}px){{.why-wide{{display:none}}.why-narrow{{display:block}}}}",
    ".why-pause{position:absolute;top:var(--why-pause-inset);right:var(--why-pause-inset);display:flex;align-items:center;gap:6px;"
    "height:28px;padding:0 12px;border-radius:14px;border:1px solid var(--site-panel-line);background:transparent;"
    "color:var(--site-secondary);font-family:inherit;font-size:13px;line-height:1;cursor:pointer}",
    ".why-pause .why-play,[data-paused=\"true\"] .why-pause .why-hold{display:none}",
    "[data-paused=\"true\"] .why-pause .why-play{display:block}",
    ".why-pause:hover{color:var(--site-title)}",
    ".why-pause:focus-visible{outline:2px solid var(--site-focus);outline-offset:2px}",
    ".why-sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}",
    # Frozen under reduced motion (the rule per variant above), so there is nothing for Pause to do.
    "@media (prefers-reduced-motion: reduce){.why-pause{display:none}}",
]

# Hidden until site.js wires it up: without JavaScript it could not pause anything.
BUTTON = ('<button type="button" class="why-pause" hidden>'
          '<svg class="why-hold" width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><rect x="1.5" y="1" width="2.5" height="8" rx="1" fill="currentColor"></rect><rect x="6" y="1" width="2.5" height="8" rx="1" fill="currentColor"></rect></svg>'
          '<svg class="why-play" width="10" height="10" viewBox="0 0 10 10" aria-hidden="true"><path d="M2.5 1.2 L8.8 5 L2.5 8.8 Z" fill="currentColor"></path></svg>'
          '<span class="why-hold">Pause</span><span class="why-play">Play</span><span class="why-sr"> the animations</span>'
          '</button>')


def render():
    """({"why-bridge": figure, "why-rdmalink": figure}, css): the two <figure>s and the CSS they need."""
    css = list(COMMON_CSS)
    svgs = {"left": [], "right": []}
    for v in VARIANTS.values():
        rules, left, right, _ = build(v)
        css += rules
        for side, label, body in (("left", LEFT_LABEL, left), ("right", RIGHT_LABEL, right)):
            svgs[side].append(f'<svg class="{v["p"]}-anim {v["klass"]}" viewBox="0 0 600 240" {v["size"]} role="img" aria-label="{label}">\n'
                              + "\n".join(body) + "\n</svg>")

    def figure(title, side, caption):
        return ('<figure class="why-fig panel">\n'
                f'<div class="why-title">{title}</div>\n'
                + "\n".join(svgs[side]) + "\n"
                + BUTTON + "\n"
                f'<figcaption class="why-caption">{caption}</figcaption>\n'
                '</figure>')

    figures = {
        "why-bridge": figure(LEFT_TITLE, "left", LEFT_CAPTION),
        "why-rdmalink": figure(RIGHT_TITLE, "right", RIGHT_CAPTION),
    }
    return figures, "\n".join(css)


if __name__ == "__main__":
    for name, v in VARIANTS.items():
        print(name, "G =", round(build(v)[3], 3))
