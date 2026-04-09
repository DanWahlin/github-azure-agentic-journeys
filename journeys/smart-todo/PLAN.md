# SmartTodo: AI-Powered Task Breakdown — Spec

A todo app where vague goals become actionable plans. Type "Prepare Conference talk" and AI returns concrete steps you can check off. This document is the spec — Copilot CLI reads it to generate the implementation.

**Out of scope:** No user authentication (anonymous for now), no push notifications, no collaboration/sharing, no offline sync, no recurring todos, no image attachments.

---

## Choose Your Stack

Pick your API language. Data models, endpoints, and acceptance criteria are identical across stacks. Azure Functions Flex Consumption is the hosting plan for all languages.

| | Node.js | Python | .NET | Java |
|---|---------|--------|------|------|
| **Framework** | Azure Functions v2 model + TypeScript | Azure Functions v2 model + Python | Azure Functions (isolated worker) + C# | Azure Functions + Java |
| **Azure SQL** | `mssql` | `pyodbc` | `Microsoft.Data.SqlClient` | `JdbcTemplate` + `mssql-jdbc` |
| **AI** | `openai` | `openai` | `Azure.AI.OpenAI` | `com.openai:openai-java` |

Frontend: Swift/SwiftUI (iOS 17+). Deploy backend with **azd** + **Bicep using Azure Verified Modules (AVM)**.

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
├── infra/                      # Bicep with AVM modules
│   ├── main.bicep
│   ├── main.parameters.json
│   ├── abbreviations.json
│   └── modules/
└── azure.yaml                  # azd configuration
```

The API must follow the **repository pattern** (interfaces/contracts → implementations → factory) so functions never import the database client directly. Define repository contracts as interfaces/protocols per your language. The data layer uses Azure SQL.

---

## Phase 1: API

Build the API with Azure SQL Database. You'll need an Azure SQL instance provisioned (Phase 4 creates this, or use an existing one during development).

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

**Node.js entry point note:** Set `"main": "dist/functions/*.js"` in `package.json` — this must match where `tsc` emits the compiled function files. Since `tsconfig.json` uses `rootDir: "src"` and `outDir: "dist"`, source files under `src/functions/` compile to `dist/functions/` (the `src/` prefix is stripped). A common mistake is writing `"main": "dist/src/functions/*.js"` which causes Azure Functions Core Tools to find zero functions.

**Azure SQL notes:** Use `[order]` (bracket-quoted) since `order` is a SQL reserved word. For managed identity auth, use `azure-active-directory-default` authentication — no passwords. SSL is required by default. For local development, connect to Azure SQL using a connection string with SQL auth or your Azure AD identity — set `AZURE_SQL_SERVER`, `AZURE_SQL_DATABASE`, and optionally `AZURE_SQL_USER`/`AZURE_SQL_PASSWORD` in `local.settings.json`.

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

Response (200):

```json
[
  {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "title": "Prepare Conference talk",
    "status": "pending",
    "userId": "user-1",
    "stepsGenerated": true,
    "createdAt": "2026-04-05T10:00:00.000Z",
    "updatedAt": "2026-04-05T10:05:00.000Z",
    "steps": [
      {
        "id": "s1-uuid",
        "title": "Choose talk topic and submit abstract",
        "description": "Review the conference themes and pick a topic you're passionate about. Write a 200-word abstract.",
        "order": 1,
        "isCompleted": false,
        "createdAt": "2026-04-05T10:05:00.000Z"
      }
    ]
  }
]
```

400 if `userId` is missing.

#### `POST /api/todos`

Request body:

```json
{
  "title": "Prepare Conference talk",
  "userId": "user-1"
}
```

Response (201):

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "title": "Prepare Conference talk",
  "status": "pending",
  "userId": "user-1",
  "stepsGenerated": false,
  "createdAt": "2026-04-05T10:00:00.000Z",
  "updatedAt": "2026-04-05T10:00:00.000Z",
  "steps": []
}
```

400 if `title` is empty, missing, or exceeds 500 characters. 400 if `userId` is missing.

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
3. Call gpt-5-mini with the todo title using the system prompt from Phase 3
4. Parse the AI response as a JSON array
5. Validate each item has `title` (string, non-empty) and `description` (string, non-empty)
6. Assign sequential `order` values starting at 1
7. Generate UUID for each step's `id`
8. Insert all steps into the database
9. Set `stepsGenerated = true` on the todo
10. Return the todo with all generated steps

Response (200):

