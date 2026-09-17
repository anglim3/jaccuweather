const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
const appJs = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
const buildJs = fs.readFileSync(path.join(root, 'build.js'), 'utf8');

function loadAlertIconFunctions() {
  const source = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const versionStart = source.indexOf('const ASSET_VERSION');
  const versionEnd = source.indexOf(';', versionStart) + 1;
  const baseStart = source.indexOf('const ALERT_ICON_BASE');
  const displayStart = source.indexOf('function displayAlerts(');
  assert.ok(versionStart > -1, 'expected ASSET_VERSION in public/app.js');
  assert.ok(baseStart > -1, 'expected ALERT_ICON_BASE in public/app.js');
  assert.ok(displayStart > baseStart, 'expected getAlertIconFile/getAlertIcon before displayAlerts');
  const sandbox = {};
  vm.runInNewContext(
    `${source.slice(versionStart, versionEnd)}
     ${source.slice(baseStart, displayStart)}
     this.getAlertIconFile = getAlertIconFile;
     this.getAlertIcon = getAlertIcon;
     this.ALERT_ICON_BASE = ALERT_ICON_BASE;
     this.ASSET_VERSION = ASSET_VERSION;`,
    sandbox
  );
  return sandbox;
}

// The exact vendored alarm set: only icons mapped by getAlertIconFile()
// plus the one honest generic fallback (weather-alarm.svg).
const VENDORED_ALERT_ICONS = [
  'alert-avalanche-danger.svg',
  'dust.svg',
  'flag-cold-wave.svg',
  'flag-gale-warning.svg',
  'flag-hurricane-warning.svg',
  'flag-small-craft-advisory.svg',
  'flag-storm-warning.svg',
  'fog.svg',
  'hurricane.svg',
  'smoke.svg',
  'snowflake.svg',
  'sun-hot.svg',
  'thunderstorms.svg',
  'tornado.svg',
  'water.svg',
  'weather-alarm.svg',
];

