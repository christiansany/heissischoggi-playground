var builder = WebApplication.CreateBuilder(args);

builder
    .AddGraphQL("assistance")
    .AddGlobalObjectIdentification()
    .AddAssistanceTypes();

var app = builder.Build();

app.MapGraphQL();
app.RunWithGraphQLCommands(args);