```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "title": "Prepare Conference talk",
  "status": "pending",
  "userId": "user-1",
  "stepsGenerated": true,
  "createdAt": "2026-04-05T10:00:00.000Z",
  "updatedAt": "2026-04-05T10:05:00.000Z",
  "steps": [
    {
      "id": "step-uuid-1",
      "title": "Choose talk topic and submit abstract",
      "description": "Review the Conference conference themes and pick a topic you're passionate about. Write a compelling 200-word abstract that highlights what attendees will learn.",
      "order": 1,
      "isCompleted": false,
      "createdAt": "2026-04-05T10:05:00.000Z"
    },
    {
      "id": "step-uuid-2",
      "title": "Research and outline the presentation",
      "description": "Spend 2-3 hours researching your topic. Create a detailed outline with 5-7 main sections. Include key talking points, code demos, and audience interaction moments.",
      "order": 2,
      "isCompleted": false,
      "createdAt": "2026-04-05T10:05:00.000Z"
    },
    {
      "id": "step-uuid-3",
      "title": "Build the slide deck",
      "description": "Create slides in your preferred tool. Aim for 30-40 slides for a 45-minute talk. Use visuals over bullet points. Include a title slide, agenda, and summary slide.",
      "order": 3,
      "isCompleted": false,
      "createdAt": "2026-04-05T10:05:00.000Z"
    },
    {
      "id": "step-uuid-4",
      "title": "Prepare code demos",
      "description": "Build 2-3 working code demos that illustrate your key points. Test them on conference WiFi speed. Record a backup video of each demo in case of technical issues.",
      "order": 4,
      "isCompleted": false,
      "createdAt": "2026-04-05T10:05:00.000Z"
    },
    {
      "id": "step-uuid-5",
      "title": "Rehearse the full talk",
      "description": "Practice the complete talk at least 3 times. Time yourself to stay within your slot. Practice transitions between slides and demos. Get feedback from a colleague.",
      "order": 5,
      "isCompleted": false,
      "createdAt": "2026-04-05T10:05:00.000Z"
    }
  ]
}
```

404 if todo not found. 503 if AI service is unavailable or returns unparseable output after retry.

#### `PATCH /api/todos/:id/steps/:stepId`

Request body:

```json
{
  "isCompleted": true
}
```

Response (200): Updated step object.

```json
{
  "id": "step-uuid-1",
  "todoId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "title": "Choose talk topic and submit abstract",
  "description": "Review the Conference conference themes...",
  "order": 1,
  "isCompleted": true,
  "createdAt": "2026-04-05T10:05:00.000Z"
}
```

404 if todo or step not found. 400 if `isCompleted` is not a boolean.

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

**Action Steps** (for todo-2, "Set up home office"):

| id | todoId | title | description | order | isCompleted |
|----|--------|-------|-------------|-------|-------------|
| step-2-1 | todo-2 | Choose a desk and chair | Research ergonomic options. Budget $500-800 for a standing desk and $300-500 for an ergonomic chair. Check reviews on Wirecutter. | 1 | true |
| step-2-2 | todo-2 | Set up monitor and peripherals | Get a 27" 4K monitor, wireless keyboard, and mouse. Use a monitor arm to save desk space. Budget $400-600. | 2 | true |
| step-2-3 | todo-2 | Organize cable management | Buy cable clips and a cable tray from Amazon ($20-30). Route power and data cables neatly under the desk. | 3 | false |
| step-2-4 | todo-2 | Set up lighting | Get a desk lamp with adjustable color temperature (3000K-5000K). Position it to avoid screen glare. Budget $50-100. | 4 | false |

**Action Steps** (for todo-3, "Plan weekend hiking trip"):

| id | todoId | title | description | order | isCompleted |
|----|--------|-------|-------------|-------|-------------|
| step-3-1 | todo-3 | Pick a trail | Check AllTrails for moderate 5-8 mile hikes within 1 hour drive. Consider elevation gain and current trail conditions. | 1 | true |
| step-3-2 | todo-3 | Check weather forecast | Look at the 3-day forecast for the trailhead area. Have a backup indoor plan if rain is expected. | 2 | true |
| step-3-3 | todo-3 | Pack gear and supplies | Pack: hiking boots, water (2L per person), trail snacks, sunscreen, first aid kit, phone charger, downloaded trail map. | 3 | true |

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

