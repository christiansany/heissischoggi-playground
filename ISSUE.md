<!-- Title: Fusion: "No plan was found for the @defer fragment" when the deferred fields and the parent field come from the same single subgraph -->

**Product:** Hot Chocolate (Fusion)

**Version:** 16.7.7 (also 16.8.0-p.25)

**Link to minimal reproduction:** https://github.com/christiansany/heissischoggi-playground

### Steps to reproduce

1. Clone the repository above (.NET SDK 10 or newer, `jq`, `curl`, `unzip`).
2. Run `./scripts/repro.sh` (or `HC_VERSION=16.8.0-p.25 ./scripts/repro.sh`).
3. Open `results/<version>/REPORT.md`.

Two source schemas (the "new-style" variant of the repro, shortened):

```graphql
# catalog
type Query {
  productById(id: Int!): Product @shareable @lookup
  productBySlug(slug: String!): Product
}
type Product @key(fields: "id") {
  id: Int!
  name: String!
}

# reviews
type Query {
  productById(id: Int!): Product @shareable @lookup
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
an initial step `productBySlug { id }` in `catalog`, then a deferred step `productById(id:) { name }` in `catalog`.

That is the plan the gateway produces for the same operation when only `catalog` is composed.

### What is actually happening?

Planning fails with `No plan was found for the @defer fragment at path '$.productBySlug'`.

In the repro the failing case has these properties:

- the parent field (`productBySlug`) is served by one subgraph only,
- every deferred field is served by that same subgraph,
- a second subgraph also contributes to the type.

| Operation | `catalog` only | `catalog` + `reviews` |
|---|---|---|
| `productBySlug { id name }` | ok | ok |
| `productBySlug { id ... @defer { name } }` | ok, deferred | **No plan was found** |
| `productBySlug { id ... @defer { name rating } }` | n/a (no `rating`) | ok, deferred |
| `productBySlug { id ... @defer { rating } }` | n/a (no `rating`) | ok, deferred |
| `productById(id: 1) { id ... @defer { name } }` | ok, deferred | ok, deferred |

The repro also contains an "old-style" variant, which is how our production source schemas look: `Node` interface and `[NodeResolver]`, no composition directives, source schema settings `"version": "1.0.0"`, composed with `--enable-global-object-identification`. `productBySlug { id ... @defer { name } }` fails there the same way. `productById(id:) { id ... @defer { name } }` fails there too while `catalog` is the only subgraph serving `productById`, and works once another subgraph serves it as well.

### Relevant log output

The response is HTTP 200 with the error `Unexpected Execution Error`; this is its `extensions.exception`:

```
No plan was found for the @defer fragment at path '$.productBySlug'.
   at HotChocolate.Fusion.Planning.OperationPlanner.PlanIncrementalPlan(String operationId, IncrementalPlanDescriptor descriptor, Int32 incrementalPlanId, PlanningBudget budget, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Planning.OperationPlanner.RouteIncrementalPlans(String id, DeferSplitResult splitResult, PlanContextGraph contextGraph, PlanningBudget budget, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Planning.OperationPlanner.CreatePlan(String id, String hash, String shortHash, OperationDefinitionNode operationDefinition, CancellationToken cancellationToken)
   at HotChocolate.Fusion.Execution.Pipeline.OperationPlanMiddleware.PlanOperation(RequestContext context, OperationDocumentInfo operationDocumentInfo, OperationDefinitionNode operation)
   ... (6 more frames, see results/16.7.7/new-style/catalog+reviews/2-slug-defer-name.response.txt)
```

### Additional context

- Results for every operation and composition, with the operation plans (JSON) of all operations that could be planned: `results/16.7.7/REPORT.md` in the repro.
- The plan of the working `... @defer { name rating }` operation contains the kind of step the failing operation needs: a deferred `productById(id:) { name }` in `catalog`.
- The 16.8.0-p.25 run uses an archive composed by the Nitro CLI 16.7.7.
- Found on a production gateway (old-style source schemas) on 16.7.6.
- Not root-caused.
