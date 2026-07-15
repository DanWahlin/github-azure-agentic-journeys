# SmartTodo: AI-Powered Task Breakdown — Spec

A todo app where vague goals become actionable plans. Type "Prepare Conference talk" and AI returns concrete steps you can check off. This document is the spec — GitHub Copilot reads it to generate the implementation.

**Out of scope:** No user authentication (anonymous for now), no push notifications, no collaboration/sharing, no offline sync, no recurring todos, no image attachments.

---

## Choose Your Stack

Pick your API language. Data models, endpoints, and acceptance criteria are identical across stacks. Azure Functions Flex Consumption is the hosting plan for all languages.

**Happy path (recommended for first run):** Node.js + TypeScript + Azure Functions v4, region `westus`, model `gpt-5-mini` (fallback `gpt-4.1`). Todo status enum: **`pending` | `in_progress` | `completed`** only (never `not_started`).

| | Node.js | Python | .NET | Java |
|---|---------|--------|------|------|
| **Framework** | Azure Functions Node.js v4 programming model (`@azure/functions`) + TypeScript | Azure Functions v4 runtime (Python v2 programming model) | Azure Functions isolated worker model + C# | Azure Functions + Java |
| **Azure SQL** | `mssql` + `@types/mssql` (dev) | `mssql-python` | `Microsoft.Data.SqlClient` | `mssql-jdbc` (`com.microsoft.sqlserver:mssql-jdbc`) |
| **AI** | `openai` | `openai` | `OpenAI` | `com.openai:openai-java` |

Frontend: Swift/SwiftUI (iOS 17+). **macOS + Xcode required for the iOS client.** Deploy backend with **azd** + **Bicep**. Prefer Azure Verified Modules (AVM), but use raw `Microsoft.*` resources when AVM parameter drift blocks deployment.

The iOS app is NOT deployed by azd — only the Azure backend is. The app points at the deployed API URL via a `Config.swift` file.

## Project Structure

```
smart-todo/
├── src/
│   ├── api/                    # Azure Functions (your chosen language)
│   │   ├── host.json
│   │   ├── local.settings.json
│   │   └── src/
│   │       ├── functions/      # HTTP-triggered functions
│   │       ├── data/           # Repository pattern + Azure SQL
│   │       ├── ai/             # AI task decomposition
│   │       └── models/         # Data models
│   └── ios/
│       └── SmartTodo/
│           ├── SmartTodo.xcodeproj
│           ├── SmartTodoApp.swift
│           ├── Config.swift
│           ├── Models/
│           ├── Services/
│           └── Views/
├── infra/                      # Bicep with AVM modules or raw Microsoft.* resources
│   ├── main.bicep
│   ├── main.parameters.json
│   ├── abbreviations.json
│   └── modules/
└── azure.yaml                  # azd configuration
```

The API must follow the **repository pattern** (interfaces/contracts → implementations → factory) so functions never import the database client directly. Define repository contracts as interfaces/protocols per your language. The data layer uses Azure SQL.

---

## Phase 1: API

Build the API with Azure SQL Database. You'll need an Azure SQL instance provisioned (Phase 3 creates this, or use an existing one during development).

### Data Access Layer

Repository contracts — define as interfaces/protocols per your language:

```
TodoRepository:
  getAll(userId) → Todo[]
  getById(id) → Todo | null
  create(input) → Todo
  update(id, updates) → Todo
  delete(id) → void

ActionStepRepository:
  getByTodoId(todoId) → ActionStep[]
  create(step) → ActionStep
  update(id, updates) → ActionStep
  deleteByTodoId(todoId) → void

DataStore:
  todos: TodoRepository
  actionSteps: ActionStepRepository
  initialize() → void
```

Functions never import the database client directly — they get a `DataStore` from the factory. The factory should call `initialize()` once and cache the result so that HTTP function handlers don't pay the cost of `CREATE TABLE IF NOT EXISTS` on every request.

