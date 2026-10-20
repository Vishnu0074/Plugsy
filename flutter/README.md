# Plugsy Flutter app

## Run
```sh
flutter pub get
flutter run
```

Configure the backend with:
```sh
flutter run --dart-define=PLUGSY_API_BASE_URL=http://10.0.2.2:8000/api
```
The default URL is for the Android emulator. On a physical phone, use your computer's LAN IP. Use HTTPS for production.

The starter includes account registration/login, optional host onboarding, charger listing with map pin/current location, nearby charger discovery, map markers, booking requests and host accept/decline actions.

Not yet production-ready: push notifications/phone ringing, payment gateway and commission settlement, real state electricity tariff data, completed-session metering, review submission UI, email verification, token refresh, and private-address masking must be implemented and tested before launch.
