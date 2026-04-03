# AIMarket: AI-Powered Marketplace — Spec

Marketplace API + React storefront with AI-powered semantic search and a shopping assistant. This document is the spec — Copilot reads it to generate the implementation.

**Out of scope:** No auth, no payments, no image upload, no email, no admin dashboard, no rate limiting, no WebSockets.

---

## Choose Your Stack

Pick your API language. Data models, endpoints, and acceptance criteria are identical across stacks.

| | Node.js | Python | .NET | Java |
|---|---------|--------|------|------|
| **Framework** | Express + TypeScript | FastAPI | ASP.NET Core Minimal APIs | Spring Boot |
| **SQLite** | `better-sqlite3` | `sqlite3` (stdlib) | `Microsoft.Data.Sqlite` | `JdbcTemplate` + SQLite |

Frontend is always React 18 + Tailwind CSS. AI via **gpt-5-mini on Microsoft Foundry** (fallback to gpt-4o if there's no quota available for gpt-5-mini). Deploy with **azd** + **Bicep using Azure Verified Modules (AVM)**. See [`data-access-abstraction` skill](../../.github/skills/data-access-abstraction/SKILL.md) for repository pattern examples in all four languages.

## Project Structure

```
aimarket/
├── api/          # Your chosen language
├── client/       # React frontend (Vite + Tailwind)
├── infra/        # Bicep with AVM modules (Phase 4)
└── azure.yaml    # azd configuration (Phase 4)
```

The API must follow the **repository pattern** (interfaces → implementations → factory) so the data layer can swap between SQLite (local) and Cosmos DB/PostgreSQL (Azure) via `DATA_PROVIDER` env var.

---

## Phase 1: API

Build the API with a local SQLite database. No Azure services needed yet.

### Data Access Layer

Repository contracts — define as interfaces/protocols per your language:

```
ProductRepository:
  getAll(page, pageSize, category?, minPrice?, maxPrice?, status?) → { data: Product[], totalCount }
  getById(id) → Product | null
  create(input) → Product
  update(id, fields) → Product | null
  search(query, filters?) → Product[]

OrderRepository:
  create(userId, items, shippingAddress) → Order
  getById(id) → Order | null
  getByUserId(userId, page, pageSize) → { data: Order[], totalCount }

UserRepository:
  create(email, name, role) → User
  getById(id) → User | null
  getByEmail(email) → User | null
```

Factory reads `DATA_PROVIDER` env var (default `sqlite`), returns the matching implementation. Routes never import database clients directly.

**SQLite notes:** Store arrays/objects as JSON strings, parse on read. Use `order_items` junction table for order line items. Set `journal_mode=WAL` and `foreign_keys=ON`. DB file: `api/aimarket.db` (add to `.gitignore`).

**API entry point:** Enable CORS, parse JSON, expose `GET /api/health` → `{status:"ok"}`, mount routes at `/api/{products,orders,users,chat}`, global error handler last.

### Data Models

#### Product

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| id | string | auto | UUID v4, generated on create |
| name | string | yes | 1–200 characters |
| description | string | yes | 1–2000 characters |
| shortDescription | string | yes | 1–200 characters |
| price | number | yes | > 0, two decimal places |
| category | string | yes | Must be one of: `Electronics`, `Clothing`, `Home`, `Sports`, `Books`, `Toys` |
| tags | string[] | no | Defaults to `[]` |
| inventory | number | yes | >= 0, integer |
| rating | number | no | 1.0–5.0, default `0` |
| reviewCount | number | no | >= 0, default `0` |
| imageUrl | string | no | Valid URL or empty string |
| sellerId | string | yes | Must reference an existing user with role `seller` |
| status | string | no | `draft`, `active`, or `archived`. Default `active` |
| createdAt | string | auto | ISO 8601, set on create |
| updatedAt | string | auto | ISO 8601, set on create and update |

#### Order

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| id | string | auto | UUID v4 |
| userId | string | yes | Must reference an existing user |
| items | OrderItem[] | yes | At least 1 item. Each: `{ productId: string, quantity: number, priceAtPurchase: number }` |
| total | number | auto | Sum of (quantity × priceAtPurchase) for all items. Calculated server-side. |
| status | string | auto | `pending` on create. Valid transitions: pending → confirmed → shipped → delivered; pending → cancelled |
| shippingAddress | object | yes | `{ street: string, city: string, state: string, zip: string, country: string }` — all fields required |
| createdAt | string | auto | ISO 8601 |

**Order creation behavior:** When an order is placed, the API must:
1. Validate all `productId` references exist and have status `active`
2. Validate each product has sufficient `inventory` for the requested `quantity`
3. Decrement `inventory` for each product by the ordered `quantity`
4. Set `priceAtPurchase` from the product's current `price` (not from the request)
5. Calculate `total` server-side

#### User

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| id | string | auto | UUID v4 |
| email | string | yes | Valid email format, unique across all users |
| name | string | yes | 1–100 characters |
| role | string | yes | `buyer` or `seller` |
| createdAt | string | auto | ISO 8601 |

### API Endpoints

Base URL: `http://localhost:3000/api`

#### `GET /products`

List products with pagination and optional filters.

**Query parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| page | number | 1 | Page number (1-based) |
| pageSize | number | 20 | Items per page (max 100) |
| category | string | — | Filter by exact category |
| minPrice | number | — | Filter by minimum price |
| maxPrice | number | — | Filter by maximum price |
| status | string | `active` | Filter by status. Only return `active` products by default. |

**Response (200):**

```json
{
  "data": [
    {
      "id": "a1b2c3d4-...",
      "name": "UltraBook Pro 15",
      "shortDescription": "Lightweight 15-inch ultrabook with all-day battery",
      "price": 1299.99,
      "category": "Electronics",
      "tags": ["laptop", "ultrabook", "portable"],
      "inventory": 25,
      "rating": 4.7,
      "reviewCount": 142,
      "imageUrl": "https://images.unsplash.com/photo-1589561084283-930aa7b1ce50?w=400&h=300&fit=crop",
      "status": "active"
  "pageSize": 20,
  "totalCount": 10,
  "totalPages": 1
}
```

Note: List responses return a subset of fields (no `description`, `sellerId`, `createdAt`, `updatedAt`). Full details are returned by `GET /products/:id`.

#### `GET /products/:id`

**Response (200):** Full product object with all fields.

**Response (404):**

```json
{
  "error": { "code": "NOT_FOUND", "message": "Product not found" }
}
```

#### `POST /products`

**Request body:**

```json
{
  "name": "Mechanical Keyboard",
  "description": "Cherry MX Brown switches with RGB backlighting and USB-C connection.",
  "shortDescription": "Mechanical keyboard with Cherry MX switches",
  "price": 149.99,
  "category": "Electronics",
  "tags": ["keyboard", "mechanical", "rgb"],
  "inventory": 50,
  "imageUrl": "https://images.unsplash.com/photo-1589561084283-930aa7b1ce50?w=400&h=300&fit=crop",
  "sellerId": "seller-user-id"
}
```

**Response (201):** The created product with `id`, `createdAt`, `updatedAt`, and defaults applied.

**Response (400):** Validation error with specific field failures.

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Validation failed",
    "details": [
      { "field": "price", "message": "Price must be greater than 0" },
      { "field": "category", "message": "Category must be one of: Electronics, Clothing, Home, Sports, Books, Toys" }
    ]
  }
}
```

#### `PUT /products/:id`

Partial update. Only include fields to change. Returns the updated product (200) or 404.

#### `POST /orders`

**Request body:**

```json
{
  "userId": "buyer-user-id",
  "items": [
    { "productId": "product-1-id", "quantity": 2 },
    { "productId": "product-2-id", "quantity": 1 }
  ],
  "shippingAddress": {
    "street": "123 Main St",
    "city": "Seattle",
    "state": "WA",
    "zip": "98101",
    "country": "US"
  }
}
```

**Response (201):**

```json
{
  "id": "order-id",
  "userId": "buyer-user-id",
  "items": [
    { "productId": "product-1-id", "quantity": 2, "priceAtPurchase": 1299.99 },
    { "productId": "product-2-id", "quantity": 1, "priceAtPurchase": 249.99 }
  ],
  "total": 2849.97,
  "status": "pending",
  "shippingAddress": { "street": "123 Main St", "city": "Seattle", "state": "WA", "zip": "98101", "country": "US" },
  "createdAt": "2026-04-02T10:30:00.000Z"
}
```

**Error cases:**
- 400 if `items` is empty
- 400 if any `productId` doesn't exist or isn't `active`
- 400 if any product has insufficient `inventory`
- 400 if `shippingAddress` is missing required fields

#### `GET /orders/:id`

Full order object (200) or 404.

#### `GET /orders?userId=xxx`

Paginated list of orders for a user. Same pagination format as products.

#### `POST /users/register`

**Request body:**

```json
{
  "email": "alex@example.com",
  "name": "Alex Johnson",
  "role": "buyer"
}
```

**Response (201):** The created user with `id` and `createdAt`.

**Response (400):** If email already exists: `{ "error": { "code": "DUPLICATE_EMAIL", "message": "A user with this email already exists" } }`

#### `GET /users/:id`

Full user object (200) or 404.

### Error Format

All errors: `{ "error": { "code": "ERROR_CODE", "message": "...", "details": [] } }`. `details` only on validation errors.

| Status | Code | When |
|--------|------|------|
| 400 | `VALIDATION_ERROR` | Missing or invalid fields |
| 400 | `DUPLICATE_EMAIL` | Email already registered |
| 400 | `INSUFFICIENT_INVENTORY` | Not enough stock |
| 404 | `NOT_FOUND` | Resource doesn't exist |
| 500 | `INTERNAL_ERROR` | Unexpected error |

### Seed Data

Loaded into the SQLite database on startup. Persists locally in the `aimarket.db` file.

**Users:**

| id | email | name | role |
|----|-------|------|------|
| `user-buyer-1` | `alex@example.com` | Alex Johnson | buyer |
| `user-seller-1` | `jordan@example.com` | Jordan Lee | seller |

**Products** (all `sellerId: "user-seller-1"`, all `status: "active"`):

| id | name | category | price | inventory | rating | tags |
|----|------|----------|-------|-----------|--------|------|
| `prod-1` | UltraBook Pro 15 | Electronics | 1299.99 | 25 | 4.7 | laptop, ultrabook, portable |
| `prod-2` | Wireless Noise-Canceling Headphones | Electronics | 249.99 | 100 | 4.5 | headphones, wireless, noise-canceling |
| `prod-3` | Trail Runner X200 | Sports | 129.99 | 60 | 4.3 | running, shoes, trail |
| `prod-4` | Organic Cotton Crew Neck | Clothing | 34.99 | 200 | 4.1 | t-shirt, organic, cotton |
| `prod-5` | Smart Home Hub | Electronics | 89.99 | 75 | 4.4 | smart-home, hub, voice-control |
| `prod-6` | Ceramic Pour-Over Set | Home | 45.99 | 40 | 4.8 | coffee, pour-over, ceramic |
| `prod-7` | Pro Django | Books | 39.99 | 150 | 4.6 | programming, python, django |
| `prod-8` | Yoga Mat Premium | Sports | 59.99 | 80 | 4.2 | yoga, mat, exercise |
| `prod-9` | Winter Puffer Jacket | Clothing | 189.99 | 35 | 4.5 | jacket, winter, puffer |
| `prod-10` | Building Block Castle Set | Toys | 49.99 | 90 | 4.9 | building, blocks, kids |

**Product descriptions:**

| id | description | shortDescription |
|----|-------------|------------------|
| `prod-1` | The UltraBook Pro 15 is a lightweight 15-inch laptop computer built for professionals on the move. Featuring a full-day battery, a vivid IPS display, and a backlit keyboard, this portable computer handles everything from code to presentations without breaking a sweat. | Lightweight 15-inch ultrabook with all-day battery |
| `prod-2` | Block out distractions with industry-leading active noise cancellation. These wireless headphones deliver rich, balanced sound over Bluetooth 5.2 with 30 hours of battery life. Foldable design fits easily in a backpack. | Wireless over-ear headphones with active noise cancellation |
| `prod-3` | Designed for rugged terrain, the Trail Runner X200 features aggressive lugs for grip, a rock plate for protection, and a breathable mesh upper. Ideal for trail runs, hiking, and obstacle courses. | Rugged trail running shoes with aggressive grip |
| `prod-4` | Made from 100% GOTS-certified organic cotton, this crew neck tee is soft, breathable, and built to last. Pre-shrunk fabric and reinforced stitching mean it holds its shape wash after wash. | Soft organic cotton t-shirt, pre-shrunk and durable |
| `prod-5` | Control your lights, thermostat, and locks with voice commands or the companion app. The Smart Home Hub supports Zigbee, Z-Wave, and Wi-Fi devices and works with Alexa and Google Assistant out of the box. | Voice-controlled smart home hub with multi-protocol support |
| `prod-6` | Hand-thrown ceramic dripper and server set for pour-over coffee enthusiasts. The ribbed interior promotes even extraction while the double-wall server keeps your brew warm. Dishwasher safe. | Handcrafted ceramic pour-over coffee dripper and server |
| `prod-7` | Master Django from models to deployment. Covers the ORM, class-based views, REST APIs with Django REST Framework, authentication, testing, and production deployment with Docker and CI/CD pipelines. | Complete Django guide from models to production deployment |
| `prod-8` | Extra-thick 6mm natural rubber mat with a non-slip textured surface on both sides. Alignment lines help with pose positioning. Includes a carrying strap. Free from PVC, latex, and heavy metals. | Extra-thick 6mm natural rubber yoga mat with alignment lines |
| `prod-9` | Stay warm in sub-zero temperatures with this 700-fill-power down puffer jacket. Water-resistant shell, elastic cuffs, and a detachable hood keep the cold out. Packs into its own pocket for travel. | 700-fill down puffer jacket, water-resistant and packable |
| `prod-10` | Build a medieval castle with 850 interlocking pieces including turrets, a drawbridge, and 6 knight minifigures. Compatible with all major building block brands. Recommended for ages 6 and up. | 850-piece castle building set with 6 knight minifigures |

Use Unsplash image URLs for `imageUrl`. Format: `https://images.unsplash.com/photo-{id}?w=400&h=300&fit=crop`. Choose photos that match each product (laptop, headphones, shoes, etc.).