> **Note:** The `update()` method on `TodoRepository` must also support updating `stepsGenerated` (boolean) — the `generateSteps` function sets this to `true` after inserting AI-generated steps. Include `stepsGenerated` as an optional field in your update input type alongside `title` and `status`.

**Node.js entry point note:** Set `"main": "dist/functions/*.js"` in `package.json` — this must match where `tsc` emits the compiled function files. Since `tsconfig.json` uses `rootDir: "src"` and `outDir: "dist"`, source files under `src/functions/` compile to `dist/functions/` (the `src/` prefix is stripped). A common mistake is writing `"main": "dist/src/functions/*.js"` which causes Azure Functions Core Tools to find zero functions.

**Node.js deployment note:** For `azd` remote/Oryx build, do not exclude `src/` or `tsconfig.json` in `.funcignore`; Azure needs both to compile TypeScript. Exclude `node_modules/`, `dist/**/*.map`, and `local.settings.json`.

**Azure SQL notes:** Use `[order]` (bracket-quoted) since `order` is a SQL reserved word. For managed identity auth, use `azure-active-directory-default` authentication — no passwords. SSL is required by default. In Azure, set `AZURE_SQL_SERVER` to the full FQDN from `fullyQualifiedDomainName` (for example, `sql-name.database.windows.net`) and do not strip the `.database.windows.net` suffix. For local development, connect to Azure SQL using a connection string with SQL auth or your Azure AD identity — set `AZURE_SQL_SERVER`, `AZURE_SQL_DATABASE`, and optionally `AZURE_SQL_USER`/`AZURE_SQL_PASSWORD` in `local.settings.json`.

### Data Models

#### Todo

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| id | string | auto | UUID v4, generated on create |
| title | string | yes | 1–500 characters, trimmed |
| status | string | auto | `pending` on create. Valid values: `pending`, `in_progress`, `completed` |
| userId | string | yes | Non-empty string |
| stepsGenerated | boolean | auto | `false` on create, `true` after steps are generated |
| createdAt | string | auto | ISO 8601 timestamp |
| updatedAt | string | auto | ISO 8601 timestamp, updated on every change |

#### ActionStep

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| id | string | auto | UUID v4, generated on create |
| todoId | string | yes | Must reference an existing Todo |
| title | string | yes | 1–200 characters |
| description | string | yes | 1–1000 characters, actionable detail |
| order | number | yes | 1-based sequential integer |
| isCompleted | boolean | auto | `false` on create |
| createdAt | string | auto | ISO 8601 timestamp |

### Database Schema (SQL)

```sql
CREATE TABLE Todos (
    id NVARCHAR(36) PRIMARY KEY,
    title NVARCHAR(500) NOT NULL,
    status NVARCHAR(20) NOT NULL DEFAULT 'pending',
    userId NVARCHAR(100) NOT NULL,
    stepsGenerated BIT NOT NULL DEFAULT 0,
    createdAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE()
);

CREATE INDEX IX_Todos_UserId ON Todos(userId);

CREATE TABLE ActionSteps (
    id NVARCHAR(36) PRIMARY KEY,
    todoId NVARCHAR(36) NOT NULL,
    title NVARCHAR(200) NOT NULL,
    description NVARCHAR(1000) NOT NULL,
    [order] INT NOT NULL,
    isCompleted BIT NOT NULL DEFAULT 0,
    createdAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT FK_ActionSteps_Todos FOREIGN KEY (todoId) REFERENCES Todos(id) ON DELETE CASCADE
);

CREATE INDEX IX_ActionSteps_TodoId ON ActionSteps(todoId);
```

### API Endpoints

#### `GET /api/todos`

Query parameters:

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| userId | string | yes | Filter todos by user |

Response (200): `Todo[]` including nested `steps`. 400 if `userId` is missing.

#### `POST /api/todos`

Request body:

```json
{
  "title": "Prepare Conference talk",
  "userId": "user-1"
}
```

Response (201): Created `Todo` with `status: "pending"`, `stepsGenerated: false`, and empty `steps`. 400 if `title` is empty, missing, or exceeds 500 characters. 400 if `userId` is missing.

