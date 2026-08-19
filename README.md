# E-Commerce Microservices Platform

A full-stack e-commerce application built with **.NET 8**, demonstrating a
production-style microservices architecture: four independent backend services, a
YARP API gateway, and a Razor Pages web client, all containerized with Docker Compose.

Each service is deliberately implemented in a **different architectural style**, so the
solution doubles as a side-by-side comparison of how these approaches play out in
practice.

Around the application sit the pieces a real deployment needs: an xUnit test suite
(51 tests, no Docker required), four GitHub Actions pipelines that build, scan, publish and
deploy, and a Terraform stack that provisions the whole thing on AWS ECS Fargate.

---

## Architecture

```mermaid
%%{init: {"theme": "base", "themeVariables": {
    "fontFamily": "-apple-system, Segoe UI, Helvetica, Arial, sans-serif",
    "primaryColor": "#ffffff",
    "primaryTextColor": "#1f2328",
    "primaryBorderColor": "#8c959f",
    "lineColor": "#57606a",
    "textColor": "#1f2328",
    "mainBkg": "#ffffff",
    "clusterBkg": "#f6f8fa",
    "clusterBorder": "#d0d7de",
    "edgeLabelBackground": "#f6f8fa",
    "titleColor": "#1f2328"
}}}%%
flowchart TB
    BROWSER(["Browser"])

    subgraph docker ["🐳 &nbsp; Docker Compose &nbsp; · &nbsp; 11 containers on a shared bridge network"]
        direction TB

        subgraph client ["Client container"]
            WEB["<b>shopping.web</b><br/>Razor Pages + Refit<br/>host :6005"]
        end

        subgraph gateway ["Gateway container"]
            GW["<b>yarpapigateway</b><br/>Gateway Routing + Rate Limiting<br/>host :6004"]
        end

        subgraph services ["Service containers"]
            CAT["<b>catalog.api</b><br/>Vertical Slice + CQRS<br/>host :6000"]
            BAS["<b>basket.api</b><br/>Vertical Slice + CQRS<br/>host :6001"]
            DIS["<b>discount.grpc</b><br/>N-Layer, gRPC server<br/>host :6002"]
            ORD["<b>ordering.api</b><br/>Clean Architecture + DDD<br/>host :6003"]
        end

        subgraph broker ["Broker container"]
            MQ{{"<b>messagebroker</b><br/>RabbitMQ + MassTransit<br/>:5672 &nbsp; UI :15672"}}
        end

        subgraph data ["Data containers"]
            CATDB[("<b>catalogdb</b><br/>PostgreSQL, Marten<br/>:5432")]
            BASDB[("<b>basketdb</b><br/>PostgreSQL, Marten<br/>:5433")]
            CACHE[("<b>distributedcache</b><br/>Redis<br/>:6379")]
            ORDDB[("<b>orderdb</b><br/>SQL Server, EF Core<br/>:1433")]
            DISDB[("SQLite file<br/>EF Core<br/>in-container")]
        end
    end

    BROWSER -->|"HTTP :6005"| WEB
    WEB -->|"Refit typed clients"| GW
    GW -->|"/catalog-service/*"| CAT
    GW -->|"/basket-service/*"| BAS
    GW -->|"/ordering-service/*"| ORD

    BAS -->|"gRPC GetDiscount<br/><b>synchronous</b>"| DIS
    BAS -->|"publish<br/>BasketCheckoutEvent"| MQ
    MQ -->|"consume<br/><b>asynchronous</b>"| ORD

    CAT --- CATDB
    BAS --- BASDB
    BAS -.->|"cache-aside"| CACHE
    DIS --- DISDB
    ORD --- ORDDB

    classDef svc fill:#4f46e5,stroke:#3730a3,color:#fff
    classDef store fill:#f1f3f6,stroke:#c9cfda,color:#23272f
    classDef bus fill:#b54708,stroke:#93370d,color:#fff
    classDef edge fill:#0f766e,stroke:#115e59,color:#fff
    classDef ext fill:#ffffff,stroke:#8c959f,color:#1f2328

    class CAT,BAS,DIS,ORD svc
    class CATDB,BASDB,CACHE,DISDB,ORDDB store
    class MQ bus
    class WEB,GW edge
    class BROWSER ext

    style docker fill:#f6f8fa,stroke:#d0d7de,rx:18,ry:18
    linkStyle 0 color:#ffffff
```

