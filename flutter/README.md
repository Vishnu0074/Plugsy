# Plugsy Flutter app

## Generate native platform scaffolding
Run once on a machine with Flutter installed:
```sh
bash bootstrap_platforms.sh
flutter pub get
```
Review generated changes before committing.

## Configure push notifications
Install/configure Firebase for Android and iOS:
```sh
dart pub global activate flutterfire_cli
flutterfire configure
```
Follow Firebase setup instructions and add the app's platform config files. The Flutter app registers FCM tokens after login, shows foreground alerts, and relies on system notifications for background alerts. The Django backend must also have `FIREBASE_SERVICE_ACCOUNT_JSON` configured.

## Configure payments
Plugsy uses Razorpay Checkout. Configure `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` on the backend and use Razorpay **test keys** while developing. The secret must never be embedded in the Flutter app. A valid payment requires provider-side captured status and a signed checkout response/webhook.

## Run
```sh
flutter run --dart-define=PLUGSY_API_BASE_URL=http://10.0.2.2:8000/api
```
The URL above is for an Android emulator. For iOS simulator use `http://127.0.0.1:8000/api`; for a physical device use the computer's LAN IP. Use HTTPS in production.

## Lifecycle in the app
1. Driver requests a charger and enters estimated kWh.
2. Host receives an in-app/FCM notification and accepts or declines.
3. Host starts the session when the driver arrives.
4. Host records actual kWh to complete the session.
5. Driver pays the calculated final amount through Razorpay Checkout.
6. Driver leaves a 1–5 star review after payment is confirmed.

**Not production-ready until tested:** the kWh value is entered by the host, not independently metered; push delivery needs Firebase configuration; payment flows need live-provider validation, refunds/disputes, and reconciliation. Email verification, password reset, access-token refresh, host/charger verification, and physical-device builds are also outstanding.
