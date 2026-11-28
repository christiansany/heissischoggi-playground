# Fusion: `@defer` fails with "No plan was found for the @defer fragment"

Minimal reproduction for a Hot Chocolate Fusion query-planner bug.
Tested with the Hot Chocolate packages 16.7.7 and 16.8.0-p.25 (target framework .NET 10); the composition is always done by the Nitro CLI 16.7.7.

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

The response is HTTP 200 with the error `Unexpected Execution Error`. Its `extensions.exception` (the gateway runs with `IncludeExceptionDetails`) is:

```
No plan was found for the @defer fragment at path '$.productBySlug'.
   at HotChocolate.Fusion.Planning.OperationPlanner.PlanIncrementalPlan(String operationId, IncrementalPlanDescriptor descriptor, Int32 incrementalPlanId, PlanningBudget budget, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Planning.OperationPlanner.RouteIncrementalPlans(String id, DeferSplitResult splitResult, PlanContextGraph contextGraph, PlanningBudget budget, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Planning.OperationPlanner.CreatePlan(String id, String hash, String shortHash, OperationDefinitionNode operationDefinition, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Execution.Pipeline.OperationPlanMiddleware.PlanOperation(RequestContext context, OperationDocumentInfo operationDocumentInfo, OperationDefinitionNode operation)
   ... (6 more frames, see results/16.7.7/new-style/catalog+reviews/2-slug-defer-name.response.txt)
```

In this repro the operation fails when all of this is true:

- the parent field (`Query.productBySlug`) is served by one subgraph only (`catalog`),
- every deferred field (`Product.name`) is served by that same subgraph,
- a second subgraph (`reviews`) also contributes to the type (`Product`).

The same operation works when only `catalog` is composed.

## Two styles, same bug

The repo contains the subgraphs in two styles. Both show the bug.

| | [new-style](src/new-style) | [old-style](src/old-style) |
|---|---|---|
| Subgraphs | `catalog`, `reviews` | `catalog`, `reviews`, `assistance` |
| Entity resolution | `[Lookup]` on `productById` | `[NodeResolver]` / `Node` interface, no composition attributes |
| Source schema | `@lookup`, `@key`, `@shareable` | no composition directives |
| `schema-settings.json` | as exported | as exported, plus `"version": "1.0.0"`: the composition then infers the lookups and keys |
| Composition | default | `--enable-global-object-identification` |
| `productById` served by | `catalog`, `reviews` | `catalog`, `assistance` |
| `reviews` reaches `Product` by | `productById(id:)` | `node(id:)` only |
| `id` type | `Int!` | `ID!` |

In both styles `scripts/compose.sh` rewrites the port in the exported `schema-settings.json`.

Source schemas as exported by `schema export`, shortened: `schema { ... }`, scalar and directive definitions, descriptions and `@cost` are left out.

```graphql
# new-style catalog                                # new-style reviews
type Query {                                       type Query {
  productById(id: Int!): Product                     productById(id: Int!): Product
    @shareable @lookup                                 @shareable @lookup
  productBySlug(slug: String!): Product            }
}
type Product @key(fields: "id") {                  type Product @key(fields: "id") {
  id: Int!                                           rating: Float!
  name: String!                                      id: Int!
  description: String!                             }
}
```

```graphql
# old-style catalog                                # old-style reviews
type Query {                                       type Query {
  node(id: ID!): Node                                node(id: ID!): Node
  nodes(ids: [ID!]!): [Node]!                        nodes(ids: [ID!]!): [Node]!
  productById(id: ID!): Product                    }
  productBySlug(slug: String!): Product
}
type Product implements Node {                     type Product implements Node {
  id: ID!                                            rating: Float!
  name: String!                                      id: ID!
  description: String!                             }
}
interface Node { id: ID! }                         interface Node { id: ID! }

# old-style assistance
type Query {
  node(id: ID!): Node
  nodes(ids: [ID!]!): [Node]!
  productById(id: ID!): Product
}
type Product implements Node {
  id: ID!
}
interface Node { id: ID! }
```

Full files: `src/<style>/<Subgraph>/schema.graphqls`. Composed schema per run: `results/<version>/<style>/<composition>/gateway.graphqls`.

## Run it

Builds against `net10.0`. Needs a .NET SDK that can build that (10 or newer), `jq`, `curl` and `unzip`.

