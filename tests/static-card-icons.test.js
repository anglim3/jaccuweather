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
// icon (@meteocons/svg-static) each one uses. Every header uses the fill
// variant except Humidity, which uses the monochrome variant so the glyph
// renders in the header text color (currentColor).
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

// Pollen UI (Tree / Grass / Weed cards, legend, methodology factor row,
// symptom-modal current values, allergy modal title) and the official
// static pollen-category icon each one uses.
const POLLEN_UI_MAPPING = [
  ['Tree</div>', 'pollen-tree.svg'],
  ['Grass</div>', 'pollen-grass.svg'],
  ['Weed</div>', 'pollen-weed.svg'],
  ['<strong>Tree:</strong>', 'pollen-tree.svg'],
  ['<strong>Grass:</strong>', 'pollen-grass.svg'],
  ['<strong>Weed:</strong>', 'pollen-weed.svg'],
  ['Tree pollen</div>', 'pollen-tree.svg'],
  ['Grass pollen</div>', 'pollen-grass.svg'],
  ['Weed pollen</div>', 'pollen-weed.svg'],
];

// The pollen icons vendored into public/icons/cards/: the generic icon
// plus the Tree / Grass / Weed category icons the UI actually maps.
const POLLEN_CATEGORY = [
  'pollen.svg',
  'pollen-grass.svg',
  'pollen-tree.svg',
  'pollen-weed.svg',
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
  '<i class="fas fa-tree text-green-400 mr-1"></i>Tree',
  '<i class="fas fa-leaf text-lime-400 mr-1"></i>Grass',
  '<i class="fas fa-seedling text-amber-400 mr-1"></i>Weed',
  '<i class="fas fa-leaf mr-2"></i>Pollen',
  '<i class="fas fa-tree text-green-400 mr-1"></i>Tree pollen',
  '<i class="fas fa-leaf text-lime-400 mr-1"></i>Grass pollen',
  '<i class="fas fa-seedling text-amber-400 mr-1"></i>Weed pollen',
  '<i class="fas fa-seedling text-green-300"></i>',
];

function loadPatchApplier() {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const start = source.indexOf('function parseHunks');
  const end = source.indexOf('function extractJsonStringConst');
  const sandbox = { console };
  vm.runInNewContext(`${source.slice(start, end)}; this.applyUnifiedDiff = applyUnifiedDiff;`, sandbox);
  return sandbox.applyUnifiedDiff;
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

test('card headers use vendored static Meteocons icons (humidity is monochrome)', () => {
  for (const [label, file] of CARD_ICON_MAPPING) {
    assert.match(
      html,
      new RegExp(`<img src="/icons/cards/${escapeRegExp(file)}"[^>]*class="card-icon[^"]*"[^>]*>${escapeRegExp(label)}`),
      `expected ${label} header to use /icons/cards/${file}`
    );
  }
});

test('humidity header uses the monochrome variant, other headers stay fill', () => {
  const dir = path.join(root, 'public', 'icons', 'cards');
  const humidity = fs.readFileSync(path.join(dir, 'humidity.svg'), 'utf8');
  // Monochrome glyph: raindrop inherits the header text color.
  assert.equal(humidity.includes('currentColor'), true, 'humidity.svg must use currentColor (monochrome)');
  // Monochrome file has no fill gradient/defs and no blue fill leftovers.
  assert.equal(humidity.includes('linearGradient'), false, 'humidity.svg must not carry the fill gradient');
  assert.equal(humidity.includes('paint0_linear'), false, 'humidity.svg must not reference the fill gradient');
  assert.equal(humidity.includes('#1D4ED8'), false, 'humidity.svg must not carry the fill blue stroke');
  assert.equal(humidity.includes('#2563EB'), false, 'humidity.svg must not carry the fill blue stop');
  // Only humidity swaps: every other card header icon stays on the fill set.
  for (const [, file] of CARD_ICON_MAPPING) {
    if (file === 'humidity.svg') continue;
    const svg = fs.readFileSync(path.join(dir, file), 'utf8');
    assert.equal(svg.includes('currentColor'), false, `${file} must stay on the fill set (no currentColor)`);
  }
});

test('card header icons read larger than the label text', () => {
  const css = html.slice(html.indexOf('.card-icon {'), html.indexOf('.card-icon {') + 200);
  assert.match(css, /width:\s*2em/);
  assert.match(css, /height:\s*2em/);
  assert.match(html, /#symptomRiskModalIcon \.card-icon \{\s*width:\s*1em/);
});

test('pollen UI uses the official static pollen-category icons', () => {
  const sources = [html, appJs];
  for (const [label, file] of POLLEN_UI_MAPPING) {
    const found = sources.some((src) =>
      (src.includes(`<img src="/icons/cards/${file}"`) || src.includes(`<img src="/icons/cards/${file}?v=\${ASSET_VERSION}"`)) && src.includes(label)
    );
    assert.equal(found, true, `expected ${label} to use /icons/cards/${file}`);
  }
  // Allergy card header and allergy modal title use the generic pollen icon.
  assert.match(html, /<img src="\/icons\/cards\/pollen\.svg"[^>]*>Allergy/);
  assert.match(appJs, /titleIcon\.innerHTML = `<img src="\/icons\/cards\/pollen\.svg\?v=\$\{ASSET_VERSION\}"/);
});

test('retired Font Awesome card headers are gone', () => {
  for (const retired of RETIRED_HEADERS) {
    const present = html.includes(retired) || appJs.includes(retired);
    assert.equal(present, false, `expected retired header to be gone: ${retired}`);
  }
});

test('Sinus keeps its existing icon (no honest Meteocons match)', () => {
  assert.match(html, /fa-head-side-cough[^<]*<\/i>Sinus/);
  assert.match(appJs, /fa-head-side-cough/);
  const dir = path.join(root, 'public', 'icons', 'cards');
  const vendored = fs.readdirSync(dir).filter((f) => f.endsWith('.svg')).sort();
  const expected = [...new Set([
    ...CARD_ICON_MAPPING.map(([, file]) => file),
    ...POLLEN_CATEGORY,
  ])].sort();
  assert.deepEqual(vendored, expected);
});

test('every vendored card icon exists on disk and has no SMIL animation', () => {
  const dir = path.join(root, 'public', 'icons', 'cards');
  for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.svg'))) {
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
  for (const [, file] of [...CARD_ICON_MAPPING, ...POLLEN_UI_MAPPING]) {
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