**Orders:**

| id | userId | items | total | status |
|----|--------|-------|-------|--------|
| `order-1` | `user-buyer-1` | prod-1 × 1 ($1299.99), prod-6 × 2 ($45.99 each) | 1391.97 | confirmed |
| `order-2` | `user-buyer-1` | prod-4 × 3 ($34.99 each) | 104.97 | pending |

**Note:** Seed orders are pre-loaded historical data. They do **not** decrement product inventory. Inventory values in the products table represent current stock.
---

## Phase 2: Frontend

Build the React storefront. The API must be running for the frontend to work.

### Pages

#### Product Grid (Home Page — `/`)

- Displays all active products in a responsive card grid (3 columns on desktop, 2 on tablet, 1 on mobile)
- Each card shows: image, name, short description, price, rating (stars), and category badge
- Search bar at the top of the page (plain text search that filters by name and tags client-side)
- Category filter buttons below the search bar (All, Electronics, Clothing, Home, Sports, Books, Toys)
- Clicking a product card navigates to the product detail page

#### Product Detail (`/products/:id`)

- Full product view: large image, name, full description, price, rating, review count, category, tags, inventory status
- "Add to Cart" button with quantity selector (1-10, default 1)
- If inventory is 0, show "Out of Stock" and disable the button
- "Back to Products" link

