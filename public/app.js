// ─── Dark/Light theme toggle ────────────────────────────
// Dark mode (default) = static deep-blue background (the loading/skeleton color)
// Light mode = weather-reactive dynamic gradients (sunny, cloudy, rainy, etc.)
function initThemeToggle() {
    const btn = document.getElementById('themeToggleBtn');
    const icon = document.getElementById('themeIcon');
    if (!btn || !icon) return;

    // Load saved theme or default to dark
    const saved = localStorage.getItem('jaccuweather-theme');
    if (saved === 'light') {
        document.documentElement.setAttribute('data-theme', 'light');
        icon.className = 'fas fa-moon text-sm';
    } else {
        document.documentElement.removeAttribute('data-theme');
        icon.className = 'fas fa-sun text-sm';
    }

    btn.addEventListener('click', () => {
        const isLight = document.documentElement.getAttribute('data-theme') === 'light';
        if (isLight) {
            // Switch to dark: strip weather theme, back to static deep-blue
            document.documentElement.removeAttribute('data-theme');
            localStorage.setItem('jaccuweather-theme', 'dark');
            icon.className = 'fas fa-sun text-sm';
            const bgLayer = document.getElementById('bgLayer');
            if (bgLayer) bgLayer.className = 'bg-layer';
        } else {
            // Switch to light: apply weather-reactive gradient
            document.documentElement.setAttribute('data-theme', 'light');
            localStorage.setItem('jaccuweather-theme', 'light');
            icon.className = 'fas fa-moon text-sm';
            // Re-apply weather theme if we have weather data
            if (currentWeatherData && currentWeatherData.current) {
                setTheme(currentWeatherData.current.weather_code, currentWeatherData.current.is_day !== 0);
            }
        }
    });
}

// Initialize theme toggle on DOM ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initThemeToggle);
} else {
    initThemeToggle();
}

let currentLat = null;
let currentLon = null;
let currentLocationName = null;
let currentWeatherData = null; // Store full weather data for modals
let favorites = []; // Array of favorite locations
let hourlyChart = {};
let dailyChart = {};
let currentTideData = null;
let searchDebounceTimer = null;
let searchSuggestions = [];
let selectedSuggestionIndex = -1;
let blurHideTimer = null;
let activeSuggestionRequestId = 0;
// Layer switching removed - Ventusky handles layers internally

const HOURLY_FORECAST_HOURS = 48;
const UNITS = {
    temperature: '\u00b0F',
    wind: 'mph',
    humidity: '%',
    precipitation: 'in',
    snowfall: 'in',
    pressure: 'inHg',
    uv: ''
};

const NOAA_STATIONS_URL = 'https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions';
const NOAA_DATAGETTER_URL = 'https://api.tidesandcurrents.noaa.gov/api/prod/datagetter';
const TIDE_CACHE_VERSION = 'v2';
const NOAA_STATIONS_CACHE_KEY = `${TIDE_CACHE_VERSION}_noaa_tide_stations_cache`;
const NOAA_STATIONS_CACHE_MS = 7 * 24 * 60 * 60 * 1000;
const NOAA_PREDICTIONS_CACHE_MS = 24 * 60 * 60 * 1000;
const MAX_STATION_DISTANCE_KM = 50;
const MAX_COASTAL_ELEVATION_M = 20;

const US_BOUNDS = {
    minLat: 24,
    maxLat: 50,
    minLon: -125,
    maxLon: -66
};

// ── ApexCharts shared base options ──
function baseChartOptions(overrides = {}) {
    // Extract categories from overrides without clobbering base label settings
    const xaxisCategories = overrides.xaxis?.categories;
    const xaxisTickAmount = overrides.xaxis?.tickAmount;

    // Mobile-specific chart optimizations
    // Docs: https://apexcharts.com/docs/options/chart/
    const isMobile = window.innerWidth <= 768;
    const baseTickAmount = isMobile ? 4 : 6;
    const baseChartHeight = isMobile ? 250 : 300;

    const opts = {
        chart: {
            type: 'area',
            background: 'transparent',
            foreColor: '#fff',
            toolbar: { show: false },
            animations: {
                enabled: true,
                easing: 'easeinout',
                speed: 600,
                // Mobile: disable one-by-one gradual animation (48 pts * 150ms delay = 7.2s)
                animateGradually: { enabled: !isMobile },
            },
            fontFamily: 'inherit',
            height: baseChartHeight,
            // Mobile: disable zoom — drag-to-zoom hijacks touch scrolling
            // Docs: chart.zoom.enabled defaults to true
            zoom: { enabled: !isMobile },
            ...overrides.chart
        },
        theme: { mode: 'dark' },
        grid: { borderColor: 'rgba(255,255,255,0.08)', strokeDashArray: 3 },
        legend: { show: true, position: 'top', labels: { colors: '#fff' }, fontSize: '13px' },
        stroke: { curve: 'monotoneCubic', width: 3, lineCap: 'round' },
        fill: {
            type: 'gradient',
            gradient: {
                shadeIntensity: 1,
                opacityFrom: 0.4,
                opacityTo: 0.02,
                stops: [0, 100]
            }
        },
        markers: { size: 0, hover: { size: 5 } },
        dataLabels: { enabled: false },
        tooltip: {
            theme: 'dark',
            // Mobile: tooltip follows finger during drag-scrub
            followCursor: isMobile,
        },
        xaxis: {
            categories: xaxisCategories || [],
            tickAmount: xaxisTickAmount || baseTickAmount,
            labels: {
                style: { colors: '#fff', fontSize: '11px' },
                rotate: -40,
                rotateAlways: false,
                hideOverlappingLabels: true,
            },
        },
        yaxis: {
            labels: { style: { colors: '#fff', fontSize: '12px' } },
        },
    };

    // Merge overrides on top, but preserve xaxis/yaxis base settings
    const merged = { ...opts, ...overrides };

    // Re-apply chart so toolbar/animations/zoom survive override clobbering
    merged.chart = {
        ...opts.chart,
        ...overrides.chart,
    };

    // Re-apply tooltip so mobile followCursor/fixed survive override clobbering
    merged.tooltip = {
        ...opts.tooltip,
        ...overrides.tooltip,
    };

    // Re-apply xaxis/yaxis so base label settings survive override clobbering
    merged.xaxis = {
        categories: xaxisCategories || overrides.xaxis?.categories || [],
        tickAmount: xaxisTickAmount || overrides.xaxis?.tickAmount || baseTickAmount,
        labels: {
            style: { colors: '#fff', fontSize: '11px' },
            rotate: -40,
            rotateAlways: false,
            hideOverlappingLabels: true,
            ...overrides.xaxis?.labels,
        },
        ...overrides.xaxis,
        categories: xaxisCategories || overrides.xaxis?.categories || [],
        tickAmount: xaxisTickAmount || overrides.xaxis?.tickAmount || baseTickAmount,
    };

    merged.yaxis = {
        labels: { style: { colors: '#fff', fontSize: '12px' } },
        ...overrides.yaxis,
    };

    return merged;
}

// Format units from API (e.g., "mp/h" -> "mph")
function formatUnit(unit) {
    if (!unit) return '';
    return unit.replace('mp/h', 'mph');
}

function averageEnsembleValues(values) {
    if (!Array.isArray(values) || values.length === 0) return null;
    const numbers = values.filter((value) => Number.isFinite(value));
    if (!numbers.length) return null;
    return numbers.reduce((sum, value) => sum + value, 0) / numbers.length;
}

function modeEnsembleValue(values, round = false) {
    if (!Array.isArray(values) || values.length === 0) return null;
    const counts = new Map();
    for (const rawValue of values) {
        if (!Number.isFinite(rawValue)) continue;
        const value = round ? Math.round(rawValue) : rawValue;
        counts.set(value, (counts.get(value) || 0) + 1);
    }
    if (!counts.size) return null;

    let bestValue = null;
    let bestCount = -1;
    for (const [value, count] of counts.entries()) {
        if (count > bestCount) {
            bestValue = value;
            bestCount = count;
        }
    }
    return bestValue;
}

function medianEnsembleValue(values) {
    if (!Array.isArray(values) || values.length === 0) return null;
    const sorted = values.filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
    if (!sorted.length) return null;
    const mid = Math.floor(sorted.length / 2);
    if (sorted.length % 2 === 1) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
}

function medianFloorEnsembleValue(values) {
    if (!Array.isArray(values) || values.length === 0) return null;
    const sorted = values.filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
    if (!sorted.length) return null;
    const mid = Math.floor(sorted.length / 2);
    // For even-length arrays, pick the lower-middle element instead of averaging.
    // This is for categorical data (WMO weather codes) where averaging produces
    // phantom codes (e.g. median of [51, 99] = 75 "heavy snow" instead of 51 "light drizzle").
    if (sorted.length % 2 === 0) return sorted[mid - 1];
    return sorted[mid];
}

function findEnsembleSeries(container, variable, options = {}) {
    if (!container || !variable) return [];
    const { excludeMember = false } = options;
    const keys = Object.keys(container);
    const series = [];
    for (const key of keys) {
        if (key === variable || key.startsWith(`${variable}_`)) {
            if (excludeMember && key.includes('member')) continue;
            const value = container[key];
            if (Array.isArray(value)) {
                series.push(value);
            }
        }
    }
    return series;
}

function findEnsembleUnit(unitsContainer, variable, options = {}) {
    if (!unitsContainer || !variable) return undefined;
    const { excludeMember = false } = options;
    if (unitsContainer[variable]) return unitsContainer[variable];
    const unitKey = Object.keys(unitsContainer).find((key) => {
        if (!key.startsWith(`${variable}_`)) return false;
        if (excludeMember && key.includes('member')) return false;
        return true;
    });
    return unitKey ? unitsContainer[unitKey] : undefined;
}

function aggregateEnsembleSeries(seriesList, strategy = 'average', expectedLength = null) {
    if (!seriesList.length) return null;
    // Use expectedLength (time array length) as the source of truth when provided,
    // otherwise fall back to Math.max on series lengths
    const length = expectedLength !== null && expectedLength !== undefined
        ? expectedLength
        : Math.max(...seriesList.map((series) => series.length));
    const result = new Array(length).fill(null);

    for (let i = 0; i < length; i++) {
        const memberValues = seriesList.map((series) => series[i]).filter((value) => value !== undefined && value !== null);
        if (!memberValues.length) continue;

        if (strategy === 'mode') {
            result[i] = modeEnsembleValue(memberValues, true);
        } else if (strategy === 'median') {
            result[i] = medianEnsembleValue(memberValues);
        } else if (strategy === 'medianFloor') {
            result[i] = medianFloorEnsembleValue(memberValues);
        } else if (strategy === 'binary') {
            const avg = averageEnsembleValues(memberValues);
            result[i] = avg === null ? null : (avg >= 0.5 ? 1 : 0);
        } else {
            result[i] = averageEnsembleValues(memberValues);
        }
    }

    return result;
}

function roundTo(value, decimals) {
    if (!Number.isFinite(value)) return value;
    const factor = 10 ** decimals;
    return Math.round(value * factor) / factor;
}

function normalizeAggregatedSeries(series, options = {}) {
    if (!Array.isArray(series)) return series;
    const { decimals = null, clampAbsBelow = null } = options;
    return series.map((value) => {
        if (!Number.isFinite(value)) return value;
        let next = value;
        if (decimals !== null) {
            next = roundTo(next, decimals);
        }
        if (clampAbsBelow !== null && Math.abs(next) < clampAbsBelow) {
            return 0;
        }
        return next;
    });
}

function deriveEnsemblePrecipitationProbability(hourlyData, threshold = 0.01, expectedLength = null) {
    if (!hourlyData) return null;

    const memberSeries = Object.keys(hourlyData)
        .filter((key) => (
            key.startsWith('precipitation_') &&
            !key.startsWith('precipitation_probability') &&
            key.includes('member') &&
            Array.isArray(hourlyData[key])
        ))
        .map((key) => hourlyData[key]);

    if (!memberSeries.length) return null;

    // Use expectedLength (time array length) as the source of truth when provided,
    // otherwise fall back to Math.max on series lengths
    const length = expectedLength !== null && expectedLength !== undefined
        ? expectedLength
        : Math.max(...memberSeries.map((series) => series.length));
    const probability = new Array(length).fill(null);

    for (let i = 0; i < length; i++) {
        const membersWithRain = memberSeries.reduce((count, series) => {
            const value = series[i];
            return Number.isFinite(value) && value > threshold ? count + 1 : count;
        }, 0);
        probability[i] = Math.round((membersWithRain / memberSeries.length) * 100);
    }

    return probability;
}

function nearestTimeIndex(times, targetDate) {
    if (!Array.isArray(times) || !times.length) return 0;
    const targetMs = targetDate.getTime();
    let bestIndex = 0;
    let bestDelta = Number.POSITIVE_INFINITY;

    for (let i = 0; i < times.length; i++) {
        const timeMs = new Date(times[i]).getTime();
        if (!Number.isFinite(timeMs)) continue;
        const delta = Math.abs(timeMs - targetMs);
        if (delta < bestDelta) {
            bestDelta = delta;
            bestIndex = i;
        }
    }
    return bestIndex;
}

function summarizeDailyFromHourly(hourly, dates) {
    const dateIndexes = new Map();
    dates.forEach((date) => dateIndexes.set(date, []));

    for (let i = 0; i < hourly.time.length; i++) {
        const dateKey = hourly.time[i].split('T')[0];
        if (dateIndexes.has(dateKey)) {
            dateIndexes.get(dateKey).push(i);
        }
    }

    const result = {
        weather_code: [],
        temperature_2m_max: [],
        temperature_2m_min: [],
        apparent_temperature_max: [],
        apparent_temperature_min: [],
        precipitation_sum: [],
        wind_speed_10m_max: [],
        precipitation_probability_max: [],
        snowfall_sum: []
    };

    const aggregateDay = (indexes, series, mode) => {
        if (!series || !indexes.length) return null;
        const values = indexes.map((idx) => series[idx]).filter((value) => Number.isFinite(value));
        if (!values.length) return null;
        if (mode === 'max') return Math.max(...values);
        if (mode === 'min') return Math.min(...values);
        if (mode === 'sum') return values.reduce((sum, value) => sum + value, 0);
        if (mode === 'mode') return modeEnsembleValue(values, true);
        if (mode === 'median') return medianEnsembleValue(values);
        if (mode === 'medianFloor') return medianFloorEnsembleValue(values);
        return averageEnsembleValues(values);
    };

    for (const date of dates) {
        const indexes = dateIndexes.get(date) || [];
        result.weather_code.push(aggregateDay(indexes, hourly.weather_code, 'medianFloor'));
        result.temperature_2m_max.push(aggregateDay(indexes, hourly.temperature_2m, 'max'));
        result.temperature_2m_min.push(aggregateDay(indexes, hourly.temperature_2m, 'min'));
        result.apparent_temperature_max.push(aggregateDay(indexes, hourly.apparent_temperature, 'max'));
        result.apparent_temperature_min.push(aggregateDay(indexes, hourly.apparent_temperature, 'min'));
        result.precipitation_sum.push(aggregateDay(indexes, hourly.precipitation, 'sum'));
        result.wind_speed_10m_max.push(aggregateDay(indexes, hourly.wind_speed_10m, 'max'));
        result.precipitation_probability_max.push(aggregateDay(indexes, hourly.precipitation_probability, 'max'));
        result.snowfall_sum.push(aggregateDay(indexes, hourly.snowfall, 'sum'));
    }

    return result;
}

function buildSunriseSunsetFromDates(dates, lat, lon) {
    return dates.map((dateKey) => {
        const day = parseDateString(dateKey);
        const times = SunCalc.getTimes(day, lat, lon);
        return {
            sunrise: times?.sunrise ? times.sunrise.toISOString() : null,
            sunset: times?.sunset ? times.sunset.toISOString() : null
        };
    });
}

