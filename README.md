# Fusion: `@defer` fails with "No plan was found for the @defer fragment"

Minimal reproduction for a Hot Chocolate Fusion query-planner bug.

A deferred fragment cannot be planned when

- the parent field (`Query.productBySlug`) is served by **one** subgraph (`catalog`),
- every deferred field (`Product.name`) is served by that **same** subgraph, and
- a **second** subgraph (`reviews`) also has a lookup for the type (`Product`).

```graphql
query SlugDeferName {
  productBySlug(slug: "table") {
    id
    ... @defer(label: "A") {
      name
    }
  }
}
```

```
No plan was found for the @defer fragment at path '$.productBySlug'.
   at HotChocolate.Fusion.Planning.OperationPlanner.PlanIncrementalPlan(String operationId, IncrementalPlanDescriptor descriptor, Int32 incrementalPlanId, PlanningBudget budget, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Planning.OperationPlanner.RouteIncrementalPlans(String id, DeferSplitResult splitResult, PlanContextGraph contextGraph, PlanningBudget budget, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Planning.OperationPlanner.CreatePlan(String id, String hash, String shortHash, OperationDefinitionNode operationDefinition, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Execution.Pipeline.OperationPlanMiddleware.PlanOperation(RequestContext context, OperationDocumentInfo operationDocumentInfo, OperationDefinitionNode operation)
   at HotChocolate.Fusion.Execution.Pipeline.OperationPlanMiddleware.InvokeAsync(RequestContext context, RequestDelegate next)
```

Reproduced on **16.7.7** and **16.8.0-p.25** (.NET 10).

## Setup

| Project | Port | Schema |
|---|---|---|
| [src/Catalog](src/Catalog/Types.cs) | 5101 | [schema.graphqls](src/Catalog/schema.graphqls) |
| [src/Reviews](src/Reviews/Types.cs) | 5102 | [schema.graphqls](src/Reviews/schema.graphqls) |
| [src/Gateway](src/Gateway/Program.cs) | 5100 | [gateway.graphqls](src/Gateway/gateway.graphqls) (composed), `gateway.far` |

```graphql
# catalog
type Query {
  productById(id: Int!): Product @lookup @shareable
  productBySlug(slug: String!): Product
}
type Product @key(fields: "id") {
  id: Int!
  slug: String!
  name: String!
  description: String!
}

# reviews
type Query {
  productById(id: Int!): Product @lookup @shareable
}
type Product @key(fields: "id") {
  id: Int!
  rating: Float!
}
```

## Run it

Needs the .NET 10 SDK, `jq` and `curl`.

```sh
./scripts/repro.sh                        # 16.7.7
HC_VERSION=16.8.0-p.25 ./scripts/repro.sh # any other version
```

The script builds everything, exports the subgraph schemas, composes the gateway
with the Nitro CLI, starts all three services and sends every file in
[operations/](operations) to the gateway with the `Fusion-Operation-Plan: 1` header.
It does this for two compositions:

- `catalog+reviews`: the bug
- `catalog-only`: control, same services, `reviews` left out of the composition

Output goes to `results/<version>/<composition>/`:
`summary.txt`, `<operation>.response.txt` (raw response) and `<operation>.plan.json` (operation plan).

To poke at it by hand, start the three projects
(`dotnet run --no-launch-profile --urls http://localhost:<port>` in each `src/*` folder)
and open http://localhost:5100/graphql.

## Results (16.7.7, identical on 16.8.0-p.25)

| # | Operation | Deferred fields | `catalog+reviews` | `catalog-only` |
|---|---|---|---|---|
| 1 | [1-eager](operations/1-eager.graphql) | none | ok | ok |
| 2 | [2-slug-defer-name](operations/2-slug-defer-name.graphql) | `name` (catalog) | **No plan was found** | ok |
| 3 | [3-slug-defer-name-rating](operations/3-slug-defer-name-rating.graphql) | `name` (catalog), `rating` (reviews) | ok | n/a |
| 4 | [4-slug-defer-rating](operations/4-slug-defer-rating.graphql) | `rating` (reviews) | ok | n/a |
| 5 | [5-byid-defer-name](operations/5-byid-defer-name.graphql) | `name` (catalog), parent `productById` is in both subgraphs | ok | ok |

- Summaries: [catalog+reviews](results/16.7.7/catalog+reviews/summary.txt), [catalog-only](results/16.7.7/catalog-only/summary.txt)
- The error is thrown while planning, before any subgraph is called.
- Operation 2 only breaks once `reviews` is part of the composition, although `reviews` serves nothing the query asks for.

