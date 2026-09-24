const test = require('node:test');
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const logicPath = path.join(root, 'ios/Jaccuweather/Resources/Logic/jaccuweather-logic.js');
const appJs = fs.readFileSync(path.join(root, 'public/app.js'), 'utf8');

function loadLogic() {
  const sandbox = { console, setTimeout, clearTimeout };
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(logicPath, 'utf8'), sandbox);
  assert.ok(sandbox.JaccuweatherLogic, 'extracted logic must export JaccuweatherLogic');
  assert.equal(typeof sandbox.SunCalc.getMoonTimes, 'function');
  return sandbox.JaccuweatherLogic;
}

function ensembleFixture() {
  const times = [
    '2026-06-01T12:00',
    '2026-06-01T13:00',
    '2026-06-01T14:00'
  ];
  const days = ['2026-06-01'];
  return {
    latitude: 47.6,
    longitude: -122.3,
    utc_offset_seconds: -25200,
    timezone: 'America/Los_Angeles',
    elevation: 10,
    hourly: {
      time: times,
      temperature_2m_icon_seamless: [60, 62, 64],
      temperature_2m_gfs_seamless: [66, 68, 70],
      temperature_2m_ecmwf_ifs025: [63, 65, 67],
      weather_code_icon_seamless: [63, 63, 3],
      weather_code_gfs_seamless: [61, 63, 2],
      weather_code_ecmwf_ifs025: [80, 3, 1],
      precipitation_icon_seamless: [0.2, 0, 0],
      precipitation_gfs_seamless: [0.1, 0, 0],
      precipitation_ecmwf_ifs025: [0.15, 0, 0],
      precipitation_probability_icon_seamless: [80, 10, 5],
      relative_humidity_2m_icon_seamless: [70, 68, 66],
      relative_humidity_2m_gfs_seamless: [72, 70, 68],
      wind_speed_10m_icon_seamless: [8, 9, 10],
      wind_speed_10m_gfs_seamless: [10, 11, 12],
      is_day_icon_seamless: [1, 1, 1],
      apparent_temperature_icon_seamless: [58, 60, 62],
      dew_point_2m_icon_seamless: [50, 51, 52],
      uv_index_icon_seamless: [6, 7, 8],
      surface_pressure_icon_seamless: [1012, 1013, 1014],
      cloud_cover_icon_seamless: [80, 40, 20]
    },
    daily: {
      time: days,
      weather_code_icon_seamless: [63],
      weather_code_gfs_seamless: [61],
      weather_code_ecmwf_ifs025: [80],
      temperature_2m_max_icon_seamless: [70],
      temperature_2m_max_gfs_seamless: [74],
      temperature_2m_min_icon_seamless: [50],
      temperature_2m_min_gfs_seamless: [52],
      precipitation_sum_icon_seamless: [0.2],
      precipitation_sum_gfs_seamless: [0.1],
      wind_speed_10m_max_icon_seamless: [12],
      sunrise_icon_seamless: ['2026-06-01T05:20'],
      sunset_icon_seamless: ['2026-06-01T20:50']
    }
  };
}

test('extracted logic bundle exists and loads', () => {
  assert.ok(fs.existsSync(logicPath));
  const logic = loadLogic();
  assert.equal(typeof logic.normalizeEnsembleWeatherData, 'function');
  assert.equal(typeof logic.normalizeEnsembleForNative, 'function');
});

test('ensemble averaging matches web normalizeEnsembleWeatherData (mean temp, medianFloor WMO)', () => {
  const logic = loadLogic();
  const normalized = logic.normalizeEnsembleWeatherData(ensembleFixture(), 47.6, -122.3);
  assert.equal(normalized.hourly.temperature_2m[0], 63); // (60+66+63)/3
  // weather codes 63, 61, 80 → sorted 61,63,80 medianFloor 63
  assert.equal(normalized.hourly.weather_code[0], 63);
  assert.equal(normalized.daily.sunrise[0], '2026-06-01T05:20');
  assert.equal(normalized.current.dewpoint_2m !== undefined, true);
  const native = logic.normalizeEnsembleForNative(ensembleFixture(), 47.6, -122.3);
  assert.equal(native.hourly.temperature_2m[0], normalized.hourly.temperature_2m[0]);
  assert.ok(native.current.is_day === 0 || native.current.is_day === 1 || native.current.is_day === true || native.current.is_day === false || typeof native.current.is_day === 'number');
});