#### `PATCH /api/todos/:id`

Request body (all fields optional):

```json
{
  "title": "Prepare Conference keynote",
  "status": "in_progress"
}
```

Response (200): Updated todo object (same shape as GET response, including steps).

404 if todo not found. 400 if `status` is not one of `pending`, `in_progress`, `completed`.

#### `DELETE /api/todos/:id`

Response (204): No content.

404 if todo not found. Cascade-deletes associated action steps.

#### `POST /api/todos/:id/generate-steps`

No request body. Calls the AI service to generate action steps from the todo's title.

**Behavior:**
1. Fetch the todo by ID — 404 if not found
2. If `stepsGenerated` is already `true`, delete existing steps first (regenerate)
3. Call gpt-5-mini with the todo title using the system prompt from the AI Task Decomposition section below
4. Parse the AI response as a JSON array
5. Validate each item has `title` (string, non-empty) and `description` (string, non-empty)
6. Assign sequential `order` values starting at 1
7. Generate UUID for each step's `id`
8. Insert all steps into the database
9. Set `stepsGenerated = true` on the todo
10. Return the todo with all generated steps

Response (200): Updated `Todo` with 3-7 AI-generated `steps`. Each step has `title`, `description`, `order`, and `isCompleted`. 404 if todo not found. 503 if AI service is unavailable or returns unparseable output after retry.

#### `PATCH /api/todos/:id/steps/:stepId`

Request body:

```json
{
  "isCompleted": true
}
```

Response (200): Updated `ActionStep`. 404 if todo or step not found. 400 if `isCompleted` is not a boolean.

**Auto-completion rule:** After updating a step, check all steps for the parent todo. If ALL steps are `isCompleted: true`, set the todo's status to `completed`. If a step is unchecked (`isCompleted: false`) and the todo's status is `completed`, set it back to `in_progress`.

### Error Response Format

All errors return:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Title is required and must be between 1 and 500 characters."
  }
}
```

Error codes: `VALIDATION_ERROR`, `NOT_FOUND`, `AI_SERVICE_ERROR`, `INTERNAL_ERROR`.

Status code mapping:
- `VALIDATION_ERROR` → 400
- `NOT_FOUND` → 404
- `AI_SERVICE_ERROR` → 503
- `INTERNAL_ERROR` → 500

### Seed Data

The seed script (`src/api/src/data/seed.ts`) must run before first use so the API returns data immediately. Add an npm script to make this easy: `"seed": "tsx src/data/seed.ts"`. The seed should be idempotent — skip if the database already contains rows. The README test commands (e.g., `curl .../api/todos/todo-1`) assume seed data is present.

**Todos** (all userId: "user-1"):

| id | title | status | stepsGenerated |
|----|-------|--------|----------------|
| todo-1 | Prepare Conference talk | pending | false |
| todo-2 | Set up home office | in_progress | true |
| todo-3 | Plan weekend hiking trip | completed | true |

Seed action steps for `todo-2` and `todo-3` so the app can show generated/completed states immediately:

| id | todoId | title | order | isCompleted |
|----|--------|-------|-------|-------------|
| step-2-1 | todo-2 | Choose a desk and chair | 1 | true |
| step-2-2 | todo-2 | Set up monitor and peripherals | 2 | true |
| step-2-3 | todo-2 | Organize cable management | 3 | false |
| step-2-4 | todo-2 | Set up lighting | 4 | false |
| step-3-1 | todo-3 | Pick a trail | 1 | true |
| step-3-2 | todo-3 | Check weather forecast | 2 | true |
| step-3-3 | todo-3 | Pack gear and supplies | 3 | true |

Use short actionable descriptions for each seed step.

### AI Task Decomposition

**Endpoint:** `POST /api/todos/:id/generate-steps`

**AI SDK:** Use the plain OpenAI-compatible SDK for the chosen language (`openai`, `OpenAI`, or `com.openai:openai-java`) with a normalized `/openai/v1/` base URL.

**Client setup:** Normalize `AZURE_AI_ENDPOINT` so it ends with `/openai/v1/`, pass `AZURE_AI_KEY` as the API key, and pass `AZURE_AI_DEPLOYMENT` as the model/deployment name when calling chat completions.

**System prompt:**

```
You are a productivity assistant that breaks down goals into actionable steps.

