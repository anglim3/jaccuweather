#!/usr/bin/env node
/**
 * Hits the same Open-Meteo ensemble URL the iOS WeatherService / website fetchWeather() build.
 * Use this on Linux/CI where Xcode cannot compile the .xcodeproj.
 */
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const LAT = process.env.LAT || '47.6062';
const LON = process.env.LON || '-122.3321';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

const hourly = [
  'temperature_2m', 'relative_humidity_2m', 'weather_code', 'wind_speed_10m',
  'wind_direction_10m', 'wind_gusts_10m', 'precipitation_probability', 'precipitation',
  'snowfall', 'surface_pressure', 'cloud_cover', 'cloud_cover_low', 'cloud_cover_mid',
  'cloud_cover_high', 'shortwave_radiation', 'is_day', 'apparent_temperature',
  'dew_point_2m', 'uv_index'
].join(',');

const daily = [
  'weather_code', 'temperature_2m_max', 'temperature_2m_min', 'apparent_temperature_max',
  'apparent_temperature_min', 'precipitation_sum', 'wind_speed_10m_max',
  'wind_direction_10m_dominant', 'wind_gusts_10m_max', 'precipitation_probability_max',
  'snowfall_sum', 'uv_index_max', 'sunrise', 'sunset'
].join(',');

const url = new URL('https://ensemble-api.open-meteo.com/v1/ensemble');
url.searchParams.set('latitude', LAT);
url.searchParams.set('longitude', LON);
url.searchParams.set('models', 'icon_seamless,gfs_seamless,ecmwf_ifs025');
url.searchParams.set('hourly', hourly);
url.searchParams.set('daily', daily);
url.searchParams.set('forecast_days', '14');
url.searchParams.set('past_days', '2');
url.searchParams.set('temperature_unit', 'fahrenheit');
url.searchParams.set('windspeed_unit', 'mph');
url.searchParams.set('precipitation_unit', 'inch');
url.searchParams.set('timezone', 'auto');

const pollenUrl = new URL('https://air-quality-api.open-meteo.com/v1/air-quality');
pollenUrl.searchParams.set('latitude', LAT);
pollenUrl.searchParams.set('longitude', LON);
pollenUrl.searchParams.set('current', 'us_aqi,pm10,pm2_5,ozone,nitrogen_dioxide,sulphur_dioxide,carbon_monoxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen');
pollenUrl.searchParams.set('hourly', 'alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen');
pollenUrl.searchParams.set('forecast_days', '5');
pollenUrl.searchParams.set('timezone', 'auto');

async function get(target) {
  const response = await fetch(target, {
    headers: { 'User-Agent': 'JaccuweatherPersonal/1.0 (https://github.com/anglim3/jaccuweather)' }
  });
  if (!response.ok) {
    throw new Error(`${target.origin} HTTP ${response.status}`);
  }
  return response.json();
}

function loadLogic() {
  const sandbox = { console, setTimeout, clearTimeout };
  vm.createContext(sandbox);
  vm.runInContext(
    fs.readFileSync(path.join(root, 'ios/Jaccuweather/Resources/Logic/jaccuweather-logic.js'), 'utf8'),
    sandbox
  );
  return sandbox.JaccuweatherLogic;
}

(async () => {
  console.log('Ensemble URL:', url.toString());
  const raw = await get(url);
  const logic = loadLogic();
  const weather = logic.normalizeEnsembleWeatherData(raw, Number(LAT), Number(LON));
  const temp = weather.current && weather.current.temperature_2m;
  const code = weather.current && weather.current.weather_code;
  const days = weather.daily && weather.daily.time ? weather.daily.time.length : 0;
  const hours = weather.hourly && weather.hourly.time ? weather.hourly.time.length : 0;
  if (typeof temp !== 'number') {
    throw new Error('normalized current.temperature_2m missing');
  }
  if (days < 14) {
    throw new Error(`expected at least 14 daily rows, got ${days}`);
  }
  if (!Array.isArray(weather.hourly.weather_code) || weather.hourly.weather_code.length !== hours) {
    throw new Error('ensemble weather_code series missing after normalize');
  }
  console.log(`OK ensemble ${LAT},${LON}  current=${temp}°F  weather_code=${code}  hourly=${hours}  daily=${days}  tz=${weather.timezone}`);

  const pollen = await get(pollenUrl);
  const aqi = pollen.current && pollen.current.us_aqi;
  console.log(`OK open-meteo pollen/AQI  us_aqi=${aqi ?? 'n/a'}  grass=${pollen.current?.grass_pollen ?? 'n/a'}`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
