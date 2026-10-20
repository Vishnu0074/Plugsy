# Plugsy Flutter app

## Generate native platform scaffolding
Run once on a machine with Flutter installed:
```sh
bash bootstrap_platforms.sh
flutter pub get
```
Review generated changes before committing.

## Run
```sh
flutter run --dart-define=PLUGSY_API_BASE_URL=http://10.0.2.2:8000/api
```
The URL above is for an Android emulator. For iOS simulator use `http://127.0.0.1:8000/api`; for a physical device use the computer's LAN IP. Use HTTPS in production.

## Booking lifecycle
1. Driver requests a charger and enters estimated kWh.
2. Host sees an in-app notification and accepts or declines.
3. Host starts the session when the driver arrives.
4. Host records actual kWh to complete the session.
5. Driver and host settle payment outside Plugsy. The host taps **Mark as paid** only after receiving the money.
6. Driver can leave a 1–5 star review once the host confirms payment.

No Firebase setup, push notifications, payment gateway, or automatic host payouts are used in this version. The app records the host's manual payment confirmation; it does not move money or independently verify payment. The kWh value is entered by the host, not independently metered.


## Map
Plugsy uses the open-source **Leaflet.js** library embedded in Flutter through WebView, with OpenStreetMap tiles and attribution. Hosts can use the device's current location or tap the map to select a charger's location. The discovery map displays charger markers. The map requires an internet connection to load Leaflet and map tiles.