## Operation plans

Hashes removed for readability; the raw plans are in `results/`.
Operation 2 has no plan in `catalog+reviews`, since planning is the step that fails.

### Operation 2 in `catalog-only` (works): the plan that is expected

The deferred part is one lookup into `catalog` (`productById(id:)`), keyed by the `id` of the initial result.

```json
{
  "version": "1.2.0",
  "operation": {
    "name": "SlugDeferName",
    "kind": "Query",
    "document": "query SlugDeferName { productBySlug(slug: \"table\") { id id @fusion__requirement } }",
    "id": "817d579aa18b4ab66632b56574cd018a"
  },
  "searchSpace": 1,
  "expandedNodes": 1,
  "nodes": [
    {
      "id": 1,
      "type": "Operation",
      "schema": "catalog",
      "operation": {
        "name": "SlugDeferName_5fab490a_1",
        "kind": "Query",
        "document": "query SlugDeferName_5fab490a_1 { productBySlug(slug: \"table\") { id } }"
      },
      "resultSelectionSet": "{ productBySlug }"
    }
  ],
  "deliveryGroups": [
    {
      "id": 0,
      "path": "$.productBySlug",
      "label": "A"
    }
  ],
  "incrementalPlans": [
    {
      "deliveryGroupIds": [
        0
      ],
      "parentNodeId": 1,
      "requirements": [
        {
          "name": "__fusion_1_id",
          "type": "Int!",
          "path": "$.productBySlug",
          "selectionMap": "id"
        }
      ],
      "operation": {
        "name": "SlugDeferName",
        "kind": "Query",
        "document": "query SlugDeferName { productBySlug(slug: \"table\") { name id @fusion__requirement } }",
        "id": "817d579aa18b4ab66632b56574cd018a#defer_0"
      },
      "nodes": [
        {
          "id": 1,
          "type": "Operation",
          "schema": "catalog",
          "operation": {
            "name": "SlugDeferName_defer_1",
            "kind": "Query",
            "document": "query SlugDeferName_defer_1($__fusion_1_id: Int!) { productById(id: $__fusion_1_id) { name } }"
          },
          "lookupTypeName": "Product",
          "resultSelectionSet": "{ name }",
          "source": "$.productById",
          "target": "$.productBySlug",
          "requirements": [
            {
              "name": "__fusion_1_id",
              "type": "Int!",
              "path": "$.productBySlug",
              "selectionMap": "id"
            }
          ],
          "dependencies": [
            {
              "parentNodeId": 1
            }
          ]
        }
      ]
    }
  ]
}
```

### Operation 3 in `catalog+reviews` (works)

Contains the very same `catalog` lookup step for `name`. The planner finds it as soon as the fragment also selects a `reviews` field.

