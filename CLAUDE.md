# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Smart Laser Distance Meter — a 3-year engineering project (University of Peradeniya). An ESP32-based handheld device measures distances via LiDAR and orientation via IMU, transmits data over BLE to a Flutter mobile app that generates 2D/3D floor plans, supports AR scanning, and exports to PDF/DXF.

Three independent sub-projects:
- **`code/`** — Flutter mobile app (Dart, SDK ^3.10.7)
- **`code/smartmeasure-backend/`** — Node.js/Express REST API (PostgreSQL)
- **`firmware/`** — ESP32 Arduino firmware (PlatformIO)

---

## Commands

### Flutter Mobile App (`code/`)

```bash
flutter pub get          # Install dependencies
flutter run              # Run on connected device/emulator
flutter build apk        # Build Android APK
flutter test             # Run all tests
flutter test test/widget_test.dart  # Run a single test file
flutter analyze          # Static analysis (flutter_lints)
```

### Backend (`code/smartmeasure-backend/`)

```bash
npm install     # Install dependencies
npm run dev     # Development server with nodemon hot-reload
npm start       # Production server (node src/app.js)
```

Backend requires a `.env` file with PostgreSQL connection string and JWT secret. Database migrations are SQL files under `code/smartmeasure-backend/src/db/migrations/`.

### Firmware (`firmware/`)

```bash
pio run                          # Build firmware
pio run --target upload          # Build and flash to ESP32 via USB
pio device monitor               # Serial monitor at 115200 baud
pio run --target upload && pio device monitor  # Flash then monitor
```

---

## Architecture

### Data Flow

```
ESP32 (VL53L0X + MPU6050) → BLE → Flutter App → SQLite (local)
                                                 → REST API → PostgreSQL (cloud)
```

The firmware sends measurement packets over BLE. `ble_manager.dart` handles the BLE connection; `ble_packet.dart` parses the binary packet format from the device.

### Flutter App Structure (`code/lib/`)

| Directory/File | Purpose |
|---|---|
| `main.dart` | App entry point, Riverpod `ProviderScope` |
| `core/constants.dart` | Shared constants (BLE UUIDs, etc.) |
| `ble/` | BLE connection management and packet parsing |
| `sketch/` | 2D floor plan: model, painter, screen, PDF export, furniture |
| `ar/` | AR room scanning: camera scan, polygon math, result screen |
| `database/` | SQLite helper, project list, cloud projects, collaboration screens |
| `screens/` | Home screen, login screen, DXF exporter |
| `services/` | `api_service.dart` (HTTP to backend), `sync_service.dart` (local→cloud) |

**State management**: Riverpod throughout. The `SketchModel` (in `sketch/sketch_model.dart`) is the central data model for floor plan geometry, rooms, and furniture.

**3D visualization** (`sketch/room_3d_screen.dart`): renders via a WebView running a Three.js scene — not native Flutter 3D. The Dart side communicates with JavaScript via `webview_flutter`.

**AR flow**: `ar_scan_screen.dart` uses `ar_flutter_plugin_2` to scan room surfaces; `ar_polygon_math.dart` converts AR hit points into floor plan geometry; results are passed to `ar_result_screen.dart`.

**Export**: `sketch/sketch_pdf_export.dart` for PDF; `screens/dxf_exporter.dart` for DXF (CAD format, current feature branch: `feature-Dxf-export`).

### Backend Structure (`code/smartmeasure-backend/src/`)

| File | Purpose |
|---|---|
| `app.js` | Express app setup, route mounting |
| `db/db.js` | PostgreSQL pool via `pg` |
| `middleware/auth_middleware.js` | JWT verification middleware |
| `routes/auth.js` | Register/login, bcryptjs password hashing |
| `routes/projects.js` | CRUD for projects and room data |
| `routes/sync.js` | Sync endpoint for pushing local SQLite data to cloud |

### Firmware Structure (`firmware/src/main.cpp`)

Single-file Arduino sketch. Key concepts:
- **Screen states**: `OFF`, `MODE_SELECT`, `NORMAL`, `BLE_MODE`
- **Measurement states**: `IDLE`, `LASER_ON`, `MEASURED`, `HISTORY`
- BLE GATT service/characteristic UUIDs defined in `core/constants.dart` (Flutter) must match those in `main.cpp`
- Hardware: VL53L0X (LiDAR, I2C), SSD1306 OLED (I2C), buttons (power/select/down/measure), buzzer, laser pointer (GPIO 4)

---

## Key Constraints

- **BLE UUIDs** in `firmware/src/main.cpp` and `code/lib/core/constants.dart` must stay in sync.
- **Packet format** between firmware and `ble_packet.dart` is a custom binary protocol — changes to either side require updating both.
- The Flutter app targets Android primarily; AR features (`ar_flutter_plugin_2`) require a physical device with ARCore support.
- The backend uses Express 5 (not 4) — error handling middleware signature differs (`(err, req, res, next)`).
