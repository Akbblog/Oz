// Landing-page globe. The Earth, its glow and the country markers are drawn
// by COBE (vendor/cobe.esm.js, MIT, loaded on demand). The moving arcs are
// drawn here, on a 2D layer above it, using the same projection as COBE so
// they stay glued to the globe while it turns.
//
//   const globe = await window.ilGlobe.mount(hostElement, {
//     markers: [{ key: 'USA', lat: 39.5, lng: -98.5 }, ...],
//   });                         // resolves to null when WebGL is unavailable
//   globe.anchor(nx, ny);       // where the results card is (0..1 of the host)
//   globe.pulse('USA');         // a lead leaves that country for the card
//   globe.link('USA', 'India'); // a comet travels between two countries
//   globe.hover(nx, ny); globe.leave();
//   globe.dragStart(); globe.drag(dxPixels); globe.dragEnd(pixelsPerSecond);
//   globe.destroy();
//
// The host element ignores pointer events on purpose: the app listens for
// them, so the mouse wheel keeps scrolling the page over the globe.
(function () {
  'use strict';

  var LIB = 'vendor/cobe.esm.js';
  var libPromise = null;

  function loadLib() {
    if (!libPromise) {
      var url = new URL(LIB, document.baseURI).href;
      libPromise = import(url).then(function (m) { return m.default; });
    }
    return libPromise;
  }

  function hasWebGL() {
    try {
      var c = document.createElement('canvas');
      return !!(c.getContext('webgl2') || c.getContext('webgl') || c.getContext('experimental-webgl'));
    } catch (e) {
      return false;
    }
  }

  // Longitude/latitude the globe should face -> COBE angles.
  function facing(lat, lng) {
    return {
      phi: Math.PI - ((lng * Math.PI) / 180 - Math.PI / 2),
      theta: (lat * Math.PI) / 180,
    };
  }

  // Same unit vector COBE uses for a location.
  function unit(lat, lng) {
    var r = (lat * Math.PI) / 180;
    var a = (lng * Math.PI) / 180 - Math.PI;
    var o = Math.cos(r);
    return [-o * Math.cos(a), Math.sin(r), o * Math.sin(a)];
  }

  var R = 0.8;                       // COBE's globe radius in clip space
  var WARM = [0.98, 0.74, 0.32];
  var TEAL = '108,196,214';
  var VIOLET = '160,140,255';
  var GOLD = '250,190,84';

  function easeInOut(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
  function clamp01(t) { return t < 0 ? 0 : t > 1 ? 1 : t; }

  async function mount(host, options) {
    if (!host || !hasWebGL()) return null;
    var createGlobe;
    try {
      createGlobe = await loadLib();
    } catch (e) {
      return null;
    }

    var markers = ((options && options.markers) || []).map(function (m) {
      return { key: m.key, lat: m.lat, lng: m.lng, v: unit(m.lat, m.lng) };
    });
    var byKey = {};
    markers.forEach(function (m) { byKey[m.key] = m; });

    host.style.position = 'relative';
    host.style.pointerEvents = 'none';
    host.style.overflow = 'visible';
    var layerCss = 'position:absolute;inset:0;width:100%;height:100%;opacity:0;transition:opacity 900ms ease;';
    var canvas = document.createElement('canvas');
    canvas.style.cssText = layerCss + 'contain:layout paint size;';
    host.appendChild(canvas);
    var overlay = document.createElement('canvas');
    overlay.style.cssText = layerCss;
    host.appendChild(overlay);
    var ctx = overlay.getContext('2d');

    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var size = Math.max(120, Math.round(host.clientWidth || 480));

    var start = facing(20, 62); // Middle East / South Asia first
    var phi = start.phi;
    var spin = 0;            // leftover speed from a drag (radians / second)
    var dragging = false;
    var lean = 0, leanTarget = 0;
    var nod = 0, nodTarget = 0;
    var pulses = {};         // key -> time it was lit
    var flights = [];        // comets between countries
    var leads = [];          // comets from a country to the card
    var ripples = [];        // { v | (x,y), born, rgb }
    var anchor = { x: 0.62, y: 0.68 };
    var destroyed = false;
    var raf = 0;
    var last = performance.now();
    var visible = true;

    var globe;
    try {
      globe = createGlobe(canvas, {
        devicePixelRatio: dpr,
        width: size,
        height: size,
        phi: phi,
        theta: 0.3,
        dark: 1,
        diffuse: 1.25,
        scale: 1,
        mapSamples: 20000,
        mapBrightness: 5.2,
        mapBaseBrightness: 0.04,
        baseColor: [0.36, 0.72, 0.82],
        markerColor: WARM,
        glowColor: [0.16, 0.42, 0.50],
        offset: [0, 0],
        opacity: 0.92,
        markers: [],
        arcs: [],
        markerElevation: 0.02,
      });
    } catch (e) {
      host.removeChild(canvas);
      host.removeChild(overlay);
      return null;
    }

    function fitOverlay() {
      overlay.width = Math.round(size * dpr);
      overlay.height = Math.round(size * dpr);
    }
    fitOverlay();

    var io = null;
    if ('IntersectionObserver' in window) {
      io = new IntersectionObserver(function (entries) {
        visible = entries[0].isIntersecting;
        if (visible && !raf && !destroyed) {
          last = performance.now();
          raf = requestAnimationFrame(frame);
        }
      });
      io.observe(host);
    }
    var ro = null;
    if ('ResizeObserver' in window) {
      ro = new ResizeObserver(function () {
        var s = Math.max(120, Math.round(host.clientWidth || size));
        if (s !== size) { size = s; fitOverlay(); }
      });
      ro.observe(host);
    }

    // ---- projection (identical to COBE's) --------------------------------
    var cp = 1, sp = 0, ct = 1, st = 0;
    var out = [0, 0, 0, true]; // x px, y px, depth, in front of / outside the disc
    function project(v, radius) {
      var x = v[0] * radius, y = v[1] * radius, z = v[2] * radius;
      var c = cp * x + sp * z;
      var s = sp * st * x + ct * y - cp * st * z;
      var d = -sp * ct * x + st * y + cp * ct * z;
      out[0] = ((c + 1) / 2) * size;
      out[1] = ((-s + 1) / 2) * size;
      out[2] = d;
      out[3] = d >= 0 || c * c + s * s >= R * R;
      return out;
    }

    // Point on the lifted great-circle path between two unit vectors.
    var tmp = [0, 0, 0];
    function pathPoint(a, b, omega, so, lift, f) {
      var wa = Math.sin((1 - f) * omega) / so, wb = Math.sin(f * omega) / so;
      tmp[0] = a[0] * wa + b[0] * wb;
      tmp[1] = a[1] * wa + b[1] * wb;
      tmp[2] = a[2] * wa + b[2] * wb;
      return project(tmp, R * (1 + lift * Math.sin(f * Math.PI)));
    }

    function stroke(x0, y0, x1, y1, rgb, alpha, width) {
      if (alpha <= 0.004) return;
      ctx.strokeStyle = 'rgba(' + rgb + ',' + alpha.toFixed(3) + ')';
      ctx.lineWidth = width;
      ctx.beginPath();
      ctx.moveTo(x0, y0);
      ctx.lineTo(x1, y1);
      ctx.stroke();
    }

    function glowDot(x, y, radius, rgb, alpha) {
      var g = ctx.createRadialGradient(x, y, 0, x, y, radius);
      g.addColorStop(0, 'rgba(' + rgb + ',' + alpha + ')');
      g.addColorStop(1, 'rgba(' + rgb + ',0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, 6.2832);
      ctx.fill();
    }

    function drawFlights(t, k) {
      var STEPS = 56;
      for (var i = flights.length - 1; i >= 0; i--) {
        var fl = flights[i];
        var u = (t - fl.born) / fl.dur;
        if (u >= 1) {
          flights.splice(i, 1);
          continue;
        }
        // The head runs ahead; the tail follows and catches up at the end.
        var head = easeInOut(clamp01(u / 0.72));
        var tail = easeInOut(clamp01((u - 0.30) / 0.70));
        if (!fl.landed && head >= 0.999) {
          fl.landed = true;
          ripples.push({ v: fl.b, born: t, rgb: fl.rgb });
        }
        var prevX = 0, prevY = 0, prevOk = false, has = false;
        for (var s = 0; s <= STEPS; s++) {
          var f = s / STEPS;
          var p = pathPoint(fl.a, fl.b, fl.omega, fl.so, fl.lift, f);
          var x = p[0], y = p[1], ok = p[3], depth = p[2];
          if (has && (ok || prevOk)) {
            var dim = depth < 0 ? 0.30 : 1;
            // Faint route for the whole hop.
            var routeFade = Math.sin(Math.PI * clamp01(u)) * 0.10 * dim;
            stroke(prevX, prevY, x, y, fl.rgb, routeFade, 1 * k);
            if (f > tail && f <= head + 1 / STEPS) {
              var along = head - tail > 0.001 ? (f - tail) / (head - tail) : 1;
              var a = along * along * dim;
              stroke(prevX, prevY, x, y, fl.rgb, a * 0.22, (5 + 5 * along) * k);   // glow
              stroke(prevX, prevY, x, y, fl.rgb, a * 0.95, (0.9 + 1.6 * along) * k); // core
            }
          }
          prevX = x; prevY = y; prevOk = ok; has = true;
        }
        if (head < 0.999) {
          var h = pathPoint(fl.a, fl.b, fl.omega, fl.so, fl.lift, head);
          if (h[3]) {
            var hd = h[2] < 0 ? 0.35 : 1;
            glowDot(h[0], h[1], 13 * k, fl.rgb, 0.85 * hd);
            ctx.fillStyle = 'rgba(255,255,255,' + (0.95 * hd) + ')';
            ctx.beginPath();
            ctx.arc(h[0], h[1], 2.2 * k, 0, 6.2832);
            ctx.fill();
          }
        }
      }
    }

    function drawLeads(t, k) {
      var tx = anchor.x * size, ty = anchor.y * size;
      var SEG = 30;
      for (var i = leads.length - 1; i >= 0; i--) {
        var ld = leads[i];
        var u = (t - ld.born) / ld.dur;
        if (u >= 1) {
          leads.splice(i, 1);
          continue;
        }
        var p = project(ld.m.v, R * 1.02);
        if (!p[3] && u < 0.15) { leads.splice(i, 1); continue; } // turned away before leaving
        var fx = p[0], fy = p[1];
        // Rise away from the globe, then curve down into the card.
        var cx = (fx + tx) / 2 + (ty - fy) * 0.20;
        var cy = Math.min(fy, ty) - (Math.abs(tx - fx) * 0.30 + 46 * k);
        var head = easeInOut(clamp01(u / 0.80));
        var tail = easeInOut(clamp01((u - 0.34) / 0.66));
        var px = 0, py = 0;
        for (var s = 0; s <= SEG; s++) {
          var f = tail + (head - tail) * (s / SEG);
          var q = 1 - f;
          var x = q * q * fx + 2 * q * f * cx + f * f * tx;
          var y = q * q * fy + 2 * q * f * cy + f * f * ty;
          if (s > 0) {
            var along = s / SEG;
            var a = along * along;
            stroke(px, py, x, y, GOLD, a * 0.22, (5 + 6 * along) * k);
            stroke(px, py, x, y, along > 0.7 ? '255,236,200' : GOLD, a * 0.95, (1 + 1.9 * along) * k);
          }
          px = x; py = y;
        }
        if (head < 0.995) {
          glowDot(px, py, 15 * k, GOLD, 0.9);
          ctx.fillStyle = 'rgba(255,255,255,0.97)';
          ctx.beginPath();
          ctx.arc(px, py, 2.5 * k, 0, 6.2832);
          ctx.fill();
        } else if (!ld.landed) {
          ld.landed = true;
          ripples.push({ x: tx, y: ty, born: t, rgb: GOLD });
        }
      }
    }

    function drawRipples(t, k) {
      for (var i = ripples.length - 1; i >= 0; i--) {
        var r = ripples[i];
        var u = (t - r.born) / 0.9;
        if (u >= 1) { ripples.splice(i, 1); continue; }
        var x = r.x, y = r.y;
        if (r.v) {
          var p = project(r.v, R * 1.02);
          if (!p[3] || p[2] < 0) continue;
          x = p[0]; y = p[1];
        }
        for (var n = 0; n < 2; n++) {
          var uu = clamp01(u - n * 0.22);
          if (uu <= 0) continue;
          ctx.strokeStyle = 'rgba(' + r.rgb + ',' + ((1 - uu) * 0.75).toFixed(3) + ')';
          ctx.lineWidth = 1.6 * k;
          ctx.beginPath();
          ctx.arc(x, y, (3 + uu * 24) * k, 0, 6.2832);
          ctx.stroke();
        }
      }
    }

    function frame(now) {
      raf = 0;
      if (destroyed) return;
      var dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      var t = now / 1000;

      if (!dragging) {
        phi += (0.11 + spin) * dt;
        spin *= Math.pow(0.12, dt);
      }
      var ease = 1 - Math.pow(0.004, dt);
      lean += (leanTarget - lean) * ease;
      nod += (nodTarget - nod) * ease;

      // Markers breathe; a pulsing one swells for a moment.
      var list = markers.map(function (m, i) {
        var s = 0.034 + 0.006 * Math.sin(t * 2.1 + i * 1.7);
        var lit = pulses[m.key];
        if (lit !== undefined) {
          var age = t - lit;
          if (age < 1.4) s += 0.05 * Math.sin((age / 1.4) * Math.PI);
          else delete pulses[m.key];
        }
        return { location: [m.lat, m.lng], size: s };
      });

      var p = phi + lean, th = 0.3 + nod;
      globe.update({ phi: p, theta: th, width: size, height: size, markers: list });

      cp = Math.cos(p); sp = Math.sin(p); ct = Math.cos(th); st = Math.sin(th);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, size, size);
      ctx.lineCap = 'round';
      ctx.globalCompositeOperation = 'lighter';
      var k = Math.max(0.6, size / 520);
      drawFlights(t, k);
      drawRipples(t, k);
      drawLeads(t, k);

      if (visible) raf = requestAnimationFrame(frame);
    }

    raf = requestAnimationFrame(frame);
    requestAnimationFrame(function () {
      canvas.style.opacity = '1';
      overlay.style.opacity = '1';
    });

    function now() { return performance.now() / 1000; }

    return {
      anchor: function (nx, ny) { anchor.x = nx; anchor.y = ny; },
      // A lead leaves this country for the results card. Returns false when
      // the country is on the far side of the globe right now.
      pulse: function (key) {
        var m = byKey[key];
        if (!m) return false;
        var front = project(m.v, R);
        if (front[2] < 0.12) return false;
        var t = now();
        pulses[key] = t;
        ripples.push({ v: m.v, born: t, rgb: GOLD });
        leads.push({ m: m, born: t, dur: 1.15, landed: false });
        return true;
      },
      // A comet travels from one country to another.
      link: function (fromKey, toKey) {
        var a = byKey[fromKey], b = byKey[toKey];
        if (!a || !b || a === b) return;
        var d = a.v[0] * b.v[0] + a.v[1] * b.v[1] + a.v[2] * b.v[2];
        var omega = Math.acos(Math.max(-1, Math.min(1, d)));
        if (omega < 0.06) return;
        var t = now();
        pulses[fromKey] = t;
        flights.push({
          a: a.v, b: b.v, omega: omega, so: Math.sin(omega),
          lift: 0.10 + 0.34 * (omega / Math.PI),     // short hops stay low
          born: t, dur: 1.5 + 1.5 * (omega / Math.PI),
          rgb: flights.length % 2 ? VIOLET : TEAL, landed: false,
        });
      },
      hover: function (nx, ny) {
        leanTarget = Math.max(-0.5, Math.min(0.5, nx)) * 0.5;
        nodTarget = Math.max(-0.5, Math.min(0.5, ny)) * 0.32;
      },
      leave: function () { leanTarget = 0; nodTarget = 0; },
      dragStart: function () { dragging = true; spin = 0; },
      drag: function (dx) { phi += dx * 0.0085; },
      dragEnd: function (velocity) {
        dragging = false;
        spin = Math.max(-5, Math.min(5, velocity * 0.0085));
      },
      destroy: function () {
        destroyed = true;
        if (raf) cancelAnimationFrame(raf);
        if (io) io.disconnect();
        if (ro) ro.disconnect();
        try { globe.destroy(); } catch (e) { /* context already lost */ }
        if (canvas.parentNode) canvas.parentNode.removeChild(canvas);
        if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
      },
    };
  }

  window.ilGlobe = { mount: mount };
})();
