      // Google Maps Platform Pollen API daily forecast endpoint:
      // https://pollen.googleapis.com/v1/forecast:lookup
      const googleUrl = `https://pollen.googleapis.com/v1/forecast:lookup?key=${encodeURIComponent(env.GOOGLE_POLLEN_API_KEY)}&location.latitude=${encodeURIComponent(lat)}&location.longitude=${encodeURIComponent(lon)}&days=5&plantsDescription=false`;
      const googleResponse = await fetch(googleUrl);
      if (googleResponse.ok) {
        const googleData = await googleResponse.json();
        const normalized = normalizeGooglePollen(googleData);
        if (normalized?.current && hasAnyUsablePollen(normalized)) {
          // Check for missing weed/ragweed for diagnostics
          if (!hasNumericValue(normalized.current.weed_pollen) || !hasNumericValue(normalized.current.ragweed_pollen)) {
            const firstDay = Array.isArray(googleData.dailyInfo) ? googleData.dailyInfo[0] : null;
            const pollenTypeSummary = (firstDay?.pollenTypeInfo || []).map(info => ({
              code: getGooglePollenTypeCode(info),
              inSeason: info.inSeason ?? null,
              hasIndexInfo: Boolean(info.indexInfo),
              indexValue: info.indexInfo?.value ?? null,
              category: info.indexInfo?.category ?? null,
            }));
            const plantSummary = (firstDay?.plantInfo || [])
              .filter(info => ['RAGWEED', 'MUGWORT'].includes(getGooglePlantCode(info)) || info?.plantDescription?.type === 'WEED')
              .map(info => ({
                code: getGooglePlantCode(info),
                type: info.plantDescription?.type ?? null,
                inSeason: info.inSeason ?? null,
                hasIndexInfo: Boolean(info.indexInfo),
                indexValue: info.indexInfo?.value ?? null,
                category: info.indexInfo?.category ?? null,
              }));
            console.warn('Google pollen weed/ragweed unavailable in first day', JSON.stringify({ pollenTypeSummary, plantSummary }));
          }
          return jsonResponse(normalized, 200, { 'X-Pollen-Source': normalized.pollen_source || 'google' });
        }
      } else {
        console.warn('Google Pollen API unavailable; falling back to Open-Meteo. Status:', googleResponse.status);
      }
    } catch (error) {
      console.warn('Google Pollen API failed; falling back to Open-Meteo:', error.message);
    }
  }

  if (env.TOMORROW_API_KEY) {
    try {
      const tomorrowData = await fetchTomorrowPollen(lat, lon, env.TOMORROW_API_KEY);
      if (tomorrowData?.current) {
        return jsonResponse(tomorrowData, 200, { 'X-Pollen-Source': tomorrowData.pollen_source || 'tomorrow' });
      }
    } catch (error) {
      console.warn('Tomorrow.io pollen fallback failed; falling back to Open-Meteo:', error.message);
    }
  }

  try {
    const openMeteoData = await fetchOpenMeteoPollen(lat, lon);
    return jsonResponse(openMeteoData, 200, { 'X-Pollen-Source': 'open-meteo' });
  } catch (error) {
    console.error('Open-Meteo pollen fallback failed:', error.message);
    return jsonResponse({ error: true, reason: 'Pollen data unavailable' }, 503);
  }
}