function normalizeEnsembleWeatherData(rawData, lat, lon) {
    const normalized = {
        latitude: rawData.latitude,
        longitude: rawData.longitude,
        generationtime_ms: rawData.generationtime_ms,
        utc_offset_seconds: rawData.utc_offset_seconds,
        timezone: rawData.timezone,
        timezone_abbreviation: rawData.timezone_abbreviation,
        elevation: rawData.elevation,
        current_units: { time: 'iso8601' },
        current: {},
        hourly_units: { time: 'iso8601' },
        hourly: { time: rawData.hourly?.time ? [...rawData.hourly.time] : [] },
        daily_units: { time: 'iso8601' },
        daily: { time: [] }
    };

    const hourlyConfigs = [
        { source: 'temperature_2m', target: 'temperature_2m', strategy: 'average' },
        { source: 'relative_humidity_2m', target: 'relative_humidity_2m', strategy: 'average' },
        { source: 'weather_code', target: 'weather_code', strategy: 'medianFloor', excludeMember: true },
        { source: 'wind_speed_10m', target: 'wind_speed_10m', strategy: 'average' },
        { source: 'precipitation_probability', target: 'precipitation_probability', strategy: 'average', excludeMember: true },
        { source: 'precipitation', target: 'precipitation', strategy: 'average' },
        { source: 'snowfall', target: 'snowfall', strategy: 'average' },
        { source: 'surface_pressure', target: 'surface_pressure', strategy: 'average' },
        { source: 'cloud_cover', target: 'cloud_cover', strategy: 'average' },
        { source: 'cloud_cover_low', target: 'cloud_cover_low', strategy: 'average' },
        { source: 'cloud_cover_mid', target: 'cloud_cover_mid', strategy: 'average' },
        { source: 'cloud_cover_high', target: 'cloud_cover_high', strategy: 'average' },
        { source: 'shortwave_radiation', target: 'shortwave_radiation', strategy: 'average' },
        { source: 'is_day', target: 'is_day', strategy: 'binary' },
        { source: 'apparent_temperature', target: 'apparent_temperature', strategy: 'average' },
        { source: 'dew_point_2m', target: 'dewpoint_2m', strategy: 'average' },
        { source: 'uv_index', target: 'uv_index', strategy: 'average' }
    ];
    const hourlyPostProcess = {
        temperature_2m: { decimals: 0 },
        relative_humidity_2m: { decimals: 0 },
        wind_speed_10m: { decimals: 1 },
        precipitation_probability: { decimals: 0 },
        precipitation: { decimals: 2, clampAbsBelow: 0.01 },
        snowfall: { decimals: 2, clampAbsBelow: 0.1 },
        apparent_temperature: { decimals: 0 },
        dewpoint_2m: { decimals: 0 },
        uv_index: { decimals: 1 }
    };

    for (const config of hourlyConfigs) {
        const seriesList = findEnsembleSeries(rawData.hourly, config.source, {
            excludeMember: !!config.excludeMember
        });
        const aggregated = aggregateEnsembleSeries(seriesList, config.strategy, normalized.hourly.time.length);
        if (aggregated) {
            normalized.hourly[config.target] = normalizeAggregatedSeries(
                aggregated,
                hourlyPostProcess[config.target]
            );
            const unit = findEnsembleUnit(rawData.hourly_units, config.source, {
                excludeMember: !!config.excludeMember
            });
            if (unit) normalized.hourly_units[config.target] = unit;
        }
    }

    const derivedPrecipitationProbability = deriveEnsemblePrecipitationProbability(rawData.hourly, 0.01, normalized.hourly.time.length);
    if (derivedPrecipitationProbability) {
        normalized.hourly.precipitation_probability = derivedPrecipitationProbability;
        normalized.hourly_units.precipitation_probability = '%';
    }

    const dailyTime = rawData.daily?.time ? [...rawData.daily.time] : [...new Set(normalized.hourly.time.map((time) => time.split('T')[0]))];
    normalized.daily.time = dailyTime;

    const dailyConfigs = [
        { source: 'weather_code', target: 'weather_code', strategy: 'medianFloor', excludeMember: true },
        { source: 'temperature_2m_max', target: 'temperature_2m_max', strategy: 'average' },
        { source: 'temperature_2m_min', target: 'temperature_2m_min', strategy: 'average' },
        { source: 'apparent_temperature_max', target: 'apparent_temperature_max', strategy: 'average' },
        { source: 'apparent_temperature_min', target: 'apparent_temperature_min', strategy: 'average' },
        { source: 'precipitation_sum', target: 'precipitation_sum', strategy: 'average' },
        { source: 'wind_speed_10m_max', target: 'wind_speed_10m_max', strategy: 'average' },
        { source: 'precipitation_probability_max', target: 'precipitation_probability_max', strategy: 'average', excludeMember: true },
        { source: 'snowfall_sum', target: 'snowfall_sum', strategy: 'average' }
    ];
    const dailyPostProcess = {
        temperature_2m_max: { decimals: 0 },
        temperature_2m_min: { decimals: 0 },
        apparent_temperature_max: { decimals: 0 },
        apparent_temperature_min: { decimals: 0 },
        precipitation_sum: { decimals: 2, clampAbsBelow: 0.01 },
        wind_speed_10m_max: { decimals: 1 },
        precipitation_probability_max: { decimals: 0 },
        snowfall_sum: { decimals: 2, clampAbsBelow: 0.1 }
    };

    for (const config of dailyConfigs) {
        const seriesList = findEnsembleSeries(rawData.daily, config.source, {
            excludeMember: !!config.excludeMember
        });
        const aggregated = aggregateEnsembleSeries(seriesList, config.strategy, dailyTime.length);
        if (aggregated) {
            normalized.daily[config.target] = normalizeAggregatedSeries(
                aggregated,
                dailyPostProcess[config.target]
            );
            const unit = findEnsembleUnit(rawData.daily_units, config.source, {
                excludeMember: !!config.excludeMember
            });
            if (unit) normalized.daily_units[config.target] = unit;
        }
    }

    if (Array.isArray(normalized.hourly.precipitation_probability) && dailyTime.length) {
        const derivedDaily = summarizeDailyFromHourly(normalized.hourly, dailyTime);
        normalized.daily.precipitation_probability_max = normalizeAggregatedSeries(
            derivedDaily.precipitation_probability_max,
            dailyPostProcess.precipitation_probability_max
        );
        normalized.daily_units.precipitation_probability_max = '%';
    }

    const sunriseSeries = findEnsembleSeries(rawData.daily, 'sunrise');
    const sunsetSeries = findEnsembleSeries(rawData.daily, 'sunset');
    if (sunriseSeries.length) normalized.daily.sunrise = [...sunriseSeries[0]];
    if (sunsetSeries.length) normalized.daily.sunset = [...sunsetSeries[0]];
    if (normalized.daily.sunrise) normalized.daily_units.sunrise = 'iso8601';
    if (normalized.daily.sunset) normalized.daily_units.sunset = 'iso8601';

    const missingDailyFields = [
        'weather_code',
        'temperature_2m_max',
        'temperature_2m_min',
        'apparent_temperature_max',
        'apparent_temperature_min',
        'precipitation_sum',
        'wind_speed_10m_max',
        'precipitation_probability_max',
        'snowfall_sum'
    ].filter((field) => !normalized.daily[field]);

    if (missingDailyFields.length && normalized.hourly.time.length) {
        const derivedDaily = summarizeDailyFromHourly(normalized.hourly, dailyTime);
        for (const field of missingDailyFields) {
            normalized.daily[field] = normalizeAggregatedSeries(
                derivedDaily[field],
                dailyPostProcess[field]
            );
        }
    }

    if (!normalized.daily.sunrise || !normalized.daily.sunset) {
        const sunTimes = buildSunriseSunsetFromDates(dailyTime, lat, lon);
        if (!normalized.daily.sunrise) normalized.daily.sunrise = sunTimes.map((entry) => entry.sunrise);
        if (!normalized.daily.sunset) normalized.daily.sunset = sunTimes.map((entry) => entry.sunset);
        normalized.daily_units.sunrise = 'iso8601';
        normalized.daily_units.sunset = 'iso8601';
    }

    if (!normalized.daily_units.temperature_2m_max && normalized.hourly_units.temperature_2m) {
        normalized.daily_units.temperature_2m_max = normalized.hourly_units.temperature_2m;
    }
    if (!normalized.daily_units.temperature_2m_min && normalized.hourly_units.temperature_2m) {
        normalized.daily_units.temperature_2m_min = normalized.hourly_units.temperature_2m;
    }
    if (!normalized.daily_units.apparent_temperature_max && normalized.hourly_units.apparent_temperature) {
        normalized.daily_units.apparent_temperature_max = normalized.hourly_units.apparent_temperature;
    }
    if (!normalized.daily_units.apparent_temperature_min && normalized.hourly_units.apparent_temperature) {
        normalized.daily_units.apparent_temperature_min = normalized.hourly_units.apparent_temperature;
    }
    // Hardcode units since ensemble API uses suffixed keys that findEnsembleUnit may miss
    if (!normalized.hourly_units.temperature_2m) normalized.hourly_units.temperature_2m = '°F';
    if (!normalized.hourly_units.relative_humidity_2m) normalized.hourly_units.relative_humidity_2m = '%';
    if (!normalized.hourly_units.wind_speed_10m) normalized.hourly_units.wind_speed_10m = 'mp/h';
    if (!normalized.hourly_units.precipitation) normalized.hourly_units.precipitation = 'inch';
    if (!normalized.hourly_units.snowfall) normalized.hourly_units.snowfall = 'inch';
    if (!normalized.hourly_units.surface_pressure) normalized.hourly_units.surface_pressure = 'hPa';
    if (!normalized.hourly_units.apparent_temperature) normalized.hourly_units.apparent_temperature = '°F';
    if (!normalized.hourly_units.dewpoint_2m) normalized.hourly_units.dewpoint_2m = '°F';
    if (!normalized.hourly_units.uv_index) normalized.hourly_units.uv_index = '';
    if (!normalized.daily_units.precipitation_sum) {
        normalized.daily_units.precipitation_sum = 'inch';
    }
    if (!normalized.daily_units.snowfall_sum) {
        normalized.daily_units.snowfall_sum = 'inch';
    }
    if (!normalized.daily_units.wind_speed_10m_max && normalized.hourly_units.wind_speed_10m) {
        normalized.daily_units.wind_speed_10m_max = normalized.hourly_units.wind_speed_10m;
    }
    if (!normalized.daily_units.precipitation_probability_max) {
        normalized.daily_units.precipitation_probability_max = '%';
    }
    if (!normalized.daily_units.weather_code) {
        normalized.daily_units.weather_code = 'wmo code';
    }

    const currentIndex = nearestTimeIndex(normalized.hourly.time, new Date());
    normalized.current.time = normalized.hourly.time[currentIndex] || new Date().toISOString();
    normalized.current.temperature_2m = normalized.hourly.temperature_2m?.[currentIndex];
    normalized.current.relative_humidity_2m = normalized.hourly.relative_humidity_2m?.[currentIndex];
    normalized.current.apparent_temperature = normalized.hourly.apparent_temperature?.[currentIndex];
    normalized.current.wind_speed_10m = normalized.hourly.wind_speed_10m?.[currentIndex];
    normalized.current.uv_index = normalized.hourly.uv_index?.[currentIndex];
    normalized.current.weather_code = normalized.hourly.weather_code?.[currentIndex];
    normalized.current.dewpoint_2m = normalized.hourly.dewpoint_2m?.[currentIndex];
    normalized.current.surface_pressure = normalized.hourly.surface_pressure?.[currentIndex];

    normalized.current_units.temperature_2m = normalized.hourly_units.temperature_2m;
    normalized.current_units.relative_humidity_2m = normalized.hourly_units.relative_humidity_2m;
    normalized.current_units.apparent_temperature = normalized.hourly_units.apparent_temperature;
    normalized.current_units.wind_speed_10m = normalized.hourly_units.wind_speed_10m;
    normalized.current_units.uv_index = normalized.hourly_units.uv_index || '';
    normalized.current_units.weather_code = normalized.hourly_units.weather_code || 'wmo code';
    normalized.current_units.dewpoint_2m = normalized.hourly_units.dewpoint_2m;
    normalized.current_units.surface_pressure = normalized.hourly_units.surface_pressure;

    return normalized;
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function isLikelyUsLocation(lat, lon) {
    return lat >= US_BOUNDS.minLat &&
        lat <= US_BOUNDS.maxLat &&
        lon >= US_BOUNDS.minLon &&
        lon <= US_BOUNDS.maxLon;
}

async function fetchWith503Retry(url, options = {}, retries = 2) {
    let attempt = 0;
    while (attempt <= retries) {
        const response = await fetch(url, options);
        if (response.status !== 503 || attempt === retries) {
            return response;
        }
        attempt++;
        await sleep(1000);
    }
}

function extractDurationHours(duration) {
    if (!duration) return 0;
    const dayMatch = duration.match(/(\d+)D/);
    const hourMatch = duration.match(/(\d+)H/);
    const minuteMatch = duration.match(/(\d+)M/);
    const days = dayMatch ? Number(dayMatch[1]) : 0;
    const hours = hourMatch ? Number(hourMatch[1]) : 0;
    const minutes = minuteMatch ? Number(minuteMatch[1]) : 0;
    return days * 24 + hours + (minutes / 60);
}

function overlapHours(rangeStart, rangeEnd, targetStart, targetEnd) {
    const start = Math.max(rangeStart.getTime(), targetStart.getTime());
    const end = Math.min(rangeEnd.getTime(), targetEnd.getTime());
    if (end <= start) return 0;
    return (end - start) / (1000 * 60 * 60);
}

function getCachedJson(key, maxAgeMs) {
    try {
        const raw = localStorage.getItem(key);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        if (!parsed || !parsed.ts || !parsed.data) return null;
        if ((Date.now() - parsed.ts) > maxAgeMs) return null;
        return parsed.data;
    } catch (error) {
        return null;
    }
}

function setCachedJson(key, data) {
    try {
        localStorage.setItem(key, JSON.stringify({ ts: Date.now(), data }));
    } catch (error) {
        // Ignore localStorage write failures (quota, private mode)
    }
}

function formatDateYYYYMMDD(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}${month}${day}`;
}

function formatDateKey(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

function parseNoaaDateTime(dateTimeString) {
    if (!dateTimeString || typeof dateTimeString !== 'string') return null;
    const [datePart, timePart] = dateTimeString.trim().split(' ');
    if (!datePart || !timePart) return null;
    const [year, month, day] = datePart.split('-').map(Number);
    const [hours, minutes] = timePart.split(':').map(Number);
    if (![year, month, day, hours, minutes].every(Number.isFinite)) return null;
    return new Date(year, month - 1, day, hours, minutes, 0, 0);
}

function haversineKm(lat1, lon1, lat2, lon2) {
    const toRad = (value) => value * Math.PI / 180;
    const earthRadiusKm = 6371;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return earthRadiusKm * c;
}

function normalizeNoaaStations(rawStations) {
    if (!Array.isArray(rawStations)) return [];

    return rawStations
        .map((station) => {
            const lat = Number(station?.lat);
            const lon = Number(station?.lng ?? station?.lon ?? station?.long);
            return {
                id: station?.id,
                name: station?.name || station?.id,
                lat,
                lon
            };
        })
        .filter((station) => station.id && Number.isFinite(station.lat) && Number.isFinite(station.lon));
}

async function fetchNoaaStations() {
    const cached = getCachedJson(NOAA_STATIONS_CACHE_KEY, NOAA_STATIONS_CACHE_MS);
    if (cached && Array.isArray(cached) && cached.length > 0) {
        const normalizedCached = normalizeNoaaStations(cached);
        if (normalizedCached.length > 0) {
            return normalizedCached;
        }
    }

    const response = await fetch(NOAA_STATIONS_URL);
    if (!response.ok) {
        throw new Error(`NOAA stations request failed (${response.status})`);
    }

    const payload = await response.json();
    const rawStations = Array.isArray(payload?.stations) ? payload.stations : [];
    const stations = normalizeNoaaStations(rawStations);

    if (stations.length > 0) {
        setCachedJson(NOAA_STATIONS_CACHE_KEY, stations);
    }
    return stations;
}

async function findNearestNoaaStation(lat, lon, stations) {
    if (!Array.isArray(stations) || stations.length === 0) return null;

    const sortedStations = stations
        .map((station) => ({
            ...station,
            distance: haversineKm(lat, lon, station.lat, station.lon)
        }))
        .sort((a, b) => a.distance - b.distance);

    const nearestCandidate = sortedStations[0];
    if (!nearestCandidate) return null;

    console.debug(`[Tides] Nearest NOAA station candidate: ${nearestCandidate.name} (${nearestCandidate.id}) at ${nearestCandidate.distance.toFixed(1)} km`);

    return {
        ...nearestCandidate,
        distanceMi: nearestCandidate.distance * 0.621371
    };
}

function findNearbyNoaaStations(lat, lon, stations, maxDistanceKm = MAX_STATION_DISTANCE_KM) {
    if (!Array.isArray(stations) || stations.length === 0) return [];

    return stations
        .map((station) => ({
            ...station,
            distance: haversineKm(lat, lon, station.lat, station.lon)
        }))
        .filter((station) => station.distance <= maxDistanceKm)
        .sort((a, b) => a.distance - b.distance)
        .map((station) => ({
            ...station,
            distanceMi: station.distance * 0.621371
        }));
}

async function fetchNoaaPredictions(stationId, interval, beginDate, endDate) {
    const cacheKey = `${TIDE_CACHE_VERSION}_noaa_tide_predictions_${stationId}_${interval}_${formatDateYYYYMMDD(beginDate)}`;
    const cached = getCachedJson(cacheKey, NOAA_PREDICTIONS_CACHE_MS);
    if (cached && Array.isArray(cached)) {
        return cached;
    }

    const params = new URLSearchParams({
        product: 'predictions',
        application: 'jaccuweather',
        begin_date: formatDateYYYYMMDD(beginDate),
        end_date: formatDateYYYYMMDD(endDate),
        datum: 'MLLW',
        station: stationId,
        time_zone: 'lst_ldt',
        units: 'english',
        interval,
        format: 'json'
    });

    const response = await fetch(`${NOAA_DATAGETTER_URL}?${params.toString()}`);
    if (!response.ok) {
        throw new Error(`NOAA predictions request failed (${response.status})`);
    }

    const payload = await response.json();
    if (payload?.error) {
        throw new Error(payload.error.message || 'NOAA predictions error');
    }
    const predictions = Array.isArray(payload?.predictions) ? payload.predictions : [];
    setCachedJson(cacheKey, predictions);
    return predictions;
}

function interpolateTideCurve(hiloPoints, intervalMinutes = 15) {
    if (!Array.isArray(hiloPoints) || hiloPoints.length < 2) return [];

    const sorted = hiloPoints
        .filter((point) => point?.time instanceof Date && Number.isFinite(point.value))
        .slice()
        .sort((a, b) => a.time.getTime() - b.time.getTime());

    if (sorted.length < 2) return [];

    const intervalMs = Math.max(1, Number(intervalMinutes) || 15) * 60 * 1000;
    const curve = [];
    const seen = new Set();

    const pushPoint = (timeMs, value) => {
        if (seen.has(timeMs) || !Number.isFinite(value)) return;
        seen.add(timeMs);
        curve.push({
            time: new Date(timeMs),
            value: Number(value.toFixed(3)),
            type: ''
        });
    };

    for (let i = 0; i < sorted.length - 1; i++) {
        const start = sorted[i];
        const end = sorted[i + 1];
        const startMs = start.time.getTime();
        const endMs = end.time.getTime();
        const spanMs = endMs - startMs;

        if (spanMs <= 0) continue;

        for (let tMs = startMs; tMs < endMs; tMs += intervalMs) {
            const t = (tMs - startMs) / spanMs;
            const value = start.value + (end.value - start.value) * ((1 - Math.cos(Math.PI * t)) / 2);
            pushPoint(tMs, value);
        }

        pushPoint(endMs, end.value);
    }

    return curve;
}

function buildTideDailySummaries(hiloPredictions, startDate, days) {
    const summaries = {};
    const start = new Date(startDate);
    start.setHours(0, 0, 0, 0);
    const end = new Date(start);
    end.setDate(end.getDate() + days);

    hiloPredictions.forEach((entry) => {
        if (!entry?.time || !Number.isFinite(entry.value)) return;
        if (entry.time < start || entry.time > end) return;

        const dateKey = formatDateKey(entry.time);
        if (!summaries[dateKey]) {
            summaries[dateKey] = { high: null, low: null };
        }

        if (entry.type === 'H') {
            if (!summaries[dateKey].high || entry.value > summaries[dateKey].high.value) {
                summaries[dateKey].high = { value: entry.value, time: entry.time };
            }
        } else if (entry.type === 'L') {
            if (!summaries[dateKey].low || entry.value < summaries[dateKey].low.value) {
                summaries[dateKey].low = { value: entry.value, time: entry.time };
            }
        }
    });

    return summaries;
}

function parseNoaaPredictionRow(row) {
    const time = parseNoaaDateTime(row?.t);
    const value = Number(row?.v);
    if (!time || !Number.isFinite(value)) return null;
    return {
        time,
        value,
        type: (row?.type || '').toUpperCase()
    };
}

async function fetchTideDataForLocation(lat, lon, elevation) {
    const stations = await fetchNoaaStations();
    const nearestStation = await findNearestNoaaStation(lat, lon, stations);

    const elevationMeters = Number(elevation);
    const isCoastal = Number.isFinite(elevationMeters) &&
        nearestStation &&
        nearestStation.distance <= MAX_STATION_DISTANCE_KM &&
        elevationMeters <= MAX_COASTAL_ELEVATION_M;

    console.log('TIDE DEBUG:', { elevation: elevationMeters, nearestStation, distance: nearestStation?.distance });

    if (!isCoastal) {
        const distanceMessage = nearestStation ? `${nearestStation.distance.toFixed(1)} km` : 'no nearby station';
        const elevationMessage = Number.isFinite(elevationMeters) ? `${elevationMeters.toFixed(1)} m` : 'unknown elevation';
        console.debug(`[Tides] Hidden for inland/non-coastal location (station: ${distanceMessage}, elevation: ${elevationMessage})`);
        return null;
    }

    console.debug(`[Tides] Coastal location confirmed (station: ${nearestStation.distance.toFixed(1)} km, elevation: ${elevationMeters.toFixed(1)} m)`);

    const now = new Date();
    const beginDate = new Date(now);
    beginDate.setHours(0, 0, 0, 0);
    const endDate = new Date(beginDate);
    endDate.setDate(endDate.getDate() + 14);

    const candidateStations = findNearbyNoaaStations(lat, lon, stations, MAX_STATION_DISTANCE_KM);

    for (const station of candidateStations) {
        try {
            const hiloRaw = await fetchNoaaPredictions(station.id, 'hilo', beginDate, endDate);
            const hiloPredictions = hiloRaw.map(parseNoaaPredictionRow).filter(Boolean);

            if (hiloPredictions.length < 2) {
                console.debug(`[Tides] Skipping station ${station.id} (${station.name}) due to missing hilo data`);
                continue;
            }

            const interpolatedPredictions = interpolateTideCurve(hiloPredictions, 15);
            if (interpolatedPredictions.length < 2) {
                console.debug(`[Tides] Skipping station ${station.id} (${station.name}) due to insufficient interpolated curve points`);
                continue;
            }

            const dailySummaries = buildTideDailySummaries(hiloPredictions, beginDate, 14);
            return {
                station,
                interpolatedPredictions,
                hiloPredictions,
                dailySummaries
            };
        } catch (error) {
            console.debug(`[Tides] Station ${station.id} failed: ${error.message}`);
        }
    }

    console.debug('[Tides] No nearby NOAA station returned valid hilo tide predictions');
    return null;
}

function formatTideSummary(summary) {
    if (!summary || !summary.high || !summary.low) return '';
    return `High: ${summary.high.value.toFixed(1)}ft @ ${formatTime12Hour(summary.high.time)} / Low: ${summary.low.value.toFixed(1)}ft @ ${formatTime12Hour(summary.low.time)}`;
}

function computeTideYAxisBounds(values) {
    if (!Array.isArray(values) || values.length === 0) {
        return { min: -1, max: 1 };
    }

    const numericValues = values.filter((value) => Number.isFinite(value));
    if (numericValues.length === 0) {
        return { min: -1, max: 1 };
    }

    const rawMin = Math.min(...numericValues);
    const rawMax = Math.max(...numericValues);
    const padding = 0.5;

    let min = Math.floor((rawMin - padding) * 2) / 2;
    let max = Math.ceil((rawMax + padding) * 2) / 2;

    // Avoid zero-height axis when values are flat.
    if (min === max) {
        min -= 0.5;
        max += 0.5;
    }

    return { min, max };
}

function clearTideChartContainer(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;
    container.innerHTML = '';
}

function clearTideUiState() {
    if (hourlyChart.tides) {
        hourlyChart.tides.destroy();
        delete hourlyChart.tides;
    }
    if (dailyChart.tides) {
        dailyChart.tides.destroy();
        delete dailyChart.tides;
    }

    clearTideChartContainer('hourlyTidesChart');
    clearTideChartContainer('dailyTidesChart');
}

function setHourlyTidesVisibility(tideData) {
    const option = document.getElementById('hourlyTidesOption');
    const chartContainer = document.getElementById('hourlyTidesChartContainer');
    const subtitle = document.getElementById('hourlyTidesSubtitle');
    if (!option || !chartContainer || !subtitle) return;

    const hasTideData = Boolean(
        tideData?.station &&
        Array.isArray(tideData.interpolatedPredictions) &&
        tideData.interpolatedPredictions.length > 0 &&
        Array.isArray(tideData.hiloPredictions) &&
        tideData.hiloPredictions.length > 0
    );

    if (hasTideData) {
        option.classList.remove('hidden');
        chartContainer.dataset.featureHidden = 'false';
        subtitle.textContent = `${tideData.station.name} - ${tideData.station.distanceMi.toFixed(1)} mi away`;
    } else {
        clearTideUiState();
        option.classList.add('hidden');
        chartContainer.dataset.featureHidden = 'true';
        chartContainer.style.display = 'none';
        subtitle.textContent = '';
    }
}

function setDailyTidesVisibility(tideData) {
    const option = document.getElementById('dailyTidesOption');
    const chartContainer = document.getElementById('dailyTidesChartContainer');
    const subtitle = document.getElementById('dailyTidesSubtitle');
    if (!option || !chartContainer || !subtitle) return;

    const hasTideData = Boolean(
        tideData?.station &&
        Array.isArray(tideData.interpolatedPredictions) &&
        tideData.interpolatedPredictions.length > 1 &&
        Array.isArray(tideData.hiloPredictions) &&
        tideData.hiloPredictions.length > 1
    );

    if (hasTideData) {
        option.classList.remove('hidden');
        chartContainer.dataset.featureHidden = 'false';
        subtitle.textContent = `${tideData.station.name} - 14-day tidal curve`;
    } else {
        clearTideUiState();
        option.classList.add('hidden');
        chartContainer.dataset.featureHidden = 'true';
        chartContainer.style.display = 'none';
        subtitle.textContent = '';
    }
}

// Favorites management using IndexedDB (more persistent than localStorage)
let favoritesDB = null;

// Initialize IndexedDB
function initFavoritesDB() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open('WeatherAppDB', 1);

        request.onerror = () => reject(request.error);
        request.onsuccess = () => {
            favoritesDB = request.result;
            resolve(favoritesDB);
        };

        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            if (!db.objectStoreNames.contains('favorites')) {
                db.createObjectStore('favorites', { keyPath: 'id', autoIncrement: true });
            }
        };
    });
}

// Load favorites from IndexedDB
async function loadFavorites() {
    try {
        if (!favoritesDB) {
            await initFavoritesDB();
        }

        const transaction = favoritesDB.transaction(['favorites'], 'readonly');
        const store = transaction.objectStore('favorites');
        const request = store.getAll();

        request.onsuccess = () => {
            const dbFavorites = request.result;

            // If IndexedDB is empty, try to migrate from localStorage
            if (dbFavorites.length === 0) {
                const saved = localStorage.getItem('weatherFavorites');
                if (saved) {
                    try {
                        const localFavorites = JSON.parse(saved);
                        if (localFavorites && localFavorites.length > 0) {
                            // Migrate from localStorage to IndexedDB
                            favorites = localFavorites;
                            saveFavorites(); // This will save to IndexedDB
                            return;
                        }
                    } catch (e) {
                        console.error('Error parsing localStorage favorites:', e);
                    }
                }
            }

            // Extract favorites from IndexedDB (remove id field)
            favorites = dbFavorites.map(fav => ({
                name: fav.name,
                lat: fav.lat,
                lon: fav.lon
            }));
            renderFavorites();
        };

        request.onerror = () => {
            console.error('Error loading favorites from IndexedDB');
            // Fallback to localStorage
            const saved = localStorage.getItem('weatherFavorites');
            if (saved) {
                try {
                    favorites = JSON.parse(saved);
                } catch (e) {
                    favorites = [];
                }
            }
            renderFavorites();
        };
    } catch (error) {
        console.error('Error initializing favorites DB:', error);
        // Fallback to localStorage if IndexedDB fails
        const saved = localStorage.getItem('weatherFavorites');
        if (saved) {
            try {
                favorites = JSON.parse(saved);
            } catch (e) {
                favorites = [];
            }
        }
        renderFavorites();
    }
}

// Save favorites to IndexedDB
async function saveFavorites() {
    try {
        if (!favoritesDB) {
            await initFavoritesDB();
        }

        const transaction = favoritesDB.transaction(['favorites'], 'readwrite');
        const store = transaction.objectStore('favorites');

        // Clear existing favorites
        await new Promise((resolve, reject) => {
            const clearRequest = store.clear();
            clearRequest.onsuccess = () => resolve();
            clearRequest.onerror = () => reject(clearRequest.error);
        });

        // Add all current favorites
        const promises = favorites.map(fav => {
            return new Promise((resolve, reject) => {
                const addRequest = store.add(fav);
                addRequest.onsuccess = () => resolve();
                addRequest.onerror = () => reject(addRequest.error);
            });
        });

        await Promise.all(promises);

        // Also save to localStorage as backup
        localStorage.setItem('weatherFavorites', JSON.stringify(favorites));

        renderFavorites();
    } catch (error) {
        console.error('Error saving favorites to IndexedDB:', error);
        // Fallback to localStorage
        try {
            localStorage.setItem('weatherFavorites', JSON.stringify(favorites));
        } catch (e) {
            console.error('Error saving to localStorage:', e);
        }
        renderFavorites();
    }
}

function addFavorite() {
    if (!currentLat || !currentLon || !currentLocationName) {
        alert('Please search for a location first or use your current location.');
        return;
    }

    // Check if already in favorites
    const exists = favorites.some(fav =>
        Math.abs(fav.lat - currentLat) < 0.001 &&
        Math.abs(fav.lon - currentLon) < 0.001
    );

    if (exists) {
        alert('This location is already in your favorites.');
        return;
    }

    favorites.push({
        name: currentLocationName,
        lat: currentLat,
        lon: currentLon
    });

    saveFavorites();
}

function removeFavorite(index) {
    favorites.splice(index, 1);
    saveFavorites();
}

function switchToFavorite(lat, lon, name) {
    currentLocationName = name;
    fetchWeather(lat, lon);
    document.getElementById('favoritesDropdown').classList.add('hidden');
}

function renderFavorites() {
    const favoritesList = document.getElementById('favoritesList');
    const noFavorites = document.getElementById('noFavorites');

    favoritesList.innerHTML = '';

    if (favorites.length === 0) {
        noFavorites.classList.remove('hidden');
        favoritesList.classList.add('hidden');
    } else {
        noFavorites.classList.add('hidden');
        favoritesList.classList.remove('hidden');

        favorites.forEach((fav, index) => {
            const favItem = document.createElement('div');
            favItem.className = 'flex items-center justify-between p-3 hover:bg-white/10 rounded-lg mb-1';

            const nameDiv = document.createElement('div');
            nameDiv.className = 'flex-1 cursor-pointer';
            nameDiv.innerHTML = `
                <div class="text-white font-semibold">${fav.name}</div>
                <div class="text-white/60 text-xs">${fav.lat.toFixed(4)}, ${fav.lon.toFixed(4)}</div>
            `;
            nameDiv.addEventListener('click', () => switchToFavorite(fav.lat, fav.lon, fav.name));

            const deleteBtn = document.createElement('button');
            deleteBtn.className = 'text-red-400 hover:text-red-300 ml-2 p-1';
            deleteBtn.innerHTML = '<i class="fas fa-trash"></i>';
            deleteBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                removeFavorite(index);
            });

            favItem.appendChild(nameDiv);
            favItem.appendChild(deleteBtn);
            favoritesList.appendChild(favItem);
        });
    }
}

// Prevent iframe from opening new tabs
// Override window.open globally to prevent Ventusky iframe from opening new tabs
const originalWindowOpen = window.open;
window.open = function(url, target, features) {
    // Block any attempts to open new tabs/windows from iframes
    if (url && (url.includes('ventusky.com') || url.includes('ventusky'))) {
        console.log('Blocked Ventusky window.open:', url);
        return null;
    }
    // Also block if target is _blank and URL is from Ventusky
    if (target === '_blank' && url && (url.includes('ventusky.com') || url.includes('ventusky'))) {
        console.log('Blocked Ventusky _blank link:', url);
        return null;
    }
    // Allow other window.open calls (for legitimate uses)
    return originalWindowOpen.apply(this, arguments);
};

// Intercept postMessage from iframe that might try to open new tabs
window.addEventListener('message', (event) => {
    // Only trust messages from Ventusky domain
    if (event.origin.includes('ventusky.com')) {
        // Block any messages that might trigger navigation
        if (event.data && (typeof event.data === 'string' || typeof event.data === 'object')) {
            const dataStr = JSON.stringify(event.data);
            if (dataStr.includes('open') || dataStr.includes('navigate') || dataStr.includes('window')) {
                console.log('Blocked Ventusky postMessage:', event.data);
                event.stopPropagation();
                return false;
            }
        }
    }
}, { capture: true });

// Initialize with user's location or default
window.addEventListener('DOMContentLoaded', () => {
    loadFavorites();

    // Favorites button click handler
    document.getElementById('favoritesBtn').addEventListener('click', (e) => {
        e.stopPropagation();
        const dropdown = document.getElementById('favoritesDropdown');
        dropdown.classList.toggle('hidden');
    });

    // Add favorite button
    document.getElementById('addFavoriteBtn').addEventListener('click', (e) => {
        e.stopPropagation();
        addFavorite();
    });

    // Close dropdown when clicking outside
    document.addEventListener('click', (e) => {
        const dropdown = document.getElementById('favoritesDropdown');
        const btn = document.getElementById('favoritesBtn');
        if (!dropdown.contains(e.target) && !btn.contains(e.target)) {
            dropdown.classList.add('hidden');
        }
    });

    if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
            (position) => {
                currentLat = position.coords.latitude;
                currentLon = position.coords.longitude;
                fetchWeather(currentLat, currentLon);
            },
            () => {
                // Default to London if geolocation fails
                fetchWeather(51.5074, -0.1278);
            }
        );
    } else {
        fetchWeather(51.5074, -0.1278);
    }
});

// Search functionality
const locationInputEl = document.getElementById('locationInput');
const searchAutocompleteEl = document.getElementById('searchAutocomplete');

document.getElementById('searchBtn').addEventListener('click', handleSearch);
locationInputEl.addEventListener('input', onSearchInput);
locationInputEl.addEventListener('keydown', onSearchInputKeydown);
locationInputEl.addEventListener('focus', onSearchInputFocus);
locationInputEl.addEventListener('blur', onSearchInputBlur);
document.addEventListener('click', onDocumentClickForAutocomplete);

// Refresh button - re-fetch weather for current location
document.getElementById('refreshBtn').addEventListener('click', () => {
    if (currentLat && currentLon) {
        const btn = document.getElementById('refreshBtn');
        const svg = btn.querySelector('svg');
        if (svg) {
            svg.style.transition = 'transform 0.6s var(--ease-spring)';
            svg.style.transform = 'rotate(360deg)';
            setTimeout(() => { svg.style.transition = 'none'; svg.style.transform = 'rotate(0deg)'; }, 600);
        }
        fetchWeather(currentLat, currentLon);
    }
});
document.getElementById('locationBtn').addEventListener('click', () => {
    const btn = document.getElementById('locationBtn');

    if (!navigator.geolocation) {
        showLocationBtnError(btn, 'Geolocation not supported');
        return;
    }

    const doGeolocate = () => {
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>';
        btn.disabled = true;
        btn.title = 'Getting your location...';

        navigator.geolocation.getCurrentPosition(
            (position) => {
                btn.innerHTML = '<i class="fas fa-location-arrow"></i>';
                btn.disabled = false;
                btn.title = 'Use Current Location';
                currentLat = position.coords.latitude;
                currentLon = position.coords.longitude;
                currentLocationName = null;
                fetchWeather(currentLat, currentLon);
            },
            (err) => {
                btn.innerHTML = '<i class="fas fa-location-arrow"></i>';
                btn.disabled = false;
                btn.title = 'Use Current Location';
                if (err.code === 1) {
                    showLocationBtnError(btn, 'Location blocked - enable in browser settings');
                } else if (err.code === 3) {
                    showLocationBtnError(btn, 'Location timed out - try again');
                } else {
                    showLocationBtnError(btn, 'Unable to get location');
                }
            },
            { timeout: 10000, maximumAge: 60000, enableHighAccuracy: false }
        );
    };

    // Check permission status first if Permissions API is available
    if (navigator.permissions) {
        navigator.permissions.query({ name: 'geolocation' }).then((result) => {
            if (result.state === 'denied') {
                showLocationBtnError(btn, 'Location blocked - enable in browser settings');
            } else {
                doGeolocate();
            }
        }).catch(() => doGeolocate());
    } else {
        doGeolocate();
    }
});

function showLocationBtnError(btn, msg) {
    // Show error as a tooltip/badge on the button itself, visible regardless of scroll position
    const existing = document.getElementById('locationBtnError');
    if (existing) existing.remove();

    const tooltip = document.createElement('div');
    tooltip.id = 'locationBtnError';
    tooltip.style.cssText = 'position:absolute;background:#ef4444;color:#fff;font-size:12px;padding:4px 10px;border-radius:6px;white-space:nowrap;z-index:9999;pointer-events:none;top:calc(100% + 6px);left:50%;transform:translateX(-50%);box-shadow:0 2px 8px rgba(0,0,0,0.4)';
    tooltip.textContent = msg;

    btn.style.position = 'relative';
    btn.appendChild(tooltip);
    setTimeout(() => tooltip.remove(), 4000);
}

function onSearchInput(e) {
    const query = e.target.value.trim();
    clearTimeout(searchDebounceTimer);

    if (query.length < 2) {
        hideAutocomplete();
        return;
    }

    searchDebounceTimer = setTimeout(() => {
        fetchSuggestions(query);
    }, 300);
}

function onSearchInputFocus() {
    if (blurHideTimer) clearTimeout(blurHideTimer);
    if (searchSuggestions.length > 0 && locationInputEl.value.trim().length >= 2) {
        showAutocomplete();
    }
}

function onSearchInputBlur() {
    blurHideTimer = setTimeout(() => {
        hideAutocomplete();
    }, 150);
}

function onDocumentClickForAutocomplete(e) {
    if (!searchAutocompleteEl || !locationInputEl) return;
    if (searchAutocompleteEl.contains(e.target) || locationInputEl.contains(e.target)) return;
    hideAutocomplete();
}

function onSearchInputKeydown(e) {
    const hasSuggestions = searchSuggestions.length > 0 && !searchAutocompleteEl.classList.contains('hidden');

    if (e.key === 'Escape') {
        hideAutocomplete();
        return;
    }

    if (e.key === 'ArrowDown' && hasSuggestions) {
        e.preventDefault();
        selectedSuggestionIndex = (selectedSuggestionIndex + 1) % searchSuggestions.length;
        renderSuggestions(searchSuggestions);
        return;
    }

    if (e.key === 'ArrowUp' && hasSuggestions) {
        e.preventDefault();
        selectedSuggestionIndex = selectedSuggestionIndex <= 0 ? searchSuggestions.length - 1 : selectedSuggestionIndex - 1;
        renderSuggestions(searchSuggestions);
        return;
    }

    if (e.key === 'Enter') {
        if (hasSuggestions && selectedSuggestionIndex >= 0) {
            e.preventDefault();
            selectSuggestion(searchSuggestions[selectedSuggestionIndex]);
            return;
        }
        hideAutocomplete();
        handleSearch();
    }
}

function showAutocompleteLoading() {
    if (!searchAutocompleteEl) return;
    selectedSuggestionIndex = -1;
    searchAutocompleteEl.innerHTML = `
        <div class="px-4 py-3 text-sm text-white/70 flex items-center gap-2 min-h-[44px]">
            <i class="fas fa-spinner fa-spin text-xs"></i>
            <span>Searching...</span>
        </div>
    `;
    showAutocomplete();
}

function showAutocomplete() {
    if (!searchAutocompleteEl) return;
    searchAutocompleteEl.classList.remove('hidden');
}

function hideAutocomplete() {
    if (!searchAutocompleteEl) return;
    clearTimeout(searchDebounceTimer);
    selectedSuggestionIndex = -1;
    searchAutocompleteEl.classList.add('hidden');
}

async function fetchSuggestions(query) {
    const requestId = ++activeSuggestionRequestId;
    showAutocompleteLoading();

    try {
        const response = await fetch(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(query)}&count=8&language=en&format=json`);
        const data = await response.json();

        if (requestId !== activeSuggestionRequestId) return;

        searchSuggestions = data.results || [];
        selectedSuggestionIndex = searchSuggestions.length ? 0 : -1;
        renderSuggestions(searchSuggestions);
    } catch (error) {
        if (requestId !== activeSuggestionRequestId) return;
        hideAutocomplete();
        searchSuggestions = [];
        selectedSuggestionIndex = -1;
        console.error('Autocomplete fetch failed:', error);
    }
}