// Representative real NWS `properties.event` strings and the official
// alarm icon each one must resolve to.
const EVENT_MAPPING = [
  ['Tornado Warning', 'tornado.svg'],
  ['Tornado Watch', 'tornado.svg'],
  ['Hurricane Warning', 'hurricane.svg'],
  ['Hurricane Watch', 'hurricane.svg'],
  ['Tropical Storm Warning', 'hurricane.svg'],
  ['Tropical Storm Watch', 'hurricane.svg'],
  ['Typhoon Warning', 'hurricane.svg'],
  ['Severe Thunderstorm Warning', 'thunderstorms.svg'],
  ['Severe Thunderstorm Watch', 'thunderstorms.svg'],
  ['Severe Weather Statement', 'thunderstorms.svg'],
  ['Flash Flood Warning', 'water.svg'],
  ['Flash Flood Watch', 'water.svg'],
  ['Flood Warning', 'water.svg'],
  ['Flood Watch', 'water.svg'],
  ['Flood Advisory', 'water.svg'],
  ['Coastal Flood Advisory', 'water.svg'],
  ['Lakeshore Flood Warning', 'water.svg'],
  ['Storm Surge Warning', 'water.svg'],
  ['Storm Surge Watch', 'water.svg'],
  ['Tsunami Warning', 'water.svg'],
  ['Tsunami Advisory', 'water.svg'],
  ['Beach Hazards Statement', 'water.svg'],
  ['Rip Current Statement', 'water.svg'],
  ['Hydrologic Outlook', 'water.svg'],
  ['Red Flag Warning', 'smoke.svg'],
  ['Fire Weather Watch', 'smoke.svg'],
  ['Air Quality Alert', 'smoke.svg'],
  ['Dense Smoke Advisory', 'smoke.svg'],
  ['Avalanche Warning', 'alert-avalanche-danger.svg'],
  ['Avalanche Watch', 'alert-avalanche-danger.svg'],
  ['Avalanche Advisory', 'alert-avalanche-danger.svg'],
  ['Dense Fog Advisory', 'fog.svg'],
  ['Dust Storm Warning', 'dust.svg'],
  ['Blowing Dust Advisory', 'dust.svg'],
  ['Excessive Heat Warning', 'sun-hot.svg'],
  ['Excessive Heat Watch', 'sun-hot.svg'],
  ['Heat Advisory', 'sun-hot.svg'],
  ['Winter Storm Warning', 'snowflake.svg'],
  ['Winter Storm Watch', 'snowflake.svg'],
  ['Winter Weather Advisory', 'snowflake.svg'],
  ['Blizzard Warning', 'snowflake.svg'],
  ['Ice Storm Warning', 'snowflake.svg'],
  ['Lake Effect Snow Warning', 'snowflake.svg'],
  ['Snow Squall Warning', 'snowflake.svg'],
  ['Freeze Warning', 'flag-cold-wave.svg'],
  ['Freeze Watch', 'flag-cold-wave.svg'],
  ['Frost Advisory', 'flag-cold-wave.svg'],
  ['Cold Weather Advisory', 'flag-cold-wave.svg'],
  ['Extreme Cold Warning', 'flag-cold-wave.svg'],
  ['Wind Chill Advisory', 'flag-cold-wave.svg'],
  ['High Wind Warning', 'flag-gale-warning.svg'],
  ['High Wind Watch', 'flag-gale-warning.svg'],
  ['Wind Advisory', 'flag-gale-warning.svg'],
  ['Gale Warning', 'flag-gale-warning.svg'],
  ['Gale Watch', 'flag-gale-warning.svg'],
  ['Lake Wind Advisory', 'flag-gale-warning.svg'],
  ['Extreme Wind Warning', 'flag-gale-warning.svg'],
  ['Small Craft Advisory', 'flag-small-craft-advisory.svg'],
  ['Storm Warning', 'flag-storm-warning.svg'],
  ['Storm Watch', 'flag-storm-warning.svg'],
  ['Special Marine Warning', 'flag-storm-warning.svg'],
  ['Hurricane Force Wind Warning', 'flag-hurricane-warning.svg'],
  // Generic NWS products with no honest icon match use the fallback.
  ['Special Weather Statement', 'weather-alarm.svg'],
  ['Hazardous Weather Outlook', 'weather-alarm.svg'],
  ['Short Term Forecast', 'weather-alarm.svg'],
];

test('NWS alert event types map to the closest official alarm icon', () => {
  const { getAlertIconFile } = loadAlertIconFunctions();
  for (const [event, file] of EVENT_MAPPING) {
    assert.equal(getAlertIconFile(event), file, `"${event}" should map to ${file}`);
  }
});

test('keyword overlaps resolve to the most specific icon', () => {
  const { getAlertIconFile } = loadAlertIconFunctions();
  // Each of these contains a weaker keyword ("storm warning", "freeze",
  // "hurricane") that must not win over the specific match.
  assert.equal(getAlertIconFile('Storm Surge Warning'), 'water.svg');
  assert.equal(getAlertIconFile('Winter Storm Warning'), 'snowflake.svg');
  assert.equal(getAlertIconFile('Severe Thunderstorm Warning'), 'thunderstorms.svg');
  assert.equal(getAlertIconFile('Dust Storm Warning'), 'dust.svg');
  assert.equal(getAlertIconFile('Freezing Rain Advisory'), 'snowflake.svg');
  assert.equal(getAlertIconFile('Freezing Fog Advisory'), 'fog.svg');
  assert.equal(getAlertIconFile('Hurricane Force Wind Warning'), 'flag-hurricane-warning.svg');
  assert.equal(getAlertIconFile('Tropical Storm Warning'), 'hurricane.svg');
});

test('unknown, empty, and missing events use the generic fallback', () => {
  const { getAlertIconFile } = loadAlertIconFunctions();
  for (const event of [undefined, null, '', 'Some Future Product']) {
    assert.equal(getAlertIconFile(event), 'weather-alarm.svg', `event ${String(event)} should fall back`);
  }
});

