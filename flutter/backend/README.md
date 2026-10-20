# Plugsy Django backend

## Run locally
1. Create a virtual environment and install dependencies: `pip install -r requirements.txt`
2. Set a secure SECRET_KEY for production; local development can use the default.
3. Run `python manage.py makemigrations marketplace`, `python manage.py migrate`, then `python manage.py runserver 0.0.0.0:8000`.
4. Android emulator API base URL: `http://10.0.2.2:8000/api`.

## Endpoints
- POST /api/auth/register/ — email, username, password, wants_to_host
- POST /api/auth/login/ — username or email and password; returns JWT
- GET/POST /api/chargers/ — discover published chargers / create listing
- GET/POST /api/bookings/ — list own bookings / request a charger
- POST /api/bookings/<id>/respond/ — host accepts or declines a pending request
- GET/POST /api/reviews/ — review a charger after a completed booking

## Production requirements
Set SECRET_KEY, DEBUG=False, ALLOWED_HOSTS and DATABASE_URL; configure HTTPS, email verification, CORS, rate limiting, push notifications, payments, monitoring and backups. Use PostgreSQL/PostGIS for larger proximity searches. Booking acceptance does not prove payment or verified energy consumption. Do not expose exact private addresses before a booking is accepted.