Given a todo item, generate 3-7 concrete, actionable steps to accomplish it.
Each step should be specific enough that someone could start working on it immediately.

Rules:
- Each step title must be under 200 characters
- Each step description must be 1-3 sentences with specific, actionable detail
- Include quantities, time estimates, or specific tools where relevant
- Steps must be in logical order (what to do first, second, etc.)
- Be practical and realistic, not generic or motivational

Respond with ONLY a valid JSON array. No markdown, no code fences, no explanation:
[
  {
    "title": "Short action title",
    "description": "Specific actionable description with details."
  }
]
```

**User prompt:** The todo's `title` field, verbatim.

**Model config:**
- Model: `gpt-5-mini` (fallback: `gpt-4.1` — check regional availability with `az cognitiveservices model list --location <region>`)
- Temperature: leave at the model default — gpt-5 family models reject custom temperature values. Set `0.7` only if using the gpt-4.1 fallback.
- Max tokens: `1500`

**Response parsing:**
1. Get the raw text response from the model
2. Strip markdown code fences if present (` ```json\n...\n``` ` → `[...]`)
3. Parse as JSON array
4. Validate: array of objects, each with non-empty `title` (string) and `description` (string)
5. If validation fails, retry once with a stricter follow-up: "Your previous response was not valid JSON. Return ONLY a JSON array."
6. If retry fails, throw `AI_SERVICE_ERROR`
7. Assign sequential `order` values (1, 2, 3...)
8. Generate UUID v4 for each step's `id`

**Environment Variables:**

| Variable | Local Dev | Production |
|----------|-----------|------------|
| AZURE_AI_ENDPOINT | From Azure Portal (with or without `/openai/v1/`) | Set by Bicep output |
| AZURE_AI_DEPLOYMENT | `gpt-5-mini` | Set by Bicep output |
| AZURE_AI_KEY | API key from portal | Set by Bicep output |

Local dev and production both use API key auth via the plain `openai` package. Normalize the endpoint to include `/openai/v1/` before creating the client; Bicep may output the raw resource endpoint without that suffix.

---

## Phase 2: iOS Client

### Platform Requirements

- iOS 17.0+ deployment target
- SwiftUI with async/await
- No third-party dependencies — use `URLSession` for networking, `JSONDecoder`/`JSONEncoder` for serialization

### Config

```swift
// Config.swift
enum Config {
    #if DEBUG
    static let apiBaseURL = "http://localhost:7071"
    #else
    static let apiBaseURL = "https://<your-function-app>.azurewebsites.net"
    #endif

    static let defaultUserId = "user-1"
}
```

The API URL must be configurable — never hardcode it. Use `#if DEBUG` to switch between local dev and production.

**To test against the deployed Azure API:** The simplest approach is to replace the `apiBaseURL` value directly (removing the `#if DEBUG` / `#else` / `#endif` conditional) with your deployed Function App URL. Get the URL with `azd env get-value API_URL`. You can restore the conditional later. Building with the Xcode Release scheme also works but requires additional signing configuration.

### Models

Create Swift `Codable` + `Identifiable` models that match the API `Todo`, `ActionStep`, and `{ error: { code, message } }` shapes exactly.

### API Client

```swift
class APIClient {
    static let shared = APIClient()
    private let baseURL = Config.apiBaseURL
    private let userId = Config.defaultUserId

    func getTodos() async throws -> [Todo]
    func createTodo(title: String) async throws -> Todo
    func updateTodo(id: String, title: String?, status: String?) async throws -> Todo
    func deleteTodo(id: String) async throws
    func generateSteps(todoId: String) async throws -> Todo
    func updateStep(todoId: String, stepId: String, isCompleted: Bool) async throws -> ActionStep
}
```