Every box inside the boundary is a container declared in `docker-compose.yml` and built
from its own `Dockerfile`. `docker-compose.override.yml` wires them together by injecting
connection strings, gateway addresses and broker credentials as environment variables, so
no host or password is hard-coded in the images.

Containers reach each other by Compose service name on the internal network, never through
the published ports:

| From | To | Internal address |
|---|---|---|
| shopping.web | gateway | `http://yarpapigateway:8080` |
| gateway | catalog.api | `http://catalog.api:8080` |
| basket.api | discount.grpc | `http://discount.grpc:8080` |
| basket.api | Redis | `distributedcache:6379` |
| basket.api / ordering.api | RabbitMQ | `amqp://ecommerce-mq:5672` |

The `:6000` to `:6005` host ports shown in the diagram exist only so you can hit individual
services from your machine while debugging. A single `docker compose up` builds and starts
the entire system.

### The 11 containers

`docker-compose.yml` declares exactly eleven services: six application containers built
from source, and five infrastructure containers pulled from public images.

**Application containers** — built from a `Dockerfile` in this repo, all listening on
`8080` (HTTP) and `8081` (HTTPS) inside the network:

| # | Compose service | Image | Host ports | Role |
|---|---|---|---|---|
| 1 | `catalog.api` | `catalogapi` (built) | 6000, 6060 | Product catalog, vertical slices over Marten |
| 2 | `basket.api` | `basketapi` (built) | 6001, 6061 | Shopping cart, Redis cache-aside, publishes checkout events |
| 3 | `discount.grpc` | `discountgrpc` (built) | 6002, 6062 | gRPC discount server, SQLite file inside the container |
| 4 | `ordering.api` | `orderingapi` (built) | 6003, 6063 | Clean Architecture + DDD, consumes checkout events |
| 5 | `yarpapigateway` | `yarpapigateway` (built) | 6004 | Single entry point, routing + rate limiting |
| 6 | `shopping.web` | `shoppingweb` (built) | 6005 | Razor Pages storefront, talks only to the gateway |

**Infrastructure containers** — official images, `restart: always`:

| # | Compose service | Image | Host ports | Role |
|---|---|---|---|---|
| 7 | `catalogdb` | `postgres` | 5432 | Catalog document store, volume `postgres_catalog` |
| 8 | `basketdb` | `postgres` | 5433 → 5432 | Basket document store, volume `postgres_basket` |
| 9 | `distributedcache` | `redis` | 6379 | Basket distributed cache |
| 10 | `orderdb` | `mcr.microsoft.com/mssql/server` | 1433 | Ordering relational store (EF Core) |
| 11 | `messagebroker` | `rabbitmq:management` | 5672, 15672 | Event bus, hostname `ecommerce-mq`, management UI |

Discount has no database container of its own: it keeps a SQLite file inside its own
container, which is why the count is eleven rather than twelve.

Startup order is expressed with `depends_on`: `shopping.web` waits on `yarpapigateway`,
which waits on the three HTTP APIs; `basket.api` waits on `basketdb`,
`distributedcache`, `discount.grpc` and `messagebroker`; `catalog.api` on `catalogdb`;
`ordering.api` on `orderdb` and `messagebroker`.

### Checkout workflow

The full path a checkout takes through the system, showing where communication is
synchronous and where it is event-driven:

```mermaid
%%{init: {"theme": "base", "themeVariables": {
    "fontFamily": "-apple-system, Segoe UI, Helvetica, Arial, sans-serif",
    "primaryColor": "#ffffff",
    "primaryTextColor": "#1f2328",
    "primaryBorderColor": "#8c959f",
    "lineColor": "#57606a",
    "textColor": "#1f2328",
    "actorBkg": "#ffffff",
    "actorBorder": "#8c959f",
    "actorTextColor": "#1f2328",
    "actorLineColor": "#8c959f",
    "signalColor": "#1f2328",
    "signalTextColor": "#1f2328",
    "noteBkgColor": "#fff8c5",
    "noteBorderColor": "#d4a72c",
    "noteTextColor": "#1f2328",
    "labelBoxBkgColor": "#ffffff",
    "labelBoxBorderColor": "#8c959f",
    "labelTextColor": "#1f2328",
    "loopTextColor": "#1f2328",
    "activationBkgColor": "#f6f8fa",
    "activationBorderColor": "#8c959f",
    "sequenceNumberColor": "#ffffff"
}}}%%
sequenceDiagram
    autonumber
    actor U as User
    participant W as Shopping.Web
    participant G as YARP Gateway
    participant B as Basket.API
    participant D as Discount.Grpc
    participant R as Redis
    participant Q as RabbitMQ
    participant O as Ordering.API
    participant S as SQL Server

    rect rgb(238, 241, 255)
    note over U,R: Building the cart
    U->>W: Add product to cart
    W->>G: POST /basket-service/basket
    G->>B: StoreBasketCommand via MediatR
    loop for each cart item
        B->>D: gRPC GetDiscount
        D-->>B: Coupon amount
        note right of B: item.Price -= coupon.Amount
    end
    B->>R: Store basket, cache-aside
    B-->>W: Updated cart
    end

    rect rgb(255, 250, 235)
    note over U,Q: Checkout, fire and forget
    U->>W: Place order
    W->>G: POST /basket-service/basket/checkout
    G->>B: CheckoutBasketCommand
    B->>Q: Publish BasketCheckoutEvent
    B->>R: Delete basket
    B-->>W: Success
    W-->>U: Confirmation page
    end

    rect rgb(236, 253, 243)
    note over Q,S: Order processing, decoupled
    Q->>O: Consume BasketCheckoutEvent
    O->>O: Map to CreateOrderCommand
    O->>O: Build Order aggregate
    O->>S: SaveChanges
    note right of O: Interceptor dispatches<br/>OrderCreatedEvent
    end
```