#### Cart (`/cart`)

- List of cart items with: product name, image (small), unit price, quantity (editable), line total
- "Remove" button per item
- Cart summary: subtotal, item count
- "Place Order" button that calls `POST /api/orders` with a hardcoded `userId` of `user-buyer-1` and a hardcoded shipping address
- After successful order, show a confirmation message with the order ID and clear the cart
- Empty cart state: "Your cart is empty" with a link to browse products

### Components

#### SearchBar

- Text input with placeholder "Search products..."
- Filters the product grid as the user types (debounced, 300ms)
- After Phase 3: add a toggle for "AI Search" that uses the semantic search endpoint instead of client-side filtering

#### ChatWidget

- Floating button in the bottom-right corner (collapsed by default)
- Click to expand a chat panel (400px wide, 500px tall)
- **In Phase 2:** Show a placeholder message: "Shopping assistant coming soon! (Phase 3)". Do not wire up the API.
- **In Phase 3:** Wire up to `POST /api/chat`:
  - Message list showing conversation history (user messages right-aligned, assistant messages left-aligned)
  - Text input at the bottom with a send button
  - Sends full message history to `POST /api/chat` on each message
  - Shows a typing indicator while waiting for a response
  - Initial assistant message on open: "Hi! I'm the AIMarket assistant. I can help you find products, compare options, or answer questions about our catalog. What are you looking for?"

