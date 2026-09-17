const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function loadIconFunctions() {
  const source = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const versionStart = source.indexOf('const ASSET_VERSION');
  const baseStart = source.indexOf('const WEATHER_ICON_BASE');
  const fileStart = source.indexOf('function getWeatherIconFile');
  const iconStart = source.indexOf('function getWeatherIcon(');
  const descStart = source.indexOf('function getWeatherDescription');
  const moonStart = source.indexOf('function calculateMoonPhase');
  assert.ok(versionStart > -1 && baseStart > versionStart, 'expected ASSET_VERSION before WEATHER_ICON_BASE in public/app.js');
  assert.ok(fileStart > baseStart, 'expected WEATHER_ICON_BASE and getWeatherIconFile in public/app.js');
  assert.ok(iconStart > fileStart && descStart > iconStart && moonStart > descStart, 'expected icon functions in order');
  const baseEnd = source.indexOf(';', baseStart) + 1;
  const sandbox = {};
  vm.runInNewContext(
    `${source.slice(versionStart, baseEnd)}
     ${source.slice(fileStart, descStart)}
     ${source.slice(descStart, moonStart)}
     this.getWeatherIconFile = getWeatherIconFile;
     this.getWeatherIcon = getWeatherIcon;
     this.getWeatherDescription = getWeatherDescription;
     this.WEATHER_ICON_BASE = WEATHER_ICON_BASE;
     this.ASSET_VERSION = ASSET_VERSION;`,
    sandbox
  );
  return sandbox;
}

const ALL_WMO_CODES = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99];

test('every mapped WMO code resolves to a vendored fill icon file', () => {
  const { getWeatherIconFile } = loadIconFunctions();
  const dir = path.join(root, 'public', 'icons', 'weather');
  for (const code of ALL_WMO_CODES) {
    for (const isDay of [true, false]) {
      const file = getWeatherIconFile(code, isDay);
      assert.match(file, /^[a-z-]+\.svg$/, `code ${code} day=${isDay} should map to a fill icon file`);
      assert.ok(fs.existsSync(path.join(dir, file)), `vendored icon missing: ${file} (code ${code} day=${isDay})`);
    }
  }
});

test('day and night variants differ where the pack has them', () => {
  const { getWeatherIconFile } = loadIconFunctions();
  for (const code of [0, 1, 2, 3, 45, 51, 61, 63, 71, 95, 96]) {
    const day = getWeatherIconFile(code, true);
    const night = getWeatherIconFile(code, false);
    assert.notEqual(day, night, `code ${code} should have distinct day/night icons`);
    assert.ok(day.includes('-day'), `day icon for ${code} should be a day variant: ${day}`);
    assert.ok(night.includes('-night'), `night icon for ${code} should be a night variant: ${night}`);
  }
});

test('severity tiers map rain and snow codes to distinct icons', () => {
  const { getWeatherIconFile } = loadIconFunctions();
  assert.notEqual(getWeatherIconFile(61, true), getWeatherIconFile(63, true));
  assert.notEqual(getWeatherIconFile(63, true), getWeatherIconFile(65, true));
  assert.notEqual(getWeatherIconFile(71, true), getWeatherIconFile(73, true));
  assert.notEqual(getWeatherIconFile(73, true), getWeatherIconFile(75, true));
  assert.equal(getWeatherIconFile(95, true), 'thunderstorms-day-rain.svg');
  assert.equal(getWeatherIconFile(96, true), 'thunderstorms-day-hail.svg');
  assert.equal(getWeatherIconFile(99, true), 'thunderstorms-day-hail.svg');
  assert.equal(getWeatherIconFile(0, true), 'clear-day.svg');
  assert.equal(getWeatherIconFile(0, false), 'clear-night.svg');
  assert.equal(getWeatherIconFile(999, true), 'clear-day.svg');
});

