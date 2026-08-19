using Refit;
using Shopping.Web.Services;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;

namespace Shopping.Web.IntegrationTests;

/// <summary>
/// Contract tests for <see cref="IBasketService"/>.
///
/// The interesting one is <see cref="IBasketService.LoadUserBasket"/> -- a default
/// interface method holding the only piece of graceful degradation in the whole solution
/// (a 404 from Basket becomes an empty cart rather than an error page). WireMock is the
/// right tool for that: the behaviour is defined entirely by the downstream status code,
/// which is awkward to trigger any other way.
/// </summary>
public class BasketServiceWireMockTests : IClassFixture<WireMockGatewayFixture>
{
    private const string DefaultUser = "swn";

    private readonly WireMockGatewayFixture _gateway;
    private readonly IBasketService _basket;

    public BasketServiceWireMockTests(WireMockGatewayFixture gateway)
    {
        _gateway = gateway;
        _gateway.Reset();
        _basket = RestService.For<IBasketService>(_gateway.GatewayUrl);
    }

    [Fact]
    public async Task LoadUserBasket_returns_an_empty_cart_when_the_basket_does_not_exist()
    {
        _gateway.Server
            .Given(Request.Create().WithPath($"/basket-service/basket/{DefaultUser}").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(404));

        var cart = await _basket.LoadUserBasket();

        cart.UserName.Should().Be(DefaultUser);
        cart.Items.Should().BeEmpty();
        cart.TotalPrice.Should().Be(0m);
    }

    [Fact]
    public async Task LoadUserBasket_returns_the_stored_cart_when_one_exists()
    {
        _gateway.Server
            .Given(Request.Create().WithPath($"/basket-service/basket/{DefaultUser}").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""
                {
                  "cart": {
                    "userName": "swn",
                    "items": [
                      { "quantity": 2, "color": "Black", "price": 500.00,
                        "productId": "5334c996-8457-4cf0-815c-ed2b77c4ff61",
                        "productName": "IPhone X" }
                    ]
                  }
                }
                """));

        var cart = await _basket.LoadUserBasket();

        cart.Items.Should().ContainSingle().Which.ProductName.Should().Be("IPhone X");
        cart.TotalPrice.Should().Be(1000.00m); // computed client-side: 2 * 500
    }

    [Fact]
    public async Task LoadUserBasket_does_not_swallow_a_500()
    {
        _gateway.Server
            .Given(Request.Create().WithPath($"/basket-service/basket/{DefaultUser}").UsingGet())
            .RespondWith(Response.Create().WithStatusCode(500));

        var act = async () => await _basket.LoadUserBasket();

        // Only 404 is treated as "no basket yet". Everything else must surface, otherwise
        // a broken Basket service would silently look like an empty cart to every user.
        await act.Should().ThrowAsync<ApiException>();
    }

    [Fact]
    public async Task StoreBasket_posts_the_cart_to_the_basket_route()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/basket-service/basket").UsingPost())
            .RespondWith(Response.Create().WithStatusCode(201)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""{"userName":"swn"}"""));

        var response = await _basket.StoreBasket(new StoreBasketRequest(new ShoppingCartModel
        {
            UserName = DefaultUser,
            Items = [new ShoppingCartItemModel { Quantity = 1, Price = 10m, ProductName = "IPhone X" }]
        }));

        response.UserName.Should().Be(DefaultUser);

        var request = _gateway.Server.LogEntries.Should().ContainSingle().Subject;
        request.RequestMessage.Method.Should().Be("POST");
        request.RequestMessage.Body.Should().Contain("IPhone X");
    }

    [Fact]
    public async Task CheckoutBasket_posts_to_the_checkout_route()
    {
        _gateway.Server
            .Given(Request.Create().WithPath("/basket-service/basket/checkout").UsingPost())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""{"isSuccess":true}"""));

        var response = await _basket.CheckoutBasket(
            new CheckoutBasketRequest(new BasketCheckoutModel { UserName = DefaultUser }));

        response.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task DeleteBasket_targets_the_user_scoped_route()
    {
        _gateway.Server
            .Given(Request.Create().WithPath($"/basket-service/basket/{DefaultUser}").UsingDelete())
            .RespondWith(Response.Create().WithStatusCode(200)
                .WithHeader("Content-Type", "application/json")
                .WithBody("""{"isSuccess":true}"""));

        var response = await _basket.DeleteBasket(DefaultUser);

        response.IsSuccess.Should().BeTrue();
    }
}
