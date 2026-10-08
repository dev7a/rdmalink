// The 3D stage behind the page's viewer: the design canvas's src/mac-scene.js, unchanged
// except where a comment says "Site:". viewer.js calls createMacScene once three.js is in.
function createMacScene(T, canvas, opts) {
  'use strict';
  // The RDMALink stage, for the web. Geometry is RDMALinkCore's ReceptacleCatalogue
  // (centimetres), the look is App/Stage. Returns null when WebGL is unavailable.
  opts = opts || {};
  var PI = Math.PI;
  var noop = function () {};
  var onHover = opts.onHover || noop;
  var onCursor = opts.onCursor || noop;
  // onPorts(ports, changed): the Thunderbolt ports of the Mac on show, as
  // [{ id, name, ready }], after every load and toggle; `changed` is the toggled
  // port's hover info, or null. onFail(): the WebGL context was lost for good.
  var onPorts = opts.onPorts || noop;
  var onFail = opts.onFail || noop;
  var reduced = !!opts.reducedMotion;
  // opts.theme: 'dark' (the default) or 'light'; setTheme() switches it in place.

  // ---------- catalogue ----------
  // Faces: back -z, front +z, left -x, right +x. u runs 0..1 across a face from the
  // viewer's left as they look at it; v runs 0..1 up it, above the base band.
  // A row is [kind, face, u, v, position name, ready at start, cable at start].
  var MODELS = {
    // .studioSix: Mac Studio with M3 Ultra or M5 Ultra (Thunderbolt 5 on the front too).
    studio: {
      w: 19.7, h: 9.5, d: 19.7, r: 2.4, bevel: 0.22, band: 1.0, vertical: true,
      rest: { th: PI - 0.55, ph: 0.30 },
      grille: { face: 'back', u0: 0.06, u1: 0.94, v0: 0.40, v1: 0.94 },
      rows: [
        ['tb', 'back', 0.157, 0.20, 'Back, far left', true, true],
        ['tb', 'back', 0.207, 0.20, 'Back, middle left'],
        ['tb', 'back', 0.258, 0.20, 'Back, middle right'],
        ['tb', 'back', 0.309, 0.20, 'Back, far right'],
        ['eth', 'back', 0.38, 0.20], ['power', 'back', 0.508, 0.20],
        ['usba', 'back', 0.616, 0.20], ['usba', 'back', 0.68, 0.20],
        ['hdmi', 'back', 0.77, 0.20], ['jack', 'back', 0.85, 0.20], ['button', 'back', 0.92, 0.20],
        ['tb', 'front', 0.165, 0.20, 'Front, left'],
        ['tb', 'front', 0.24, 0.20, 'Front, right'],
        ['sd', 'front', 0.38, 0.20], ['led', 'front', 0.85, 0.20]
      ]
    },
    // .notebook: MacBook Pro 14-inch with M4 Pro, M4 Max, M5 Pro or M5 Max (the
    // 16-inch has the same three ports).
    mbp: {
      w: 31.26, h: 1.55, d: 22.12, r: 1.0, bevel: 0.22, band: 0, vertical: false,
      lid: { depth: 22.0, thickness: 0.42, open: 104 },
      rest: { th: -PI / 2 + 0.75, ph: 0.32 },
      rows: [
        ['magsafe', 'left', 0.154, 0.5],
        ['tb', 'left', 0.228, 0.5, 'Left side, rear', true, true],
        ['tb', 'left', 0.303, 0.5, 'Left side, front'],
        ['jack', 'left', 0.339, 0.5],
        ['sd', 'right', 0.675, 0.5],
        ['tb', 'right', 0.787, 0.5, 'Right side'],
        ['hdmi', 'right', 0.869, 0.5]
      ]
    },
    // .mini: Mac mini with M4 Pro or M5 Pro. The front two are USB-C that carries
    // USB only.
    mini: {
      w: 12.7, h: 5.0, d: 12.7, r: 1.4, bevel: 0.16, band: 0.7, vertical: true,
      rest: { th: PI - 0.55, ph: 0.34 },
      rows: [
        ['power8', 'back', 0.246, 0.35], ['eth', 'back', 0.418, 0.35], ['hdmi', 'back', 0.57, 0.35],
        ['tb', 'back', 0.684, 0.35, 'Back, left', true, true],
        ['tb', 'back', 0.754, 0.35, 'Back, middle'],
        ['tb', 'back', 0.822, 0.35, 'Back, right'],
        ['usb', 'front', 0.206, 0.35, 'Front, left'],
        ['usb', 'front', 0.325, 0.35, 'Front, right'],
        ['led', 'front', 0.69, 0.35], ['jack', 'front', 0.79, 0.35]
      ]
    }
  };
  // Opening width, height and corner radius (cm), and what a hover calls it.
  var KIND = {
    tb: { dims: [0.95, 0.35, 0.17], label: 'Thunderbolt 5' },
    usb: { dims: [0.95, 0.35, 0.08], label: 'USB-C' },
    usba: { dims: [1.3, 0.6, 0.12], label: 'USB-A' },
    hdmi: { dims: [1.5, 0.55, 0.15], label: 'HDMI' },
    eth: { dims: [1.25, 1.35, 0.2], label: 'Ethernet' },
    power: { dims: [1.9, 1.9, 0.95], label: 'Power' },
    power8: { dims: [1.9, 1.1, 0.5], label: 'Power' },
    jack: { dims: [0.55, 0.55, 0.27], label: 'Headphone jack' },
    sd: { dims: [2.6, 0.22, 0.1], label: 'SDXC card slot' },
    magsafe: { dims: [1.3, 0.42, 0.2], label: 'MagSafe 3' },
    button: { dims: [1.1, 1.1, 0.55], label: 'Power button' },
    led: { dims: [0.28, 0.28, 0.14], label: '' }
  };
  var YAW = { front: 0, right: PI / 2, back: PI, left: -PI / 2 };

  // ---------- renderer ----------
  var renderer;
  try {
    renderer = new T.WebGLRenderer({ canvas: canvas, antialias: true, alpha: false, powerPreference: 'high-performance' });
  } catch (err) {
    return null;
  }
  if (!renderer || !renderer.getContext()) return null;
  // The canvas keeps its WebGL context when the editor re-mounts this view on the
  // same element; three.js assumes a fresh context, so without this the old
  // renderer's leftover GL state blows every lit surface out to white.
  renderer.resetState();
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputEncoding = T.sRGBEncoding;
  renderer.toneMapping = T.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = T.PCFSoftShadowMap;
  // The key light is fixed to the model and only the camera turns, so the shadow
  // is the same every frame: it is redrawn when a Mac loads or the frame is refit.
  renderer.shadowMap.autoUpdate = false;
  renderer.shadowMap.needsUpdate = true;
  // The editor remounts this view and a page can hold several; a context the
  // browser drops stays blank, so say so rather than leave an empty frame.
  // Cancelling the event is what lets the browser restore the context later
  // (viewer.js restarts on webglcontextrestored). three.js's own listener
  // cancels it too, but only while the renderer is alive.
  function contextLost(event) {
    if (event) event.preventDefault();
    if (disposed) return;
    lost = true;
    if (raf) { cancelAnimationFrame(raf); raf = 0; }
    onFail('lost');
  }
  var lost = false;
  canvas.addEventListener('webglcontextlost', contextLost, false);

  var scene = new T.Scene();
  var camera = new T.PerspectiveCamera(30, 16 / 9, 4, 600);
  var owned = []; // textures and render targets to dispose

  function srgb(hex) { return new T.Color(hex).convertSRGBToLinear(); }

  // ---------- appearance ----------
  // As in App/Stage (StagePalette, StageSceneBuilder.makeLights): the aluminium is
  // the same silver in both, "dark mode changes the light, never the metal". The
  // ink turns near-black in light mode, the accent brightens a step in the dark
  // (and in light darkens only as far as 3:1 on the ground needs, see setAccent),
  // the tones round the openings lift a little so a hole still reads as a hole,
  // and the base band is a shadow line that follows the ground.
  //   edge, lift  the backdrop: the page colour at the rim, the lift behind the Mac
  //   room        the environment: [floor, zenith gain, nadir gain, softbox gain]
  //   key, rim    directional light
  //   shadow      the contact shadow's opacity, and its map size: a coarser map in
  //               light mode blurs the edge, which a light ground shows up
  //   bloom       the Ready glow's peak opacity, added in the dark, laid over in light
  var THEMES = {
    dark: {
      edge: 0x16171a, lift: 0x24262b, room: [0.10, 0.22, 0.08, 1],
      key: 1.1, rim: 0.55, shadow: 0.55, shadowMap: 2048,
      ink: 0xf5f5f5, recess: 0x0b0b0c, usbRecess: 0x141416, band: 0x232428, scenery: 0x19191b,
      brighten: true, bloom: 0.55, additive: true
    },
    light: {
      edge: 0xefefec, lift: 0xfbfbf9, room: [0.62, 0.3, 0.22, 1.3],
      key: 1.5, rim: 0.18, shadow: 0.16, shadowMap: 256,
      ink: 0x1c1c1c, recess: 0x141414, usbRecess: 0x1c1c1c, band: 0x6b6b6b, scenery: 0x2b2b2b,
      brighten: false, bloom: 0.32, additive: false
    }
  };
  function themeOf(name) { return name === 'light' ? THEMES.light : THEMES.dark; }
  var look = themeOf(opts.theme);

  // The backdrop and the veil a model swap dips through: one radial lift, drawn
  // straight into the framebuffer so it matches the page's colour exactly.
  var backVert = 'varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }';
  var backFrag = [
    'uniform vec3 uEdge; uniform vec3 uLift; uniform float uAspect; uniform float uOpacity; varying vec2 vUv;',
    'void main() {',
    '  vec2 p = vUv - vec2(0.5, 0.44); p.x *= uAspect;',
    '  float k = smoothstep(0.62, 0.0, length(p));',
    '  gl_FragColor = vec4(mix(uEdge, uLift, k * k), uOpacity);',
    '}'
  ].join('\n');
  function backdropMaterial(opacity) {
    return new T.ShaderMaterial({
      uniforms: {
        uEdge: { value: new T.Color(look.edge) }, uLift: { value: new T.Color(look.lift) },
        uAspect: { value: 16 / 9 }, uOpacity: { value: opacity }
      },
      vertexShader: backVert, fragmentShader: backFrag,
      depthTest: false, depthWrite: false, transparent: opacity < 1
    });
  }
  var quad = new T.PlaneGeometry(2, 2);
  var backdrop = new T.Mesh(quad, backdropMaterial(1));
  backdrop.frustumCulled = false; backdrop.renderOrder = -1000; scene.add(backdrop);
  var veil = new T.Mesh(quad, backdropMaterial(0));
  veil.frustumCulled = false; veil.renderOrder = 1000; veil.visible = false; scene.add(veil);

  // Studio lighting as an environment: a room with three softboxes, so the
  // aluminium reads as metal rather than grey plastic. Dim in the dark; in light
  // mode the room is the bright surround the app's stage has there. Each is built
  // the first time its appearance is shown and kept for a switch back.
  var envs = {};
  function environment() {
    var r = look.room, cacheKey = r.join(':');
    if (envs[cacheKey]) return envs[cacheKey];
    var env = new T.Scene();
    var room = new T.SphereGeometry(60, 32, 16);
    var colors = [];
    var pos = room.attributes.position;
    for (var i = 0; i < pos.count; i++) {
      var y = pos.getY(i) / 60;
      var c = y > 0 ? r[0] + r[1] * y : r[0] + r[2] * y;
      colors.push(c, c, c * 1.04);
    }
    room.setAttribute('color', new T.Float32BufferAttribute(colors, 3));
    env.add(new T.Mesh(room, new T.MeshBasicMaterial({ side: T.BackSide, vertexColors: true })));
    function softbox(w, h, x, y, z, k, tint) {
      k *= r[3];
      var m = new T.Mesh(new T.PlaneGeometry(w, h), new T.MeshBasicMaterial({ color: new T.Color(k, k, k * (tint || 1)), side: T.DoubleSide }));
      m.position.set(x, y, z); m.lookAt(0, 0, 0); env.add(m);
    }
    softbox(36, 18, -22, 34, 18, 3.4);        // key, upper left front
    softbox(6, 40, 34, 12, -18, 2.6, 1.12);   // cool strip, right rear
    softbox(6, 34, -36, 10, -16, 1.5);        // strip, left rear
    softbox(40, 8, 0, 6, 40, 1.3);            // low front fill
    softbox(24, 24, 0, 48, 0, 0.7);           // top
    var pmrem = new T.PMREMGenerator(renderer);
    var rt = pmrem.fromScene(env, 0.02);
    owned.push(rt);
    pmrem.dispose();
    env.traverse(function (o) { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); });
    envs[cacheKey] = rt.texture;
    return rt.texture;
  }

  var key = new T.DirectionalLight(0xffffff, look.key);
  key.castShadow = true;
  key.shadow.mapSize.set(look.shadowMap, look.shadowMap);
  key.shadow.bias = -0.0004;
  key.shadow.normalBias = 0.02;
  scene.add(key); scene.add(key.target);
  var rim = new T.DirectionalLight(0xdfe6ff, look.rim); scene.add(rim); scene.add(rim.target);
  var ground = new T.Mesh(new T.PlaneGeometry(600, 600), new T.ShadowMaterial({ opacity: look.shadow }));
  ground.rotation.x = -PI / 2; ground.receiveShadow = true; scene.add(ground);

  // ---------- materials ----------
  // What follows the appearance (band, recesses, scenery, ink) is coloured by
  // applyTheme(), so a switch recolours these shared materials in place.
  var M = {
    metal: new T.MeshStandardMaterial({ color: srgb(0xc9cacd), metalness: 0.9, roughness: 0.34 }),
    pad: new T.MeshStandardMaterial({ color: srgb(0xc3c4c7), metalness: 0.85, roughness: 0.5 }),
    band: new T.MeshStandardMaterial({ metalness: 0.5, roughness: 0.7 }),
    recess: new T.MeshStandardMaterial({ metalness: 0.1, roughness: 0.9 }),
    usbRecess: new T.MeshStandardMaterial({ metalness: 0.0, roughness: 1.0 }),
    scenery: new T.MeshStandardMaterial({ metalness: 0.15, roughness: 0.85 }),
    pin: new T.MeshStandardMaterial({ color: srgb(0x5a5a5e), metalness: 0.3, roughness: 0.7 }),
    buttonRing: new T.MeshBasicMaterial({ color: srgb(0x3a3a3e), side: T.DoubleSide, toneMapped: false }),
    led: new T.MeshBasicMaterial({ color: srgb(0xf7f7f9), toneMapped: false }),
    stub: new T.MeshStandardMaterial({ color: srgb(0x7d7d82), metalness: 0.2, roughness: 0.6 }),
    well: new T.MeshStandardMaterial({ color: srgb(0x151517), metalness: 0.0, roughness: 0.95 }),
    keys: new T.MeshStandardMaterial({ color: srgb(0x2a2a2d), metalness: 0.0, roughness: 0.9 }),
    bezel: new T.MeshStandardMaterial({ color: srgb(0x060607), metalness: 0.1, roughness: 0.3 }),
    screen: new T.MeshStandardMaterial({ color: srgb(0x0b0c0f), metalness: 0.2, roughness: 0.16 }),
    hidden: new T.MeshBasicMaterial({ visible: false }),
    // Rings are unlit, so a state never reads differently because of the key light.
    // As in App/Stage (StageSceneBuilder, StagePalette): the bridge ring, the inner
    // "a Mac is here" ring and the thread are the ink, grey 0.96 in the dark and
    // 0.11 in light, and only Ready, hover and the bloom take the accent (§4.3/§4.4:
    // tone and geometry, never a colour channel).
    bridge: ringMaterial(0.62),
    inner: ringMaterial(0.9),
    ready: ringMaterial(1),
    hoverTb: ringMaterial(0.5),
    bloom: new T.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false, toneMapped: false }),
    thread: new T.MeshBasicMaterial({ transparent: true, opacity: 0.85, depthWrite: false, toneMapped: false })
  };
  function ringMaterial(opacity) {
    return new T.MeshBasicMaterial({ transparent: true, opacity: opacity, side: T.DoubleSide, depthWrite: false, toneMapped: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 });
  }
  [M.recess, M.usbRecess, M.scenery, M.pin, M.led, M.buttonRing, M.well, M.keys, M.bezel, M.screen, M.pad].forEach(function (m) {
    m.polygonOffset = true; m.polygonOffsetFactor = -1; m.polygonOffsetUnits = -1;
  });

  // The perforation tile: 64 columns by 80 rows of holes at the app's 0.10 cm and
  // 0.08 cm pitch, one 6.4 cm tile that wraps with no seam.
  var TILE = 6.4;
  var dots = (function () {
    var c = document.createElement('canvas'); c.width = 512; c.height = 512;
    var g = c.getContext('2d'); g.fillStyle = '#000'; g.fillRect(0, 0, 512, 512); g.fillStyle = '#fff';
    for (var row = -1; row <= 80; row++) for (var col = -1; col <= 64; col++) {
      var x = col * 8 + (row & 1 ? 4 : 0) + 2, y = row * 6.4 + 3.2;
      g.beginPath(); g.arc(x, y, 2.56, 0, PI * 2); g.fill();
    }
    var t = new T.CanvasTexture(c);
    t.wrapS = t.wrapT = T.RepeatWrapping; t.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
    owned.push(t); return t;
  })();
  M.grille = new T.MeshStandardMaterial({ alphaMap: dots, transparent: true, depthWrite: false, metalness: 0, roughness: 0.9, polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1 });
  var glow = (function () {
    var c = document.createElement('canvas'); c.width = 128; c.height = 128;
    var g = c.getContext('2d'); var grd = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    grd.addColorStop(0, 'rgba(255,255,255,1)'); grd.addColorStop(0.45, 'rgba(255,255,255,0.35)'); grd.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grd; g.fillRect(0, 0, 128, 128);
    var t = new T.CanvasTexture(c); owned.push(t); return t;
  })();
  M.bloom.map = glow;
  var fade = (function () {
    var c = document.createElement('canvas'); c.width = 256; c.height = 4;
    var g = c.getContext('2d'); var grd = g.createLinearGradient(0, 0, 256, 0);
    grd.addColorStop(0, '#fff'); grd.addColorStop(0.3, '#aaa'); grd.addColorStop(0.85, '#000');
    g.fillStyle = grd; g.fillRect(0, 0, 256, 4);
    var t = new T.CanvasTexture(c); owned.push(t); return t;
  })();
  M.thread.alphaMap = fade;

  var accent = '#3d8bff';
  // WCAG luminance of 0-255 sRGB, and the colour stepped toward the ink #1c1d20 until it
  // holds `ratio` on the ground, in the same rounded steps as the DC's renderVals.
  function luminance(c) {
    return c.reduce(function (sum, v, i) {
      var k = v / 255;
      return sum + [0.2126, 0.7152, 0.0722][i] * (k <= 0.03928 ? k / 12.92 : Math.pow((k + 0.055) / 1.055, 2.4));
    }, 0);
  }
  function holding(color, ratio) {
    var edge = new T.Color(look.edge);
    var bg = luminance([edge.r, edge.g, edge.b].map(function (v) { return Math.round(v * 255); })) + 0.05;
    var rgb = [color.r, color.g, color.b].map(function (v) { return Math.round(v * 255); }), dim = rgb;
    for (var t = 0.05; t <= 1 && bg / (luminance(dim) + 0.05) < ratio; t += 0.05) {
      dim = rgb.map(function (v, i) { return Math.round(v * (1 - t) + [28, 29, 32][i] * t); });
    }
    return new T.Color(dim[0] / 255, dim[1] / 255, dim[2] / 255);
  }
  function setAccent(hex) {
    accent = hex || '#3d8bff';
    var base = new T.Color();
    try { base.setStyle(String(accent)); } catch (e) { base.set(0x3d8bff); }
    // The app brightens the accent one step in the dark to hold contrast. In light the
    // ring keeps the accent unless it falls under 3:1 on the ground; then it is darkened
    // toward the ink, 5% at a time, until it holds, as the DC darkens the legend's Ready
    // swatch, so the key and the ring stay one colour (#64d2ff is 1.5:1 as it comes).
    var ring = look.brighten ? base.clone().lerp(new T.Color(0xffffff), 0.18) : holding(base, 3);
    M.hoverTb.color.copy(ring).convertSRGBToLinear();
    M.ready.color.copy(ring).convertSRGBToLinear();
    M.bloom.color.copy(base).convertSRGBToLinear();
    // Each port's bloom is its own copy (its opacity animates), so recolour those too.
    if (mac) mac.features.forEach(function (f) { if (f.bloom) f.bloom.material.color.copy(M.bloom.color); });
    requestFrame();
  }

  // Recolours the scene for 'dark' or 'light' in place: nothing is rebuilt.
  function applyTheme(name) {
    look = themeOf(name);
    [backdrop, veil].forEach(function (b) { b.material.uniforms.uEdge.value.set(look.edge); b.material.uniforms.uLift.value.set(look.lift); });
    scene.environment = environment();
    key.intensity = look.key; rim.intensity = look.rim;
    ground.material.opacity = look.shadow;
    if (key.shadow.mapSize.x !== look.shadowMap) {
      key.shadow.mapSize.set(look.shadowMap, look.shadowMap);
      if (key.shadow.map) { key.shadow.map.dispose(); key.shadow.map = null; }
      renderer.shadowMap.needsUpdate = true;
    }
    M.band.color.copy(srgb(look.band));
    M.recess.color.copy(srgb(look.recess));
    M.grille.color.copy(srgb(look.recess)); // a grille hole is a recess
    M.usbRecess.color.copy(srgb(look.usbRecess));
    M.scenery.color.copy(srgb(look.scenery));
    [M.bridge, M.inner, M.thread].forEach(function (mm) { mm.color.copy(srgb(look.ink)); });
    // Light added to a light ground washes out, so there the glow is laid over.
    var blending = look.additive ? T.AdditiveBlending : T.NormalBlending;
    M.bloom.blending = blending;
    if (mac) mac.features.forEach(function (f) {
      if (!f.bloom) return;
      f.bloom.material.blending = blending;
      if (f.closed === 4 && !ringAnims.some(function (a) { return a.f === f; })) f.bloom.material.opacity = look.bloom;
    });
    setAccent(accent);
  }
  function setTheme(name) {
    if (disposed || lost || themeOf(name) === look) return;
    applyTheme(name);
  }

  // ---------- geometry ----------
  function roundedShape(w, h, r) {
    var s = new T.Shape(); var x = -w / 2, y = -h / 2; r = Math.max(0.001, Math.min(r, w / 2, h / 2));
    s.moveTo(x + r, y); s.lineTo(x + w - r, y); s.absarc(x + w - r, y + r, r, -PI / 2, 0, false);
    s.lineTo(x + w, y + h - r); s.absarc(x + w - r, y + h - r, r, 0, PI / 2, false);
    s.lineTo(x + r, y + h); s.absarc(x + r, y + h - r, r, PI / 2, PI, false);
    s.lineTo(x, y + r); s.absarc(x + r, y + r, r, PI, 1.5 * PI, false);
    return s;
  }
  function flat(w, h, r, mat, seg) { return new T.Mesh(new T.ShapeGeometry(roundedShape(w, h, r), seg || 16), mat); }
  function circle(rad, mat) { return new T.Mesh(new T.CircleGeometry(rad, 32), mat); }

  // A rounded-rectangle footprint w x d with plan radius r, extruded h up from y = 0,
  // its top and bottom edges rounded by `bevel`. Smooth normals all round, so the
  // corners read as turned aluminium rather than facets; the faces stay flat.
  function prism(w, d, r, h, bevel, seg) {
    seg = seg || 14;
    var hw = w / 2, hd = d / 2; r = Math.min(r, hw, hd); bevel = Math.min(bevel, r, h / 2);
    var ring = [], i, j;
    var corners = [[hw - r, hd - r, 0], [-(hw - r), hd - r, PI / 2], [-(hw - r), -(hd - r), PI], [hw - r, -(hd - r), 1.5 * PI]];
    corners.forEach(function (c) {
      for (i = 0; i <= seg; i++) { var a = c[2] + (i / seg) * (PI / 2); ring.push([c[0], c[1], Math.cos(a), Math.sin(a)]); }
    });
    var prof = [], bs = bevel > 0 ? 5 : 0;
    if (bs) {
      for (j = 0; j <= bs; j++) { var t0 = -PI / 2 + (j / bs) * (PI / 2); prof.push([bevel * (Math.cos(t0) - 1), bevel * (1 + Math.sin(t0)), Math.cos(t0), Math.sin(t0)]); }
      for (j = 0; j <= bs; j++) { var t1 = (j / bs) * (PI / 2); prof.push([bevel * (Math.cos(t1) - 1), h - bevel + bevel * Math.sin(t1), Math.cos(t1), Math.sin(t1)]); }
    } else { prof.push([0, 0, 1, 0], [0, h, 1, 0]); }
    var P = [], N = [], I = [];
    function vert(x, y, z, nx, ny, nz) { P.push(x, y, z); N.push(nx, ny, nz); return P.length / 3 - 1; }
    function tri(a, b, c, nx, ny, nz) {
      var ax = P[a * 3], ay = P[a * 3 + 1], az = P[a * 3 + 2];
      var ux = P[b * 3] - ax, uy = P[b * 3 + 1] - ay, uz = P[b * 3 + 2] - az;
      var vx = P[c * 3] - ax, vy = P[c * 3 + 1] - ay, vz = P[c * 3 + 2] - az;
      var cx = uy * vz - uz * vy, cy = uz * vx - ux * vz, cz = ux * vy - uy * vx;
      if (cx * nx + cy * ny + cz * nz >= 0) I.push(a, b, c); else I.push(a, c, b);
    }
    var n = ring.length, rows = [];
    prof.forEach(function (p) {
      var row = [];
      ring.forEach(function (q) { row.push(vert(q[0] + q[2] * (r + p[0]), p[1], q[1] + q[3] * (r + p[0]), q[2] * p[2], p[3], q[3] * p[2])); });
      rows.push(row);
    });
    for (j = 0; j < rows.length - 1; j++) for (i = 0; i < n; i++) {
      var a = rows[j][i], b = rows[j][(i + 1) % n], c = rows[j + 1][(i + 1) % n], e = rows[j + 1][i];
      var q = ring[i]; var nr = prof[j][2];
      tri(a, b, c, q[2] * nr + 0.0001, prof[j][3] + 0.0001, q[3] * nr); tri(a, c, e, q[2] * nr + 0.0001, prof[j][3] + 0.0001, q[3] * nr);
    }
    [[0, -1], [prof.length - 1, 1]].forEach(function (cap) {
      var p = prof[cap[0]]; var ctr = vert(0, p[1], 0, 0, cap[1], 0); var ids = [];
      ring.forEach(function (q) { ids.push(vert(q[0] + q[2] * (r + p[0]), p[1], q[1] + q[3] * (r + p[0]), 0, cap[1], 0)); });
      for (i = 0; i < n; i++) tri(ctr, ids[i], ids[(i + 1) % n], 0, cap[1], 0);
    });
    var g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(P, 3));
    g.setAttribute('normal', new T.Float32BufferAttribute(N, 3));
    g.setIndex(I);
    return g;
  }

  // A flat outline track in the XY plane, facing +z. `closed` is how many of the four
  // gaps (bottom, left, top, right: clockwise from the bottom) have closed; 4 is solid.
  var ringCache = {};
  function ringGeometry(w, h, r, t, closed) {
    var cacheKey = [w, h, r, t, closed].map(function (v) { return v.toFixed(3); }).join(':');
    if (ringCache[cacheKey]) return ringCache[cacheKey];
    var hw = w / 2, hh = h / 2; r = Math.min(r, hw, hh);
    var sx = hw - r, sy = hh - r, q = PI * r / 2;
    // Clockwise from the middle of the bottom edge.
    var segs = [
      { len: sx, f: function (s) { return [-s, -hh, 0, -1]; } },
      { len: q, f: function (s) { var a = -PI / 2 - s / r; return [-sx + r * Math.cos(a), -sy + r * Math.sin(a), Math.cos(a), Math.sin(a)]; } },
      { len: 2 * sy, f: function (s) { return [-hw, -sy + s, -1, 0]; } },
      { len: q, f: function (s) { var a = PI - s / r; return [-sx + r * Math.cos(a), sy + r * Math.sin(a), Math.cos(a), Math.sin(a)]; } },
      { len: 2 * sx, f: function (s) { return [-sx + s, hh, 0, 1]; } },
      { len: q, f: function (s) { var a = PI / 2 - s / r; return [sx + r * Math.cos(a), sy + r * Math.sin(a), Math.cos(a), Math.sin(a)]; } },
      { len: 2 * sy, f: function (s) { return [hw, sy - s, 1, 0]; } },
      { len: q, f: function (s) { var a = -s / r; return [sx + r * Math.cos(a), -sy + r * Math.sin(a), Math.cos(a), Math.sin(a)]; } },
      { len: sx, f: function (s) { return [sx - s, -hh, 0, -1]; } }
    ];
    var per = 0; segs.forEach(function (sg) { per += sg.len; });
    function at(s) {
      s = ((s % per) + per) % per;
      for (var k = 0; k < segs.length; k++) { if (s <= segs[k].len || k === segs.length - 1) return segs[k].f(Math.min(s, segs[k].len)); s -= segs[k].len; }
    }
    // The middles of the bottom, left, top and right sides are exact quarters.
    var mids = [0, per / 4, per / 2, 3 * per / 4];
    var gap = 0.09 * per, open = [];
    for (var k = 0; k < 4; k++) if (k >= closed) open.push(mids[k]);
    var spans = [];
    if (!open.length) spans.push([0, per]);
    else for (k = 0; k < open.length; k++) {
      var a0 = open[k] + gap / 2, a1 = (k + 1 < open.length ? open[k + 1] : open[0] + per) - gap / 2;
      if (a1 > a0) spans.push([a0, a1]);
    }
    var P = [], I = [];
    spans.forEach(function (sp) {
      var steps = Math.max(2, Math.ceil((sp[1] - sp[0]) / per * 120)), base = P.length / 3;
      for (var i = 0; i <= steps; i++) {
        var p = at(sp[0] + (sp[1] - sp[0]) * i / steps);
        P.push(p[0] - p[2] * t / 2, p[1] - p[3] * t / 2, 0, p[0] + p[2] * t / 2, p[1] + p[3] * t / 2, 0);
      }
      for (i = 0; i < steps; i++) { var b = base + i * 2; I.push(b, b + 1, b + 3, b, b + 3, b + 2); }
    });
    var g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(P, 3));
    g.setIndex(I); g.computeVertexNormals();
    ringCache[cacheKey] = g;
    return g;
  }

  function placeOnFace(m, face, u, v) {
    var across = (face === 'back' || face === 'front') ? m.w : m.d;
    var along = (u - 0.5) * across, y = m.band + v * (m.h - m.band);
    if (face === 'back') return new T.Vector3(-along, y, -m.d / 2);
    if (face === 'front') return new T.Vector3(along, y, m.d / 2);
    if (face === 'left') return new T.Vector3(-m.w / 2, y, along);
    return new T.Vector3(m.w / 2, y, -along);
  }

  // The grille strip follows the shell round its corners, like the app's, so it
  // lies on the aluminium for its whole width rather than floating off a plane.
  function grilleGeometry(m, gr) {
    var across = (gr.face === 'back' || gr.face === 'front') ? m.w : m.d;
    var perp = (gr.face === 'back' || gr.face === 'front') ? m.d / 2 : m.w / 2;
    var ha = across / 2, r = Math.min(m.r, ha, perp), a = YAW[gr.face], ca = Math.cos(a), sa = Math.sin(a);
    var y0 = m.band + gr.v0 * (m.h - m.band), y1 = m.band + gr.v1 * (m.h - m.band), off = 0.02;
    var s0 = (gr.u0 - 0.5) * across, s1 = (gr.u1 - 0.5) * across, steps = 96, P = [], U = [], I = [];
    for (var i = 0; i <= steps; i++) {
      var s = s0 + (s1 - s0) * i / steps, x, z, arc, extra = Math.abs(s) - (ha - r);
      if (extra <= 0) { x = s; z = perp + off; arc = s; } else {
        var th = Math.asin(Math.min(extra / r, 1)), sg = s < 0 ? -1 : 1;
        x = sg * (ha - r) + sg * Math.sin(th) * (r + off); z = perp - r + Math.cos(th) * (r + off); arc = sg * (ha - r + r * th);
      }
      var wx = x * ca + z * sa, wz = -x * sa + z * ca;
      P.push(wx, y0, wz, wx, y1, wz); U.push(arc / TILE, y0 / TILE, arc / TILE, y1 / TILE);
      if (i < steps) { var b = i * 2; I.push(b, b + 2, b + 3, b, b + 3, b + 1); }
    }
    var g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(P, 3));
    g.setAttribute('uv', new T.Float32BufferAttribute(U, 2));
    g.setIndex(I); g.computeVertexNormals();
    return g;
  }

  // ---------- building a Mac ----------
  var mac = null;
  function build(keyName) {
    var m = MODELS[keyName];
    var group = new T.Group(), solids = [], proxies = [], features = [];
    function solid(mesh) { mesh.castShadow = true; mesh.userData.solid = true; solids.push(mesh); return mesh; }
    if (!m.lid) {
      var body = solid(new T.Mesh(prism(m.w, m.d, m.r, m.h - m.band, m.bevel), M.metal));
      body.position.y = m.band; group.add(body);
      if (m.band) {
        var inset = 0.55;
        group.add(solid(new T.Mesh(prism(m.w - 2 * inset, m.d - 2 * inset, Math.max(m.r - inset, 0.4), m.band + 0.02, 0.05), M.band)));
      }
      if (m.grille) group.add(new T.Mesh(grilleGeometry(m, m.grille), M.grille));
    } else {
      group.add(solid(new T.Mesh(prism(m.w, m.d, m.r, m.h, m.bevel), M.metal)));
      var top = m.h + 0.012;
      var well = flat(27.4, 11.4, 0.4, M.well); well.rotation.x = -PI / 2; well.position.set(0, top, -m.d / 2 + 1.2 + 5.7); group.add(well);
      var keys = new T.InstancedMesh(new T.PlaneGeometry(1.55, 1.5), M.keys, 70), dummy = new T.Object3D(), n = 0;
      for (var row = 0; row < 5; row++) for (var col = 0; col < 14; col++) {
        dummy.position.set(-12.35 + col * 1.9, top + 0.01, -m.d / 2 + 1.2 + 1.7 + row * 1.9); dummy.rotation.set(-PI / 2, 0, 0); dummy.updateMatrix();
        keys.setMatrixAt(n++, dummy.matrix);
      }
      group.add(keys);
      // Speaker grilles either side of the keys. The app's buildNotebook has none;
      // these come from docs/prototype/stage.html, and a real MacBook Pro has them.
      [-1, 1].forEach(function (sx) {
        var sp = new T.PlaneGeometry(3.6, 11.0); var uv = sp.attributes.uv;
        for (var i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 3.6 / TILE * 1.6, uv.getY(i) * 11 / TILE * 1.6);
        var spk = new T.Mesh(sp, M.grille); spk.rotation.x = -PI / 2; spk.position.set(sx * 13.7, top + 0.004, -m.d / 2 + 1.2 + 5.5); group.add(spk);
      });
      var pad = flat(13.0, 8.2, 0.3, M.pad); pad.rotation.x = -PI / 2; pad.position.set(0, top, m.d / 2 - 0.8 - 4.1); group.add(pad);
      // The lid: hinged at the back edge, opened past upright; the screen is on its
      // inner face, so it faces the person at the keyboard. This differs on purpose
      // from App/Stage/StageSceneBuilder.swift buildNotebook, which puts the bezel and
      // screen at y = thickness + 0.01 facing +y: after the -104 degree hinge that
      // face points backward, so the app draws its screen on the back of the lid.
      var hinge = new T.Group(); hinge.position.set(0, m.h + 0.05, -m.d / 2 + 0.55);
      var L = m.lid;
      var lid = solid(new T.Mesh(prism(m.w, L.depth, m.r, L.thickness, 0.12), M.metal)); lid.position.z = L.depth / 2; hinge.add(lid);
      var bezel = flat(m.w - 0.5, L.depth - 0.7, 0.6, M.bezel); bezel.rotation.x = PI / 2; bezel.position.set(0, -0.012, L.depth / 2 + 0.05); hinge.add(bezel);
      var screen = flat(m.w - 1.4, L.depth - 1.6, 0.35, M.screen); screen.rotation.x = PI / 2; screen.position.set(0, -0.024, L.depth / 2 + 0.05); hinge.add(screen);
      var notch = flat(3.2, 0.9, 0.2, M.bezel); notch.rotation.x = PI / 2; notch.position.set(0, -0.036, L.depth - 0.75 - 0.45); hinge.add(notch);
      hinge.rotation.x = -(PI / 180) * L.open;
      group.add(hinge);
    }

    m.rows.forEach(function (row, idx) {
      var kind = row[0], face = row[1], d = KIND[kind].dims.slice();
      if (m.vertical && (kind === 'tb' || kind === 'usb')) { var tmp = d[0]; d[0] = d[1]; d[1] = tmp; }
      var pw = d[0], ph = d[1], pr = d[2];
      var at = placeOnFace(m, face, row[2], row[3]);
      var g = new T.Group(); g.position.copy(at); g.rotation.y = YAW[face]; group.add(g);
      var f = { id: keyName + ':' + face + '.' + idx, kind: kind, face: face, name: row[4] || '', group: g, pos: at, dims: d, ready: !!row[5] };
      if (kind === 'led') {
        var led = circle(pw / 2, M.led); led.position.z = 0.012; g.add(led);
      } else if (kind === 'button') {
        var br = new T.Mesh(new T.RingGeometry(pw / 2 - 0.08, pw / 2, 40), M.buttonRing); br.position.z = 0.012; g.add(br);
      } else {
        var holeMat = kind === 'tb' ? M.recess : kind === 'usb' ? M.usbRecess : M.scenery;
        var hole = (kind === 'power' || kind === 'jack') ? circle(pw / 2, holeMat) : flat(pw, ph, pr, holeMat, 20);
        hole.position.z = 0.012; g.add(hole);
        var pins = kind === 'power' ? [[-0.45, 0.25, 0.26], [0.45, 0.25, 0.26], [0, -0.35, 0.26]] : kind === 'power8' ? [[-0.45, 0, 0.22], [0.45, 0, 0.22]] : [];
        pins.forEach(function (p) { var pin = circle(p[2], M.pin); pin.position.set(p[0], p[1], 0.02); g.add(pin); });
      }
      if (kind !== 'led') {
        // Every opening can be pointed at for its name, but only Thunderbolt takes a
        // ring: §4.5 says USB-only receptacles never take a ring of any kind, and the
        // app's scenery is never ringed, lit or selected. A site extra is the label.
        var isPort = kind === 'tb' || kind === 'usb';
        var cw = isPort ? Math.max(pw + 0.55, 1.6) : Math.max(pw + 0.4, 1.0), chh = isPort ? Math.max(ph + 0.7, 1.6) : Math.max(ph + 0.4, 1.0);
        var proxy = new T.Mesh(new T.BoxGeometry(cw, chh, 0.5), M.hidden); proxy.position.z = 0.15; proxy.userData.feature = f; g.add(proxy); proxies.push(proxy);
      }
      if (kind === 'tb') {
        var hover = new T.Mesh(ringGeometry(pw + 1.0, ph + 1.0, pr + 0.5, 0.08, 4), M.hoverTb);
        hover.position.z = 0.12; hover.visible = false; g.add(hover); f.hover = hover;
      }
      if (kind === 'tb') {
        f.ringDims = [pw + 0.5, ph + 0.5, pr + 0.25, 0.1];
        f.closed = f.ready ? 4 : 0;
        var ring = new T.Mesh(ringGeometry(f.ringDims[0], f.ringDims[1], f.ringDims[2], f.ringDims[3], f.closed), f.ready ? M.ready : M.bridge);
        ring.position.z = 0.1; g.add(ring); f.ring = ring;
        var bloomMat = M.bloom.clone(); bloomMat.opacity = f.ready ? look.bloom : 0;
        var bloom = new T.Mesh(new T.PlaneGeometry(pw + 2.6, ph + 2.6), bloomMat); bloom.position.z = 0.09; bloom.visible = f.ready; g.add(bloom); f.bloom = bloom;
        if (row[6]) {
          // A cable is in this one: the plug, and a thread of light running off along the desk.
          var stub = new T.Mesh(new T.BoxGeometry(Math.max(pw - 0.16, 0.12), Math.max(ph - 0.16, 0.12), 0.55), M.stub); stub.position.z = 0.29; stub.castShadow = true; g.add(stub);
          // §4.2's inner ring, "a Mac is here": solid ink, hugging the opening.
          var inner = new T.Mesh(ringGeometry(pw + 0.16, ph + 0.16, pr + 0.08, 0.07, 4), M.inner); inner.position.z = 0.1; g.add(inner);
          // Scaled to the machine, so the thread reads the same on a mini as on a notebook.
          // It sweeps away from the resting camera, so it reads as a cable leaving the Mac
          // rather than one pointed at the viewer.
          var y = at.y, span = Math.max(m.w, m.d), len = span * 0.62, lat = m.vertical ? 1 : -1;
          var curve = new T.CatmullRomCurve3([
            new T.Vector3(0, 0, 0.5), new T.Vector3(lat * 0.02 * len, -0.2 * y, 0.14 * len), new T.Vector3(lat * 0.1 * len, -y + 0.35, 0.3 * len),
            new T.Vector3(lat * 0.28 * len, -y + 0.15, 0.5 * len), new T.Vector3(lat * 0.55 * len, -y + 0.15, 0.72 * len)
          ]);
          var thread = new T.Mesh(new T.TubeGeometry(curve, 96, span * 0.0055, 10, false), M.thread); g.add(thread);
        }
      }
      features.push(f);
    });

    // What the camera frames: the box, and on a notebook the standing lid.
    var box = new T.Box3(new T.Vector3(-m.w / 2, 0, -m.d / 2), new T.Vector3(m.w / 2, m.h, m.d / 2));
    if (m.lid) {
      var ang = m.lid.open * PI / 180;
      box.max.y = m.h + 0.05 + m.lid.depth * Math.sin(ang);
      box.min.z = Math.min(box.min.z, -m.d / 2 + 0.55 + m.lid.depth * Math.cos(ang));
    }
    return { key: keyName, model: m, group: group, solids: solids, proxies: proxies, features: features, box: box, pickables: proxies.concat(solids) };
  }

  function disposeObject(root) {
    var geos = new Set(), mats = new Set();
    root.traverse(function (o) {
      if (o.geometry) geos.add(o.geometry);
      if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach(function (mm) { mats.add(mm); });
    });
    var shared = new Set(Object.keys(M).map(function (k) { return M[k]; }));
    var cached = new Set(Object.keys(ringCache).map(function (k) { return ringCache[k]; }));
    geos.forEach(function (g) { if (!cached.has(g)) g.dispose(); });
    mats.forEach(function (mm) { if (!shared.has(mm)) mm.dispose(); });
  }

  // ---------- camera ----------
  var cam = { th: 0, ph: 0.3, base: 60, mul: 1, target: new T.Vector3() };
  var size = { w: 1, h: 1 };
  function fit() {
    if (!mac) return;
    var sphere = mac.box.getBoundingSphere(new T.Sphere());
    var vf = camera.fov * PI / 180, hf = 2 * Math.atan(Math.tan(vf / 2) * camera.aspect);
    cam.base = sphere.radius / Math.sin(Math.min(vf, hf) / 2) * (camera.aspect < 1 ? 1.1 : 1.0);
    cam.target.copy(sphere.center);
    cam.target.y = mac.model.lid ? sphere.center.y * 0.9 : sphere.center.y;
    var R = sphere.radius * 1.4;
    var sc = key.shadow.camera; sc.left = -R; sc.right = R; sc.top = R; sc.bottom = -R; sc.near = 1; sc.far = R * 8; sc.updateProjectionMatrix();
    key.position.set(-18, 32, 14).normalize().multiplyScalar(R * 3).add(cam.target); key.target.position.copy(cam.target);
    rim.position.set(22, 12, -26).normalize().multiplyScalar(R * 3).add(cam.target); rim.target.position.copy(cam.target);
    renderer.shadowMap.needsUpdate = true;
  }
  function placeCamera() {
    var r = cam.base * cam.mul, cp = Math.cos(cam.ph);
    camera.position.set(cam.target.x + r * Math.sin(cam.th) * cp, cam.target.y + r * Math.sin(cam.ph), cam.target.z + r * Math.cos(cam.th) * cp);
    camera.lookAt(cam.target);
  }
  function resize() {
    var w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    if (w === size.w && h === size.h) return;
    size.w = w; size.h = h;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    // A tall frame carries its caption under the machine, so the picture sits a little higher.
    if (w < h * 1.1) camera.setViewOffset(w, h, 0, Math.round(h * 0.06), w, h); else camera.clearViewOffset();
    camera.updateProjectionMatrix();
    backdrop.material.uniforms.uAspect.value = veil.material.uniforms.uAspect.value = w / h;
    fit(); setHover(null); requestFrame();
  }

  // ---------- motion ----------
  var auto = { stopped: reduced, inside: false };
  var tween = null;     // camera re-frame
  var swap = null;      // veil dip between models
  var reveal = null;    // rings waking up, left to right
  var ringAnims = [];
  function ease(k) { return 1 - Math.pow(1 - k, 3); }
  function load(keyName, arriving) {
    if (hovered) setHover(null);
    focused = null; pendingHover = null;
    if (mac) { scene.remove(mac.group); disposeObject(mac.group); }
    mac = build(keyName); scene.add(mac.group); ringAnims = [];
    fit();
    onPorts(portList(), null);
    var rest = mac.model.rest;
    if (arriving && !reduced) {
      cam.th = rest.th - 0.6; cam.ph = rest.ph + 0.06; cam.mul = 1.12;
      tween = { t0: performance.now(), dur: 900, th0: cam.th, ph0: cam.ph, mul0: cam.mul, th1: rest.th, ph1: rest.ph };
      var tbs = mac.features.filter(function (f) { return f.ring; });
      tbs.forEach(function (f) { f.ring.visible = false; f.bloom.visible = false; });
      reveal = { t0: performance.now() + 250, items: tbs };
    } else {
      cam.th = rest.th; cam.ph = rest.ph; cam.mul = 1; tween = null; reveal = null;
    }
  }
  function setModel(keyName) {
    if (!MODELS[keyName]) return;
    if (swap) {
      swap.key = keyName;
      // Picked again while the last pick fades in: dip back out from where the veil is.
      if (swap.phase === 'in' && mac && mac.key !== keyName) {
        swap.phase = 'out'; swap.t0 = performance.now() - veil.material.uniforms.uOpacity.value * 160;
      }
      return;
    }
    if (mac && mac.key === keyName) return;
    setHover(null);
    if (reduced || !mac) { load(keyName, false); requestFrame(); return; }
    swap = { key: keyName, t0: performance.now(), phase: 'out' };
    requestFrame();
  }
  function step(now) {
    var busy = false;
    if (swap) {
      busy = true;
      var k = Math.max(0, Math.min(1, (now - swap.t0) / (swap.phase === 'out' ? 160 : 320)));
      veil.visible = true;
      veil.material.uniforms.uOpacity.value = swap.phase === 'out' ? k : 1 - k;
      if (k >= 1) {
        if (swap.phase === 'out') {
          if (!mac || mac.key !== swap.key) load(swap.key, true);
          swap.phase = 'in'; swap.t0 = now;
        } else if (mac && mac.key !== swap.key) {
          swap.phase = 'out'; swap.t0 = now;
        } else { swap = null; veil.visible = false; }
      }
    }
    if (tween) {
      busy = true;
      var e = ease(Math.max(0, Math.min(1, (now - tween.t0) / tween.dur)));
      var dth = tween.th1 - tween.th0;
      cam.th = tween.th0 + dth * e; cam.ph = tween.ph0 + (tween.ph1 - tween.ph0) * e; cam.mul = tween.mul0 + (1 - tween.mul0) * e;
      if (e >= 1) {
        tween = null;
        if (pendingHover) { var shown = pendingHover; pendingHover = null; setHover(shown, true); }
      }
    }
    if (reveal) {
      busy = true;
      var done = true;
      reveal.items.forEach(function (f, i) {
        var on = now >= reveal.t0 + i * 70;
        f.ring.visible = on; f.bloom.visible = on && f.closed === 4;
        if (!on) done = false;
      });
      if (done) reveal = null;
    }
    if (ringAnims.length) {
      busy = true;
      ringAnims = ringAnims.filter(function (a) {
        var f = a.f, stepsDone = Math.max(0, Math.floor((now - a.t0) / 120));
        var want = a.to > a.from ? Math.min(a.to, a.from + stepsDone) : Math.max(a.to, a.from - stepsDone);
        if (want !== f.closed) setClosed(f, want);
        var target = f.closed === 4 ? look.bloom : 0, bm = f.bloom.material;
        bm.opacity += (target - bm.opacity) * 0.25; f.bloom.visible = bm.opacity > 0.01;
        return !(f.closed === a.to && Math.abs(bm.opacity - target) < 0.01);
      });
    }
    return busy;
  }
  function setClosed(f, n) {
    f.closed = n;
    f.ring.geometry = ringGeometry(f.ringDims[0], f.ringDims[1], f.ringDims[2], f.ringDims[3], n);
    f.ring.material = n === 0 ? M.bridge : M.ready;
  }
  function toggleReady(f) {
    f.ready = !f.ready;
    ringAnims = ringAnims.filter(function (a) { return a.f !== f; });
    var to = f.ready ? 4 : 0;
    if (reduced) { setClosed(f, to); f.bloom.material.opacity = to === 4 ? look.bloom : 0; f.bloom.visible = to === 4; }
    else ringAnims.push({ f: f, from: f.closed, to: to, t0: performance.now() });
    requestFrame();
    onPorts(portList(), info(f));
  }
  function portList() {
    return mac ? mac.features.filter(function (f) { return f.kind === 'tb'; }).map(function (f) { return { id: f.id, name: f.name, ready: !!f.ready }; }) : [];
  }

  // ---------- picking ----------
  var ray = new T.Raycaster(), ndc = new T.Vector2(), tmp = new T.Vector3(), nrm = new T.Vector3();
  function pointerNdc(ev) {
    var rect = canvas.getBoundingClientRect();
    ndc.set(((ev.clientX - rect.left) / rect.width) * 2 - 1, -((ev.clientY - rect.top) / rect.height) * 2 + 1);
    return ndc;
  }
  function pick(ev) {
    if (!mac) return null;
    placeCamera(); camera.updateMatrixWorld(); mac.group.updateMatrixWorld(true);
    var p = pointerNdc(ev);
    ray.setFromCamera(p, camera);
    var hits = ray.intersectObjects(mac.pickables, false), wall = Infinity, i;
    for (i = 0; i < hits.length; i++) if (hits[i].object.userData.solid) { wall = hits[i].distance; break; }
    var best = null, bestD = Infinity;
    for (i = 0; i < hits.length; i++) {
      var f = hits[i].object.userData.feature;
      if (!f || hits[i].distance > wall) continue;
      f.group.getWorldPosition(tmp);
      nrm.set(0, 0, 1).applyQuaternion(f.group.getWorldQuaternion(new T.Quaternion()));
      if (nrm.dot(camera.position.clone().sub(tmp)) <= 0) continue;
      tmp.project(camera);
      var dd = (tmp.x - p.x) * (tmp.x - p.x) * camera.aspect * camera.aspect + (tmp.y - p.y) * (tmp.y - p.y);
      if (dd < bestD) { bestD = dd; best = f; }
    }
    return best;
  }
  var hovered = null;
  function info(f) {
    placeCamera(); camera.updateMatrixWorld();
    f.group.getWorldPosition(tmp); tmp.project(camera);
    var title = KIND[f.kind].label, sub = '';
    if (f.kind === 'tb') { title = f.name + ' · Thunderbolt 5'; sub = f.ready ? 'Ready for RDMA' : 'In Thunderbolt Bridge'; }
    else if (f.kind === 'usb') { title = f.name + ' · USB-C'; sub = 'USB only, not Thunderbolt'; }
    return { id: f.id, kind: f.kind, title: title, sub: sub, ready: !!f.ready, thunderbolt: f.kind === 'tb', x: (tmp.x + 1) / 2 * size.w, y: (1 - tmp.y) / 2 * size.h };
  }
  function setHover(f, force) {
    if (hovered === f && !force) return;
    if (hovered && hovered.hover) hovered.hover.visible = false;
    hovered = f;
    if (f && f.hover) f.hover.visible = true;
    onHover(f ? info(f) : null);
    onCursor(drag && drag.moved > 4 ? 'grabbing' : f && f.kind === 'tb' ? 'pointer' : 'grab');
    requestFrame();
  }

  // ---------- pointer ----------
  var drag = null;
  function pointerDown(ev) {
    if (ev.pointerType === 'mouse' && ev.button !== 0) return;
    try { canvas.setPointerCapture(ev.pointerId); } catch (e) { /* capture is best effort */ }
    drag = { id: ev.pointerId, x: ev.clientX, y: ev.clientY, moved: 0 };
    // Any press ends the idle turn, a tap on touch included; otherwise the port just
    // tapped turns away and its label is left pointing at nothing.
    auto.stopped = true;
  }
  function pointerMove(ev) {
    if (drag && ev.pointerId === drag.id) {
      var dx = ev.clientX - drag.x, dy = ev.clientY - drag.y;
      drag.x = ev.clientX; drag.y = ev.clientY; drag.moved += Math.abs(dx) + Math.abs(dy);
      if (drag.moved > 4) {
        if (!auto.stopped) auto.stopped = true;
        tween = null; pendingHover = null;
        cam.th -= dx * 0.008;
        cam.ph = Math.max(0.04, Math.min(0.85, cam.ph + dy * 0.006));
        if (hovered) setHover(null); else onCursor('grabbing');
        requestFrame();
      }
      return;
    }
    if (ev.pointerType === 'mouse') { auto.inside = true; if (!swap && !tween) setHover(pick(ev)); }
  }
  function pointerUp(ev) {
    if (!drag || ev.pointerId !== drag.id) return;
    var click = drag.moved < 6;
    drag = null;
    try { canvas.releasePointerCapture(ev.pointerId); } catch (e) { /* already released */ }
    if (click && !swap) {
      var f = pick(ev);
      if (f && f.kind === 'tb') toggleReady(f);
      setHover(f, true);
    } else {
      setHover(ev.pointerType === 'mouse' ? pick(ev) : null, true);
    }
  }
  function pointerLeave(ev) {
    if (drag) return;
    if (ev && ev.pointerType && ev.pointerType !== 'mouse') return;
    auto.inside = false; setHover(null); requestFrame();
  }
  function pointerCancel() { drag = null; setHover(null); }
  function keyDown(ev) {
    var turn = ev.key === 'ArrowLeft' ? 0.35 : ev.key === 'ArrowRight' ? -0.35 : 0;
    if (!turn) return;
    if (ev.preventDefault) ev.preventDefault();
    auto.stopped = true; setHover(null); pendingHover = null;
    if (reduced) { cam.th += turn; requestFrame(); return; }
    tween = { t0: performance.now(), dur: 360, th0: cam.th, ph0: cam.ph, mul0: cam.mul, th1: cam.th + turn, ph1: cam.ph };
    requestFrame();
  }

  // ---------- ports by keyboard ----------
  // The page puts a real button in front of each Thunderbolt port; focusing one
  // turns the Mac just far enough to face it and rings it, and pressing it toggles.
  var focused = null, pendingHover = null;
  function findPort(id) {
    if (!mac) return null;
    for (var i = 0; i < mac.features.length; i++) if (mac.features[i].id === id && mac.features[i].kind === 'tb') return mac.features[i];
    return null;
  }
  function wrapAngle(a) { a = (a + PI) % (2 * PI); if (a < 0) a += 2 * PI; return a - PI; }
  function focusPort(id) {
    var f = swap ? null : findPort(id);
    pendingHover = null;
    if (!f) { if (focused && hovered === focused) setHover(null); focused = null; return; }
    focused = f; auto.stopped = true;
    var delta = wrapAngle(cam.th - YAW[f.face]), keep = 0.45;
    if (Math.abs(delta) > 0.8) {
      var th1 = cam.th - delta + (delta > 0 ? keep : -keep);
      if (reduced) { tween = null; cam.th = th1; cam.mul = 1; }
      else {
        setHover(null);
        tween = { t0: performance.now(), dur: 700, th0: cam.th, ph0: cam.ph, mul0: cam.mul, th1: th1, ph1: cam.ph };
        pendingHover = f; requestFrame(); return;
      }
    }
    setHover(f, true);
  }
  function toggle(id) {
    var f = swap ? null : findPort(id);
    if (!f) return;
    if (focused !== f) focusPort(id); // a press without focus first still faces it
    toggleReady(f);
    if (tween) pendingHover = f; else setHover(f, true);
  }

  // ---------- loop ----------
  var raf = 0, last = 0, visible = true, disposed = false;
  function requestFrame() { if (!raf && visible && !disposed && !lost) raf = requestAnimationFrame(frame); }
  function frame(now) {
    raf = 0;
    if (disposed) return;
    var dt = last ? Math.min(0.05, (now - last) / 1000) : 0; last = now;
    var busy = step(now);
    if (!auto.stopped && !auto.inside && !drag && !tween && !swap) {
      cam.th += dt * 0.16; busy = true;
      if (hovered) setHover(null); // a label cannot follow a turning port
    }
    placeCamera();
    renderer.render(scene, camera);
    if (busy) requestFrame(); else last = 0;
  }
  var ro = typeof ResizeObserver !== 'undefined' ? new ResizeObserver(resize) : null;
  if (ro) ro.observe(canvas);
  // Draws only while the canvas is on screen and the tab is showing. (Site: the tab check
  // is new; the canvas copy of this file relied on requestAnimationFrame pausing.)
  var onScreen = true;
  function showing() {
    visible = onScreen && !document.hidden;
    if (visible) requestFrame();
  }
  var io = typeof IntersectionObserver !== 'undefined' ? new IntersectionObserver(function (entries) {
    onScreen = entries[entries.length - 1].isIntersecting;
    showing();
  }) : null;
  if (io) io.observe(canvas);
  document.addEventListener('visibilitychange', showing, false);

  function dispose() {
    if (disposed) return;
    disposed = true;
    if (raf) cancelAnimationFrame(raf);
    if (ro) ro.disconnect();
    if (io) io.disconnect();
    document.removeEventListener('visibilitychange', showing, false);
    if (mac) disposeObject(mac.group);
    Object.keys(ringCache).forEach(function (k) { ringCache[k].dispose(); });
    Object.keys(M).forEach(function (k) { M[k].dispose(); });
    backdrop.material.dispose(); veil.material.dispose(); quad.dispose();
    ground.geometry.dispose(); ground.material.dispose();
    owned.forEach(function (t) { t.dispose(); });
    if (key.shadow.map) key.shadow.map.dispose();
    canvas.removeEventListener('webglcontextlost', contextLost, false);
    renderer.dispose();
    // Hand the context back now rather than at GC, so remounts in the editor and
    // two viewers on one page never pile up to the browser's limit (~16). Only for a
    // canvas that has left the page: a remount that reuses this canvas element gets
    // this same context back from getContext, and a lost one would stay blank.
    setTimeout(function () {
      if (canvas.isConnected || lost) return;
      try { renderer.forceContextLoss(); } catch (e) { /* no WEBGL_lose_context */ }
    }, 0);
  }

  accent = opts.accent;
  applyTheme(opts.theme);
  load(MODELS[opts.model] ? opts.model : 'studio', false);
  resize();
  requestFrame();

  return {
    setModel: setModel,
    setAccent: setAccent,
    setTheme: setTheme,
    resize: function () { size.w = 0; resize(); },
    pointerDown: pointerDown, pointerMove: pointerMove, pointerUp: pointerUp,
    pointerLeave: pointerLeave, pointerCancel: pointerCancel, keyDown: keyDown,
    focusPort: focusPort, toggle: toggle,
    dispose: dispose,
    debug: function () { return { cam: cam, camera: camera, scene: scene, mac: mac, renderer: renderer, auto: auto, look: function () { return look; }, swap: function () { return swap; }, hovered: function () { return hovered; }, project: function (f) { return info(f); }, pose: function (th, ph) { auto.stopped = true; tween = null; cam.th = th; cam.ph = ph; requestFrame(); } }; }
  };
}
