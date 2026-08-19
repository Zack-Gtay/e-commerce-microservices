namespace Ordering.Domain.UnitTests;

/// <summary>
/// Behaviour tests for the <see cref="Order"/> aggregate root.
///
/// These are pure unit tests: no database, no DI container, no mocks. That is only
/// possible because Ordering.Domain has no infrastructure dependencies -- which is
/// the practical payoff of the Clean Architecture layering, not just a diagram.
/// </summary>
public class OrderTests
{
    private static Order NewOrder() => Order.Create(
        id: OrderId.Of(Guid.NewGuid()),
        customerId: CustomerId.Of(Guid.NewGuid()),
        orderName: OrderName.Of("ORD-1"),
        shippingAddress: TestData.Address(),
        billingAddress: TestData.Address(),
        payment: TestData.Payment());

    [Fact]
    public void Create_starts_the_order_in_Pending_status()
    {
        var order = NewOrder();

        order.Status.Should().Be(OrderStatus.Pending);
    }

    [Fact]
    public void Create_raises_exactly_one_OrderCreatedEvent()
    {
        var order = NewOrder();

        order.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<OrderCreatedEvent>()
            .Which.order.Should().BeSameAs(order);
    }

    [Fact]
    public void ClearDomainEvents_returns_and_empties_the_pending_events()
    {
        var order = NewOrder();

        var dequeued = order.ClearDomainEvents();

        dequeued.Should().ContainSingle().Which.Should().BeOfType<OrderCreatedEvent>();
        order.DomainEvents.Should().BeEmpty();
    }

    [Fact]
    public void Update_raises_an_OrderUpdatedEvent_and_applies_the_new_status()
    {
        var order = NewOrder();
        order.ClearDomainEvents();

        order.Update(
            orderName: OrderName.Of("ORD-2"),
            shippingAddress: TestData.Address(),
            billingAddress: TestData.Address(),
            payment: TestData.Payment(),
            status: OrderStatus.Completed);

        order.Status.Should().Be(OrderStatus.Completed);
        order.OrderName.Value.Should().Be("ORD-2");
        order.DomainEvents.Should().ContainSingle()
            .Which.Should().BeOfType<OrderUpdatedEvent>();
    }

    [Fact]
    public void Add_appends_an_item_and_TotalPrice_reflects_quantity_times_price()
    {
        var order = NewOrder();

        order.Add(ProductId.Of(Guid.NewGuid()), quantity: 2, price: 50m);
        order.Add(ProductId.Of(Guid.NewGuid()), quantity: 1, price: 30m);

        order.OrderItems.Should().HaveCount(2);
        order.TotalPrice.Should().Be(130m); // (2 * 50) + (1 * 30)
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void Add_rejects_a_non_positive_quantity(int quantity)
    {
        var order = NewOrder();

        var act = () => order.Add(ProductId.Of(Guid.NewGuid()), quantity, price: 10m);

        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-5)]
    public void Add_rejects_a_non_positive_price(decimal price)
    {
        var order = NewOrder();

        var act = () => order.Add(ProductId.Of(Guid.NewGuid()), quantity: 1, price);

        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void Remove_deletes_the_matching_line_item()
    {
        var order = NewOrder();
        var productId = ProductId.Of(Guid.NewGuid());
        order.Add(productId, 1, 10m);

        order.Remove(productId);

        order.OrderItems.Should().BeEmpty();
    }

    [Fact]
    public void Remove_is_a_no_op_when_the_product_is_not_in_the_order()
    {
        var order = NewOrder();
        order.Add(ProductId.Of(Guid.NewGuid()), 1, 10m);

        order.Remove(ProductId.Of(Guid.NewGuid()));

        order.OrderItems.Should().HaveCount(1);
    }

    [Fact]
    public void OrderItems_is_exposed_as_a_read_only_collection()
    {
        var order = NewOrder();

        order.OrderItems.Should().BeAssignableTo<IReadOnlyList<OrderItem>>();

        // ReadOnlyCollection<T> still implements ICollection<T>, but every mutating
        // member throws -- so even a caller that casts cannot bypass Order.Add().
        var smuggled = (ICollection<OrderItem>)order.OrderItems;
        var act = () => smuggled.Add(null!);

        act.Should().Throw<NotSupportedException>();
    }

    [Fact]
    public void Line_items_are_created_with_the_parent_order_id()
    {
        var order = NewOrder();
        var productId = ProductId.Of(Guid.NewGuid());

        order.Add(productId, 3, 25m);

        var item = order.OrderItems.Single();
        item.OrderId.Should().Be(order.Id);
        item.ProductId.Should().Be(productId);
        item.Quantity.Should().Be(3);
        item.Price.Should().Be(25m);
    }
}
