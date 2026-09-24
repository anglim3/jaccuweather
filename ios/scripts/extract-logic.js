#!/usr/bin/env node
/**
 * Pulls DOM-free functions from public/app.js + pollen normalizers from
 * build.js into a single bundle the iOS app (JavaScriptCore) and Node tests share.
 */
const fs = require('fs');
const path = require('path');
const https = require('https');

const root = path.resolve(__dirname, '../..');
const outDir = path.join(root, 'ios/Jaccuweather/Resources/Logic');
fs.mkdirSync(outDir, { recursive: true });

function extractRange(source, startName, endName) {
  const start = source.search(new RegExp(`(?:async )?function ${startName}\\s*\\(`));
  if (start < 0) throw new Error('missing start ' + startName);
  const end = source.search(new RegExp(`(?:async )?function ${endName}\\s*\\(`));
  if (end < 0 || end <= start) throw new Error('missing end ' + endName + ' after ' + startName);
  return source.slice(start, end).trim();
}

const app = fs.readFileSync(path.join(root, 'public/app.js'), 'utf8');
const build = fs.readFileSync(path.join(root, 'build.js'), 'utf8');

const appSlices = [
  extractRange(app, 'averageEnsembleValues', 'sleep'),
  extractRange(app, 'isLikelyUsLocation', 'fetchWith503Retry'),
  extractRange(app, 'extractDurationHours', 'getCachedJson'),
  extractRange(app, 'formatDateYYYYMMDD', 'fetchNoaaStations'),
  extractRange(app, 'interpolateTideCurve', 'fetchTideDataForLocation'),
  extractRange(app, 'getWeatherIconFile', 'getWeatherIcon'),
  extractRange(app, 'getWeatherDescription', 'calculateMoonPhase'),
  extractRange(app, 'getAlertIconFile', 'getAlertIcon'),
  extractRange(app, 'calculateMoonPhase', 'openMoonDetailsModal'),
  extractRange(app, 'formatTime12Hour', 'formatLastUpdated'),
  extractRange(app, 'formatLastUpdatedBetween', 'recordWeatherFetchTime'),
  extractRange(app, 'parseLocationLocalIso', 'updateSunDot'),
  extractRange(app, 'hpaToInhg', 'getRiskLabel'),
  extractRange(app, 'hasPollenValue', 'updateAllergyRiskDisplay'),
  extractRange(app, 'getPollenLevel', 'displayPollenData'),
  extractRange(app, 'uvCategoryLabel', 'resetDailyChartState')
].join('\n\n');

const pollenStart = build.indexOf('function hasNumericValue');
const pollenEnd = build.indexOf('async function fetchTomorrowPollen');
if (pollenStart < 0 || pollenEnd < pollenStart) throw new Error('pollen helpers missing in build.js');
const pollenHelpers = build.slice(pollenStart, pollenEnd);

const constants = `
var HOURLY_FORECAST_HOURS = 48;
var STALE_REFETCH_AFTER_MS = 15 * 60 * 1000;
var US_BOUNDS = { minLat: 24, maxLat: 50, minLon: -125, maxLon: -66 };
var POLLEN_CURRENT_PARAMS = 'us_aqi,pm10,pm2_5,ozone,nitrogen_dioxide,sulphur_dioxide,carbon_monoxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen';
var POLLEN_HOURLY_PARAMS = 'alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen';
var POLLEN_FIELDS = ['tree_pollen','alder_pollen','birch_pollen','olive_pollen','grass_pollen','weed_pollen','mugwort_pollen','ragweed_pollen'];
var MAX_STATION_DISTANCE_KM = 50;
var MAX_COASTAL_ELEVATION_M = 20;
`;