function formatSuggestionSubtitle(result) {
    return [result.admin1, result.country ? cleanLocationName(result.country) : result.country].filter(Boolean).join(', ');
}

function cleanLocationName(name) {
    if (!name) return name;
    // Remove trailing "(the)" artifact from BigDataCloud API
    return name.replace(/\s*\(the\)\s*$/i, '').trim();
}

function formatDisplayLocationName(result) {
    const name = result.name || result.admin1 || result.admin2 || '';
    const resultCountry = result.country ? cleanLocationName(result.country) : '';
    const admin1 = result.admin1 || '';
    const isUS = resultCountry && (
        resultCountry.includes('United States') ||
        resultCountry === 'US' ||
        resultCountry === 'USA'
    );

    if (name && resultCountry) {
        if (isUS && admin1) return `${name}, ${admin1}`;
        if (!isUS) return `${name}, ${resultCountry}`;
        return name;
    }

    if (name) return name;
    if (admin1) return admin1;
    return null;
}

function renderSuggestions(results) {
    if (!searchAutocompleteEl) return;

    if (!results.length) {
        searchAutocompleteEl.innerHTML = '<div class="px-4 py-3 text-sm text-white/60 min-h-[44px]">No matches found</div>';
        showAutocomplete();
        return;
    }

    searchAutocompleteEl.innerHTML = results.map((result, index) => {
        const subtitle = formatSuggestionSubtitle(result);
        const highlightedClass = index === selectedSuggestionIndex ? 'bg-white/20' : 'hover:bg-white/10';
        const cityName = result.name || 'Unknown location';

        return `
            <button
                type="button"
                class="search-autocomplete-item w-full text-left px-4 py-2.5 border-b border-white/5 last:border-b-0 transition-colors ${highlightedClass}"
                data-suggestion-index="${index}"
            >
                <div class="text-white font-semibold leading-tight">${cityName}</div>
                <div class="text-white/50 text-xs mt-1 leading-tight">${subtitle || 'Location'}</div>
            </button>
        `;
    }).join('');

    searchAutocompleteEl.querySelectorAll('[data-suggestion-index]').forEach((item) => {
        item.addEventListener('mousedown', (e) => e.preventDefault());
        item.addEventListener('click', () => {
            const idx = Number(item.dataset.suggestionIndex);
            if (!Number.isNaN(idx) && searchSuggestions[idx]) {
                selectSuggestion(searchSuggestions[idx]);
            }
        });
    });

    showAutocomplete();

    const highlightedItem = searchAutocompleteEl.querySelector(`[data-suggestion-index="${selectedSuggestionIndex}"]`);
    if (highlightedItem) {
        highlightedItem.scrollIntoView({ block: 'nearest' });
    }
}

function selectSuggestion(result) {
    if (!result) return;

    const displayValue = [result.name, result.admin1, result.country].filter(Boolean).join(', ');
    locationInputEl.value = displayValue || result.name || '';
    currentLat = result.latitude;
    currentLon = result.longitude;
    currentLocationName = formatDisplayLocationName(result);

    hideAutocomplete();
    locationInputEl.blur();
    fetchWeather(currentLat, currentLon);
}

// State abbreviation to full name mapping (US states)
const STATE_ABBREVIATIONS = {
    'AL': 'Alabama', 'AK': 'Alaska', 'AZ': 'Arizona', 'AR': 'Arkansas', 'CA': 'California',
    'CO': 'Colorado', 'CT': 'Connecticut', 'DE': 'Delaware', 'FL': 'Florida', 'GA': 'Georgia',
    'HI': 'Hawaii', 'ID': 'Idaho', 'IL': 'Illinois', 'IN': 'Indiana', 'IA': 'Iowa',
    'KS': 'Kansas', 'KY': 'Kentucky', 'LA': 'Louisiana', 'ME': 'Maine', 'MD': 'Maryland',
    'MA': 'Massachusetts', 'MI': 'Michigan', 'MN': 'Minnesota', 'MS': 'Mississippi', 'MO': 'Missouri',
    'MT': 'Montana', 'NE': 'Nebraska', 'NV': 'Nevada', 'NH': 'New Hampshire', 'NJ': 'New Jersey',
    'NM': 'New Mexico', 'NY': 'New York', 'NC': 'North Carolina', 'ND': 'North Dakota', 'OH': 'Ohio',
    'OK': 'Oklahoma', 'OR': 'Oregon', 'PA': 'Pennsylvania', 'RI': 'Rhode Island', 'SC': 'South Carolina',
    'SD': 'South Dakota', 'TN': 'Tennessee', 'TX': 'Texas', 'UT': 'Utah', 'VT': 'Vermont',
    'VA': 'Virginia', 'WA': 'Washington', 'WV': 'West Virginia', 'WI': 'Wisconsin', 'WY': 'Wyoming',
    'DC': 'District of Columbia'
};

// Reverse mapping (full name to abbreviation)
const STATE_NAMES_TO_ABBR = {};
Object.keys(STATE_ABBREVIATIONS).forEach(abbr => {
    STATE_NAMES_TO_ABBR[STATE_ABBREVIATIONS[abbr].toLowerCase()] = abbr;
});

function normalizeState(stateInput) {
    if (!stateInput) return null;
    const state = stateInput.trim();
    // Check if it's an abbreviation
    if (state.length <= 2) {
        return STATE_ABBREVIATIONS[state.toUpperCase()] || state;
    }
    // Check if it's a full name
    const lowerState = state.toLowerCase();
    if (STATE_NAMES_TO_ABBR[lowerState]) {
        return STATE_ABBREVIATIONS[STATE_NAMES_TO_ABBR[lowerState]];
    }
    // Return as-is if not found
    return state;
}

function matchesState(result, searchState) {
    if (!searchState) return true;
    const resultAdmin1 = (result.admin1 || '').toLowerCase();
    const normalizedSearch = normalizeState(searchState).toLowerCase();
    return resultAdmin1 === normalizedSearch ||
           resultAdmin1.includes(normalizedSearch) ||
           normalizedSearch.includes(resultAdmin1);
}

async function handleSearch() {
    const query = document.getElementById('locationInput').value.trim();
    if (!query) return;
    hideAutocomplete();

    try {
        // Parse "City, State" or "City, State, Country" format
        const parts = query.split(',').map(p => p.trim());
        const city = parts[0];
        const state = parts.length > 1 ? parts[1] : null;
        const country = parts.length > 2 ? parts[2] : null;

        // Build search query - use city name, optionally add country filter
        let searchUrl = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(city)}`;
        if (country) {
            searchUrl += `&country=${encodeURIComponent(country)}`;
        }
        // Get more results to filter through (up to 10)
        searchUrl += `&count=10`;

        const response = await fetch(searchUrl);
        const data = await response.json();

        if (data.results && data.results.length > 0) {
            let result = data.results[0];

            // If state was provided, try to find a match
            if (state) {
                const stateMatch = data.results.find(r => matchesState(r, state));
                if (stateMatch) {
                    result = stateMatch;
                } else {
                    // If no exact match, show all results and let user know
                    console.log('State not found, using first result:', result);
                }
            }

            currentLat = result.latitude;
            currentLon = result.longitude;
            currentLocationName = formatDisplayLocationName(result);
            fetchWeather(currentLat, currentLon);
        } else {
            showError('Location not found. Please try another search.');
        }
    } catch (error) {
        showError('Error searching for location. Please try again.');
        console.error(error);
    }
}

async function fetchWeather(lat, lon) {
    currentLat = lat;
    currentLon = lon;
    currentTideData = null;
    showLoading();
    hideError();
    hideContent();

    try {
        // Make direct request to Open-Meteo ensemble endpoint from browser (uses user's IP, not shared Cloudflare IP)
        const weatherResponse = await fetch(`https://ensemble-api.open-meteo.com/v1/ensemble?latitude=${lat}&longitude=${lon}&models=icon_seamless,gfs_seamless,ecmwf_ifs025&hourly=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,precipitation_probability,precipitation,snowfall,surface_pressure,cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,shortwave_radiation,is_day,apparent_temperature,dew_point_2m,uv_index&daily=weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,apparent_temperature_min,precipitation_sum,wind_speed_10m_max,wind_direction_10m_dominant,wind_gusts_10m_max,precipitation_probability_max,snowfall_sum,sunrise,sunset&forecast_days=14&past_days=2&temperature_unit=fahrenheit&windspeed_unit=mph&precipitation_unit=inch&timezone=auto`);

        // Check for rate limiting before parsing JSON
        if (weatherResponse.status === 429) {
            const errorData = await weatherResponse.json().catch(() => ({ error: true, reason: 'Rate limit exceeded' }));
            showError(errorData.reason || 'Rate limit exceeded. Please wait a moment and try again.');
            return;
        }

        if (!weatherResponse.ok) {
            const errorData = await weatherResponse.json().catch(() => ({ error: true, reason: 'Failed to fetch weather data' }));
            showError(errorData.reason || `Failed to fetch weather data (${weatherResponse.status})`);
            return;
        }

        const weatherDataRaw = await weatherResponse.json();

        if (weatherDataRaw.error) {
            showError(weatherDataRaw.reason || 'Failed to fetch weather data');
            return;
        }

        const weatherData = normalizeEnsembleWeatherData(weatherDataRaw, lat, lon);

        // If we don't have a stored location name, try to get it via reverse geocoding
        if (!currentLocationName) {
            try {
                // Make direct request to BigDataCloud from browser (uses user's IP, not shared Cloudflare IP)
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 5000); // 5 second timeout

                const reverseGeoResponse = await fetch(`https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${encodeURIComponent(lat)}&longitude=${encodeURIComponent(lon)}&localityLanguage=en`, {
                    signal: controller.signal
                });

                clearTimeout(timeoutId);

                if (!reverseGeoResponse.ok) {
                    throw new Error(`HTTP ${reverseGeoResponse.status}`);
                }

                const data = await reverseGeoResponse.json();

                // BigDataCloud returns data directly - transform to match expected format
                if (data) {
                    // Try to get city name, fallback to town, village, or municipality
                    const cityName = data.city || data.locality || data.town || data.village || data.municipality || data.county;
                    const stateName = data.principalSubdivision;
                    const countryName = cleanLocationName(data.countryName);

                    // Check if it's US (handle various formats like "United States", "United States of America", etc.)
                    const isUS = countryName && (
                        countryName.includes('United States') ||
                        countryName === 'US' ||
                        countryName === 'USA'
                    );

                    if (cityName) {
                        if (stateName && isUS) {
                            // For US locations, show "City, State"
                            currentLocationName = `${cityName}, ${stateName}`;
                        } else if (countryName && !isUS) {
                            // For non-US locations, show "City, Country"
                            currentLocationName = `${cityName}, ${countryName}`;
                        } else {
                            currentLocationName = cityName;
                        }
                    } else if (stateName && isUS) {
                        currentLocationName = stateName;
                    } else if (countryName && !isUS) {
                        currentLocationName = countryName;
                    }
                }
            } catch (error) {
                // Log error for debugging but don't break the app
                console.error('Reverse geocoding failed:', error.message);
            }
        }

        try {
            currentTideData = await fetchTideDataForLocation(lat, lon, weatherData.elevation);
        } catch (tideError) {
            currentTideData = null;
            console.error('NOAA tide fetch failed:', tideError.message);
        }

        currentWeatherData = weatherData; // Store for modals
        currentPollenData = null; // Clear previous location's pollen while new data loads
        currentNiceWeatherData = null; // Clear previous location's nice weather reasoning
        displayWeather(weatherData);

        // Initialize Ventusky radar
        initializeVentuskyRadar(lat, lon);

        // Fetch weather alerts (for US locations)
        fetchWeatherAlerts(lat, lon);

        // Fetch air quality data
        fetchAirQuality(lat, lon);
    } catch (error) {
        showError('Failed to fetch weather data. Please try again.');
        console.error(error);
    } finally {
        hideLoading();
    }
}

// ─── Horizon dynamic background theme ───────────────────
const WMO_THEMES = {
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
    95: 'storm', 96: 'storm', 99: 'storm',
};

function setTheme(weatherCode, isDay) {
    const bgLayer = document.getElementById('bgLayer');
    if (!bgLayer) return;
    const isLight = document.documentElement.getAttribute('data-theme') === 'light';
    if (!isLight) {
        // Dark mode: static deep-blue background, no weather theme
        bgLayer.className = 'bg-layer';
        return;
    }
    // Light mode: apply weather-reactive gradient
    let theme = WMO_THEMES[weatherCode] || 'cloudy';
    if (!isDay && (weatherCode === 0 || weatherCode === 1)) theme = 'clear-night';
    bgLayer.className = 'bg-layer ' + theme;
}

// Update sun/moon marker so its center sits exactly on the sun-arc path.
// Arc is an SVG half-ellipse path; marker is HTML so it stays circular.
// Screen-space projection pins the marker center onto the stroked path.
let _sunArcRiseIso = null;
let _sunArcSetIso = null;
let _sunArcUtcOffset = 0;
let _sunArcTimer = null;
let _sunArcRaf = 0;
let _sunArcGen = 0;

// Open-Meteo timezone=auto returns sunrise/sunset as wall-clock ISO without offset
// ("2026-07-08T05:45"). new Date() treats that as the browser zone — wrong for other cities.
function parseLocationLocalIso(iso, utcOffsetSeconds = 0) {
    if (!iso) return NaN;
    const s = String(iso);
    if (/[zZ]$|[+-]\d{2}:?\d{2}$/.test(s)) {
        const ms = new Date(s).getTime();
        return Number.isFinite(ms) ? ms : NaN;
    }
    const m = s.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/);
    if (!m) {
        const ms = new Date(s).getTime();
        return Number.isFinite(ms) ? ms : NaN;
    }
    const asUtc = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0));
    return asUtc - (Number(utcOffsetSeconds) || 0) * 1000;
}

// Format Open-Meteo local wall clock without shifting into the browser timezone
function formatIsoLocalClock(iso) {
    const m = String(iso || '').match(/T(\d{2}):(\d{2})/);
    if (!m) return formatTime12Hour(new Date(iso));
    let h = parseInt(m[1], 10);
    const mi = m[2];
    const ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12 || 12;
    return `${h}:${mi} ${ampm}`;
}

function updateSunDot(sunriseIso, sunsetIso, utcOffsetSeconds = _sunArcUtcOffset) {
    const sunDot = document.getElementById('sunDot');
    const arcEl = sunDot && sunDot.parentElement;
    if (!sunDot || !arcEl || !sunriseIso || !sunsetIso) return;

    _sunArcRiseIso = sunriseIso;
    _sunArcSetIso = sunsetIso;
    _sunArcUtcOffset = Number(utcOffsetSeconds) || 0;
    const gen = ++_sunArcGen;

    // #weatherContent is often still display:none when displayWeather first runs (zero width).
    // Never apply coords from a collapsed arc — that freezes the marker on the previous city.
    if (arcEl.clientWidth < 8 || arcEl.offsetWidth < 8) {
        if (_sunArcRaf) cancelAnimationFrame(_sunArcRaf);
        _sunArcRaf = requestAnimationFrame(() => {
            _sunArcRaf = 0;
            if (gen !== _sunArcGen) return;
            updateSunDot(sunriseIso, sunsetIso, utcOffsetSeconds);
        });
        return;
    }

    const now = Date.now();
    const rise = parseLocationLocalIso(sunriseIso, _sunArcUtcOffset);
    const set = parseLocationLocalIso(sunsetIso, _sunArcUtcOffset);
    if (!Number.isFinite(rise) || !Number.isFinite(set) || set <= rise) return;

    const isDay = now >= rise && now <= set;

    // Day progress along the arc; night parks at the ends (pre-dawn left, post-dusk right)
    let t = 0;
    if (now <= rise) t = 0;
    else if (now >= set) t = 1;
    else t = (now - rise) / (set - rise);

    // Parametric half-ellipse on the SVG path (viewBox 0 0 1000 100):
    // theta PI (sunrise/left) -> 0 (sunset/right). Map SVG user space -> screen
    // so the 12px HTML marker center sits exactly on the stroked path.
    const theta = Math.PI * (1 - t);
    const pathEl = document.getElementById('sunArcPath');
    const svgEl = pathEl && pathEl.ownerSVGElement;

    let x;
    let y;
    if (pathEl && svgEl && typeof svgEl.createSVGPoint === 'function') {
        const pt = svgEl.createSVGPoint();
        pt.x = 500 + 500 * Math.cos(theta);
        pt.y = 100 - 100 * Math.sin(theta);
        const ctm = pathEl.getScreenCTM();
        if (ctm) {
            const screen = pt.matrixTransform(ctm);
            const arcRect = arcEl.getBoundingClientRect();
            x = screen.x - arcRect.left;
            y = screen.y - arcRect.top;
        }
    }
    // Fallback if SVG matrix unavailable (shouldn't happen in modern browsers)
    if (x === undefined || y === undefined) {
        const a = arcEl.offsetWidth / 2;
        const b = arcEl.offsetHeight;
        x = a + a * Math.cos(theta);
        y = b - b * Math.sin(theta);
    }

    // Jump immediately on location change (skip 0.8s slide from previous city)
    const prevTransition = sunDot.style.transition;
    sunDot.style.transition = 'none';
    sunDot.style.left = `${x}px`;
    sunDot.style.top = `${y}px`;
    sunDot.style.bottom = 'auto';
    void sunDot.offsetWidth; // reflow so re-enabling transition does not interpolate
    sunDot.style.transition = prevTransition || '';

    sunDot.classList.toggle('is-moon', !isDay);
    sunDot.setAttribute('aria-label', isDay ? 'Sun position' : 'Moon (sun is down)');
    sunDot.title = isDay ? 'Sun' : 'Moon';

    if (!_sunArcTimer) {
        _sunArcTimer = setInterval(() => {
            if (_sunArcRiseIso && _sunArcSetIso) {
                updateSunDot(_sunArcRiseIso, _sunArcSetIso, _sunArcUtcOffset);
            }
        }, 60_000);
        window.addEventListener('resize', () => {
            if (_sunArcRiseIso && _sunArcSetIso) {
                updateSunDot(_sunArcRiseIso, _sunArcSetIso, _sunArcUtcOffset);
            }
        });
        if (typeof ResizeObserver !== 'undefined') {
            const ro = new ResizeObserver(() => {
                if (_sunArcRiseIso && _sunArcSetIso) {
                    updateSunDot(_sunArcRiseIso, _sunArcSetIso, _sunArcUtcOffset);
                }
            });
            ro.observe(arcEl);
        }
    }
}