test('rain/drizzle/shower/thunder with probability <= 30 downgrades to partly cloudy', () => {
  const { getWeatherIconFile } = loadIconFunctions();
  const partlyCloudyDay = getWeatherIconFile(2, true);
  for (const code of [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99]) {
    assert.equal(getWeatherIconFile(code, true, 30), partlyCloudyDay, `code ${code} at 30% should downgrade`);
    assert.equal(getWeatherIconFile(code, true, 0), partlyCloudyDay, `code ${code} at 0% should downgrade`);
  }
  assert.equal(getWeatherIconFile(61, true, 31), 'partly-cloudy-day-rain.svg');
  assert.equal(getWeatherIconFile(61, true, null), 'partly-cloudy-day-rain.svg');
  assert.equal(getWeatherIconFile(3, true, 10), 'overcast-day.svg');
  assert.equal(getWeatherIconFile(71, true, 10), 'partly-cloudy-day-snow.svg');
});

test('getWeatherIcon renders a Worker-served img instead of emoji', () => {
  const { getWeatherIcon, WEATHER_ICON_BASE, ASSET_VERSION } = loadIconFunctions();
  assert.equal(WEATHER_ICON_BASE, '/icons/weather/');
  assert.equal(ASSET_VERSION, 'dev');
  const html = getWeatherIcon(63, true);
  assert.ok(html.startsWith('<img '), 'should render an img tag');
  assert.ok(html.includes('src="/icons/weather/overcast-day-rain.svg?v=dev"'), 'should point at the Worker icon route with a version query');
  assert.ok(html.includes('class="wx-icon"'), 'should carry the sizing class');
  assert.ok(html.includes('alt="Moderate rain"'), 'should label the icon from the WMO description');
  assert.ok(!/[\u{1F300}-\u{1FAFF}\u2600-\u27BF]/u.test(html), 'should contain no emoji');
  const night = getWeatherIcon(0, false);
  assert.ok(night.includes('clear-night.svg?v=dev'), 'night clear should use the night variant');
});

test('build embeds the vendored icons and serves them from the Worker', () => {
  const buildSource = fs.readFileSync(path.join(root, 'build.js'), 'utf8');
  assert.ok(buildSource.includes("url.pathname.startsWith('/icons/weather/')"), 'Worker should serve /icons/weather/*');
  assert.ok(buildSource.includes('WEATHER_ICONS'), 'icons should be embedded at build time');
  assert.ok(!buildSource.includes('cdn.meteocons.com'), 'must not hotlink the Meteocons CDN');
  const appSource = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  assert.ok(!appSource.includes('cdn.meteocons.com'), 'client must not hotlink the Meteocons CDN');
});

test('rain/drizzle drop strokes use high-contrast sky blue, not navy', () => {
  const dir = path.join(root, 'public', 'icons', 'weather');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.svg'));
  let raindropFiles = 0;
  for (const file of files) {
    const svg = fs.readFileSync(path.join(dir, file), 'utf8');
    assert.equal(svg.includes('#0A5AD4'), false, `${file} should not use navy drop stroke`);
    if (!/id="Raindrop/.test(svg)) continue;
    raindropFiles += 1;
    const drops = [...svg.matchAll(/id="Raindrop[^"]*"[\s\S]*?stroke="([^"]+)"[\s\S]*?stroke-width="([^"]+)"/g)];
    assert.ok(drops.length >= 3, `${file} should have raindrop strokes`);
    for (const [, color, width] of drops) {
      assert.equal(color, '#7DD3FC', `${file} drop stroke should be sky-300`);
      assert.equal(width, '5', `${file} drop stroke-width should be slightly thicker`);
    }
    assert.ok(/stroke="#(E6EFFC|94A3B8)"/.test(svg), `${file} should keep original cloud strokes`);
  }
  assert.ok(raindropFiles >= 10, `expected rain/drizzle(/sleet) fill icons, got ${raindropFiles}`);

  const worker = fs.readFileSync(path.join(root, 'src', 'index.js'), 'utf8');
  assert.ok(worker.includes('#7DD3FC'), 'built Worker should embed the sky-300 rain strokes');
  assert.equal(worker.includes('#0A5AD4'), false, 'built Worker should not embed navy rain strokes');
});
