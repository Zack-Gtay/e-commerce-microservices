namespace Ordering.Domain.UnitTests;

/// <summary>
/// The value objects are the domain's first line of defence: an invalid Order cannot be
/// constructed even by a caller that bypassed FluentValidation at the API boundary.
/// </summary>
public class ValueObjectTests
{
    // ---------- strongly-typed identifiers ----------

    [Fact]
    public void OrderId_rejects_an_empty_guid()
    {
        var act = () => OrderId.Of(Guid.Empty);

        act.Should().Throw<DomainException>()
            .WithMessage("*OrderId cannot be empty*");
    }

    [Fact]
    public void CustomerId_rejects_an_empty_guid()
    {
        var act = () => CustomerId.Of(Guid.Empty);

        act.Should().Throw<DomainException>().WithMessage("*CustomerId cannot be empty*");
    }

    [Fact]
    public void ProductId_rejects_an_empty_guid()
    {
        var act = () => ProductId.Of(Guid.Empty);

        act.Should().Throw<DomainException>().WithMessage("*ProductId cannot be empty*");
    }

    [Fact]
    public void OrderItemId_rejects_an_empty_guid()
    {
        var act = () => OrderItemId.Of(Guid.Empty);

        act.Should().Throw<DomainException>().WithMessage("*OrderItemId cannot be empty*");
    }

    [Fact]
    public void OrderId_carries_the_underlying_value()
    {
        var guid = Guid.NewGuid();

        OrderId.Of(guid).Value.Should().Be(guid);
    }

    [Fact]
    public void Strongly_typed_ids_compare_by_value_not_by_reference()
    {
        var guid = Guid.NewGuid();

        // Declared as `record`, so structural equality comes for free -- this is what
        // makes them safe to use as dictionary keys and in EF change tracking.
        OrderId.Of(guid).Should().Be(OrderId.Of(guid));
        OrderId.Of(guid).Should().NotBe(OrderId.Of(Guid.NewGuid()));
    }

    // ---------- OrderName ----------

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void OrderName_rejects_blank_values(string value)
    {
        var act = () => OrderName.Of(value);

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void OrderName_rejects_null()
    {
        var act = () => OrderName.Of(null!);

        act.Should().Throw<ArgumentNullException>();
    }

    // ---------- Address ----------

    [Fact]
    public void Address_requires_an_email_address()
    {
        var act = () => Address.Of("Zakaria", "El Gtay", "  ", "12 Rue Mohammed V", "Morocco", "Casablanca", "20000");

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Address_requires_an_address_line()
    {
        var act = () => Address.Of("Zakaria", "El Gtay", "zakaria@example.com", "", "Morocco", "Casablanca", "20000");

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Address_exposes_the_values_it_was_built_with()
    {
        var address = TestData.Address(country: "Morocco", zipCode: "20000");

        address.Country.Should().Be("Morocco");
        address.ZipCode.Should().Be("20000");
        address.EmailAddress.Should().Be("zakaria@example.com");
    }

    // ---------- Payment ----------

    [Fact]
    public void Payment_rejects_a_cvv_longer_than_three_characters()
    {
        var act = () => TestData.Payment(cvv: "1234");

        act.Should().Throw<ArgumentOutOfRangeException>();
    }

    [Fact]
    public void Payment_requires_a_card_number()
    {
        var act = () => TestData.Payment(cardNumber: "");

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Payment_requires_a_card_name()
    {
        var act = () => TestData.Payment(cardName: "   ");

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Payment_accepts_a_valid_card()
    {
        var payment = TestData.Payment(cvv: "123");

        payment.CVV.Should().Be("123");
        payment.PaymentMethod.Should().Be(1);
    }
}
