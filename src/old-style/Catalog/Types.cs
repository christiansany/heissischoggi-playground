[assembly: Module("CatalogTypes")]

namespace Catalog;

// `slug` is not a field of Product, so `productBySlug` is a plain query field and not a lookup.
public sealed record Product(int Id, [property: GraphQLIgnore] string Slug, string Name, string Description);

public static class ProductRepository
{
    private static readonly Product[] s_products =
    [
        new(1, "table", "Table", "A sturdy table."),
        new(2, "couch", "Couch", "A comfy couch.")
    ];

    public static Product? GetById(int id) => s_products.FirstOrDefault(p => p.Id == id);

    public static Product? GetBySlug(string slug) => s_products.FirstOrDefault(p => p.Slug == slug);
}

[QueryType]
public static partial class ProductQueries
{
    // Node resolver: `Product implements Node`, reachable through `node(id:)` and `productById(id:)`.
    // No [Lookup]: the composition infers the lookup (source schema settings version 1.0.0).
    [NodeResolver]
    public static Product? GetProductById(int id) => ProductRepository.GetById(id);

    // Served ONLY by the catalog subgraph.
    public static Product? GetProductBySlug(string slug) => ProductRepository.GetBySlug(slug);
}
