const test = require('node:test');
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const logicPath = path.join(__dirname, '../ios/Jaccuweather/Resources/Logic/jaccuweather-logic.js');

function loadLogic() {
  const sandbox = { console };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(logicPath, 'utf8'), sandbox);
  return sandbox.JaccuweatherLogic;
}

test('US AQI categories match the website bands', () => {
  const logic = loadLogic();
  const cases = [
    [0, 'Good', 'green'],
    [50, 'Good', 'green'],
    [50.4, 'Good', 'green'],
    [50.6, 'Moderate', 'yellow'],
    [51, 'Moderate', 'yellow'],
    [100, 'Moderate', 'yellow'],
    [101, 'Unhealthy for Sensitive Groups', 'orange'],
    [150, 'Unhealthy for Sensitive Groups', 'orange'],
    [151, 'Unhealthy', 'red'],
    [200, 'Unhealthy', 'red'],
    [201, 'Very Unhealthy', 'purple'],
    [300, 'Very Unhealthy', 'purple'],
    [301, 'Hazardous', 'maroon'],
    [500, 'Hazardous', 'maroon']
  ];
  for (const [usAqi, category, color] of cases) {
    const got = logic.usAqiDisplay({ current: { us_aqi: usAqi } });
    assert.equal(got.value, Math.round(usAqi));
    assert.equal(got.category, category);
    assert.equal(got.color, color);
  }
});

test('US AQI display is absent when the value is missing', () => {
  const logic = loadLogic();
  assert.equal(logic.usAqiDisplay(null), null);
  assert.equal(logic.usAqiDisplay({}), null);
  assert.equal(logic.usAqiDisplay({ current: {} }), null);
  assert.equal(logic.usAqiDisplay({ current: { us_aqi: null } }), null);
  assert.equal(logic.usAqiDisplay({ us_aqi: null }), null);
  assert.equal(logic.usAqiDisplay({ current: { us_aqi: Number.NaN } }), null);
  assert.equal(logic.usAqiDisplay({ current: { us_aqi: 'nope' } }), null);
});

test('Google and Tomorrow pollen keep Open-Meteo us_aqi when they omit it', () => {
  const logic = loadLogic();
  const primary = {
    current: { us_aqi: null, grass_pollen: 10, tree_pollen: 20 },
    pollen_source: 'google'
  };
  const openMeteo = {
    current: { us_aqi: 42, grass_pollen: 99 },
    pollen_source: 'open-meteo'
  };
  const merged = logic.mergeOpenMeteoUsAqi(primary, openMeteo);
  assert.equal(merged.current.us_aqi, 42);
  assert.equal(merged.current.grass_pollen, 10);
  assert.equal(merged.current.tree_pollen, 20);
  assert.equal(merged.pollen_source, 'google');
  assert.equal(primary.current.us_aqi, null);
  const shown = logic.usAqiDisplay(merged);
  assert.equal(shown.value, 42);
  assert.equal(shown.category, 'Good');
  assert.equal(shown.color, 'green');

  const kept = logic.mergeOpenMeteoUsAqi(
    { current: { us_aqi: 12 }, pollen_source: 'tomorrow' },
    openMeteo
  );
  assert.equal(kept.current.us_aqi, 12);
  assert.equal(kept.pollen_source, 'tomorrow');

  const stillMissing = logic.mergeOpenMeteoUsAqi(
    { current: { us_aqi: null }, pollen_source: 'google' },
    { current: { us_aqi: null }, pollen_source: 'open-meteo' }
  );
  assert.equal(stillMissing.current.us_aqi, null);
  assert.equal(logic.usAqiDisplay(stillMissing), null);
});
