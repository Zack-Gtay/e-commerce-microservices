namespace Shopping.Web.Pages
{
    public class ProductListModel
        (ICatalogService catalogService, IBasketService basketService, ILogger<ProductListModel> logger)
        : PageModel
    {
        public IEnumerable<string> CategoryList { get; set; } = [];
        public IEnumerable<ProductModel> ProductList { get; set; } = [];

        [BindProperty(SupportsGet = true)]
        public string SelectedCategory { get; set; } = default!;

        [BindProperty(SupportsGet = true, Name = "q")]
        public string? Query { get; set; }

        public async Task<IActionResult> OnGetAsync(string categoryName)
        {
            var response = await catalogService.GetProducts();

            CategoryList = response.Products.SelectMany(p => p.Category).Distinct();

            var products = response.Products;

            if (!string.IsNullOrWhiteSpace(categoryName))
            {
                products = products.Where(p => p.Category.Contains(categoryName));
                SelectedCategory = categoryName;
            }

            if (!string.IsNullOrWhiteSpace(Query))
            {
                products = products.Where(p =>
                    p.Name.Contains(Query, StringComparison.OrdinalIgnoreCase) ||
                    p.Description.Contains(Query, StringComparison.OrdinalIgnoreCase));
            }

            ProductList = products.ToList();

            return Page();
        }

        public async Task<IActionResult> OnPostAddToCartAsync(Guid productId)
        {
            logger.LogInformation("Add to cart button clicked");
            var productResponse = await catalogService.GetProduct(productId);

            var basket = await basketService.LoadUserBasket();

            basket.Items.Add(new ShoppingCartItemModel
            {
                ProductId = productId,
                ProductName = productResponse.Product.Name,
                Price = productResponse.Product.Price,
                Quantity = 1,
                Color = "Black"
            });

            await basketService.StoreBasket(new StoreBasketRequest(basket));

            return RedirectToPage("Cart");
        }
    }
}
