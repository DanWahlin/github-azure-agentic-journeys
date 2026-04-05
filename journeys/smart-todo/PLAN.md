# SmartTodo: AI-Powered Task Breakdown — Spec

A todo app where vague goals become actionable plans. Type "Prepare Conference talk" and AI returns concrete steps you can check off. This document is the spec — Copilot CLI reads it to generate the implementation.

**Out of scope:** No user authentication (anonymous for now), no push notifications, no collaboration/sharing, no offline sync, no recurring todos, no image attachments.

---

## Choose Your Stack

| | Node.js |
|---|---------|
| **Framework** | Azure Functions v2 programming model + TypeScript |
| **Database (local)** | `better-sqlite3` |
| **Database (Azure)** | Azure SQL Database |
| **AI** | `@azure/ai-inference` with gpt-5-mini on Microsoft Foundry |

Frontend: Swift/SwiftUI (iOS 17+). Deploy backend with **azd** + **Bicep using Azure Verified Modules (AVM)**. See [`data-access-abstraction` skill](../../.github/skills/data-access-abstraction/SKILL.md) for repository pattern examples.

The iOS app is NOT deployed by azd — only the Azure backend is. The app points at the deployed API URL via a `Config.swift` file.

## Project Structure

```
smart-todo/
├── src/
│   ├── api/                    # Azure Functions (Node.js + TypeScript)
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── host.json
│   │   ├── local.settings.json
│   │   └── src/
│   │       ├── functions/      # HTTP-triggered functions
│   │       │   ├── getTodos.ts
│   │       │   ├── createTodo.ts
│   │       │   ├── updateTodo.ts
│   │       │   ├── deleteTodo.ts
│   │       │   ├── generateSteps.ts
│   │       │   └── updateStep.ts
│   │       ├── data/
│   │       │   ├── interfaces.ts
│   │       │   ├── sql.ts          # Azure SQL implementation
│   │       │   ├── sqlite.ts       # SQLite implementation (local dev)
│   │       │   ├── store.ts        # Factory
│   │       │   └── seed.ts
│   │       ├── ai/
│   │       │   └── taskBreaker.ts
│   │       └── models/
│   │           └── index.ts
│   └── ios/
│       └── SmartTodo/
│           ├── SmartTodo.xcodeproj
│           ├── SmartTodoApp.swift
│           ├── Config.swift
│           ├── Models/
│           │   ├── Todo.swift
│           │   └── ActionStep.swift
│           ├── Services/
│           │   └── APIClient.swift
│           └── Views/
│               ├── TodoListView.swift
│               ├── TodoDetailView.swift
│               ├── ActionStepsView.swift
│               └── AddTodoView.swift
├── infra/                      # Bicep with AVM modules (Phase 3)
│   ├── main.bicep
│   ├── main.parameters.json
│   ├── abbreviations.json
│   └── modules/
└── azure.yaml                  # azd configuration (Phase 3)
```

The API must follow the **repository pattern** (interfaces → implementations → factory) so the data layer can swap between SQLite (local) and Azure SQL (Azure) via `DATA_PROVIDER` env var.

---

## Phase 1: API

Build the API with a local SQLite database. No Azure services needed yet.

### Data Access Layer

Repository contracts — define as TypeScript interfaces:

```typescript
interface ITodoRepository {
  getAll(userId: string): Promise<Todo[]>;
  getById(id: string): Promise<Todo | null>;
  create(input: CreateTodoInput): Promise<Todo>;
  update(id: string, updates: UpdateTodoInput): Promise<Todo>;
  delete(id: string): Promise<void>;
}

interface IActionStepRepository {
  getByTodoId(todoId: string): Promise<ActionStep[]>;
  create(step: CreateActionStepInput): Promise<ActionStep>;
  update(id: string, updates: UpdateActionStepInput): Promise<ActionStep>;
  deleteByTodoId(todoId: string): Promise<void>;
}

interface DataStore {
  todos: ITodoRepository;
  actionSteps: IActionStepRepository;
  initialize(): Promise<void>;
}
```

Factory reads `DATA_PROVIDER` env var (default `sqlite`), returns the matching implementation. Functions never import database clients directly.

**SQLite notes:** Use `[order]` (bracket-quoted) since `order` is a SQL reserved word. Set `journal_mode=WAL` and `foreign_keys=ON`. DB file: `src/api/smarttodo.db` (add to `.gitignore`).

**Azure SQL notes:** Use `mssql` package with `@azure/identity` for managed identity auth. Connection uses `authentication: { type: 'azure-active-directory-default' }` — no passwords. SSL is required by default.

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

For SQLite, adapt the syntax: use `TEXT` instead of `NVARCHAR`, `INTEGER` instead of `BIT`, `CURRENT_TIMESTAMP` instead of `GETUTCDATE()`.

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
  - "✨ Generate Steps" when `stepsGenerated == false` — prominent style
  - "🔄 Regenerate Steps" when `stepsGenerated == true` — secondary style
- `ProgressView` overlay during AI generation with "Generating steps..." label
- `ActionStepsView` embedded below (if steps exist)
- "Delete Todo" button at bottom (destructive style, with confirmation alert)

#### ActionStepsView

