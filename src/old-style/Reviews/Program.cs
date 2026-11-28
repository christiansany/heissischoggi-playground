var builder = WebApplication.CreateBuilder(args);

builder
    .AddGraphQL("reviews")
    .AddGlobalObjectIdentification()
    .AddQueryType()
    .AddType<Reviews.Product>();

var app = builder.Build();

app.MapGraphQL();
app.RunWithGraphQLCommands(args);