The user is never blocked on order creation. Basket returns as soon as the event is
published, and Ordering processes it independently, so the ordering service can be down
or restarting without breaking checkout.

### Architectural styles by service

| Service | Architecture | Key patterns |
|---|---|---|
| **Catalog.API** | Vertical Slice Architecture | CQRS, feature folders, Marten document DB |
| **Basket.API** | Vertical Slice Architecture | CQRS, Repository, Decorator, Cache-Aside |
| **Discount.Grpc** | N-Layer Architecture | gRPC services, EF Core, Protobuf contracts |
| **Ordering** | Clean Architecture + DDD | Aggregates, Value Objects, Domain Events, CQRS |

### Communication

- **Synchronous**: Basket calls Discount over **gRPC / Protocol Buffers** to resolve
  the final product price at cart time.
- **Asynchronous**: Basket publishes a `BasketCheckoutEvent` to **RabbitMQ** via
  **MassTransit**; Ordering subscribes and materializes the order. This decouples
  checkout from order processing entirely.

---

## Tech stack

**Backend**: .NET 8, ASP.NET Core Minimal APIs, gRPC, Carter, MediatR, FluentValidation, Mapster, Scrutor
**Frontend**: ASP.NET Core Razor Pages, Bootstrap, jQuery, Refit
**Data**: PostgreSQL (Marten document DB), SQL Server + SQLite (EF Core), Redis
**Messaging**: RabbitMQ, MassTransit
**Gateway**: YARP Reverse Proxy
**Testing**: xUnit, FluentAssertions, NSubstitute, WireMock.Net, Coverlet
**CI/CD**: GitHub Actions, Docker Buildx, Trivy, OIDC federation to AWS
**Cloud**: Terraform, AWS ECS Fargate, ALB, RDS, ElastiCache, Amazon MQ / SQS + SNS, Secrets Manager, CloudWatch
**Infrastructure**: Docker, Docker Compose

---

## Services

### Catalog.API
Product catalog built as vertical slices. Each feature (`CreateProduct`,
`GetProductByCategory`, and so on) owns its command/query, handler, validator, and
endpoint in a single folder. Uses **Marten** for transactional document storage on
PostgreSQL, with Carter for endpoint registration.

### Basket.API
Shopping cart persisted as a document per user. A `CachedBasketRepository` **decorator**
(wired via Scrutor) layers Redis cache-aside on top of the base repository without the
handlers knowing about it. Calls Discount over gRPC, and publishes checkout events to
RabbitMQ.

### Discount.Grpc
A lean gRPC server exposing four RPCs (`GetDiscount`, `CreateDiscount`,
`UpdateDiscount`, `DeleteDiscount`) over Protobuf contracts, backed by SQLite through
EF Core with code-first migrations.

### Ordering
Clean Architecture across four projects: `Domain`, `Application`, `Infrastructure`,
`API`. The domain layer models orders as **DDD aggregates** with strongly-typed value
objects (`OrderId`, `CustomerId`, `Address`, `Payment`) and raises **domain events**
dispatched through an EF Core `SaveChanges` interceptor.

### YarpApiGateway
Single entry point applying the Gateway Routing pattern, with route/cluster/transform
configuration and a fixed-window **rate limiter** (5 requests / 10s) on the ordering
route.

