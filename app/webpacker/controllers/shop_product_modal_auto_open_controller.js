import { Controller } from "stimulus";

export default class extends Controller {
  connect() {
    const params = new URLSearchParams(window.location.search);
    const productId = params.get("product_id");
    if (!productId) return;

    const orderCycleId = params.get("order_cycle_id");
    let url = `/shop/product_modal?product_id=${encodeURIComponent(productId)}`;
    if (orderCycleId) {
      url += `&order_cycle_id=${encodeURIComponent(orderCycleId)}`;
    }

    this.load(url);
  }

  async load(url) {
    const container = document.getElementById("shop-product-modal-container");
    if (!container) return;

    try {
      const response = await fetch(url, {
        method: "GET",
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest",
        },
        credentials: "same-origin",
      });

      if (!response.ok) return;

      container.innerHTML = await response.text();
    } catch (error) {
      // Silently ignore network errors
    }
  }
}
