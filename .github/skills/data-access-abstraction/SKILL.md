---
name: data-access-abstraction
description: Data access abstraction patterns for apps that need to swap between local databases (SQLite) and cloud databases (Cosmos DB, PostgreSQL) without changing application code. Covers Node.js/TypeScript, Python/FastAPI, and .NET. Use when building apps that run locally with SQLite and deploy to Azure with Cosmos DB or PostgreSQL.
---

# Data Access Abstraction

Build APIs with swappable data layers using the repository pattern. Develop locally with SQLite, deploy to Azure with Cosmos DB or PostgreSQL — same route code, different backend. Works in any language.

## When to Use This Skill

- Building an API that needs to run locally (SQLite) and in Azure (Cosmos DB or PostgreSQL)
- Adding a new data provider to an existing app without changing routes or business logic
- Migrating from one database to another incrementally
- Any project following the AIMarket journey pattern (local dev → cloud deploy)

## Pattern Overview

The pattern is the same regardless of language:

```
Routes/Controllers → Repository Interfaces → Factory → Implementations
                                                │
                                                ├── SQLite (local dev)
                                                ├── Cosmos DB (Azure deploy)
                                                ├── PostgreSQL (Azure deploy)
                                                └── In-memory (testing)
```

**Three rules:**
1. Define repository interfaces (or abstract classes / protocols) per entity
2. Routes depend only on the interfaces — never import a database client directly
3. A factory reads a config value (`DATA_PROVIDER`) and returns the right implementation

Adding a new database means writing a new implementation file. Zero changes to routes.

## Environment Variable

All languages use the same convention:

```
DATA_PROVIDER=sqlite     # Local development (default)
DATA_PROVIDER=cosmos     # Azure Cosmos DB
DATA_PROVIDER=postgres   # Azure PostgreSQL
```

---

## Node.js / TypeScript

### Repository Interfaces

```typescript
// data/interfaces.ts

export interface IProductRepository {
  getAll(params: {
    page: number; pageSize: number;
    category?: string; minPrice?: number; maxPrice?: number;
  }): Promise<{ data: Product[]; totalCount: number }>;

  getById(id: string): Promise<Product | null>;
  create(input: CreateProductInput): Promise<Product>;
  update(id: string, fields: Partial<Product>): Promise<Product | null>;
}

export interface IOrderRepository {
  create(input: CreateOrderInput): Promise<Order>;
  getById(id: string): Promise<Order | null>;
  getByUserId(userId: string, page: number, pageSize: number): Promise<{ data: Order[]; totalCount: number }>;
}

export interface IUserRepository {
  create(input: CreateUserInput): Promise<User>;
  getById(id: string): Promise<User | null>;
  getByEmail(email: string): Promise<User | null>;
}

export interface DataStore {
  products: IProductRepository;
  orders: IOrderRepository;
  users: IUserRepository;
  close?(): void;
}
```

### Factory

```typescript
// data/store.ts

export async function createStore(): Promise<DataStore> {
  const provider = process.env.DATA_PROVIDER || 'sqlite';
  switch (provider) {
    case 'sqlite':
      return (await import('./sqlite.js')).createSqliteStore();
    case 'cosmos':
      return (await import('./cosmos.js')).createCosmosStore();
    case 'postgres':
      return (await import('./postgres.js')).createPostgresStore();
    default:
      throw new Error(`Unknown DATA_PROVIDER: ${provider}`);
  }
}
```

### SQLite Implementation

Use `better-sqlite3` (synchronous API, fast). Wrap sync calls in `Promise.resolve()` or make routes `await` — sync values resolve immediately.