test('14-day WMO mapping + 30% rain downgrade match web getWeatherIconFile', () => {
  const logic = loadLogic();
  assert.equal(logic.getWeatherIconFile(63, true), 'overcast-day-rain.svg');
  assert.equal(logic.getWeatherIconFile(63, true, 30), 'partly-cloudy-day.svg');
  assert.equal(logic.getWeatherIconFile(63, true, 31), 'overcast-day-rain.svg');
  assert.equal(logic.getWeatherIconFile(2, false), 'partly-cloudy-night.svg');
  assert.equal(logic.getWeatherDescription(95), 'Thunderstorm');
});

test('NWS alert icons use Meteocons alarm set', () => {
  const logic = loadLogic();
  assert.equal(logic.getAlertIconFile('Tornado Warning'), 'tornado.svg');
  assert.equal(logic.getAlertIconFile('Heat Advisory'), 'sun-hot.svg');
  assert.equal(logic.getAlertIconFile('Winter Storm Watch'), 'snowflake.svg');
  assert.equal(logic.getAlertIconFile('Something else'), 'weather-alarm.svg');
  const dir = path.join(root, 'ios/Jaccuweather/Resources/Icons/alerts');
  for (const file of ['tornado.svg', 'sun-hot.svg', 'snowflake.svg', 'weather-alarm.svg']) {
    assert.ok(fs.existsSync(path.join(dir, file)), file);
  }
});

test('Google TREE category does not invent alder/birch/olive species', () => {
  const logic = loadLogic();
  const normalized = logic.normalizeGooglePollen({
    dailyInfo: [{
      date: { year: 2026, month: 6, day: 1 },
      pollenTypeInfo: [
        { code: 'TREE', indexInfo: { value: 2 } },
        { code: 'GRASS', indexInfo: { value: 4 } }
      ],
      plantInfo: []
    }]
  });
  assert.equal(normalized.current.tree_pollen, 100);
  assert.equal(normalized.current.alder_pollen, null);
  assert.equal(normalized.current.birch_pollen, null);
  assert.equal(normalized.current.olive_pollen, null);
  assert.equal(normalized.current.grass_pollen, 200);
  assert.equal(normalized.pollen_source, 'google');
});

test('pollen 5-day grouping uses daily max of hourly species like the website', () => {
  const logic = loadLogic();
  const days = logic.buildPollenForecastDays({
    hourly: {
      time: ['2026-06-01T00:00', '2026-06-01T12:00', '2026-06-02T00:00'],
      grass_pollen: [10, 40, 5],
      alder_pollen: [null, 80, null],
      tree_pollen: [20, 30, 10],
      ragweed_pollen: [null, null, 2]
    }
  });
  assert.equal(days.length, 2);
  assert.equal(days[0].grass, 40);
  assert.equal(days[0].tree, 80);
});

test('sinus / allergy / nice-weather scoring functions are the website functions', () => {
  const logic = loadLogic();
  const sinus = logic.calculateSinusRisk(-2, 80, 0.4, 25);
  assert.equal(sinus, 4);
  assert.equal(logic.getSimpleRiskLabel(sinus).label, 'High');
  const allergy = logic.calculateAllergyRisk(5, 0, {
    current: { grass_pollen: 250, tree_pollen: null, weed_pollen: null, alder_pollen: null, birch_pollen: null, olive_pollen: null, mugwort_pollen: null, ragweed_pollen: null }
  });
  assert.ok(allergy >= 3);
  const todayAvg = { avgTemp: 72, avgHumidity: 50, precipSum: 0, windMax: 8 };
  const data = {
    current: { uv_index: 5 },
    daily: { precipitation_probability_max: [10], weather_code: [1], time: ['2026-06-01'] },
    hourly: { time: ['2026-06-01T12:00'], cloud_cover: [30] }
  };
  const nice = logic.getNiceWeatherBreakdown(data, todayAvg, 0);
  assert.equal(nice.score, 10);
  assert.equal(logic.getNiceWeatherLabel(10).label, 'Excellent');
});

test('moon rise/set instants format in city timezone offset', () => {
  const logic = loadLogic();
  const ms = Date.UTC(2026, 5, 1, 12, 0, 0);
  const label = logic.formatInstantInLocation(ms, -7 * 3600);
  assert.equal(label, '5:00 AM');
  const times = logic.moonTimesMs(ms, 47.6062, -122.3321);
  assert.ok(times.rise === null || Number.isFinite(times.rise));
  assert.ok(times.set === null || Number.isFinite(times.set));
});