function displayWeather(data) {
    setHourlyTidesVisibility(currentTideData);
    setDailyTidesVisibility(currentTideData);

    // Use stored location name if available (from search or reverse geocoding)
    let location = currentLocationName;

    // If we still don't have a location name, show coordinates as last resort
    if (!location) {
        location = `${data.latitude.toFixed(2)}, ${data.longitude.toFixed(2)}`;
    }

    // Current weather
    document.getElementById('currentLocation').textContent = location;
    document.getElementById('currentDate').textContent = new Date().toLocaleDateString('en-US', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric'
    });

    // Last updated timestamp
    document.getElementById('lastUpdated').textContent = `Updated ${formatLastUpdated(new Date())}`;

    document.getElementById('currentTemp').textContent = `${Math.round(data.current.temperature_2m)}${data.current_units.temperature_2m}`;
    const currentIconEl = document.getElementById('currentIcon');
    if (currentIconEl) {
        currentIconEl.textContent = getWeatherIcon(data.current.weather_code, data.current.is_day !== 0);
        currentIconEl.setAttribute('aria-hidden', 'true');
    }

    // Set dynamic background theme based on current conditions
    setTheme(data.current.weather_code, data.current.is_day !== 0);

    // Display today's high/low temperatures (index 2 because of past_days=2)
    if (data.daily && data.daily.temperature_2m_max && data.daily.temperature_2m_max[2] !== undefined) {
        const todayHigh = Math.round(data.daily.temperature_2m_max[2]);
        const todayLow = Math.round(data.daily.temperature_2m_min[2]);
        // Use compact format for mobile, full format for desktop
        const isMobile = window.innerWidth <= 768;
        document.getElementById('currentHighLow').textContent = isMobile ?
            `${todayHigh}°/${todayLow}°` : `H:${todayHigh}° L:${todayLow}°`;
    }

    document.getElementById('currentCondition').textContent = getWeatherDescription(data.current.weather_code);
    document.getElementById('feelsLike').textContent = `${Math.round(data.current.apparent_temperature)}${data.current_units.apparent_temperature}`;
    document.getElementById('humidity').textContent = `${data.current.relative_humidity_2m}${data.current_units.relative_humidity_2m}`;

    // Dew point
    if (data.current.dewpoint_2m !== undefined) {
        document.getElementById('dewPoint').textContent = `${Math.round(data.current.dewpoint_2m)}${data.current_units.dewpoint_2m}`;
    }

    document.getElementById('windSpeed').textContent = `${data.current.wind_speed_10m} ${formatUnit(data.current_units.wind_speed_10m)}`;
    document.getElementById('uvIndex').textContent = data.current.uv_index;

    // Pressure with trend
    displayPressure(data);

    // Sunrise and sunset times (today is index 2 due to past_days=2).
    // Labels use wall-clock from the ISO string (location local), not browser timezone.
    // Dot position is applied after showContent() so the arc has real layout width.
    const todayIndex = 2;
    if (data.daily && data.daily.sunrise && data.daily.sunrise[todayIndex]) {
        document.getElementById('sunrise').textContent = formatIsoLocalClock(data.daily.sunrise[todayIndex]);
    }
    if (data.daily && data.daily.sunset && data.daily.sunset[todayIndex]) {
        document.getElementById('sunset').textContent = formatIsoLocalClock(data.daily.sunset[todayIndex]);
    }

    // Moon phase (for today)
    const today = new Date();
    const moonPhaseValue = calculateMoonPhase(today);
    const moonPhase = getMoonPhase(moonPhaseValue);
    document.getElementById('moonPhaseEmoji').textContent = moonPhase.emoji;
    document.getElementById('moonPhaseName').textContent = moonPhase.name;

    // Make moon phase card clickable
    const moonPhaseCard = document.getElementById('moonPhase');
    if (moonPhaseCard) {
        moonPhaseCard.style.cursor = 'pointer';
        moonPhaseCard.addEventListener('click', () => openMoonDetailsModal(today));
    }

    // Calculate and display symptom risks
    if (data.hourly && data.hourly.surface_pressure) {
        // Get today's date and yesterday's date
        const todayDate = new Date();
        const yesterdayDate = new Date(todayDate);
        yesterdayDate.setDate(yesterdayDate.getDate() - 1);

        // Calculate daily averages for today and yesterday
        const todayAvg = calculateDailyAverages(data.hourly, todayDate);
        const yesterdayAvg = calculateDailyAverages(data.hourly, yesterdayDate);

        if (todayAvg) {
            // Calculate pressure change (today - yesterday)
            const pressureChange = yesterdayAvg ?
                (todayAvg.avgPressureInhg - yesterdayAvg.avgPressureInhg) : 0;

            // Get temperature swing from daily data (today is at index 2 due to past_days=2)
            const todayIndex = 2;
            const tempSwing = data.daily.temperature_2m_max[todayIndex] -
                             data.daily.temperature_2m_min[todayIndex];

            // Store symptom data for modal display
            currentSymptomData = {
                pressureChange: pressureChange,
                humidity: todayAvg.avgHumidity,
                precipitation: todayAvg.precipSum,
                tempSwing: tempSwing,
                avgTemp: todayAvg.avgTemp,
                windMax: todayAvg.windMax
            };

            // Calculate risks
            const sinusRisk = calculateSinusRisk(
                pressureChange,
                todayAvg.avgHumidity,
                todayAvg.precipSum,
                tempSwing
            );

            // Initial allergy risk - will be updated when pollen data arrives
            const allergyRisk = calculateAllergyRisk(
                todayAvg.windMax,
                todayAvg.precipSum,
                currentPollenData
            );

            // Display sinus risk
            const sinusLabel = getRiskLabel(sinusRisk);
            document.getElementById('sinusRiskValue').textContent = `${sinusRisk}/10`;
            document.getElementById('sinusRiskLabel').textContent = sinusLabel.label;
            document.getElementById('sinusRiskLabel').className = `text-xs font-semibold ${sinusLabel.colorClass}`;

            // Display allergy risk
            updateAllergyRiskDisplay(allergyRisk);

            // Display nice weather index (higher is nicer)
            const niceWeatherIndex = calculateNiceWeatherIndex(data, todayAvg, todayIndex);
            currentNiceWeatherData = getNiceWeatherBreakdown(data, todayAvg, todayIndex);
            updateNiceWeatherDisplay(niceWeatherIndex);
        }
    }

    // Precipitation timing
    displayPrecipitationTiming(data);

    // Hourly forecast — conditions view
    const hourlyContainer = document.getElementById('hourlyViewConditions').querySelector('.flex');
    hourlyContainer.innerHTML = '';
    // Hourly forecast — precipitation view
    const precipContainer = document.getElementById('hourlyPrecipContainer');
    precipContainer.innerHTML = '';
    // Hourly forecast — wind view
    const windContainer = document.getElementById('hourlyWindContainer');
    windContainer.innerHTML = '';

    // Find max precipitation for scaling bars
    let maxPrecip = 0;

    const now = new Date();
    const currentHour = now.getHours();

    // Find today's data in the hourly forecast (skip past days due to past_days=2)
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0); // Set to start of today

    let startIndex = 0;
    // Find the first hour of today
    for (let i = 0; i < data.hourly.time.length; i++) {
        const hourTime = new Date(data.hourly.time[i]);
        hourTime.setHours(0, 0, 0, 0); // Set to start of that day
        if (hourTime.getTime() >= todayStart.getTime()) {
            // Found today's data, now find the closest hour to current time
            for (let j = i; j < data.hourly.time.length; j++) {
                const currentHourTime = new Date(data.hourly.time[j]);
                if (currentHourTime.getHours() >= currentHour) {
                    startIndex = j;
                    break;
                }
            }
            if (startIndex > 0) break; // Found it
        }
    }

    // First pass: find max precipitation for scaling
    for (let i = 0; i < HOURLY_FORECAST_HOURS && (startIndex + i) < data.hourly.time.length; i++) {
        const hourIndex = startIndex + i;
        const p = data.hourly.precipitation ? (data.hourly.precipitation[hourIndex] || 0) : 0;
        if (p > maxPrecip) maxPrecip = p;
    }
    // Avoid division by zero
    const precipScale = maxPrecip > 0 ? maxPrecip : 1;

    for (let i = 0; i < HOURLY_FORECAST_HOURS && (startIndex + i) < data.hourly.time.length; i++) {
        const hourIndex = startIndex + i;
        const hour = new Date(data.hourly.time[hourIndex]);

        // ── Conditions view (existing) ──
        const hourItem = document.createElement('div');
        hourItem.className = 'flex flex-col items-center forecast-chip hourly-chip rounded-lg p-3 backdrop-blur-sm clickable';
        hourItem.innerHTML = `
            <div class="text-white/70 text-sm mb-1">${formatTime12Hour(hour)}</div>
            <div class="text-2xl mb-2">${getWeatherIcon(data.hourly.weather_code[hourIndex], data.hourly.is_day ? data.hourly.is_day[hourIndex] !== 0 : true)}</div>
            <div class="text-white font-bold text-lg">${Math.round(data.hourly.temperature_2m[hourIndex])}${UNITS.temperature}</div>
            <div class="text-white/60 text-xs mt-1">${data.hourly.wind_speed_10m[hourIndex]} ${UNITS.wind}</div>
        `;
        hourItem.addEventListener('click', () => openHourlyModal(data));
        hourlyContainer.appendChild(hourItem);

        // ── Precipitation view ──
        const precipVal = data.hourly.precipitation ? (data.hourly.precipitation[hourIndex] || 0) : 0;
        const precipProb = data.hourly.precipitation_probability ? (data.hourly.precipitation_probability[hourIndex] ?? 0) : 0;
        const barHeight = precipVal > 0 ? Math.max(4, (precipVal / precipScale) * 40) : 2;
        const precipItem = document.createElement('div');
        precipItem.className = 'flex flex-col items-center forecast-chip hourly-chip rounded-lg p-3 backdrop-blur-sm clickable';
        precipItem.innerHTML = `
            <div class="text-white/70 text-sm mb-1">${formatTime12Hour(hour)}</div>
            <div class="hourly-precip-bar-container">
                <div class="hourly-precip-bar ${precipVal === 0 ? 'zero' : ''}" style="height: ${barHeight}px"></div>
            </div>
            <div class="text-white font-bold text-sm mt-1">${precipVal > 0 ? precipVal.toFixed(2) + '"' : '0"'}</div>
            <div class="text-white/60 text-xs mt-1">${precipProb}%</div>
        `;
        precipItem.addEventListener('click', () => openHourlyModal(data));
        precipContainer.appendChild(precipItem);

        // ── Wind view ──
        const windSpeed = data.hourly.wind_speed_10m[hourIndex] || 0;
        const windGust = data.hourly.wind_gusts_10m ? (data.hourly.wind_gusts_10m[hourIndex] || 0) : null;
        const windDir = data.hourly.wind_direction_10m ? (data.hourly.wind_direction_10m[hourIndex] ?? 0) : 0;
        // Wind direction arrow: CSS rotation. Arrow points FROM the direction the wind blows.
        // wind_direction_10m is meteorological: direction FROM which wind blows. Arrow should point opposite.
        const arrowRotation = windDir + 180;
        const windItem = document.createElement('div');
        windItem.className = 'flex flex-col items-center forecast-chip hourly-chip rounded-lg p-3 backdrop-blur-sm clickable';
        windItem.innerHTML = `
            <div class="text-white/70 text-sm mb-1">${formatTime12Hour(hour)}</div>
            <div class="wind-arrow" style="transform: rotate(${arrowRotation}deg)">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <line x1="12" y1="19" x2="12" y2="5"/>
                    <polyline points="5 12 12 5 19 12"/>
                </svg>
            </div>
            <div class="text-white font-bold text-lg mt-1">${Math.round(windSpeed)}</div>
            <div class="text-white/60 text-xs mt-1">${UNITS.wind}${windGust !== null ? ' G' + Math.round(windGust) : ''}</div>
        `;
        windItem.addEventListener('click', () => openHourlyModal(data));
        windContainer.appendChild(windItem);
    }

    // Wire up toggle buttons
    const toggleBtns = document.querySelectorAll('#hourlyHighlightsToggle .highlights-toggle-btn');
    const toggleLabel = document.getElementById('hourlyToggleLabel');
    const viewIds = {
        conditions: 'hourlyViewConditions',
        precipitation: 'hourlyViewPrecipitation',
        wind: 'hourlyViewWind',
    };
    const labelMap = {
        conditions: 'Conditions',
        precipitation: 'Precipitation',
        wind: 'Wind',
    };
    toggleBtns.forEach(btn => {
        // Remove any previous listener by cloning
        const newBtn = btn.cloneNode(true);
        btn.parentNode.replaceChild(newBtn, btn);
        newBtn.addEventListener('click', () => {
            const mode = newBtn.getAttribute('data-mode');
            // Update button active states
            document.querySelectorAll('#hourlyHighlightsToggle .highlights-toggle-btn').forEach(b => b.classList.remove('active'));
            newBtn.classList.add('active');
            // Update label
            toggleLabel.textContent = labelMap[mode] || mode;
            toggleLabel.classList.add('active');
            // Show correct view, hide others
            Object.entries(viewIds).forEach(([m, id]) => {
                const el = document.getElementById(id);
                if (m === mode) el.classList.add('active');
                else el.classList.remove('active');
            });
        });
    });

    // Daily forecast
    const dailyContainer = document.getElementById('dailyForecast');
    dailyContainer.innerHTML = '';

    // Check if mobile to use abbreviated day names
    const isMobile = window.innerWidth <= 768;
    const weekdayFormat = isMobile ? 'short' : 'long';

    // Start from index 2 to skip past 2 days due to past_days=2
    for (let i = 0; i < Math.min(14, data.daily.time.length - 2); i++) {
        const dayIndex = i + 2; // Skip past days
        const day = parseDateString(data.daily.time[dayIndex]);
        const tideSummary = currentTideData?.dailySummaries ? currentTideData.dailySummaries[formatDateKey(day)] : null;
        const tideSummaryText = formatTideSummary(tideSummary);
        const apparentMaxRaw = data.daily.apparent_temperature_max ? data.daily.apparent_temperature_max[dayIndex] : null;
        const apparentMinRaw = data.daily.apparent_temperature_min ? data.daily.apparent_temperature_min[dayIndex] : null;
        const hasApparentTemps = apparentMaxRaw !== null && apparentMaxRaw !== undefined && apparentMinRaw !== null && apparentMinRaw !== undefined;
        const apparentMax = hasApparentTemps ? Math.round(apparentMaxRaw) : null;
        const apparentMin = hasApparentTemps ? Math.round(apparentMinRaw) : null;
        const apparentUnit = UNITS.temperature;

        // Week separator every 7 days
        if (i > 0 && i % 7 === 0) {
            const separator = document.createElement('div');
            separator.className = 'week-separator flex items-center gap-3 my-4 px-2';
            separator.innerHTML = `
                <div class="flex-1 h-px bg-white/10"></div>
                <span class="text-white/40 text-xs font-semibold tracking-wider uppercase">Week ${Math.floor(i / 7) + 1}</span>
                <div class="flex-1 h-px bg-white/10"></div>
            `;
            dailyContainer.appendChild(separator);
        }

        const dayItem = document.createElement('div');
        dayItem.className = 'daily-forecast-card forecast-chip rounded-lg p-4 backdrop-blur-sm clickable';
        dayItem.innerHTML = `
            <div class="daily-forecast-main">
                <div class="daily-forecast-date">
                    <div class="daily-forecast-icon text-3xl">${getWeatherIcon(data.daily.weather_code[dayIndex], true, data.daily.precipitation_probability_max ? data.daily.precipitation_probability_max[dayIndex] : null)}</div>
                    <div class="min-w-0">
                        <div class="daily-forecast-day text-white font-semibold text-lg">${day.toLocaleDateString('en-US', { weekday: weekdayFormat })}</div>
                        <div class="daily-forecast-date-label text-white/70 text-sm">${day.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}</div>
                    </div>
                </div>
                <div class="daily-forecast-details">
                    <div class="daily-forecast-temps text-right">
                        <div class="daily-forecast-high text-white font-bold text-xl">${Math.round(data.daily.temperature_2m_max[dayIndex])}${UNITS.temperature}</div>
                        <div class="daily-forecast-low text-white/70 text-sm">${Math.round(data.daily.temperature_2m_min[dayIndex])}${UNITS.temperature}</div>
                        ${hasApparentTemps ? `<div class="daily-forecast-feels text-white/50 text-xs">Feels like ${apparentMax}${apparentUnit} / ${apparentMin}${apparentUnit}</div>` : ''}
                    </div>
                    <div class="daily-forecast-metrics text-white/70 text-sm text-right">
                        ${data.daily.snowfall_sum && data.daily.snowfall_sum[dayIndex] > 0 ? '' : `<div><i class="fas fa-tint mr-1"></i>${data.daily.precipitation_sum[dayIndex] || 0} ${UNITS.precipitation}</div>`}
                        ${data.daily.snowfall_sum && data.daily.snowfall_sum[dayIndex] > 0 ? `<div><i class="fas fa-snowflake mr-1"></i>${data.daily.snowfall_sum[dayIndex]} ${UNITS.snowfall}</div>` : ''}
                        ${data.daily.snowfall_sum && data.daily.snowfall_sum[dayIndex] > 0 ? (data.daily.precipitation_probability_max && data.daily.precipitation_probability_max[dayIndex] !== null && data.daily.precipitation_probability_max[dayIndex] !== undefined ? `<div><i class="fas fa-snowflake mr-1"></i>${data.daily.precipitation_probability_max[dayIndex]}%</div>` : '') : (data.daily.precipitation_probability_max && data.daily.precipitation_probability_max[dayIndex] !== null && data.daily.precipitation_probability_max[dayIndex] !== undefined ? `<div><i class="fas fa-tint mr-1"></i>${data.daily.precipitation_probability_max[dayIndex]}%</div>` : '')}
                        <div><i class="fas fa-wind mr-1"></i>${data.daily.wind_speed_10m_max[dayIndex]} ${UNITS.wind}</div>
                    </div>
                </div>
            </div>
            ${tideSummaryText ? `
            <div class="daily-forecast-tide mt-3 pt-3 border-t border-cyan-400/20 text-cyan-100/90 text-xs md:text-sm">
                <i class="fas fa-water mr-2 text-cyan-300/90"></i><span>${tideSummaryText}</span>
            </div>
            ` : ''}
        `;

        dayItem.addEventListener('click', () => openDailyModal(data));
        dailyContainer.appendChild(dayItem);
    }

    // Display weekly snow totals if there's snow in the forecast
    displayWeeklySnowTotals(data);

    showContent();

    // Sun/moon marker must run AFTER content is visible — hidden nodes report width 0.
    // Double rAF covers post-paint layout (fonts / sticky header / skeleton swap).
    if (data.daily && data.daily.sunrise && data.daily.sunset) {
        const todayIndex = 2;
        const riseIso = data.daily.sunrise[todayIndex];
        const setIso = data.daily.sunset[todayIndex];
        const offset = data.utc_offset_seconds || 0;
        const placeSun = () => updateSunDot(riseIso, setIso, offset);
        placeSun();
        requestAnimationFrame(() => requestAnimationFrame(placeSun));
    }

    // Add click handlers to section headers
    if (currentWeatherData) {
        document.getElementById('hourlyHeader').addEventListener('click', () => openHourlyModal(currentWeatherData));
        document.getElementById('dailyHeader').addEventListener('click', () => openDailyModal(currentWeatherData));
    }
}

async function displayWeeklySnowTotals(data) {
    const snowSection = document.getElementById('weeklySnowSection');
    const snowContent = document.getElementById('weeklySnowContent');
    snowContent.innerHTML = '';

    // Check if there's any snow in the forecast
    if (!data.daily.snowfall_sum) {
        snowSection.classList.add('hidden');
        return;
    }

    // Collect all days with snow
    const snowDays = [];
    // Check if mobile to use abbreviated day names
    const isMobile = window.innerWidth <= 768;
    const weekdayFormat = isMobile ? 'short' : 'long';

    // Start from index 2 to skip past 2 days due to past_days=2
    for (let i = 0; i < Math.min(14, data.daily.time.length - 2); i++) {
        const dayIndex = i + 2; // Skip past days
        const snowfall = data.daily.snowfall_sum[dayIndex] || 0;
        if (snowfall > 0) {
            const day = parseDateString(data.daily.time[dayIndex]);
            const dayName = day.toLocaleDateString('en-US', { weekday: weekdayFormat });
            const dateStr = day.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
            // Round to nearest 0.1 inch
            const roundedSnow = Math.round(snowfall * 10) / 10;
            snowDays.push({
                dayName,
                dateStr,
                snowfall: roundedSnow,
                index: i
            });
        }
    }

    if (snowDays.length === 0) {
        snowSection.classList.add('hidden');
        return;
    }

    // Group consecutive days
    const snowPeriods = [];
    let currentPeriod = null;

    for (let i = 0; i < snowDays.length; i++) {
        const snowDay = snowDays[i];

        if (!currentPeriod) {
            // Start new period
            currentPeriod = {
                days: [snowDay],
                totalSnow: snowDay.snowfall
            };
        } else {
            // Check if consecutive (within 1 day index difference)
            const lastDayIndex = currentPeriod.days[currentPeriod.days.length - 1].index;
            if (snowDay.index === lastDayIndex + 1) {
                // Consecutive day - add to current period
                currentPeriod.days.push(snowDay);
                currentPeriod.totalSnow += snowDay.snowfall;
            } else {
                // Not consecutive - save current period and start new one
                snowPeriods.push(currentPeriod);
                currentPeriod = {
                    days: [snowDay],
                    totalSnow: snowDay.snowfall
                };
            }
        }
    }

    // Add the last period
    if (currentPeriod) {
        snowPeriods.push(currentPeriod);
    }

    // Display snow periods
    snowSection.classList.remove('hidden');

    snowPeriods.forEach(period => {
        const periodItem = document.createElement('div');
        periodItem.className = 'forecast-chip rounded-lg p-4 backdrop-blur-sm';

        // Round total to nearest 0.1
        const totalSnowRounded = Math.round(period.totalSnow * 10) / 10;

        // Determine unit (inch vs inches)
        const unit = totalSnowRounded === 1.0 ? 'inch' : 'inches';

        let periodText;
        if (period.days.length === 1) {
            // Single day
            const day = period.days[0];
            periodText = `Snowfall on ${day.dayName} (${day.dateStr}) is ${totalSnowRounded.toFixed(1)} ${unit}`;

            periodItem.innerHTML = `
                <div class="text-white font-semibold">${periodText}</div>
            `;
        } else {
            // Multiple days - show range
            const firstDay = period.days[0];
            const lastDay = period.days[period.days.length - 1];
            periodText = `Snowfall between ${firstDay.dayName} (${firstDay.dateStr}) and ${lastDay.dayName} (${lastDay.dateStr}) is ${totalSnowRounded.toFixed(1)} ${unit}`;

            // Add breakdown of individual days
            const dayBreakdown = period.days.map(day => {
                const dayUnit = day.snowfall === 1.0 ? 'inch' : 'inches';
                return `${day.dayName}: ${day.snowfall.toFixed(1)} ${dayUnit}`;
            }).join(' • ');

            periodItem.innerHTML = `
                <div class="flex-1">
                    <div class="text-white font-semibold mb-1">${periodText}</div>
                    <div class="text-white/70 text-sm">${dayBreakdown}</div>
                </div>
            `;
        }

        snowContent.appendChild(periodItem);
    });

    try {
        const nws = await fetchNwsSnowForecast(currentLat, currentLon);
        if (!nws.unavailable && nws.totalInches >= 0.1) {
            const nwsLine = document.createElement('p');
            nwsLine.className = 'text-gray-400 text-sm mt-3';
            nwsLine.textContent = `NWS 48h forecast: ${nws.totalInches.toFixed(1)} in`;
            snowContent.appendChild(nwsLine);
        }
    } catch (error) {
        console.error('NWS weekly snow line error:', error);
    }
}

