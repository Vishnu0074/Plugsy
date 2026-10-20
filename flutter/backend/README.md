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

Android emulator API URL: `http://10.0.2.2:8000/api`.

## Booking lifecycle
1. Driver requests a charger and submits estimated kWh.
2. Plugsy stores an in-app notification for the host; no push-notification provider is configured.
3. Host accepts or declines. Only one accepted booking per charger may be active at a time.
4. Host starts the session when the driver arrives.
5. Host records measured kWh at completion. The backend calculates the final amount from measured kWh × the host's listed price per kWh.
6. Payment happens outside Plugsy. After the host actually receives the money, the host taps **Mark as paid**. This is a manual confirmation, not a payment transaction or proof of transfer.
7. Driver can submit one 1–5-star review after the host marks the completed booking as paid.

**Metering limitation:** kWh is currently host-entered, not read from an EV charger/energy meter. Do not describe it as independently verified.

## API routes
- `POST /api/auth/register/`, `POST /api/auth/login/`
- `GET/POST /api/chargers/`
- `GET/POST /api/bookings/`
- `POST /api/bookings/<id>/respond/`
- `POST /api/bookings/<id>/start/`
- `POST /api/bookings/<id>/complete/`
- `POST /api/bookings/<id>/mark-paid/` — host-only manual confirmation after offline payment is received
- `GET /api/notifications/`, `POST /api/notifications/<id>/read/`
- `GET/POST /api/reviews/`

## Environment configuration
Set `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS`, `DATABASE_URL`, and `CORS_ALLOWED_ORIGINS` as appropriate. No payment-gateway credentials or Firebase credentials are required for this version.

## Production hardening still required
Email verification/password reset, token refresh/logout revocation, manual-payment disputes, idempotency/rate-limit tests, privacy/legal notices, host/charger verification, exact-address disclosure rules, monitoring, backups, and physical-device build tests.
