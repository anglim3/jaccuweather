const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
const appJs = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
const buildJs = fs.readFileSync(path.join(root, 'build.js'), 'utf8');

// Conditions / Atmosphere / Health card headers and the static Meteocons
// fill icon (@meteocons/svg-static) each one uses.
const CARD_ICON_MAPPING = [
  ['Feels Like', 'thermometer.svg'],
  ['Humidity', 'humidity.svg'],
  ['Wind', 'wind.svg'],
  ['UV Index', 'uv-index.svg'],
  ['Sun', 'sunrise.svg'],
  ['Pressure', 'barometer.svg'],
  ['Moon', 'starry-night.svg'],
  ['Air Quality', 'smoke.svg'],
  ['Allergy', 'pollen.svg'],
  ['Nice Weather', 'clear-day.svg'],
];

// Exact Font Awesome header markup these cards used before the swap.
const RETIRED_HEADERS = [
  '<i class="fas fa-thermometer-half text-orange-400 mr-1"></i>Feels Like',
  '<i class="fas fa-tint text-blue-400 mr-1"></i>Humidity',
  '<i class="fas fa-wind text-cyan-400 mr-1"></i>Wind',
  '<i class="fas fa-sun text-yellow-400 mr-1"></i>UV Index',
  '<i class="fas fa-sun text-yellow-500 mr-1"></i>Sun',
  '<i class="fas fa-gauge text-green-400 mr-1"></i>Pressure',
  '<i class="fas fa-moon text-purple-400 mr-1"></i>Moon',
  '<i class="fas fa-lungs text-green-400 mr-1"></i>Air Quality',
  '<i class="fas fa-seedling text-green-300 mr-1"></i>Allergy',
  '<i class="fas fa-face-smile-beam text-yellow-300 mr-1"></i>Nice Weather',
];

function loadPatchApplier() {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const start = source.indexOf('function parseHunks');
  const end = source.indexOf('function extractJsonStringConst');
  const sandbox = { console };
  vm.runInNewContext(`${source.slice(start, end)}; this.applyUnifiedDiff = applyUnifiedDiff;`, sandbox);
  return sandbox.applyUnifiedDiff;
}

test('card headers use vendored static Meteocons fill icons', () => {
  for (const [label, file] of CARD_ICON_MAPPING) {
    assert.match(
      html,
      new RegExp(`<img src="/icons/cards/${file.replace('.', '\\.')}"[^>]*class="card-icon[^"]*"[^>]*>${label}`),
      `expected ${label} header to use /icons/cards/${file}`
    );
  }
});

test('retired Font Awesome card headers are gone', () => {
  for (const retired of RETIRED_HEADERS) {
    assert.equal(html.includes(retired), false, `expected retired header to be gone: ${retired}`);
  }
});

test('Sinus keeps its existing icon (no honest Meteocons match)', () => {
  assert.match(html, /fa-head-side-cough[^<]*<\/i>Sinus/);
  const dir = path.join(root, 'public', 'icons', 'cards');
  const vendored = fs.readdirSync(dir).filter((f) => f.endsWith('.svg')).sort();
  assert.deepEqual(vendored, CARD_ICON_MAPPING.map(([, file]) => file).sort());
});

test('every referenced card icon exists on disk and has no SMIL animation', () => {
  const dir = path.join(root, 'public', 'icons', 'cards');
  for (const [, file] of CARD_ICON_MAPPING) {
    const svg = fs.readFileSync(path.join(dir, file), 'utf8');
    assert.equal(svg.includes('animate'), false, `${file} must be static (no SMIL)`);
    assert.equal(svg.includes('<set'), false, `${file} must be static (no <set>)`);
  }
});

test('weather-code icons still use the animated fill set', () => {
  assert.match(appJs, /const WEATHER_ICON_BASE = '\/icons\/weather\/'/);
  assert.match(appJs, /function getWeatherIconFile\(/);
  assert.match(appJs, /function getWeatherIcon\(/);
  // The vendored forecast icons keep their SMIL rotation animation.
  const weatherDir = path.join(root, 'public', 'icons', 'weather');
  const animated = fs.readdirSync(weatherDir)
    .filter((f) => f.endsWith('.svg'))
    .filter((f) => fs.readFileSync(path.join(weatherDir, f), 'utf8').includes('animate'));
  assert.ok(animated.length > 0, 'expected animated SVGs in public/icons/weather/');
  assert.match(html, /<img src="\/icons\/weather\/overcast-day-rain\.svg"/);
});

test('build.js embeds and serves both icon sets same-origin', () => {
  assert.match(buildJs, /const CARD_ICONS = /);
  assert.match(buildJs, /url\.pathname\.startsWith\('\/icons\/cards\/'\)/);
  assert.match(buildJs, /url\.pathname\.startsWith\('\/icons\/weather\/'\)/);
  assert.equal(buildJs.includes('hotlink'), true);
  // No CDN or third-party icon host may be introduced for card icons.
  for (const [, file] of CARD_ICON_MAPPING) {
    assert.equal(buildJs.includes(file), false, `build.js must not hardcode ${file}`);
  }
});

test('patches/index.html.patch still applies cleanly after the swap', () => {
  const applyUnifiedDiff = loadPatchApplier();
  const patch = fs.readFileSync(path.join(root, 'patches', 'index.html.patch'), 'utf8');
  const patched = applyUnifiedDiff(html, patch);
  assert.match(patched, /Direct Ventusky origin/);
  assert.match(patched, /title="Ventusky weather radar"/);
});
