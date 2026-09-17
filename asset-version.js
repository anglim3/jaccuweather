'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Placeholder in public/app.js; build.js replaces it with a content hash.
const ASSET_VERSION_PLACEHOLDER = 'dev';

const ICON_SRC_RE = /src="(\/icons\/(?:weather|cards|alerts)\/[A-Za-z0-9.-]+\.svg)"/g;
const UNVERSIONED_ICON_SRC_RE = /src="\/icons\/(?:weather|cards|alerts)\/[A-Za-z0-9.-]+\.svg"/;

function shortContentHash(parts) {
  const hash = crypto.createHash('md5');
  for (const part of parts) {
    hash.update(part);
  }
  return hash.digest('hex').substring(0, 8);
}

function loadSvgMap(dir) {
  const files = {};
  if (!fs.existsSync(dir)) return files;
  for (const file of fs.readdirSync(dir).sort()) {
    if (file.endsWith('.svg')) {
      files[file] = fs.readFileSync(path.join(dir, file), 'utf8');
    }
  }
  return files;
}

function collectStaticAssetParts(rootDir) {
  const parts = [];
  for (const setName of ['weather', 'cards', 'alerts']) {
    const dir = path.join(rootDir, 'public', 'icons', setName);
    const files = loadSvgMap(dir);
    for (const name of Object.keys(files).sort()) {
      parts.push(`icons/${setName}/${name}`, files[name]);
    }
  }
  const faviconPath = path.join(rootDir, 'public', 'favicon.svg');
  const applePath = path.join(rootDir, 'public', 'apple-touch-icon.png');
  parts.push('favicon.svg', fs.readFileSync(faviconPath));
  if (fs.existsSync(applePath)) {
    parts.push('apple-touch-icon.png', fs.readFileSync(applePath));
  }
  return parts;
}

function computeStaticAssetVersion(rootDir) {
  return shortContentHash(collectStaticAssetParts(rootDir));
}

function injectAssetVersion(jsContent, assetVersion) {
  const from = `const ASSET_VERSION = '${ASSET_VERSION_PLACEHOLDER}';`;
  const to = `const ASSET_VERSION = '${assetVersion}';`;
  if (!jsContent.includes(from)) {
    throw new Error("public/app.js must declare const ASSET_VERSION = 'dev' for build-time injection");
  }
  return jsContent.replace(from, to);
}

function stampHtmlIconUrls(html, assetVersion) {
  return html.replace(ICON_SRC_RE, `src="$1?v=${assetVersion}"`);
}

function stampHtmlDocumentAssets(html, { assetVersion, jsVersion }) {
  let out = html;
  out = out.replace(
    /href="\/favicon\.svg(?:\?v=[^"]*)?"/,
    `href="/favicon.svg?v=${assetVersion}"`
  );
  out = out.replace(
    /href="\/apple-touch-icon\.png(?:\?v=[^"]*)?"/,
    `href="/apple-touch-icon.png?v=${assetVersion}"`
  );
  out = out.replace(
    /<script src="(?:\.\/)?(?:\/)?app\.js(?:\?v=[^"]*)?"><\/script>/,
    `<script src="/app.js?v=${jsVersion}"></script>`
  );
  return out;
}

function hasUnversionedIconSrc(html) {
  return UNVERSIONED_ICON_SRC_RE.test(html);
}

module.exports = {
  ASSET_VERSION_PLACEHOLDER,
  ICON_SRC_RE,
  UNVERSIONED_ICON_SRC_RE,
  shortContentHash,
  loadSvgMap,
  collectStaticAssetParts,
  computeStaticAssetVersion,
  injectAssetVersion,
  stampHtmlIconUrls,
  stampHtmlDocumentAssets,
  hasUnversionedIconSrc,
};
