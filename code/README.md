# SmartMeasure Pro (Flutter App)

This folder contains the Flutter mobile application for the **Smart Laser Distance Meter** project.

If you want the full system overview (device + app + cloud backend), see the repository root README.

## What the app does (non-technical)
- Connects to the handheld device over **Bluetooth**
- Lets you **sketch room floor plans**, apply real wall measurements, and add objects
- Supports **AR room scanning** as an alternative input method
- Saves projects locally and optionally **syncs to cloud** for backup/collaboration
- Exports plans as **PDF** and **DXF (CAD)**

## Key tech
- Flutter / Dart
- Bluetooth LE: `flutter_blue_plus`
- State management: Riverpod
- Local storage: SQLite (`sqflite`)
- Cloud: HTTP + JWT token stored using `flutter_secure_storage`
- AR: `ar_flutter_plugin_2`

## Quick start
From this `code/` folder:

1. Install dependencies:
	- `flutter pub get`
2. Run on a connected device/emulator:
	- `flutter run`

## Configuration notes
- Cloud API base URL is configured in `lib/services/api_service.dart` (`ApiService.baseUrl`).
- BLE service/characteristic UUIDs used by the app are in `lib/ble/ble_manager.dart`.

## Main folders
- `lib/ble/` — BLE scan/connect + packet parsing
- `lib/sketch/` — floor-plan editor (2D), furniture, export, 3D view
- `lib/ar/` — AR scan + polygon generation
- `lib/database/` — local SQLite schema + offline sync queue
- `lib/services/` — cloud auth + sync
- `smartmeasure-backend/` — Node.js backend (Express + PostgreSQL)
