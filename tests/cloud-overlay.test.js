const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

// Regression guard for the cloud-cover overlay (low/mid/high bars overlaid per
// category instead of stacked/grouped). Legend-hidden series keep an empty
// <g class="apexcharts-series"> in the DOM; the overlay must:
//   1. count only series that actually rendered bars (a lone visible series must
//      keep its natural bar width instead of stretching totalSeriesCount x and
//      overlapping neighbouring categories), and
//   2. anchor slots on the first VISIBLE series (crash fix: series 0 has no bars
//      when the Low Clouds layer is legend-hidden).
// Geometry helpers are exercised against a fake DOM mirroring ApexCharts output:
// path-based bars (borderRadius makes ApexCharts emit <path d="M x y ...">), with
// transform-anchored overlay placement.

function loadOverlay() {
  const source = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const start = source.indexOf('function overlayCloudSeries');
  assert.ok(start > -1, 'expected overlayCloudSeries in public/app.js');
  // brace-match the full function body
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

// Fake DOM: groups -> bars as path elements like ApexCharts 4.x with borderRadius
function makeBar(x, w) {
  const d = `M ${x} 10 L ${x + w} 10 L ${x + w} 90 L ${x} 90 L ${x} 10`;
  return {
    attrs: { d, barWidth: String(w) },
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

test('overlay stretches each visible series to the full grouped width', () => {
  const overlay = loadOverlay();
  // three visible series, natural width 19.3 -> group width 57.9
  const groups = [
    makeSeriesGroup([makeBar(3.2, 19.3), makeBar(67.6, 19.3)]),
    makeSeriesGroup([makeBar(22.5, 19.3), makeBar(87.0, 19.3)]),
    makeSeriesGroup([makeBar(41.9, 19.3), makeBar(106.3, 19.3)]),
  ];
  overlay(makeChartEl(groups));
  for (const g of groups) {
    for (const bar of g.bars) {
      const m = bar.attrs.transform.match(/scale\(([\d.]+)/);
      assert.ok(m, 'expected a scale transform on overlaid bars');
      assert.equal(Math.abs(parseFloat(m[1]) - 3), 0, 'scale should stretch by seriesCount');
    }
  }
});

test('overlay counts only VISIBLE series (legend-hidden series have no bars)', () => {
  const overlay = loadOverlay();
  // mid + high collapsed by the legend: their <g> elements remain, empty.
  // Low-only: one visible series with ApexCharts' natural FULL-slot width (57.5).
  // Correct result: no stretch (57.5 x 1); the old bug stretched to 57.5 x 3.
  const lowOnly = [makeSeriesGroup([makeBar(3.2, 57.5), makeBar(67.6, 57.5)]), makeSeriesGroup([]), makeSeriesGroup([])];
  overlay(makeChartEl(lowOnly));
  for (const bar of lowOnly[0].bars) {
    const m = bar.attrs.transform.match(/scale\(([\d.]+)/);
    const sx = m ? parseFloat(m[1]) : 1;
    assert.equal(sx, 1, 'lone visible series must not be stretched');
  }
});

test('overlay anchors on the first VISIBLE series (no crash when Low is hidden)', () => {
  const overlay = loadOverlay();
  // Low collapsed: series 0 has NO bars -> old code crashed on baseBars[0].getAttribute
  const midAndHigh = [
    makeSeriesGroup([]),
    makeSeriesGroup([makeBar(3.2, 28.8), makeBar(67.6, 28.8)]),
    makeSeriesGroup([makeBar(32.0, 28.8), makeBar(96.6, 28.8)]),
  ];
  assert.doesNotThrow(() => overlay(makeChartEl(midAndHigh)));
  // both visible series should end up anchored at the mid series' x-slots.
  // Transform chain translate(destX) scale(sx) translate(-curX): at the bar's own
  // origin (p = curX) the effective start x is exactly destX (the translate value).
  const anchoredX = (bar) => {
    const tm = (bar.attrs.transform || '').match(/translate\(((-?[\d.]+))/);
    return tm ? parseFloat(tm[1]) : null;
  };
  for (const bar of [...midAndHigh[1].bars, ...midAndHigh[2].bars]) {
    const effX = anchoredX(bar);
    assert.ok(effX != null, 'expected a transform on overlaid bars');
    assert.ok(
      Math.abs(effX - 3.2) < 0.2 || Math.abs(effX - 67.6) < 0.2,
      `bar should be anchored at a mid-series slot (3.2 or 67.6), got ${effX}`
    );
  }
});

test('overlay no-ops when every series is legend-hidden (empty state)', () => {
  const overlay = loadOverlay();
  const allHidden = [makeSeriesGroup([]), makeSeriesGroup([]), makeSeriesGroup([])];
  assert.doesNotThrow(() => overlay(makeChartEl(allHidden)));
});

test('overlay handles rect-based bars (width/x attributes)', () => {
  const overlay = loadOverlay();
  const rect = (x, w) => ({
    attrs: { x: String(x), width: String(w), barWidth: String(w) },
    getAttribute(n) { return this.attrs[n] ?? null; },
    setAttribute(n, v) { this.attrs[n] = v; },
    hasAttribute(n) { return n in this.attrs; },
  });
  const groups = [makeSeriesGroup([rect(3.2, 19.3), rect(67.6, 19.3)]), makeSeriesGroup([rect(22.5, 19.3), rect(87.0, 19.3)])];
  overlay(makeChartEl(groups));
  // rect path: x/width set directly. All bars collapse onto the first series'
  // x-slots (3.2, 67.6) and stretch to the full group width (19.3 x 2).
  for (const g of groups) {
    for (const bar of g.bars) {
      assert.ok(
        bar.attrs.x === '3.2' || bar.attrs.x === '67.6',
        `x should be a base-series slot, got ${bar.attrs.x}`
      );
      assert.equal(bar.attrs.width, String(19.3 * 2));
    }
  }
});