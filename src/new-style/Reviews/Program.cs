var builder = WebApplication.CreateBuilder(args);

builder
    .AddGraphQL("reviews")
    .AddReviewsTypes();

var app = builder.Build();

app.MapGraphQL();
app.RunWithGraphQLCommands(args);