const iosHelpers = `
function asJsDate(value) {
  if (value instanceof Date) return value;
  if (typeof value === 'number' && Number.isFinite(value)) return new Date(value);
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed : new Date();
}

// Same WMO → background class as setTheme() in public/app.js. Light appearance
// paints this class; dark appearance ignores it and keeps the static blue.
var WMO_SKY_THEMES = {
  0: 'sunny', 1: 'sunny',
  2: 'cloudy', 3: 'cloudy',
  45: 'fog', 48: 'fog',
  51: 'rainy', 53: 'rainy', 55: 'rainy',
  56: 'rainy', 57: 'rainy',
  61: 'rainy', 63: 'rainy', 65: 'rainy',
  66: 'rainy', 67: 'rainy',
  71: 'snow', 73: 'snow', 75: 'snow', 77: 'snow',
  80: 'rainy', 81: 'rainy', 82: 'storm',
  85: 'snow', 86: 'snow',
  95: 'storm', 96: 'storm', 99: 'storm'
};

function weatherSkyTheme(weatherCode, isDay) {
  const code = Number(weatherCode);
  let theme = WMO_SKY_THEMES[code] || 'cloudy';
  const day = isDay === true || isDay === 1 || isDay === '1';
  if (!day && (code === 0 || code === 1)) theme = 'clear-night';
  return theme;
}

function pollenEmoji(level) {
  switch (level) {
    case 0: return '😊';
    case 1: return '🙂';
    case 2: return '😐';
    case 3: return '😷';
    case 4: return '🤧';
    default: return '🌿';
  }
}

function circularMeanDegrees(values) {
  let sinSum = 0;
  let cosSum = 0;
  let count = 0;
  for (const value of values) {
    if (!Number.isFinite(value)) continue;
    const rad = value * Math.PI / 180;
    sinSum += Math.sin(rad);
    cosSum += Math.cos(rad);
    count++;
  }
  if (!count) return null;
  let deg = Math.atan2(sinSum, cosSum) * 180 / Math.PI;
  if (deg < 0) deg += 360;
  return deg;
}

// Member keys look like wind_direction_10m_icon_seamless_member01.
// Reject longer variable names that share the prefix (cloud_cover vs cloud_cover_low).
function ensembleMemberSeries(container, variable) {
  if (!container || !variable) return [];
  const blocked = {
    cloud_cover: ['low', 'mid', 'high'],
    wind_direction_10m: ['dominant'],
    wind_gusts_10m: ['max'],
    wind_speed_10m: ['max']
  }[variable] || [];
  const prefix = variable + '_';
  const series = [];
  for (const key of Object.keys(container)) {
    if (key !== variable && !key.startsWith(prefix)) continue;
    const tail = key === variable ? '' : key.slice(prefix.length);
    if (blocked.some((word) => tail === word || tail.startsWith(word + '_'))) continue;
    const value = container[key];
    if (Array.isArray(value)) series.push(value);
  }
  return series;
}

function aggregateMemberHours(seriesList, length, reducer) {
  if (!seriesList.length || !length) return null;
  const result = new Array(length).fill(null);
  let any = false;
  for (let i = 0; i < length; i++) {
    const values = [];
    for (const series of seriesList) {
      const value = series[i];
      if (Number.isFinite(value)) values.push(value);
    }
    if (!values.length) continue;
    result[i] = reducer(values);
    any = true;
  }
  return any ? result : null;
}

function roundSeries(series, decimals) {
  if (!series) return series;
  const factor = 10 ** decimals;
  return series.map((value) => Number.isFinite(value) ? Math.round(value * factor) / factor : value);
}

function attachNativeWindAndCloud(raw, n) {
  if (!n || !n.hourly) return;
  const hourly = raw && raw.hourly;
  const len = Array.isArray(n.hourly.time) ? n.hourly.time.length : 0;
  const gusts = aggregateMemberHours(ensembleMemberSeries(hourly, 'wind_gusts_10m'), len, averageEnsembleValues);
  const dirs = aggregateMemberHours(ensembleMemberSeries(hourly, 'wind_direction_10m'), len, circularMeanDegrees);
  if (gusts) n.hourly.wind_gusts_10m = roundSeries(gusts, 1);
  if (dirs) {
    n.hourly.wind_direction_10m = roundSeries(dirs, 0).map((value) => value === 360 ? 0 : value);
  }
  for (const name of ['cloud_cover_low', 'cloud_cover_mid', 'cloud_cover_high']) {
    if (Array.isArray(n.hourly[name]) && n.hourly[name].some((value) => Number.isFinite(value))) continue;
    const avg = aggregateMemberHours(ensembleMemberSeries(hourly, name), len, averageEnsembleValues);
    if (avg) n.hourly[name] = roundSeries(avg, 1);
  }
}

function normalizeEnsembleForNative(raw, lat, lon) {
  const n = normalizeEnsembleWeatherData(raw, lat, lon);
  attachNativeWindAndCloud(raw, n);
  const idx = nearestTimeIndex(n.hourly && n.hourly.time ? n.hourly.time : [], new Date());
  if (n.current && n.hourly) {
    if (n.hourly.is_day) n.current.is_day = n.hourly.is_day[idx];
    if (n.hourly.precipitation) n.current.precipitation = n.hourly.precipitation[idx];
    if (n.hourly.cloud_cover) n.current.cloud_cover = n.hourly.cloud_cover[idx];
    if (n.hourly.wind_direction_10m) n.current.wind_direction_10m = n.hourly.wind_direction_10m[idx];
    if (n.hourly.wind_gusts_10m) n.current.wind_gusts_10m = n.hourly.wind_gusts_10m[idx];
  }
  return n;
}

function moonTimesMs(ms, lat, lon) {
  const r = calculateMoonRiseSet(asJsDate(ms), lat, lon);
  return {
    rise: r.rise instanceof Date ? r.rise.getTime() : null,
    set: r.set instanceof Date ? r.set.getTime() : null,
    alwaysUp: !!r.alwaysUp,
    alwaysDown: !!r.alwaysDown
  };
}

function nextMoonMs(kind, ms) {
  const fn = kind === 'full' ? getNextFullMoon : getNextNewMoon;
  const r = fn(asJsDate(ms));
  return { ms: r.date instanceof Date ? r.date.getTime() : null, days: r.days };
}

function nearestTimeIndexMs(times, ms) {
  return nearestTimeIndex(times, asJsDate(ms));
}

function buildPollenForecastDays(aqiData) {
  const hourlyData = aqiData && aqiData.hourly;
  if (!hourlyData || !Array.isArray(hourlyData.time)) return [];
  const dailyData = {};
  for (let i = 0; i < hourlyData.time.length; i++) {
    const date = String(hourlyData.time[i]).split('T')[0];
    if (!dailyData[date]) {
      dailyData[date] = { date: date, tree: null, grass: null, weed: null, weedNullDisplayAsNone: false };
    }
    dailyData[date].weedNullDisplayAsNone = dailyData[date].weedNullDisplayAsNone || shouldDisplayNullPollenAsNone(aqiData, ['weed_pollen', 'mugwort_pollen', 'ragweed_pollen'], i);
    dailyData[date].tree = maxAvailablePollen([
      dailyData[date].tree,
      hourlyData.tree_pollen && hourlyData.tree_pollen[i],
      hourlyData.alder_pollen && hourlyData.alder_pollen[i],
      hourlyData.birch_pollen && hourlyData.birch_pollen[i],
      hourlyData.olive_pollen && hourlyData.olive_pollen[i]
    ]);
    dailyData[date].grass = maxAvailablePollen([
      dailyData[date].grass,
      hourlyData.grass_pollen && hourlyData.grass_pollen[i]
    ]);
    dailyData[date].weed = maxAvailablePollen([
      dailyData[date].weed,
      hourlyData.weed_pollen && hourlyData.weed_pollen[i],
      hourlyData.mugwort_pollen && hourlyData.mugwort_pollen[i],
      hourlyData.ragweed_pollen && hourlyData.ragweed_pollen[i]
    ]);
  }
  return Object.keys(dailyData).slice(0, 5).map(function (dateStr, index) {
    const data = dailyData[dateStr];
    const treeLevel = getPollenLevel(data.tree);
    const grassLevel = getPollenLevel(data.grass);
    const weedLevel = getPollenLevel(data.weed, { displayNullAsNone: data.weedNullDisplayAsNone });
    const overall = Math.max(treeLevel.level || 0, grassLevel.level || 0, weedLevel.level || 0);
    return {
      date: dateStr,
      index: index,
      tree: data.tree,
      grass: data.grass,
      weed: data.weed,
      treeLabel: treeLevel.label,
      grassLabel: grassLevel.label,
      weedLabel: weedLevel.label,
      emoji: pollenEmoji(overall)
    };
  });
}
`;

