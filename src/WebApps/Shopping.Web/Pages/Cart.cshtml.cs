namespace Shopping.Web.Pages
{
    public class CartModel(IBasketService basketService, ILogger<CartModel> logger)
        : PageModel
    {
        public ShoppingCartModel Cart { get; set; } = new ShoppingCartModel();

        public async Task<IActionResult> OnGetAsync()
        {
            Cart = await basketService.LoadUserBasket();

            return Page();
        }

        public async Task<IActionResult> OnPostRemoveToCartAsync(Guid productId)
        {
            logger.LogInformation("Remove to cart button clicked");
            Cart = await basketService.LoadUserBasket();

            Cart.Items.RemoveAll(x => x.ProductId == productId);

            await basketService.StoreBasket(new StoreBasketRequest(Cart));

            return RedirectToPage();
        }

        public async Task<IActionResult> OnPostUpdateQuantityAsync(Guid productId, int quantity)
        {
            logger.LogInformation("Update quantity for {ProductId} to {Quantity}", productId, quantity);

            quantity = Math.Clamp(quantity, 1, 99);

            Cart = await basketService.LoadUserBasket();

            foreach (var item in Cart.Items.Where(x => x.ProductId == productId))
            {
                item.Quantity = quantity;
            }

            await basketService.StoreBasket(new StoreBasketRequest(Cart));

            return RedirectToPage();
        }
    }
}