- Progress bar at top: `ProgressView(value: completedCount, total: totalCount)` with label "N of M complete"
- Ordered list of steps (sorted by `order` field)
- Each row shows:
  - Checkbox (toggle `isCompleted` via API call)
  - Step number (1, 2, 3...)
  - Title (strikethrough + gray when completed)
  - Description (expandable with disclosure indicator, or always visible if short)

---

## Phase 3: AI Features

### Task Decomposition

**Endpoint:** `POST /api/todos/:id/generate-steps`

**AI SDK:** `@azure/ai-inference` with `ModelClient`

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
| AZURE_AI_ENDPOINT | From Azure Portal | Set by Bicep output |
| AZURE_AI_DEPLOYMENT | `gpt-5-mini` | Set by Bicep output |
| AZURE_AI_KEY | API key from portal | Not needed (managed identity) |

Local dev uses API key auth (`AzureKeyCredential`). Production uses `DefaultAzureCredential` (managed identity).

---

## Phase 4: Deploy to Azure

### Azure Resources (AVM Modules)

| Resource | AVM Module | Purpose |
|----------|-----------|---------|
| Function App | `br/public:avm/res/web/site` (kind: `functionapp,linux`) | API hosting |
| App Service Plan | `br/public:avm/res/web/serverfarm` (Flex Consumption) | Functions compute |
| Azure SQL Server | `br/public:avm/res/sql/server` | Database server |
| Azure SQL Database | child resource of server | Todo + action step storage |
| AI Foundry | `br/public:avm/ptn/ai-ml/ai-foundry` | gpt-5-mini model hosting |
| Monitoring | `br/public:avm/ptn/azd/monitoring` | App Insights + Log Analytics |
| Storage Account | `br/public:avm/res/storage/storage-account` | Functions runtime storage |

### azure.yaml

```yaml
name: smart-todo
metadata:
  template: smart-todo@0.0.1
services:
  api:
    project: ./src/api
    host: function
    language: ts
infra:
  provider: bicep
  path: ./infra
```

Single service only — no `web` service. The iOS app runs on device, not in Azure.

### Bicep Requirements

- Use AVM modules for ALL resources — no raw resource definitions
- System-assigned managed identity on the Function App
- Role assignment: `Cognitive Services User` for Function App identity → AI Services
- Azure SQL: set deploying user as Azure AD admin, firewall rule allowing Azure services (`0.0.0.0`)
- AI Services: `disableLocalAuth: false` for development, system-assigned managed identity
- Outputs in SCREAMING_SNAKE_CASE: `API_URL`, `SQL_SERVER_NAME`, `SQL_DATABASE_NAME`, `FUNCTION_APP_NAME`, `AZURE_AI_ENDPOINT`, `AZURE_AI_DEPLOYMENT`, `RESOURCE_GROUP_NAME`
- `azd-service-name: 'api'` tag on the Function App
- Function App settings: `DATA_PROVIDER=sql`, `AZURE_AI_ENDPOINT`, `AZURE_AI_DEPLOYMENT`, `AZURE_SQL_SERVER`, `AZURE_SQL_DATABASE`

### Post-Provision: Managed Identity SQL Access

Azure SQL requires a SQL command to add the Function App's managed identity as a user. This can't be done in Bicep — it requires a post-provision script or manual step.

Create `infra/hooks/postprovision.sh`:

```bash
#!/bin/bash
SQL_SERVER=$(azd env get-value SQL_SERVER_NAME)
SQL_DB=$(azd env get-value SQL_DATABASE_NAME)
FUNC_APP=$(azd env get-value FUNCTION_APP_NAME)

# Create the managed identity user and grant roles
# The deploying user must be Azure AD admin on the SQL server
az sql db execute --server "$SQL_SERVER" --database "$SQL_DB" \
  --query "IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$FUNC_APP') BEGIN CREATE USER [$FUNC_APP] FROM EXTERNAL PROVIDER; ALTER ROLE db_datareader ADD MEMBER [$FUNC_APP]; ALTER ROLE db_datawriter ADD MEMBER [$FUNC_APP]; END"
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

1. **Simulator**: Run from Xcode with `DEBUG` scheme (uses `http://localhost:7071`)
2. **Physical device**: Update `Config.swift` with the deployed `API_URL` from `azd env get-value API_URL`, build with a development signing profile
3. **TestFlight** (optional): Archive and upload via Xcode → App Store Connect for beta testing with others

### Known Deployment Gotchas

1. **Soft-deleted Cognitive Services** — if redeploying after `azd down`, the AI Services resource is soft-deleted for 48 hours and blocks re-creation. Purge it first: `az cognitiveservices account list-deleted` then `az cognitiveservices account purge`
2. **Azure SQL AD admin** — the deploying user must be set as Azure AD admin on the SQL server for the post-provision managed identity script to work. The Bicep template should set this.
3. **Functions cold start** — first request after idle takes 5-10 seconds on consumption plan. The iOS app should show loading state during API calls.
4. **AI model deployment lag** — gpt-5-mini deployment may take 1-2 minutes during provisioning. The `generate-steps` endpoint returns 503 until it's ready.
5. **Provider registration** — run these once per subscription before first deploy:

```bash
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.OperationalInsights
```
