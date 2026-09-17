const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const {
  ASSET_VERSION_PLACEHOLDER,
  collectStaticAssetParts,
  computeStaticAssetVersion,
  hasUnversionedIconSrc,
  injectAssetVersion,
  shortContentHash,
  stampHtmlDocumentAssets,
  stampHtmlIconUrls,
} = require('../asset-version');

function extractJsonStringConst(source, name) {
  const key = 'const ' + name + ' = ';
  const i = source.indexOf(key);
  assert.ok(i > -1, `${name} not found`);
  const start = i + key.length;
  assert.equal(source[start], '"', `${name} is not a JSON string`);
  let k = start + 1;
  while (k < source.length) {
    if (source[k] === '\\') {
      k += 2;
      continue;
    }
    if (source[k] === '"') {
      k += 1;
      break;
    }
    k += 1;
  }
  return JSON.parse(source.slice(start, k));
}

function loadPatchApplier() {
  const source = fs.readFileSync(path.join(root, 'lockdown-worker.js'), 'utf8');
  const start = source.indexOf('function parseHunks');
  const end = source.indexOf('function extractJsonStringConst');
  const sandbox = { console };
  vm.runInNewContext(`${source.slice(start, end)}; this.applyUnifiedDiff = applyUnifiedDiff;`, sandbox);
  return sandbox.applyUnifiedDiff;
}

