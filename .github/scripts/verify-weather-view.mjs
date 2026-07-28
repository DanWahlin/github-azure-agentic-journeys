import { azdValue, fail, main, request } from './_utils.mjs';

function requireMatch(text, pattern, description) {
  if (!pattern.test(text)) fail(`Missing ${description}`);
}

async function fetchText(url, description) {
  const response = await request(url, { timeoutMs: 60000 });
  const text = await response.text();
  if (response.status !== 200) {
    fail(`${description} returned HTTP ${response.status}: ${text.slice(0, 200)}`);
  }
  return { response, text };
}

function requireFiveAlignedDays(payload) {
  const required = [
    'time',
    'weather_code',
    'temperature_2m_max',
    'temperature_2m_min',
    'precipitation_probability_max',
    'wind_speed_10m_max',
  ];

  if (!payload?.daily || typeof payload.daily !== 'object') {
    fail('Open-Meteo response is missing daily data');
  }

  for (const field of required) {
    const value = payload.daily[field];
    if (!Array.isArray(value) || value.length !== 5) {
      fail(`Open-Meteo daily.${field} must contain exactly 5 values; received ${Array.isArray(value) ? value.length : 'non-array'}`);
    }
  }
}

main(async () => {
  const webUrl = azdValue('WEB_URL');
  if (!/^https:\/\//i.test(webUrl)) fail(`WEB_URL must use HTTPS: ${webUrl}`);

  const root = new URL('/', `${webUrl}/`).href;
  const { response: documentResponse, text: html } = await fetchText(root, 'WeatherView document');
  requireMatch(html, /WeatherView/i, 'WeatherView branding in index.html');
  requireMatch(html, /<script[^>]+type=["']module["'][^>]+src=["'][^"']*app\.js["']/i, 'module script for app.js');
  requireMatch(html, /(?:forecast|weather)[-_ ]?(?:grid|cards?)/i, 'forecast container marker');
  requireMatch(html, /aria-live=["']polite["']/i, 'polite live status region');

  const contentType = documentResponse.headers.get('content-type') ?? '';
  if (!contentType.toLowerCase().includes('text/html')) {
    fail(`WeatherView document content-type is not text/html: ${contentType || '<missing>'}`);
  }

  const nosniff = documentResponse.headers.get('x-content-type-options') ?? '';
  if (nosniff.toLowerCase() !== 'nosniff') {
    fail(`X-Content-Type-Options must be nosniff; received ${nosniff || '<missing>'}`);
  }

  const assets = [
    ['styles.css', /(?:data-theme|prefers-color-scheme)/i, 'theme styles'],
    ['app.js', /(?:geolocation|getCurrentPosition)/i, 'geolocation flow'],
    ['weather-api.js', /api\.open-meteo\.com\/v1\/forecast/i, 'Open-Meteo forecast endpoint'],
    ['weather-maps.js', /(?:weatherCode|weather_code|WMO|thunderstorm)/i, 'weather-code mapping'],
  ];

  for (const [path, marker, description] of assets) {
    const { text } = await fetchText(new URL(path, root).href, path);
    requireMatch(text, marker, description);
  }

  const forecastUrl = new URL('https://api.open-meteo.com/v1/forecast');
  forecastUrl.searchParams.set('latitude', '47.6062');
  forecastUrl.searchParams.set('longitude', '-122.3321');
  forecastUrl.searchParams.set(
    'daily',
    'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max',
  );
  forecastUrl.searchParams.set('timezone', 'auto');
  forecastUrl.searchParams.set('forecast_days', '5');
  forecastUrl.searchParams.set('temperature_unit', 'celsius');

  const forecastResponse = await request(forecastUrl.href, { timeoutMs: 60000 });
  const forecastText = await forecastResponse.text();
  if (forecastResponse.status !== 200) {
    fail(`Open-Meteo forecast returned HTTP ${forecastResponse.status}: ${forecastText.slice(0, 200)}`);
  }

  let forecast;
  try {
    forecast = JSON.parse(forecastText);
  } catch {
    fail(`Open-Meteo forecast did not return valid JSON: ${forecastText.slice(0, 200)}`);
  }
  requireFiveAlignedDays(forecast);

  console.log(`WeatherView URL: ${webUrl}`);
  console.log('PASS: WeatherView assets and five-day Open-Meteo contract verified');
});