```typescript
// data/sqlite.ts

import Database from 'better-sqlite3';

export function createSqliteStore(dbPath = 'app.db'): DataStore {
  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  // Create tables, seed if empty...

  return {
    products: {
      async getAll({ page, pageSize, category, minPrice, maxPrice }) {
        let where = 'WHERE status = ?';
        const params: any[] = ['active'];
        if (category) { where += ' AND category = ?'; params.push(category); }
        if (minPrice != null) { where += ' AND price >= ?'; params.push(minPrice); }
        if (maxPrice != null) { where += ' AND price <= ?'; params.push(maxPrice); }

        const { c: totalCount } = db.prepare(`SELECT COUNT(*) as c FROM products ${where}`).get(...params);
        const rows = db.prepare(`SELECT * FROM products ${where} LIMIT ? OFFSET ?`)
          .all(...params, pageSize, (page - 1) * pageSize);
        return { data: rows.map(parseRow), totalCount };
      },
      // ...
    },
    close: () => db.close(),
  };
}
```

**SQLite-specific:** Store arrays as JSON strings (`JSON.stringify(tags)`), parse on read. Use a junction table for order items.

### Cosmos DB Implementation

```typescript
// data/cosmos.ts

import { CosmosClient } from '@azure/cosmos';

export function createCosmosStore(): DataStore {
  const client = new CosmosClient({ endpoint: process.env.COSMOS_ENDPOINT!, key: process.env.COSMOS_KEY! });
  const db = client.database(process.env.COSMOS_DATABASE || 'aimarket');

  return {
    products: {
      async getAll({ page, pageSize, category, minPrice, maxPrice }) {
        let query = 'SELECT * FROM c WHERE c.status = @status';
        const parameters = [{ name: '@status', value: 'active' }];
        if (category) { query += ' AND c.category = @cat'; parameters.push({ name: '@cat', value: category }); }
        // ... build query
        const { resources } = await db.container('products').items.query({ query, parameters }).fetchAll();
        return { data: resources.slice((page-1)*pageSize, page*pageSize), totalCount: resources.length };
      },
      // ...
    },
  };
}
```

**Cosmos-specific:** Arrays and objects are native JSON — no serialization. Embed order items in the order document.

### PostgreSQL Implementation

Use `pg` (node-postgres). PostgreSQL supports native arrays and JSONB, so it sits between SQLite and Cosmos in terms of data handling.

```typescript
// data/postgres.ts

import pg from 'pg';

export function createPostgresStore(): DataStore {
  const pool = new pg.Pool({
    connectionString: process.env.POSTGRES_CONNECTION_STRING,
    ssl: process.env.POSTGRES_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
  });

  return {
    products: {
      async getAll({ page, pageSize, category, minPrice, maxPrice }) {
        let where = 'WHERE status = $1';
        const params: any[] = ['active'];
        let idx = 2;

        if (category) { where += ` AND category = $${idx++}`; params.push(category); }
        if (minPrice != null) { where += ` AND price >= $${idx++}`; params.push(minPrice); }
        if (maxPrice != null) { where += ` AND price <= $${idx++}`; params.push(maxPrice); }

        const countRes = await pool.query(`SELECT COUNT(*) FROM products ${where}`, params);
        const totalCount = parseInt(countRes.rows[0].count);
        const dataRes = await pool.query(
          `SELECT * FROM products ${where} LIMIT $${idx++} OFFSET $${idx}`,
          [...params, pageSize, (page - 1) * pageSize]
        );
        return { data: dataRes.rows, totalCount };
      },
      // ...
    },
    close: () => pool.end(),
  };
}
```

**PostgreSQL-specific:** Use `TEXT[]` for arrays (native), `JSONB` for nested objects, and `$1` parameterized queries. Azure PostgreSQL requires `ssl: { rejectUnauthorized: false }`.

### Routes

```typescript
// routes/products.ts — depends only on DataStore interface

export function productRoutes(store: DataStore): Router {
  const router = Router();
  router.get('/', async (req, res) => {
    const result = await store.products.getAll({ page: 1, pageSize: 20 });
    res.json(result);
  });
  return router;
}
```

---

