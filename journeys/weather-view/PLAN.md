# WeatherView: Accessible Five-Day Forecast — Spec

WeatherView is a production-quality static website built with vanilla HTML, CSS, and JavaScript. It uses Open-Meteo for city lookup and five-day forecasts, supports browser geolocation, Celsius/Fahrenheit units, light/dark themes, and resilient loading and error states. GitHub Copilot uses this document as the implementation spec.

README prompts use the exact section names in this document as stable references. If a section is renamed, update its README references in the same change.

**Source:** This spec builds on the [WeatherView implementation plan](https://github.com/DanWahlin/github-copilot-get-started/blob/main/.plans/main-plan.md) from `github-copilot-get-started` and resolves its city-search/geolocation notes into one coherent user flow.

**Resolved source decision:** The source plan both marks a city textbox as required and later says city search is outside v1. This journey intentionally keeps the required city search while also implementing browser geolocation and deterministic Seattle fallback. That preserves both valuable user paths, makes the app more complete, and gives the learner a meaningful external-API/error-state flow to test.

**Out of scope:** No account system, paid weather API, backend API, database, maps, severe-weather alerts, push notifications, or server-side rendering.

---

## Choose Your Stack

**Happy path (required for this journey):** vanilla HTML5 + CSS + modern JavaScript ES modules, Node.js 24 LTS or later for local tooling and verification, Azure Static Web Apps Free tier, Bicep, and Azure Developer CLI (`azd`).

Do not replace the frontend with React, Vue, Angular, a CSS framework, or a component library. The point is to practice planning, modular browser code, accessibility, testing, and Azure deployment without framework abstraction.

## Project Structure

```text
weather-view/
├── index.html
├── styles.css
├── app.js
├── weather-api.js
├── weather-maps.js
├── staticwebapp.config.json
├── package.json
├── tests/
│   └── weather.spec.js
├── scripts/
│   ├── build-static.mjs
│   └── verify-app.mjs
├── dist/                  # Generated deployable assets; ignored by Git
├── infra/
│   ├── main.bicep
│   ├── main.parameters.json
│   └── modules/
│       └── static-web-app.bicep
└── azure.yaml
```

Keep application modules at the journey root so they deploy directly as static assets. Generated dependencies and deployment state (`node_modules/`, `test-results/`, `playwright-report/`, `.azure/`) must be ignored by Git.

---

## Product Experience

### Primary User Flow

1. On first load, render the app shell immediately and show a polite loading status.
2. Ask for browser geolocation only after the page is interactive. If permission succeeds, load that location's forecast.
3. If permission is denied, unavailable, or times out, load the fixed fallback location: **Seattle, Washington** (`47.6062`, `-122.3321`). Explain the fallback without presenting it as an error.
4. Let the user search for another city at any time. Resolve the city through Open-Meteo Geocoding, show a useful location label, and load its forecast.
5. When multiple geocoding matches exist, use the highest-ranked result and display `name`, `admin1` when present, and country. Do not invent coordinates.
6. Changing units refetches the current location in the selected unit. Changing theme never refetches weather data.
7. Persist selected unit, theme override, and last successful location in `localStorage`. If no explicit theme exists, follow `prefers-color-scheme`.

### Layout and Visual Design

- Use a centered app shell with a readable maximum width and generous spacing.
- Header/navigation contains the WeatherView brand, city search, unit toggle, and theme toggle.
- Show the resolved location and forecast update time above the cards.
- Render five forecast cards in a responsive grid: five or three columns when space allows, two on tablet, one on narrow mobile screens.
- Each card shows day/date, semantic weather icon, weather description, high/low temperature, precipitation probability, and maximum wind speed.
- Use CSS custom properties for design tokens and both themes.
- Use subtle hover/focus/theme transitions, while respecting `prefers-reduced-motion`.
- Avoid external image dependencies. Weather icons may be inline SVG or Unicode with accessible text; they must remain legible in both themes.
- Include concise, present-tense Open-Meteo attribution in the footer.

### Theme Behavior

- Default to the operating-system preference through `prefers-color-scheme`.
- Persist an explicit user choice as `weather-view-theme` with value `light` or `dark`.
- Apply `data-theme` to the root `<html>` element.
- The theme control must expose its current state through visible text and an accessible name.
- Both themes must maintain WCAG AA-conscious contrast for text and controls.

### Unit Behavior

- Support Celsius and Fahrenheit.
- Persist the choice as `weather-view-unit` with value `celsius` or `fahrenheit`.
- Request the selected unit from Open-Meteo with `temperature_unit`; do not convert cached values in the browser.
- Refetch the current coordinates when the unit changes.
- Display `°C` or `°F` consistently on every forecast card.

### City Search

- Provide a labeled text input and submit button in the header or controls region.
- Trim input and reject an empty city without making a request.
- Resolve cities with `https://geocoding-api.open-meteo.com/v1/search` using `name`, `count=5`, `language=en`, and `format=json`.
- If no result exists, show a helpful inline error and keep the previous successful forecast visible.
- Submit on Enter and through the visible button.
- Disable repeat submission while a request is active.

---

## Weather Data

### Forecast API

Use `https://api.open-meteo.com/v1/forecast`.

Required query parameters:

- `latitude`
- `longitude`
- `daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max`
- `timezone=auto`
- `forecast_days=5`
- `temperature_unit=celsius|fahrenheit`

Use a dedicated `weather-api.js` module. It must:

1. Build URLs with `URL` and `URLSearchParams`, not string concatenation.
2. Treat non-2xx responses as errors.
3. Validate the response shape before normalization.
4. Require exactly five aligned values for time and every required daily field.
5. Normalize raw parallel arrays into an array of five UI-focused forecast objects.
6. Preserve enough location/timezone metadata to render an accurate label and update time.
7. Map network, HTTP, geocoding-empty, and malformed-payload failures to user-safe messages while retaining useful errors for tests.
8. Treat each `daily.time` value as a calendar date in the forecast timezone. Do not parse it at midnight and then format it in a western timezone, which can display the previous day. Use a date-only-safe representation or a noon anchor and test an America timezone explicitly.

### Normalized Forecast Model

```js
{
  location: {
    name: "Seattle, Washington, United States",
    latitude: 47.6062,
    longitude: -122.3321,
    timezone: "America/Los_Angeles"
  },
  unit: "celsius",
  days: [
    {
      date: "2026-07-28",
      weatherCode: 1,
      description: "Mainly clear",
      icon: "partly-cloudy",
      temperatureMax: 24.1,
      temperatureMin: 15.8,
      precipitationProbability: 10,
      windSpeedMax: 18.2
    }
  ]
}
```

### Weather Code Mapping

Keep WMO weather-code mapping in `weather-maps.js`. Include, at minimum:

- `0`: Clear sky
- `1`, `2`, `3`: Mainly clear, partly cloudy, overcast
- `45`, `48`: Fog
- `51`, `53`, `55`, `56`, `57`: Drizzle/freezing drizzle
- `61`, `63`, `65`, `66`, `67`: Rain/freezing rain
- `71`, `73`, `75`, `77`: Snow
- `80`, `81`, `82`, `85`, `86`: Showers
- `95`, `96`, `99`: Thunderstorm

Unknown codes must map to a neutral `Unknown conditions` label and safe icon rather than crashing.

### Caching

- Cache the last successful normalized response in memory or `sessionStorage` by rounded coordinates plus selected unit.
- A cached result may be reused for up to 10 minutes.
- Never cache failures.
- Unit changes use separate cache keys.
- Persist only the last successful location, not the complete forecast, in `localStorage`.

---

## Application States and Resilience

The UI must represent these states explicitly:

- **Initial/loading:** app shell is visible; status region announces loading.
- **Success:** exactly five cards and location metadata render.
- **Empty geocoding result:** previous forecast remains; search error is visible.
- **Forecast error:** show a plain-language error and Retry button.
- **Malformed response:** treat it as a forecast error; never render partial mismatched cards.
- **Offline/network failure:** retain the previous successful forecast when available and offer Retry.

Use one `aria-live="polite"` status region. Do not move keyboard focus unexpectedly when asynchronous work completes. Retry repeats the last failed action with the current location/unit.

---

## Accessibility and Performance

### Accessibility

- Use semantic `header`, `nav`, `main`, `section`, and heading structure.
- Associate every input/control with a visible label or unambiguous accessible name.
- All controls work with keyboard-only navigation and show a visible focus indicator.
- Toggle state uses native controls or accurate `aria-pressed`/`aria-checked` semantics.
- Decorative icons are hidden from assistive technology; weather meaning is available as text.
- Do not encode weather or temperature meaning through color alone.
- Respect `prefers-reduced-motion`.

### Performance

- Use no production framework or runtime dependency.
- Load JavaScript with `type="module"` and defer parsing naturally.
- Render cards in one DOM update using a template string or `DocumentFragment`.
- Avoid layout-thrashing read/write loops.
- Keep the initial static payload small and avoid external fonts and image assets.
- Target no console errors and no failed required network requests in the successful flow.

---

## Local Tooling and Tests

Create a minimal `package.json` with Node.js 24 or later and scripts:

- `start`: serve the project locally on a configurable port without requiring a global package
- `build`: recreate `dist/` and copy only deployable site assets
- `test`: run unit/behavior tests
- `test:e2e`: run Playwright browser tests when installed
- `verify`: run `node scripts/verify-app.mjs`

Tests must cover:

1. Forecast URL contains all required fields, `forecast_days=5`, `timezone=auto`, and selected `temperature_unit`.
2. Response normalization produces exactly five aligned day objects.
3. Malformed or incomplete payloads fail closed.
4. WMO code mapping includes representative clear, rain, snow, thunderstorm, and unknown values.
5. Unit and theme preferences persist and restore.
6. Search empty input does not call geocoding.
7. Geolocation denial falls back to Seattle.
8. Successful rendering creates exactly five cards.
9. Unit change causes a refetch using the new source unit.
10. Error and retry states are keyboard accessible.
11. A mocked `2026-07-28` forecast in `America/Phoenix` renders `Tuesday, Jul 28`, not the previous day.

The generated `scripts/verify-app.mjs` must start or connect to the local server, verify the main document and all required static modules, call Open-Meteo with Seattle coordinates, assert exactly five forecast days, and exit nonzero on every failed status or assertion. It must not print secrets (none are required by this app).

---

## Azure Deployment

Deploy the static site to **Azure Static Web Apps Free tier** using Bicep and `azd`. No local Docker, backend service, API key, storage account, or GitHub Actions workflow is required.

**Publish architecture recovery:** Record the host platform and architecture before deployment, but do not reject ARM64 automatically. Windows 11 on ARM can run many x64 applications through emulation. If azd provisions the Static Web App and the publish phase then fails with `Exec format error`, `cannot execute binary file`, or raw ELF output, use the learner-facing Troubleshooting recovery. The recovery may use one approved temporary x64 Azure Container Instance, must keep the deployment token only in process memory and secure environment values, and must delete and verify deletion of the exact container group in a `finally` path. If policy prohibits that temporary resource, continue from an approved x64 host. Never install privileged emulation or make local Docker a prerequisite.

### Azure Skills Plugin

The Azure Skills plugin for GitHub Copilot supplies current Azure guidance and validation. Install it with the canonical marketplace and plugin names:

```text
/plugin marketplace add microsoft/azure-skills
/plugin install azure@azure-skills
```

Use its tools/skills intentionally:

| Tool / Skill | When to use |
|---|---|
| `azure_bicep_schema` | Confirm current `Microsoft.Web/staticSites` or AVM properties and API versions |
| `azure_deploy_iac_guidance` | Confirm the `azd` + Static Web Apps project layout |
| `azure_deploy_plan` | Review the proposed deployment before `azd up` |
| `azure-prepare` | Generate Bicep, `main.parameters.json`, and `azure.yaml` |
| `azure-validate` | Validate Bicep and deployment configuration without creating resources |
| `azure-deploy` | Guide the `azd up` deployment and diagnose deployment failures |

### Azure Resources

| Resource | Module / approach | Purpose |
|---|---|---|
| Resource group | Subscription-scope `main.bicep` | Owns the journey resources |
| Azure Static Web App | Prefer `br/public:avm/res/web/static-site`; fall back to raw `Microsoft.Web/staticSites@2023-12-01` if current AVM inputs block deployment | Hosts the static site globally |

Use Free SKU (`name: Free`, `tier: Free`), `provider: Custom`, and `allowConfigFileUpdates: true`. Apply the tag `{ 'azd-service-name': 'web' }` so `azd` maps the declared service to the resource.

Azure Static Web Apps supports only selected deployment locations. Normalize the requested location to one of `centralus`, `eastus2`, `westus2`, `westeurope`, or `eastasia`; use `eastus2` as the documented default/fallback. The resource group may remain in the selected `AZURE_LOCATION`.

### Bicep Requirements

1. `infra/main.bicep` runs at subscription scope and creates one environment-scoped resource group.
2. Put resource-group resources in a resource-group-scoped module.
3. Names are deterministic, lowercase where required, and include an environment token.
4. Apply standard `azd-env-name` tagging and `azd-service-name: web` to the Static Web App.
5. Output `WEB_URL`, `STATIC_WEB_APP_NAME`, and `RESOURCE_GROUP_NAME` in SCREAMING_SNAKE_CASE.
6. Do not create a deployment token, GitHub workflow, managed function, backend, or secret.
7. Prefer the Static Web App AVM module, but use raw `Microsoft.Web/staticSites` when current AVM parameter drift blocks a working deployment; document the reason in `issues.md`.

### azure.yaml

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/Azure/azure-dev/main/schemas/v1.0/azure.yaml.json
name: weather-view
metadata:
  template: weather-view@0.0.1
services:
  web:
    project: .
    language: js
    host: staticwebapp
    dist: dist
infra:
  provider: bicep
  path: ./infra
```

Azure Developer CLI cannot publish a Static Web App when both its service source and output folder resolve to the project root. Generate `scripts/build-static.mjs`, set `dist: dist`, and add an npm `build` script. The build script must recreate `dist/` and copy only `index.html`, `styles.css`, `app.js`, `weather-api.js`, `weather-maps.js`, and `staticwebapp.config.json`. It must not copy tests, scripts, dependencies, `.azure`, documentation, package files, or infrastructure. Add `dist/` to `.gitignore`, run the build before deployment, and inspect the exact output list.

### Static Web Apps Configuration

Create `staticwebapp.config.json` with:

- A navigation fallback to `/index.html` that excludes static files (`*.css`, `*.js`, icons, and common image extensions).
- Security headers including `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, and a practical Content Security Policy allowing only self plus the two required Open-Meteo HTTPS origins for `connect-src`.
- No blanket caching rule for `index.html`; hashed assets are optional for this small journey.

### Deployment Flow

1. Use GitHub Copilot and the Azure Skills plugin to validate prerequisites, register `Microsoft.Web` only if needed, read the current subscription ID, and set `AZURE_SUBSCRIPTION_ID` as a literal `azd` environment value.
2. Record the deployment host platform and architecture. Continue on ARM64 unless the publisher returns the documented architecture error.
3. Run `azd up` from the generated `journeys/weather-view` workspace directory.
4. Wait for infrastructure provisioning and the `web` service deployment to finish successfully.
5. Read `WEB_URL` through `azd env get-value WEB_URL`.
6. Run the checked-in deployment verifier and browser acceptance checks immediately.

### Deployment Acceptance Criteria

Deployment is complete only when all checks pass:

- `WEB_URL` uses HTTPS and returns HTTP 200.
- `index.html`, `styles.css`, `app.js`, `weather-api.js`, and `weather-maps.js` load successfully from Azure Static Web Apps.
- The deployed page renders exactly five forecast cards from a live Open-Meteo response.
- Default/fallback location is visibly Seattle when geolocation is unavailable in the automated browser.
- City search changes the location and keeps five cards visible.
- Celsius/Fahrenheit changes the displayed unit and persists after reload.
- Light/dark theme changes and persists after reload.
- Keyboard focus is visible and controls have usable accessible names.
- The successful browser flow has no console errors and no failed required document, script, stylesheet, fetch, or XHR requests.
- A full-page screenshot is captured from the deployed URL.

The journey README owns the commands and prompts that create local verification, generate infrastructure, execute `azd up`, run `.github/scripts/verify-weather-view.mjs`, perform browser acceptance, and clean up with `azd down --force --purge`.