All methods use `URLSession.shared.data(for:)` with `async throws`. On non-2xx responses, decode the `APIError` format and throw a descriptive `LocalizedError`.

**DELETE response:** `DELETE /api/todos/:id` returns `204 No Content`, so the Swift client must not try to decode JSON for that call.

### Views

#### TodoListView (main screen — `/`)

- Navigation title: "SmartTodo"
- List of todos showing: title, status badge (color-coded: gray=pending, blue=in_progress, green=completed), step progress (e.g., "2/4 steps")
- Swipe to delete with confirmation
- "+" button in navigation bar toolbar to present `AddTodoView` as a sheet
- Tap a todo row to navigate to `TodoDetailView`
- Pull to refresh with `.refreshable`
- Empty state: "No todos yet. Tap + to add one."

#### AddTodoView (presented as sheet)

- Text field for todo title with placeholder "What do you want to accomplish?"
- "Add" button (disabled if title is empty or whitespace-only)
- "Cancel" button to dismiss
- Keyboard auto-focused on appear with `.onAppear { isFocused = true }`

#### TodoDetailView

- Todo title displayed as editable `TextField`
- Status picker: `Picker` with `pending`, `in_progress`, `completed` options
- Conditional button:
  - "✨ Generate Steps" when `stepsGenerated == false` — prominent style. **Do not use `Label` inside a `Form` button** — `Form` strips the icon. Instead use `HStack { Image(systemName: "sparkles"); Text("Generate Steps") }` with `.frame(maxWidth: .infinity)` and `.buttonStyle(.borderedProminent)`.
  - "🔄 Regenerate Steps" when `stepsGenerated == true` — same `HStack` pattern with `Image(systemName: "arrow.clockwise")` and `.tint(.blue)` for visibility
- `ProgressView` overlay during AI generation with "Generating steps..." label
- `ActionStepsView` embedded below (if steps exist)
- "Delete Todo" button at bottom (destructive style, with confirmation alert)
- The entire view should be wrapped in a `ScrollView` (or use `Form`/`List`) so that the generate button, action steps, and delete button are all reachable regardless of how many steps are generated

#### ActionStepsView

- Progress bar at top: `ProgressView(value: completedCount, total: totalCount)` with label "N of M complete"
- Ordered list of steps (sorted by `order` field) — must be scrollable so all steps are visible even when 7 are generated. Do NOT use a fixed-height container that clips at 5 items. Use a `List` or `ForEach` inside the parent `ScrollView`/`Form`.
- Each row shows:
  - Checkbox (toggle `isCompleted` via API call)
  - Step number (1, 2, 3...)
  - Title (strikethrough + gray when completed)
  - Description (expandable with disclosure indicator, or always visible if short)

---

## Phase 3: Deploy to Azure

Deploy the API to Azure Functions **Flex Consumption** plan — a serverless, scale-to-zero hosting plan with per-function scaling, virtual network support, and configurable instance memory sizes. See [Flex Consumption plan docs](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan) for details.

### Azure Resources

Prefer AVM modules for consistency. If an AVM module blocks deployment because of parameter drift, unsupported passthrough, or schema mismatch, switch that single resource to a raw `Microsoft.*` Bicep resource and document why.

Required resources: Function App on Flex Consumption, App Service Plan (`FC1`), Azure SQL Server + Database, Microsoft Foundry/Azure OpenAI with `gpt-5-mini`, Storage Account, Log Analytics, and Application Insights.

### azure.yaml

The `language` field should match the learner's chosen stack:

```yaml
name: smart-todo
metadata:
  template: smart-todo@0.0.1
services:
  api:
    project: ./src/api
    host: function
    language: ts   # Use: ts, python, csharp, java
infra:
  provider: bicep
  path: ./infra
hooks:
  postprovision:
    - shell: sh
      run: ./infra/hooks/postprovision.sh
```

Single service only — no `web` service. The iOS app runs on device, not in Azure.