```json
{
  "version": "1.2.0",
  "operation": {
    "name": "SlugDeferNameRating",
    "kind": "Query",
    "document": "query SlugDeferNameRating { productBySlug(slug: \"table\") { id id @fusion__requirement } }",
    "id": "4d3b4ba5d7774e66c413fecddc4197aa"
  },
  "searchSpace": 1,
  "expandedNodes": 1,
  "nodes": [
    {
      "id": 1,
      "type": "Operation",
      "schema": "catalog",
      "operation": {
        "name": "SlugDeferNameRating_83e86e53_1",
        "kind": "Query",
        "document": "query SlugDeferNameRating_83e86e53_1 { productBySlug(slug: \"table\") { id } }"
      },
      "resultSelectionSet": "{ productBySlug }"
    }
  ],
  "deliveryGroups": [
    {
      "id": 0,
      "path": "$.productBySlug",
      "label": "A"
    }
  ],
  "incrementalPlans": [
    {
      "deliveryGroupIds": [
        0
      ],
      "parentNodeId": 1,
      "requirements": [
        {
          "name": "__fusion_1_id",
          "type": "Int!",
          "path": "$.productBySlug",
          "selectionMap": "id"
        },
        {
          "name": "__fusion_2_id",
          "type": "Int!",
          "path": "$.productBySlug",
          "selectionMap": "id"
        }
      ],
      "operation": {
        "name": "SlugDeferNameRating",
        "kind": "Query",
        "document": "query SlugDeferNameRating { productBySlug(slug: \"table\") { name rating id @fusion__requirement } }",
        "id": "4d3b4ba5d7774e66c413fecddc4197aa#defer_0"
      },
      "nodes": [
        {
          "id": 1,
          "type": "Operation",
          "schema": "reviews",
          "operation": {
            "name": "SlugDeferNameRating_defer_1",
            "kind": "Query",
            "document": "query SlugDeferNameRating_defer_1($__fusion_1_id: Int!) { productById(id: $__fusion_1_id) { rating } }"
          },
          "lookupTypeName": "Product",
          "resultSelectionSet": "{ rating }",
          "source": "$.productById",
          "target": "$.productBySlug",
          "requirements": [
            {
              "name": "__fusion_1_id",
              "type": "Int!",
              "path": "$.productBySlug",
              "selectionMap": "id"
            }
          ],
          "dependencies": [
            {
              "parentNodeId": 1
            }
          ]
        },
        {
          "id": 2,
          "type": "Operation",
          "schema": "catalog",
          "operation": {
            "name": "SlugDeferNameRating_defer_2",
            "kind": "Query",
            "document": "query SlugDeferNameRating_defer_2($__fusion_2_id: Int!) { productById(id: $__fusion_2_id) { name } }"
          },
          "lookupTypeName": "Product",
          "resultSelectionSet": "{ name }",
          "source": "$.productById",
          "target": "$.productBySlug",
          "requirements": [
            {
              "name": "__fusion_2_id",
              "type": "Int!",
              "path": "$.productBySlug",
              "selectionMap": "id"
            }
          ],
          "dependencies": [
            {
              "parentNodeId": 1
            }
          ]
        }
      ]
    }
  ]
}
```

### Operation 5 in `catalog+reviews` (works)

```json
{
  "version": "1.2.0",
  "operation": {
    "name": "ByIdDeferName",
    "kind": "Query",
    "document": "query ByIdDeferName { productById(id: 1) { id } }",
    "id": "eea33d0cb174711a4b6a045eace682fd"
  },
  "searchSpace": 2,
  "expandedNodes": 2,
  "nodes": [
    {
      "id": 1,
      "type": "Operation",
      "schema": "catalog",
      "operation": {
        "name": "ByIdDeferName_9550e797_1",
        "kind": "Query",
        "document": "query ByIdDeferName_9550e797_1 { productById(id: 1) { id } }"
      },
      "resultSelectionSet": "{ productById }"
    },
    {
      "id": 2,
      "type": "Operation",
      "schema": "reviews",
      "operation": {
        "name": "ByIdDeferName_defer_2",
        "kind": "Query",
        "document": "query ByIdDeferName_defer_2 { productById(id: 1) { id } }"
      },
      "resultSelectionSet": "{ productById }"
    }
  ],
  "deliveryGroups": [
    {
      "id": 0,
      "path": "$.productById",
      "label": "A"
    }
  ],
  "incrementalPlans": [
    {
      "deliveryGroupIds": [
        0
      ],
      "parentNodeId": 1,
      "requirements": [
        {
          "name": "__fusion_1_id",
          "type": "Int!",
          "path": "$.productById",
          "selectionMap": "id"
        }
      ],
      "operation": {
        "name": "ByIdDeferName",
        "kind": "Query",
        "document": "query ByIdDeferName { productById(id: 1) { name id @fusion__requirement } }",
        "id": "eea33d0cb174711a4b6a045eace682fd#defer_0"
      },
      "nodes": [
        {
          "id": 1,
          "type": "Operation",
          "schema": "catalog",
          "operation": {
            "name": "ByIdDeferName_defer_1",
            "kind": "Query",
            "document": "query ByIdDeferName_defer_1($__fusion_1_id: Int!) { productById(id: $__fusion_1_id) { name } }"
          },
          "lookupTypeName": "Product",
          "resultSelectionSet": "{ name }",
          "source": "$.productById",
          "target": "$.productById",
          "requirements": [
            {
              "name": "__fusion_1_id",
              "type": "Int!",
              "path": "$.productById",
              "selectionMap": "id"
            }
          ],
          "dependencies": [
            {
              "parentNodeId": 2
            }
          ]
        }
      ]
    }
  ]
}
```

## Expected

Operation 2 is planned in `catalog+reviews` exactly like in `catalog-only`:
initial step `productBySlug { id }` in `catalog`, deferred step `productById(id:) { name }` in `catalog`.

The issue text for the Hot Chocolate repository is in [ISSUE.md](ISSUE.md).
