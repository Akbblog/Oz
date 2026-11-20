# Infinity Leads interface context

The product uses a dark, restrained workspace with teal for primary actions and green for completed or selected states. Use the shared `AppColors`, `AppSpacing`, and `AppTypography` tokens. Keep content centered at readable widths on desktop and use full-width controls on phones.

Purchase screens show credits first, then price and cost per credit. Load prices and credit policy from the API; do not imply a refund rule or payment method when the server has not provided it. A package must have an obvious selected state and a keyboard-accessible control. The exact search cost is shown before a search begins; package examples are illustrative and use the backend estimate endpoint.

Preserve navigation and behavior across desktop, tablet, and mobile. Test the web build and inspect layouts at narrow phone and desktop widths after UI changes.