#### CartIcon

- Shopping cart icon in the top-right navigation
- Badge showing total item count
- Clicking navigates to `/cart`

### State Management

- Cart state stored in React context (not persisted to a backend)
- Cart structure: `Map<productId, { product: Product, quantity: number }>`
- Cart survives page navigation but resets on browser refresh

### API Client

All API calls go through a single `api.ts` module:

```typescript
const API_BASE = import.meta.env.VITE_API_URL || '/api';

export async function getProducts(params?: { category?: string; page?: number }): Promise<PaginatedResponse<Product>>
export async function getProduct(id: string): Promise<Product>
export async function searchProducts(query: string): Promise<Product[]>
export async function placeOrder(order: CreateOrderRequest): Promise<Order>
export async function sendChatMessage(messages: ChatMessage[]): Promise<string>
```

**URL convention:** Endpoint paths in the client (e.g., `/products`, `/orders`) do NOT include the `/api` prefix — that's part of `API_BASE`. In development, the Vite proxy maps `/api` → `localhost:3000/api`. In production, set `VITE_API_URL` to the full API base including `/api` (e.g., `https://ca-api-xxx.azurecontainerapps.io/api`).
---

## Phase 3: AI Features

Add semantic search and a shopping assistant. Requires Azure AI Search and Azure OpenAI services.