```swift
struct Todo: Codable, Identifiable {
    let id: String
    var title: String
    var status: String           // "pending", "in_progress", "completed"
    let userId: String
    var stepsGenerated: Bool
    let createdAt: String
    var updatedAt: String
    var steps: [ActionStep]
}

struct ActionStep: Codable, Identifiable {
    let id: String
    let todoId: String
    let title: String
    let description: String
    let order: Int
    var isCompleted: Bool
    let createdAt: String
}

struct APIError: Codable {
    let error: ErrorDetail
}

struct ErrorDetail: Codable {
    let code: String
    let message: String
}
```

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

## Phase 3: AI Features

### Task Decomposition

**Endpoint:** `POST /api/todos/:id/generate-steps`

**AI SDK:** `openai` npm package (OpenAI-compatible client for Microsoft Foundry)

**Client setup:**

```typescript
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: process.env.AZURE_AI_ENDPOINT,
  apiKey: process.env.AZURE_AI_KEY,
});
```

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
- Model: `gpt-5-mini` (fallback: `gpt-4o`)
- Temperature: `0.7`
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
| AZURE_AI_ENDPOINT | From Azure Portal (include `/openai/v1/` path) | Set by Bicep output |
| AZURE_AI_DEPLOYMENT | `gpt-5-mini` | Set by Bicep output |
| AZURE_AI_KEY | API key from portal | Set by Bicep output (or managed identity) |

Local dev and production both use API key auth via the `openai` package. The endpoint URL should include the `/openai/v1/` suffix (e.g., `https://<resource>.openai.azure.com/openai/v1/`).

---

## Phase 4: Deploy to Azure

Deploy the API to Azure Functions **Flex Consumption** plan — a serverless, scale-to-zero hosting plan with per-function scaling, virtual network support, and configurable instance memory sizes. See [Flex Consumption plan docs](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan) for details.

### Azure Skills Plugin

The Azure Skills plugin for Copilot CLI provides both MCP tools and plugin skills that should be used throughout this phase. Install it with `/plugin install azure@azure-skills` if not already installed.

**MCP Tools — use these during infrastructure generation and deployment:**

| Tool | When to Use |
|------|-------------|
| `azure_bicep_schema` | When generating Bicep — look up AVM module properties, required fields, and latest API versions for `Microsoft.Web/sites`, `Microsoft.Sql/servers`, `Microsoft.Storage/storageAccounts`, etc. |
| `azure_deploy_iac_guidance` | Before writing Bicep — get best practices for azd project structure and Flex Consumption configuration |
| `azure_deploy_plan` | Before running `azd up` — validate the deployment plan, check for missing dependencies or misconfigurations |
| `azure_deploy_architecture` | After generating Bicep — create a Mermaid architecture diagram to verify the resource topology matches the spec |
| `azure_deploy_app_logs` | After deployment — fetch Log Analytics logs to troubleshoot Function App startup errors, SQL connection failures, or AI service issues |
| `azure_deploy_pipeline` | When setting up CI/CD — get GitHub Actions guidance for automated deployments |

**Plugin Skills — use these for infrastructure generation:**

| Skill | When to Use |
|-------|-------------|
| `azure-prepare` | Generate Bicep infrastructure, azure.yaml, and deployment configuration from the resource requirements |
| `azure-validate` | Validate generated infrastructure before deployment |
| `azure-deploy` | Execute the deployment with azd |

These tools and skills help Copilot CLI produce correct Bicep on the first try and diagnose issues faster when something goes wrong. For example, running `azure_bicep_schema` for `Microsoft.Web/sites` would reveal that Flex Consumption requires `siteConfig.alwaysOn = false` and that `FUNCTIONS_WORKER_RUNTIME` must not be set in app settings.

### Azure Resources (AVM Modules)