### Flex Consumption Configuration

- **Instance memory size:** 2048 MB (default, suitable for most API workloads)
- **Per-function scaling:** Enabled automatically — each function (getTodos, generateSteps, etc.) scales independently
- **Always ready instances:** Optional — set to 1 for the HTTP trigger group to eliminate cold starts during demos

### Bicep Requirements

- Prefer AVM modules, but allow raw `Microsoft.*` resources when AVM blocks deployment
- System-assigned managed identity on the Function App
- AI access: default path uses `AZURE_AI_KEY` with the plain `openai` SDK. Add `Cognitive Services User` only if you later switch to managed identity for AI.
- Role assignment: `Storage Blob Data Owner` (`b7e6dc6d-f1e8-4753-8033-0f276bb0955b`) for Function App identity → Storage Account (required for Flex Consumption deployment)
- Role assignment: `Storage Blob Data Contributor` (`ba92f5b4-2d11-453d-a403-e96b0029c9fe`) for the deploying user → Storage Account (required for `azd deploy` to upload the zip package)
- Azure SQL: set the deploying user as Microsoft Entra admin, add a firewall rule allowing Azure services (`0.0.0.0`), then create a database user for the Function App identity in post-provision
- Azure SQL Database: set `maxSizeBytes: 2147483648` (2 GB) when using Basic tier (default 32 GB exceeds the limit)
- **Azure SQL Database: set `zoneRedundant: false`** — Basic tier does not support zone redundancy. AVM module may default to true, causing "ProvisioningDisabled: Provisioning of zone redundant database/pool is not supported."
- Microsoft Foundry: use `br/public:avm/ptn/ai-ml/ai-foundry` with `baseName` (max 12 chars), `aiModelDeployments` array for gpt-5-mini, `aiFoundryConfiguration.disableLocalAuth: false`, and system-assigned managed identity
- **AI model version is region-specific** — use `az cognitiveservices model list --location <region> --query "[?model.name=='gpt-5-mini']"` to find the correct version before generating Bicep. For example, `westus` requires `2025-08-07` (not `2025-02-27`).
- Outputs in SCREAMING_SNAKE_CASE: `API_URL`, `SQL_SERVER_NAME`, `SQL_DATABASE_NAME`, `FUNCTION_APP_NAME`, `AZURE_AI_ENDPOINT`, `AZURE_AI_DEPLOYMENT`, `RESOURCE_GROUP_NAME`
- `azd-service-name: 'api'` tag on the Function App
- Function App settings: `AZURE_AI_ENDPOINT`, `AZURE_AI_DEPLOYMENT`, `AZURE_AI_KEY`, `AZURE_SQL_SERVER`, `AZURE_SQL_DATABASE`. `AZURE_SQL_SERVER` must be the SQL FQDN, not just the short server name.
- **Do NOT include `FUNCTIONS_WORKER_RUNTIME` in app settings** — Flex Consumption sets this via `functionAppConfig.runtime`, and having it in app settings causes a deployment error
- **Set `siteConfig.alwaysOn` to `false`** — the AVM module defaults to `true`, which is invalid for Flex Consumption
- **Set Storage Account `networkAcls.defaultAction` to `Allow`** — the AVM module defaults to `Deny`, which blocks `azd deploy` zip uploads
- **Flex Consumption `deploymentpackage` container** — `azd deploy` uploads the zip to a blob container named `deploymentpackage`. This container may not exist after first provisioning. If `azd deploy` fails with "The specified container does not exist", create it with `az storage container create --name deploymentpackage --account-name <name> --auth-mode login` and retry.

### .NET-Specific Notes

- Use the `OpenAI` NuGet package for the `/openai/v1/` endpoint path.
- Do NOT add `Microsoft.Azure.Functions.Worker.ApplicationInsights` or `Microsoft.ApplicationInsights.WorkerService`; App Insights is wired through infrastructure.

### Post-Provision: Managed Identity SQL Access