test('stale-tab refresh uses the same 15-minute helper as the website', () => {
  const logic = loadLogic();
  const now = 1_000_000;
  assert.equal(logic.shouldRefetchStaleForecast(now, now - 14 * 60 * 1000, 15 * 60 * 1000), false);
  assert.equal(logic.shouldRefetchStaleForecast(now, now - 16 * 60 * 1000, 15 * 60 * 1000), true);
  assert.equal(logic.STALE_REFETCH_AFTER_MS, 15 * 60 * 1000);
});

test('UV category labels match the website', () => {
  const logic = loadLogic();
  assert.equal(logic.uvCategoryLabel(1), 'Low');
  assert.equal(logic.uvCategoryLabel(4), 'Moderate');
  assert.equal(logic.uvCategoryLabel(7), 'High');
  assert.equal(logic.uvCategoryLabel(9), 'Very high');
  assert.equal(logic.uvCategoryLabel(12), 'Extreme');
});

test('iOS ensemble URL matches public/app.js fetchWeather()', () => {
  const match = appJs.match(/https:\/\/ensemble-api\.open-meteo\.com\/v1\/ensemble\?[^`]+/);
  assert.ok(match, 'fetchWeather ensemble URL');
  const web = match[0];
  assert.match(web, /models=icon_seamless,gfs_seamless,ecmwf_ifs025/);
  assert.match(web, /uv_index/);
  assert.match(web, /forecast_days=14/);
  assert.match(web, /past_days=2/);
  const endpoints = fs.readFileSync(path.join(root, 'ios/Jaccuweather/Services/APIEndpoints.swift'), 'utf8');
  assert.match(endpoints, /ensemble-api\.open-meteo\.com\/v1\/ensemble/);
  assert.match(endpoints, /icon_seamless,gfs_seamless,ecmwf_ifs025/);
});

test('Ventusky Safari URL matches lockdown-era website', () => {
  const match = appJs.match(/https:\/\/www\.ventusky\.com\/\?p=\$\{[^}]+\}/);
  assert.ok(match);
  const endpoints = fs.readFileSync(path.join(root, 'ios/Jaccuweather/Services/APIEndpoints.swift'), 'utf8');
  assert.match(endpoints, /https:\/\/www\.ventusky\.com\/\?p=/);
  const radar = fs.readFileSync(path.join(root, 'ios/Jaccuweather/Views/RadarView.swift'), 'utf8');
  assert.match(radar, /Open Ventusky radar/);
  assert.match(radar, /Link\("Open Ventusky radar"/);
  assert.doesNotMatch(radar, /WKWebView\(/);
});

test('NWS WMS overlay uses RIDGE2 nexrad-n0q-wmst EPSG:3857', () => {
  const overlay = fs.readFileSync(path.join(root, 'ios/Jaccuweather/Services/NWSRadarOverlay.swift'), 'utf8');
  const endpoints = fs.readFileSync(path.join(root, 'ios/Jaccuweather/Services/APIEndpoints.swift'), 'utf8');
  assert.match(endpoints, /opengeo\.ncep\.noaa\.gov/);
  assert.match(overlay, /APIEndpoints\.nwsWms/);
  assert.match(overlay, /nexrad-n0q-wmst/);
  assert.match(overlay, /EPSG:3857/);
});

test('Secrets.xcconfig keeps pollen keys blank and documents NWS User-Agent', () => {
  const secrets = fs.readFileSync(path.join(root, 'ios/Jaccuweather/Config/Secrets.xcconfig'), 'utf8');
  assert.match(secrets, /GOOGLE_POLLEN_API_KEY\s*=\s*$/m);
  assert.match(secrets, /TOMORROW_API_KEY\s*=\s*$/m);
  assert.match(secrets, /NWS_USER_AGENT\s*=/);
  assert.doesNotMatch(secrets, /AIza/);
  const plist = fs.readFileSync(path.join(root, 'ios/Jaccuweather/Info.plist'), 'utf8');
  assert.match(plist, /\$\(NWS_USER_AGENT\)/);
});

test('Xcode copies Logic and Icons to the app root, not a Resources folder', () => {
  const pbx = fs.readFileSync(path.join(root, 'ios/Jaccuweather.xcodeproj/project.pbxproj'), 'utf8');
  const gen = fs.readFileSync(path.join(root, 'ios/scripts/generate-xcodeproj.js'), 'utf8');
  assert.match(pbx, /name = Logic; path = Resources\/Logic;/);
  assert.match(pbx, /name = Icons; path = Resources\/Icons;/);
  assert.match(pbx, /Logic in Resources/);
  assert.match(pbx, /Icons in Resources/);
  assert.doesNotMatch(pbx, /path = Resources;/);
  assert.doesNotMatch(pbx, /Resources in Resources/);
  assert.match(gen, /name = Logic; path = Resources\/Logic;/);
  assert.match(gen, /name = Icons; path = Resources\/Icons;/);
  assert.doesNotMatch(gen, /path = Resources;/);
  assert.match(pbx, /DEVELOPMENT_TEAM = "";/);
  assert.ok(fs.existsSync(path.join(root, 'ios/Jaccuweather/Resources/Logic/jaccuweather-logic.js')));
  assert.ok(fs.existsSync(path.join(root, 'ios/Jaccuweather/Resources/Icons/weather')));
});

test('native ensemble keeps cloud layers and circular-mean wind', () => {
  const logic = loadLogic();
  const raw = ensembleFixture();
  raw.hourly.cloud_cover_low_icon_seamless = [10, 20, 30];
  raw.hourly.cloud_cover_low_gfs_seamless = [30, 40, 50];
  raw.hourly.cloud_cover_mid_icon_seamless = [40, 50, 60];
  raw.hourly.cloud_cover_high_ecmwf_ifs025 = [70, 80, 90];
  raw.hourly.wind_direction_10m_icon_seamless = [350, 0, 90];
  raw.hourly.wind_direction_10m_gfs_seamless = [10, 0, 90];
  raw.hourly.wind_gusts_10m_icon_seamless = [12, 14, 16];
  raw.hourly.wind_gusts_10m_gfs_seamless = [8, 10, 20];
  const native = logic.normalizeEnsembleForNative(raw, 47.6, -122.3);
  assert.equal(native.hourly.cloud_cover_low[0], 20);
  assert.equal(native.hourly.cloud_cover_mid[0], 40);
  assert.equal(native.hourly.cloud_cover_high[0], 70);
  assert.equal(native.hourly.wind_direction_10m[0], 0);
  assert.equal(native.hourly.wind_direction_10m[2], 90);
  assert.equal(native.hourly.wind_gusts_10m[0], 10);
  assert.equal(native.hourly.wind_gusts_10m[1], 12);
});

test('light-mode sky class matches website setTheme WMO map', () => {
  const logic = loadLogic();
  assert.equal(logic.weatherSkyTheme(0, 1), 'sunny');
  assert.equal(logic.weatherSkyTheme(0, 0), 'clear-night');
  assert.equal(logic.weatherSkyTheme(1, false), 'clear-night');
  assert.equal(logic.weatherSkyTheme(3, 1), 'cloudy');
  assert.equal(logic.weatherSkyTheme(45, 1), 'fog');
  assert.equal(logic.weatherSkyTheme(63, 0), 'rainy');
  assert.equal(logic.weatherSkyTheme(82, 1), 'storm');
  assert.equal(logic.weatherSkyTheme(73, 1), 'snow');
  assert.equal(logic.weatherSkyTheme(95, 0), 'storm');
  assert.equal(logic.weatherSkyTheme(999, 1), 'cloudy');
  const block = appJs.slice(appJs.indexOf('const WMO_THEMES'), appJs.indexOf('function setTheme'));
  assert.match(block, /0:\s*'sunny'/);
  assert.match(block, /82:\s*'storm'/);
  assert.match(appJs, /if \(!isDay && \(weatherCode === 0 \|\| weatherCode === 1\)\) theme = 'clear-night'/);
});

test('1024 app icon and vendored Meteocons copies are present', () => {
  const icon = path.join(root, 'ios/Jaccuweather/Assets.xcassets/AppIcon.appiconset/AppIcon.png');
  assert.ok(fs.existsSync(icon));
  const buf = fs.readFileSync(icon);
  assert.equal(buf.readUInt32BE(16), 1024);
  assert.equal(buf.readUInt32BE(20), 1024);
  const weatherDir = path.join(root, 'ios/Jaccuweather/Resources/Icons/weather');
  const publicWeather = path.join(root, 'public/icons/weather');
  const publicFiles = fs.readdirSync(publicWeather).filter((f) => f.endsWith('.svg'));
  for (const file of publicFiles) {
    assert.ok(fs.existsSync(path.join(weatherDir, file)), `ios missing weather icon ${file}`);
  }
});
