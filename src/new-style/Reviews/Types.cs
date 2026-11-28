[assembly: Module("ReviewsTypes")]

namespace Reviews;

// Entity stub: the reviews subgraph only knows a product by its id.
public sealed record Product(int Id)
{
    public double GetRating() => Id == 1 ? 4.5 : 3.0;
}

[QueryType]
public static partial class ProductQueries
{
    // Served by BOTH subgraphs (catalog + reviews).
    [Lookup, Shareable]
    public static Product? GetProductById(int id) => new(id);
}