### AI Feature 1: Semantic Product Search

Replace keyword filtering with semantic search that understands intent.

#### Azure AI Search Index

**Index name:** `aimarket-products`

**Fields:**

| Field | Type | Searchable | Filterable | Sortable | Facetable |
|-------|------|-----------|-----------|---------|----------|
| id | string (key) | no | yes | no | no |
| name | string | yes | no | yes | no |
| description | string | yes | no | no | no |
| category | string | yes | yes | no | yes |
| tags | string collection | yes | yes | no | yes |
| price | double | no | yes | yes | no |
| rating | double | no | yes | yes | no |

**Semantic configuration:**
- Semantic configuration name: `aimarket-semantic`
- Title field: `name`
- Content fields: `description`
- Keyword fields: `tags`

#### Endpoint: `POST /api/products/search`

**Request body:**

```json
{
  "query": "something lightweight for travel",
  "category": "Electronics",
  "minPrice": 100,
  "maxPrice": 1500
}
```

Only `query` is required. `category`, `minPrice`, and `maxPrice` are optional filters applied alongside semantic ranking.

**Response (200):**

```json
{
  "data": [
    {
      "id": "prod-1",
      "name": "UltraBook Pro 15",
      "shortDescription": "Lightweight 15-inch ultrabook with all-day battery",
      "price": 1299.99,
      "category": "Electronics",
      "rating": 4.7,
      "imageUrl": "https://images.unsplash.com/photo-1589561084283-930aa7b1ce50?w=400&h=300&fit=crop",
      "score": 0.92
  "count": 3
}
```

