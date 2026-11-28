const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function loadHelpers() {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const start = js.indexOf('// ─── Daily forecast temperature range bars');
  const end = js.indexOf('function getWeatherIconFile', start);
  assert.ok(start > -1 && end > start, 'expected range bar helpers in app.js');
  const sandbox = { console };
  vm.runInNewContext(`${js.slice(start, end)};
    this.getTemperatureSpan = getTemperatureSpan;
    this.getTemperatureRangeFractions = getTemperatureRangeFractions;
    this.getTemperatureRangeSegment = getTemperatureRangeSegment;
    this.renderTemperatureRangeBar = renderTemperatureRangeBar;
    this.getDailyPrecipCue = getDailyPrecipCue;
    this.formatRangeTemp = formatRangeTemp;`, sandbox);
  return sandbox;
}

const h = loadHelpers();
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} !~ ${b}`);

test('shared span is min low to max high across the whole list', () => {
  assert.deepEqual({ ...h.getTemperatureSpan([40, 55, 48], [60, 82, 70]) }, { lower: 40, upper: 82 });
});

test('flat forecast keeps a minimum 1 degree span', () => {
  assert.deepEqual({ ...h.getTemperatureSpan([70, 70], [70, 70]) }, { lower: 70, upper: 71 });
});

test('span ignores missing values and falls back when empty', () => {
  assert.deepEqual({ ...h.getTemperatureSpan([null, 50], [undefined, 60]) }, { lower: 50, upper: 60 });
  assert.deepEqual({ ...h.getTemperatureSpan([], []) }, { lower: 0, upper: 1 });
});

test('segment positions follow the shared scale', () => {
  const span = { lower: 40, upper: 80 };
  const seg = h.getTemperatureRangeSegment(50, 70, span, 200);
  near(seg.x, 50);
  near(seg.width, 100);
  // widest day fills the whole track
  const full = h.getTemperatureRangeSegment(40, 80, span, 200);
  near(full.x, 0);
  near(full.width, 200);
});

test('same low and high still shows a pill the height of the track', () => {
  const seg = h.getTemperatureRangeSegment(60, 60, { lower: 40, upper: 80 }, 200);
  near(seg.width, 6);
  near(seg.x, 100);
});

test('pill at the hot end is pulled back inside the track', () => {
  const seg = h.getTemperatureRangeSegment(80, 80, { lower: 40, upper: 80 }, 200);
  near(seg.width, 6);
  near(seg.x, 194);
});

test('inverted low/high behaves like the ordered pair', () => {
  const span = { lower: 40, upper: 80 };
  assert.deepEqual(
    { ...h.getTemperatureRangeSegment(70, 50, span, 200) },
    { ...h.getTemperatureRangeSegment(50, 70, span, 200) }
  );
});

test('values outside the span are clamped', () => {
  const f = h.getTemperatureRangeFractions(20, 100, { lower: 40, upper: 80 });
  near(f.start, 0);
  near(f.end, 1);
});

test('zero track width or missing temps yield no segment', () => {
  const span = { lower: 40, upper: 80 };
  assert.equal(h.getTemperatureRangeSegment(50, 60, span, 0), null);
  assert.equal(h.getTemperatureRangeSegment(null, 60, span, 100), null);
  assert.equal(h.getTemperatureRangeSegment(50, NaN, span, 100), null);
});

test('narrow track never lets the pill exceed the track', () => {
  const seg = h.getTemperatureRangeSegment(40, 80, { lower: 40, upper: 80 }, 4);
  near(seg.width, 4);
  near(seg.x, 0);
});

test('rendered bar uses the chart Low to High gradient and shared fractions', () => {
  const html = h.renderTemperatureRangeBar(50, 70, { lower: 40, upper: 80 });
  assert.match(html, /rgb\(54, 162, 235\), rgb\(255, 99, 132\)/);
  assert.match(html, /--range-start:0\.2500/);
  assert.match(html, /--range-end:0\.7500/);
  assert.match(h.renderTemperatureRangeBar(null, null, { lower: 0, upper: 1 }), /temp-range-track/);
});

test('rain cue shows at 10% and up; dry days return null so the slot stays empty', () => {
  assert.equal(h.getDailyPrecipCue(9, 0), null);
  assert.equal(h.getDailyPrecipCue(null, 0), null);
  assert.equal(h.getDailyPrecipCue(10, 0).text, '10%');
  assert.equal(h.getDailyPrecipCue(10, 0).snow, false);
  assert.equal(h.getDailyPrecipCue(60, 0.4).snow, true);
});

test('temperature labels are rounded with a degree sign, not 24-hour or unit text', () => {
  assert.equal(h.formatRangeTemp(71.6), '72\u00b0');
  assert.equal(h.formatRangeTemp(-0.2), '0\u00b0');
  assert.equal(h.formatRangeTemp(undefined), '--');
});

test('daily list is phone-width and the row is a single iOS-like line', () => {
  const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const rule = (sel) => {
    const m = html.match(new RegExp(`(?:^|\\n)\\s*${sel.replace('.', '\\.')}\\s*\\{([^}]*)\\}`));
    assert.ok(m, `missing rule ${sel}`);
    return m[1];
  };
  const list = rule('#dailyForecast');
  assert.match(list, /max-width:\s*24\.5rem/);
  const main = rule('.daily-forecast-main');
  assert.match(main, /minmax\(24px,\s*1fr\)/);
  const track = rule('.temp-range-track');
  assert.match(track, /height:\s*6px/);
  assert.match(track, /min-width:\s*24px/);
  assert.match(html, /\.daily-forecast-chevron\s*\{/);
  assert.match(js, /daily-forecast-chevron/);
  const rowStart = js.indexOf("dayItem.className = 'daily-forecast-card");
  const rowEnd = js.indexOf('dayItem.addEventListener', rowStart);
  const row = js.slice(rowStart, rowEnd);
  assert.doesNotMatch(row, /daily-forecast-metrics/);
  assert.doesNotMatch(row, /Feels like|fas fa-wind|fas fa-tint/);
});

test('desktop forecast uses two week columns and keeps a short right-aligned bar', () => {
  const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const desktop = html.match(/@media \(min-width:\s*760px\) \{([\s\S]*?)\n        \}/);
  assert.ok(desktop, 'missing 760px week-column breakpoint');
  const block = desktop[1];
  assert.match(block, /#dailyForecast\s*\{[^}]*max-width:\s*none/);
  assert.match(block, /grid-template-columns:\s*1fr 1fr/);
  assert.match(block, /grid-template-rows:\s*subgrid/);
  assert.match(block, /grid-row:\s*span 9/);
  assert.match(block, /grid-template-columns:\s*50px 28px 40px minmax\(0, 1fr\) 36px minmax\(64px, 100px\) 36px 14px/);
  assert.match(block, /\.temp-range-track\s*\{[^}]*max-width:\s*100px/);
  assert.match(js, /daily-forecast-spacer/);
  assert.match(js, /className = 'daily-forecast-week'/);
  assert.match(js, /Week \$\{week \+ 1\}/);
  assert.match(js, /daily-forecast-week-snow/);
  assert.match(js, /groupConsecutiveSnowDays/);
  assert.doesNotMatch(js, /snowSection\.classList\.remove\('hidden'\)/);
});
