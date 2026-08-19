using Refit;
using Shopping.Web.Services;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;

namespace Shopping.Web.IntegrationTests;

/// <summary>
/// Contract tests for <see cref="ICatalogService"/> against a stubbed gateway.
///
/// What these actually protect: the "/catalog-service" path prefix that YARP strips via
/// its PathPattern transform. If someone edits the Refit template or the gateway route in
/// isolation, the two halves stop lining up -- and that only shows up at runtime as a 404
/// unless a test pins it.
/// </summary>
public class CatalogServiceWireMockTests : IClassFixture<WireMockGatewayFixture>
{
    private readonly WireMockGatewayFixture _gateway;
    private readonly ICatalogService _catalog;

    public CatalogServiceWireMockTests(WireMockGatewayFixture gateway)
    {
        _gateway = gateway;
        _gateway.Reset();
        _catalog = RestService.For<ICatalogService>(_gateway.GatewayUrl);
    }

    [Fact]
    public async Task GetProducts_deserialises_the_catalog_payload()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/catalog-service/products").UsingGet())
            .RespondWith(Response.Create()
                .WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""
                {
                  "products": [
                    { "id": "5334c996-8457-4cf0-815c-ed2b77c4ff61",
                      "name": "IPhone X",
                      "category": ["Smart Phone"],
                      "description": "A great phone",
                      "imageFile": "product-1.png",
                      "price": 950.00 }
                  ]
                }
                """));

        var response = await _catalog.GetProducts();

        var product = response.Products.Should().ContainSingle().Subject;
        product.Name.Should().Be("IPhone X");
        product.Price.Should().Be(950.00m);
        product.Category.Should().ContainSingle().Which.Should().Be("Smart Phone");
    }

    [Fact]
    public async Task GetProducts_calls_the_gateway_prefixed_path_with_pagination_query()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/catalog-service/products").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""{"products":[]}"""));

        await _catalog.GetProducts(pageNumber: 2, pageSize: 25);

        var request = _gateway.Server.LogEntries.Should().ContainSingle().Subject;
        request.RequestMessage.Path.Should().Be("/catalog-service/products");
        request.RequestMessage.Query!["pageNumber"].Should().Contain("2");
        request.RequestMessage.Query!["pageSize"].Should().Contain("25");
    }

    [Fact]
    public async Task GetProduct_substitutes_the_id_into_the_route_template()
    {
        var id = Guid.Parse("5334c996-8457-4cf0-815c-ed2b77c4ff61");

        _gateway.Server
            .Given(Request.Create().WithPath($"/catalog-service/products/{id}").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""
                {"product":{"id":"__ID__","name":"IPhone X","category":["Smart Phone"],
                 "description":"d","imageFile":"f.png","price":950.00}}
                """.Replace("__ID__", id.ToString())));

        var response = await _catalog.GetProduct(id);

        response.Product.Id.Should().Be(id);
    }

    [Fact]
    public async Task GetProductsByCategory_hits_the_category_route()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/catalog-service/products/category/Smart Phone").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""{"products":[]}"""));

        var response = await _catalog.GetProductsByCategory("Smart Phone");

        response.Products.Should().BeEmpty();
    }

    [Fact]
    public async Task A_gateway_500_surfaces_to_the_caller_as_an_ApiException()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/catalog-service/products").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(500));

        var act = async () => await _catalog.GetProducts();

        // Documents today's behaviour: there is no retry or circuit breaker on this
        // client, so a downstream fault propagates straight to the Razor page.
        var thrown = await act.Should().ThrowAsync<ApiException>();
        thrown.Which.StatusCode.Should().Be(System.Net.HttpStatusCode.InternalServerError);
    }
}
