[assembly: Module("CatalogTypes")]

namespace Catalog;

public sealed record Product(int Id, string Slug, string Name, string Description);

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
    // Served by BOTH subgraphs (catalog + reviews).
    [Lookup, Shareable]
    public static Product? GetProductById(int id) => ProductRepository.GetById(id);

    // Served ONLY by the catalog subgraph.
    public static Product? GetProductBySlug(string slug) => ProductRepository.GetBySlug(slug);
}