## Python / FastAPI

### Repository Interfaces

Use `Protocol` (structural typing) or `ABC` (nominal typing). Protocol is more Pythonic.

```python
# data/interfaces.py

from typing import Protocol
from models import Product, Order, User

class ProductRepository(Protocol):
    def get_all(self, *, page: int = 1, page_size: int = 20,
                category: str | None = None, min_price: float | None = None,
                max_price: float | None = None) -> dict:
        """Returns { 'data': list[Product], 'total_count': int }"""
        ...

    def get_by_id(self, id: str) -> Product | None: ...
    def create(self, data: dict) -> Product: ...
    def update(self, id: str, fields: dict) -> Product | None: ...

class OrderRepository(Protocol):
    def create(self, data: dict) -> Order: ...
    def get_by_id(self, id: str) -> Order | None: ...
    def get_by_user_id(self, user_id: str, page: int, page_size: int) -> dict: ...

class UserRepository(Protocol):
    def create(self, data: dict) -> User: ...
    def get_by_id(self, id: str) -> User | None: ...
    def get_by_email(self, email: str) -> User | None: ...

class DataStore(Protocol):
    products: ProductRepository
    orders: OrderRepository
    users: UserRepository
```

### Factory

```python
# data/store.py

import os

def create_store() -> DataStore:
    provider = os.getenv("DATA_PROVIDER", "sqlite")
    if provider == "sqlite":
        from data.sqlite import create_sqlite_store
        return create_sqlite_store()
    elif provider == "cosmos":
        from data.cosmos import create_cosmos_store
        return create_cosmos_store()
    elif provider == "postgres":
        from data.postgres import create_postgres_store
        return create_postgres_store()
    else:
        raise ValueError(f"Unknown DATA_PROVIDER: {provider}")
```

### SQLite Implementation

```python
# data/sqlite.py

import sqlite3, json, uuid
from models import Product

class SqliteProductRepository:
    def __init__(self, db: sqlite3.Connection):
        self.db = db

    def get_all(self, *, page=1, page_size=20, category=None, min_price=None, max_price=None):
        where, params = "WHERE status = ?", ["active"]
        if category:
            where += " AND category = ?"; params.append(category)
        if min_price is not None:
            where += " AND price >= ?"; params.append(min_price)
        if max_price is not None:
            where += " AND price <= ?"; params.append(max_price)

        total = self.db.execute(f"SELECT COUNT(*) FROM products {where}", params).fetchone()[0]
        rows = self.db.execute(
            f"SELECT * FROM products {where} LIMIT ? OFFSET ?",
            params + [page_size, (page - 1) * page_size]
        ).fetchall()

        return {"data": [self._parse(r) for r in rows], "total_count": total}

    def _parse(self, row) -> Product:
        d = dict(row)
        d["tags"] = json.loads(d["tags"])  # JSON string → list
        return Product(**d)

def create_sqlite_store(db_path="app.db"):
    db = sqlite3.connect(db_path)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")
    # Create tables, seed if empty...
    return SqliteDataStore(
        products=SqliteProductRepository(db),
        orders=SqliteOrderRepository(db),
        users=SqliteUserRepository(db),
    )
```

### Cosmos DB Implementation

```python
# data/cosmos.py

from azure.cosmos import CosmosClient
import os

class CosmosProductRepository:
    def __init__(self, container):
        self.container = container

    def get_all(self, *, page=1, page_size=20, category=None, min_price=None, max_price=None):
        query = "SELECT * FROM c WHERE c.status = @status"
        params = [{"name": "@status", "value": "active"}]
        if category:
            query += " AND c.category = @cat"
            params.append({"name": "@cat", "value": category})
        # ... build query
        items = list(self.container.query_items(query=query, parameters=params, enable_cross_partition_query=True))
        start = (page - 1) * page_size
        return {"data": items[start:start+page_size], "total_count": len(items)}

def create_cosmos_store():
    client = CosmosClient(os.environ["COSMOS_ENDPOINT"], os.environ["COSMOS_KEY"])
    db = client.get_database_client(os.getenv("COSMOS_DATABASE", "aimarket"))
    return CosmosDataStore(
        products=CosmosProductRepository(db.get_container_client("products")),
        orders=CosmosOrderRepository(db.get_container_client("orders")),
        users=CosmosUserRepository(db.get_container_client("users")),
    )
```

