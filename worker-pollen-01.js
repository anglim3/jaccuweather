
function hasNumericValue(value) {
  return value !== null && value !== undefined && Number.isFinite(Number(value));
}

function hasAnyUsablePollen(data) {
  if (!data?.current) return false;
  const pollenFields = ['alder_pollen','birch_pollen','olive_pollen','grass_pollen','weed_pollen','mugwort_pollen','ragweed_pollen'];
  return pollenFields.some(f => hasNumericValue(data.current[f]));
}

function googleIndexToPollenValue(indexValue) {
  // Google Pollen API returns an index (typically 0-5), not grains/m³.
  // Scale it into the app's existing pollen value shape so the current UI and
  // allergy-risk code can continue to represent unavailable values as null.
  if (!hasNumericValue(indexValue)) return null;
  return Math.max(0, Number(indexValue)) * 50;
}

function maxAvailableGoogleValue(values) {
  const availableValues = values.filter(hasNumericValue).map(Number);
  if (availableValues.length === 0) return null;
  return Math.max(...availableValues);
}

function normalizeGoogleCode(value) {
  return String(value || '').trim().toUpperCase();
}

function getGooglePollenTypeCode(info) {
  return normalizeGoogleCode(info?.code || info?.typeCode || info?.pollenType || info?.displayName);
}

function getGooglePlantCode(info) {
  return normalizeGoogleCode(info?.code || info?.plantCode || info?.displayName);
}

function googleInfoHasUsableIndex(info) {
  return info?.inSeason !== false && info?.indexInfo && hasNumericValue(info.indexInfo.value);
}

function googleInfoIsPresentWithoutIndex(info) {
  return info && !info.indexInfo;
}

function typeCodeToAppField(typeCode) {
  const normalized = normalizeGoogleCode(typeCode);
  if (normalized === 'TREE') return 'tree';
  if (normalized === 'GRASS') return 'grass';
  if (normalized === 'WEED') return 'weed';
  return null;
}

function plantCodeToAppField(plantCode) {
  const normalized = normalizeGoogleCode(plantCode);
  const plantMap = {
    ALDER: 'alder_pollen',
    BIRCH: 'birch_pollen',
    OLIVE: 'olive_pollen',
    GRAMINALES: 'grass_pollen',
    GRASS: 'grass_pollen',
    RAGWEED: 'ragweed_pollen',
    MUGWORT: 'mugwort_pollen',
  };
  return plantMap[normalized] || null;
}

function normalizeGooglePollen(googleData) {
  const dailyInfo = Array.isArray(googleData?.dailyInfo) ? googleData.dailyInfo : [];
  if (dailyInfo.length === 0) return null;

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
  const noneDisplayHourly = [];

  for (const day of dailyInfo.slice(0, 5)) {
    const date = day.date
      ? [day.date.year, String(day.date.month).padStart(2, '0'), String(day.date.day).padStart(2, '0')].join('-')
      : new Date().toISOString().split('T')[0];
    const categoryValues = { tree: null, grass: null, weed: null };
    const noneDisplayFields = {};

    for (const info of (day.pollenTypeInfo || [])) {
      const field = typeCodeToAppField(getGooglePollenTypeCode(info));
      if (!field) continue;
      if (field === 'weed' && googleInfoIsPresentWithoutIndex(info)) {
        noneDisplayFields.weed_pollen = true;
      }
      if (!googleInfoHasUsableIndex(info)) continue;
      const value = googleIndexToPollenValue(info.indexInfo.value);
      if (hasNumericValue(value)) {
        categoryValues[field] = categoryValues[field] === null ? value : Math.max(categoryValues[field], value);
      }
    }

    const plantValues = {
      alder_pollen: null,
      birch_pollen: null,
      olive_pollen: null,
      grass_pollen: null,
      weed_pollen: null,
      mugwort_pollen: null,
      ragweed_pollen: null,
    };

    for (const info of (day.plantInfo || [])) {
      const field = plantCodeToAppField(getGooglePlantCode(info));
      if (!field) continue;
      if ((field === 'weed_pollen' || field === 'ragweed_pollen') && googleInfoIsPresentWithoutIndex(info)) {
        noneDisplayFields[field] = true;
      }
      if (!googleInfoHasUsableIndex(info)) continue;
      const value = googleIndexToPollenValue(info.indexInfo.value);
      if (hasNumericValue(value)) {
        plantValues[field] = plantValues[field] === null ? value : Math.max(plantValues[field], value);
      }
    }

    plantValues.weed_pollen = categoryValues.weed;

    const normalizedDay = {
      alder_pollen: plantValues.alder_pollen ?? categoryValues.tree,
      birch_pollen: plantValues.birch_pollen ?? categoryValues.tree,
      olive_pollen: plantValues.olive_pollen ?? categoryValues.tree,
      grass_pollen: plantValues.grass_pollen ?? categoryValues.grass,
      weed_pollen: plantValues.weed_pollen,
      mugwort_pollen: plantValues.mugwort_pollen,
      ragweed_pollen: plantValues.ragweed_pollen,
    };

    for (const field of Object.keys(noneDisplayFields)) {
      if (hasNumericValue(normalizedDay[field])) {
        delete noneDisplayFields[field];
      }
    }

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
    noneDisplayHourly.push(noneDisplayFields);

    hourly.time.push(date + 'T12:00');
    for (const field of POLLEN_HOURLY_PARAMS.split(',')) {
      hourly[field].push(normalizedDay[field]);
    }
  }

  return {