test('public/app.js declares ASSET_VERSION and applies it to every icon URL builder', () => {
  const appJs = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  assert.match(appJs, /const ASSET_VERSION = 'dev';/);
  assert.match(appJs, /src="\$\{WEATHER_ICON_BASE\}\$\{file\}\?v=\$\{ASSET_VERSION\}"/);
  assert.match(appJs, /src="\$\{ALERT_ICON_BASE\}\$\{file\}\?v=\$\{ASSET_VERSION\}"/);
  assert.match(appJs, /src="\/icons\/cards\/pollen\.svg\?v=\$\{ASSET_VERSION\}"/);
  assert.match(appJs, /src="\/icons\/cards\/pollen-tree\.svg\?v=\$\{ASSET_VERSION\}"/);
  assert.match(appJs, /src="\/icons\/cards\/pollen-grass\.svg\?v=\$\{ASSET_VERSION\}"/);
  assert.match(appJs, /src="\/icons\/cards\/pollen-weed\.svg\?v=\$\{ASSET_VERSION\}"/);
  assert.equal((appJs.match(/src="\/icons\/cards\/[^"]+\.svg"/g) || []).length, 0, 'hardcoded card srcs must include ?v=${ASSET_VERSION}');
});

test('static asset version is a short content hash and changes when an icon changes', () => {
  const version = computeStaticAssetVersion(root);
  assert.match(version, /^[0-9a-f]{8}$/);
  assert.notEqual(version, ASSET_VERSION_PLACEHOLDER);
  const mutated = shortContentHash([...collectStaticAssetParts(root), 'changed-icon-bytes']);
  assert.notEqual(mutated, version, 'hash must change when icon content changes');
});

test('HTML document fingerprints reuse the apple-touch ?v= pattern', () => {
  const stamped = stampHtmlDocumentAssets(
    '<link rel="icon" href="/favicon.svg">\n<link rel="apple-touch-icon" href="/apple-touch-icon.png">\n<script src="app.js"></script>',
    { assetVersion: 'abcd1234', jsVersion: 'deadbeef' }
  );
  assert.match(stamped, /href="\/favicon\.svg\?v=abcd1234"/);
  assert.match(stamped, /href="\/apple-touch-icon\.png\?v=abcd1234"/);
  assert.match(stamped, /<script src="\/app\.js\?v=deadbeef"><\/script>/);
});

test('icon query strings keep Worker pathname routing', () => {
  const url = new URL('https://example.com/icons/weather/overcast-day-rain.svg?v=abcd1234');
  assert.equal(url.pathname, '/icons/weather/overcast-day-rain.svg');
  assert.equal(url.searchParams.get('v'), 'abcd1234');
  assert.equal(url.pathname.startsWith('/icons/weather/'), true);
  assert.equal(url.pathname.split('/').pop(), 'overcast-day-rain.svg');
});

test('build.js revalidates the HTML shell and long-caches fingerprinted blobs', () => {
  const buildJs = fs.readFileSync(path.join(root, 'build.js'), 'utf8');
  assert.match(buildJs, /computeStaticAssetVersion/);
  assert.match(buildJs, /injectAssetVersion/);
  assert.match(buildJs, /stampHtmlDocumentAssets/);
  const htmlHandler = buildJs.slice(buildJs.indexOf("url.pathname === '/'"), buildJs.indexOf("url.pathname === '/app.js'"));
  assert.match(htmlHandler, /'Cache-Control': 'no-cache'/);
  const appHandler = buildJs.slice(buildJs.indexOf("url.pathname === '/app.js'"), buildJs.indexOf("url.pathname === '/favicon.svg'"));
  assert.match(appHandler, /'Cache-Control': 'public, max-age=31536000, immutable'/);
  assert.match(buildJs, /url\.pathname\.startsWith\('\/icons\/weather\/'\)/);
  assert.match(buildJs, /url\.pathname\.startsWith\('\/icons\/cards\/'\)/);
  assert.match(buildJs, /url\.pathname\.startsWith\('\/icons\/alerts\/'\)/);
  assert.equal((buildJs.match(/'Cache-Control': 'public, max-age=31536000, immutable'/g) || []).length >= 5, true);
});

test('lockdown stamps HTML icon URLs after patches so index.html.patch still applies', () => {
  const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
  const applyUnifiedDiff = loadPatchApplier();
  const patch = fs.readFileSync(path.join(root, 'patches', 'index.html.patch'), 'utf8');
  const patched = applyUnifiedDiff(html, patch);
  assert.equal(hasUnversionedIconSrc(patched), true, 'public HTML stays unversioned so the patch can match');
  const stamped = stampHtmlIconUrls(patched, 'abcd1234');
  assert.equal(hasUnversionedIconSrc(stamped), false);
  assert.match(stamped, /src="\/icons\/cards\/thermometer\.svg\?v=abcd1234"/);
  assert.match(stamped, /src="\/icons\/weather\/overcast-day-rain\.svg\?v=abcd1234"/);
  assert.equal(stamped.includes('/icons/cards/sunrise.svg'), false, 'patched-out sun card must stay removed');
});

test('built worker HTML and JS use the current asset version and still embed icon SVGs', () => {
  const version = computeStaticAssetVersion(root);
  const src = fs.readFileSync(path.join(root, 'src', 'index.js'), 'utf8');
  const html = extractJsonStringConst(src, 'HTML_CONTENT');
  const js = extractJsonStringConst(src, 'JS_CONTENT');

  assert.match(js, new RegExp(`const ASSET_VERSION = '${version}';`));
  assert.equal(js.includes(`const ASSET_VERSION = '${ASSET_VERSION_PLACEHOLDER}';`), false);
  assert.match(js, /src="\$\{WEATHER_ICON_BASE\}\$\{file\}\?v=\$\{ASSET_VERSION\}"/);
  assert.match(html, new RegExp(`/icons/cards/thermometer\\.svg\\?v=${version}`));
  assert.match(html, new RegExp(`/icons/weather/overcast-day-rain\\.svg\\?v=${version}`));
  assert.match(html, new RegExp(`/favicon\\.svg\\?v=${version}`));
  assert.match(html, new RegExp(`/apple-touch-icon\\.png\\?v=${version}`));
  assert.match(html, /<script src="\/app\.js\?v=[0-9a-f]{8}"><\/script>/);
  assert.equal(hasUnversionedIconSrc(html), false);

  const htmlHandler = src.slice(src.indexOf("url.pathname === '/'"), src.indexOf("url.pathname === '/app.js'"));
  assert.match(htmlHandler, /'Cache-Control': 'no-cache'/);
  assert.match(src, /url\.pathname\.startsWith\('\/icons\/weather\/'\)/);
  assert.match(src, /const WEATHER_ICONS = /);
  assert.match(src, /<svg /);
});

test('injectAssetVersion refuses to ship the placeholder', () => {
  assert.throws(() => injectAssetVersion('const WEATHER_ICON_BASE = \'/icons/weather/\';', 'abcd1234'));
  assert.equal(
    injectAssetVersion("const ASSET_VERSION = 'dev';", 'abcd1234'),
    "const ASSET_VERSION = 'abcd1234';"
  );
});
