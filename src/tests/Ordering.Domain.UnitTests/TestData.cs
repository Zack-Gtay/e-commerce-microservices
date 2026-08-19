namespace Ordering.Domain.UnitTests;

/// <summary>
/// Object-mother helpers so each test states only the values it actually cares about.
/// </summary>
internal static class TestData
{
    public static Address Address(
        string firstName = "Zakaria",
        string lastName = "El Gtay",
        string email = "zakaria@example.com",
        string addressLine = "12 Rue Mohammed V",
        string country = "Morocco",
        string state = "Casablanca",
        string zipCode = "20000")
        => ValueObjects.Address.Of(firstName, lastName, email, addressLine, country, state, zipCode);

    public static Payment Payment(
        string cardName = "Z EL GTAY",
        string cardNumber = "5555444433332222",
        string expiration = "12/28",
        string cvv = "123",
        int paymentMethod = 1)
        => ValueObjects.Payment.Of(cardName, cardNumber, expiration, cvv, paymentMethod);
}