function getWeatherIcon(code, isDay = true, precipProbability = null) {
    // Suppress rain/drizzle icons when precipitation probability is low (<= 30%)
    // Downgrade to partly cloudy instead
    if (precipProbability !== null && precipProbability <= 30) {
        const rainCodes = [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99];
        if (rainCodes.includes(code)) {
            code = 2; // Partly cloudy
        }
    }
    // WMO Weather interpretation codes
    // Night variants for clear/partly cloudy conditions
    if (!isDay) {
        const nightIcons = {
            0: '🌙', 1: '🌙', 2: '☁️', 3: '☁️',
            45: '🌫️', 48: '🌫️',
            51: '🌧️', 53: '🌧️', 55: '🌧️',
            56: '🌨️', 57: '🌨️',
            61: '🌧️', 63: '🌧️', 65: '🌧️',
            66: '🌨️', 67: '🌨️',
            71: '❄️', 73: '❄️', 75: '❄️',
            77: '❄️',
            80: '🌧️', 81: '🌧️', 82: '🌧️',
            85: '🌨️', 86: '🌨️',
            95: '⛈️', 96: '⛈️', 99: '⛈️'
        };
        return nightIcons[code] || '🌙';
    }
    const icons = {
        0: '☀️', 1: '🌤️', 2: '⛅', 3: '☁️',
        45: '🌫️', 48: '🌫️',
        51: '🌦️', 53: '🌦️', 55: '🌦️',
        56: '🌨️', 57: '🌨️',
        61: '🌧️', 63: '🌧️', 65: '🌧️',
        66: '🌨️', 67: '🌨️',
        71: '❄️', 73: '❄️', 75: '❄️',
        77: '❄️',
        80: '🌦️', 81: '🌦️', 82: '🌦️',
        85: '🌨️', 86: '🌨️',
        95: '⛈️', 96: '⛈️', 99: '⛈️'
    };
    return icons[code] || '☀️';
}

function getWeatherDescription(code) {
    const descriptions = {
        0: 'Clear sky', 1: 'Mainly clear', 2: 'Partly cloudy', 3: 'Overcast',
        45: 'Foggy', 48: 'Depositing rime fog',
        51: 'Light drizzle', 53: 'Moderate drizzle', 55: 'Dense drizzle',
        56: 'Light freezing drizzle', 57: 'Dense freezing drizzle',
        61: 'Slight rain', 63: 'Moderate rain', 65: 'Heavy rain',
        66: 'Light freezing rain', 67: 'Heavy freezing rain',
        71: 'Slight snow', 73: 'Moderate snow', 75: 'Heavy snow',
        77: 'Snow grains',
        80: 'Slight rain showers', 81: 'Moderate rain showers', 82: 'Violent rain showers',
        85: 'Slight snow showers', 86: 'Heavy snow showers',
        95: 'Thunderstorm', 96: 'Thunderstorm with slight hail', 99: 'Thunderstorm with heavy hail'
    };
    return descriptions[code] || 'Unknown';
}

function calculateMoonPhase(date) {
    // Calculate days since known new moon (January 6, 2000 18:14 UTC)
    const knownNewMoon = new Date('2000-01-06T18:14:00Z');
    const daysSinceNewMoon = (date - knownNewMoon) / (1000 * 60 * 60 * 24);

    // Moon cycle is approximately 29.53058867 days
    const moonCycle = 29.53058867;
    const phase = (daysSinceNewMoon % moonCycle) / moonCycle;

    // Ensure phase is between 0 and 1
    return phase < 0 ? phase + 1 : phase;
}

function getMoonPhase(phase) {
    // Moon phase is a value from 0 to 1
    // 0 = New Moon, 0.25 = First Quarter, 0.5 = Full Moon, 0.75 = Last Quarter
    if (phase === null || phase === undefined) return { emoji: '🌑', name: 'Unknown' };

    if (phase < 0.03 || phase >= 0.97) {
        return { emoji: '🌑', name: 'New Moon' };
    } else if (phase >= 0.03 && phase < 0.22) {
        return { emoji: '🌒', name: 'Waxing Crescent' };
    } else if (phase >= 0.22 && phase < 0.28) {
        return { emoji: '🌓', name: 'First Quarter' };
    } else if (phase >= 0.28 && phase < 0.47) {
        return { emoji: '🌔', name: 'Waxing Gibbous' };
    } else if (phase >= 0.47 && phase < 0.53) {
        return { emoji: '🌕', name: 'Full Moon' };
    } else if (phase >= 0.53 && phase < 0.72) {
        return { emoji: '🌖', name: 'Waning Gibbous' };
    } else if (phase >= 0.72 && phase < 0.78) {
        return { emoji: '🌗', name: 'Last Quarter' };
    } else {
        return { emoji: '🌘', name: 'Waning Crescent' };
    }
}

function getMoonIllumination(date) {
    // Use SunCalc to get accurate moon illumination
    // Returns illuminated fraction (0 to 1), convert to percentage
    const moonIllumination = SunCalc.getMoonIllumination(date);
    return Math.round(moonIllumination.fraction * 100);
}

function calculateMoonDistance(date, lat, lon) {
    // Use SunCalc to get accurate moon distance
    // Distance is returned in kilometers, convert to miles
    const moonPosition = SunCalc.getMoonPosition(date, lat, lon);
    // Distance is in kilometers, convert to miles (1 km = 0.621371 miles)
    const distanceInMiles = moonPosition.distance * 0.621371;
    return Math.round(distanceInMiles);
}

function calculateMoonRiseSet(date, lat, lon) {
    // Use SunCalc to get accurate moonrise/moonset times
    const moonTimes = SunCalc.getMoonTimes(date, lat, lon);

    // SunCalc returns Date objects or null if moon doesn't rise/set that day
    return {
        rise: moonTimes.rise || null,
        set: moonTimes.set || null,
        alwaysUp: moonTimes.alwaysUp || false,
        alwaysDown: moonTimes.alwaysDown || false
    };
}

function getNextFullMoon(date) {
    const currentPhase = calculateMoonPhase(date);
    let daysToFull = 0;

    if (currentPhase < 0.5) {
        // Before full moon
        daysToFull = (0.5 - currentPhase) * 29.53058867;
    } else {
        // After full moon, next one is in next cycle
        daysToFull = (1.5 - currentPhase) * 29.53058867;
    }

    const nextFullMoon = new Date(date);
    nextFullMoon.setDate(nextFullMoon.getDate() + Math.round(daysToFull));
    return { date: nextFullMoon, days: Math.round(daysToFull) };
}

function getNextNewMoon(date) {
    const currentPhase = calculateMoonPhase(date);
    let daysToNew = 0;

    if (currentPhase < 0.97) {
        // Before new moon
        daysToNew = (1 - currentPhase) * 29.53058867;
    } else {
        // Very close to new moon, next one is in next cycle
        daysToNew = (1 - currentPhase + 1) * 29.53058867;
    }

    const nextNewMoon = new Date(date);
    nextNewMoon.setDate(nextNewMoon.getDate() + Math.round(daysToNew));
    return { date: nextNewMoon, days: Math.round(daysToNew) };
}

function openMoonDetailsModal(date) {
    const modal = document.getElementById('moonDetailsModal');
    modal.classList.add('active');

    // Use current location or default to a location if not available
    const lat = currentLat || 40.7128; // Default to NYC if location not available
    const lon = currentLon || -74.0060;

    const moonPhaseValue = calculateMoonPhase(date);
    const moonPhase = getMoonPhase(moonPhaseValue);
    const illumination = getMoonIllumination(date);
    const distance = calculateMoonDistance(date, lat, lon);

    // Get moonrise/moonset using SunCalc
    const riseSet = calculateMoonRiseSet(date, lat, lon);

    // Get next full/new moon
    const nextFull = getNextFullMoon(date);
    const nextNew = getNextNewMoon(date);

    // Populate modal
    document.getElementById('moonDetailsEmoji').textContent = moonPhase.emoji;
    document.getElementById('moonDetailsName').textContent = moonPhase.name;
    document.getElementById('moonDetailsDate').textContent = date.toLocaleDateString('en-US', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric'
    });
    document.getElementById('moonIllumination').textContent = `${illumination}%`;

    // Handle moonrise/moonset display (may be null if moon doesn't rise/set that day)
    if (riseSet.alwaysUp) {
        document.getElementById('moonRise').textContent = 'Always up';
    } else if (riseSet.alwaysDown) {
        document.getElementById('moonRise').textContent = 'Always down';
    } else if (riseSet.rise) {
        document.getElementById('moonRise').textContent = formatTime12Hour(riseSet.rise);
    } else {
        document.getElementById('moonRise').textContent = 'N/A';
    }

    if (riseSet.alwaysUp) {
        document.getElementById('moonSet').textContent = 'Always up';
    } else if (riseSet.alwaysDown) {
        document.getElementById('moonSet').textContent = 'Always down';
    } else if (riseSet.set) {
        document.getElementById('moonSet').textContent = formatTime12Hour(riseSet.set);
    } else {
        document.getElementById('moonSet').textContent = 'N/A';
    }

    document.getElementById('moonDistance').textContent = `${distance.toLocaleString()} mi`;
    document.getElementById('nextFullMoon').textContent = `${nextFull.days} days (${nextFull.date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })})`;
    document.getElementById('nextNewMoon').textContent = `${nextNew.days} days (${nextNew.date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })})`;
}

function formatTime12Hour(date) {
    let hours = date.getHours();
    const minutes = date.getMinutes();
    const ampm = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12;
    hours = hours ? hours : 12; // the hour '0' should be '12'
    const minutesStr = minutes < 10 ? '0' + minutes : minutes;
    return `${hours}:${minutesStr} ${ampm}`;
}

function parseDateString(dateString) {
    // Parse date string (format: "YYYY-MM-DD") as local date, not UTC
    // This prevents timezone issues where UTC dates shift to previous day
    const parts = dateString.split('-');
    if (parts.length === 3) {
        const year = parseInt(parts[0], 10);
        const month = parseInt(parts[1], 10) - 1; // Month is 0-indexed
        const day = parseInt(parts[2], 10);
        return new Date(year, month, day);
    }
    // Fallback to regular Date parsing if format is different
    return new Date(dateString);
}

function formatLastUpdated(date) {
    const now = new Date();
    const diffMs = now - date;
    const diffMins = Math.floor(diffMs / 60000);

    if (diffMins < 1) {
        return 'just now';
    } else if (diffMins === 1) {
        return '1 minute ago';
    } else if (diffMins < 60) {
        return `${diffMins} minutes ago`;
    } else {
        const diffHours = Math.floor(diffMins / 60);
        if (diffHours === 1) {
            return '1 hour ago';
        } else {
            return `${diffHours} hours ago`;
        }
    }
}

function displayPressure(data) {
    const pressureElement = document.getElementById('pressure');
    const trendElement = document.getElementById('pressureTrend');
    const statusElement = document.getElementById('pressureStatus');

    if (!data.current.surface_pressure) {
        return;
    }

    // Convert hPa to inHg (1 hPa = 0.02953 inHg)
    const pressureInHg = (data.current.surface_pressure * 0.02953).toFixed(2);
    pressureElement.textContent = `${pressureInHg}"`;

    // Calculate pressure trend by comparing to 3 hours ago
    let trend = '';
    let trendText = 'Steady';

    if (data.hourly && data.hourly.surface_pressure) {
        const now = new Date();
        const currentHour = now.getHours();

        // Find current hour index
        let currentIdx = -1;
        for (let i = 0; i < data.hourly.time.length; i++) {
            const hourTime = new Date(data.hourly.time[i]);
            if (hourTime.getHours() === currentHour && hourTime.getDate() === now.getDate()) {
                currentIdx = i;
                break;
            }
        }

        // Compare to 3 hours ago
        if (currentIdx >= 3) {
            const currentPressure = data.hourly.surface_pressure[currentIdx];
            const pastPressure = data.hourly.surface_pressure[currentIdx - 3];
            const diff = currentPressure - pastPressure;

            if (diff > 1) {
                trend = '↑';
                trendText = 'Rising';
                trendElement.className = 'text-lg text-green-400';
            } else if (diff < -1) {
                trend = '↓';
                trendText = 'Falling';
                trendElement.className = 'text-lg text-red-400';
            } else {
                trend = '→';
                trendText = 'Steady';
                trendElement.className = 'text-lg text-gray-400';
            }
        }
    }

    trendElement.textContent = trend;
    statusElement.textContent = trendText;
}

function displayPrecipitationTiming(data) {
    const section = document.getElementById('precipTimingSection');
    const timingText = document.getElementById('precipTiming');
    const icon = document.getElementById('precipIcon');

    if (!data.hourly || !data.hourly.precipitation) {
        section.classList.add('hidden');
        return;
    }

    const now = new Date();
    const currentHour = now.getHours();

    // Find current hour index
    let startIndex = 0;
    for (let i = 0; i < data.hourly.time.length; i++) {
        const hourTime = new Date(data.hourly.time[i]);
        if (hourTime.getHours() >= currentHour && hourTime.getDate() === now.getDate()) {
            startIndex = i;
            break;
        }
    }

    // Look ahead 48 hours for precipitation
    let precipStartTime = null;
    let precipEndTime = null;
    let isSnow = false;
    let precipAmount = 0;

    for (let i = startIndex; i < Math.min(startIndex + HOURLY_FORECAST_HOURS, data.hourly.time.length); i++) {
        const precip = data.hourly.precipitation[i] || 0;
        const snow = data.hourly.snowfall ? (data.hourly.snowfall[i] || 0) : 0;

        if (precip > 0 || snow > 0) {
            if (!precipStartTime) {
                precipStartTime = new Date(data.hourly.time[i]);
                isSnow = snow > 0;
            }
            precipAmount += precip + snow;
            precipEndTime = new Date(data.hourly.time[i]);
        } else if (precipStartTime && !precipEndTime) {
            // Gap in precipitation - could end the period here
            break;
        }
    }

    if (!precipStartTime) {
        // No precipitation expected
        icon.textContent = '☀️';
        timingText.textContent = `No precipitation expected in the next ${HOURLY_FORECAST_HOURS} hours`;
        section.classList.remove('hidden');
    } else {
        const startHour = precipStartTime.getHours();
        const nowHour = now.getHours();
        const startDate = precipStartTime.getDate();
        const nowDate = now.getDate();

        icon.textContent = isSnow ? '❄️' : '🌧️';

        // Check if precipitation is happening now (within the current hour)
        if (startHour === nowHour && startDate === nowDate) {
            const precipType = isSnow ? 'Snow' : 'Rain';
            timingText.textContent = `${precipType} is currently falling`;
        } else {
            const precipType = isSnow ? 'Snow' : 'Rain';
            const timeStr = formatTime12Hour(precipStartTime);

            // Check if it's today or tomorrow
            if (startDate === nowDate) {
                timingText.textContent = `${precipType} expected around ${timeStr}`;
            } else if (startDate === nowDate + 1) {
                timingText.textContent = `${precipType} expected tomorrow around ${timeStr}`;
            } else {
                const dayName = precipStartTime.toLocaleDateString('en-US', { weekday: 'long' });
                timingText.textContent = `${precipType} expected ${dayName} around ${timeStr}`;
            }
        }
        section.classList.remove('hidden');
    }
}

async function fetchNwsSnowForecast(lat, lon) {
    if (!isLikelyUsLocation(lat, lon)) {
        return {
            unavailable: true,
            message: 'NWS data not available for this location'
        };
    }

    const pointsResponse = await fetchWith503Retry(
        `https://api.weather.gov/points/${lat.toFixed(4)},${lon.toFixed(4)}`
    );

    if (!pointsResponse.ok) {
        if (pointsResponse.status === 404) {
            return {
                unavailable: true,
                message: 'NWS data not available for this location'
            };
        }
        throw new Error(`NWS points request failed (${pointsResponse.status})`);
    }

    const pointsData = await pointsResponse.json();
    const gridUrl = pointsData?.properties?.forecastGridData;
    if (!gridUrl) {
        return {
            unavailable: true,
            message: 'NWS data not available for this location'
        };
    }

    const gridResponse = await fetchWith503Retry(gridUrl);
    if (!gridResponse.ok) {
        throw new Error(`NWS grid request failed (${gridResponse.status})`);
    }

    const gridData = await gridResponse.json();
    const snowfallValues = gridData?.properties?.snowfallAmount?.values || [];
    if (!snowfallValues.length) {
        return { totalInches: 0 };
    }

    const now = new Date();
    const end48h = new Date(now.getTime() + 48 * 60 * 60 * 1000);
    let totalMm = 0;

    snowfallValues.forEach(entry => {
        const validTime = entry.validTime || '';
        const [startIso, durationIso = 'PT0H'] = validTime.split('/');
        const rangeStart = startIso ? new Date(startIso) : null;
        if (!rangeStart || Number.isNaN(rangeStart.getTime())) return;

        const durationHours = extractDurationHours(durationIso || entry.period);
        const safeDuration = durationHours > 0 ? durationHours : 1;
        const rangeEnd = new Date(rangeStart.getTime() + safeDuration * 60 * 60 * 1000);
        const overlap = overlapHours(rangeStart, rangeEnd, now, end48h);
        if (overlap <= 0) return;

        const mmValue = Number(entry.value) || 0; // NWS snowfallAmount UOM is wmoUnit:mm
        totalMm += mmValue * (overlap / safeDuration);
    });

    return { totalInches: totalMm / 25.4 };
}

function showLoading() {
    document.getElementById('loading').classList.remove('hidden');
}

function hideLoading() {
    document.getElementById('loading').classList.add('hidden');
}

function showContent() {
    document.getElementById('weatherContent').classList.remove('hidden');
}

function hideContent() {
    document.getElementById('weatherContent').classList.add('hidden');
}

function showError(message) {
    document.getElementById('errorMessage').classList.remove('hidden');
    document.getElementById('errorText').textContent = message;
}

function hideError() {
    document.getElementById('errorMessage').classList.add('hidden');
}

// Weather alerts functionality
async function fetchWeatherAlerts(lat, lon) {
    // Only fetch alerts for US locations (rough check: lat 24-50, lon -125 to -66)
    if (lat < 24 || lat > 50 || lon < -125 || lon > -66) {
        return; // Not in US, skip alerts
    }

    try {
        // First, get the forecast zone for this point
        const pointResponse = await fetch(`/api/nws-points/${lat.toFixed(4)},${lon.toFixed(4)}`);

        if (!pointResponse.ok) {
            console.log('NWS points API not available:', pointResponse.status);
            return; // Silently fail if not available
        }

        const pointData = await pointResponse.json();

        // Check if the response has an error
        if (pointData.error) {
            console.log('NWS points API error:', pointData.reason);
            return;
        }

        const forecastZoneUrl = pointData.properties?.forecastZone;

        if (!forecastZoneUrl) {
            console.log('No forecast zone URL found in NWS response');
            return;
        }

        // Extract zone ID from URL (e.g., "https://api.weather.gov/zones/forecast/AZZ001" -> "AZZ001")
        const zoneId = forecastZoneUrl.split('/').pop();

        if (!zoneId) {
            console.log('Could not extract zone ID from URL:', forecastZoneUrl);
            return;
        }

        // Fetch alerts for this zone
        const alertsResponse = await fetch(`/api/alerts/active/zone/${zoneId}`);

        if (!alertsResponse.ok) {
            console.log('NWS alerts API not available:', alertsResponse.status);
            return;
        }

        const alertsData = await alertsResponse.json();

        // Check if the response has an error
        if (alertsData.error) {
            console.log('NWS alerts API error:', alertsData.reason);
            return;
        }

        if (alertsData.features && alertsData.features.length > 0) {
            // Filter to only show actual (active) alerts
            const activeAlerts = alertsData.features.filter(alert =>
                alert.properties.status === 'Actual'
            );

            if (activeAlerts.length > 0) {
                displayAlerts(activeAlerts);
            }
        }
    } catch (error) {
        // Log error for debugging but don't break the app
        console.error('Weather alerts error:', error.message);
    }
}

function displayAlerts(alerts) {
    const alertsContainer = document.getElementById('weatherAlerts');
    alertsContainer.innerHTML = '';
    alertsContainer.classList.remove('hidden');

    alerts.forEach((alert, index) => {
        const props = alert.properties;
        const severity = props.severity?.toLowerCase() || 'unknown';
        const urgency = props.urgency?.toLowerCase() || 'unknown';

        // Determine alert color based on severity
        let alertColor = 'bg-yellow-500/20 border-yellow-300/30';
        if (severity === 'extreme' || severity === 'severe') {
            alertColor = 'bg-red-500/20 border-red-300/30';
        } else if (severity === 'moderate') {
            alertColor = 'bg-orange-500/20 border-orange-300/30';
        }

        const alertItem = document.createElement('div');
        alertItem.className = `${alertColor} backdrop-blur-sm rounded-lg border shadow-lg mb-3`;

        const eventType = props.event || 'Weather Alert';
        const headline = props.headline || '';
        const description = props.description || '';
        const effective = props.effective ? new Date(props.effective).toLocaleString('en-US') : '';
        const expires = props.expires ? new Date(props.expires).toLocaleString('en-US') : '';

        // Create unique IDs for this alert
        const alertId = `alert-${index}`;
        const headerId = `alert-header-${index}`;
        const contentId = `alert-content-${index}`;
        const expandIconId = `alert-icon-${index}`;

        alertItem.innerHTML = `
            <div class="cursor-pointer" id="${headerId}">
                <div class="flex items-center justify-between p-4">
                    <div class="flex items-center gap-3 flex-1 min-w-0">
                        <i class="fas fa-exclamation-triangle text-2xl text-white flex-shrink-0"></i>
                        <div class="flex-1 min-w-0">
                            <div class="flex items-center gap-2 mb-1 flex-wrap">
                                <h3 class="text-xl font-bold text-white">${eventType}</h3>
                                ${props.severity ? `<span class="px-2 py-1 bg-white/20 rounded text-xs text-white font-semibold uppercase whitespace-nowrap">${props.severity}</span>` : ''}
                            </div>
                            ${headline ? `<p class="text-white font-semibold text-sm">${headline}</p>` : ''}
                        </div>
                    </div>
                    <i id="${expandIconId}" class="fas fa-chevron-down text-white transition-transform duration-200 flex-shrink-0 ml-2"></i>
                </div>
            </div>
            <div id="${contentId}" class="hidden px-4 pb-4">
                <div class="border-t border-white/20 pt-4">
                    ${description ? `<p class="text-white/90 text-sm mb-3 whitespace-pre-line">${description}</p>` : ''}
                    ${(effective || expires) ? `
                    <div class="flex flex-col gap-2 text-white/70 text-xs mt-4 pt-4 border-t border-white/10">
                        ${effective ? `<div><i class="fas fa-clock mr-1"></i>Effective: ${effective}</div>` : ''}
                        ${expires ? `<div><i class="fas fa-calendar-times mr-1"></i>Expires: ${expires}</div>` : ''}
                    </div>
                    ` : ''}
                </div>
            </div>
        `;

        // Add click handler for expand/collapse
        const header = alertItem.querySelector(`#${headerId}`);
        const content = alertItem.querySelector(`#${contentId}`);
        const expandIcon = alertItem.querySelector(`#${expandIconId}`);

        header.addEventListener('click', () => {
            const isExpanded = !content.classList.contains('hidden');
            if (isExpanded) {
                content.classList.add('hidden');
                expandIcon.classList.remove('fa-chevron-up');
                expandIcon.classList.add('fa-chevron-down');
                expandIcon.style.transform = 'rotate(0deg)';
            } else {
                content.classList.remove('hidden');
                expandIcon.classList.remove('fa-chevron-down');
                expandIcon.classList.add('fa-chevron-up');
                expandIcon.style.transform = 'rotate(180deg)';
            }
        });

        alertsContainer.appendChild(alertItem);
    });
}

// Air Quality functionality
// Store pollen data globally for use in allergy risk calculation
let currentPollenData = null;

const POLLEN_FIELDS = [
    'tree_pollen',
    'alder_pollen',
    'birch_pollen',
    'olive_pollen',
    'grass_pollen',
    'weed_pollen',
    'mugwort_pollen',
    'ragweed_pollen'
];

function hasPollenValue(value) {
    return value !== null && value !== undefined && Number.isFinite(Number(value));
}

function maxAvailablePollen(values) {
    const availableValues = values.filter(hasPollenValue).map(Number);
    if (availableValues.length === 0) return null;
    return Math.max(...availableValues);
}