### FastAPI Routes

```python
# routes/products.py — depends only on DataStore protocol

from fastapi import APIRouter, Depends
from data.store import create_store

router = APIRouter(prefix="/api/products")

@router.get("/")
def list_products(page: int = 1, page_size: int = 20, category: str | None = None,
                  store: DataStore = Depends(create_store)):
    result = store.products.get_all(page=page, page_size=page_size, category=category)
    return {**result, "page": page, "page_size": page_size}
```

---

## .NET / C# (Minimal APIs or Controllers)

### Repository Interfaces

```csharp
// Data/Interfaces.cs

public interface IProductRepository
{
    Task<(List<Product> Data, int TotalCount)> GetAllAsync(
        int page = 1, int pageSize = 20,
        string? category = null, decimal? minPrice = null, decimal? maxPrice = null);
    Task<Product?> GetByIdAsync(string id);
    Task<Product> CreateAsync(CreateProductInput input);
    Task<Product?> UpdateAsync(string id, UpdateProductInput input);
}

public interface IOrderRepository
{
    Task<Order> CreateAsync(CreateOrderInput input);
    Task<Order?> GetByIdAsync(string id);
    Task<(List<Order> Data, int TotalCount)> GetByUserIdAsync(string userId, int page, int pageSize);
}

public interface IUserRepository
{
    Task<User> CreateAsync(CreateUserInput input);
    Task<User?> GetByIdAsync(string id);
    Task<User?> GetByEmailAsync(string email);
}
```

### Dependency Injection (Factory)

```csharp
// Program.cs

var provider = builder.Configuration["DATA_PROVIDER"] ?? "sqlite";

if (provider == "sqlite")
{
    builder.Services.AddSingleton<IProductRepository, SqliteProductRepository>();
    builder.Services.AddSingleton<IOrderRepository, SqliteOrderRepository>();
    builder.Services.AddSingleton<IUserRepository, SqliteUserRepository>();
}
else if (provider == "cosmos")
{
    builder.Services.AddSingleton<IProductRepository, CosmosProductRepository>();
    builder.Services.AddSingleton<IOrderRepository, CosmosOrderRepository>();
    builder.Services.AddSingleton<IUserRepository, CosmosUserRepository>();
}
else if (provider == "postgres")
{
    builder.Services.AddSingleton<IProductRepository, PostgresProductRepository>();
    builder.Services.AddSingleton<IOrderRepository, PostgresOrderRepository>();
    builder.Services.AddSingleton<IUserRepository, PostgresUserRepository>();
}
```

.NET uses built-in DI instead of a manual factory. The pattern is the same: register implementations based on config, inject interfaces into routes.

### SQLite Implementation

```csharp
// Data/SqliteProductRepository.cs

using Microsoft.Data.Sqlite;
using System.Text.Json;

public class SqliteProductRepository : IProductRepository
{
    private readonly SqliteConnection _db;

    public SqliteProductRepository(IConfiguration config)
    {
        _db = new SqliteConnection(config.GetConnectionString("Sqlite") ?? "Data Source=app.db");
        _db.Open();
        // Create tables, seed if empty...
    }

    public async Task<(List<Product> Data, int TotalCount)> GetAllAsync(
        int page = 1, int pageSize = 20,
        string? category = null, decimal? minPrice = null, decimal? maxPrice = null)
    {
        var where = "WHERE status = 'active'";
        if (category != null) where += $" AND category = @category";
        if (minPrice != null) where += $" AND price >= @minPrice";
        if (maxPrice != null) where += $" AND price <= @maxPrice";

        // Execute count + select queries...
        // Parse tags from JSON string: JsonSerializer.Deserialize<string[]>(row["tags"])
    }
}
```

