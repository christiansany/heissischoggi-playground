<!-- Title: Fusion: "No plan was found for the @defer fragment" when deferred fields come from the same subgraph as the parent field -->

**Product:** Hot Chocolate (Fusion)

**Version:** 16.7.7 (also 16.8.0-p.25)

**Link to minimal reproduction:** https://github.com/christiansany/heissischoggi-playground

### Steps to reproduce

1. Clone the repository above (.NET 10 SDK, `jq`, `curl`).
2. Run `./scripts/repro.sh` (or `HC_VERSION=16.8.0-p.25 ./scripts/repro.sh`).
3. See `results/<version>/catalog+reviews/summary.txt`.

Two source schemas:

```graphql
# catalog
type Query {
  productById(id: Int!): Product @lookup @shareable
  productBySlug(slug: String!): Product
}
type Product @key(fields: "id") {
  id: Int!
  name: String!
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

Operation sent to the gateway:

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

### What is expected?

The operation is planned and the deferred part is delivered incrementally:
initial step `productBySlug { id }` in `catalog`, deferred step `productById(id:) { name }` in `catalog`.

That is the plan the gateway produces when `reviews` is left out of the composition
(`results/16.7.7/catalog-only/2-slug-defer-name.plan.json` in the repro).

### What is actually happening?

Planning fails with `No plan was found for the @defer fragment at path '$.productBySlug'`. No subgraph is called.

In the repro all of these hold:

- the parent field (`productBySlug`) is served by one subgraph only,
- every deferred field is served by that same subgraph,
- another subgraph also has a lookup for the type.

| Operation (`catalog` + `reviews` composed) | Result |
|---|---|
| `productBySlug { id name }` | ok |
| `productBySlug { id ... @defer { name } }` | **No plan was found** |
| `productBySlug { id ... @defer { name rating } }` | ok, deferred |
| `productBySlug { id ... @defer { rating } }` | ok, deferred |
| `productById(id: 1) { id ... @defer { name } }` | ok, deferred |
| `productBySlug { id ... @defer { name } }` with only `catalog` composed | ok, deferred |

### Relevant log output

```
No plan was found for the @defer fragment at path '$.productBySlug'.
   at HotChocolate.Fusion.Planning.OperationPlanner.PlanIncrementalPlan(String operationId, IncrementalPlanDescriptor descriptor, Int32 incrementalPlanId, PlanningBudget budget, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Planning.OperationPlanner.RouteIncrementalPlans(String id, DeferSplitResult splitResult, PlanContextGraph contextGraph, PlanningBudget budget, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Planning.OperationPlanner.CreatePlan(String id, String hash, String shortHash, OperationDefinitionNode operationDefinition, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Execution.Pipeline.OperationPlanMiddleware.PlanOperation(RequestContext context, OperationDocumentInfo operationDocumentInfo, OperationDefinitionNode operation)
   at HotChocolate.Fusion.Execution.Pipeline.OperationPlanMiddleware.InvokeAsync(RequestContext context, RequestDelegate next)
```

### Additional context

<details>
<summary>Plan of the working variant <code>... @defer { name rating }</code>: it contains the catalog lookup the failing operation needs</summary>

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

</details>

<details>
<summary>Plan of the failing operation when only <code>catalog</code> is composed (expected plan)</summary>

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

</details>

- All plans, raw responses and the composed schema are in the repro repository.
- Found in a production-sized gateway (about 30 source schemas) on 16.7.6, where it blocks `@defer` for most fragments under a field that a single source schema owns.
- I have not root-caused it. `PlanQueue.EnqueueLookupPlanNodes` looks like the place where the lookup for the defer anchor is chosen.
