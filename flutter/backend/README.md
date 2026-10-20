# Plugsy Django backend

## Local development
```sh
cd flutter/backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver 0.0.0.0:8000
```

The initial migration is committed. Android emulator API URL: `http://10.0.2.2:8000/api`.

## Booking lifecycle
1. Driver requests a charger and submits estimated kWh.
2. The backend creates an in-app notification for the host and sends an FCM push when the device token and Firebase service-account credentials are configured.
3. Host accepts or declines. Only one accepted booking per charger may be active at a time.
4. Host starts the session when the driver arrives.
5. Host records the measured kWh at session completion. The backend calculates the final amount from measured kWh × the host's published per-kWh price.
6. Driver pays the final amount through Razorpay Checkout. The server verifies the checkout signature and confirms captured status/amount directly with Razorpay; a signed webhook also handles asynchronous confirmation.
7. When Razorpay Route is enabled and the host has a configured linked account, the backend initiates the host transfer and processes transfer status webhooks. Otherwise the payment is collected but the host payout remains in `needs_setup`.
8. Driver can submit one 1–5-star review after the session is complete and payment is confirmed.

**Metering limitation:** kWh is currently host-entered, not read from an EV charger/energy meter. Do not describe it as independently verified. Real-world launch needs metering integration, disputes/refunds, host identity and charger safety verification.

## API routes
- `POST /api/auth/register/`, `POST /api/auth/login/`
- `GET/POST /api/chargers/`
- `GET/POST /api/bookings/`
- `POST /api/bookings/<id>/respond/`
- `POST /api/bookings/<id>/start/`
- `POST /api/bookings/<id>/complete/`
- `POST /api/bookings/<id>/payment-order/`
- `POST /api/bookings/<id>/verify-payment/`
- `POST /api/payments/razorpay/webhook/`
- `POST /api/devices/register/`
- `GET /api/payouts/` — host payout status and transfer reconciliation state
- `POST /api/payouts/<id>/retry/` — administrator-only retry for payouts marked `needs_setup` or `failed`; never retry `needs_reconciliation` until the provider dashboard confirms no transfer was created
- `GET /api/notifications/`, `POST /api/notifications/<id>/read/`
- `GET/POST /api/reviews/`

## Required configuration before live payments
Set these environment variables on the backend host:
- `SECRET_KEY`: long random secret; never use the development default.
- `DEBUG=False`, `ALLOWED_HOSTS`, `DATABASE_URL`, `CORS_ALLOWED_ORIGINS`.
- `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET`: use Razorpay test keys during testing; never place the secret in Flutter.
- `RAZORPAY_WEBHOOK_SECRET`: create a Razorpay webhook for `payment.captured`, `payment.failed`, `transfer.processed`, `transfer.failed`, and `transfer.reversed`, pointing to `https://YOUR_API/api/payments/razorpay/webhook/`.
- `RAZORPAY_ROUTE_ENABLED=true` only after Razorpay Route is activated for your business. A verified host's linked account ID must be entered in Django admin (`Users → Plugsy → Razorpay account ID`) after the provider's host onboarding/KYC is complete. The payout ledger shows `needs_setup`, `initiated`, `transferred`, `failed`, or `needs_reconciliation`; network-uncertain transfers must be reconciled in the Razorpay dashboard before retrying.
- `FIREBASE_SERVICE_ACCOUNT_JSON`: the Firebase service-account JSON encoded as a single-line JSON string for FCM push delivery.

## Firebase mobile setup
From `flutter/`, run `dart pub global activate flutterfire_cli` then `flutterfire configure` and follow the Firebase Android/iOS configuration instructions. Ensure the Android `google-services.json` and iOS `GoogleService-Info.plist` are added privately to the app configuration (do not commit service-account credentials). The app registers FCM device tokens after login and displays foreground alerts.

## Production hardening still required
Email verification/password reset, token refresh/logout revocation, refund/dispute handling, payment reconciliation, idempotency and rate-limit tests, privacy/legal notices, host/charger verification, exact-address disclosure rules, monitoring, backups, and physical-device build tests.