const exportsBlock = `
var JaccuweatherLogic = {
  normalizeEnsembleWeatherData: normalizeEnsembleWeatherData,
  normalizeEnsembleForNative: normalizeEnsembleForNative,
  getWeatherIconFile: getWeatherIconFile,
  getWeatherDescription: getWeatherDescription,
  getAlertIconFile: getAlertIconFile,
  calculateMoonPhase: function (ms) { return calculateMoonPhase(asJsDate(ms)); },
  getMoonPhase: getMoonPhase,
  getMoonIllumination: function (ms) { return getMoonIllumination(asJsDate(ms)); },
  calculateMoonDistance: function (ms, lat, lon) { return calculateMoonDistance(asJsDate(ms), lat, lon); },
  calculateMoonRiseSet: calculateMoonRiseSet,
  moonTimesMs: moonTimesMs,
  getNextFullMoon: function (ms) { return nextMoonMs('full', ms); },
  getNextNewMoon: function (ms) { return nextMoonMs('new', ms); },
  formatIsoLocalClock: formatIsoLocalClock,
  formatInstantInLocation: formatInstantInLocation,
  formatTime12Hour: formatTime12Hour,
  formatLastUpdatedBetween: formatLastUpdatedBetween,
  shouldRefetchStaleForecast: shouldRefetchStaleForecast,
  parseLocationLocalIso: parseLocationLocalIso,
  nearestTimeIndex: nearestTimeIndexMs,
  hpaToInhg: hpaToInhg,
  calculateDailyAveragesForDateString: calculateDailyAveragesForDateString,
  getAverageHourlyValueForDate: getAverageHourlyValueForDate,
  calculateSinusRisk: calculateSinusRisk,
  getPressureTrend: getPressureTrend,
  getSinusDrivers: getSinusDrivers,
  getSimpleRiskLabel: getSimpleRiskLabel,
  calculateAllergyRisk: calculateAllergyRisk,
  getAllergyDrivers: getAllergyDrivers,
  getNiceWeatherBreakdown: getNiceWeatherBreakdown,
  getNiceWeatherLabel: getNiceWeatherLabel,
  getPollenLevel: getPollenLevel,
  maxAvailablePollen: maxAvailablePollen,
  hasAnyPollenData: hasAnyPollenData,
  formatPollenValue: formatPollenValue,
  shouldDisplayNullPollenAsNone: shouldDisplayNullPollenAsNone,
  buildPollenForecastDays: buildPollenForecastDays,
  uvCategoryLabel: uvCategoryLabel,
  weatherSkyTheme: weatherSkyTheme,
  maxHourlyUvForDateString: maxHourlyUvForDateString,
  normalizeGooglePollen: normalizeGooglePollen,
  normalizeTomorrowPollen: normalizeTomorrowPollen,
  hasAnyUsablePollen: hasAnyUsablePollen,
  haversineKm: haversineKm,
  normalizeNoaaStations: normalizeNoaaStations,
  interpolateTideCurve: interpolateTideCurve,
  buildTideDailySummaries: buildTideDailySummaries,
  parseNoaaPredictionRow: parseNoaaPredictionRow,
  isLikelyUsLocation: isLikelyUsLocation,
  extractDurationHours: extractDurationHours,
  overlapHours: overlapHours,
  HOURLY_FORECAST_HOURS: HOURLY_FORECAST_HOURS,
  STALE_REFETCH_AFTER_MS: STALE_REFETCH_AFTER_MS
};
if (typeof module !== 'undefined' && module.exports) module.exports = JaccuweatherLogic;
`;

