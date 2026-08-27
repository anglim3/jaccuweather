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
    .filter((f) => f.startsWith(prefix) && f.endsWith('.patch') && f !== 'app-08.patch')
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
src = applyPatchToConst(src, 'HTML_CONTENT', 'patches/index.html.patch', 'Direct Ventusky origin');

const jsonNeedle = "'Access-Control-Allow-Origin': '*',\n      ...extraHeaders,";
const jsonReplacement = '...extraHeaders,';
<REST_OF_FILE_PLACEHOLDER>