Azure SQL requires a post-provision SQL step to add the Function App's managed identity as a database user. Generate `infra/hooks/postprovision.sh` (wired as `hooks.postprovision` in `azure.yaml`) that does this automatically after `azd provision`. It requires `sqlcmd` (go-sqlcmd / `brew install sqlcmd`) — `az sql db execute` does not exist.

The hook must, in order:
1. Fail with a clear install hint if `sqlcmd` is missing.
2. Read `SQL_SERVER_NAME`, `SQL_DATABASE_NAME`, `FUNCTION_APP_NAME`, and `RESOURCE_GROUP_NAME` via `azd env get-value`.
3. Normalize the server name both ways — `az sql` commands need the short name, `sqlcmd` needs the full FQDN:
   ```bash
   SQL_SERVER_SHORT=${SQL_SERVER%.database.windows.net}
   SQL_FQDN="${SQL_SERVER_SHORT}.database.windows.net"
   ```
4. Add a temporary firewall rule for the developer machine public IP (`curl -s https://api.ipify.org`) — Allow Azure Services alone is not enough for local `sqlcmd`. Delete this rule on exit via a shell `trap`, even when a later step fails (never leave the developer IP open).
5. Create the managed identity user and grant roles (the deploying user must be Microsoft Entra admin on the SQL server, set in Bicep):
   ```bash
   sqlcmd -S "$SQL_FQDN" -d "$SQL_DB" --authentication-method ActiveDirectoryAzCli \
     -Q "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '${FUNC_APP}') CREATE USER [${FUNC_APP}] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [${FUNC_APP}]; ALTER ROLE db_datawriter ADD MEMBER [${FUNC_APP}]; ALTER ROLE db_ddladmin ADD MEMBER [${FUNC_APP}];"
   ```
6. Apply the schema + seed file with `sqlcmd ... -i infra/hooks/postprovision-schema.sql`.
7. Print `Post-provision SQL setup complete.` on success (the README verification step checks for this line).

### Database Schema Initialization

Also generate `infra/hooks/postprovision-schema.sql` with the CREATE TABLE statements from the Database Schema section and the seed rows from the Seed Data section. Make it idempotent (`IF OBJECT_ID(...) IS NULL` around DDL; only insert seed rows when the Todos table is empty) so re-running the hook is safe. The post-provision hook runs it after the managed identity setup so the deployed API and iOS app return data immediately.

### Mobile Distribution

The iOS app is NOT deployed via azd. To test: replace the `Config.swift` `apiBaseURL` with the deployed URL (`azd env get-value API_URL`) and run from Xcode on the Simulator (⌘R). For physical devices, use the deployed URL with a development signing profile.

### Known Deployment Gotchas

1. **SQL/AI region limits:** If SQL provisioning or `gpt-5-mini` deployment fails, try `westus3`, `centralus`, or `southcentralus`; verify model version with `az cognitiveservices model list`.
2. **Post-provision SQL access:** The deploying user must be Microsoft Entra admin, and local SQL setup needs a temporary firewall rule for the developer IP.
3. **Azure SQL DNS failures:** If logs show `getaddrinfo ENOTFOUND <sql-name>`, `AZURE_SQL_SERVER` is only the short name. Use `<sql-name>.database.windows.net`.
4. **Oryx TypeScript build fails:** Check `.funcignore`; do not exclude `src/` or `tsconfig.json`.
5. **Storage deploy failures:** For 403 or missing container errors, ensure Storage `networkAcls.defaultAction` is `Allow`, the deploying user has `Storage Blob Data Contributor`, and the `deploymentpackage` container exists.
6. **Simulator preflight busy:** If Xcode reports `Application failed preflight checks` or `SBMainWorkspace Busy`, terminate/uninstall the app from that simulator, reboot the simulator, then clean build and run again.

---

## Production Hardening (Out of Scope)

Before exposing this beyond a demo, add API authentication, move `AZURE_AI_KEY` to Key Vault or managed identity, add rate limiting for `/generate-steps`, encode output if data is rendered in a browser, and replace broad storage/SQL firewall rules with private networking.
