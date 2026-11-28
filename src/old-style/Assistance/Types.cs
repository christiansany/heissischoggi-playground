[assembly: Module("AssistanceTypes")]

namespace Assistance;

// Entity stub: this subgraph serves `productById`, but knows nothing about a
// product except its id.
public sealed record Product(int Id);

[QueryType]
public static partial class ProductQueries
{
    [NodeResolver]
    public static Product? GetProductById(int id) => new(id);
}