function hasAnyPollenData(current) {
    return !!current && POLLEN_FIELDS.some(field => hasPollenValue(current[field]));
}

function formatPollenValue(value) {
    return hasPollenValue(value) ? Math.round(Number(value)) : '0';
}

function updateAllergyRiskDisplay(risk) {
    const valueEl = document.getElementById('allergyRiskValue');
    const labelEl = document.getElementById('allergyRiskLabel');

    if (risk === null || risk === undefined) {
        valueEl.textContent = '0/10';
        labelEl.textContent = 'None';
        labelEl.className = 'text-xs font-semibold text-gray-400';
        return;
    }

    const allergyLabel = getRiskLabel(risk);
    valueEl.textContent = `${risk}/10`;
    labelEl.textContent = allergyLabel.label;
    labelEl.className = `text-xs font-semibold ${allergyLabel.colorClass}`;
}

function updateNiceWeatherDisplay(index) {
    const valueEl = document.getElementById('niceWeatherValue');
    const labelEl = document.getElementById('niceWeatherLabel');

    if (!valueEl || !labelEl) return;

    if (index === null || index === undefined) {
        valueEl.textContent = '--';
        labelEl.textContent = 'Unavailable';
        labelEl.className = 'text-xs font-semibold text-gray-400';
        return;
    }

    const niceLabel = getNiceWeatherLabel(index);
    valueEl.textContent = `${index}/10`;
    labelEl.textContent = niceLabel.label;
    labelEl.className = `text-xs font-semibold ${niceLabel.colorClass}`;
}

async function fetchAirQuality(lat, lon) {
    try {
        // Fetch pollen/air-quality data through the Worker. The Worker optionally
        // uses Google Pollen API when GOOGLE_POLLEN_API_KEY is configured, then
        // falls back to Open-Meteo while preserving null unavailable semantics.
        const aqiResponse = await fetch(`/api/pollen?lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lon)}`);

        if (!aqiResponse.ok) {
            // Hide air quality and pollen sections if API is unavailable
            document.getElementById('airQualitySection').classList.add('hidden');
            document.getElementById('pollenSection').classList.add('hidden');
            currentPollenData = null;
            updateAllergyRiskWithPollenData();
            return;
        }

        const aqiData = await aqiResponse.json();

        if (aqiData.error || !aqiData.current) {
            document.getElementById('airQualitySection').classList.add('hidden');
            document.getElementById('pollenSection').classList.add('hidden');
            currentPollenData = null;
            updateAllergyRiskWithPollenData();
            return;
        }

        // Store pollen data for allergy risk calculation
        currentPollenData = aqiData;

        if (hasPollenValue(aqiData.current.us_aqi)) {
            displayAirQuality(aqiData.current);
        } else {
            document.getElementById('airQualitySection').classList.add('hidden');
        }
        displayPollenData(aqiData);

        // Recalculate allergy risk with real pollen data
        updateAllergyRiskWithPollenData();
    } catch (error) {
        console.error('Error fetching air quality:', error);
        document.getElementById('airQualitySection').classList.add('hidden');
        document.getElementById('pollenSection').classList.add('hidden');
        currentPollenData = null;
        updateAllergyRiskWithPollenData();
    }
}

function displayAirQuality(data) {
    const aqiSection = document.getElementById('airQualitySection');
    const aqiValue = document.getElementById('aqiValue');
    const aqiStatus = document.getElementById('aqiStatus');

    // Show the section
    aqiSection.classList.remove('hidden');

    // Get US AQI (0-500 scale)
    const usAqi = data.us_aqi || 0;

    // Determine AQI category and color
    let category, color;
    if (usAqi <= 50) {
        category = 'Good';
        color = 'text-green-400';
    } else if (usAqi <= 100) {
        category = 'Moderate';
        color = 'text-yellow-400';
    } else if (usAqi <= 150) {
        category = 'Unhealthy for Sensitive Groups';
        color = 'text-orange-400';
    } else if (usAqi <= 200) {
        category = 'Unhealthy';
        color = 'text-red-400';
    } else if (usAqi <= 300) {
        category = 'Very Unhealthy';
        color = 'text-purple-400';
    } else {
        category = 'Hazardous';
        color = 'text-red-600';
    }

    // Update display
    aqiValue.textContent = usAqi;
    aqiValue.className = `text-2xl font-bold ${color}`;
    aqiStatus.textContent = category;
    aqiStatus.className = `text-white/90 text-xs mt-1 ${color}`;
}

// ============================================
// Symptom Risk Calculation Functions
// ============================================

// Store symptom data globally for modal display
let currentSymptomData = null;
let currentNiceWeatherData = null;

// Convert hPa to inHg (inches of mercury)
function hpaToInhg(hpa) {
    return hpa * 0.02953;
}

// Calculate daily averages from hourly data for a specific date
function calculateDailyAverages(hourlyData, targetDate) {
    const targetDateStr = targetDate.toISOString().split('T')[0];
    return calculateDailyAveragesForDateString(hourlyData, targetDateStr);
}

function calculateDailyAveragesForDateString(hourlyData, targetDateStr) {
    if (!hourlyData || !hourlyData.time || !targetDateStr) return null;

    let tempSum = 0, humiditySum = 0, pressureSum = 0, precipSum = 0;
    let windMax = 0, count = 0;

    for (let i = 0; i < hourlyData.time.length; i++) {
        const hourDate = hourlyData.time[i].split('T')[0];
        if (hourDate === targetDateStr) {
            tempSum += hourlyData.temperature_2m[i] || 0;
            humiditySum += hourlyData.relative_humidity_2m[i] || 0;
            pressureSum += hourlyData.surface_pressure ? (hourlyData.surface_pressure[i] || 0) : 0;
            precipSum += hourlyData.precipitation ? (hourlyData.precipitation[i] || 0) : 0;
            windMax = Math.max(windMax, hourlyData.wind_speed_10m[i] || 0);
            count++;
        }
    }

    if (count === 0) return null;

    return {
        avgTemp: tempSum / count,
        avgHumidity: humiditySum / count,
        avgPressureInhg: hpaToInhg(pressureSum / count),
        precipSum: precipSum,
        windMax: windMax
    };
}

// Calculate sinus risk score (0-10)
function calculateSinusRisk(pressureChange, humidity, precipitation, tempSwing) {
    let risk = 0;

    // Pressure drop scoring
    if (pressureChange < -0.30) {
        risk += 5;
    } else if (pressureChange >= -0.30 && pressureChange < -0.18) {
        risk += 3;
    } else if (pressureChange >= -0.18 && pressureChange < -0.10) {
        risk += 2;
    }

    // High humidity
    if (humidity > 70) {
        risk += 1;
    }

    // Precipitation
    if (precipitation > 0.1) {
        risk += 1;
    }

    // Temperature swing
    if (tempSwing > 20) {
        risk += 1;
    }

    // Clip to 0-10
    return Math.max(0, Math.min(10, risk));
}

// Calculate allergy risk score (0-10) - requires pollen data
function calculateAllergyRisk(windMax, precipitation, pollenData = null) {
    // Requires actual pollen values. Null/undefined means unavailable, not zero.
    if (!pollenData || !hasAnyPollenData(pollenData.current)) {
        return null;
    }

    let risk = 0;
    const current = pollenData.current;

    // Get max pollen levels
    const treePollen = maxAvailablePollen([
        current.tree_pollen,
        current.alder_pollen,
        current.birch_pollen,
        current.olive_pollen
    ]);
    const grassPollen = maxAvailablePollen([current.grass_pollen]);
    const weedPollen = maxAvailablePollen([
        current.weed_pollen,
        current.mugwort_pollen,
        current.ragweed_pollen
    ]);
    const maxPollen = maxAvailablePollen([treePollen, grassPollen, weedPollen]);

    // Score based on actual pollen levels (grains/m³)
    if (maxPollen > 200) {
        risk += 5;  // Very High pollen
    } else if (maxPollen > 80) {
        risk += 4;  // High pollen
    } else if (maxPollen > 20) {
        risk += 2;  // Moderate pollen
    } else if (maxPollen > 0) {
        risk += 1;  // Low pollen
    }

    // Wind disperses pollen
    if (windMax > 10) {
        risk += 2;
    }

    // Wet day reduces risk (rain washes pollen away)
    if (precipitation > 0.1) {
        risk -= 2;
    }

    // Clip to 0-10
    return Math.max(0, Math.min(10, risk));
}

function calculateNiceWeatherIndex(data, todayAvg, todayIndex) {
    const breakdown = getNiceWeatherBreakdown(data, todayAvg, todayIndex);
    return breakdown ? breakdown.score : null;
}

function getNiceWeatherBreakdown(data, todayAvg, todayIndex) {
    if (!data || !todayAvg) return null;

    const avgTemp = todayAvg.avgTemp;
    const avgHumidity = todayAvg.avgHumidity;
    const precipSum = todayAvg.precipSum;
    const windMax = todayAvg.windMax;
    const uvIndex = data.current?.uv_index ?? 0;
    const precipProbability = data.daily?.precipitation_probability_max?.[todayIndex] ?? 0;
    const cloudCover = getAverageHourlyValueForDate(data.hourly, 'cloud_cover', data.daily?.time?.[todayIndex]);
    const weatherCode = data.daily?.weather_code?.[todayIndex];
    const weatherDescription = getWeatherDescription(weatherCode);

    if ([avgTemp, avgHumidity, precipSum, windMax].some(value => value === null || value === undefined || Number.isNaN(value))) {
        return null;
    }

    let score = 10;
    const factors = [];

    function addFactor(name, value, points, note, iconClass) {
        factors.push({ name, value, points, note, iconClass });
        score -= points;
    }

    // Temperature comfort sweet spot is roughly 65-78°F.
    if (avgTemp < 50) addFactor('Temperature', `${avgTemp.toFixed(0)}°F avg`, 4, 'Too cold for most outdoor comfort', 'fas fa-thermometer-half text-blue-300');
    else if (avgTemp < 60) addFactor('Temperature', `${avgTemp.toFixed(0)}°F avg`, 2, 'Cooler than the 65–78°F sweet spot', 'fas fa-thermometer-half text-blue-300');
    else if (avgTemp > 92) addFactor('Temperature', `${avgTemp.toFixed(0)}°F avg`, 4, 'Very hot for outdoor comfort', 'fas fa-thermometer-half text-red-300');
    else if (avgTemp > 85) addFactor('Temperature', `${avgTemp.toFixed(0)}°F avg`, 2, 'Hotter than ideal', 'fas fa-thermometer-half text-orange-300');
    else if (avgTemp > 78) addFactor('Temperature', `${avgTemp.toFixed(0)}°F avg`, 1, 'A little warm versus the comfort sweet spot', 'fas fa-thermometer-half text-yellow-300');
    else factors.push({ name: 'Temperature', value: `${avgTemp.toFixed(0)}°F avg`, points: 0, note: 'Comfortable 65–78°F range', iconClass: 'fas fa-thermometer-half text-green-300' });

    // Rain and high rain odds make otherwise pleasant weather less nice.
    if (precipSum > 0.5) addFactor('Precipitation', `${precipSum.toFixed(2)} in`, 3, 'Wet day expected', 'fas fa-cloud-rain text-blue-300');
    else if (precipSum > 0.1) addFactor('Precipitation', `${precipSum.toFixed(2)} in`, 2, 'Some rain expected', 'fas fa-cloud-rain text-blue-300');
    else if (precipSum > 0) addFactor('Precipitation', `${precipSum.toFixed(2)} in`, 1, 'Light precipitation possible', 'fas fa-cloud-rain text-blue-300');
    else factors.push({ name: 'Precipitation', value: `${precipSum.toFixed(2)} in`, points: 0, note: 'Dry conditions', iconClass: 'fas fa-cloud-rain text-green-300' });

    if (precipProbability >= 70) addFactor('Rain odds', `${precipProbability}%`, 2, 'High chance of precipitation', 'fas fa-umbrella text-blue-300');
    else if (precipProbability >= 40) addFactor('Rain odds', `${precipProbability}%`, 1, 'Moderate chance of precipitation', 'fas fa-umbrella text-yellow-300');

    // Calm-to-light breezes score best.
    if (windMax > 25) addFactor('Wind', `${windMax.toFixed(1)} mph max`, 3, 'Very windy', 'fas fa-wind text-orange-300');
    else if (windMax > 18) addFactor('Wind', `${windMax.toFixed(1)} mph max`, 2, 'Windy', 'fas fa-wind text-yellow-300');
    else if (windMax > 12) addFactor('Wind', `${windMax.toFixed(1)} mph max`, 1, 'Breezy', 'fas fa-wind text-yellow-300');
    else factors.push({ name: 'Wind', value: `${windMax.toFixed(1)} mph max`, points: 0, note: 'Calm to light breeze', iconClass: 'fas fa-wind text-green-300' });

    // Muggy or very dry conditions reduce comfort.
    if (avgHumidity > 80) addFactor('Humidity', `${avgHumidity.toFixed(0)}% avg`, 2, 'Muggy', 'fas fa-tint text-blue-300');
    else if (avgHumidity > 65) addFactor('Humidity', `${avgHumidity.toFixed(0)}% avg`, 1, 'Humid', 'fas fa-tint text-blue-300');
    else if (avgHumidity < 25) addFactor('Humidity', `${avgHumidity.toFixed(0)}% avg`, 1, 'Very dry', 'fas fa-tint text-yellow-300');
    else factors.push({ name: 'Humidity', value: `${avgHumidity.toFixed(0)}% avg`, points: 0, note: 'Comfortable humidity', iconClass: 'fas fa-tint text-green-300' });

    // Too much cloud cover and very high UV both detract from "nice" outdoor weather.
    if (cloudCover !== null && cloudCover !== undefined) {
        if (cloudCover > 85) addFactor('Cloud/weather', `${cloudCover.toFixed(0)}% clouds, ${weatherDescription}`, 2, 'Very cloudy or overcast', 'fas fa-cloud text-gray-300');
        else if (cloudCover > 65) addFactor('Cloud/weather', `${cloudCover.toFixed(0)}% clouds, ${weatherDescription}`, 1, 'Mostly cloudy', 'fas fa-cloud text-gray-300');
        else factors.push({ name: 'Cloud/weather', value: `${cloudCover.toFixed(0)}% clouds, ${weatherDescription}`, points: 0, note: 'Good sky conditions', iconClass: 'fas fa-cloud-sun text-green-300' });
    } else {
        factors.push({ name: 'Cloud/weather', value: weatherDescription, points: 0, note: 'Cloud cover unavailable', iconClass: 'fas fa-cloud-sun text-gray-300' });
    }

    if (uvIndex >= 9) addFactor('UV', `${uvIndex}`, 1, 'Very high UV', 'fas fa-sun text-orange-300');
    else factors.push({ name: 'UV', value: `${uvIndex}`, points: 0, note: 'UV not extreme', iconClass: 'fas fa-sun text-yellow-300' });

    const finalScore = Math.max(0, Math.min(10, Math.round(score)));
    return { score: finalScore, factors };
}

function getAverageHourlyValueForDate(hourlyData, field, targetDateStr) {
    if (!hourlyData || !hourlyData.time || !hourlyData[field] || !targetDateStr) return null;
    let sum = 0;
    let count = 0;

    for (let i = 0; i < hourlyData.time.length; i++) {
        if (hourlyData.time[i].split('T')[0] === targetDateStr && hourlyData[field][i] !== null && hourlyData[field][i] !== undefined) {
            sum += hourlyData[field][i];
            count++;
        }
    }

    return count > 0 ? sum / count : null;
}

function getNiceWeatherLabel(index) {
    if (index >= 8) {
        return { label: 'Excellent', colorClass: 'text-green-400' };
    } else if (index >= 6) {
        return { label: 'Nice', colorClass: 'text-lime-400' };
    } else if (index >= 4) {
        return { label: 'Fair', colorClass: 'text-yellow-400' };
    }
    return { label: 'Poor', colorClass: 'text-orange-400' };
}

// Get risk level label and color class
function getRiskLabel(risk) {
    if (risk <= 2) {
        return { label: 'Low', colorClass: 'text-green-400' };
    } else if (risk <= 4) {
        return { label: 'Moderate', colorClass: 'text-yellow-400' };
    } else if (risk <= 7) {
        return { label: 'High', colorClass: 'text-orange-400' };
    } else {
        return { label: 'Very High', colorClass: 'text-red-400' };
    }
}

// Update allergy risk calculation when pollen data becomes available
function updateAllergyRiskWithPollenData() {
    if (!currentSymptomData || !currentPollenData) return;

    // Recalculate allergy risk with real pollen data
    const allergyRisk = calculateAllergyRisk(
        currentSymptomData.windMax,
        currentSymptomData.precipitation,
        currentPollenData
    );

    // Update display
    updateAllergyRiskDisplay(allergyRisk);
}

// ============================================
// Pollen Display Functions
// ============================================

// Get pollen level category based on grains/m³
function getPollenLevel(value, options = {}) {
    if (value === null || value === undefined) {
        return { label: 'None', colorClass: 'text-gray-400', level: 0 };
    } else if (value === 0) {
        return { label: 'None', colorClass: 'text-gray-400', level: 0 };
    } else if (value <= 20) {
        return { label: 'Low', colorClass: 'text-green-400', level: 1 };
    } else if (value <= 80) {
        return { label: 'Moderate', colorClass: 'text-yellow-400', level: 2 };
    } else if (value <= 200) {
        return { label: 'High', colorClass: 'text-orange-400', level: 3 };
    } else {
        return { label: 'Very High', colorClass: 'text-red-400', level: 4 };
    }
}

function shouldDisplayNullPollenAsNone(aqiData, fields, dayIndex = null) {
    const metadata = aqiData?.pollen_null_display_as_none;
    const flags = dayIndex === null ? metadata?.current : metadata?.hourly?.[dayIndex];
    if (!flags) return false;
    return fields.some(field => flags[field]);
}

// Display pollen data
function displayPollenData(aqiData) {
    const pollenSection = document.getElementById('pollenSection');

    if (!aqiData.current) {
        pollenSection.classList.add('hidden');
        return;
    }

    const current = aqiData.current;

    // Calculate combined values for each category, preserving unavailable values as null.
    const treePollen = maxAvailablePollen([
        current.tree_pollen,
        current.alder_pollen,
        current.birch_pollen,
        current.olive_pollen
    ]);
    const grassPollen = maxAvailablePollen([current.grass_pollen]);
    const weedPollen = maxAvailablePollen([
        current.weed_pollen,
        current.mugwort_pollen,
        current.ragweed_pollen
    ]);
    const weedNullDisplayAsNone = shouldDisplayNullPollenAsNone(aqiData, ['weed_pollen', 'mugwort_pollen', 'ragweed_pollen']);

    pollenSection.classList.remove('hidden');

    // Display current tree pollen
    const treeLevel = getPollenLevel(treePollen);
    document.getElementById('pollenTreeValue').textContent = formatPollenValue(treePollen);
    document.getElementById('pollenTreeLabel').textContent = treeLevel.label;
    document.getElementById('pollenTreeLabel').className = `text-xs mt-1 font-semibold ${treeLevel.colorClass}`;

    // Display current grass pollen
    const grassLevel = getPollenLevel(grassPollen);
    document.getElementById('pollenGrassValue').textContent = formatPollenValue(grassPollen);
    document.getElementById('pollenGrassLabel').textContent = grassLevel.label;
    document.getElementById('pollenGrassLabel').className = `text-xs mt-1 font-semibold ${grassLevel.colorClass}`;

    // Display current weed pollen
    const weedLevel = getPollenLevel(weedPollen, { displayNullAsNone: weedNullDisplayAsNone });
    document.getElementById('pollenWeedValue').textContent = formatPollenValue(weedPollen);
    document.getElementById('pollenWeedLabel').textContent = weedLevel.label;
    document.getElementById('pollenWeedLabel').className = `text-xs mt-1 font-semibold ${weedLevel.colorClass}`;

    // Display 5-day forecast
    if (aqiData.hourly && aqiData.hourly.time) {
        displayPollenForecast(aqiData.hourly, aqiData);
    }
}

// Display pollen forecast
function displayPollenForecast(hourlyData, aqiData = null) {
    const forecastContainer = document.getElementById('pollenForecast');
    forecastContainer.innerHTML = '';

    // Group hourly data by day and get daily max
    const dailyData = {};

    for (let i = 0; i < hourlyData.time.length; i++) {
        const date = hourlyData.time[i].split('T')[0];

        if (!dailyData[date]) {
            dailyData[date] = { tree: null, grass: null, weed: null, weedNullDisplayAsNone: false };
        }

        dailyData[date].weedNullDisplayAsNone = dailyData[date].weedNullDisplayAsNone || shouldDisplayNullPollenAsNone(aqiData, ['weed_pollen', 'mugwort_pollen', 'ragweed_pollen'], i);

        dailyData[date].tree = maxAvailablePollen([
            dailyData[date].tree,
            hourlyData.tree_pollen?.[i],
            hourlyData.alder_pollen?.[i],
            hourlyData.birch_pollen?.[i],
            hourlyData.olive_pollen?.[i]
        ]);
        dailyData[date].grass = maxAvailablePollen([
            dailyData[date].grass,
            hourlyData.grass_pollen?.[i]
        ]);
        dailyData[date].weed = maxAvailablePollen([
            dailyData[date].weed,
            hourlyData.weed_pollen?.[i],
            hourlyData.mugwort_pollen?.[i],
            hourlyData.ragweed_pollen?.[i]
        ]);
    }

    const dates = Object.keys(dailyData).slice(0, 5);
    const isMobile = window.innerWidth <= 768;

    dates.forEach((dateStr, index) => {
        const day = parseDateString(dateStr);
        const data = dailyData[dateStr];

        const treeLevel = getPollenLevel(data.tree);
        const grassLevel = getPollenLevel(data.grass);
        const weedLevel = getPollenLevel(data.weed, { displayNullAsNone: data.weedNullDisplayAsNone });

        const overallLevel = Math.max(treeLevel.level || 0, grassLevel.level || 0, weedLevel.level || 0);

        const forecastItem = document.createElement('div');
        forecastItem.className = 'stat-card rounded-xl p-4 flex items-center justify-between';

        const dayName = index === 0 ? 'Today' :
                       index === 1 ? 'Tomorrow' :
                       day.toLocaleDateString('en-US', { weekday: isMobile ? 'short' : 'long' });
        const dateDisplay = day.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });

        forecastItem.innerHTML = `
            <div class="flex items-center gap-3">
                <div class="text-2xl">${getPollenEmoji(overallLevel)}</div>
                <div>
                    <div class="text-white font-semibold">${dayName}</div>
                    <div class="text-gray-400 text-xs">${dateDisplay}</div>
                </div>
            </div>
            <div class="flex items-center gap-4 text-sm">
                <div class="text-center">
                    <div class="text-gray-500 text-xs mb-1">Tree</div>
                    <div class="${treeLevel.colorClass} font-semibold">${treeLevel.label}</div>
                </div>
                <div class="text-center">
                    <div class="text-gray-500 text-xs mb-1">Grass</div>
                    <div class="${grassLevel.colorClass} font-semibold">${grassLevel.label}</div>
                </div>
                <div class="text-center">
                    <div class="text-gray-500 text-xs mb-1">Weed</div>
                    <div class="${weedLevel.colorClass} font-semibold">${weedLevel.label}</div>
                </div>
            </div>
        `;

        forecastContainer.appendChild(forecastItem);
    });
}

// Get emoji based on pollen level
function getPollenEmoji(level) {
    switch(level) {
        case 0: return '😊';
        case 1: return '🙂';
        case 2: return '😐';
        case 3: return '😷';
        case 4: return '🤧';
        default: return '🌿';
    }
}

// ============================================
// Symptom Risk Modal
// ============================================

