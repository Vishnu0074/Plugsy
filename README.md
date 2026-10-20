# Plugsy

**Find a charge. Share the power.**

Plugsy is a peer-to-peer EV charging marketplace where drivers discover chargers shared by hosts, request a session, pay for measured energy, and review the experience.

## Repository layout
- `flutter/` — Flutter mobile app.
- `flutter/backend/` — Django REST API.

## Implemented booking lifecycle
1. Driver requests a charger and enters estimated energy.
2. Host receives an in-app notification and, when Firebase (not configured) is configured, an FCM phone notification.
3. Host accepts/declines, then starts the session when the driver arrives.
4. Host records actual kWh at completion; the API calculates the final bill.
5. Driver pays through manual payment confirmation Checkout. The backend verifies the checkout signature, provider-side captured status and amount; a signed webhook handles asynchronous confirmation.
6. If manual payment confirmation Route is enabled and the host has a verified linked account, Plugsy initiates a host transfer and tracks transfer webhooks. Otherwise the payout is marked `needs_setup` and must not be represented as paid out.
7. Driver can review the charger after successful payment.

## Development
See [Flutter setup](flutter/README.md) and [Django API setup](flutter/backend/README.md). Run backend lifecycle tests with `python manage.py test marketplace`.

## Important launch limitations
- Energy consumption is host-entered; it is not independently metered by the EV charger.
- Configure Firebase (not configured) for real push delivery and manual payment confirmation test keys before payment testing.
- Before live transactions, activate and test manual payment confirmation Route, add production-grade refunds/disputes and payout reconciliation, identity and charger safety verification, email verification, password reset, token refresh/revocation, monitoring, backups, and privacy/legal policies.
- Protect private home addresses: the public API rounds coordinates until a booking is accepted.


## Current payment and notification scope
Plugsy currently has no payment gateway, automatic payout, Firebase setup, or push notifications. The driver and host settle payment outside the app; after receiving the money, the host confirms it with **Mark as paid**. The backend records that confirmation so the driver can review the completed session. In-app notifications are stored in the backend only.
