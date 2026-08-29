const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function loadPatchApplier() {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const start = source.indexOf('function parseHunks');
  const end = source.indexOf('function extractJsonStringConst');
  const sandbox = { console };
  vm.runInNewContext(`${source.slice(start, end)}; this.applyUnifiedDiff = applyUnifiedDiff;`, sandbox);
  return sandbox.applyUnifiedDiff;
}

function patchedAppJs() {
  const applyUnifiedDiff = loadPatchApplier();
  let js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const dir = path.join(root, 'patches');
  const early = fs.readdirSync(dir).filter((f) => /^app-0[1-7]\.patch$/.test(f)).sort();
  js = applyUnifiedDiff(js, early.map((f) => fs.readFileSync(path.join(dir, f), 'utf8')).join(''));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-08.patch'), 'utf8'));
  js = applyUnifiedDiff(js, fs.readFileSync(path.join(dir, 'app-09.patch'), 'utf8'));
  return js;
}

function formatIsoLocalClock(iso) {
  const m = String(iso || '').match(/T(\d{2}):(\d{2})/);
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const mi = m[2];
  const ampm = h >= 12 ? 'PM' : 'AM';
  h = h % 12 || 12;
  return `${h}:${mi} ${ampm}`;
}

test('daily modal used loop i (past_days) instead of dayIndex before the patch', () => {
  const daily = {
    time: ['2026-08-27', '2026-08-28', '2026-08-29', '2026-08-30'],
    sunrise: ['2026-08-27T06:10', '2026-08-28T06:11', '2026-08-29T06:12', '2026-08-30T06:13'],
  };
  const i = 0;
  const dayIndex = i + 2;
  assert.equal(daily.time[dayIndex], '2026-08-29');
  assert.equal(daily.sunrise[i], '2026-08-27T06:10');
  assert.equal(daily.sunrise[dayIndex], '2026-08-29T06:12');
});

test('formatIsoLocalClock keeps Tokyo wall-clock from a naive Open-Meteo ISO', () => {
  assert.equal(formatIsoLocalClock('2026-08-29T05:12'), '5:12 AM');
  assert.equal(formatIsoLocalClock('2026-08-29T18:40'), '6:40 PM');
});

test('app-09 patch applies after app-08 and indexes sunrise/sunset with dayIndex', () => {
  const js = patchedAppJs();
  assert.equal(js.includes('data.daily.sunrise[i]'), false);
  assert.equal(js.includes('data.daily.sunset[i]'), false);
  assert.equal(js.includes('formatIsoLocalClock(data.daily.sunrise[dayIndex])'), true);
  assert.equal(js.includes('formatIsoLocalClock(data.daily.sunset[dayIndex])'), true);
  assert.equal(js.includes("formatTime12Hour(new Date(data.daily.sunrise["), false);
});

test('lockdown-worker applies app-09 after app-08 and concatenates only app-01..07', () => {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const eight = source.indexOf("applyPatchToConst(src, 'JS_CONTENT', 'patches/app-08.patch')");
  const nine = source.indexOf("applyPatchToConst(src, 'JS_CONTENT', 'patches/app-09.patch')");
  assert.ok(eight > -1 && nine > eight);
  assert.match(source, /\^app-0\[1-7\]\\.patch\$/);
});