**Behavior:**
- Uses Azure AI Search with semantic ranking (query type: `semantic`)
- Falls back to simple text search if Azure AI Search is unavailable
- Returns top 10 results ranked by semantic relevance
- Each result includes a `score` (0-1) from Azure AI Search
- **Two-step process:** Search returns IDs and scores from the index, then the API fetches full product details (including `shortDescription`, `imageUrl`) from the database and merges them into the response

#### Indexing

- On API startup, push all seed products to the Azure AI Search index
- Provide a script or endpoint (`POST /api/products/reindex`) to re-push all products

#### Frontend Integration

- Add an "AI Search" toggle to the SearchBar component
- When enabled, search calls `POST /api/products/search` instead of client-side filtering
- Show a small label on results: "AI-powered results" when semantic search is active

### AI Feature 2: Shopping Assistant

A conversational agent that helps users find products.

#### Endpoint: `POST /api/chat`

**Request body:**

```json
{
  "messages": [
    { "role": "user", "content": "What laptops do you have?" }
  ]
}
```

**Response (200):**

```json
{
  "role": "assistant",
  "content": "We have the UltraBook Pro 15, a lightweight 15-inch ultrabook at $1,299.99 with a 4.7 rating. It's great for travel and has all-day battery life. Would you like more details, or are you looking for something in a different price range?"
}
```

#### System Prompt

```
You are the AIMarket shopping assistant. You help customers find and compare 
products from the AIMarket catalog.

Rules:
- Only recommend products that exist in the catalog provided below.
- Include the product name, price, and rating when recommending products.
- If a customer asks about a product category you don't have, say so honestly.
- Keep responses concise (2-3 sentences for simple questions, up to a paragraph for comparisons).
- Do not make up products, prices, or features that aren't in the catalog.
- You cannot process orders, handle returns, or take payments. If asked, explain 
  that the customer can add items to their cart on the website.

Current catalog:
{products_json}
```

**Behavior:**
- On each request, fetch all active products and inject them into the system prompt as JSON
- Use Azure OpenAI chat completions API with `gpt-4o` (or `gpt-5-mini` if quota is available)
- Temperature: `0.7`
- Max tokens: `500`
- Pass the full message history from the request (the client maintains conversation state)

### Environment Variables (Phase 3)

`AZURE_SEARCH_ENDPOINT`, `AZURE_SEARCH_KEY`, `AZURE_SEARCH_INDEX` (default: `aimarket-products`), `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_KEY`, `AZURE_OPENAI_DEPLOYMENT` (default: `gpt-4o`).

When not set: search falls back to SQLite LIKE queries; `/api/chat` returns 503.
---

## Phase 4: Deploy to Azure

Deploy the full stack to Azure Container Apps using Bicep with AVM modules and azd.

### Containerization

