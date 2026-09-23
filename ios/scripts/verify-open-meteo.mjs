#!/usr/bin/env node
/**
 * Hits the same Open-Meteo forecast URL the iOS WeatherService builds.
 * Use this on Linux/CI where Xcode cannot compile the .xcodeproj.
 */
const LAT = process.env.LAT || '47.6062';
const LON = process.env.LON || '-122.3321';

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

const current = [
  'temperature_2m', 'relative_humidity_2m', 'apparent_temperature', 'is_day',
  'precipitation', 'weather_code', 'cloud_cover', 'surface_pressure', 'wind_speed_10m',
  'wind_direction_10m', 'wind_gusts_10m', 'uv_index', 'dew_point_2m'
].join(',');

const url = new URL('https://api.open-meteo.com/v1/forecast');
url.searchParams.set('latitude', LAT);
url.searchParams.set('longitude', LON);
url.searchParams.set('current', current);
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

(async () => {
  console.log('Forecast URL:', url.toString());
  const forecast = await get(url);
  const temp = forecast.current && forecast.current.temperature_2m;
  const code = forecast.current && forecast.current.weather_code;
  const days = (forecast.daily && forecast.daily.time) ? forecast.daily.time.length : 0;
  const hours = (forecast.hourly && forecast.hourly.time) ? forecast.hourly.time.length : 0;
  if (typeof temp !== 'number') {
    throw new Error('Open-Meteo current.temperature_2m missing');
  }
  if (days < 14) {
    throw new Error(`expected at least 14 daily rows, got ${days}`);
  }
  console.log(`OK forecast ${LAT},${LON}  current=${temp}°F  weather_code=${code}  hourly=${hours}  daily=${days}  tz=${forecast.timezone}`);

  const pollen = await get(pollenUrl);
  const aqi = pollen.current && pollen.current.us_aqi;
  console.log(`OK open-meteo pollen/AQI  us_aqi=${aqi ?? 'n/a'}  grass=${pollen.current?.grass_pollen ?? 'n/a'}`);
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