### Cosmos DB Implementation

```csharp
// Data/CosmosProductRepository.cs

using Microsoft.Azure.Cosmos;

public class CosmosProductRepository : IProductRepository
{
    private readonly Container _container;

    public CosmosProductRepository(CosmosClient client, IConfiguration config)
    {
        var db = client.GetDatabase(config["COSMOS_DATABASE"] ?? "aimarket");
        _container = db.GetContainer("products");
    }

    public async Task<(List<Product> Data, int TotalCount)> GetAllAsync(
        int page = 1, int pageSize = 20,
        string? category = null, decimal? minPrice = null, decimal? maxPrice = null)
    {
        var query = new QueryDefinition("SELECT * FROM c WHERE c.status = @status")
            .WithParameter("@status", "active");
        // Add filters, execute, paginate...
    }
}
```

### Minimal API Routes

```csharp
// Routes depend only on interfaces — injected via DI

app.MapGet("/api/products", async (IProductRepository repo,
    int page = 1, int pageSize = 20, string? category = null) =>
{
    var (data, total) = await repo.GetAllAsync(page, pageSize, category);
    return Results.Ok(new { data, page, pageSize, totalCount = total });
});
```

---

## Java / Spring Boot

### Repository Interfaces

```java
// data/ProductRepository.java

public interface ProductRepository {
    PaginatedResult<Product> getAll(int page, int pageSize,
        String category, Double minPrice, Double maxPrice);
    Optional<Product> getById(String id);
    Product create(CreateProductInput input);
    Optional<Product> update(String id, UpdateProductInput input);
}

// data/OrderRepository.java

public interface OrderRepository {
    Order create(CreateOrderInput input);
    Optional<Order> getById(String id);
    PaginatedResult<Order> getByUserId(String userId, int page, int pageSize);
}

// data/UserRepository.java

public interface UserRepository {
    User create(CreateUserInput input);
    Optional<User> getById(String id);
    Optional<User> getByEmail(String email);
}
```

### Factory via Spring Profiles

Spring profiles replace the manual factory. Set `DATA_PROVIDER` as the active profile:

```yaml
# application.yml
spring:
  profiles:
    active: ${DATA_PROVIDER:sqlite}
```

```java
// data/sqlite/SqliteProductRepository.java

@Repository
@Profile("sqlite")
public class SqliteProductRepository implements ProductRepository {
    private final JdbcTemplate jdbc;

    public SqliteProductRepository(DataSource dataSource) {
        this.jdbc = new JdbcTemplate(dataSource);
    }

    @Override
    public PaginatedResult<Product> getAll(int page, int pageSize,
            String category, Double minPrice, Double maxPrice) {
        var where = new StringBuilder("WHERE status = 'active'");
        var params = new ArrayList<>();

        if (category != null) { where.append(" AND category = ?"); params.add(category); }
        if (minPrice != null) { where.append(" AND price >= ?"); params.add(minPrice); }
        if (maxPrice != null) { where.append(" AND price <= ?"); params.add(maxPrice); }

        int total = jdbc.queryForObject(
            "SELECT COUNT(*) FROM products " + where, Integer.class, params.toArray());
        var rows = jdbc.query(
            "SELECT * FROM products " + where + " LIMIT ? OFFSET ?",
            this::mapRow,
            Stream.concat(params.stream(), Stream.of(pageSize, (page - 1) * pageSize)).toArray());

        return new PaginatedResult<>(rows, total);
    }

    private Product mapRow(ResultSet rs, int rowNum) throws SQLException {
        return new Product(
            rs.getString("id"),
            rs.getString("name"),
            // ...
            objectMapper.readValue(rs.getString("tags"), new TypeReference<List<String>>() {}),  // JSON → List
            // ...
        );
    }
}
```