function openSymptomRiskModal(type) {
    const modal = document.getElementById('symptomRiskModal');
    const titleText = document.getElementById('symptomRiskModalTitleText');
    const titleIcon = document.getElementById('symptomRiskModalIcon');
    const sinusSection = document.getElementById('sinusFormulaSection');
    const allergySection = document.getElementById('allergyFormulaSection');
    const currentValuesContainer = document.getElementById('symptomCurrentValues');

    if (type === 'sinus') {
        titleText.textContent = 'Sinus Risk Methodology';
        titleIcon.innerHTML = '<i class="fas fa-head-side-cough text-blue-300"></i>';
        sinusSection.classList.remove('hidden');
        allergySection.classList.add('hidden');
    } else {
        titleText.textContent = 'Allergy Risk Methodology';
        titleIcon.innerHTML = '<i class="fas fa-seedling text-green-300"></i>';
        sinusSection.classList.add('hidden');
        allergySection.classList.remove('hidden');
    }

    // Populate current values if available
    if (currentSymptomData) {
        const data = currentSymptomData;

        if (type === 'sinus') {
            currentValuesContainer.innerHTML = `
                <div class="stat-card rounded-lg p-3 text-center">
                    <div class="text-gray-400 text-xs mb-1">Pressure Change</div>
                    <div class="text-white font-bold">${data.pressureChange >= 0 ? '+' : ''}${data.pressureChange.toFixed(2)} inHg</div>
                </div>
                <div class="stat-card rounded-lg p-3 text-center">
                    <div class="text-gray-400 text-xs mb-1">Humidity</div>
                    <div class="text-white font-bold">${data.humidity.toFixed(0)}%</div>
                </div>
                <div class="stat-card rounded-lg p-3 text-center">
                    <div class="text-gray-400 text-xs mb-1">Precipitation</div>
                    <div class="text-white font-bold">${data.precipitation.toFixed(2)} in</div>
                </div>
                <div class="stat-card rounded-lg p-3 text-center">
                    <div class="text-gray-400 text-xs mb-1">Temp Swing</div>
                    <div class="text-white font-bold">${data.tempSwing.toFixed(1)}°F</div>
                </div>
            `;
        } else {
            // Check if we have pollen data
            let pollenHtml = '';
            if (currentPollenData && currentPollenData.current) {
                const pollen = currentPollenData.current;
                const treePollen = maxAvailablePollen([pollen.tree_pollen, pollen.alder_pollen, pollen.birch_pollen, pollen.olive_pollen]);
                const grassPollen = maxAvailablePollen([pollen.grass_pollen]);
                const weedPollen = maxAvailablePollen([pollen.weed_pollen, pollen.mugwort_pollen, pollen.ragweed_pollen]);
                const treeLevel = getPollenLevel(treePollen);
                const grassLevel = getPollenLevel(grassPollen);
                const weedLevel = getPollenLevel(weedPollen);

                pollenHtml = `
                    <div class="stat-card rounded-lg p-3 text-center">
                        <div class="text-gray-400 text-xs mb-1"><i class="fas fa-tree text-green-400 mr-1"></i>Tree Pollen</div>
                        <div class="text-white font-bold">${formatPollenValue(treePollen)}</div>
                        <div class="text-xs ${treeLevel.colorClass}">${treeLevel.label}</div>
                    </div>
                    <div class="stat-card rounded-lg p-3 text-center">
                        <div class="text-gray-400 text-xs mb-1"><i class="fas fa-leaf text-lime-400 mr-1"></i>Grass Pollen</div>
                        <div class="text-white font-bold">${formatPollenValue(grassPollen)}</div>
                        <div class="text-xs ${grassLevel.colorClass}">${grassLevel.label}</div>
                    </div>
                    <div class="stat-card rounded-lg p-3 text-center">
                        <div class="text-gray-400 text-xs mb-1"><i class="fas fa-seedling text-amber-400 mr-1"></i>Weed Pollen</div>
                        <div class="text-white font-bold">${formatPollenValue(weedPollen)}</div>
                        <div class="text-xs ${weedLevel.colorClass}">${weedLevel.label}</div>
                    </div>
                `;
            }

            currentValuesContainer.innerHTML = `
                ${pollenHtml}
                <div class="stat-card rounded-lg p-3 text-center">
                    <div class="text-gray-400 text-xs mb-1">Max Wind</div>
                    <div class="text-white font-bold">${data.windMax.toFixed(1)} mph</div>
                </div>
                <div class="stat-card rounded-lg p-3 text-center">
                    <div class="text-gray-400 text-xs mb-1">Precipitation</div>
                    <div class="text-white font-bold">${data.precipitation.toFixed(2)} in</div>
                </div>
            `;
        }
    }

    modal.classList.add('active');

    // Re-render MathJax for the newly visible content
    if (window.MathJax) {
        MathJax.typesetPromise([modal]).catch(function (err) {
            console.log('MathJax typeset error:', err);
        });
    }
}

function openNiceWeatherModal() {
    const modal = document.getElementById('niceWeatherModal');
    const currentValuesContainer = document.getElementById('niceWeatherCurrentValues');
    const reasoningContainer = document.getElementById('niceWeatherReasoning');

    if (!modal || !currentValuesContainer || !reasoningContainer) return;

    if (!currentNiceWeatherData) {
        currentValuesContainer.innerHTML = `
            <div class="stat-card rounded-lg p-3 text-center col-span-2 md:col-span-3">
                <div class="text-gray-400 text-sm">Nice Weather methodology is unavailable until today's weather data loads.</div>
            </div>
        `;
        reasoningContainer.innerHTML = '';
    } else {
        const label = getNiceWeatherLabel(currentNiceWeatherData.score);
        currentValuesContainer.innerHTML = `
            <div class="stat-card rounded-lg p-3 text-center col-span-2 md:col-span-3">
                <div class="text-gray-400 text-xs mb-1">Overall Score</div>
                <div class="text-3xl font-bold text-white">${currentNiceWeatherData.score}/10</div>
                <div class="text-sm font-semibold ${label.colorClass}">${label.label}</div>
            </div>
            ${currentNiceWeatherData.factors.map(factor => `
                <div class="stat-card rounded-lg p-3 text-center">
                    <div class="text-gray-400 text-xs mb-1"><i class="${factor.iconClass} mr-1"></i>${factor.name}</div>
                    <div class="text-white font-bold">${factor.value}</div>
                </div>
            `).join('')}
        `;

        reasoningContainer.innerHTML = currentNiceWeatherData.factors.map(factor => `
            <div class="stat-card rounded-lg p-3">
                <div class="flex items-start justify-between gap-3">
                    <div>
                        <div class="font-semibold text-white"><i class="${factor.iconClass} mr-2"></i>${factor.name}</div>
                        <div class="text-gray-400 text-sm mt-1">${factor.value} - ${factor.note}</div>
                    </div>
                    <div class="shrink-0 font-bold ${factor.points > 0 ? 'text-yellow-400' : 'text-green-400'}">${factor.points > 0 ? `−${factor.points}` : '0'}</div>
                </div>
            </div>
        `).join('');
    }

    modal.classList.add('active');
}

// Chart selector functionality
function initializeChartSelector(selectId) {
    const select = document.getElementById(selectId);
    if (!select) return;

    const modal = select.closest('.modal');
    const chartContainers = modal.querySelectorAll('.chart-container');

    // Set initial state to show temperature chart
    select.value = 'temp';

    // Replace select with clone to remove stale event listeners
    const newSelect = select.cloneNode(true);
    select.parentNode.replaceChild(newSelect, select);

    // cloneNode doesn't reliably preserve select.value — set it after insertion
    newSelect.value = 'temp';

    // IMPORTANT: updateChartVisibility must reference newSelect (the live DOM element),
    // not the original select (detached after clone). The closure captures `select`
    // which is no longer in the DOM after replaceChild.
    function updateChartVisibility() {
        const selectedValue = newSelect.value;

        chartContainers.forEach(container => {
            if (container.dataset.featureHidden === 'true') {
                container.style.display = 'none';
                return;
            }
            if (selectedValue === 'all') {
                container.style.display = 'block';
            } else {
                const chartType = container.getAttribute('data-chart-type');
                container.style.display = chartType === selectedValue ? 'block' : 'none';
            }
        });
    }

    // Apply initial visibility for the cloned select
    updateChartVisibility();
    newSelect.addEventListener('change', updateChartVisibility);
}

