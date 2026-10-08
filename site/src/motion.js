// Motion: the start of the hero's opening, blocks that fade up as they come into view, the How it works
// story, the page's one WebGL check, the keys that page through a pinned sequence, and the reader's
// place when reduced motion is switched.
//
// This file loads in <head> without defer, so html.js is set before the first paint. styles.css hides
// a [data-reveal] block, or a part of the hero, only under html.js, and only without reduced motion, so
// the page without JavaScript (or with reduced motion) shows everything at once. The rest waits for the
// DOM.
// Nothing here moves on scroll: IntersectionObservers set classes, a ResizeObserver hands styles.css a
// few sizes, and CSS does the motion. The one scroll listener (keepPlace) only notes where the reader is.
(function () {
  'use strict';
  var root = document.documentElement;
  root.classList.add('js');
  var IO = 'IntersectionObserver' in window;
  var still = window.matchMedia('(prefers-reduced-motion: reduce)');

  function each(list, fn) { for (var i = 0; i < list.length; i++) fn(list[i], i); }
  function onChange(mq, fn) {
    if (mq.addEventListener) mq.addEventListener('change', fn);
    else if (mq.addListener) mq.addListener(fn);
  }

  // Whether this browser gives the page WebGL. hero.js, why3d.js and viewer.js ask (window.hasWebGL)
  // before they fetch three.js (600 KB), which would only log an error without it. The answer is worked
  // out once, with one throwaway context that is handed back at once (about 4 ms), and kept; with it
  // comes html.gl, under which styles.css lays the hero out around its 3D stage. Where that layout
  // applies the check is made now, before the first paint, so a browser without WebGL never shows the
  // stage's layout first and then moves the page; elsewhere it waits for the first script that asks.
  var gl;
  function hasWebGL() {
    if (gl !== undefined) return gl;
    try {
      var c = document.createElement('canvas');
      var ctx = c.getContext('webgl2') || c.getContext('webgl');
      var lose = ctx && ctx.getExtension('WEBGL_lose_context');
      if (lose) lose.loseContext();
      gl = !!ctx;
    } catch (e) { gl = false; }
    if (gl) root.classList.add('gl');
    return gl;
  }
  window.hasWebGL = hasWebGL;
  if (window.matchMedia('screen and (prefers-reduced-motion: no-preference) and (min-width: 1024px)').matches) hasWebGL();

  // PageDown, PageUp and Space while a sequence is pinned (How it works here, See it in viewer.js): a
  // page at a time would carry the reader past two of its moments at once, so the keys go from one
  // moment to the next instead, and on past the last as usual. A sequence registers a function
  // (window.addStops) that gives the scroll positions of its moments, first to last, or null while it is
  // not pinned. From up to a screen above the first, the next key lands on it; from up to a screen past
  // the last (How it works stays pinned a step longer), PageUp lands on the last.
  var stops = [];
  window.addStops = function (fn) { stops.push(fn); };
  document.addEventListener('keydown', function (e) {
    var space = e.key === ' ';
    var dir = e.key === 'PageDown' || (space && !e.shiftKey) ? 1 : e.key === 'PageUp' || (space && e.shiftKey) ? -1 : 0;
    if (!dir || e.defaultPrevented || e.altKey || e.ctrlKey || e.metaKey || e.isComposing) return;
    // Keys that type, and Space on anything it presses (the viewer's canvas among them), stay theirs.
    var t = e.target;
    var mine = space ? 'a, button, input, select, textarea, summary, [contenteditable], [tabindex]' : 'input, select, textarea, [contenteditable]';
    if (t && t.closest && t.closest(mine)) return;
    var y = window.scrollY;
    for (var i = 0; i < stops.length; i++) {
      var b = stops[i]();
      if (!b || y < b[0] - window.innerHeight || y > b[b.length - 1] + window.innerHeight) continue;
      var to = null;
      b.forEach(function (v) { if (dir > 0 ? to === null && v > y + 2 : v < y - 2) to = v; });
      if (to === null) return;
      e.preventDefault();
      window.scrollTo({ top: to, behavior: still.matches ? 'instant' : 'smooth' });
      return;
    }
  });

  // Switching reduced motion on or off changes the page's height above and around the reader (the hero,
  // the See it sequence), and scroll anchoring cannot hold a pinned stage. The place is noted as the
  // reader scrolls: the first section not yet scrolled past, and how far into it, as a share of its
  // height (or in px while its top is still on screen). After the switch, once every script has laid the
  // page out again, the reader is put back there. The listener is registered now, in <head>, so it runs
  // before the other scripts' and reads the place as it was.
  var place = null;
  onChange(still, function () {
    var was = place;
    if (!was) return;
    requestAnimationFrame(function () {
      var r = was.s.getBoundingClientRect();
      var into = was.px !== null ? was.px : was.f * r.height;
      window.scrollTo({ top: window.scrollY + r.top + into, behavior: 'instant' });
    });
  });
  function keepPlace() {
    var sections = document.querySelectorAll('main > section'), queued = false;
    function note() {
      queued = false;
      for (var i = 0; i < sections.length; i++) {
        var r = sections[i].getBoundingClientRect();
        if (r.bottom <= 0) continue;
        place = { s: sections[i], px: r.top >= 0 ? -r.top : null, f: -r.top / Math.max(1, r.height) };
        return;
      }
    }
    window.addEventListener('scroll', function () {
      if (queued) return;
      queued = true;
      requestAnimationFrame(note);
    }, { passive: true });
    note();
  }

  // [data-reveal] blocks get .is-in once they come into view, and keep it. Blocks that come in
  // together (two cards side by side, a heading and its lead) follow one another 90 ms apart, in
  // page order. A block already above the viewport when the page opens (at #install, say) shows
  // at once. A block already in view as the page opens, with the hero (How it works, right under the
  // hero on a tall screen), comes in after the hero's own parts, the last of which starts at 0.46 s
  // (styles.css, "The hero's opening"); it waits for the opening to start if it has not yet. A block
  // that comes into view later, or once a link into the page has taken the hero off screen, does not
  // wait. Without IntersectionObserver every block shows now.
  var opened = null;   // when the hero's opening started (hero(), below)
  var AFTER_HERO = 550; // ms after it: the next beat after the hero's last part
  function reveal() {
    var blocks = document.querySelectorAll('[data-reveal]');
    if (!IO) { each(blocks, function (el) { el.classList.add('is-in'); }); return; }
    var hero = document.getElementById('top'), waiting = [];
    function show(el, ms) {
      el.style.setProperty('--reveal-delay', ms + 'ms');
      el.classList.add('is-in');
    }
    // How long a block in view as the page opens waits for the hero's parts: -1 until the opening starts.
    function lead() {
      if (!hero || hero.getBoundingClientRect().top < 0) return 0;
      return opened === null ? -1 : Math.max(0, Math.round(opened + AFTER_HERO - performance.now()));
    }
    var first = true;   // the observer's first call: where every block is as the page opens
    var io = new IntersectionObserver(function (entries) {
      var n = 0, wait = first ? lead() : 0;
      first = false;
      entries.forEach(function (e) {
        var above = e.boundingClientRect.bottom < 0;
        if (!e.isIntersecting && !above) return;
        io.unobserve(e.target);
        if (above) show(e.target, 0);
        else if (wait < 0) waiting.push(e.target);
        else show(e.target, wait + Math.min(n++, 4) * 90);
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    each(blocks, function (el) { io.observe(el); });
    document.addEventListener('hero-go', function () {
      waiting.forEach(function (el, i) { show(el, AFTER_HERO + Math.min(i, 4) * 90); });
      waiting = [];
    });
  }

  // How it works. .is-story on the section turns on the pinned layout in styles.css (1024 px and wider,
  // on a landscape screen at least 560 px tall), so the stacked cards stay if anything here is missing.
  // The section's heading and its steps (.how-stage) stay put while the tops of three empty slots, added
  // here, scroll past the middle of the viewport, about a third of a viewport apart. The active step is
  // the one whose slot's top has reached the middle last: step 1 above the story, step 3 below it. It
  // is worked out again only when a slot's top crosses the middle line (each slot runs on well past the
  // section, so no other edge crosses it while the section shows), or when the section comes into view.
  // A ResizeObserver hands styles.css the sizes it cannot know: a title's height (--how-t), the tallest
  // paragraph's (--how-p, the slot the paragraphs share) and the heading's (--how-head), which the
  // screenshot leaves room for. The active paragraph's height (--how-pa) is what the titles after it move
  // down by, and the accent bar beside it is scaled to end with its last line (--how-bar-s). Sizes are
  // read only when one of them changes size, never on scroll. Transitions start once those sizes are in
  // (.is-live), so nothing slides into place as the page opens.
  // The section's scroll-margin-top makes a link to #how land with the stage where it pins, so the whole
  // frame shows and step 1 is active. It comes from the sticky top and the stage's margin above it that
  // styles.css works out, read again when the sizes or the window change.
  function story() {
    var how = document.getElementById('how');
    var stage = how && how.querySelector('.how-stage');
    var steps = stage ? stage.querySelectorAll('.step') : [];
    if (!IO || !('ResizeObserver' in window) || steps.length !== 3) return;
    var head = stage.querySelector('.head');
    var title = steps[0].querySelector('.step-title');
    var paras = [];
    each(steps, function (s) { paras.push(s.querySelector('.step-text p')); });
    if (!head || !title || paras.indexOf(null) >= 0) return;

    var track = document.createElement('div');
    track.className = 'how-track';
    track.setAttribute('aria-hidden', 'true');
    each(steps, function () { track.appendChild(document.createElement('div')); });
    how.appendChild(track);
    var slots = track.children;

    var active = -1, t = 0, inset = 0, heights = [0, 0, 0], tallest = 0;
    function fit() {
      if (active < 0 || !tallest) return;
      how.style.setProperty('--how-pa', heights[active] + 'px');
      how.style.setProperty('--how-bar-s', String((t + heights[active] - inset) / (t + tallest - inset)));
    }

    function update() {
      var mid = window.innerHeight / 2, k = 0;
      each(slots, function (s, i) { if (s.getBoundingClientRect().top <= mid) k = i; });
      if (k === active) return;
      if (active >= 0) steps[active].classList.remove('is-active');
      steps[k].classList.add('is-active');
      how.style.setProperty('--how-k', String(k));
      active = k;
      fit();
    }

    // PageDown and PageUp go from step to step while the stage is pinned (see addStops): to where each
    // slot's top reaches the middle line.
    window.addStops(function () {
      if (getComputedStyle(stage).position !== 'sticky') return null;
      var y = window.scrollY, mid = window.innerHeight / 2;
      return [].map.call(slots, function (s) { return s.getBoundingClientRect().top + y - mid + 1; });
    });

    function land() {
      var cs = getComputedStyle(stage);
      how.style.scrollMarginTop = cs.position === 'sticky'
        ? (parseFloat(cs.top) - parseFloat(getComputedStyle(how).paddingTop) - parseFloat(cs.marginTop)) + 'px' : '';
    }

    var live = false;
    var sizes = new ResizeObserver(function () {
      t = title.offsetHeight;
      // The bar starts below the title's top padding and ends above the paragraph's bottom padding.
      inset = parseFloat(getComputedStyle(title).paddingTop) + parseFloat(getComputedStyle(paras[0]).paddingBottom);
      tallest = 0;
      each(paras, function (p, i) { heights[i] = p.offsetHeight; tallest = Math.max(tallest, heights[i]); });
      how.style.setProperty('--how-t', t + 'px');
      how.style.setProperty('--how-p', tallest + 'px');
      how.style.setProperty('--how-head', head.offsetHeight + 'px');
      fit();
      land();
      if (live) return;
      live = true;
      requestAnimationFrame(function () { how.classList.add('is-live'); });
    });
    each([head, title].concat(paras), function (el) { sizes.observe(el); });
    window.addEventListener('resize', land);

    how.classList.add('is-story');
    update();
    land();
    // A root shrunk to the line across the middle of the viewport.
    var line = new IntersectionObserver(update, { rootMargin: '-50% 0px -50% 0px' });
    each(slots, function (s) { line.observe(s); });
    new IntersectionObserver(update).observe(how);
  }

  // The hero's opening (styles.css, "The hero's opening"; hero.js plays the rest). html.hero-go starts it
  // once the DOM is ready and the headline's font has loaded, so the title never changes face as it rises;
  // it waits 700 ms at most for the font. A page opened in a background tab starts it when the tab first
  // shows, so the opening is seen rather than played to no one. hero.js hears the same moment as the
  // 'hero-go' event on the document, and waits for it before the Mac turns.
  function hero() {
    var root = document.documentElement, font = false, dom = false, started = false;
    function go() {
      if (started || !font || !dom) return;
      if (document.hidden) { document.addEventListener('visibilitychange', go); return; }
      document.removeEventListener('visibilitychange', go);
      started = true;
      opened = performance.now();
      root.classList.add('hero-go');
      document.dispatchEvent(new Event('hero-go'));
    }
    function fontReady() { font = true; go(); }
    setTimeout(fontReady, 700);
    try { document.fonts.load('400 100px "Instrument Serif"').then(fontReady, fontReady); } catch (e) { fontReady(); }
    document.addEventListener('DOMContentLoaded', function () { dom = true; go(); });
  }

  hero();
  document.addEventListener('DOMContentLoaded', function () {
    reveal();
    story();
    keepPlace();
  });
})();