```java
// data/cosmos/CosmosProductRepository.java

@Repository
@Profile("cosmos")
public class CosmosProductRepository implements ProductRepository {
    private final CosmosContainer container;

    public CosmosProductRepository(CosmosClient client,
            @Value("${cosmos.database:aimarket}") String dbName) {
        this.container = client.getDatabase(dbName).getContainer("products");
    }

    @Override
    public PaginatedResult<Product> getAll(int page, int pageSize,
            String category, Double minPrice, Double maxPrice) {
        var query = new StringBuilder("SELECT * FROM c WHERE c.status = @status");
        var params = new ArrayList<SqlParameter>();
        params.add(new SqlParameter("@status", "active"));

        if (category != null) {
            query.append(" AND c.category = @cat");
            params.add(new SqlParameter("@cat", category));
        }
        // ... build query

        var options = new CosmosQueryRequestOptions();
        var items = container.queryItems(
            new SqlQuerySpec(query.toString(), params), options, Product.class);

        var all = items.stream().collect(Collectors.toList());
        int start = (page - 1) * pageSize;
        return new PaginatedResult<>(
            all.subList(start, Math.min(start + pageSize, all.size())), all.size());
    }
}
```

### SQLite DataSource Config

```java
// config/SqliteConfig.java

@Configuration
@Profile("sqlite")
public class SqliteConfig {
    @Bean
    public DataSource dataSource() {
        var ds = new SQLiteDataSource();
        ds.setUrl("jdbc:sqlite:app.db");
        return ds;
    }

    @Bean
    public CommandLineRunner initDb(DataSource dataSource) {
        return args -> {
            var jdbc = new JdbcTemplate(dataSource);
            jdbc.execute("PRAGMA journal_mode=WAL");
            jdbc.execute("PRAGMA foreign_keys=ON");
            // Create tables, seed if empty...
        };
    }
}
```

### Controller Routes

```java
// controller/ProductController.java — depends only on ProductRepository interface

@RestController
@RequestMapping("/api/products")
public class ProductController {
    private final ProductRepository repo;

    public ProductController(ProductRepository repo) {  // Spring injects the active profile's impl
        this.repo = repo;
    }

    @GetMapping
    public ResponseEntity<?> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int pageSize,
            @RequestParam(required = false) String category) {
        var result = repo.getAll(page, pageSize, category, null, null);
        return ResponseEntity.ok(Map.of(
            "data", result.data(), "page", page, "pageSize", pageSize,
            "totalCount", result.totalCount(),
            "totalPages", (int) Math.ceil((double) result.totalCount() / pageSize)
        ));
    }
}
```

**Key:** Spring's `@Profile` + DI eliminates the manual factory. Set `DATA_PROVIDER=postgres` or `DATA_PROVIDER=cosmos` as the active profile and Spring wires the matching implementations automatically. Add `@Profile("postgres")` to a `PostgresProductRepository` that uses `JdbcTemplate` with a PostgreSQL `DataSource` — same `JdbcTemplate` API as SQLite, different driver and SQL dialect.

---

## SQLite Patterns (All Languages)

SQLite doesn't support arrays or nested objects. These patterns apply regardless of language:

| Data Type | SQLite Storage | Read Pattern |
|-----------|---------------|-------------|
| `string[]` (tags) | JSON string column: `'["tag1","tag2"]'` | Parse with `JSON.parse()` / `json.loads()` / `JsonSerializer.Deserialize` / `ObjectMapper.readValue()` |
| Nested object (address) | JSON string column: `'{"street":"..."}'` | Parse on read |
| One-to-many (order items) | Junction table: `order_items(orderId, productId, quantity, price)` | JOIN on read |
| UUID primary keys | TEXT column | Generate with `uuid` / `uuid4()` / `Guid.NewGuid()` / `UUID.randomUUID()` |

