# Module 18 Assignment: Real-Time Location Tracker

A Flutter application developed for **Module 18 Assignment: Google Maps & Geolocator**.

## 📱 Features & Assignment Tasks Completed

1. **Automatic Map Animation**:
   - Google Map smoothly animates to the user's current GPS location upon acquiring initial coordinates.
2. **Real-Time Location Updates (10-second interval)**:
   - Uses `Geolocator` to fetch user's live position every 10 seconds via a periodic timer.
   - Marker dynamically moves to reflect the latest location coordinates.
3. **Polyline Tracking**:
   - Connects previous and current points with a vibrant blue polyline (`#1E88E5`).
   - Automatically appends points and extends the route as position changes.
4. **Marker Information Window**:
   - Tapping the marker opens an InfoWindow.
   - **Title**: `My Current Location`
   - **Snippet**: `<latitude>,<longitude>` (e.g. `23.7216771,90.4165835`).
5. **Bonus Emulator Convenience**:
   - Includes a route simulation toggle (along Dhaka's Jatrabari Flyover / Wari route from the assignment screenshot) so you can test 10-second updates even on emulators without configuring mock GPS coordinates.
   - Live countdown chip showing seconds remaining until the next 10-second update.
   - Floating action button to re-center on the user's current location.

---

## 🛠️ Google Maps API Key Setup

To render live Google Maps tiles on Android:
1. Open [Google Cloud Console](https://console.cloud.google.com/).
2. Enable **Maps SDK for Android**.
3. Create an API Key (or restrict it to package `com.ostad.m18.real_time_location_tracker`).
4. Paste the key in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="YOUR_GOOGLE_MAPS_API_KEY" />
   ```

---

## 🚀 How to Run

1. Clone this repository:
   ```bash
   git clone <repo-url>
   cd m18
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run on connected emulator or physical device:
   ```bash
   flutter run
   ```

---

## 📦 Packages Used
- [`google_maps_flutter`](https://pub.dev/packages/google_maps_flutter)
- [`geolocator`](https://pub.dev/packages/geolocator)
