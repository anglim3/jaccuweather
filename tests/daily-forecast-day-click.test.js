const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');

function loadResolver() {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const start = js.indexOf('// Identify a 14-day row by its absolute data-day-index');
  const end = js.indexOf('function openDailyModal', start);
  assert.ok(start > -1 && end > start, 'expected daily click helpers in app.js');
  const sandbox = { console };
  vm.runInNewContext(`${js.slice(start, end)};
    this.resolveDailyForecastDayOffset = resolveDailyForecastDayOffset;`, sandbox);
  return sandbox;
}

function makeTwoWeekList() {
  const cards = [];
  const weeks = [];
  const root = {
    id: 'dailyForecast',
    contains(node) {
      return node && node._root === this;
    },
  };
  for (let week = 0; week < 2; week++) {
    const weekEl = { className: 'daily-forecast-week', children: [] };
    for (let slot = 0; slot < 7; slot++) {
      const i = week * 7 + slot;
      const inner = {
        className: 'daily-forecast-date-label',
        closest(sel) {
          return sel === '.daily-forecast-card' ? card : null;
        },
      };
      const card = {
        className: 'daily-forecast-card',
        _root: root,
        _week: week,
        _slot: slot,
        attributes: { 'data-day-index': String(i) },
        getAttribute(name) {
          return this.attributes[name];
        },
        closest(sel) {
          return sel === '.daily-forecast-card' ? this : null;
        },
      };
      inner.closest = card.closest.bind(card);
      card._inner = inner;
      weekEl.children.push(card);
      cards.push(card);
    }
    weeks.push(weekEl);
  }
  return { root, cards, weeks };
}

const h = loadResolver();

test('every one of the 14 rows, including week 2, resolves its own absolute day index', () => {
  const { root, cards, weeks } = makeTwoWeekList();
  assert.equal(cards.length, 14);
  assert.equal(weeks[1].children.length, 7);

  for (let i = 0; i < 14; i++) {
    const card = cards[i];
    const fromCard = h.resolveDailyForecastDayOffset(card, root);
    const fromInner = h.resolveDailyForecastDayOffset(card._inner, root);
    assert.equal(fromCard, i, `card ${i} should resolve to ${i}`);
    assert.equal(fromInner, i, `click inside card ${i} should resolve to ${i}`);
  }

  // The bug: position inside the week 2 wrapper is 0-6, same as week 1.
  const week2FirstLocalIndex = weeks[1].children.indexOf(cards[7]);
  assert.equal(week2FirstLocalIndex, 0);
  assert.equal(h.resolveDailyForecastDayOffset(cards[7], root), 7);
  assert.notEqual(h.resolveDailyForecastDayOffset(cards[7], root), week2FirstLocalIndex);
  assert.equal(h.resolveDailyForecastDayOffset(cards[13], root), 13);
});

test('clicks outside a day card, or cards without an absolute index, are ignored', () => {
  const { root, cards } = makeTwoWeekList();
  const stray = { closest() { return null; } };
  assert.equal(h.resolveDailyForecastDayOffset(stray, root), null);
  assert.equal(h.resolveDailyForecastDayOffset(cards[0], { contains() { return false; } }), null);
  const bad = {
    closest() { return this; },
    getAttribute() { return 'nope'; },
    _root: root,
  };
  root.contains = (n) => n === bad || n === cards[0];
  // re-bind contains for the original helper path: use a dedicated root
  const root2 = { contains(n) { return n === bad; } };
  bad._root = root2;
  assert.equal(h.resolveDailyForecastDayOffset(bad, root2), null);
});

test('the daily list stamps absolute data-day-index and delegates clicks from #dailyForecast', () => {
  const js = fs.readFileSync(path.join(root, 'public', 'app.js'), 'utf8');
  const html = fs.readFileSync(path.join(root, 'public', 'index.html'), 'utf8');
  assert.match(js, /setAttribute\('data-day-index', String\(i\)\)/);
  assert.match(js, /getElementById\('dailyForecast'\)\.addEventListener\('click', handleDailyForecastClick\)/);
  assert.doesNotMatch(js, /dayItem\.addEventListener\('click',\s*\(\)\s*=>\s*openDailyModal\(data\)\)/);
  assert.match(js, /function openDailyModal\(data, dayOffset\)/);
  assert.match(js, /detailItem\.setAttribute\('data-day-index', String\(i\)\)/);
  assert.match(js, /classList\.add\('is-selected-day'\)/);
  assert.match(html, /#dailyDetails \.is-selected-day/);
  assert.match(js, /function destroyCharts/);
  assert.match(js, /destroyCharts\(dailyChart\)/);
});