**Pragmas to always set:**
```sql
PRAGMA journal_mode = WAL;    -- Better concurrent read performance
PRAGMA foreign_keys = ON;     -- Enforce referential integrity
```

## Cosmos DB Patterns (All Languages)

| Data Type | Cosmos DB Storage | Notes |
|-----------|------------------|-------|
| `string[]` (tags) | Native JSON array | No serialization needed |
| Nested object (address) | Native JSON object | No serialization needed |
| One-to-many (order items) | Embedded array in document | No junction table needed |
| Queries | SQL-like with `@param` | Use parameterized queries for safety |

**Partition key strategy:** Choose a field that distributes data evenly. Common choices: `/id` (default), `/category` (products), `/userId` (orders).

## PostgreSQL Patterns (All Languages)

PostgreSQL supports native arrays and JSONB, so it handles complex types better than SQLite but uses SQL instead of Cosmos DB's document model.

| Data Type | PostgreSQL Storage | Notes |
|-----------|-------------------|-------|
| `string[]` (tags) | `TEXT[]` (native array) | Use `= ANY($1)` for filtering, no serialization needed |
| Nested object (address) | `JSONB` column | Query with `->` / `->>` operators |
| One-to-many (order items) | Junction table (same as SQLite) or `JSONB` array | Junction table is cleaner for queries |
| UUID primary keys | `UUID` type or `TEXT` | Use `gen_random_uuid()` for server-side generation |
| Parameterized queries | `$1, $2, $3` (Node pg) or `%s` (Python psycopg2) or `@param` (.NET Npgsql) | Never concatenate user input |

**Azure PostgreSQL requirements:**
```
# Connection string must include sslmode
POSTGRES_CONNECTION_STRING=postgresql://user:pass@host.postgres.database.azure.com:5432/aimarket?sslmode=require

# For Azure Flexible Server, also set
POSTGRES_SSL=true
```

**Libraries by language:**

| Language | Library | Notes |
|----------|---------|-------|
| Node.js | `pg` (node-postgres) | Use `Pool` for connection pooling |
| Python | `psycopg2` or `asyncpg` | `psycopg2-binary` for easy install, `asyncpg` for async FastAPI |
| .NET | `Npgsql` + `Npgsql.EntityFrameworkCore.PostgreSQL` | Or raw `NpgsqlConnection` |
| Java | Spring `JdbcTemplate` + `postgresql` driver | Same `JdbcTemplate` API as SQLite, different DataSource |

## Anti-Patterns

| Don't | Do Instead |
|-------|------------|
| Import database clients in route files | Import only interfaces/protocols |
| Put SQL/query strings in routes | Encapsulate in the implementation |
| Hardcode connection strings | Use environment variables |
| Create one repository for all entities | One interface per entity |
| Skip `async/await` because SQLite is sync | Always use async — it's free for sync implementations |
| Test against a real database | Create an in-memory implementation for unit tests |

## Checklist

- [ ] Repository interfaces defined per entity (typed, no database-specific imports)
- [ ] Factory/DI reads `DATA_PROVIDER` and returns the correct implementation
- [ ] Routes depend only on interfaces, never on implementation files
- [ ] SQLite implementation handles JSON serialization for arrays and objects
- [ ] PostgreSQL implementation uses native `TEXT[]` for arrays and `JSONB` for objects
- [ ] Cosmos DB implementation uses native JSON types (no serialization)
- [ ] `DATA_PROVIDER=sqlite` works locally
- [ ] `DATA_PROVIDER=postgres` works with Azure PostgreSQL (SSL enabled)
- [ ] `DATA_PROVIDER=cosmos` works with Azure Cosmos DB
- [ ] `.env.example` documents all providers and their required variables
- [ ] An in-memory implementation exists for unit tests
