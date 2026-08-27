const POLLEN_CURRENT_PARAMS = 'us_aqi,pm10,pm2_5,ozone,nitrogen_dioxide,sulphur_dioxide,carbon_monoxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen';
const POLLEN_HOURLY_PARAMS = 'alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen';

function jsonResponse(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...extraHeaders,
    },
  });
}

function isSameOriginRequest(request, requestUrl) {
  const allowedOrigin = requestUrl.origin;
  const origin = request.headers.get('Origin');
  if (origin) {
    return origin === allowedOrigin;
  }
  const fetchSite = request.headers.get('Sec-Fetch-Site');
  if (fetchSite) {
    return fetchSite === 'same-origin';
  }
  const referer = request.headers.get('Referer');
  if (referer) {
    try {
      return new URL(referer).origin === allowedOrigin;
    } catch (error) {
      return false;
    }
  }
  return false;
}
