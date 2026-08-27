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
    .filter((f) => f.startsWith(prefix) && f.endsWith('.patch'))
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

const pollenOld = `if (apiPath.startsWith('pollen')) {
        return handlePollenRequest(url, env);
      }`;
const pollenNew = `if (apiPath.startsWith('pollen')) {
        if (!isSameOriginRequest(request, url)) {
          return jsonResponse({ error: true, reason: 'Forbidden' }, 403);
        }
        return handlePollenRequest(url, env);
      }`;
if (src.includes(pollenOld)) {
  src = src.replace(pollenOld, pollenNew);
} else if (!src.includes("return jsonResponse({ error: true, reason: 'Forbidden' }, 403)")) {
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

fs.writeFileSync(srcPath, src);
console.log('lockdown-worker: pollen same-origin gate on; Ventusky HTML proxy removed; client patches inlined');
