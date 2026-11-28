namespace Reviews;

// Entity stub: the reviews subgraph only knows a product by its id.
// It has no `productById` field; the gateway reaches it through `node(id:)`.
[Node]
public sealed record Product(int Id)
{
    public double GetRating() => Id == 1 ? 4.5 : 3.0;

    [NodeResolver]
    public static Product? Get(int id) => new(id);
}