### Shopping.Web
Server-rendered Razor Pages storefront covering product listing, product detail, cart,
checkout, and order history. It consumes the gateway through three **Refit** typed HTTP
clients.

---

## Cross-cutting concerns

Shared via the `BuildingBlocks` libraries:

- **CQRS abstractions**: `ICommand`, `IQuery`, and their handler interfaces
- **Pipeline behaviors**: `ValidationBehavior` (FluentValidation) and `LoggingBehavior`
  run around every MediatR request
- **Global exception handling**: `CustomExceptionHandler` maps domain and validation
  exceptions to RFC 7807 problem details
- **Health checks**: every service exposes `/health` with a UI-friendly response writer
- **Pagination**: shared `PaginatedResult<T>` / `PaginationRequest`

---

## Getting started

### Prerequisites

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Docker Desktop](https://www.docker.com/products/docker-desktop) (allocate at least
  4 GB memory)
- [Visual Studio 2022](https://visualstudio.microsoft.com/downloads/) or
  [VS Code](https://code.visualstudio.com/) (optional)

### Run it

```bash
git clone https://github.com/Zack-Gtay/e-commerce-microservices.git
cd e-commerce-microservices/src
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d
```

Give the databases a moment to finish initializing on first run. A couple of services
retry their connection until the containers are healthy.

To build and test without Docker:

```bash
dotnet build src/eshop-microservices.sln
dotnet test  src/eshop-microservices.sln
```

### Endpoints

| Service | HTTP | HTTPS |
|---|---|---|
| Shopping Web UI | http://localhost:6005 | n/a |
| YARP API Gateway | http://localhost:6004 | n/a |
| Catalog API | http://localhost:6000 | https://localhost:6060 |
| Basket API | http://localhost:6001 | https://localhost:6061 |
| Discount gRPC | http://localhost:6002 | https://localhost:6062 |
| Ordering API | http://localhost:6003 | https://localhost:6063 |
| RabbitMQ dashboard | http://localhost:15672 | n/a |

RabbitMQ dashboard credentials are `guest` / `guest`.

Checking out a basket from the web UI publishes a message you can watch land on the
RabbitMQ dashboard before Ordering consumes it.

---

## Tests

Three xUnit projects, **51 tests**, all in `src/tests/`. They run entirely in-process:
no Docker, no database, no network, so `dotnet test` is a few seconds on a cold clone.

```bash
dotnet test src/eshop-microservices.sln
```

| Project | Tests | What it pins down |
|---|---|---|
| `Ordering.Domain.UnitTests` | 29 | `Order` aggregate invariants (status transitions, line-item add/remove, total price, exactly-one `OrderCreatedEvent`, event clearing) and the strongly-typed value objects (`OrderId`, `CustomerId`, `ProductId`, `Address`, `Payment`) |
| `BuildingBlocks.UnitTests` | 6 | `ValidationBehavior`: short-circuits the pipeline before the handler, aggregates failures across every registered validator, and surfaces property names for the ProblemDetails payload |
| `Shopping.Web.IntegrationTests` | 16 | The three Refit typed clients against a `WireMockGatewayFixture` standing in for the YARP gateway — real URL templates, real JSON contracts, real error mapping (`ApiException` on a gateway 500) |

Tooling: **xUnit** + **FluentAssertions**, **NSubstitute** for handler doubles,
**WireMock.Net** for the gateway stub, **Coverlet** for Cobertura coverage in CI.

---

## CI/CD

Four GitHub Actions workflows in `.github/workflows/`. Everything that touches AWS
authenticates through **GitHub OIDC federation** — an IAM role assumed for the life of the
job — so there are no long-lived `AWS_ACCESS_KEY_ID` secrets in the repo.

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | push / PR to `main` | Restore → build → `dotnet test` with Cobertura coverage and a TRX report, plus a 6-way matrix that builds every service image and scans it with Trivy. No credentials, so it works on forks. |
| `docker-publish.yml` | push to `main`, `v*` tags | Builds the six images and pushes them to **ECR** tagged with the commit SHA (and `latest`), with Buildx GHA layer caching and a Trivy SARIF scan per image. |
| `deploy.yml` | after a successful publish, or manual | Rolling **ECS Fargate** deploy: re-renders each task definition onto the new image tag, one service at a time, waits for steady state, then smoke-tests `/health` through the gateway. Rollback is the same workflow with an older SHA. |
| `terraform.yml` | PR / push touching `infra/terraform/**` | `fmt -check` → `validate` → tflint → Trivy config scan → `plan` posted as a PR comment, then applies **that exact uploaded plan** on `main` behind a GitHub Environment reviewer gate. |

---

## Cloud infrastructure

`infra/terraform/` describes the AWS target environment in 13 `.tf` files, with S3 remote
state and native lockfile locking. The service topology lives in a single `locals.services`
map in `main.tf`; every ECR repository, log group, task definition, ECS service, Cloud Map
entry and alarm is generated from it, so adding a seventh microservice is one map entry.

| File | Resources |
|---|---|
| `vpc.tf` | VPC across 2 AZs, public/private subnets, IGW + NAT, three tiered security groups (ALB → tasks → data) |
| `ecs.tf` | Fargate cluster with Fargate Spot, per-service task definitions, Cloud Map service discovery, execution/task IAM roles, CPU target-tracking autoscaling, deployment circuit breaker |
| `alb.tf` | Public ALB; only `shopping-web` and `yarp-api-gateway` are internet-facing, the four services stay private |
| `ecr.tf` | One repository per service with lifecycle expiry |
| `rds.tf` | PostgreSQL for the Catalog/Basket document stores; SQL Server for Ordering behind `enable_sqlserver` (off by default — it is expensive to idle) |
| `elasticache.tf` | Redis replication group for the basket cache |
| `sqs.tf` | Amazon MQ for RabbitMQ (drop-in for the shipped MassTransit transport) **and** SNS → SQS with a dead-letter queue, the AWS-native target state |
| `secrets.tf` | Secrets Manager entries injected into tasks as container secrets |
| `observability.tf` | CloudWatch dashboard, log metric filter for slow requests, and alarms on CPU, zero running tasks, ALB 5xx and p99 latency, DLQ depth and queue age |
| `oidc.tf` | The GitHub OIDC provider and the deploy role the workflows assume |

```bash
cd infra/terraform
terraform init -backend-config=backend.hcl   # see backend.hcl.example
terraform plan
```

Nothing here is required to run the app locally — Docker Compose remains the development
path.

---

## Project structure

```
.
├── .github/workflows/                 # four pipelines, see CI/CD below
├── infra/terraform/                   # AWS environment as code, see Cloud infrastructure
├── global.json                        # pins the .NET 8 SDK band so local and CI agree
└── src/
    ├── eshop-microservices.sln        # 15 entries: 11 app projects, 3 test projects, docker-compose.dcproj
    ├── docker-compose.yml             # the 11 containers
    ├── docker-compose.override.yml    # connection strings, ports, broker credentials
    ├── ApiGateways/
    │   └── YarpApiGateway/            # YARP reverse proxy + rate limiting
    ├── BuildingBlocks/
    │   ├── BuildingBlocks/            # CQRS, behaviors, exceptions, pagination
    │   └── BuildingBlocks.Messaging/  # MassTransit config, integration events
    ├── Services/
    │   ├── Catalog/Catalog.API/       # Vertical Slice + CQRS
    │   ├── Basket/Basket.API/         # Vertical Slice + Redis cache-aside
    │   ├── Discount/Discount.Grpc/    # N-Layer gRPC service
    │   └── Ordering/                  # Clean Architecture + DDD
    │       ├── Ordering.Domain/
    │       ├── Ordering.Application/
    │       ├── Ordering.Infrastructure/
    │       └── Ordering.API/
    ├── WebApps/
    │   └── Shopping.Web/              # Razor Pages client
    └── tests/
        ├── BuildingBlocks.UnitTests/       # MediatR pipeline behaviors
        ├── Ordering.Domain.UnitTests/      # aggregate + value object invariants
        └── Shopping.Web.IntegrationTests/  # Refit clients against a stubbed gateway
```

---

## Roadmap

- Authentication and authorization (ASP.NET Core Identity / JWT). The UI currently
  assumes a fixed customer id
- Move local connection strings out of `appsettings.json` into user-secrets (the AWS path
  already pulls them from Secrets Manager)
- Switch `BuildingBlocks.Messaging` from `UsingRabbitMq` to `UsingAmazonSqs` so the SNS/SQS
  resources in `sqs.tf` become the messaging backbone
- Service-level API tests against real containers (Testcontainers), on top of the current
  domain and web-tier suites
- Structured logging and distributed tracing (Serilog, OpenTelemetry)
- Promote the Terraform stack to a production environment with a custom domain and TLS

---

## License

Licensed under the MIT License. See [LICENSE](LICENSE).
