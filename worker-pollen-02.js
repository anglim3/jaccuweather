    latitude: googleData.regionCode ? undefined : googleData.latitude,
    longitude: googleData.longitude,
    current,
    hourly,
    pollen_null_display_as_none: {
      current: noneDisplayHourly[0] || {},
      hourly: noneDisplayHourly,
    },
    pollen_source: 'google',
    pollen_units: 'Google index scaled to app pollen value range',
  };
}

function tomorrowIndexToPollenValue(indexValue) {
  // Tomorrow.io pollen indexes are ordinal values (0-5). Keep the same scaling
  // used for Google so mixed-source payloads stay in the app's expected range.
  if (!hasNumericValue(indexValue)) return null;
  return Math.max(0, Number(indexValue)) * 50;
}

function normalizeTomorrowPollen(tomorrowData) {
  const intervals = Array.isArray(tomorrowData?.data?.timelines?.[0]?.intervals)
    ? tomorrowData.data.timelines[0].intervals
    : Array.isArray(tomorrowData?.timelines?.daily)
      ? tomorrowData.timelines.daily.map(day => ({ startTime: day.time, values: day.values }))
      : [];
  if (intervals.length === 0) return null;

  const hourly = {
    time: [],
    alder_pollen: [],
    birch_pollen: [],
    olive_pollen: [],
    grass_pollen: [],
    weed_pollen: [],
    mugwort_pollen: [],
    ragweed_pollen: [],
  };

  let current = null;
  for (const interval of intervals.slice(0, 5)) {
    const values = interval.values || {};
    const normalizedDay = {
      alder_pollen: null,
      birch_pollen: null,
      olive_pollen: null,
      grass_pollen: tomorrowIndexToPollenValue(values.grassIndex),
      weed_pollen: tomorrowIndexToPollenValue(values.weedIndex),
      mugwort_pollen: null,
      ragweed_pollen: null,
    };

    if (!current) {
      current = {
        us_aqi: null,
        pm10: null,
        pm2_5: null,
        ozone: null,
        nitrogen_dioxide: null,
        sulphur_dioxide: null,
        carbon_monoxide: null,
        ...normalizedDay,
      };
    }

    hourly.time.push(interval.startTime || new Date().toISOString());
    for (const field of POLLEN_HOURLY_PARAMS.split(',')) {
      hourly[field].push(normalizedDay[field]);
    }
  }

  return {
    current,
    hourly,
    pollen_source: 'tomorrow',
    pollen_units: 'Tomorrow.io index scaled to app pollen value range',
  };
}

async function fetchTomorrowPollen(lat, lon, apiKey) {
  if (!apiKey) return null;
  const location = encodeURIComponent(lat + ',' + lon);
  const forecastUrl = `https://api.tomorrow.io/v4/weather/forecast?location=${location}&timesteps=1d&units=metric&apikey=${encodeURIComponent(apiKey)}`;
  const forecastResponse = await fetch(forecastUrl);
  if (forecastResponse.ok) {
    const forecastData = normalizeTomorrowPollen(await forecastResponse.json());
    if (hasNumericValue(forecastData?.current?.weed_pollen) || hasNumericValue(forecastData?.current?.grass_pollen)) {
      return forecastData;
    }
  }

  const timelinesUrl = `https://api.tomorrow.io/v4/timelines?location=${location}&fields=grassIndex,weedIndex&timesteps=1d&units=metric&apikey=${encodeURIComponent(apiKey)}`;
  const timelinesResponse = await fetch(timelinesUrl);
  if (!timelinesResponse.ok) {
    throw new Error(`Tomorrow.io pollen request failed with forecast status ${forecastResponse.status} and timelines status ${timelinesResponse.status}`);
  }
  return normalizeTomorrowPollen(await timelinesResponse.json());
}

function mergeMissingPollen(primary, fallback, fallbackSource) {
  if (!primary?.current || !fallback?.current) return primary;
  let usedFallback = false;
  const merged = JSON.parse(JSON.stringify(primary));
  for (const field of POLLEN_HOURLY_PARAMS.split(',')) {
    if (!hasNumericValue(merged.current[field]) && hasNumericValue(fallback.current[field])) {
      merged.current[field] = fallback.current[field];
      usedFallback = true;
    }
    if (Array.isArray(merged.hourly?.[field]) && Array.isArray(fallback.hourly?.[field])) {
      for (let i = 0; i < merged.hourly[field].length; i++) {
        if (!hasNumericValue(merged.hourly[field][i]) && hasNumericValue(fallback.hourly[field][i])) {
          merged.hourly[field][i] = fallback.hourly[field][i];
          usedFallback = true;
        }
      }
    }
  }
  if (usedFallback) {
    merged.pollen_source = (primary.pollen_source || 'primary') + '+' + fallbackSource;
    merged.pollen_fallback_source = fallbackSource;
    merged.pollen_units = [primary.pollen_units, fallback.pollen_units].filter(Boolean).join('; ');
  }
  return merged;
}

async function fetchOpenMeteoPollen(lat, lon) {
  const openMeteoUrl = `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${encodeURIComponent(lat)}&longitude=${encodeURIComponent(lon)}&current=${POLLEN_CURRENT_PARAMS}&hourly=${POLLEN_HOURLY_PARAMS}&forecast_days=5&timezone=auto`;
  const response = await fetch(openMeteoUrl, {
    headers: { 'User-Agent': 'WeatherApp/1.0 (https://weather-app.jackanglim3.workers.dev)' },
  });
  if (!response.ok) throw new Error(`Open-Meteo pollen request failed with status ${response.status}`);
  const data = await response.json();
  return { ...data, pollen_source: 'open-meteo' };
}

async function handlePollenRequest(url, env) {
  const lat = url.searchParams.get('lat') || url.searchParams.get('latitude');
  const lon = url.searchParams.get('lon') || url.searchParams.get('longitude');
  if (!lat || !lon) {
    return jsonResponse({ error: true, reason: 'Missing lat or lon parameters' }, 400);
  }

  if (env.GOOGLE_POLLEN_API_KEY) {
    try {