test('every mapped event resolves to a vendored file on disk', () => {
  const { getAlertIconFile } = loadAlertIconFunctions();
  const dir = path.join(root, 'public', 'icons', 'alerts');
  const mapped = new Set(EVENT_MAPPING.map(([, file]) => file));
  mapped.add(getAlertIconFile(undefined));
  for (const file of mapped) {
    assert.match(file, /^[a-z-]+\.svg$/, `should map to a fill icon file, got ${file}`);
    assert.ok(fs.existsSync(path.join(dir, file)), `vendored icon missing: ${file}`);
  }
  const vendored = fs.readdirSync(dir).filter((f) => f.endsWith('.svg')).sort();
  assert.deepEqual(vendored, [...VENDORED_ALERT_ICONS].sort(), 'only mapped alarm icons plus the fallback should be vendored');
});

test('getAlertIcon renders a Worker-served img instead of Font Awesome', () => {
  const { getAlertIcon, ALERT_ICON_BASE, ASSET_VERSION } = loadAlertIconFunctions();
  assert.equal(ALERT_ICON_BASE, '/icons/alerts/');
  assert.equal(ASSET_VERSION, 'dev');
  const htmlOut = getAlertIcon('Tornado Warning');
  assert.ok(htmlOut.startsWith('<img '), 'should render an img tag');
  assert.ok(htmlOut.includes('src="/icons/alerts/tornado.svg?v=dev"'), 'should point at the Worker icon route with a version query');
  assert.ok(htmlOut.includes('class="alert-icon"'), 'should carry the sizing class');
  assert.ok(!htmlOut.includes('fa-'), 'should contain no Font Awesome classes');
  assert.ok(!/[\u{1F300}-\u{1FAFF}\u2600-\u27BF]/u.test(htmlOut), 'should contain no emoji');
  const fallback = getAlertIcon('Special Weather Statement');
  assert.ok(fallback.includes('src="/icons/alerts/weather-alarm.svg?v=dev"'), 'fallback should use the generic alarm icon');
});

test('the FA triangle is gone from the event glyph; chevrons and clocks stay', () => {
  assert.equal(appJs.includes('fa-exclamation-triangle'), false, 'event glyph must not use the FA triangle');
  assert.match(appJs, /getAlertIcon\(props\.event\)/, 'displayAlerts should render the mapped alarm icon');
  // Expand/collapse affordances and timestamps keep their Font Awesome glyphs.
  assert.ok(appJs.includes('fa-chevron-down'), 'expand chevron must stay');
  assert.ok(appJs.includes('fa-chevron-up'), 'collapse chevron must stay');
  assert.ok(appJs.includes('fa-clock'), 'effective-time clock must stay');
  assert.ok(!appJs.includes('cdn.meteocons.com'), 'client must not hotlink the Meteocons CDN');
});

test('alert header icons are sized up from the old text-2xl triangle', () => {
  const start = html.indexOf('.alert-icon {');
  assert.ok(start > -1, 'expected an .alert-icon rule in public/index.html');
  const rule = html.slice(start, start + 200);
  assert.match(rule, /width:\s*3em/);
  assert.match(rule, /height:\s*3em/);
});

test('build.js embeds and serves the alert icon set same-origin', () => {
  assert.match(buildJs, /const ALERT_ICONS = /);
  assert.match(buildJs, /url\.pathname\.startsWith\('\/icons\/alerts\/'\)/);
  for (const file of VENDORED_ALERT_ICONS) {
    assert.equal(buildJs.includes(file), false, `build.js must not hardcode ${file}`);
  }
});

function loadPatchApplier() {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const start = source.indexOf('function parseHunks');
  const end = source.indexOf('function extractJsonStringConst');
  const sandbox = { console };
  vm.runInNewContext(`${source.slice(start, end)}; this.applyUnifiedDiff = applyUnifiedDiff;`, sandbox);
  return sandbox.applyUnifiedDiff;
}

test('patches/index.html.patch still applies cleanly after the swap', () => {
  const applyUnifiedDiff = loadPatchApplier();
  const patch = fs.readFileSync(path.join(root, 'patches', 'index.html.patch'), 'utf8');
  const patched = applyUnifiedDiff(html, patch);
  assert.match(patched, /Direct Ventusky origin/);
  assert.match(patched, /title="Ventusky weather radar"/);
});