| Resource | AVM Module | Purpose |
|----------|-----------|---------|
| Function App | `br/public:avm/res/web/site` (kind: `functionapp,linux`) | API hosting (Flex Consumption) |
| App Service Plan | `br/public:avm/res/web/serverfarm` (SKU: `FC1`, tier: `FlexConsumption`) | Flex Consumption compute |
| Azure SQL Server | `br/public:avm/res/sql/server` | Database server |
| Azure SQL Database | child resource of server | Todo + action step storage |
| Microsoft Foundry | `br/public:avm/ptn/ai-ml/ai-foundry` | gpt-5-mini model hosting |
| Monitoring | `br/public:avm/ptn/azd/monitoring` | App Insights + Log Analytics |
| Storage Account | `br/public:avm/res/storage/storage-account` | Functions runtime storage |

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
```

Single service only — no `web` service. The iOS app runs on device, not in Azure.

### Flex Consumption Configuration

- **Instance memory size:** 2048 MB (default, suitable for most API workloads)
- **Per-function scaling:** Enabled automatically — each function (getTodos, generateSteps, etc.) scales independently
- **Always ready instances:** Optional — set to 1 for the HTTP trigger group to eliminate cold starts during demos

### Bicep Requirements

- Use AVM modules for ALL resources — no raw resource definitions
- System-assigned managed identity on the Function App
- Role assignment: `Cognitive Services User` for Function App identity → AI Services
- Role assignment: `Storage Blob Data Owner` for Function App identity → Storage Account (required for Flex Consumption deployment)
- Role assignment: `Storage Blob Data Contributor` for the deploying user → Storage Account (required for `azd deploy` to upload the zip package)
- Azure SQL: set deploying user as Azure AD admin, firewall rule allowing Azure services (`0.0.0.0`)
- Azure SQL Database: set `maxSizeBytes: 2147483648` (2 GB) when using Basic tier (default 32 GB exceeds the limit)
- AI Services: `disableLocalAuth: false` for development, system-assigned managed identity
- Outputs in SCREAMING_SNAKE_CASE: `API_URL`, `SQL_SERVER_NAME`, `SQL_DATABASE_NAME`, `FUNCTION_APP_NAME`, `AZURE_AI_ENDPOINT`, `AZURE_AI_DEPLOYMENT`, `RESOURCE_GROUP_NAME`
- `azd-service-name: 'api'` tag on the Function App
- Function App settings: `AZURE_AI_ENDPOINT`, `AZURE_AI_DEPLOYMENT`, `AZURE_AI_KEY`, `AZURE_SQL_SERVER`, `AZURE_SQL_DATABASE`
- **Do NOT include `FUNCTIONS_WORKER_RUNTIME` in app settings** — Flex Consumption sets this via `functionAppConfig.runtime`, and having it in app settings causes a deployment error
- **Set `siteConfig.alwaysOn` to `false`** — the AVM module defaults to `true`, which is invalid for Flex Consumption
- **Set Storage Account `networkAcls.defaultAction` to `Allow`** — the AVM module defaults to `Deny`, which blocks `azd deploy` zip uploads

### .NET-Specific Notes

- Use `Azure.AI.OpenAI` NuGet package (not the base `OpenAI` package) — the base package can't construct Azure-specific API URLs. Use `AzureOpenAIClient` from `Azure.AI.OpenAI` in the DI registration.
- Do NOT add `Microsoft.Azure.Functions.Worker.ApplicationInsights` or `Microsoft.ApplicationInsights.WorkerService` — these cause version conflicts with the Functions runtime on Flex Consumption. App Insights is wired through `configs.applicationInsightResourceId` in the Bicep template instead.

### Post-Provision: Managed Identity SQL Access

Azure SQL requires a SQL command to add the Function App's managed identity as a user. This can't be done in Bicep — it requires a post-provision script or manual step.

Create `infra/hooks/postprovision.sh`:

> **Note:** `az sql db execute` does not exist. Use `sqlcmd` (install via `brew install sqlcmd`) or a Node.js/Python script with the `mssql`/`pyodbc` package to run SQL commands against Azure SQL.

```bash
#!/bin/bash
SQL_SERVER=$(azd env get-value SQL_SERVER_NAME)
SQL_DB=$(azd env get-value SQL_DATABASE_NAME)
FUNC_APP=$(azd env get-value FUNCTION_APP_NAME)

# Get an access token for Azure SQL
ACCESS_TOKEN=$(az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv)

# Create the managed identity user and grant roles (requires sqlcmd: brew install sqlcmd)
sqlcmd -S "${SQL_SERVER}.database.windows.net" -d "$SQL_DB" --authentication-method=ActiveDirectoryAccessToken --access-token "$ACCESS_TOKEN" \
  -Q "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '${FUNC_APP}') BEGIN CREATE USER [${FUNC_APP}] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [${FUNC_APP}]; ALTER ROLE db_datawriter ADD MEMBER [${FUNC_APP}]; END" \
  || echo "⚠️ Managed identity user creation skipped (may require manual setup)"
```

Wire it in azure.yaml:

```yaml
hooks:
  postprovision:
    - shell: sh
      run: ./infra/hooks/postprovision.sh
