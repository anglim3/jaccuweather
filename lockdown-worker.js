const fs = require('fs');
const path = require('path');

const srcPath = path.join(__dirname, 'src', 'index.js');
let src = fs.readFileSync(srcPath, 'utf8');

function fail(msg) {
  throw new Error('lockdown-worker: ' + msg);
}

function parseHunks(diffText) {
  const lines = diffText.replace(/\r\n/g, '\n').split('\n');
  const hunks = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const m = line.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/);
    if (!m) {
      i += 1;
      continue;
    }
    const oldStart = Number(m[1]);
    const oldCount = m[2] === undefined ? 1 : Number(m[2]);
    const body = [];
    i += 1;
    while (i < lines.length && !lines[i].startsWith('@@ ') && !lines[i].startsWith('diff ') && !lines[i].startsWith('--- ') && !lines[i].startsWith('+++ ')) {
      const l = lines[i];
      if (l.startsWith('+') || l.startsWith('-') || l.startsWith(' ') || l === '\\ No newline at end of file' || l === '') {
        if (l === '\\ No newline at end of file') {
          i += 1;
          continue;
        }
        if (l === '' && i === lines.length - 1) {
          break;
        }
        body.push(l);
        i += 1;
        continue;
      }
      break;
    }
    hunks.push({ oldStart, oldCount, body });
  }
  if (!hunks.length) fail('no hunks in patch');
  return hunks;
}

function applyUnifiedDiff(original, diffText) {
  const hadTrailingNl = original.endsWith('\n');
  const fileLines = original.split('\n');
  if (fileLines.length && fileLines[fileLines.length - 1] === '') {
    fileLines.pop();
  }
  const hunks = parseHunks(diffText);
  let offset = 0;
  for (const hunk of hunks) {
    const start = hunk.oldStart - 1 + offset;
    const oldLines = [];
    const newLines = [];
    for (const l of hunk.body) {
      if (l.startsWith(' ')) {
        oldLines.push(l.slice(1));
        newLines.push(l.slice(1));
      } else if (l.startsWith('-')) {
        oldLines.push(l.slice(1));
      } else if (l.startsWith('+')) {
        newLines.push(l.slice(1));
      }
    }
    const actual = fileLines.slice(start, start + oldLines.length);
    if (actual.join('\n') !== oldLines.join('\n')) {
      fail('hunk mismatch at original line ' + hunk.oldStart + '\nexpected:\n' + oldLines.slice(0, 3).join('\n') + '\nactual:\n' + actual.slice(0, 3).join('\n'));
    }
    fileLines.splice(start, oldLines.length, ...newLines);
    offset += newLines.length - oldLines.length;
  }
  let out = fileLines.join('\n');
  if (hadTrailingNl) out += '\n';
  return out;
}

function extractJsonStringConst(source, name) {
  const key = 'const ' + name + ' = ';
  const i = source.indexOf(key);
  if (i < 0) fail(name + ' not found');
  const start = i + key.length;
  if (source[start] !== '"') fail(name + ' is not a JSON string');
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
  const literal = source.slice(start, k);
  return { start, end: k, value: JSON.parse(literal) };
}

function replaceJsonStringConst(source, name, value) {
  const extracted = extractJsonStringConst(source, name);
  return source.slice(0, extracted.start) + JSON.stringify(value) + source.slice(extracted.end);
}

function readPatch(patchRelPath) {
  const patchPath = path.join(__dirname, patchRelPath);
  if (fs.existsSync(patchPath)) {
    return fs.readFileSync(patchPath, 'utf8');
  }
  const dir = path.dirname(patchPath);
  const fileName = path.basename(patchRelPath);
  const prefix = fileName.replace(/\.js\.patch$/, '-').replace(/\.patch$/, '-');
  const parts = fs.readdirSync(dir)
    .filter((f) => /^app-0[1-7]\.patch$/.test(f))
    .sort();
  if (!parts.length) fail('missing patch ' + patchRelPath);
  return parts.map((f) => fs.readFileSync(path.join(dir, f), 'utf8')).join('');
}

function applyPatchToConst(source, constName, patchRelPath, alreadyMarker) {
  const extracted = extractJsonStringConst(source, constName);
  if (alreadyMarker && extracted.value.includes(alreadyMarker)) {
    return source;
  }
  const patched = applyUnifiedDiff(extracted.value, readPatch(patchRelPath));
  return replaceJsonStringConst(source, constName, patched);
}

src = applyPatchToConst(src, 'JS_CONTENT', 'patches/app.js.patch', 'activeWeatherRequestId');
src = applyPatchToConst(src, 'JS_CONTENT', 'patches/app-08.patch');
src = applyPatchToConst(src, 'JS_CONTENT', 'patches/app-09.patch');
src = applyPatchToConst(src, 'HTML_CONTENT', 'patches/index.html.patch', 'Direct Ventusky origin');

const jsonNeedle = "'Access-Control-Allow-Origin': '*',\n      ...extraHeaders,";
const jsonReplacement = '...extraHeaders,';
if (!src.includes(jsonNeedle)) {
  if (!src.includes('function isSameOriginRequest')) {
    fail('jsonResponse ACAO * not found');
  }
} else {
  src = src.replace(jsonNeedle, jsonReplacement);
}

