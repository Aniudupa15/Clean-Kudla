## 🌿 Clean Kudla: Smart Waste Management System 🗑️

Welcome to **Clean Kudla**, an innovative and intelligent urban sanitation platform designed to transform waste collection in Mangaluru. With real-time tracking, automated data management, and a user-friendly interface, Clean Kudla brings accountability and efficiency to door-to-door waste collection.

---

## ✨ Project Overview: Revolutionizing Waste Collection

Clean Kudla empowers both sanitation workers and administrative staff through a unified, powerful system built with Flutter and Firebase.

* **Live GPS Tracking** 📍
* **Proximity-Based House Collection** 🏠
* **Gamified User Points System** 💰
* **Realtime Data Sync with Firestore** ☁️

---

## 🚀 Key Features

### 👷 Worker App: Ground-Level Automation

* **Live Route Tracking**: Records routes in real-time to help with coverage analysis and route optimization.
* **Auto-Marking of Houses**: Houses are marked as visited automatically when within a defined proximity.
* **Smart Proximity Collection**: Triggers auto-collection for registered users and updates their point tally.
* **Real-time Notifications**: Push alerts for collection events and updates.
* **Background Tracking**: Foreground service ensures uninterrupted tracking even when app is minimized.
* **Secure Login**: Firebase Authentication guarantees safe sign-ins.
* **Route Summary Reports**: Post-route data includes full paths and visited locations.

### 📊 Admin Panel: Central Command & Analytics

* **Live Monitoring**: View worker routes in real-time on an interactive map.
* **Detailed Logs**: Get live updates on route ID, worker info, timestamp, and total houses collected.
* **Interactive Route Playback**: Visualize entire paths and collected houses.
* **Zone Status Overview**:

    * 🟢 **Completed Routes**
    * 🔴 **Pending Houses**
    * 🔵 **Collected Houses**
* **Optimized Data Structure**: Uses a denormalized Firestore structure for performance.

---

## 🛠️ Tech Stack

* **Flutter**: Cross-platform UI toolkit.
* **Firebase + Firestore**: Real-time database, authentication, and cloud infrastructure.
* **flutter\_map**: OSM-based map integration.
* **geolocator**: High-precision location services.
* **flutter\_background\_service**: Background tracking.
* **flutter\_local\_notifications**: Local alerts.
* **permission\_handler**: Manages runtime permissions.
* **shared\_preferences**: Stores local state data.
* **uuid**: Generates unique IDs.
* **intl**: Date and time formatting.
* **google\_fonts**: Clean typography.

---

## 🏗️ Architecture & Data Flow

```mermaid
graph TD
  subgraph Worker App 👷
    A[Worker UI] --> B{Background Service}
    B --> C(Geolocator)
    C --> B
    B --> D[Firestore: routes/{workerUid}/logs/{routeId}]
    B --> E[Firestore: admin_ongoing_routes/{routeId}]
    B --> F[Firestore: users/{userId}]
  end

  subgraph Admin Panel 📊
    G[Admin UI] --> H[admin_ongoing_routes stream]
    G --> I[routes/{workerUid}/logs/{routeId} stream]
    G --> J[users collection query]
  end

  D --> E
  F --> G
```

### 🔐 Firestore Schema

**users/{userId}**:

* fullName, email, userType
* latitude, longitude
* points, lastCollectedAt
* collectedByRoutes: Map of routeId -> workerUid, timestamp

**routes/{workerUid}/logs/{routeId}**:

* startedAt, endedAt
* path: list of lat/lng
* housesVisited: list of lat/lng

**admin\_ongoing\_routes/{routeId}**:

* routeId, workerUid, workerName
* currentPath, currentHousesVisited
* lastUpdated, status

---

## 🚀 Getting Started

### Prerequisites

* Flutter SDK (Stable)
* Firebase CLI
* Google Account

### Firebase Setup

1. Create a new project in Firebase Console.
2. Enable Firestore and Authentication.
3. Register Android & iOS apps. Add config files:

    * `google-services.json` to `android/app/`
    * `GoogleService-Info.plist` to `ios/Runner/`

### Firestore Rules Example

```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == userId;
    }
    match /routes/{workerUid}/logs/{routeId} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == workerUid;
    }
    match /admin_ongoing_routes/{routeId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
  }
}
```

### Flutter Configuration

```bash
git clone <your-repo-url>
cd clean_kudla
flutter pub get
```

#### Android:

* `minSdkVersion >= 21`
* Add permissions in AndroidManifest.xml:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
```

#### iOS:

* Update Info.plist:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location for tracking routes.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

* Enable Background Modes in Xcode

---

## 💡 Usage Guide

### 👷 Worker Flow

1. Login using email/password
2. Tap **Start Collection**
3. Move around — your route gets recorded and houses auto-marked
4. Tap **Stop Collection** when done

### 📊 Admin Flow

1. Access Admin View
2. Monitor live routes and status
3. Tap a route to view path and collected houses
4. View complete zone status on the map

---

## 🤝 Contributing

We're open to contributors! Fork, fix, and submit PRs via GitHub.

## 📧 Contact

* Email: [support@cleankudla.com](mailto:support@cleankudla.com) *(placeholder)*
* GitHub: \[Add your GitHub link here]

## 📜 License

This project is licensed under the MIT License.
