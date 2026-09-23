const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

// Regression guard for the cloud-cover overlay (low/mid/high bars overlaid per
// category instead of stacked/grouped). Legend-hidden series keep an empty
// <g class="apexcharts-series"> in the DOM (always in Low, Mid, High order).
// overlayCloudSeries() must:
//   1. count only series that actually rendered bars (a lone visible series must
//      keep its natural bar width instead of stretching totalSeriesCount x and
//      overlapping neighbouring categories),
//   2. anchor slots on the first VISIBLE series (crash fix: series 0 has no bars
//      when the Low Clouds layer is legend-hidden), and
//   3. no-op cleanly when every layer is hidden / no bars have mounted yet.
//
// Geometry mirrors ApexCharts grouped-bar layout: natural bar width is full-slot
// when one layer is visible, ~half when two are, ~third when three are. Bars may
// be <path d="M x y ..."> (borderRadius) or <rect x width>.

const SLOT_X = [3.2, 67.6];
const NATURAL_WIDTH = { 1: 57.5, 2: 28.8, 3: 19.3 };

const COMBOS = [
  { name: 'Low only', visible: [true, false, false] },
  { name: 'Mid only', visible: [false, true, false] },
  { name: 'High only', visible: [false, false, true] },
  { name: 'Low + Mid', visible: [true, true, false] },
  { name: 'Low + High', visible: [true, false, true] },
  { name: 'Mid + High', visible: [false, true, true] },
  { name: 'Low + Mid + High', visible: [true, true, true] },
  { name: 'empty (all hidden)', visible: [false, false, false] },
];

function loadOverlay() {
  const source = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const start = source.indexOf('function overlayCloudSeries');
  assert.ok(start > -1, 'expected overlayCloudSeries in public/app.js');
  let i = source.indexOf('{', start), depth = 0;
  for (; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}') { depth--; if (depth === 0) break; }
  }
  const fnSource = source.slice(start, i + 1);
  const sandbox = {};
  vm.runInNewContext(`${fnSource}; this.overlayCloudSeries = overlayCloudSeries;`, sandbox);
  return sandbox.overlayCloudSeries;
}

function makeBar(kind, x, w) {
  const attrs = kind === 'rect'
    ? { x: String(x), width: String(w), barWidth: String(w) }
    : { d: `M ${x} 10 L ${x + w} 10 L ${x + w} 90 L ${x} 90 L ${x} 10`, barWidth: String(w) };
  return {
    attrs,
    getAttribute(n) { return this.attrs[n] ?? null; },
    setAttribute(n, v) { this.attrs[n] = v; },
    hasAttribute(n) { return n in this.attrs; },
  };
}

function makeSeriesGroup(bars) {
  return {
    bars,
    querySelectorAll(sel) {
      if (sel === '.apexcharts-bar-area') return bars;
      return [];
    },
  };
}

function makeChartEl(groups) {
  return {
    querySelectorAll(sel) {
      if (sel === 'g.apexcharts-series') return groups;
      if (sel === '.apexcharts-bar-area') return groups.flatMap((g) => g.bars);
      return [];
    },
  };
}

function barX(bar) {
  if (bar.attrs.x != null) return parseFloat(bar.attrs.x);
  const m = (bar.attrs.d || '').match(/^M\s*(-?[\d.]+)/);
  return m ? parseFloat(m[1]) : null;
}

function pathDestX(bar) {
  const t = bar.attrs.transform || '';
  const firstTranslate = t.match(/translate\(((-?[\d.]+))/);
  if (!firstTranslate) return null;
  const tx = parseFloat(firstTranslate[1]);
  if (/scale\(/.test(t)) return tx;
  return tx + barX(bar);
}

function overlayScale(bar, kind, origW) {
  if (kind === 'rect') {
    const w = parseFloat(bar.attrs.width);
    return origW > 0 ? w / origW : null;
  }
  const m = (bar.attrs.transform || '').match(/scale\(([\d.]+)/);
  return m ? parseFloat(m[1]) : 1;
}

function buildGroups(visible, kind) {
  const n = visible.filter(Boolean).length;
  if (n === 0) {
    return [makeSeriesGroup([]), makeSeriesGroup([]), makeSeriesGroup([])];
  }
  const w = NATURAL_WIDTH[n];
  let visIdx = 0;
  return visible.map((isVisible) => {
    if (!isVisible) return makeSeriesGroup([]);
    const offset = visIdx * w;
    visIdx += 1;
    return makeSeriesGroup(SLOT_X.map((slotX) => makeBar(kind, slotX + offset, w)));
  });
}

function assertCombo(overlay, combo, kind) {
  const groups = buildGroups(combo.visible, kind);
  const snapshot = groups.map((g) => g.bars.map((b) => ({ x: barX(b), w: parseFloat(b.attrs.barWidth) })));
  const visibleIdx = combo.visible.map((v, i) => (v ? i : -1)).filter((i) => i >= 0);
  const n = visibleIdx.length;

  assert.doesNotThrow(() => overlay(makeChartEl(groups)));

  combo.visible.forEach((isVisible, i) => {
    if (!isVisible) assert.equal(groups[i].bars.length, 0, `${combo.name}: hidden series ${i} stays empty`);
  });

  if (n === 0) return;

  const anchorSlots = snapshot[visibleIdx[0]].map((b) => b.x);
  for (const gi of visibleIdx) {
    groups[gi].bars.forEach((bar, i) => {
      assert.equal(bar.attrs['fill-opacity'], '0.55', `${combo.name}: overlay ran on visible bars`);
      const destX = kind === 'rect' ? parseFloat(bar.attrs.x) : pathDestX(bar);
      assert.ok(destX != null, `${combo.name}: expected overlay placement on series ${gi} bar ${i}`);
      assert.ok(
        Math.abs(destX - anchorSlots[i]) < 0.2,
        `${combo.name}: bar should be anchored at first visible series slot ${anchorSlots[i]}, got ${destX}`
      );
      const sx = overlayScale(bar, kind, snapshot[gi][i].w);
      assert.equal(
        sx,
        n,
        `${combo.name}: stretch must use visible count ${n}, not total series groups (3)`
      );
    });
  }
}

for (const kind of ['path', 'rect']) {
  for (const combo of COMBOS) {
    test(`overlay legend combo: ${combo.name} (${kind} bars)`, () => {
      assertCombo(loadOverlay(), combo, kind);
    });
  }
}