- **API Dockerfile:** Multi-stage build for your language. Builder stage compiles, final stage runs production artifacts only. Include `.dockerignore` to exclude dependency directories and db files.
- **Client Dockerfile:** Multi-stage `node:20-alpine` → `nginx:alpine`. Accept `VITE_API_URL` build arg. Serve with `nginx.conf` using `try_files` for SPA routing. **No `/api/` proxy block** — the frontend calls the API directly via `VITE_API_URL`.
- **`.dockerignore`:** Both directories must exclude dependency dirs, build output, and `.env`.

### Azure Resources

Use **Azure Verified Modules (AVM)** from `br/public:avm/...` where possible. For resources that require `listKeys()` or `listCredentials()` to wire secrets into Container App env vars, use deterministic `existing` resource references with `dependsOn` on the AVM module.

| Resource | Module / Approach | Purpose |
|----------|------------------|---------|
| Monitoring | `br/public:avm/ptn/azd/monitoring` | Log Analytics + App Insights |
| Container Registry | `br/public:avm/res/container-registry/registry` + `existing` ref for `listCredentials()` | Docker images |
| Azure AI Search | `br/public:avm/res/search/search-service` (Basic SKU — required for semantic ranking) + `existing` ref for `listAdminKeys()` | Semantic product search |
| Container Apps Env | `br/public:avm/res/app/managed-environment` | Hosts API + frontend |
| Container Apps (×2) | `br/public:avm/res/app/container-app` | API + web |
| Microsoft Foundry | Raw resource (`Microsoft.CognitiveServices/accounts` with `kind: AIServices`, `allowProjectManagement: true`) + child project + model deployment | gpt-4o + Foundry project. Raw because the AVM `ai-foundry` pattern module generates internal resource names we can't predict, making `listKeys()` impossible. |

**Pattern for wiring secrets:** At subscription scope, `existing` resource references cannot use `dependsOn`, so `listKeys()`/`listCredentials()` fail because the resource hasn't been created yet. **Solution: create wrapper Bicep modules** scoped at resource group level. Each wrapper calls the AVM module, then uses an `existing` ref with `dependsOn` to extract keys. The main template calls these wrappers and reads keys from their outputs. Create wrapper modules for: Container Registry (outputs loginServer, username, password), AI Search (outputs endpoint, adminKey), and AI Services (outputs endpoint, key).

### Bicep Requirements

1. **Use AVM modules** for all resources except Microsoft Foundry (see table above for why)
2. **Deterministic naming** — all resources named with `${abbrs.xxx}${resourceToken}` so `existing` refs can resolve
3. **`azd-service-name` tags** on each container app (azd maps services by tag)
4. **Output `AZURE_CONTAINER_REGISTRY_ENDPOINT`** (azd reads this for image push)
5. **Wire AI credentials** into API container env vars via secrets using `listKeys()` / `listAdminKeys()`
6. **Azure AI Search** — use `basic` SKU (not `free`), set `disableLocalAuth: false`, and set `semanticSearch: 'free'` to enable the semantic ranker
7. **Microsoft Foundry** — set `disableLocalAuth: false` for key-based auth, enable system-assigned managed identity, and set `allowProjectManagement: true`
8. **Container App startup probe** — `failureThreshold` max is 10 (not 30) when using the AVM container-app module
9. **Soft-deleted Cognitive Services** — if a previous deployment fails or is torn down, the AI Services resource may be soft-deleted and block re-creation. Run `az cognitiveservices account list-deleted` and `az cognitiveservices account purge` before redeploying

### Deployment

1. `azd up` provisions infra and deploys both services
2. **Post-deploy:** Rebuild frontend with `VITE_API_URL` pointing to the API's FQDN (including `/api` path), push to ACR, update container app. This is needed because `azd deploy` doesn't pass Docker build args.
3. **Apple Silicon (M1/M2/M3):** Add `--platform linux/amd64` to `docker build` — Azure Container Apps runs Linux AMD64 containers
4. Set `DATA_PROVIDER=cosmos` or `DATA_PROVIDER=postgres` to switch from SQLite to a cloud database
