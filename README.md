# Plugsy

**Find a charge. Share the power.**

Plugsy is a peer-to-peer EV charging marketplace: drivers discover compatible nearby chargers hosted by people and businesses; hosts list chargers, set availability, and earn from completed sessions.

## Repository layout

- `flutter/` — Flutter mobile application.
- `flutter/backend/` — Django REST API that serves the Flutter app.

## Development status

This repository starts with a foundational MVP implementation. Before production use, configure a real database, HTTPS, push notifications, payment provider, maps provider, and operational/safety checks.

## Architecture

- Flutter + Provider for app state, with an API client isolated from UI.
- Django REST Framework + JWT authentication.
- PostgreSQL in production; SQLite for local development.
- Charger coordinates stored as latitude/longitude. Nearby filtering uses a distance calculation and should be upgraded to PostGIS for larger datasets.
- Booking requests have explicit states; accepting a request does not itself prove payment or charging completion.

## Local setup

See [Flutter app setup](flutter/README.md) and [Django backend setup](flutter/backend/README.md).

## Important MVP safeguards

- A charger must be explicitly published by its owner.
- Never expose a host's exact private address to unauthenticated users; show approximate location until a booking is accepted.
- A phone ring/alert requires push notification permissions and a configured provider. The app must provide an in-app fallback.
- Price per kWh and any platform fee must be transparent before booking.
- Payment, energy metering, electrical safety, host authorization, and local regulations need validation before launch.
