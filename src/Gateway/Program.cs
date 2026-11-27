var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpClient("fusion");

builder
    .AddGraphQLGateway()
    .AddFileSystemConfiguration("./gateway.far")
    .ModifyRequestOptions(o =>
    {
        // Returns the plan in `extensions.fusion.operationPlan` when the
        // request carries the `Fusion-Operation-Plan: 1` header.
        o.AllowOperationPlanRequests = true;
        o.IncludeExceptionDetails = true;
    });

var app = builder.Build();

app.MapGraphQL();
app.Run();
