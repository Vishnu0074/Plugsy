# Plugsy

**Find a charge. Share the power.**

Plugsy is a peer-to-peer EV charging marketplace where drivers discover chargers shared by hosts, request a session, pay for measured energy, and review the experience.

## Repository layout
- `flutter/` — Flutter mobile app.
- `flutter/backend/` — Django REST API.

## Implemented booking lifecycle
1. Driver requests a charger and enters estimated energy.
2. Host receives an in-app notification and, when Firebase is configured, an FCM phone notification.
3. Host accepts/declines, then starts the session when the driver arrives.
4. Host records actual kWh at completion; the API calculates the final bill.
5. Driver pays through Razorpay Checkout. The backend verifies the checkout signature, provider-side captured status and amount; a signed webhook handles asynchronous confirmation.
6. Driver can review the charger after successful payment.

## Development
See [Flutter setup](flutter/README.md) and [Django API setup](flutter/backend/README.md). Run backend lifecycle tests with `python manage.py test marketplace`.

## Important launch limitations
- Energy consumption is host-entered; it is not independently metered by the EV charger.
- Configure Firebase for real push delivery and Razorpay test keys before payment testing.
- Before live transactions, add production-grade refunds/disputes, reconciliation, identity and charger safety verification, email verification, password reset, token refresh/revocation, monitoring, backups, and privacy/legal policies.
- Protect private home addresses: the public API rounds coordinates until a booking is accepted.