```

### Database Schema Initialization

Create `infra/hooks/postprovision-schema.sql` with the CREATE TABLE statements from the Data Models section. Run it as part of the post-provision hook after the managed identity setup.

### Mobile Distribution

The iOS app is NOT deployed via azd. For testing:

1. **Against deployed API**: Replace the `Config.swift` contents with the deployed URL directly (remove the `#if DEBUG` conditional). Get the URL with `azd env get-value API_URL`. Run from Xcode on the Simulator with ⌘R.
2. **Against local API**: Restore the `#if DEBUG` conditional in `Config.swift` with `http://localhost:7071` for the debug build. Run the Functions dev server locally first.
3. **Physical device**: Use the deployed URL in `Config.swift` (no conditional), build with a development signing profile.
4. **TestFlight** (optional): Archive and upload via Xcode → App Store Connect for beta testing with others.

### Known Deployment Gotchas

1. **Soft-deleted Cognitive Services** — if redeploying after `azd down`, the AI Services resource is soft-deleted for 48 hours and blocks re-creation. Purge it first: `az cognitiveservices account list-deleted` then `az cognitiveservices account purge`
2. **Azure SQL AD admin** — the deploying user must be set as Azure AD admin on the SQL server for the post-provision managed identity script to work. The Bicep template should set this.
3. **Functions cold start** — first request after idle takes 5-10 seconds on consumption plan. The iOS app should show loading state during API calls.
4. **AI model deployment lag** — model deployment may take 1-2 minutes during provisioning. The `generate-steps` endpoint returns 503 until it's ready.
5. **Provider registration** — run these once per subscription before first deploy:
6. **SQL provisioning restricted** — some subscriptions have SQL provisioning disabled in certain regions (e.g., `eastus`, `eastus2`). Try `westus3`, `centralus`, or `southcentralus` if you get `ProvisioningDisabled`.
7. **AI model region availability** — `gpt-5-mini` is not available in all regions. Check availability with `az cognitiveservices model list --location <region>`. Use `gpt-4o-mini` as a fallback.
8. **Storage 403 on deploy** — if `azd deploy` fails with a 403 storage error, ensure the Storage Account `networkAcls.defaultAction` is `Allow` and the deploying user has `Storage Blob Data Contributor` role.

```bash
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.OperationalInsights
```

---

## Security Considerations

This journey builds a working app without authentication to keep the focus on Azure Functions, AI integration, and iOS development. Before exposing this to real users, consider the following hardening steps:

### API Authentication

All functions use `AuthorizationLevel.Anonymous` — anyone with the URL can call them. For production:
- Use `AuthorizationLevel.Function` and distribute function keys to the iOS app, or
- Add Azure AD / Entra ID authentication via Easy Auth on the Function App, or
- Implement JWT token validation in the function code with an identity provider

### CORS (Cross-Origin Resource Sharing)

The Function App has no CORS policy configured. If you add a web frontend, restrict `allowedOrigins` to your domain. For the iOS app this isn't a browser concern, but it's good practice to lock down anyway via the Function App's CORS settings in Bicep or the Azure portal.

### AI API Key in Key Vault

`AZURE_AI_KEY` is stored as a plaintext app setting. Move it to Azure Key Vault and use a Key Vault reference in the Function App settings:

```
@Microsoft.KeyVault(SecretUri=https://<vault-name>.vault.azure.net/secrets/AZURE-AI-KEY)
```

Better yet, use managed identity for AI Services (same pattern as Azure SQL) — grant the Function App's identity the `Cognitive Services User` role and use `DefaultAzureCredential` in code instead of an API key.

### Rate Limiting / Cost Protection

The `/generate-steps` endpoint calls a paid AI model with no throttling. A bad actor (or a bug) could generate thousands of requests and run up costs. Consider:
- Adding a rate limit per `userId` (e.g., 10 generations per hour)
- Setting a spending cap on the AI Services resource in the Azure portal
- Adding Azure API Management in front of the Function App for request throttling

### Input Validation

The API validates title length (1-500 chars) and userId presence, but doesn't sanitize for HTML/script content. If the data is ever rendered in a web browser (not just the iOS app), add output encoding to prevent XSS. The current SQL parameterized queries already prevent SQL injection.

### Network Security

For production, consider tightening the network:
- **Storage Account**: Change `networkAcls.defaultAction` back to `Deny` after deployment, adding VNet rules for the Function App
- **Azure SQL**: Remove the `AllowAllWindowsAzureIps` firewall rule and use VNet integration with private endpoints instead
- **Function App**: Enable VNet integration and restrict inbound traffic to known IP ranges or API Management
