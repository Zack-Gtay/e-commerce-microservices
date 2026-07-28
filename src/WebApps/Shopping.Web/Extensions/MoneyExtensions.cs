using System.Globalization;

namespace Shopping.Web.Extensions;

public static class MoneyExtensions
{
    public static string ToMoney(this decimal value) =>
        value == decimal.Truncate(value)
            ? "$" + value.ToString("#,##0", CultureInfo.InvariantCulture)
            : "$" + value.ToString("#,##0.00", CultureInfo.InvariantCulture);
}