function download(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return download(res.headers.location).then(resolve, reject);
      }
      if (res.statusCode !== 200) return reject(new Error('HTTP ' + res.statusCode + ' ' + url));
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    }).on('error', reject);
  });
}

(async () => {
  let suncalc = '';
  const vendorPath = path.join(outDir, 'suncalc.js');
  if (fs.existsSync(vendorPath)) {
    suncalc = fs.readFileSync(vendorPath, 'utf8');
  } else {
    suncalc = await download('https://cdn.jsdelivr.net/npm/suncalc@1.9.0/suncalc.js');
    fs.writeFileSync(vendorPath, suncalc);
  }
  // JavaScriptCore and Node both need a global SunCalc; the CDN build uses `window`.
  suncalc = suncalc.replace(
    /else window\.SunCalc = SunCalc;/,
    'else { var g = (typeof globalThis !== "undefined") ? globalThis : this; g.SunCalc = SunCalc; }'
  );
  suncalc = suncalc.replace(
    /if \(typeof exports === 'object' && typeof module !== 'undefined'\) module\.exports = SunCalc;/,
    'var gSun = (typeof globalThis !== "undefined") ? globalThis : this; gSun.SunCalc = SunCalc;\n' +
      "if (typeof exports === 'object' && typeof module !== 'undefined') module.exports = SunCalc;"
  );

  const body = [
    '/* Auto-generated by ios/scripts/extract-logic.js — do not edit by hand. */',
    suncalc,
    constants,
    appSlices,
    pollenHelpers,
    iosHelpers,
    exportsBlock
  ].join('\n\n');

  const out = path.join(outDir, 'jaccuweather-logic.js');
  fs.writeFileSync(out, body);
  console.log('Wrote', out, body.length, 'bytes');
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