// Modal functionality
function openHourlyModal(data) {
    const modal = document.getElementById('hourlyModal');
    modal.classList.add('active');
    setHourlyTidesVisibility(currentTideData);

    // Show all chart containers so ApexCharts can measure width
    modal.querySelectorAll('.chart-container').forEach(c => c.style.display = 'block');

    // Destroy existing charts if they exist
    Object.values(hourlyChart).forEach(chart => {
        if (chart) chart.destroy();
    });
    hourlyChart = {};

    // Prepare data
    const now = new Date();
    const currentHour = now.getHours();

    // Find today's data in the hourly forecast (skip past days due to past_days=2)
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0); // Set to start of today

    let startIndex = 0;
    // Find the first hour of today
    for (let i = 0; i < data.hourly.time.length; i++) {
        const hourTime = new Date(data.hourly.time[i]);
        hourTime.setHours(0, 0, 0, 0); // Set to start of that day
        if (hourTime.getTime() >= todayStart.getTime()) {
            // Found today's data, now find the closest hour to current time
            for (let j = i; j < data.hourly.time.length; j++) {
                const currentHourTime = new Date(data.hourly.time[j]);
                if (currentHourTime.getHours() >= currentHour) {
                    startIndex = j;
                    break;
                }
            }
            if (startIndex > 0) break; // Found it
        }
    }

    const hours = [];
    const temps = [];
    const precip = [];
    const snow = [];
    const wind = [];
    const humidity = [];
    const pressure = [];
    const cloudLow = [];
    const cloudMid = [];
    const cloudHigh = [];
    const shortwaveData = [];
    const labels = [];

    for (let i = 0; i < HOURLY_FORECAST_HOURS && (startIndex + i) < data.hourly.time.length; i++) {
        const idx = startIndex + i;
        const hour = new Date(data.hourly.time[idx]);
        labels.push(formatTime12Hour(hour));
        hours.push(hour);
        temps.push(Math.round(data.hourly.temperature_2m[idx]));
        precip.push(data.hourly.precipitation ? data.hourly.precipitation[idx] : 0);
        snow.push(data.hourly.snowfall ? data.hourly.snowfall[idx] : 0);
        wind.push(data.hourly.wind_speed_10m[idx]);
        humidity.push(data.hourly.relative_humidity_2m[idx]);
        // Convert hPa to inHg (1 hPa = 0.02953 inHg)
        pressure.push(data.hourly.surface_pressure ? (data.hourly.surface_pressure[idx] * 0.02953).toFixed(2) : null);
        cloudLow.push(data.hourly.cloud_cover_low ? data.hourly.cloud_cover_low[idx] : 0);
        cloudMid.push(data.hourly.cloud_cover_mid ? data.hourly.cloud_cover_mid[idx] : 0);
        cloudHigh.push(data.hourly.cloud_cover_high ? data.hourly.cloud_cover_high[idx] : 0);
        shortwaveData.push(data.hourly.shortwave_radiation ? data.hourly.shortwave_radiation[idx] : 0);
    }

    const maxRadiation = Math.max(...shortwaveData.filter(v => v !== null && v !== undefined && v > 0), 1);
    const brightnessData = shortwaveData.map(v => v === null || v === undefined ? 0 : Math.round((v / maxRadiation) * 100));

    // Create charts
    // Check if there's any snow in the hourly forecast
    const hasSnowHourly = snow.some(val => val > 0);

    const tideChartContainer = document.getElementById('hourlyTidesChartContainer');
    const tideChartEl = document.getElementById('hourlyTidesChart');
    const nowMs = Date.now();
    const end48hMs = nowMs + (48 * 60 * 60 * 1000);
    const tideCurve48h = currentTideData?.interpolatedPredictions
        ? currentTideData.interpolatedPredictions.filter((point) => {
            const pointTimeMs = point.time.getTime();
            return pointTimeMs >= nowMs && pointTimeMs <= end48hMs;
        })
        : [];

    const hasTideData = tideCurve48h.length >= 2;
    if (tideChartContainer) {
        tideChartContainer.dataset.featureHidden = hasTideData ? 'false' : 'true';
    }

    let tideLabels = [];
    let tideValues = [];
    let tideHighMarkers = [];
    let tideLowMarkers = [];
    let tideMarkerLabels = [];
    let tideYAxisBounds = { min: -1, max: 1 };

    if (hasTideData) {
        tideLabels = tideCurve48h.map((point) => formatTime12Hour(point.time));
        tideValues = tideCurve48h.map((point) => point.value);
        tideYAxisBounds = computeTideYAxisBounds(tideValues);
        tideHighMarkers = new Array(tideCurve48h.length).fill(null);
        tideLowMarkers = new Array(tideCurve48h.length).fill(null);

        const hilo48h = currentTideData.hiloPredictions.filter((point) => {
            const pointTimeMs = point.time.getTime();
            return pointTimeMs >= nowMs && pointTimeMs <= end48hMs;
        });

        hilo48h.forEach((point) => {
            let closestIdx = 0;
            let minDiff = Infinity;
            for (let idx = 0; idx < tideCurve48h.length; idx++) {
                const diff = Math.abs(tideCurve48h[idx].time.getTime() - point.time.getTime());
                if (diff < minDiff) {
                    minDiff = diff;
                    closestIdx = idx;
                }
            }

            // Only mark events within 30 minutes of an interpolated curve point.
            if (minDiff > 30 * 60 * 1000) return;

            if (point.type === 'H') {
                tideHighMarkers[closestIdx] = point.value;
                tideMarkerLabels.push({ index: closestIdx, value: point.value, text: 'H' });
            } else if (point.type === 'L') {
                tideLowMarkers[closestIdx] = point.value;
                tideMarkerLabels.push({ index: closestIdx, value: point.value, text: 'L' });
            }
        });
    }

    // Build tide annotations for H/L markers
    const tideAnnotations = {};
    tideMarkerLabels.forEach((point) => {
        const labelKey = `tideLabel_${point.index}_${point.text}`;
        tideAnnotations[labelKey] = {
            x: point.index,
            y: point.value,
            borderColor: 'transparent',
            label: {
                text: point.text,
                position: 'top',
                offsetY: -8,
                style: {
                    background: 'transparent',
                    color: '#67e8f9',
                    fontSize: '11px',
                    fontWeight: 600,
                    cssClass: 'apexcharts-tide-label'
                }
            }
        };
    });

    hourlyChart = {};
    hourlyChart.temp = new ApexCharts(document.getElementById('hourlyTempChart'), baseChartOptions({
        series: [{ name: `Temperature (${UNITS.temperature})`, data: temps }],
        colors: ['rgb(255, 99, 132)'],
        
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "°F", style: { color: "#fff" } } }
    }));
    hourlyChart.temp.render();

    hourlyChart.precip = new ApexCharts(document.getElementById('hourlyPrecipChart'), baseChartOptions({
        series: [{ name: `Precipitation (${UNITS.precipitation})`, data: precip }],
        colors: ['rgb(54, 162, 235)'],
        
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "inches", style: { color: '#fff' } } }
    }));
    hourlyChart.precip.render();

    hourlyChart.wind = new ApexCharts(document.getElementById('hourlyWindChart'), baseChartOptions({
        series: [{ name: `Wind Speed (${UNITS.wind})`, data: wind }],
        colors: ['rgb(255, 206, 86)'],
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "mph", style: { color: "#fff" } } }
    }));
    hourlyChart.wind.render();

    hourlyChart.humidity = new ApexCharts(document.getElementById('hourlyHumidityChart'), baseChartOptions({
        series: [{ name: `Humidity (${UNITS.humidity})`, data: humidity }],
        colors: ['rgb(75, 192, 192)'],
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "%", style: { color: "#fff" } } }
    }));
    hourlyChart.humidity.render();

    hourlyChart.pressure = new ApexCharts(document.getElementById('hourlyPressureChart'), baseChartOptions({
        series: [{ name: 'Pressure (inHg)', data: pressure }],
        colors: ['rgb(34, 197, 94)'],
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "inHg", style: { color: "#fff" } } }
    }));
    hourlyChart.pressure.render();

    hourlyChart.snow = new ApexCharts(document.getElementById('hourlySnowChart'), baseChartOptions({
        series: [{ name: `Snowfall (${UNITS.snowfall})`, data: snow }],
        colors: ['rgb(176, 196, 222)'],
        
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "inches", style: { color: "#fff" } } }
    }));
    hourlyChart.snow.render();

    hourlyChart.cloud = new ApexCharts(document.getElementById('hourlyCloudChart'), baseChartOptions({
        chart: { type: 'bar', stacked: true },
        series: [
            { name: 'Low Clouds', data: cloudLow },
            { name: 'Mid Clouds', data: cloudMid },
            { name: 'High Clouds', data: cloudHigh }
        ],
        colors: ['rgba(100, 116, 139, 0.75)', 'rgba(148, 163, 184, 0.7)', 'rgba(203, 213, 225, 0.65)'],
        fill: { type: 'solid' },
        plotOptions: { bar: { borderRadius: 2 } },
        xaxis: { categories: labels },
        yaxis: { min: 0, max: 100, title: { text: '%', style: { color: '#fff' } }, labels: { style: { colors: '#fff' }, formatter: (val) => `${val}%` } }
    }));
    hourlyChart.cloud.render();

    hourlyChart.brightness = new ApexCharts(document.getElementById('hourlyBrightnessChart'), baseChartOptions({
        series: [{ name: 'Brightness (%)', data: brightnessData }],
        colors: ['rgb(250, 204, 21)'],
        
        
        xaxis: { categories: labels },
        yaxis: { min: 0, max: 100, title: { text: '%', style: { color: '#fff' } }, labels: { style: { colors: '#fff' }, formatter: (val) => `${val}%` } }
    }));
    hourlyChart.brightness.render();

    hourlyChart.tides = (hasTideData && tideChartEl) ? new ApexCharts(tideChartEl, baseChartOptions({
        chart: { type: 'line' },
        series: [
            { name: 'Tide Height (ft, MLLW)', data: tideValues, type: 'area' },
            { name: 'High Tide', data: tideHighMarkers, type: 'scatter' },
            { name: 'Low Tide', data: tideLowMarkers, type: 'scatter' }
        ],
        colors: ['#06b6d4', '#67e8f9', '#22d3ee'],
        stroke: { curve: 'monotoneCubic', width: [3, 0, 0] },
        fill: { type: ['gradient', 'solid', 'solid'], opacity: [0.3, 1, 1] },
        markers: { size: [0, 6, 6], shape: ['circle', 'circle', 'square'] },
        xaxis: { categories: tideLabels },
        yaxis: { min: tideYAxisBounds.min, max: tideYAxisBounds.max, title: { text: 'ft', style: { color: '#fff' } }, labels: { style: { colors: '#fff' }, formatter: (val) => `${val} ft` } },
        tooltip: { y: { formatter: (val) => `${Number(val).toFixed(1)} ft` } },
        annotations: { points: tideAnnotations }
    })) : null;
    if (hourlyChart.tides) hourlyChart.tides.render();

    // Hide/show precipitation and snow charts based on data
    const hourlyPrecipChartContainer = document.getElementById('hourlyPrecipChart').parentElement;
    const hourlySnowChartContainer = document.getElementById('hourlySnowChart').parentElement;

    if (hasSnowHourly) {
        hourlyPrecipChartContainer.style.display = 'none';
        hourlySnowChartContainer.style.display = 'block';
    } else {
        hourlyPrecipChartContainer.style.display = 'block';
        hourlySnowChartContainer.style.display = 'none';
    }

    // Populate detailed hourly items
    const detailsContainer = document.getElementById('hourlyDetails');
    detailsContainer.innerHTML = '';
    for (let i = 0; i < hours.length; i++) {
        const idx = startIndex + i;
        const hour = hours[i];
        const detailItem = document.createElement('div');
        detailItem.className = 'forecast-chip rounded-lg p-4 backdrop-blur-sm';
        detailItem.innerHTML = `
                <div class="flex items-center justify-between mb-2">
                <div class="text-white font-semibold">${hour.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })} ${formatTime12Hour(hour)}</div>
                <div class="text-2xl">${getWeatherIcon(data.hourly.weather_code[idx], data.hourly.is_day ? data.hourly.is_day[idx] !== 0 : true)}</div>
            </div>
            <div class="grid grid-cols-2 gap-2 text-sm">
                <div><span class="text-white/70">Temp:</span> <span class="text-white font-bold">${Math.round(temps[i])}${UNITS.temperature}</span></div>
                <div><span class="text-white/70">Condition:</span> <span class="text-white">${getWeatherDescription(data.hourly.weather_code[idx])}</span></div>
                <div><span class="text-white/70">Wind:</span> <span class="text-white">${wind[i]} ${UNITS.wind}</span></div>
                <div><span class="text-white/70">Humidity:</span> <span class="text-white">${humidity[i]}${UNITS.humidity}</span></div>
                ${pressure[i] ? `<div><span class="text-white/70">Pressure:</span> <span class="text-white">${pressure[i]}" inHg</span></div>` : ''}
                ${data.hourly.snowfall && snow[i] > 0 ? '' : (data.hourly.precipitation ? `<div><span class="text-white/70">Precip:</span> <span class="text-white">${precip[i]} ${UNITS.precipitation}</span>${data.hourly.precipitation_probability && data.hourly.precipitation_probability[idx] !== null && data.hourly.precipitation_probability[idx] !== undefined ? ` <span class="text-white/60">(${data.hourly.precipitation_probability[idx]}%)</span>` : ''}</div>` : '')}
                ${data.hourly.snowfall && snow[i] > 0 ? `<div><span class="text-white/70">Snow:</span> <span class="text-white">${snow[i]} ${UNITS.snowfall}</span>${data.hourly.precipitation_probability && data.hourly.precipitation_probability[idx] !== null && data.hourly.precipitation_probability[idx] !== undefined ? ` <span class="text-white/60">(${data.hourly.precipitation_probability[idx]}%)</span>` : ''}</div>` : ''}
                ${data.hourly.snowfall && snow[i] > 0 ? '' : (data.hourly.precipitation_probability && data.hourly.precipitation_probability[idx] !== null && data.hourly.precipitation_probability[idx] !== undefined && !data.hourly.precipitation ? `<div><span class="text-white/70">Rain Chance:</span> <span class="text-white">${data.hourly.precipitation_probability[idx]}%</span></div>` : '')}
            </div>
            <div class="mt-2 text-white/80 text-sm">${getWeatherDescription(data.hourly.weather_code[idx])}</div>
        `;
        detailsContainer.appendChild(detailItem);
    }

    // Reveal charts after modal slide-in animation completes (300ms)
    setTimeout(() => initializeChartSelector('hourlyChartSelect'), 320);
}

function openDailyModal(data) {
    const modal = document.getElementById('dailyModal');
    modal.classList.add('active');
    setDailyTidesVisibility(currentTideData);

    // Show all chart containers so ApexCharts can measure width
    modal.querySelectorAll('.chart-container').forEach(c => c.style.display = 'block');

    // Destroy existing charts if they exist
    Object.values(dailyChart).forEach(chart => {
        if (chart) chart.destroy();
    });
    dailyChart = {};

    // Prepare data
    const labels = [];
    const maxTemps = [];
    const minTemps = [];
    const apparentMaxTemps = [];
    const apparentMinTemps = [];
    const precip = [];
    const snowfall = [];
    const wind = [];
    const precipProb = [];
    const moonPhases = [];
    const niceWeatherScores = [];
    const dailyPressure = [];
    const dailyCloudLow = [];
    const dailyCloudMid = [];
    const dailyCloudHigh = [];
    const dailyShortwaveAverage = [];
    const dailyTideLabels = [];
    const dailyTideValues = [];
    const dailyTideHighMarkers = [];
    const dailyTideLowMarkers = [];
    const dailyTideMarkerLabels = [];
    let dailyTideYAxisBounds = { min: -1, max: 1 };
    const apparentUnit = UNITS.temperature;

    // Start from index 2 to skip past 2 days due to past_days=2
    for (let i = 0; i < Math.min(14, data.daily.time.length - 2); i++) {
        const dayIndex = i + 2; // Skip past days
        const day = parseDateString(data.daily.time[dayIndex]);
        labels.push(day.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }));
        maxTemps.push(Math.round(data.daily.temperature_2m_max[dayIndex]));
        minTemps.push(Math.round(data.daily.temperature_2m_min[dayIndex]));
        const apparentMaxRaw = data.daily.apparent_temperature_max ? data.daily.apparent_temperature_max[dayIndex] : null;
        const apparentMinRaw = data.daily.apparent_temperature_min ? data.daily.apparent_temperature_min[dayIndex] : null;
        apparentMaxTemps.push(apparentMaxRaw !== null && apparentMaxRaw !== undefined ? Math.round(apparentMaxRaw) : null);
        apparentMinTemps.push(apparentMinRaw !== null && apparentMinRaw !== undefined ? Math.round(apparentMinRaw) : null);
        precip.push(data.daily.precipitation_sum[dayIndex] || 0);
        snowfall.push(data.daily.snowfall_sum ? data.daily.snowfall_sum[dayIndex] || 0 : 0);
        wind.push(data.daily.wind_speed_10m_max[dayIndex]);
        precipProb.push(data.daily.precipitation_probability_max ? data.daily.precipitation_probability_max[dayIndex] : 0);
        moonPhases.push(calculateMoonPhase(day));
        const dayAvg = calculateDailyAveragesForDateString(data.hourly, data.daily.time[dayIndex]);
        niceWeatherScores.push(calculateNiceWeatherIndex(data, dayAvg, dayIndex));

        // Calculate daily average pressure from hourly data (noon value for each day)
        if (data.hourly && data.hourly.surface_pressure) {
            const dayStr = data.daily.time[dayIndex];
            const noonIdx = data.hourly.time.findIndex(t => t.startsWith(dayStr) && t.includes('T12:'));
            if (noonIdx !== -1) {
                // Convert hPa to inHg
                dailyPressure.push((data.hourly.surface_pressure[noonIdx] * 0.02953).toFixed(2));
            } else {
                // Fallback: use first hour of the day
                const dayIdx = data.hourly.time.findIndex(t => t.startsWith(dayStr));
                if (dayIdx !== -1) {
                    dailyPressure.push((data.hourly.surface_pressure[dayIdx] * 0.02953).toFixed(2));
                } else {
                    dailyPressure.push(null);
                }
            }
        } else {
            dailyPressure.push(null);
        }

        // Calculate daily average cloud cover by altitude band from hourly data
        if (data.hourly && data.hourly.time && data.hourly.cloud_cover_low && data.hourly.cloud_cover_mid && data.hourly.cloud_cover_high) {
            const dayStr = data.daily.time[dayIndex];
            const dayHourlyIndexes = [];
            for (let h = 0; h < data.hourly.time.length; h++) {
                if (data.hourly.time[h].startsWith(dayStr)) {
                    dayHourlyIndexes.push(h);
                }
            }

            if (dayHourlyIndexes.length > 0) {
                const avgCloudLow = dayHourlyIndexes.reduce((sum, h) => sum + (data.hourly.cloud_cover_low[h] ?? 0), 0) / dayHourlyIndexes.length;
                const avgCloudMid = dayHourlyIndexes.reduce((sum, h) => sum + (data.hourly.cloud_cover_mid[h] ?? 0), 0) / dayHourlyIndexes.length;
                const avgCloudHigh = dayHourlyIndexes.reduce((sum, h) => sum + (data.hourly.cloud_cover_high[h] ?? 0), 0) / dayHourlyIndexes.length;
                dailyCloudLow.push(Number(avgCloudLow.toFixed(1)));
                dailyCloudMid.push(Number(avgCloudMid.toFixed(1)));
                dailyCloudHigh.push(Number(avgCloudHigh.toFixed(1)));
            } else {
                dailyCloudLow.push(0);
                dailyCloudMid.push(0);
                dailyCloudHigh.push(0);
            }
        } else {
            dailyCloudLow.push(0);
            dailyCloudMid.push(0);
            dailyCloudHigh.push(0);
        }

        // Calculate daily average shortwave radiation from hourly data
        if (data.hourly && data.hourly.time && data.hourly.shortwave_radiation) {
            const dayStr = data.daily.time[dayIndex];
            const dayHourlyIndexes = [];
            for (let h = 0; h < data.hourly.time.length; h++) {
                if (data.hourly.time[h].startsWith(dayStr)) {
                    dayHourlyIndexes.push(h);
                }
            }

            if (dayHourlyIndexes.length > 0) {
                const avgShortwave = dayHourlyIndexes.reduce((sum, h) => sum + (data.hourly.shortwave_radiation[h] ?? 0), 0) / dayHourlyIndexes.length;
                dailyShortwaveAverage.push(Number(avgShortwave.toFixed(1)));
            } else {
                dailyShortwaveAverage.push(0);
            }
        } else {
            dailyShortwaveAverage.push(0);
        }
    }

    const nowMs = Date.now();
    const end14dMs = nowMs + (14 * 24 * 60 * 60 * 1000);
    const dailyTideCurve14d = currentTideData?.interpolatedPredictions
        ? currentTideData.interpolatedPredictions.filter((point) => {
            const pointTimeMs = point.time.getTime();
            return pointTimeMs >= nowMs && pointTimeMs <= end14dMs;
        })
        : [];

    const hasDailyTideData = dailyTideCurve14d.length >= 2;
    const dailyTideChartEl = document.getElementById('dailyTidesChart');

    if (hasDailyTideData) {
        dailyTideCurve14d.forEach((point) => {
            dailyTideLabels.push(point.time.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }));
            dailyTideValues.push(point.value);
            dailyTideHighMarkers.push(null);
            dailyTideLowMarkers.push(null);
        });

        dailyTideYAxisBounds = computeTideYAxisBounds(dailyTideValues);

        const hilo14d = currentTideData.hiloPredictions.filter((point) => {
            const pointTimeMs = point.time.getTime();
            return pointTimeMs >= nowMs && pointTimeMs <= end14dMs;
        });

        hilo14d.forEach((point) => {
            let closestIdx = 0;
            let minDiff = Infinity;
            for (let idx = 0; idx < dailyTideCurve14d.length; idx++) {
                const diff = Math.abs(dailyTideCurve14d[idx].time.getTime() - point.time.getTime());
                if (diff < minDiff) {
                    minDiff = diff;
                    closestIdx = idx;
                }
            }

            if (minDiff > 30 * 60 * 1000) return;

            if (point.type === 'H') {
                dailyTideHighMarkers[closestIdx] = point.value;
                dailyTideMarkerLabels.push({ index: closestIdx, value: point.value, text: 'H' });
            } else if (point.type === 'L') {
                dailyTideLowMarkers[closestIdx] = point.value;
                dailyTideMarkerLabels.push({ index: closestIdx, value: point.value, text: 'L' });
            }
        });
    }

    const maxDailyShortwave = Math.max(...dailyShortwaveAverage.filter(v => v !== null && v !== undefined && v > 0), 1);
    const dailyBrightnessData = dailyShortwaveAverage.map(v => v === null || v === undefined ? 0 : Math.round((v / maxDailyShortwave) * 100));

    // Build daily tide annotations for H/L markers
    const dailyTideAnnotations = {};
    dailyTideMarkerLabels.forEach((point) => {
        const labelKey = `dailyTideLabel_${point.index}_${point.text}`;
        dailyTideAnnotations[labelKey] = {
            x: point.index,
            y: point.value,
            borderColor: 'transparent',
            label: {
                text: point.text,
                position: 'top',
                offsetY: -8,
                style: {
                    background: 'transparent',
                    color: '#67e8f9',
                    fontSize: '10px',
                    fontWeight: 600,
                    cssClass: 'apexcharts-tide-label'
                }
            }
        };
    });

    // Create charts
    dailyChart = {};

    dailyChart.temp = new ApexCharts(document.getElementById('dailyTempChart'), baseChartOptions({
        series: [
            { name: `High (${UNITS.temperature})`, data: maxTemps },
            { name: `Low (${UNITS.temperature})`, data: minTemps }
        ],
        colors: ['rgb(255, 99, 132)', 'rgb(54, 162, 235)'],
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "°F", style: { color: "#fff" } } }
    }));
    dailyChart.temp.render();

    dailyChart.feelsLike = new ApexCharts(document.getElementById('dailyFeelsLikeChart'), baseChartOptions({
        series: [
            { name: `Feels Like High (${UNITS.temperature})`, data: apparentMaxTemps },
            { name: `Feels Like Low (${UNITS.temperature})`, data: apparentMinTemps }
        ],
        colors: ['rgb(251, 146, 60)', 'rgb(56, 189, 248)'],
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "°F", style: { color: "#fff" } } }
    }));
    dailyChart.feelsLike.render();

    // Nice weather chart with custom point colors
    const niceWeatherPointColors = niceWeatherScores.map(score => {
        if (score === null || score === undefined) return 'rgba(148, 163, 184, 0.9)';
        if (score >= 8) return 'rgb(34, 197, 94)';
        if (score >= 6) return 'rgb(132, 204, 22)';
        if (score >= 4) return 'rgb(250, 204, 21)';
        return 'rgb(251, 146, 60)';
    });
    dailyChart.niceWeather = new ApexCharts(document.getElementById('dailyNiceWeatherChart'), baseChartOptions({
        series: [{ name: 'Nice Weather', data: niceWeatherScores }],
        colors: ['rgb(132, 204, 22)'],
        
        
        markers: { size: 4, colors: niceWeatherPointColors, strokeColors: '#fff', strokeWidth: 1 },
        xaxis: { categories: labels },
        yaxis: { min: 0, max: 10, tickAmount: 5, title: { text: '/10', style: { color: '#fff' } }, labels: { style: { colors: '#fff' }, formatter: (val) => `${val}/10` } },
        tooltip: { y: { formatter: (val) => (val === null || val === undefined ? 'Nice Weather: unavailable' : `Nice Weather: ${val}/10`) } }
    }));
    dailyChart.niceWeather.render();

    dailyChart.precip = new ApexCharts(document.getElementById('dailyPrecipChart'), baseChartOptions({
        series: [{ name: `Precipitation (${UNITS.precipitation})`, data: precip }],
        colors: ['rgb(54, 162, 235)'],
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "inches", style: { color: "#fff" } } }
    }));
    dailyChart.precip.render();

    dailyChart.wind = new ApexCharts(document.getElementById('dailyWindChart'), baseChartOptions({
        series: [{ name: `Wind Speed (${UNITS.wind})`, data: wind }],
        colors: ['rgb(255, 206, 86)'],
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "mph", style: { color: "#fff" } } }
    }));
    dailyChart.wind.render();

    dailyChart.pressure = new ApexCharts(document.getElementById('dailyPressureChart'), baseChartOptions({
        series: [{ name: 'Pressure (inHg)', data: dailyPressure }],
        colors: ['rgb(34, 197, 94)'],
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "inHg", style: { color: "#fff" } } }
    }));
    dailyChart.pressure.render();

    dailyChart.snow = new ApexCharts(document.getElementById('dailySnowChart'), baseChartOptions({
        series: [{ name: `Snowfall (${UNITS.snowfall})`, data: snowfall }],
        colors: ['rgb(173, 216, 230)'],
        
        
        xaxis: { categories: labels },
        yaxis: { title: { text: "inches", style: { color: "#fff" } } }
    }));
    dailyChart.snow.render();

    dailyChart.cloud = new ApexCharts(document.getElementById('dailyCloudChart'), baseChartOptions({
        chart: { type: 'bar', stacked: true },
        series: [
            { name: 'Low Clouds', data: dailyCloudLow },
            { name: 'Mid Clouds', data: dailyCloudMid },
            { name: 'High Clouds', data: dailyCloudHigh }
        ],
        colors: ['rgba(100, 116, 139, 0.75)', 'rgba(148, 163, 184, 0.7)', 'rgba(203, 213, 225, 0.65)'],
        fill: { type: 'solid' },
        plotOptions: { bar: { borderRadius: 2 } },
        xaxis: { categories: labels },
        yaxis: { min: 0, max: 100, title: { text: '%', style: { color: '#fff' } }, labels: { style: { colors: '#fff' }, formatter: (val) => `${val}%` } }
    }));
    dailyChart.cloud.render();

    dailyChart.brightness = new ApexCharts(document.getElementById('dailyBrightnessChart'), baseChartOptions({
        series: [{ name: 'Brightness (%)', data: dailyBrightnessData }],
        colors: ['rgb(250, 204, 21)'],
        
        
        xaxis: { categories: labels },
        yaxis: { min: 0, max: 100, title: { text: '%', style: { color: '#fff' } }, labels: { style: { colors: '#fff' }, formatter: (val) => `${val}%` } }
    }));
    dailyChart.brightness.render();

    dailyChart.tides = (hasDailyTideData && dailyTideChartEl) ? new ApexCharts(dailyTideChartEl, baseChartOptions({
        chart: { type: 'line' },
        series: [
            { name: 'Tide Height (ft, MLLW)', data: dailyTideValues, type: 'area' },
            { name: 'High Tide', data: dailyTideHighMarkers, type: 'scatter' },
            { name: 'Low Tide', data: dailyTideLowMarkers, type: 'scatter' }
        ],
        colors: ['#06b6d4', '#67e8f9', '#22d3ee'],
        stroke: { curve: 'monotoneCubic', width: [3, 0, 0] },
        fill: { type: ['gradient', 'solid', 'solid'], opacity: [0.3, 1, 1] },
        markers: { size: [0, 6, 6], shape: ['circle', 'circle', 'square'] },
        xaxis: { categories: dailyTideLabels, tickAmount: 14 },
        yaxis: { min: dailyTideYAxisBounds.min, max: dailyTideYAxisBounds.max, title: { text: 'ft', style: { color: '#fff' } }, labels: { style: { colors: '#fff' }, formatter: (val) => `${val} ft` } },
        tooltip: {
            x: { formatter: (_val, opts) => {
                const idx = opts?.dataPointIndex;
                return dailyTideCurve14d[idx]?.time?.toLocaleString('en-US', { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) || '';
            }},
            y: { formatter: (val) => `${Number(val).toFixed(1)} ft` }
        },
        annotations: { points: dailyTideAnnotations }
    })) : null;
    if (dailyChart.tides) dailyChart.tides.render();

    dailyChart.moonPhase = new ApexCharts(document.getElementById('dailyMoonPhaseChart'), baseChartOptions({
        series: [{ name: 'Moon Phase', data: moonPhases }],
        colors: ['rgb(147, 112, 219)'],
        
        
        xaxis: { categories: labels },
        yaxis: {
            min: 0, max: 1, tickAmount: 8,
            labels: { style: { colors: '#fff' }, formatter: (val) => getMoonPhase(val).emoji }
        },
        tooltip: { y: { formatter: (val) => { const phase = getMoonPhase(val); return `Moon Phase: ${phase.emoji} ${phase.name} (${(val * 100).toFixed(1)}%)`; } } }
    }));
    dailyChart.moonPhase.render();

    // Hide/show charts based on rain and snow presence
    const snowChartContainer = document.getElementById('dailySnowChart').parentElement;
    const precipChartContainer = document.getElementById('dailyPrecipChart').parentElement;
    const hasSnow = snowfall.some(val => val > 0);
    const hasRain = precip.some(val => val > 0);

    // Show both charts if both rain and snow are present
    if (hasSnow && hasRain) {
        snowChartContainer.style.display = 'block';
        precipChartContainer.style.display = 'block';
    } else if (hasSnow) {
        // Only snow, show snow chart
        snowChartContainer.style.display = 'block';
        precipChartContainer.style.display = 'none';
    } else {
        // Only rain or neither, show precipitation chart
        snowChartContainer.style.display = 'none';
        precipChartContainer.style.display = 'block';
    }

    // Populate detailed daily items
    const detailsContainer = document.getElementById('dailyDetails');
    detailsContainer.innerHTML = '';
    // Start from index 2 to skip past 2 days due to past_days=2
    for (let i = 0; i < Math.min(14, data.daily.time.length - 2); i++) {
        const dayIndex = i + 2; // Skip past days
        const day = parseDateString(data.daily.time[dayIndex]);
        const moonPhaseValue = calculateMoonPhase(day);
        const moonPhase = getMoonPhase(moonPhaseValue);
        const detailItem = document.createElement('div');
        detailItem.className = 'forecast-chip rounded-lg p-4 backdrop-blur-sm';
        detailItem.innerHTML = `
            <div class="flex items-center justify-between mb-3">
                <div>
                    <div class="text-white font-semibold text-lg">${day.toLocaleDateString('en-US', { weekday: 'long' })}</div>
                    <div class="text-white/70 text-sm">${day.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}</div>
                </div>
                <div class="text-4xl">${getWeatherIcon(data.daily.weather_code[dayIndex], true, data.daily.precipitation_probability_max ? data.daily.precipitation_probability_max[dayIndex] : null)}</div>
            </div>
            <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
                <div class="bg-white/10 rounded p-3">
                    <div class="text-white/70 text-xs mb-1">High / Low</div>
                    <div class="text-white font-bold">${Math.round(maxTemps[i])}${UNITS.temperature} / ${Math.round(minTemps[i])}${UNITS.temperature}</div>
                    ${apparentMaxTemps[i] !== null && apparentMaxTemps[i] !== undefined && apparentMinTemps[i] !== null && apparentMinTemps[i] !== undefined ? `<div class="text-white/60 text-xs mt-1">Feels like ${apparentMaxTemps[i]}${apparentUnit} / ${apparentMinTemps[i]}${apparentUnit}</div>` : ''}
                </div>
                ${snowfall[i] > 0 ? `
                <div class="bg-white/10 rounded p-3">
                    <div class="text-white/70 text-xs mb-1"><i class="fas fa-snowflake mr-1"></i>Snowfall</div>
                    <div class="text-white font-bold">${snowfall[i]} ${UNITS.snowfall}</div>
                    ${precipProb[i] !== null && precipProb[i] !== undefined ? `<div class="text-white/60 text-xs mt-1"><i class="fas fa-snowflake mr-1"></i>${precipProb[i]}%</div>` : ''}
                </div>
                ` : `
                <div class="bg-white/10 rounded p-3">
                    <div class="text-white/70 text-xs mb-1">Precipitation</div>
                    <div class="text-white font-bold">${precip[i]} ${UNITS.precipitation}</div>
                    ${precipProb[i] !== null && precipProb[i] !== undefined ? `<div class="text-white/60 text-xs mt-1"><i class="fas fa-tint mr-1"></i>${precipProb[i]}%</div>` : ''}
                </div>
                `}
                <div class="bg-white/10 rounded p-3">
                    <div class="text-white/70 text-xs mb-1">Wind Speed</div>
                    <div class="text-white font-bold">${wind[i]} ${UNITS.wind}</div>
                </div>
                ${dailyPressure[i] ? `
                <div class="bg-white/10 rounded p-3">
                    <div class="text-white/70 text-xs mb-1"><i class="fas fa-gauge mr-1"></i>Pressure</div>
                    <div class="text-white font-bold">${dailyPressure[i]}" inHg</div>
                </div>
                ` : ''}
                <div class="bg-white/10 rounded p-3 moon-phase-clickable" style="cursor: pointer;">
                    <div class="text-white/70 text-xs mb-1"><i class="fas fa-moon mr-1"></i>Moon Phase</div>
                    <div class="text-white font-bold flex items-center gap-2">
                        <span class="text-xl">${moonPhase.emoji}</span>
                        <span class="text-sm">${moonPhase.name}</span>
                    </div>
                </div>
                <div class="bg-white/10 rounded p-3">
                    <div class="text-white/70 text-xs mb-1"><i class="fas fa-sun mr-1"></i>Sun</div>
                    <div class="text-white">
                        <span class="text-yellow-400 text-xs">↑</span> <span class="text-sm font-semibold">${data.daily.sunrise && data.daily.sunrise[i] ? formatTime12Hour(new Date(data.daily.sunrise[i])) : 'N/A'}</span>
                    </div>
                    <div class="text-white mt-0.5">
                        <span class="text-orange-400 text-xs">↓</span> <span class="text-sm font-semibold">${data.daily.sunset && data.daily.sunset[i] ? formatTime12Hour(new Date(data.daily.sunset[i])) : 'N/A'}</span>
                    </div>
                </div>
            </div>
            <div class="mt-3 text-white/80">${getWeatherDescription(data.daily.weather_code[dayIndex])}</div>
        `;

        // Add click handler for moon phase card in modal
        const moonPhaseCard = detailItem.querySelector('.moon-phase-clickable');
        if (moonPhaseCard) {
            moonPhaseCard.addEventListener('click', (e) => {
                e.stopPropagation();
                openMoonDetailsModal(day);
            });
        }

        detailsContainer.appendChild(detailItem);
    }

    // Temperature toggle: Actual vs Feels Like
    // Reveal charts after modal slide-in animation completes (300ms)
    setTimeout(() => initializeChartSelector('dailyChartSelect'), 320);
}

// Modal close handlers
document.getElementById('closeHourlyModal').addEventListener('click', () => {
    document.getElementById('hourlyModal').classList.remove('active');
});

document.getElementById('closeDailyModal').addEventListener('click', () => {
    document.getElementById('dailyModal').classList.remove('active');
});

document.getElementById('closeMoonDetailsModal').addEventListener('click', () => {
    document.getElementById('moonDetailsModal').classList.remove('active');
});

document.getElementById('closeSymptomRiskModal').addEventListener('click', () => {
    document.getElementById('symptomRiskModal').classList.remove('active');
});

document.getElementById('closeNiceWeatherModal').addEventListener('click', () => {
    document.getElementById('niceWeatherModal').classList.remove('active');
});

document.getElementById('niceWeatherSection').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        openNiceWeatherModal();
    }
});

// Close modals when clicking outside
document.getElementById('hourlyModal').addEventListener('click', (e) => {
    if (e.target.id === 'hourlyModal') {
        document.getElementById('hourlyModal').classList.remove('active');
    }
});

document.getElementById('dailyModal').addEventListener('click', (e) => {
    if (e.target.id === 'dailyModal') {
        document.getElementById('dailyModal').classList.remove('active');
    }
});

document.getElementById('moonDetailsModal').addEventListener('click', (e) => {
    if (e.target.id === 'moonDetailsModal') {
        document.getElementById('moonDetailsModal').classList.remove('active');
    }
});

document.getElementById('symptomRiskModal').addEventListener('click', (e) => {
    if (e.target.id === 'symptomRiskModal') {
        document.getElementById('symptomRiskModal').classList.remove('active');
    }
});

document.getElementById('niceWeatherModal').addEventListener('click', (e) => {
    if (e.target.id === 'niceWeatherModal') {
        document.getElementById('niceWeatherModal').classList.remove('active');
    }
});

// Close modals with Escape key
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        document.getElementById('hourlyModal').classList.remove('active');
        document.getElementById('dailyModal').classList.remove('active');
        document.getElementById('moonDetailsModal').classList.remove('active');
        document.getElementById('symptomRiskModal').classList.remove('active');
        document.getElementById('niceWeatherModal').classList.remove('active');
    }
});

// Ventusky Radar functionality
function buildVentuskyUrl(lat, lon) {
    const isMobile = window.innerWidth <= 768;
    const zoom = isMobile ? 7 : 8; // Lower zoom on mobile (more zoomed out)
    // Use root map URL because /precipitation-map currently 302-redirects upstream.
    return `/ventusky-proxy/?p=${lat};${lon};${zoom}&l=rain`;
}

function setRadarFallback(visible, lat, lon) {
    const fallback = document.getElementById('radarFallback');
    const fallbackLink = document.getElementById('radarFallbackLink');
    if (!fallback || !fallbackLink) return;

    const directUrl = `https://www.ventusky.com/?p=${lat};${lon};7&l=rain`;
    fallbackLink.href = directUrl;
    fallback.classList.toggle('hidden', !visible);
}

function initializeVentuskyRadar(lat, lon) {
    // Build Ventusky URL with location parameters
    const ventuskyUrl = buildVentuskyUrl(lat, lon);

    // Set iframe source
    const ventuskyFrame = document.getElementById('ventuskyFrame');
    if (ventuskyFrame) {
        setRadarFallback(false, lat, lon);

        // Set handlers once to avoid listener pileups on repeated weather fetches
        if (!ventuskyFrame.dataset.handlersAttached) {
            ventuskyFrame.addEventListener('load', () => {
                // If we got a load event, hide fallback
                setRadarFallback(false, currentLat || lat, currentLon || lon);
                try {
                    // Try to access iframe content to prevent new tab opens
                    const iframeWindow = ventuskyFrame.contentWindow;
                    if (iframeWindow) {
                        iframeWindow.open = function() {
                            console.log('Blocked iframe window.open');
                            return null;
                        };
                    }
                } catch (e) {
                    // Cross-origin restrictions prevent this, expected
                }
            });

            ventuskyFrame.addEventListener('error', () => {
                setRadarFallback(true, currentLat || lat, currentLon || lon);
            });

            ventuskyFrame.dataset.handlersAttached = '1';
        }

        // If iframe stays blank (known on some Windows setups), show fallback link
        if (window.radarLoadTimeout) clearTimeout(window.radarLoadTimeout);
        window.radarLoadTimeout = setTimeout(() => {
            setRadarFallback(true, currentLat || lat, currentLon || lon);
        }, 8000);

        ventuskyFrame.src = ventuskyUrl;
    }

    // Prevent container clicks and scroll events from opening new tabs
    const radarContainer = document.getElementById('radarContainer');
    const ventuskyContainer = document.getElementById('ventuskyContainer');

    if (radarContainer && !radarContainer.dataset.guardsAttached) {
        // Track if user is scrolling to prevent accidental interactions
        let scrollTimeout;
        let isUserScrolling = false;

        // Monitor page scroll to detect when user is actively scrolling
        window.addEventListener('scroll', () => {
            isUserScrolling = true;
            clearTimeout(scrollTimeout);
            scrollTimeout = setTimeout(() => {
                isUserScrolling = false;
            }, 300);
        }, { passive: true });

        // Prevent clicks during or right after scrolling
        radarContainer.addEventListener('click', (e) => {
            if (isUserScrolling) {
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                return false;
            }
            // Only prevent if clicking outside the iframe
            if (e.target === radarContainer || e.target === ventuskyContainer) {
                e.preventDefault();
                e.stopPropagation();
                return false;
            }
        }, { passive: false, capture: true });

        // Prevent focus events that might trigger new tabs
        radarContainer.addEventListener('focusin', (e) => {
            if (isUserScrolling) {
                e.preventDefault();
                e.stopPropagation();
            }
        }, { capture: true });

        radarContainer.dataset.guardsAttached = '1';
    }
}

function updateVentuskyLocation(lat, lon) {
    const ventuskyUrl = buildVentuskyUrl(lat, lon);

    const ventuskyFrame = document.getElementById('ventuskyFrame');
    if (ventuskyFrame) {
        setRadarFallback(false, lat, lon);
        ventuskyFrame.src = ventuskyUrl;
    }
}
