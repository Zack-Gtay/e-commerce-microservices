using Refit;
using Shopping.Web.Services;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;

namespace Shopping.Web.IntegrationTests;

/// <summary>
/// Contract tests for <see cref="IOrderingService"/>.
///
/// <para>
/// Regression guard: the GetOrders template used to end in an escaped quote
/// (<c>...pageSize={pageSize}\"</c>), which appended a literal <c>"</c> to the query
/// string and made Ordering.API fail to bind pageSize. The
/// <see cref="GetOrders_sends_a_clean_query_string_with_no_trailing_characters"/> test
/// pins the corrected template so it cannot silently come back.
/// </para>
/// </summary>
public class OrderingServiceWireMockTests : IClassFixture<WireMockGatewayFixture>
{
    private readonly WireMockGatewayFixture _gateway;
    private readonly IOrderingService _ordering;

    public OrderingServiceWireMockTests(WireMockGatewayFixture gateway)
    {
        _gateway = gateway;
        _gateway.Reset();
        _ordering = RestService.For<IOrderingService>(_gateway.GatewayUrl);
    }

    private const string EmptyPage = """
    {"orders":{"pageIndex":0,"pageSize":10,"count":0,"data":[]}}
    """;

    [Fact]
    public async Task GetOrders_sends_a_clean_query_string_with_no_trailing_characters()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/ordering-service/orders").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody(EmptyPage));

        await _ordering.GetOrders(pageIndex: 0, pageSize: 10);

        var request = _gateway.Server.LogEntries.Should().ContainSingle().Subject;

        request.RequestMessage.Path.Should().Be("/ordering-service/orders");
        request.RequestMessage.Query!["pageSize"].Should().ContainSingle()
            .Which.Should().Be("10", "a stray character here breaks model binding in Ordering.API");
        request.RequestMessage.Query!["pageIndex"].Should().ContainSingle().Which.Should().Be("0");
        request.RequestMessage.RawQuery.Should().NotContain("\"");
    }

    [Fact]
    public async Task GetOrders_deserialises_the_paginated_envelope()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/ordering-service/orders").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""
                {
                  "orders": {
                    "pageIndex": 0,
                    "pageSize": 10,
                    "count": 1,
                    "data": [
                      {
                        "id": "8d3b1c4e-0000-4000-8000-000000000001",
                        "customerId": "8d3b1c4e-0000-4000-8000-000000000002",
                        "orderName": "ORD-1",
                        "shippingAddress": { "firstName":"Z","lastName":"E","emailAddress":"z@example.com",
                          "addressLine":"12 Rue Mohammed V","country":"Morocco","state":"Casablanca","zipCode":"20000" },
                        "billingAddress": { "firstName":"Z","lastName":"E","emailAddress":"z@example.com",
                          "addressLine":"12 Rue Mohammed V","country":"Morocco","state":"Casablanca","zipCode":"20000" },
                        "payment": { "cardName":"Z E","cardNumber":"5555444433332222",
                          "expiration":"12/28","cvv":"123","paymentMethod":1 },
                        "status": 2,
                        "orderItems": [
                          { "orderId":"8d3b1c4e-0000-4000-8000-000000000001",
                            "productId":"8d3b1c4e-0000-4000-8000-000000000003",
                            "quantity":2, "price":500.00 }
                        ]
                      }
                    ]
                  }
                }
                """));

        var response = await _ordering.GetOrders();

        response.Orders.Count.Should().Be(1);
        var order = response.Orders.Data.Should().ContainSingle().Subject;
        order.OrderName.Should().Be("ORD-1");
        order.Status.Should().Be(Shopping.Web.Models.Ordering.OrderStatus.Pending);
        order.OrderItems.Should().ContainSingle().Which.Price.Should().Be(500.00m);
    }

    [Fact]
    public async Task GetOrdersByCustomer_substitutes_the_customer_id()
    {
        var customerId = Guid.Parse("8d3b1c4e-0000-4000-8000-000000000002");

        _gateway.Server
            .Given(Request.Create().WithPath($"/ordering-service/orders/customer/{customerId}").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""{"orders":[]}"""));

        var response = await _ordering.GetOrdersByCustomer(customerId);

        response.Orders.Should().BeEmpty();
    }

    [Fact]
    public async Task GetOrdersByName_hits_the_name_route()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/ordering-service/orders/ORD-1").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""{"orders":[]}"""));

        var response = await _ordering.GetOrdersByName("ORD-1");

        response.Orders.Should().BeEmpty();
    }

    [Fact]
    public async Task A_404_from_ordering_surfaces_as_an_ApiException()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/ordering-service/orders/UNKNOWN").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(404));

        var act = async () => await _ordering.GetOrdersByName("UNKNOWN");

        await act.Should().ThrowAsync<ApiException>();
    }
}
