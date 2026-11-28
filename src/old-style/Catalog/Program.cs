var builder = WebApplication.CreateBuilder(args);

builder
    .AddGraphQL("catalog")
    .AddGlobalObjectIdentification()
    .AddCatalogTypes();

var app = builder.Build();

app.MapGraphQL();
app.RunWithGraphQLCommands(args);