```sh
./scripts/repro.sh                        # Hot Chocolate 16.7.7
HC_VERSION=16.8.0-p.25 ./scripts/repro.sh # other package version
```

For each style the script builds the projects, exports the subgraph schemas, composes the
gateway with the Nitro CLI, starts the services (gateway 5100, catalog 5101, reviews 5102, assistance 5103) and sends
every file in `operations/<style>/` to the gateway with the `Fusion-Operation-Plan: 1` header.
It does that for these compositions:

- `catalog-only`: control
- `catalog+reviews`: shows the bug
- `catalog+reviews+assistance`: old-style only

Output in `results/<version>/`:

- `REPORT.md`: every operation with its result per composition, and the operation plan (JSON) wherever the gateway produced one
- `<style>/<composition>/summary.txt`, `<operation>.response.txt` (raw response), `<operation>.plan.json` (raw plan)

## Results

Outcomes and plans are the same with 16.7.7 and 16.8.0-p.25; only the plan format `version` field differs (`1.2.0` / `1.4.0`).
Full reports: [16.7.7](results/16.7.7/REPORT.md), [16.8.0-p.25](results/16.8.0-p.25/REPORT.md).

- **deferred**: answered in two parts
- **n/a**: the operation selects `rating`, which does not exist without `reviews` (validation error)

### new-style

| # | Operation | `catalog-only` | `catalog+reviews` |
|---|---|---|---|
| 1 | [`productBySlug { id name }`](operations/new-style/1-eager.graphql) | ok | ok |
| 2 | [`productBySlug { id ... @defer { name } }`](operations/new-style/2-slug-defer-name.graphql) | deferred | **No plan was found** |
| 3 | [`productBySlug { id ... @defer { name rating } }`](operations/new-style/3-slug-defer-name-rating.graphql) | n/a | deferred |
| 4 | [`productBySlug { id ... @defer { rating } }`](operations/new-style/4-slug-defer-rating.graphql) | n/a | deferred |
| 5 | [`productById(id:) { id ... @defer { name } }`](operations/new-style/5-byid-defer-name.graphql) | deferred | deferred |

### old-style

| # | Operation | `catalog-only` | `catalog+reviews` | `catalog+reviews+assistance` |
|---|---|---|---|---|
| 1 | [`productBySlug { id name }`](operations/old-style/1-eager.graphql) | ok | ok | ok |
| 2 | [`productBySlug { id ... @defer { name } }`](operations/old-style/2-slug-defer-name.graphql) | deferred | **No plan was found** | **No plan was found** |
| 3 | [`productBySlug { id ... @defer { name rating } }`](operations/old-style/3-slug-defer-name-rating.graphql) | n/a | deferred | deferred |
| 4 | [`productBySlug { id ... @defer { rating } }`](operations/old-style/4-slug-defer-rating.graphql) | n/a | deferred | deferred |
| 5 | [`productById(id:) { id ... @defer { name } }`](operations/old-style/5-byid-defer-name.graphql) | deferred | **No plan was found** | deferred |
| 6 | [`node(id:) { ... on Product { id ... @defer { name } } }`](operations/old-style/6-node-defer-name.graphql) | deferred | deferred | deferred |

What the tables show:

- Operation 2 fails in both styles as soon as a second subgraph is composed.
- Operation 5 fails only where `productById` is served by `catalog` alone while another subgraph contributes to `Product` (old-style `catalog+reviews`). Where a second subgraph serves `productById` it works.
- Operation 3 works. Its plan fetches `name` with a deferred lookup step in `catalog` (`productById(id:) { name }`), keyed by the `id` of the initial step. Operation 2 would need exactly such a step.
- The error is thrown while planning, so the failing operations have no operation plan.
- Side observation: in the new-style `catalog+reviews` plan of operation 5, the initial part has a second step in `reviews` (`productById(id: 1) { id }`), and the deferred `catalog` step depends on that one. The `catalog-only` plan has no such step.

## Expected

Operation 2 is planned with further subgraphs composed the same way it is planned in `catalog-only`:
an initial step in `catalog`, then one deferred lookup step in `catalog` that fetches `name` by the product's `id`
(`productById(id:)` in new-style, `node(id:)` in old-style). Those plans are in `REPORT.md` under `catalog-only`.

The issue text for the Hot Chocolate repository is in [ISSUE.md](ISSUE.md).