const sameOriginFn = `function isSameOriginRequest(request, requestUrl) {
  const allowedOrigin = requestUrl.origin;
  const origin = request.headers.get('Origin');
  if (origin) {
    return origin === allowedOrigin;
  }
  const fetchSite = request.headers.get('Sec-Fetch-Site');
  if (fetchSite) {
    return fetchSite === 'same-origin';
  }
  const referer = request.headers.get('Referer');
  if (referer) {
    try {
      return new URL(referer).origin === allowedOrigin;
    } catch (error) {
      return false;
    }
  }
  return false;
}

`;

if (!src.includes('function isSameOriginRequest')) {
  const insertAt = src.indexOf('function hasNumericValue');
  if (insertAt < 0) fail('hasNumericValue not found');
  src = src.slice(0, insertAt) + sameOriginFn + src.slice(insertAt);
}

const pollenRateLimitFn = `async function pollenRateLimitDenied(request, env) {
  const limiter = env && env.POLLEN_RATE_LIMIT;
  if (!limiter || typeof limiter.limit !== 'function') {
    return jsonResponse({ error: true, reason: 'Service Unavailable' }, 503);
  }
  const ip = request.headers.get('CF-Connecting-IP');
  if (!ip) {
    return jsonResponse({ error: true, reason: 'Forbidden' }, 403);
  }
  try {
    const result = await limiter.limit({ key: ip });
    if (!result || result.success !== true) {
      return jsonResponse({ error: true, reason: 'Too Many Requests' }, 429);
    }
  } catch (error) {
    return jsonResponse({ error: true, reason: 'Service Unavailable' }, 503);
  }
  return null;
}

`;

if (!src.includes('async function pollenRateLimitDenied')) {
  const insertAt = src.indexOf('function hasNumericValue');
  if (insertAt < 0) fail('hasNumericValue not found');
  src = src.slice(0, insertAt) + pollenRateLimitFn + src.slice(insertAt);
}

const pollenUnpatched = `if (apiPath.startsWith('pollen')) {
        return handlePollenRequest(url, env);
      }`;
const pollenSameOriginOnly = `if (apiPath.startsWith('pollen')) {
        if (!isSameOriginRequest(request, url)) {
          return jsonResponse({ error: true, reason: 'Forbidden' }, 403);
        }
        return handlePollenRequest(url, env);
      }`;
const pollenNew = `if (apiPath.startsWith('pollen')) {
        if (!isSameOriginRequest(request, url)) {
          return jsonResponse({ error: true, reason: 'Forbidden' }, 403);
        }
        const pollenLimited = await pollenRateLimitDenied(request, env);
        if (pollenLimited) {
          return pollenLimited;
        }
        return handlePollenRequest(url, env);
      }`;
if (src.includes(pollenUnpatched)) {
  src = src.replace(pollenUnpatched, pollenNew);
} else if (src.includes(pollenSameOriginOnly)) {
  src = src.replace(pollenSameOriginOnly, pollenNew);
} else if (!src.includes('await pollenRateLimitDenied(request, env)')) {
  fail('pollen handler not found');
}

const ventuskyStart = src.indexOf('// Proxy Ventusky');
const notFound = src.indexOf("return new Response('Not Found'");
if (ventuskyStart >= 0 && notFound > ventuskyStart) {
  src = src.slice(0, ventuskyStart) + src.slice(notFound);
} else if (src.includes('/ventusky-proxy')) {
  fail('ventusky-proxy still present and block bounds not found');
}

if (src.includes('/ventusky-proxy')) {
  fail('ventusky-proxy still present after strip');
}

if (!src.includes('activeWeatherRequestId')) {
  fail('app.js patch did not land in JS_CONTENT');
}
if (!src.includes('www.ventusky.com')) {
  fail('Ventusky direct URL missing from JS_CONTENT');
}
if (src.includes('data.daily.sunrise[i]') || src.includes('data.daily.sunset[i]')) {
  fail('daily modal still indexes sunrise/sunset with loop i instead of dayIndex');
}
if (!src.includes('data.daily.sunrise[dayIndex]') || !src.includes('formatIsoLocalClock(data.daily.sunrise[dayIndex])')) {
  fail('daily modal sun times patch did not land');
}

if (!src.includes('function isSameOriginRequest')) {
  fail('same-origin gate missing after patch');
}
if (!src.includes('async function pollenRateLimitDenied')) {
  fail('pollen rate limiter missing after patch');
}
if (!src.includes('await pollenRateLimitDenied(request, env)')) {
  fail('pollen rate limiter not applied before billed handler');
}
if (!src.includes("return jsonResponse({ error: true, reason: 'Forbidden' }, 403)")) {
  fail('pollen same-origin 403 missing after patch');
}
const pollenCallAt = src.indexOf('await pollenRateLimitDenied(request, env)');
const billedCallAt = src.indexOf('return handlePollenRequest(url, env)');
if (pollenCallAt < 0 || billedCallAt < 0 || pollenCallAt > billedCallAt) {
  fail('rate limit must run before handlePollenRequest');
}

fs.writeFileSync(srcPath, src);
console.log('lockdown-worker: pollen same-origin gate on; per-IP rate limit before billed pollen; Ventusky HTML proxy removed; client patches inlined');
