# Smart Laser Distance Meter — Complete System Architecture and Code Reference

> **Snapshot:** repository `cepdnaclk/e21-3yp-Smart-Laser-Distance-Meter`, branch `main`, commit `534ad8b` (2026-09-19). Written on 2026-10-22 from a line-by-line reading of every source file in the repository.
>
> **Audience:** AI assistants, coding agents and developers who have never seen this codebase. After reading this document you should be able to explain, debug, extend or rebuild any part of the system without first opening the code.

---

## How to use this document

- **Parts 1 and 2** give the whole picture: what the product is, every feature, the architecture, the technology stack and the repository layout. Read these first.
- **Parts 3–9** are the detailed reference, one subsystem per part. Each part has the same five sections:
  - **N.1 Overview:** responsibilities, vocabulary and a diagram.
  - **N.2 Features and how they work:** end-to-end walkthroughs, from user action to function calls to data to result.
  - **N.3 File reference:** every file, with every class, method and function.
  - **N.4 Data contracts:** exact formats that other parts depend on.
  - **N.5 Known issues and limitations.**
- **Part 10** joins the parts together: end-to-end flows across subsystems, the units and coordinate systems, an identifier cross-reference, build and run instructions, a prioritised issue list, documentation errors, a glossary and a file index.

**Conventions**
- Paths are relative to the repository root.
- `(L123)` is a line number at the snapshot commit. It may drift in later commits.
- "The app" means the Flutter app in `code/`. "The device" means the ESP32 handheld. "The backend" means `code/smartmeasure-backend/`.
- **World units:** the 2D sketch coordinate unit. **1 world unit = 5 mm** (`mmPerUnit = 5.0`), so 200 units = 1 m, with x pointing right and y pointing **down**. Most data in the app is stored in world units (points, furniture positions) or millimetres (wall lengths, object sizes).
- When this document disagrees with `CLAUDE.md` or the README files, **this document reflects the code**. Those older documents contain several errors, listed in §10.7.

## Table of contents

1. [Part 1 — What the system is](#part-1--what-the-system-is)
2. [Part 2 — Architecture, technology stack and repository layout](#part-2--architecture-technology-stack-and-repository-layout)
3. [Part 3 — Firmware and BLE link](#part-3--firmware-and-ble-link)
4. [Part 4 — Flutter app foundation: entry, navigation, state, local database, AR, platform config](#part-4--flutter-app-foundation-entry-navigation-state-local-database-ar-platform-config)
5. [Part 5 — Sketch editor: data model, editing screen and geometry](#part-5--sketch-editor-data-model-editing-screen-and-geometry)
6. [Part 6 — 2D plan rendering and furniture](#part-6--2d-plan-rendering-and-furniture)
7. [Part 7 — Exports: PDF and DXF](#part-7--exports-pdf-and-dxf)
8. [Part 8 — 3D room view (Flutter WebView + Three.js)](#part-8--3d-room-view-flutter-webview--threejs)
9. [Part 9 — Backend, authentication, cloud sync and collaboration](#part-9--backend-authentication-cloud-sync-and-collaboration)
10. [Part 10 — Cross-cutting reference](#part-10--cross-cutting-reference)

---

## Part 1 — What the system is

### 1.1 Summary

**Smart Laser Distance Meter** (the app brands itself **"SmartMeasure Pro"**) is a third-year engineering project from the Department of Computer Engineering, University of Peradeniya, Sri Lanka (batch E21, course "3YP"). It turns a home-made laser distance meter into a floor-plan tool. The system has three parts:

1. **A handheld device.** An ESP32 DevKit reads a **Benewake TF-Luna** time-of-flight LiDAR over UART. It shows readings on a 128×64 SSD1306 OLED and keeps a measurement history on a micro-SD card (`/readings.csv`). It has five buttons, a buzzer and a visible aiming laser. In "Bluetooth mode" it **notifies** each measurement over BLE as a 4-byte packet: distance in mm (big-endian), a battery byte that is always 80, and a "capturing" flag.
2. **A Flutter mobile app** (`smart_measure_pro`; Android is the only realistic target). It lets the user:
   - draw rooms as polygons on a 2D canvas and set each wall's real length, either from the laser device or by typing;
   - place doors, windows, openings and 31 kinds of furniture;
   - manage several rooms in one project;
   - view the plan in **3D** (a Three.js scene inside a WebView, with GLB furniture models);
   - generate a room outline with **AR** (ARCore plane hit-tests);
   - export a **PDF** "Floor Plan Guide" or an AutoCAD **DXF**;
   - save projects locally in **SQLite**;
   - back up, sync and **collaborate** through the cloud.
3. **A Node.js / Express 5 REST backend with PostgreSQL.** It provides accounts (bcrypt + 7-day JWT), whole-project snapshot uploads with conflict detection, invite-code sharing with a per-collaborator `can_edit` flag, change polling for "live" viewing, and presence heartbeats.

### 1.2 Problem and intended solution (from the project README)

Manual indoor measuring and floor-plan sketching is slow and error-prone. The project goal is a handheld meter with a LiDAR distance sensor and an IMU for angles. The meter would compute lengths, areas and volumes and send them over Bluetooth to a phone app that builds 2D wall and floor plans automatically.

**What was actually built differs from that plan in one important way: there is no IMU in the code.** Wall *angles* come from what the user draws on the phone (or from AR), and only *lengths* come from the device. See §1.5.

### 1.3 Team and project context

The README lists the team as:
- E/21/065 Chamod S.A.R.
- E/21/068 Chandrasiri E.M.D.D.V.
- E/21/277 Padukka V.K.
- E/21/325 Rashmika W.B.R.

The project page is published with GitHub Pages from `docs/` (theme `cepdnaclk/eYY-project-theme`). The git history has 317 commits, from 2026-01-25 ("Initial commit") to 2026-09-19 ("Reapply Merge branch 'multi_room'").

### 1.4 Feature catalogue

| # | Feature | What the user gets | Main implementation | Details |
|---|---|---|---|---|
| F1 | Device measurement | Press MEAS to switch the aiming laser on, press again to measure. The OLED shows the result in mm/cm/m. The T/B toggle adds the 146 mm body height. | `firmware/src/main.cpp` (`doMeasure`, state machines) | §3.2 |
| F2 | Device history on SD card | Every measurement is appended to `/readings.csv`. The HISTORY screen pages through up to 100 records. | `main.cpp` (`saveToSD`, `loadHistory`) | §3.2 |
| F3 | BLE transmission | In Bluetooth mode the device advertises as "SmartMeasure Pro" and notifies `[dist_hi, dist_lo, 80, capturing]`. | `main.cpp` (`bleSend`), `code/lib/ble/*` | §3.2, §3.4 |
| F4 | Login / register / skip | Email + password accounts. "Skip for now" gives local-only use. | `screens/login_screen.dart`, `services/api_service.dart`, backend `routes/auth.js` | §9.2 |
| F5 | Connect to device | Scan, connect and subscribe to notifications, then open the sketch. | `ble/ble_connection_screen.dart`, `ble/ble_manager.dart` | §3.2 |
| F6 | 2D room sketching | Draw polygon rooms (tap/drag), close a room, edit vertices, angle snapping, grid, pan/zoom, undo/redo, units. | `sketch/sketch_screen.dart`, `sketch/sketch_painter.dart` | §5.2, §6.2 |
| F7 | Real wall lengths | Select a wall, then measure it with the device (BLE) or type a length. The room is rebuilt so that wall has the real length. Dimension labels turn green. | `SketchScreen._applyRealMeasurement`, `sketch_dialogs.dart` | §5.2 |
| F8 | Multi-room projects | Several `SketchShape` rooms per project, room labels, moving rooms with wall snapping, shared-wall detection. | `sketch_screen.dart`, `wall_topology.dart` | §5.2 |
| F9 | Doors, windows, openings | Objects attached to a wall by index plus position along the wall (0–1), with size, sill height and door-swing flip. | `room_object.dart`, `room_object_utils.dart`, `wall_openings.dart` | §5.2, §6.2 |
| F10 | Furniture | 31 furniture types in six categories. Place, drag, rotate, resize and delete; drawn as plan symbols. | `furniture_item.dart`, `furniture_painter.dart` | §6.2, §6.4 |
| F11 | Area and dimensions | Wall dimension labels (segmented around openings), room area, room labels. | `sketch_painter.dart`, `sketch_constants.dart` | §6.2 |
| F12 | Local save / load | Projects in SQLite `smartmeasure.db` (v4, 9 tables). Open and delete via "My Projects". | `database/database_helper.dart`, `project_list_screen.dart` | §4.2 |
| F13 | PDF export | Multi-page A4 "Floor Plan Guide" (cover, overview, one page per room) sent to the OS print dialog. | `sketch/sketch_pdf_export.dart` | §7.2 |
| F14 | DXF export | Blueprint-style preview, then an AutoCAD R12 (`AC1009`) DXF shared through the share sheet. | `screens/dxf_preview_screen.dart`, `screens/dxf_exporter.dart` | §7.2 |
| F15 | 3D view | Three.js r148 in a WebView: walls with openings, PBR materials, GLB furniture models (procedural fallback), orbit/zoom, tap to select walls, BLE-measure a wall from 3D, change room height. A legacy Dart pseudo-3D painter is also available. | `sketch/room_3d_screen.dart`, `assets/3d/three_room.html` | Part 8 |
| F16 | AR room scan | ARCore session; tap walls to capture planes; reconstruct the room polygon; edit corners and scale; import as a room. **Probably non-functional on Android** with the current plugin (static analysis). | `ar/ar_scan_screen.dart`, `ar/ar_polygon_math.dart`, `ar/ar_result_screen.dart` | §4.2 |
| F17 | Cloud backup and auto-sync | Snapshot uploads through an offline queue (`pending_uploads`), retried on connectivity change and every 60 s, with 409 conflict detection. | `services/sync_service.dart`, backend `routes/sync.js` | §9.2 |
| F18 | Collaboration | Invite codes, joining, a "Shared with me" list, per-collaborator edit permission, presence avatars (30 s heartbeat), "Open live" view with 10 s polling, restore to device. | `database/collaboration_screen.dart`, backend `routes/projects.js`, `routes/sync.js` | §9.2 |

### 1.5 Planned hardware versus implemented hardware

| Item | README / project page says | Firmware actually uses |
|---|---|---|
| Distance sensor | "LiDAR DToF range finder (up to 20 m)"; the budget lists a DTS6012M; CLAUDE.md says VL53L0X | **Benewake TF-Luna** on UART2 (GPIO16 RX / GPIO17 TX, 115200 baud). Readings over 800 cm are rejected. The VL53L0X was removed in commit `0cc4310`. |
| IMU | MPU6050 (README) / BNO055 (budget) | **None.** No IMU code has ever existed in the firmware history. |
| Display | 0.96" OLED (README) / 1.8" TFT (budget) | SSD1306 128×64 OLED, I2C address 0x3C (SDA 21, SCL 22) |
| Storage | — | micro-SD on VSPI (SCK 18, MISO 19, MOSI 23, CS 5), file `/readings.csv` |
| Buttons | — | PWR GPIO25, SEL GPIO27, DOWN GPIO33, MEAS GPIO32, OFFSET (T/B) GPIO35, all active-low |
| Feedback | Buzzer and vibration motor | Buzzer on GPIO26. No vibration-motor code. |
| Laser | Red line laser / green 5 mW laser | Aiming pointer on GPIO4 (`digitalWrite`). It does not measure anything. |
| Battery | 18650 + TP4056 | No battery measurement. The BLE battery byte is the constant 80. |

---

## Part 2 — Architecture, technology stack and repository layout

### 2.1 System context

```mermaid
flowchart LR
  subgraph Device["Handheld device (ESP32, firmware/src/main.cpp)"]
    TF[TF-Luna LiDAR<br/>UART2] --> MCU[ESP32 Arduino loop<br/>Screen FSM x NormalState FSM]
    BTN[5 buttons] --> MCU
    MCU --> OLED[SSD1306 OLED]
    MCU --> SD[(micro-SD<br/>readings.csv)]
    MCU --> BZ[Buzzer / aiming laser]
  end
  MCU -- "BLE GATT notify<br/>4 bytes: dist mm BE, 80, capturing" --> BLE
  subgraph App["Flutter app (code/lib)"]
    BLE[BleManager<br/>flutter_blue_plus] --> SK[SketchScreen<br/>2D editor]
    SK --> P2D[SketchPainter]
    SK --> R3D[Room3DScreen<br/>WebView + Three.js]
    SK --> PDF[PDF export]
    SK --> DXF[DXF preview + export]
    AR[AR scan<br/>ar_flutter_plugin_2] --> SK
    SK --> DB[(SQLite smartmeasure.db)]
    SK --> SYNC[SyncService<br/>offline queue]
    COL[CollaborationScreen] --> SK
  end
  SYNC -- "HTTP JSON + Bearer JWT" --> API
  COL -- HTTP --> API
  subgraph Backend["Backend (code/smartmeasure-backend)"]
    API[Express 5 REST<br/>/auth /projects /sync] --> PG[(PostgreSQL)]
  end
```

The same picture as text, for readers that do not render Mermaid:

```text
[TF-Luna]--UART-->[ESP32 firmware]--BLE notify (4 B)-->[BleManager]-->[SketchScreen (2D editor)]
                     |  OLED, SD card, buzzer, laser                 |   |   |   |   |
                                                                     |   |   |   |   +--> SQLite (DatabaseHelper)
           [AR scan]--polygon(mm)----------------------------------->+   |   |   +--> SyncService --HTTP--> Express API --> PostgreSQL
                                                                         |   +--> PDF / DXF exporters        ^
                                                                         +--> Room3DScreen (WebView, Three.js)  |
                                         CollaborationScreen --HTTP--------------------------------------------+
```

### 2.2 Subsystems and responsibilities

| Subsystem | Location | Responsibility | Talks to |
|---|---|---|---|
| Firmware | `firmware/src/main.cpp` (one file) | Read the sensor, run the UI state machines, log to SD, notify measurements over BLE | App (BLE, one-way) |
| BLE layer | `code/lib/ble/` | Scan, connect and subscribe; parse 4-byte packets into `BlePacket`; broadcast `packetStream` and `connectStream` | Firmware; `SketchScreen`; `Room3DScreen` |
| App shell | `code/lib/main.dart`, `screens/home_screen.dart`, `screens/login_screen.dart` | Start-up login gate, home hub, navigation | Everything |
| Sketch editor | `code/lib/sketch/` (model, screen, dialogs, widgets, topology, openings) | Central data model (`SketchShape`, `RoomObject`, `FurnitureItem`) and all editing | Painter, exporters, 3D, DB, sync |
| 2D rendering | `sketch/sketch_painter.dart`, `sketch/furniture_painter.dart` | Draw the plan on a `CustomPainter` | Sketch editor |
| Exports | `sketch/sketch_pdf_export.dart`, `screens/dxf_*.dart` | PDF via `pdf`/`printing`; DXF R12 via a hand-written writer and `share_plus` | Sketch editor (read-only) |
| 3D view | `sketch/room_3d_screen.dart`, `assets/3d/` | Serialise the plan to JSON (metres, Y up) and render it in Three.js inside `webview_flutter` | Sketch editor (callbacks), BLE |
| AR | `code/lib/ar/` | Capture wall planes and turn them into a polygon in mm, then into a `SketchShape` | Sketch editor |
| Local storage | `database/database_helper.dart` | SQLite schema v4, save/load/delete projects, upload queue | Sketch editor, `SyncService`, collaboration |
| Cloud client | `services/api_service.dart`, `services/sync_service.dart`, `database/collaboration_screen.dart` | REST wrapper, JWT storage, offline upload queue, collaboration UI | Backend |
| Backend | `code/smartmeasure-backend/src/` | Auth, projects, sharing, snapshot sync, presence | PostgreSQL |

**State management in the app.** `flutter_riverpod` is a dependency and `main.dart` wraps the app in a `ProviderScope`, but **no providers exist**. State is held in:
- `StatefulWidget`s with `setState` (`SketchScreen` alone has about 80 `setState` calls);
- two singletons, `DatabaseHelper.instance` and `SyncService.instance`;
- the static class `ApiService`;
- a `BleManager` object passed through constructors;
- broadcast streams.

Full census in §4.2.10.

### 2.3 Technology stack

**Firmware**

| Item | Value |
|---|---|
| Build system | PlatformIO, `platform = espressif32`, `board = esp32dev`, `framework = arduino`, `monitor_speed = 115200`. `upload_port` and `monitor_port` are hard-coded to `COM14`. |
| Language | C++ (Arduino) in a single sketch |
| Libraries | `lib_deps`: Adafruit SSD1306 ^2.5.7, Adafruit GFX ^1.11.9, Adafruit BusIO ^1.14.5. Bundled with the ESP32 core: `Wire` (I2C), `SPI` + `SD` (micro-SD), `BLEDevice`/`BLEServer`/`BLEUtils`/`BLE2902` (Bluedroid BLE), `HardwareSerial` (TF-Luna). The TF-Luna protocol is parsed by hand; no sensor library is used. |

**Mobile app** (`code/pubspec.yaml`; resolved versions from the local, uncommitted `pubspec.lock`)

| Concern | Package (resolved version) |
|---|---|
| Framework | Flutter (Dart SDK `^3.10.7`; lock requires Flutter ≥ 3.38.4). Developed with Flutter 3.41.7 / Dart 3.11.5. |
| BLE | `flutter_blue_plus` 1.36.8 |
| Local DB | `sqflite` 2.4.2, `path` 1.9.1 |
| HTTP / auth storage | `http` 1.6.0, `flutter_secure_storage` 9.2.4 |
| Connectivity | `connectivity_plus` 6.1.5 |
| 3D | `webview_flutter` 4.14.1 + bundled Three.js r148 (`three.min.js`) and `GLTFLoader` (`gltf_loader.js`) |
| AR | `ar_flutter_plugin_2` 0.0.3, `vector_math` 2.2.0 (`permission_handler` 11.4.0 is declared but only used transitively) |
| PDF | `pdf` 3.12.0, `printing` 5.13.1 |
| DXF sharing | `path_provider` 2.1.5, `share_plus` 9.0.0 |
| State (declared, unused) | `flutter_riverpod` / `riverpod` 2.6.1 |
| Dev | `flutter_lints` 6.0.0, `flutter_launcher_icons` 0.13.1, `flutter_test` |

**Android build:**
- namespace / applicationId `com.example.smart_measure_pro`
- minSdk 28, targetSdk = Flutter default
- Kotlin Gradle DSL (`*.gradle.kts`)
- cleartext HTTP allowed
- release builds signed with the debug key

Details in §4.3.

**Backend** (`code/smartmeasure-backend/package.json`)

| Item | Value |
|---|---|
| Runtime | Node.js (CommonJS). Developed with Node 22.19.0. |
| Framework | Express 5 (5.2.1) |
| Database | PostgreSQL via `pg` 8.20.0 `Pool`. Configured by `DATABASE_URL` (with SSL `rejectUnauthorized: false`) or by separate `DB_*` variables. |
| Auth | `bcryptjs`, `jsonwebtoken` (7-day tokens, `JWT_SECRET`) |
| Other | `cors` (origin `*`), `dotenv`; `nodemon` for `npm run dev` |
| Deployment | No Dockerfile or CI. The app's `ApiService.baseUrl` is hard-coded to `http://13.214.196.211:3000`; earlier values were a LAN IP and then Railway (§9.1). |

### 2.4 Repository layout

```text
e21-3yp-Smart-Laser-Distance-Meter/
├── README.md                   Project page text: team, intro, planned hardware (partly inaccurate, §1.5)
├── CLAUDE.md                   Guidance for Claude Code (contains errors, §10.7)
├── ARCHITECTURE.md             This document
├── .gitignore                  Flutter rules; ALSO ignores *.lock, *.glb, *.gltf (affects builds, §10.5)
├── .gitattributes              text=auto
├── .metadata, .idea/           Duplicates of code/.metadata and code/.idea (the Flutter project was once opened at the root)
├── .vscode/                    C/C++ Runner + gdb launch config (desktop C++ debugging, unrelated to PlatformIO)
├── docs/                       GitHub Pages project site (Jekyll, theme cepdnaclk/eYY-project-theme)
│   ├── README.md               Project page: team, architecture image, budget table
│   ├── _config.yml             Jekyll configuration
│   ├── data/index.json         Template placeholder team/supervisor data (never filled in)
│   ├── export_feature_explained.md   Explanation of the PDF/DXF exports (partly outdated, §7.3)
│   └── images/                 download.png (logo), "High Level Architecture Diagram.png", sample.png
├── firmware/                   ESP32 firmware (PlatformIO)
│   ├── platformio.ini          Board, framework, lib_deps
│   ├── src/main.cpp            THE ENTIRE FIRMWARE (723 lines)
│   ├── include/, lib/, test/   PlatformIO placeholder READMEs only
│   └── .vscode/                PlatformIO IDE settings
└── code/                       Flutter app "smart_measure_pro" (the backend is nested inside)
    ├── pubspec.yaml            Dependencies, assets (assets/icon/, assets/3d/, assets/models/), launcher-icon config
    ├── analysis_options.yaml   flutter_lints
    ├── temp.js                 Stale, unreferenced copy of an older three_room.html script (§8.3)
    ├── lib/
    │   ├── main.dart                     Entry, ProviderScope, MaterialApp, AppStartup login gate
    │   ├── core/constants.dart           AppConstants (only appName is used; the UUIDs there are stale placeholders)
    │   ├── ble/                          ble_manager.dart, ble_packet.dart, ble_connection_screen.dart
    │   ├── sketch/                       THE CORE: sketch_screen.dart (4161 lines), sketch_model.dart,
    │   │                                 sketch_constants.dart, sketch_painter.dart, sketch_dialogs.dart,
    │   │                                 sketch_widgets.dart, room_object.dart, room_object_utils.dart,
    │   │                                 wall_openings.dart, wall_topology.dart, furniture_item.dart,
    │   │                                 furniture_painter.dart, sketch_pdf_export.dart, room_3d_screen.dart
    │   ├── ar/                           ar_scan_screen.dart, ar_polygon_math.dart, ar_result_screen.dart
    │   ├── database/                     database_helper.dart, project_list_screen.dart,
    │   │                                 collaboration_screen.dart, cloud_projects_screen.dart (unreachable)
    │   ├── screens/                      home_screen.dart, login_screen.dart, dxf_exporter.dart, dxf_preview_screen.dart
    │   ├── services/                     api_service.dart, sync_service.dart
    │   └── furniture_3d_viewer.dart      Empty file (0 bytes)
    ├── assets/
    │   ├── 3d/three_room.html            Custom Three.js scene (template with a <!--THREE_JS--> placeholder)
    │   ├── 3d/three.min.js               Vendored Three.js r148
    │   ├── 3d/gltf_loader.js             Vendored non-module GLTFLoader
    │   ├── icon/app_icon.png             Launcher icon source
    │   └── models/                       35 GLB/GLTF furniture models (~201 MB). LOCAL ONLY: git-ignored, absent in clones.
    ├── test/widget_test.dart   Unmodified counter template; does not compile (references MyApp)
    ├── android/                Customised: manifest permissions (BLE, location, camera, internet), minSdk 28, AR meta-data
    ├── ios/                    Mostly template (camera usage string only)
    ├── web/, linux/, macos/, windows/   Untouched `flutter create` templates
    └── smartmeasure-backend/   Node.js backend
        ├── package.json
        ├── src/app.js                     Express setup, routes, /health
        ├── src/db/db.js                   pg Pool
        ├── src/middleware/auth_middleware.js   Bearer JWT check
        ├── src/routes/auth.js             POST /auth/register, /auth/login
        ├── src/routes/projects.js         Project list/create/share/join/collaborators/edit-access/leave/delete
        ├── src/routes/sync.js             POST /sync/upload, GET /sync/download, /sync/updates, presence
        ├── migrations/003–006 *.sql       Incremental migrations (001/002, the base schema, are NOT in the repo)
        └── git                            Stray empty file
```

**Code size (lines) by area:**

| Area | Lines |
|---|---|
| Sketch module | ≈ 10,750 (`sketch_screen.dart` 4,161) |
| Collaboration and database | ≈ 1,850 |
| Exports (DXF screens, outside the sketch module) | ≈ 1,300 |
| AR | ≈ 770 |
| BLE | ≈ 290 |
| `three_room.html` | 1,652 |
| Backend JavaScript | ≈ 850 |
| Firmware | 723 |

### 2.5 Development history and branches

- 317 commits between 2026-01-25 and 2026-09-19. Earlier work was merged in from an older repository on 2026-03-12 (`oldrepo/feature/canvas`, `oldrepo/feature/export`).
- Milestones visible in merges:
  - first working app version (April 2026);
  - backend, objects and database (2026-04-23);
  - Railway deployment branch (2026-04-26);
  - bug-fixing PRs (May);
  - 3D room view (`feature/3d-room-view`, 2026-05-16);
  - local memory and sync (`feature/local-memory`, PR #8, 2026-05-19);
  - TF-Luna firmware (`feature/firmware-upto-date`, 2026-09-15);
  - zoom (`feature-zoom`) and `dev-merge` (PR #11, 2026-09-16);
  - `multi_room`, merged, reverted and re-applied on 2026-09-19 (the current HEAD).
- Other remote branches that are **not** merged into `main` and are not described here:
  - `app-release`, `backend-host-azure`, `backend/railwaysetup`, `feature-Dxf-export`, `feature-AR`;
  - `testing/unit_testing`, `unitTest_Ridmal`, `webapp`, `project-webpage`;
  - `gh-pages` (the project website).

---

## Part 3 — Firmware and BLE link

### 3.1 Overview

**Scope.** This part covers two things. The first is the firmware of the handheld "SmartMeasure Pro" device: `firmware/`, a PlatformIO project whose whole program is the single Arduino sketch `firmware/src/main.cpp`. The second is the app-side Bluetooth Low Energy (BLE) link that receives the device's measurements: `code/lib/ble/ble_manager.dart`, `ble_packet.dart` and `ble_connection_screen.dart`, plus the constants file `code/lib/core/constants.dart`, which the BLE code does not actually use. The part stops at the two call sites that turn a received distance into a wall length: the 2D listener in `SketchScreen` and `Room3DScreen._triggerBleMeasurement`. The geometry those call sites perform is documented in the sketch and 3D parts.

**What the hardware really is.** These facts were checked against the code. They contradict CLAUDE.md and the READMEs.
- MCU: ESP32 DevKit (`board = esp32dev`) running the Arduino framework.
- **Distance sensor: a Benewake TF-Luna**, a single-point time-of-flight LiDAR. It is wired to **UART2** (`HardwareSerial tfSerial(2)`; ESP32 RX = GPIO16, TX = GPIO17; 115200 baud, 8N1). Its frames are parsed by hand-written code in `doMeasure()`. The **VL53L0X** that CLAUDE.md names was removed in commit `0cc4310` ("update gradle, platformio, and firmware change for new tf luna sensor"). That commit also dropped `pololu/VL53L0X @ ^1.3.1` from `lib_deps`. No VL53L0X code remains. The only traces left are a stale include path in `.vscode/settings.json` and a compiled copy in the local, git-ignored `.pio` build cache.
- **No IMU is used anywhere.**
  - The firmware has no MPU6050 or BNO055 include, no I2C address 0x68, and no register access.
  - `git log -S MPU -- firmware` finds no commit that ever contained one.
  - The BLE packet has no angle or orientation field.
  - `code/pubspec.yaml` declares no phone-sensor package.
  - So the IMU, "angle detection" and "inertial measurement" claims are design intent, not implementation. They appear in `README.md` (L48, L57, L72), in `docs/README.md` (L55, L74; L99 also budgets a "BNO055 9-Axis IMU Module") and in CLAUDE.md ("ESP32 (VL53L0X + MPU6050)").
  - In the app, wall directions come only from what the user draws, or from the AR part.
- The I2C bus (SDA GPIO21, SCL GPIO22) carries **only** the SSD1306 128×64 OLED at address 0x3C.
- The device has hardware that CLAUDE.md does not mention:
  - a micro-SD card on the VSPI bus (SCK 18, MISO 19, MOSI 23, CS 5), holding the CSV log `/readings.csv`;
  - a fifth push button on GPIO35 that toggles the "top/bottom" reference offset (+146 mm).
- The "laser" on GPIO4 is a visible **aiming pointer** switched with `digitalWrite`. It is not the measuring emitter; the TF-Luna has its own emitter.
- README.md claims a "LiDAR DToF range finder (up to 20 m)" and an "18650 battery with TP4056". The firmware rejects anything beyond 800 cm (8 m). It never measures the battery: the battery byte in every BLE packet is the constant `80`.

**App-side facts that differ from CLAUDE.md.**
- The BLE UUIDs the app actually uses are the top-level constants `serviceUuid` and `characteristicUuid` in `ble_manager.dart`. They match the firmware. `AppConstants.bleServiceUUID`, `bleCharacteristicUUID` and `deviceName` in `core/constants.dart` are placeholders that do **not** match, and nothing uses them.
- Riverpod plays no part. `BleManager` is a plain object. `HomeScreen` creates a new one on every "Start Room Sketch" tap and passes it through constructors: `BleConnectionScreen` → `SketchScreen` → `Room3DScreen`.

**Vocabulary.**

| Term | Meaning |
|---|---|
| Screen state (`enum Screen`, main.cpp L93) | Top-level device mode: `OFF`, `MODE_SELECT`, `NORMAL`, `BLE_MODE`. |
| Normal state (`enum NormalState`, L97) | Measuring sub-state, shared by NORMAL and BLE_MODE: `IDLE`, `LASER_ON`, `MEASURED`, `HISTORY`. |
| T / B reference | `measureFromBottom == false` → "T" (top): the raw sensor distance. `true` → "B" (bottom): raw + `DEVICE_HEIGHT_MM` (146 mm). Shown as a letter at the top-right of the OLED. |
| Triggered | `Button.triggered`: true for exactly one `loop()` iteration after a debounced press (falling edge). |
| Capturing packet | BLE notification `00 00 50 01`. Sent when the aiming laser is switched on in BLE mode. |
| Measurement packet | BLE notification `<dist_hi> <dist_lo> 50 00`. Carries a valid distance in mm. |
| Waiting for BLE | App-side flag `_waitingForBle` (one in `SketchScreen`, another in `Room3DScreen`). It means "apply the next measurement packet to the selected wall". |

**How the files fit together.**

```text
firmware/src/main.cpp  (single Arduino sketch on ESP32, framework = arduino)
  buttons GPIO25 PWR / 27 SEL / 33 DOWN / 32 MEAS / 35 OFFSET (active low)
      | updateButton(): 50 ms debounce -> Button.triggered (one loop pass)
      v
  loop(): T/B toggle (any state) -> Screen FSM (OFF/MODE_SELECT/NORMAL/BLE_MODE)
                                    x NormalState FSM (IDLE/LASER_ON/MEASURED/HISTORY)
      |-- doMeasure()  -- UART2 GPIO16/17 115200 --> TF-Luna (9-byte frames, cm)
      |-- showXxx()    -- I2C GPIO21/22 ---------> SSD1306 OLED 128x64 @ 0x3C
      |-- saveToSD() / loadHistory() -- SPI 18/19/23, CS 5 --> /readings.csv
      |-- beep() GPIO26 buzzer ; LASER_PIN GPIO4 aiming laser
      '-- bleSend() --> GATT notify
                        service 4fafc201-1fb5-459e-8fcc-c5c9c331914b
                        char    beb5483e-36e1-4688-b7f5-ea07361b26a8 (NOTIFY, CCCD 0x2902)
                        payload [dist_hi, dist_lo, 80, capturing?1:0]   (big-endian mm)
                              |
                              v   flutter_blue_plus 1.36.8 (Android)
code/lib/ble/ble_manager.dart   BleManager.connectToDevice(): scan, match platformName
                                == "SmartMeasure Pro" -> _connect(): connect,
                                discoverServices, setNotifyValue(true), onValueReceived
                                -> BlePacket.fromBytes() -> packetStream (broadcast)
code/lib/ble/ble_packet.dart    BlePacket {distanceMm, batteryPercent, isCapturing}
code/lib/ble/ble_connection_screen.dart   CONNECT / Skip UI; connectStream(true)
                                -> 1 s -> onConnected()
                              |
  HomeScreen "Start Room Sketch": new BleManager -> BleConnectionScreen
        onConnected: Navigator.pushReplacement(SketchScreen(bleManager))
  SketchScreen.initState: packetStream.listen -> _applyRealMeasurement(wall, mm)  (2D)
  Room3DScreen._triggerBleMeasurement: packetStream.where(..).first
        -> wallRealMm[wall] = mm ; onWallMeasured(wall, mm)                         (3D)
code/lib/core/constants.dart    AppConstants (placeholder BLE UUIDs/name; only appName used)
```

### 3.2 Features and how they work

#### 3.2.1 Boot sequence (firmware `setup()`, main.cpp L402)
Trigger: the ESP32 powers up or resets.
1. `Serial.begin(115200)` opens the debug UART over USB, then `Wire.begin(21, 22)` starts I2C.
2. Pin modes are set:
   - GPIO25, 27, 33 and 32 become `INPUT_PULLUP` buttons.
   - GPIO35 becomes plain `INPUT`. It is an input-only pin with no internal pull-up, so an external 10 kΩ pull-up to 3.3 V is required (comment at L25/L410).
   - GPIO26 (buzzer) and GPIO4 (laser) become `OUTPUT` and are driven LOW.
3. `display.begin(SSD1306_SWITCHCAPVCC, 0x3C)` initialises the OLED; its return value is ignored. The display is set to white text, cleared, and a blank frame is pushed.
4. `tfSerial.begin(115200, SERIAL_8N1, 16, 17)`, then 100 ms. Nothing is ever written to the TF-Luna. It runs on factory defaults and streams frames continuously.
5. `SPI.begin(18, 19, 23, 5)`, then 200 ms, then `SD.begin(5, SPI, 4000000)` (4 MHz).
   - On success, `sdReady = true`. If `/readings.csv` does not exist, it is created with the header line `count,mm,millis`.
   - Failure is silent. The SD features later show "SD not available" or give a long beep.
6. The BLE GATT server is built (3.2.9). Advertising is **not** started here.
7. Serial prints `Ready - press PWR to start`. Initial state:
   - `currentScreen = OFF`, `normalState = IDLE`, `selectedMode = 0`;
   - `measureFromBottom = false`, `recordCount = 0`, `lastMm = 0`;
   - OLED blank.

#### 3.2.2 Soft power on/off
- "OFF" is only a UI state. In OFF the OLED is blank and only PWR (plus the T/B button) has any effect.
  - The ESP32, the TF-Luna (still streaming), the SD card and the BLE controller all stay powered.
  - No light or deep sleep is used. The OLED is only cleared; the SSD1306 display-off command is never sent.
  - A physical power switch, if one exists, is outside the code.
- OFF + PWR → MODE_SELECT: `selectedMode = 0`, `beep(1)`, `showModeSelect()`.
- PWR leads to OFF from three states: MODE_SELECT, NORMAL/IDLE and BLE_MODE/IDLE. Each clears the OLED and calls `beep(2)`. The BLE_MODE path also forces `LASER_PIN` LOW first.
  - From LASER_ON, MEASURED or HISTORY, PWR only returns to IDLE ("cancel"/"back"), so switching off from those states takes two presses.
- Going OFF does **not** stop BLE advertising and does not drop an existing connection. BLE connect/disconnect callbacks can still repaint the screen while the device is "off" (3.2.9).

#### 3.2.3 Mode selection
- The `showModeSelect()` screen lists "Normal Mode" and "Bluetooth Mode". The entry at `selectedMode` (0 or 1) is prefixed with "> ".
- DOWN: `selectedMode = (selectedMode + 1) % 2`, `beep(1)`, redraw. Only two entries exist, so this toggles.
- SEL: `beep(2)`, then:
  - mode 0 → `currentScreen = NORMAL`, `normalState = IDLE`, `showIdle()`;
  - mode 1 → `currentScreen = BLE_MODE`, `normalState = IDLE`. Then `BLEDevice::getAdvertising()` → `addServiceUUID(SERVICE_UUID)` → `setScanResponse(true)` → `BLEDevice::startAdvertising()`. It draws the "-- Bluetooth -- / BLE Mode / Waiting for app... / Open SmartMeasure / PWR=off" screen and logs `BLE advertising` (L496–515).
- NORMAL and BLE_MODE behave identically except in four ways. BLE_MODE:
  1. sends the capturing packet when the laser is switched on;
  2. sends the measurement packet when a valid measurement is taken;
  3. shows "BLE" instead of "NRM" in the header;
  4. forces the laser off when powering off from IDLE.
- Both modes can save to SD and browse history. NORMAL never calls `bleSend`, even if an app is still connected from an earlier BLE session.

#### 3.2.4 Aim and measure (laser + TF-Luna)
Trigger: MEAS in IDLE (laser on), then MEAS again in LASER_ON (measure).
1. **IDLE + MEAS:** `digitalWrite(LASER_PIN, HIGH)` (steady aiming dot). In BLE_MODE only, `bleSend(0, true)` sends the capturing packet. Then `beep(1)`, `showLaserOn()`, → LASER_ON.
2. **LASER_ON + PWR:** laser LOW, `beep(1)`, `showIdle()`, → IDLE.
3. **LASER_ON + MEAS:** `doMeasure()` (L302) runs these steps:
   1. It blinks the aiming laser three times: LOW 150 ms, then HIGH 150 ms, ×3 = 900 ms. It then switches the laser **off**, and the laser stays off during and after the measurement.
   2. `showMeasuring()` draws "Measuring...".
   3. It drains the UART2 receive buffer (`while (tfSerial.available()) tfSerial.read();`) to discard stale frames, then waits `delay(20)`.
   4. For at most 500 ms (busy loop on `millis()`) it syncs to the frame header:
      - it waits until ≥ 9 bytes are buffered;
      - it reads one byte, which must be `0x59` (otherwise it resyncs);
      - the next byte (`peek`) must also be `0x59` and is consumed;
      - it reads 7 more bytes into `buf[0..6]`.
   5. Checksum: `(0x59 + 0x59 + buf[0] + … + buf[5]) & 0xFF` must equal `buf[6]`. On a mismatch it logs `TF-Luna: bad checksum, retrying` and continues the loop.
   6. Decode, little-endian:
      - `cm = buf[0] | buf[1] << 8` (distance in centimetres);
      - `flux = buf[2] | buf[3] << 8` (signal amplitude);
      - `buf[4..5]` (chip temperature, per the TF-Luna datasheet) are ignored;
      - it logs `TF-Luna raw: <cm> cm  flux: <flux>`.
   7. Validity checks return `-1` immediately:
      - `flux < 100` or `flux == 65535` → `signal quality fail`;
      - `cm < 20` or `cm > 800` → `out of range`.

      The **first checksum-valid frame decides**. A weak or out-of-range frame fails the whole measurement; the code does not try the next frame.
   8. `resultMm = (float)(cm * 10)`, so the resolution is 10 mm. If `measureFromBottom` is set, `resultMm += 146.0`, logged as `Bottom mode: +146mm -> <mm>`. The result is returned.
   9. If no valid frame arrives within 500 ms, it logs `TF-Luna: read timeout` and returns `-1`.

   No averaging, median or smoothing is applied: one frame is one measurement. The only calibration is the 146 mm reference shift.
4. **Result handling in `loop()`:**
   - **Failure (`mm < 0`):**
     1. `beep(1, true)` (600 ms).
     2. Error screen: header, "Out of range!", "Check target surface", plus "Press MEAS again" in NORMAL mode only.
     3. `delay(1500)`, laser HIGH again, `showLaserOn()`. The state stays LASER_ON.

     The same text is shown for weak signal, out of range and timeout. **Nothing is sent over BLE on failure.**
   - **Success:**
     - NORMAL: `lastMm = mm` → `beep(1)` → `showResult(lastMm)` → MEASURED.
     - BLE_MODE: `lastMm = mm` → `bleMeasureCount++` → `beep(1)` → `bleSend(lastMm, false)` → `showResult(lastMm)` → MEASURED → Serial `BLE sent: <mm> mm`. This log line is printed even when no client is connected.
5. **MEASURED + MEAS** saves the value (3.2.6). **MEASURED + PWR** does `beep(1)`, `showIdle()`, → IDLE: the value is discarded locally, although in BLE mode it has already been sent.

**Output range and display.**
- Valid output is 200–8000 mm with reference T, or 346–8146 mm with B.
- `showResult` uses text size 2. It shows `<(int)mm> mm` below 1000 mm and `<mm/1000 to 2 decimals> m` from 1000 mm up (e.g. "1.46 m").

**Latency.** From the second MEAS press to the result takes about 0.9 s of blinking, plus the OLED transfer, plus 20 ms, plus the first frame (the TF-Luna default is 100 Hz), plus the 180 ms beep. Buttons are not sampled during this blocking period.

#### 3.2.5 Top/Bottom reference toggle (button on GPIO35)
- It is handled at the start of every `loop()` iteration, before the per-screen logic (L458–471), so it works in **every** state, including OFF.
- Action:
  1. `measureFromBottom = !measureFromBottom`, then `beep(1)`.
  2. Serial `Mode: BOTTOM (+146mm)` or `Mode: TOP (raw)`.
  3. Redraw the current screen so that the indicator drawn by `drawModeIndicator()` at (122,0) shows "T" or "B":
     - MODE_SELECT → `showModeSelect()`;
     - NORMAL/BLE_MODE → `showIdle()`, `showLaserOn()`, `showResult(lastMm)` or `showHistory()`, according to `normalState`;
     - OFF → no redraw (beep only).
- The toggle affects only **future** measurements (step 3.8 of 3.2.4). A result already on screen is not recomputed: toggling in MEASURED changes the letter but not the number.
- In BLE_MODE/IDLE the redraw replaces the "Waiting for app..." or "App Connected!" screen with `showIdle()`.
- The setting lives in RAM only and resets to T at every boot. The BLE packet does not carry it, so the app cannot tell which reference produced a distance.

#### 3.2.6 Saving a measurement to the SD card
- **MEASURED + MEAS** calls `saveToSD(lastMm)` (L288):
  1. If `!sdReady`, it returns false.
  2. It opens `/readings.csv` with `FILE_APPEND`; if the open fails, it returns false.
  3. `recordCount++`.
  4. It writes `<recordCount>,<mm with 1 decimal>,<millis()>` plus CRLF (Arduino `println`), closes the file and returns true.
- On true: `beep(3)` and `showSaved(lastMm)` (">> SAVED! <<", the value, "Total: <recordCount>") for 1.5 s. On false: `beep(1, true)`. Either way it then calls `showIdle()` and goes to IDLE.
- Example row: `3,1460.0,183422`.
- `recordCount` starts at 0 at every boot and is not derived from the file. Numbering therefore restarts each session and duplicates earlier numbers, and "Records:"/"Total:" count only this session's saves.
- `millis` is milliseconds since boot (no RTC), not a date.

#### 3.2.7 History viewer
- **IDLE + SEL:**
  1. `loadHistory()`.
  2. `historyOffset = max(0, historyTotal - 3)`. This duplicates what `loadHistory()` already did.
  3. `showHistory()`, → HISTORY.
- **`loadHistory()` (L227):**
  - It sets `historyTotal = 0` and returns if `!sdReady` or the file cannot be opened.
  - Otherwise it reads `/readings.csv` line by line (`readStringUntil('\n')`, `trim()`). It skips lines starting with `count` (the header) or shorter than 3 characters.
  - It stores lines in `String historyLines[100]` and stops at 100. It therefore keeps the **first** 100 data rows of the file, not the last 100.
  - It sets `historyOffset` so that the last three loaded rows are visible.
- **`showHistory()` (L244):**
  - Title "-- History --", T/B indicator, rule at y=10.
  - With no SD: "SD not available". With no rows: "No records yet". Both show "PWR=back".
  - Otherwise up to 3 rows at y = 14, 28, 42, formatted `#<count>  <mm> mm`, using the first two comma-separated fields. The mm text is shown exactly as stored, e.g. `1460.0`.
  - Footer: `<offset+1>-<min(offset+3,total)>/<total>` at (80,54), then `PWR=back SEL/DWN=scroll` at (0,54). These overlap (see issues).
- **Navigation:**
  - DOWN: if `historyOffset + 3 < historyTotal`, `historyOffset++` (towards newer rows), `beep(1)`, redraw.
  - SEL: if `historyOffset > 0`, `historyOffset--` (towards older rows), `beep(1)`, redraw.
  - At either end, presses are silently ignored. History opens at the newest loaded rows, so DOWN does nothing at first.
  - PWR: `beep(1)`, `showIdle()`, → IDLE.
- Because only the first 100 rows are loaded, once the file holds more than 100 records the newest ones are never visible on the device.

#### 3.2.8 Buzzer and laser feedback
`beep(int times, bool longBeep = false)` (L82) drives GPIO26 HIGH/LOW with blocking `delay()` as an on/off (active) buzzer; there is no PWM tone. With `longBeep` it ignores `times` and sounds once for 600 ms.

| Call | Timing | Used for |
|---|---|---|
| `beep(1)` | 80 ms on + 100 ms off | OFF→MODE_SELECT; menu cursor move; laser on; successful measurement; cancel/back (PWR in LASER_ON, MEASURED, HISTORY); history scroll; T/B toggle |
| `beep(2)` | 2 × (80 + 100) ms = 360 ms | mode confirmed (SEL in MODE_SELECT); power off; BLE client connected (`onConnect`) |
| `beep(3)` | 540 ms | measurement saved to SD |
| `beep(1, true)` | 600 ms | measurement failed; SD save failed |

| Moment | `LASER_PIN` (GPIO4) |
|---|---|
| boot | LOW |
| IDLE + MEAS | HIGH (steady aiming dot) |
| `doMeasure()` | 3 × (150 ms LOW, 150 ms HIGH), then LOW for the measurement and afterwards |
| measurement failed | HIGH again after the 1.5 s error screen |
| LASER_ON + PWR (cancel) | LOW |
| BLE_MODE IDLE + PWR (off) | LOW (explicit; the NORMAL path relies on the laser already being off in IDLE) |

#### 3.2.9 BLE server, advertising and connection handling (firmware)
- **GATT build (in `setup()`, L434–443):**
  1. `BLEDevice::init("SmartMeasure Pro")` sets the GAP device name.
  2. `bleServer = BLEDevice::createServer()`, then `setCallbacks(new MyServerCallbacks())`.
  3. `createService(SERVICE_UUID)`.
  4. `bleChar = svc->createCharacteristic(CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_NOTIFY)`.
  5. `bleChar->addDescriptor(new BLE2902())` adds the CCCD that lets the client enable notifications.
  6. `svc->start()`.
- **Advertising:**
  - It starts **only** when the user confirms "Bluetooth Mode" (L499–502): `addServiceUUID(SERVICE_UUID)`, `setScanResponse(true)`, `BLEDevice::startAdvertising()`.
  - Defaults from the Arduino-ESP32 BLE library (`BLEAdvertising` constructor and `start()`, Arduino-ESP32 2.0.17 as installed locally):
    - connectable undirected (`ADV_TYPE_IND`), public address;
    - interval 0x20–0x40, i.e. 20–40 ms;
    - flags: general discoverable, BR/EDR not supported.
  - Because scan response is enabled, the library leaves the name and TX power out of the advertising packet, which carries the 128-bit service UUID. It puts the **complete local name "SmartMeasure Pro"** in the scan response. The app's Android scan is active (scan mode `lowLatency`), so it receives the name.
  - The ESP32 stack stops advertising by itself when a central connects. `onDisconnect` restarts it with `s->startAdvertising()`.
  - The firmware **never stops** advertising itself. Leaving BLE mode (PWR → OFF → NORMAL) leaves it advertising and/or connected.
  - Every entry into BLE mode calls `addServiceUUID` again. `BLEAdvertising::addServiceUUID` just `push_back`s, so duplicate entries pile up in the library's list.
- **`MyServerCallbacks::onConnect` (L377):** `bleConnected = true`, `bleMeasureCount = 0`, `beep(2)`, Serial `BLE connected`, `showBleReady()`. That screen shows header "BLE", "App Connected!", "Select wall in app", "Press MEAS to shoot" and "Sent: 0". It does not change `currentScreen` or `normalState`.
- **`MyServerCallbacks::onDisconnect` (L384):** `bleConnected = false`, `s->startAdvertising()`. It draws "-- Bluetooth --" with the T/B indicator and a rule, "App disconnected", "Waiting for app...", and logs `BLE disconnected`. It does not change state.
- **Execution context:**
  - Both callbacks run on the Bluedroid stack task, not the Arduino loop task. `beep()` blocks that task with `delay()`.
  - They draw into the shared Adafruit display buffer without locking.
  - They repaint the OLED whatever the device is doing, even in OFF, NORMAL, HISTORY or LASER_ON. The screen and the state machine can then disagree until the next redraw.
- **Security:** none. There is no pairing, bonding, encryption or allow-list; any central can connect and subscribe.
- **Commands from the app:** none. The characteristic has no WRITE property and no `BLECharacteristicCallbacks` are installed. The device cannot be triggered, configured or queried from the phone.

#### 3.2.10 Sending a measurement over BLE (firmware `bleSend`, L364)
- `bleSend(float mm, bool capturing)` builds and sends one packet:
  1. It returns at once if `!bleConnected` or `bleChar == nullptr`.
  2. `dist = (uint16_t)constrain(mm, 0, 65535)`: the float mm is clamped and truncated to whole millimetres.
  3. It builds `packet[4] = { dist >> 8, dist & 0xFF, 80, capturing ? 0x01 : 0x00 }`.
  4. `bleChar->setValue(packet, 4)` then `bleChar->notify()`. The library sends only if a client is connected **and** has enabled notifications in the 0x2902 descriptor.
- Exactly two call sites exist, both in BLE_MODE:

| When | Call | Bytes on air |
|---|---|---|
| BLE_MODE, IDLE, MEAS pressed (laser on) | `bleSend(0, true)` (L625) | `00 00 50 01` |
| BLE_MODE, LASER_ON, MEAS pressed, `doMeasure()` ≥ 0 | `bleSend(lastMm, false)` (L661) | `hi lo 50 00`, e.g. 1460 mm → `05 B4 50 00`; with B reference 1606 mm → `06 46 50 00` |

- Nothing is sent on measurement failure, on save, on cancel, in HISTORY, periodically, or in NORMAL mode. A packet carries no sequence number, timestamp, wall identifier or reference (T/B) flag.

#### 3.2.11 Finding and connecting to the device (app)
Preconditions:
- The device must be in Bluetooth Mode, i.e. advertising. In NORMAL mode it does not advertise, unless BLE mode was entered earlier in the same power cycle.
- The app must use the "Start Room Sketch" path. Opening a project from "My Projects" (`SketchScreen(initialLocalProjectId:)`) or from the AR result (`SketchScreen(initialShapes:)`) gives no BLE manager. So does collaboration (`SketchScreen(bleManager: null)`, collaboration_screen.dart L937).

Steps:
1. **Create the manager and open the connection screen.** `HomeScreen` "Start Room Sketch" (home_screen.dart L89–117) runs `final bleManager = BleManager();`. It then calls `Navigator.push(BleConnectionScreen(bleManager: bleManager, onConnected: () => Navigator.pushReplacement(context, SketchScreen(bleManager: bleManager))))`.
2. **Subscribe to connection events.** `_BleConnectionScreenState.initState` (L23) subscribes to `bleManager.connectStream`.
3. **Start the scan from the UI.** Tapping "CONNECT TO DEVICE" calls `_startScan()` (L40):
   1. `setState(_isScanning = true, _statusMessage = 'Scanning for SmartMeasure Pro...')`.
   2. `await widget.bleManager.connectToDevice()`.
   3. Start a 12 s timer. When it fires, if `_isScanning` is still true and the widget is mounted, it shows `Device not found. Make sure ESP32 is powered on.` and re-enables the button.
4. **Scan.** `BleManager.connectToDevice()` (ble_manager.dart L20):
   1. `await FlutterBluePlus.stopScan()`, then a 200 ms delay.
   2. `scanSubscription = FlutterBluePlus.scanResults.listen(...)`.
   3. `await FlutterBluePlus.startScan(timeout: Duration(seconds: 10))`. No service, name or MSD filter is passed, so all advertisers are reported.
   4. Exceptions thrown synchronously by these calls are caught and printed as `Scan error: $e`, for example a denied permission or Bluetooth being off.
   5. In flutter_blue_plus 1.36.8, `startScan` returns as soon as scanning has **started**. It does not wait for a device or for the timeout. The library stops the scan automatically after 10 s.
5. **Match the device by name.** Each `scanResults` event is the accumulated list of devices seen in the current scan. The listener loops over it. On the first result with `r.device.platformName == "SmartMeasure Pro"`, it:
   - cancels its own subscription and calls `FlutterBluePlus.stopScan()`;
   - calls `_connect(r.device)` and `break`s.

   The comparison is exact and case-sensitive. On Android, `platformName` is the advertised name, which this ESP32 sends in its scan response.
6. **Connect and subscribe.** `_connect(device)` (L48):
   1. `_device = device` is assigned **before** connecting.
   2. `await device.connect(autoConnect: false)`. flutter_blue_plus defaults apply: 35 s timeout, and on Android an MTU of 512 is requested after connecting.
   3. `_connectController.add(true)` and `print("Connected to SmartMeasure Pro")`.
   4. `await device.discoverServices()`.
   5. Find the service whose `uuid.toString().toLowerCase()` equals `serviceUuid`. Inside it, find the characteristic equal to `characteristicUuid`. For a custom 128-bit UUID, flutter_blue_plus `Guid.toString()` returns the full 36-character lowercase form.
   6. `_characteristic = c`.
   7. `await c.setNotifyValue(true)` writes the CCCD.
   8. `c.onValueReceived.listen(...)` (3.2.12).
7. **Navigate to the sketch.** The screen's `connectStream` listener receives `true`:
   1. `setState(_statusMessage = 'Connected!', _isScanning = false)`.
   2. After 1 s, `widget.onConnected()` runs. `pushReplacement` swaps the connection screen for `SketchScreen(bleManager: bleManager)`.

   `true` is emitted **before** service discovery and subscription finish. Nothing signals an error if the service or characteristic is missing.
8. **"Skip (test without device)"** calls `widget.onConnected` directly. `SketchScreen` then receives a **non-null but unconnected** `BleManager`.
9. **Runtime permissions.** The Dart code never requests permissions and never checks adapter state. flutter_blue_plus's Android plugin (`ensurePermissions` in `FlutterBluePlusPlugin.java`) requests `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` (and location where needed) by itself. `AndroidManifest.xml` declares:
   - `BLUETOOTH` and `BLUETOOTH_ADMIN`;
   - `BLUETOOTH_SCAN` (`neverForLocation`) and `BLUETOOTH_CONNECT`;
   - `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION`.

#### 3.2.12 Receiving and decoding notifications (app)
- The `onValueReceived` listener registered in `_connect` runs `final packet = BlePacket.fromBytes(bytes); _packetController.add(packet); print("Received: ${packet.distanceMm}mm  bat:${packet.batteryPercent}%");`.
- `BlePacket.fromBytes` (ble_packet.dart L12):
  - With fewer than 4 bytes it returns `BlePacket(distanceMm: 0, batteryPercent: 0, isCapturing: false)`.
  - Otherwise it sets:
    - `distanceMm = ((bytes[0] << 8) OR bytes[1]).toDouble()` (big-endian unsigned 16-bit, millimetres);
    - `batteryPercent = bytes[2]`;
    - `isCapturing = (bytes[3] & 0x01) != 0`.
  - Bytes after the fourth are ignored.
- `packetStream` is a broadcast stream with no buffering or replay: a packet that arrives while nobody listens is lost. It delivers **every** decoded notification, capturing packets included.
- Both consumers drop packets with `isCapturing == true` or `distanceMm <= 0`. That covers the laser-on packet and the zero packet produced from a short payload.
- `batteryPercent` (always 80) is used only in the debug `print`; no UI shows it.

#### 3.2.13 Applying a device distance to a wall in the 2D sketch (call-site level)
Files: `code/lib/sketch/sketch_screen.dart` and `sketch_dialogs.dart`.
1. **Select a wall.** With a closed active room, the user taps a wall dimension label (`_onTapDown`, L2560–2568) or near a wall (`_findNearWall`, L2672–2679). That sets `_selectedWallIndex` and calls the mixin method `showSketchWallEditDialog(wallIndex)` (sketch_dialogs.dart L147).
2. **Choose the device or manual entry.** The dialog reads `sketchBleManager` (typed `dynamic` to avoid importing BLE code, L18) and tests `ble != null && ble.isConnected`.
   - **Connected** → bottom sheet headed "Wall N — <drawn length> drawn" with two buttons:
     - "Use Device — press BOOT button on ESP32" closes the sheet and runs `setState { _selectedWallIndex = wallIndex; _waitingForBle = true; }`;
     - "Enter manually" opens `showSketchManualEntryDialog`.
   - **Not connected** → straight to the manual dialog.
3. **Measure on the device.** The user presses MEAS on the device (laser on, capturing packet, ignored by the app), aims, and presses MEAS again (measurement packet).

   The app text "BOOT button" (sketch_dialogs.dart L180, sketch_screen.dart L3468) is wrong. The firmware uses the MEAS button on GPIO32, and two presses are needed. BOOT/GPIO0 is not read by the firmware.
4. **Receive the packet.** The `packetStream` listener (sketch_screen.dart L203–217, registered in `initState`):
   1. Return if `packet.isCapturing` or `packet.distanceMm <= 0`.
   2. If `_waitingForBle` and `0 <= _selectedWallIndex < _wallAngles.length`:
      1. `wallIdx = _selectedWallIndex`.
      2. `setState { _waitingForBle = false; _pendingBleMm = mm; _selectedWallIndex = -1; }`.
      3. `_applyRealMeasurement(wallIdx, packet.distanceMm)`.
   3. In any other case the packet is dropped silently.
5. **Apply the measurement.** `_applyRealMeasurement(wallIndex, realMm)` (L1846):
   1. Return if `wallIndex >= _wallAngles.length` or the drawn wall length is below 1e-6.
   2. `_saveUndo()`.
   3. `setState`:
      - `activeShape.wallRealMm[wallIndex] = realMm` (mm);
      - `_rebuildPointsFromChain()` re-walks the wall chain from point 0. Wall *i* gets length `wallRealMm[i] / mmPerUnit` world units if measured (`mmPerUnit = 5.0`, sketch_constants.dart L5), otherwise its drawn length, in direction `_wallAngles[i]`;
      - `_syncWallDefinitions()`;
      - clear the selection.
   4. `_queueAutoSync()` starts the cloud sync (see the sync part).
6. **Caveats.**
   - The guard uses `_wallAngles`. `_syncWallDefinitions()` (L1815) fills it with **n−1** entries for n points (consecutive pairs only). The **closing wall** of a closed room (index n−1) therefore cannot be set this way: the packet is ignored and `_waitingForBle` stays true.
   - Nothing clears `_waitingForBle` except a successfully applied packet. There is no timeout, no cancel, and choosing manual entry does not clear it.
   - While waiting, the toolbar shows "Wall N selected — enter real measurement". Its branch takes precedence, which makes the BLE hint "Point device at wall → press BOOT button" (L3467–3468) effectively unreachable while a valid wait is pending.
   - `_pendingBleMm` is written but never read (dead).
   - The subscription is never cancelled, and its `setState` is not guarded by `mounted`.

#### 3.2.14 Applying a device distance in the 3D view (call-site level)
File: `code/lib/sketch/room_3d_screen.dart`.
1. **Open the 3D view.** SketchScreen's "3D View" button (sketch_screen.dart L3419–3436) pushes `Room3DScreen(shapes: shapes, initialActiveShapeIndex: activeIndex, bleManager: widget.bleManager, onWallMeasured: (wallIndex, mm) => _applyRealMeasurement(wallIndex, mm), onHeightChanged: ...)`. SketchScreen stays mounted underneath, so the BLE link stays up.
2. **Select a wall.** In the 3D view (WebView `wallTap` message or legacy painter tap), the info bar shows "Wall N selected". If `widget.bleManager != null` it also shows a "Measure" link with a Bluetooth icon (L469–505). This check does not look at `isConnected`, so the link also appears after "Skip".
3. **Wait for a packet.** Tapping the link calls `_triggerBleMeasurement()` (L713):
   1. `wallIdx = _selectedWallIndex!`.
   2. `setState(_waitingForBle = true)`, which shows a spinner and "Measuring…".
   3. `widget.bleManager!.packetStream.where((p) => !p.isCapturing && p.distanceMm > 0).first.then(...)`.
4. **Apply the packet.** On the first matching packet, if the screen is still mounted:
   1. `setState { _waitingForBle = false; _activeShape.wallRealMm[wallIdx] = mm; _selectedWallIndex = null; }`.
   2. `widget.onWallMeasured?.call(wallIdx, mm)` → SketchScreen `_applyRealMeasurement`.
   3. `_selectedRoomId = null`.
   4. `runJavaScript('window.highlightWall(null, -1)')`.
   5. SnackBar `Wall N: <mm> mm — updated!`.
5. **Caveats.**
   - There is no timeout or cancel; the spinner waits indefinitely.
   - `_sendRoomData()` is not called afterwards, so the Three.js scene is not re-sent.
   - The 3D view writes `wallRealMm` on **its** active shape. `_activeShapeIndex` can change via `wallTap`/`roomTap`, while `_applyRealMeasurement` applies to SketchScreen's `activeShape`. After switching rooms in 3D, the two can differ.
   - `wallRealMm` is mutated before SketchScreen's `_saveUndo()` runs, so that undo step does not restore the old real length.
   - If the 2D `_waitingForBle` flag is still set, both listeners consume the same packet.

#### 3.2.15 Disconnecting, lifetime and reconnection
- **App:**
  - `SketchScreen.dispose()` (L236–240) calls `widget.bleManager?.disconnect()`:
    1. `await _device?.disconnect()`;
    2. `_device = null`, `_characteristic = null`;
    3. `_connectController.add(false)`.
  - Nothing reacts to `false`. `BleManager.dispose()` is never called anywhere, so the controllers are never closed.
  - No link-loss detection exists. `BluetoothDevice.connectionState` is not observed, so after an unexpected disconnect `isConnected` stays `true` and no reconnect is attempted. To reconnect, the user must leave the sketch and run "Start Room Sketch" again, which creates a new `BleManager`.
- **Firmware:** `onDisconnect` clears `bleConnected` and restarts advertising whatever mode the device is in.

#### 3.2.16 End-to-end sequence: measuring a wall with the device (2D)
```text
App user / SketchScreen                    BleManager (flutter_blue_plus)        ESP32 (BLE_MODE)
tap wall label -> showSketchWallEditDialog(i)
"Use Device" -> _selectedWallIndex=i, _waitingForBle=true
                                                                              MEAS (IDLE): laser HIGH,
                                                                              bleSend(0,true), beep, LASER_ON
                                           <- notify 00 00 50 01 ------------
listener: isCapturing -> ignored  <------- packetStream
                                                                              aim; MEAS (LASER_ON): doMeasure()
                                                                              blink 0.9 s, read TF-Luna frame,
                                                                              mm = cm*10 (+146 if B)
                                                                              bleSend(mm,false), showResult, MEASURED
                                           <- notify hi lo 50 00 ------------
listener: waiting && 0<=i<_wallAngles.length
_applyRealMeasurement(i, mm): _saveUndo, wallRealMm[i]=mm,
  _rebuildPointsFromChain (len = mm / 5.0), _syncWallDefinitions, _queueAutoSync
                                                                              optional: MEAS = save CSV row,
                                                                              PWR = discard (already sent)
```

#### 3.2.17 Serial diagnostics (firmware, 115200 baud on the USB UART)
- **Boot:** `Ready - press PWR to start`.
- **TF-Luna:**
  - `TF-Luna raw: <cm> cm  flux: <flux>`;
  - `TF-Luna: bad checksum, retrying`, `TF-Luna: signal quality fail`, `TF-Luna: out of range`, `TF-Luna: read timeout`;
  - `Bottom mode: +146mm -> <mm>`.
- **T/B toggle:** `Mode: BOTTOM (+146mm)` / `Mode: TOP (raw)`.
- **BLE:** `BLE advertising`, `BLE connected`, `BLE disconnected`, `BLE sent: <mm> mm`.
- **Button dump:** every 500 ms (L713–721) a raw state line such as `BTN_PWR(25):1  BTN_SEL(27):1  BTN_DOWN(33):1  BTN_MEAS(32):1  BTN_OFFSET(35):1` is printed. This is a leftover debug feature that floods the monitor.

### 3.3 File reference

#### `firmware/src/main.cpp` — 724 lines
- **Purpose:** The complete ESP32 firmware. It handles button input, the OLED UI, two nested state machines, distance measurement with a TF-Luna LiDAR over UART, the CSV log and history on the SD card, the buzzer and aiming laser, and a BLE GATT server that notifies measurements to the app. The last change was commit `8573f75` "Add top/bottom push button"; the lines marked `// NEW` belong to that feature.
- **Depends on:**
  - Arduino-ESP32 core: `Arduino.h`; `HardwareSerial` (UART2 for the TF-Luna, UART0 `Serial` for debug); `millis`, `delay`, `digitalRead/Write`, `String`.
  - `Wire.h` (I2C for the OLED); `SPI.h` and `SD.h` (SD card, FAT, `File`).
  - `Adafruit_GFX.h` and `Adafruit_SSD1306.h` (OLED drawing, pulling in Adafruit BusIO transitively).
  - The Arduino-ESP32 BLE library on Bluedroid: `BLEDevice.h`, `BLEServer.h`, `BLE2902.h`. `BLEUtils.h` is included but nothing from it is used directly.
  - No sensor library: the TF-Luna protocol is parsed manually.
  - No other repository file is included or needed.

- **Declarations — macros (L12–35):**

| Macro | Value | Meaning |
|---|---|---|
| `SCREEN_WIDTH` / `SCREEN_HEIGHT` | 128 / 64 | OLED size in pixels |
| `OLED_ADDRESS` | 0x3C | SSD1306 I2C address |
| `SD_CS`, `SD_SCK`, `SD_MISO`, `SD_MOSI` | 5, 18, 19, 23 | SD card SPI pins (VSPI defaults) |
| `BTN_PWR` | 25 | power / cancel / back button |
| `BTN_SEL` | 27 | select / history / scroll-older button |
| `BTN_DOWN` | 33 | menu down / scroll-newer button |
| `BTN_MEAS` | 32 | laser on / measure / save button |
| `BTN_OFFSET` | 35 | T/B reference toggle; needs an external 10 kΩ pull-up (L25) |
| `BUZZER` | 26 | buzzer output |
| `LASER_PIN` | 4 | aiming laser output |
| `TF_RX`, `TF_TX` | 16, 17 | UART2 pins for the TF-Luna (ESP32 RX ← sensor TX; ESP32 TX → sensor RX, never written) |
| `SERVICE_UUID` | `"4fafc201-1fb5-459e-8fcc-c5c9c331914b"` | GATT service; the UUID from the Arduino-ESP32 `BLE_server` example |
| `CHARACTERISTIC_UUID` | `"beb5483e-36e1-4688-b7f5-ea07361b26a8"` | notify characteristic; also from that example |
| `DEVICE_HEIGHT_MM` | `146.0` | offset added in "bottom" reference mode (device length) |

- **Declarations — globals:**

| Line | Declaration | Meaning |
|---|---|---|
| L37 | `Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1)` | OLED driver; −1 = no reset pin |
| L38 | `HardwareSerial tfSerial(2)` | UART2, connected to the TF-Luna |
| L40 | `bool sdReady = false` | true once `SD.begin` succeeds |
| L41 | `int recordCount = 0` | rows saved since boot; also the `count` written to the CSV |
| L42 | `float lastMm = 0` | last valid measurement in mm (offset included) |
| L44 | `bool measureFromBottom = false` | T/B reference (false = T) |
| L46 | `BLEServer* bleServer = nullptr` | GATT server |
| L47 | `BLECharacteristic* bleChar = nullptr` | the notify characteristic |
| L48 | `bool bleConnected = false` | set and cleared by the server callbacks (written from the BT task) |
| L49 | `int bleMeasureCount = 0` | BLE measurements since the last connect; effectively never displayed (see issues) |
| L51 | `int historyOffset = 0` | index of the first history row shown |
| L52 | `int historyTotal = 0` | rows loaded into `historyLines` |
| L53 | `String historyLines[100]` | raw CSV lines (first 100 data rows) |
| L63–67 | `Button btnPwr, btnSel, btnDown, btnMeas, btnOffset` | each initialised `{pin, true, true, 0, false}` (released) |
| L94 | `Screen currentScreen = OFF` | top-level state |
| L95 | `int selectedMode = 0` | menu cursor: 0 = Normal, 1 = Bluetooth |
| L98 | `NormalState normalState = IDLE` | measuring sub-state |

- **Declarations — types:**
  - `struct Button` (L55). Fields:
    - `int pin` (GPIO);
    - `bool lastReading` (last raw sample);
    - `bool stable` (debounced level, true = released);
    - `unsigned long lastChangeTime` (`millis()` of the last raw change);
    - `bool triggered` (press edge seen in this loop pass).
  - `enum Screen { OFF, MODE_SELECT, NORMAL, BLE_MODE }` (L93).
  - `enum NormalState { IDLE, LASER_ON, MEASURED, HISTORY }` (L97).
  - `class MyServerCallbacks : public BLEServerCallbacks` (L376):
    - `void onConnect(BLEServer* s) override` (L377);
    - `void onDisconnect(BLEServer* s) override` (L384).

    See 3.2.9 for their behaviour.

- **Declarations — functions:**

| Function (line) | Behaviour |
|---|---|
| `void updateButton(Button &btn)` (L69) | Clears `triggered`; samples the pin; restarts the 50 ms timer on any raw change; once the raw level has been unchanged for > 50 ms, sets `triggered` on a stable HIGH→LOW transition and updates `stable`. |
| `void beep(int times, bool longBeep = false)` (L82) | Blocking buzzer pattern (3.2.8). |
| `void drawModeIndicator()` (L104) | Prints "B" or "T" at (122,0), text size 1. |
| `void drawHeader(String mode)` (L110) | Sets white text, size 1; "SmartMeasure Pro" at (0,0); horizontal rule at y=10; `mode` at (98,0); T/B indicator. |
| `void showModeSelect()` (L121) | Mode menu screen. |
| `void showIdle()` (L140) | Idle screen; header "BLE" or "NRM" from `currentScreen`. |
| `void showLaserOn()` (L152) | "LASER ON" aiming screen. |
| `void showMeasuring()` (L163) | "Measuring..." screen (called inside `doMeasure`). |
| `void showResult(float mm)` (L171) | Result screen; value in mm or m, size 2. |
| `void showSaved(float mm)` (L185) | "SAVED!" confirmation with the session total. |
| `void showBleReady()` (L199) | "App Connected!" screen (only from `onConnect`). |
| `void showBleSent(float mm)` (L211) | ">> WALL UPDATED <<" screen. **Never called: dead code.** |
| `void loadHistory()` (L227) | Reads up to 100 data rows from `/readings.csv` into `historyLines` and sets `historyOffset` (3.2.7). |
| `void showHistory()` (L244) | History screen (3.2.7). |
| `bool saveToSD(float mm)` (L288) | Appends a CSV row; returns success (3.2.6). |
| `float doMeasure()` (L302) | Blink, then read and validate one TF-Luna frame; returns mm (offset included) or −1 (3.2.4). |
| `void bleSend(float mm, bool capturing)` (L364) | Builds and notifies the 4-byte packet if connected (3.2.10). |
| `void setup()` (L402) | Boot sequence (3.2.1). |
| `void loop()` (L450) | Button sampling, T/B toggle, state machines, debug dump, `delay(10)`. |

- **Key logic — `loop()` order (L450–724):**
  1. `updateButton` for all five buttons.
  2. Global T/B toggle (L458).
  3. One `if/else if` chain on `currentScreen`: OFF L474, MODE_SELECT L484, NORMAL L525, BLE_MODE L620.
  4. Inside NORMAL and BLE_MODE, an `if/else if` chain on `normalState`.
  5. The serial button dump every 500 ms (L713).
  6. `delay(10)`.

  Inside a state block, the button handlers are **independent `if`s**. Two presses debounced in the same pass are both processed. For example, MEAS and SEL together in IDLE turn the laser on, then enter HISTORY with the laser still on.

- **Key logic — button map:**

| Button | OFF | MODE_SELECT | IDLE | LASER_ON | MEASURED | HISTORY |
|---|---|---|---|---|---|---|
| PWR (25) | on → MODE_SELECT | → OFF | → OFF | cancel → IDLE | discard → IDLE | back → IDLE |
| SEL (27) | — | confirm mode | open history | — | — | scroll to older |
| DOWN (33) | — | move cursor | — | — | — | scroll to newer |
| MEAS (32) | — | — | laser on (+capturing packet in BLE) | measure | save to SD | — |
| OFFSET (35) | toggle T/B | toggle + redraw | toggle + redraw | toggle + redraw | toggle + redraw (value unchanged) | toggle + redraw |

  Only short presses exist: no long-press, double-press or auto-repeat detection. A held button triggers once. Presses that start and end during a blocking delay are lost.

- **Key logic — screen state machine (`currentScreen`):**

| State | Event | Guard | Action | Next |
|---|---|---|---|---|
| any | OFFSET press | — | toggle `measureFromBottom`; `beep(1)`; Serial log; redraw the current screen (none in OFF) | unchanged |
| (reset) | `setup()` done | — | blank OLED | OFF |
| OFF | PWR | — | `selectedMode = 0`; `beep(1)`; `showModeSelect()` | MODE_SELECT |
| OFF | SEL / DOWN / MEAS | — | ignored | OFF |
| MODE_SELECT | DOWN | — | `selectedMode = (selectedMode+1) % 2`; `beep(1)`; `showModeSelect()` | MODE_SELECT |
| MODE_SELECT | SEL | `selectedMode == 0` | `beep(2)`; `normalState = IDLE`; `showIdle()` | NORMAL |
| MODE_SELECT | SEL | `selectedMode == 1` | `beep(2)`; `normalState = IDLE`; `addServiceUUID`, `setScanResponse(true)`, `BLEDevice::startAdvertising()`; draw "BLE Mode / Waiting for app..." | BLE_MODE |
| MODE_SELECT | PWR | — | clear OLED; `beep(2)` | OFF |
| MODE_SELECT | MEAS | — | ignored | MODE_SELECT |
| NORMAL | PWR | `normalState == IDLE` | clear OLED; `beep(2)` | OFF (normalState stays IDLE) |
| BLE_MODE | PWR | `normalState == IDLE` | laser LOW; clear OLED; `beep(2)`; advertising/connection untouched | OFF |
| any | BLE central connects | — | `bleConnected = true`; `bleMeasureCount = 0`; `beep(2)`; `showBleReady()` (BT task) | unchanged |
| any | BLE central disconnects | — | `bleConnected = false`; `startAdvertising()`; draw "App disconnected / Waiting for app..." (BT task) | unchanged |

- **Key logic — measuring state machine (`normalState`, the same in NORMAL and BLE_MODE except where noted):**

| State | Event | Action | Next |
|---|---|---|---|
| IDLE | MEAS | laser HIGH; BLE_MODE: `bleSend(0, true)`; `beep(1)`; `showLaserOn()` | LASER_ON |
| IDLE | SEL | `loadHistory()`; `historyOffset = max(0, historyTotal-3)`; `showHistory()` | HISTORY |
| IDLE | PWR | see screen FSM | (screen → OFF) |
| IDLE | DOWN | ignored | IDLE |
| LASER_ON | MEAS, `doMeasure() < 0` | `beep(1,true)`; error screen; `delay(1500)`; laser HIGH; `showLaserOn()` | LASER_ON |
| LASER_ON | MEAS, `doMeasure() >= 0` | `lastMm = mm`; BLE_MODE: `bleMeasureCount++`, `bleSend(lastMm,false)`; `beep(1)`; `showResult(lastMm)` | MEASURED |
| LASER_ON | PWR | laser LOW; `beep(1)`; `showIdle()` | IDLE |
| LASER_ON | SEL / DOWN | ignored | LASER_ON |
| MEASURED | MEAS | `saveToSD(lastMm)`: ok → `beep(3)`, `showSaved`, `delay(1500)`; fail → `beep(1,true)`; then `showIdle()` | IDLE |
| MEASURED | PWR | `beep(1)`; `showIdle()` | IDLE |
| MEASURED | SEL / DOWN | ignored | MEASURED |
| HISTORY | DOWN | if `historyOffset+3 < historyTotal`: `historyOffset++`, `beep(1)`, `showHistory()` | HISTORY |
| HISTORY | SEL | if `historyOffset > 0`: `historyOffset--`, `beep(1)`, `showHistory()` | HISTORY |
| HISTORY | PWR | `beep(1)`; `showIdle()` | IDLE |
| HISTORY | MEAS | ignored | HISTORY |

- **Key logic — debounce in numbers:** `millis()` is used with a 50 ms threshold, and the loop period is about 10 ms plus work. A press is reported 50–60 ms after the contact settles. `triggered` lives for exactly one loop pass, so every consumer must check it in the same pass.

- **Key logic — TF-Luna parsing:** see 3.2.4 and the frame table in 3.4. Constants:
  - header `0x59 0x59`;
  - signal threshold `flux < 100` or `== 65535`;
  - range 20–800 cm;
  - conversion ×10 (cm → mm);
  - flush, then a 20 ms settle, then a 500 ms window.

- **Timing constants:**

| Constant | Value |
|---|---|
| debounce | 50 ms |
| loop delay | 10 ms |
| short beep | 80 ms on / 100 ms off |
| long beep | 600 ms |
| laser blink | 3 × 300 ms |
| UART settle | 20 ms |
| measurement window | 500 ms |
| error screen | 1500 ms |
| "SAVED" screen | 1500 ms |
| debug dump | every 500 ms |
| setup delays | 100 ms (UART), 200 ms (SPI) |
| SD SPI clock | 4 MHz |
| UART speeds | 115200 for both Serial and TF-Luna |

- **State and data:**
  - All state is in RAM globals (tables above). Nothing persists across reboot except `/readings.csv`: T/B mode, `recordCount` and mode choice are all lost.
  - CSV and BLE packet formats are in 3.4.
  - `historyLines` holds up to 100 heap-allocated Arduino `String`s.

- **UI (OLED, white text on black; size 1 = 6×8 px characters unless noted):**

| Screen (line) | Shown when | Content (x,y) |
|---|---|---|
| blank | boot; OFF | cleared display |
| `showModeSelect` (L121) | OFF+PWR; DOWN in menu; T/B toggle | "SmartMeasure Pro" (18,0); T/B (122,0); rule y=10; "Select Mode:" (0,14); "> Normal Mode" or "  Normal Mode" (0,28); "> Bluetooth Mode" or "  Bluetooth Mode" (0,40); "SEL=ok  DWN=move" (0,54) |
| header (`drawHeader`, L110) | on most screens | "SmartMeasure Pro" (0,0); "NRM" or "BLE" (98,0); T/B (122,0); rule y=10 |
| `showIdle` (L140) | entering NORMAL; any return to IDLE | header; "Press MEASURE" (0,14); "to start" (0,24); "Records: <recordCount>" (0,36); "SEL=history PWR=off" (0,52) |
| `showLaserOn` (L152) | IDLE+MEAS; after an error | header; "** LASER ON **" (0,14); "Aim at target" (0,26); "Press MEASURE again" (0,38); "PWR=cancel" (0,52) |
| `showMeasuring` (L163) | during `doMeasure` | header; "Measuring..." (20,28) |
| `showResult` (L171) | valid measurement | header; "Result:" (0,14); size 2 at (0,28): `<int> mm` or `<x.xx> m`; "MEAS=save PWR=cancel" (0,52) |
| `showSaved` (L185) | SD save OK, 1.5 s | header; ">> SAVED! <<" (28,14); size-2 value (0,28); "Total: <recordCount>" (0,52) |
| error (inline L552–557 / L649–653) | `doMeasure` returned −1, 1.5 s | header; "Out of range!" (0,20); "Check target surface" (0,32); NORMAL only: "Press MEAS again" (0,44) |
| BLE waiting (inline L503–513) | Bluetooth Mode chosen | "-- Bluetooth --" (0,0); T/B; rule; "BLE Mode" (0,20); "Waiting for app..." (0,32); "Open SmartMeasure" (0,44); "PWR=off" (0,54) |
| `showBleReady` (L199) | `onConnect` | header "BLE"; "App Connected!" (0,14); "Select wall in app" (0,28); "Press MEAS to shoot" (0,40); "Sent: <bleMeasureCount>" (0,52), always 0 |
| disconnected (inline L387–395) | `onDisconnect` | "-- Bluetooth --" (0,0); T/B; rule; "App disconnected" (0,20); "Waiting for app..." (0,32) |
| `showHistory` (L244) | IDLE+SEL; scrolling | "-- History --" (0,0); T/B; rule; rows "#<n>  <mm> mm" at y=14/28/42; "<a>-<b>/<total>" (80,54); "PWR=back SEL/DWN=scroll" (0,54); or "SD not available" / "No records yet" (0,20) + "PWR=back" (0,54) |
| `showBleSent` (L211) | never (dead) | header "BLE"; ">> WALL UPDATED <<" (0,14); size-2 value (0,28); "Select next wall" (0,52) |

- **Connections:**
  - No repository file includes or calls this code.
  - Its only software contract is the BLE GATT interface consumed by `code/lib/ble/ble_manager.dart` and `ble_packet.dart`: UUIDs, device name and the 4-byte payload.
  - Hardware contracts: TF-Luna UART frames, the SD card file `/readings.csv`, the OLED, buttons, buzzer and laser.
  - Built by `firmware/platformio.ini`.

- **Notes and issues:**
  - **Hardware and documentation**
    - The documentation is wrong about the hardware: the sensor is a TF-Luna on UART (not a VL53L0X on I2C), and there is no IMU.
    - No battery sensing exists; byte 2 of every packet is a hardcoded `80`.
  - **Measurement**
    - A measurement is a single frame with no averaging. The first checksum-valid frame decides even if it is weak, and resolution is 10 mm.
    - One generic "Out of range!" message covers weak signal, out of range and timeout. Failures are never reported over BLE.
  - **Blocking and concurrency**
    - All feedback is blocking: beeps, the 900 ms blink, 1.5 s screens and a busy-wait read loop. Buttons are not sampled meanwhile.
    - The BLE callbacks run on the Bluedroid task. They draw to the OLED and beep without synchronisation, override whatever screen is shown (even in OFF), and leave the state machine unchanged.
    - `bleConnected` is a plain `bool` shared between tasks (neither `volatile` nor atomic) and assumes a single client.
  - **BLE**
    - Advertising starts on entering BLE mode and is never stopped by the firmware. "OFF" and NORMAL mode can still be connectable.
    - `addServiceUUID` is re-added on each BLE-mode entry, so the library list holds duplicates.
    - There is no BLE security and no command channel.
  - **Dead or ineffective code**
    - `showBleSent()` (L211) is never called.
    - `bleMeasureCount` is only displayed by `showBleReady()` right after being reset, so "Sent:" always shows 0.
    - `Serial "BLE sent:"` is printed even when no client is connected.
  - **SD card and history**
    - `recordCount` restarts at 1 every boot, so CSV numbering is duplicated across sessions and "Records"/"Total" are per session.
    - The `millis` column is time since boot, not a timestamp.
    - `loadHistory()` keeps the **first** 100 rows, so newer rows become invisible after 100 records.
    - `historyOffset` is computed twice (L241 and L536/L632).
    - **History footer overlap:** "PWR=back SEL/DWN=scroll" is 23 characters (138 px, wider than the 128 px screen). It is drawn at (0,54) over the range text already drawn at (80,54). Transparent text ORs the glyphs into garbled characters, and the last characters wrap off-screen.
  - **UI**
    - Toggling T/B in MEASURED changes the indicator but not the displayed value. The mode is not persisted and not transmitted.
    - `showBleReady()` says "Press MEAS to shoot", but one press only turns the laser on; a second press measures. The BLE idle screens give no persistent "connected" indicator.
  - **Pins and initialisation**
    - GPIO35 needs an external pull-up. Without it the floating input causes random T/B toggles.
    - `display.begin()`'s result is not checked, and SD init failure is silent.
    - `TF_TX` (GPIO17) is configured but never used; the sensor runs on factory defaults (115200 baud, cm output, 100 Hz).
  - **Other**
    - "OFF" is not a low-power state.
    - Debug serial output floods every 500 ms.
    - `BLEUtils.h` is unused.

#### `firmware/platformio.ini` — 12 lines
- **Purpose:** PlatformIO build configuration for the only environment, `[env:esp32dev]`.
- **Content:**
  - `platform = espressif32` (version not pinned; locally the installed espressif32 platform is 6.12.0 with framework-arduinoespressif32 3.20017.241212, i.e. Arduino-ESP32 core 2.0.17);
  - `board = esp32dev`, `framework = arduino`;
  - `monitor_speed = 115200`;
  - `upload_port = COM14`, `monitor_port = COM14`;
  - `lib_deps`: `adafruit/Adafruit SSD1306 @ ^2.5.7`, `adafruit/Adafruit GFX Library @ ^1.11.9`, `adafruit/Adafruit BusIO @ ^1.14.5`.
- **Implicit dependencies:** Wire, SPI, SD/FS and the BLE library come with the Arduino-ESP32 framework, so they are not listed.
- **Absent:** no `build_flags`, partition-table override, upload speed or monitor filters.
- **Commands:** `pio run`, `pio run --target upload`, `pio device monitor` (all use COM14).
- **Notes and issues:**
  - The COM port is hardcoded to one developer's Windows machine. An earlier commit used COM7, and others must edit or remove it.
  - The unpinned platform version means different machines may build against different core and BLE library versions.
  - `pololu/VL53L0X` was removed in `0cc4310`.

#### `firmware/.gitignore` — 5 lines
Standard PlatformIO ignore list: `.pio`, `.vscode/.browse.c_cpp.db*`, `.vscode/c_cpp_properties.json`, `.vscode/launch.json`, `.vscode/ipch`. `settings.json` and `extensions.json` are therefore tracked.

#### `firmware/include/README` — 37 lines
PlatformIO template text explaining that `include/` is for project header files. The directory contains no headers.

#### `firmware/lib/README` — 46 lines
PlatformIO template text explaining that `lib/` is for private libraries, with an example `Foo`/`Bar` layout. The directory contains no libraries.

#### `firmware/test/README` — 11 lines
PlatformIO template text about the PlatformIO unit-test runner. The firmware has **no tests**.

#### `firmware/.vscode/extensions.json` — 10 lines
VS Code workspace recommendations: recommends `platformio.platformio-ide` and marks `ms-vscode.cpptools-extension-pack` as unwanted. This is the standard file generated by PlatformIO.

#### `firmware/.vscode/settings.json` — 296 lines
- **What it is:** Settings for the VS Code "C/C++ Runner" extension (`C_Cpp_Runner.*` keys). It is not used by PlatformIO builds.
- **Content:**
  - absolute Windows paths to the PlatformIO Xtensa toolchain (`xtensa-esp32-elf-gcc/g++/gdb` under `C:/Users/User/.platformio/...`);
  - C standard `gnu99`, C++ standard `gnu++11`;
  - a warning flag list and MSVC warning list;
  - about 235 include paths into the framework SDK and libraries, including a **stale** `firmware/.pio/libdeps/esp32dev/VL53L0X` entry from the pre-TF-Luna version;
  - include/exclude search globs; all sanitizers and LTO off.
- **Issue:** the paths are machine-specific.

#### `code/lib/core/constants.dart` — 11 lines
- **Purpose:** Intended to be the app-wide constants holder, including the BLE identifiers. In practice only `appName` is used.
- **Depends on:** nothing.
- **Declarations:** `class AppConstants` (L1), used as a static namespace. It has no constructor and is never instantiated.

| Constant (line) | Value | Used by |
|---|---|---|
| `bleServiceUUID` (L4) | `"12345678-1234-1234-1234-123456789abc"` | **nobody**; does **not** match the firmware |
| `bleCharacteristicUUID` (L5) | `"abcdefab-cdef-abcd-efab-cdefabcdefab"` | **nobody**; does **not** match the firmware |
| `deviceName` (L6) | `"SmartMeasurePro"` (no space) | **nobody**; firmware and `BleManager` use `"SmartMeasure Pro"` |
| `appName` (L9) | `"SmartMeasure Pro"` | `main.dart` L24 (`MaterialApp.title`); `home_screen.dart` L56 (AppBar title) |
| `dbName` (L10) | `"smart_measure.db"` | **nobody**; `database_helper.dart` L19 hardcodes `'smartmeasure.db'` |

- **Key logic / State / UI:** none.
- **Connections:** imported by `main.dart` and `screens/home_screen.dart`, for `appName` only.
- **Notes and issues:**
  - The comment at L2–3 ("These must match what you define in the ESP32 firmware later") was never acted on. The real UUIDs live in `ble_manager.dart`.
  - CLAUDE.md wrongly points readers here for the UUIDs.
  - Three of the five constants are dead and inconsistent. They should either be removed or become the single source used by `ble_manager.dart` and `database_helper.dart`.

#### `code/lib/ble/ble_packet.dart` — 27 lines
- **Purpose:** Immutable value object for one decoded BLE notification, plus the byte decoder.
- **Depends on:** nothing (pure Dart).
- **Declarations:** `class BlePacket` (L1).
  - Fields:
    - `final double distanceMm` (L2): distance in millimetres, integer-valued, 0–65535;
    - `final int batteryPercent` (L3): byte 2 of the payload, always 80 from the current firmware;
    - `final bool isCapturing` (L4): bit 0 of byte 3, where true means "laser on / aiming, not a result".
  - Constructor: `const BlePacket({required this.distanceMm, required this.batteryPercent, required this.isCapturing})` (L6).
  - `factory BlePacket.fromBytes(List<int> bytes)` (L12):
    - if `bytes.length < 4`, returns `const BlePacket(distanceMm: 0, batteryPercent: 0, isCapturing: false)`;
    - otherwise `dist = (bytes[0] << 8) OR bytes[1]` (big-endian), `distanceMm = dist.toDouble()`, `batteryPercent = bytes[2]`, `isCapturing = (bytes[3] & 0x01) != 0`.
  - No `toString`, `==`/`hashCode`, `copyWith` or encoder.
- **State and data:** byte layout in 3.4. It is consistent with `bleSend()` in the firmware: same order, endianness and units.
- **Connections:**
  - Created only in `BleManager._connect`'s `onValueReceived` listener.
  - Consumed through `BleManager.packetStream` by `SketchScreen` (L203, which also imports this file for the type) and `Room3DScreen._triggerBleMeasurement` (L718).
- **Notes and issues:**
  - A malformed short payload is indistinguishable from a real "0 mm, not capturing" packet. Consumers rely on `distanceMm <= 0` to drop it.
  - Bits 1–7 of byte 3 are ignored.
  - `batteryPercent` is not shown anywhere in the UI.

#### `code/lib/ble/ble_manager.dart` — 85 lines
- **Purpose:** Encapsulates the flutter_blue_plus central role. It scans for the device by name, connects, subscribes to the measurement characteristic, and republishes decoded packets and connection events as broadcast streams.
- **Depends on:**
  - `dart:async` (`StreamController`, `StreamSubscription`);
  - `package:flutter_blue_plus/flutter_blue_plus.dart`: pubspec `^1.31.0`, resolved to 1.36.8 in `pubspec.lock`, with `flutter_blue_plus_android` 7.0.4. It provides `FlutterBluePlus.startScan/stopScan/scanResults`, `ScanResult`, `BluetoothDevice.connect/discoverServices/disconnect/platformName`, `BluetoothService`, and `BluetoothCharacteristic.setNotifyValue/onValueReceived`;
  - `ble_packet.dart`.
- **Declarations:**
  - **Top-level constants:** `const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"` (L5) and `const String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8"` (L6). They are public, so every importer sees them, but only this file uses them. **These are the live UUIDs, and they match `main.cpp` L32–33.**
  - **`class BleManager` (L8)**, with the implicit default constructor. Fields:
    - `BluetoothDevice? _device` (L9): the target device. It is also the connection flag.
    - `BluetoothCharacteristic? _characteristic` (L10): set at discovery and cleared on disconnect, **never read**.
    - `final _packetController = StreamController<BlePacket>.broadcast()` (L12).
    - `final _connectController = StreamController<bool>.broadcast()` (L13).
  - **Getters:**
    - `Stream<BlePacket> get packetStream` (L15);
    - `Stream<bool> get connectStream` (L16);
    - `bool get isConnected => _device != null` (L17).
  - **Methods:**
    - `Future<void> connectToDevice()` (L20): stop any scan, wait 200 ms, listen to `FlutterBluePlus.scanResults`, `startScan(timeout: 10 s)`. The listener calls `_connect` for the first result whose `device.platformName == "SmartMeasure Pro"` (literal, L30), after cancelling itself and stopping the scan. Synchronous errors are caught and printed (`Scan error: $e`). It returns once scanning has started.
    - `Future<void> _connect(BluetoothDevice device)` (L48): `_device = device`; `connect(autoConnect: false)`; emit `true`; `discoverServices()`; match service and characteristic by lowercase string; `setNotifyValue(true)`; listen to `onValueReceived`, decoding each value with `BlePacket.fromBytes`, adding it to `_packetController` and printing it.
    - `Future<void> disconnect()` (L74): `await _device?.disconnect()`; null both fields; emit `false`.
    - `void dispose()` (L81): closes both controllers. **Never called** anywhere.
- **Key logic — scan behaviour that matters (from the flutter_blue_plus 1.36.8 source):**
  - `scanResults` re-emits the previous scan's list to every new listener ("if you re-listen to the stream it re-emits the previous results"). A second connection attempt in the same app session therefore sees the old list immediately. If that list contains the device, `_connect` runs with the stale `ScanResult` before the fresh scan reports anything. This works if the device is advertising or already connected; otherwise `connect` fails after 35 s.
  - The listener cancels itself **only when it finds the device**. After an unsuccessful 10 s scan it stays subscribed (it is not registered with `cancelWhenScanComplete`).
    - When the user taps CONNECT again on the same `BleConnectionScreen`, a second listener is added. When the device is then found, **both** run `_connect` concurrently.
    - Consequences:
      - `connect` and `discoverServices` run twice;
      - two `onValueReceived` listeners mean every notification reaches `packetStream` **twice**;
      - `connectStream` emits `true` twice.
    - If both `true` events arrive while the connection screen is still mounted, `onConnected()` runs twice. The second `pushReplacement` replaces the first `SketchScreen`, whose `dispose()` then calls `disconnect()` on the shared manager.
  - Errors thrown by `_connect` happen inside the async scan listener, so the `try/catch` in `connectToDevice` cannot catch them. Examples: connect timeout, Android GATT errors, a `discoverServices` or `setNotifyValue` failure. They surface as uncaught async errors. The UI keeps "Scanning..." until its 12 s timer, and `_device` remains set, so `isConnected` reports `true` after a failed connection.
  - No `withServices` filter is used. Any device advertising the exact name "SmartMeasure Pro" matches, and the first one in the list wins.
- **State and data:**
  - All state is per instance. Every "Start Room Sketch" tap creates a new instance, and old instances are never disposed.
  - flutter_blue_plus keeps its own static state, such as the cached names and the last scan results.
- **Connections:**
  - Instantiated in `screens/home_screen.dart` L98.
  - Passed to `BleConnectionScreen` (`connectToDevice`, `connectStream`), to `SketchScreen` (`packetStream`, `isConnected` via `SketchDialogsMixin.sketchBleManager`, `disconnect()` in `dispose`) and from there to `Room3DScreen` (`packetStream`).
  - Imported by `ble_connection_screen.dart`, `home_screen.dart`, `sketch_screen.dart` and `room_3d_screen.dart`.
- **Notes and issues:**
  - `isConnected` does not reflect the real link state: it is set before the connection completes, stays true after failure or link loss, and nothing observes `connectionState`.
  - There is no reconnection logic.
  - `connectStream` emits `true` before discovery and subscription, and there is no error event if the service or characteristic is missing (for example, firmware with different UUIDs).
  - `_characteristic` is dead state.
  - The `onValueReceived` subscription is never cancelled (`cancelWhenDisconnected` is not used).
  - The manager is never disposed.
  - `print()` is used for logging (`avoid_print` lint).
  - The device name is a hardcoded literal rather than `AppConstants.deviceName`, which has the wrong value anyway.
  - There is no write path, matching the firmware, which accepts no commands.

#### `code/lib/ble/ble_connection_screen.dart` — 183 lines
- **Purpose:** Full-screen UI that starts the BLE search and connection, then hands control to the sketch screen through a callback. It also offers a "Skip" path for testing without hardware.
- **Depends on:** `package:flutter/material.dart`; `ble_manager.dart` (`BleManager.connectToDevice`, `connectStream`).
- **Declarations:**
  - **`class BleConnectionScreen extends StatefulWidget` (L4).** Fields:
    - `final BleManager bleManager` (L5);
    - `final VoidCallback onConnected` (L6), called to navigate onwards.

    Constructor: `const BleConnectionScreen({super.key, required this.bleManager, required this.onConnected})` (L8). `createState()` (L15) returns `_BleConnectionScreenState`.
  - **`class _BleConnectionScreenState` (L18).** Fields:
    - `bool _isScanning = false` (L19);
    - `String _statusMessage = 'Press the button to find SmartMeasure Pro'` (L20).

    Methods:
    - `initState()` (L23) subscribes to `widget.bleManager.connectStream`. On `true`, it calls `setState(_statusMessage = 'Connected!', _isScanning = false)` and then `Future.delayed(1 s, widget.onConnected)`. `false` is ignored.
    - `void _startScan() async` (L40) sets the scanning state, awaits `connectToDevice()`, then starts the 12 s "not found" timer described in 3.2.11. The timer is guarded by `mounted`.
    - `build()` (L60) builds the layout below.

    There is no `dispose()` override.
- **UI:** `Scaffold` with background `#1A1A2E`, then `SafeArea` → `Padding(32)` → a centred `Column`:
  1. `Icons.bluetooth_searching`, size 80, colour `#00AAFF`.
  2. "SmartMeasure Pro" (monospace 24 bold, `#EEEEEE`), then "Bluetooth Connection" (monospace 14, `#888888`), then 60 px of space.
  3. Status box: `#0D1A27`, radius 8, border `#334466`. It contains a 16×16 `CircularProgressIndicator` (stroke 2, `#00AAFF`) while scanning, otherwise `Icons.info_outline` (`#556677`), followed by `_statusMessage` (monospace 13, `#AABBCC`).
  4. A full-width, 52 px high `ElevatedButton.icon` with `Icons.bluetooth`:
     - idle: label "CONNECT TO DEVICE", background `#00AAFF`, `onPressed: _startScan`;
     - scanning: label "SCANNING...", background `#334466`, `onPressed: null` (disabled).
  5. `TextButton` "Skip (test without device)" (monospace 12, `#556677`) → `widget.onConnected` directly.

  There is no AppBar; the system back button returns to `HomeScreen`.

| UI state | `_isScanning` | `_statusMessage` | Button |
|---|---|---|---|
| initial | false | "Press the button to find SmartMeasure Pro" | "CONNECT TO DEVICE" (enabled) |
| scanning | true | "Scanning for SmartMeasure Pro..." | "SCANNING..." (disabled) + spinner |
| connected | false | "Connected!" | enabled; `onConnected()` after 1 s |
| timeout (12 s after scan start) | false | "Device not found. Make sure ESP32 is powered on." | enabled (retry possible; see the duplicate-listener issue) |

- **Connections:**
  - Pushed by `HomeScreen`'s "Start Room Sketch" button. The `onConnected` closure there runs `Navigator.pushReplacement(context, SketchScreen(bleManager: bleManager))` with **HomeScreen's** context. `pushReplacement` replaces whatever route is on top of the navigator.
  - Uses `BleManager` only.
- **Notes and issues:**
  - The `connectStream` subscription is never cancelled. Its `setState` is not guarded by `mounted`, so a late `true` after the user has left (back or Skip while a scan was running) throws "setState() called after dispose()" (or a null-check error in release) inside the listener.
  - After a Skip-while-scanning, a later connection still succeeds inside the shared manager, and that `SketchScreen` silently gains a working link.
  - After pressing back, a connection completed later stays open in an orphaned manager that nobody disconnects. The ESP32 then remains "connected" and stops advertising.
  - The 12 s timeout reports "Device not found" even when the device was found but `connect` failed or is still in progress (the connect timeout is 35 s).
  - Navigation happens 1 s after `connect()`, regardless of whether characteristic discovery and subscription succeeded.
  - "Skip" hands `SketchScreen` an unconnected but non-null `BleManager`. The 2D dialog correctly falls back to manual entry because it checks `isConnected`. The 3D view still offers "Measure", which then waits forever.
  - Retrying after a failed scan can double-connect (see `ble_manager.dart`).
  - The firmware precondition (device in Bluetooth Mode) is not explained on screen. The message only says "Make sure ESP32 is powered on."

### 3.4 Data contracts

**Hardware pin map (firmware `main.cpp`).**

| Signal | GPIO | Configured as | Notes |
|---|---|---|---|
| `BTN_PWR` | 25 | `INPUT_PULLUP` | active low |
| `BTN_SEL` | 27 | `INPUT_PULLUP` | active low |
| `BTN_DOWN` | 33 | `INPUT_PULLUP` | active low |
| `BTN_MEAS` | 32 | `INPUT_PULLUP` | active low |
| `BTN_OFFSET` | 35 | `INPUT` | input-only pin; external 10 kΩ pull-up to 3.3 V required |
| `BUZZER` | 26 | `OUTPUT` | HIGH = sound (on/off drive, no PWM) |
| `LASER_PIN` | 4 | `OUTPUT` | HIGH = aiming laser on |
| I2C SDA / SCL | 21 / 22 | `Wire.begin(21, 22)` | SSD1306 128×64 OLED at 0x3C, `SSD1306_SWITCHCAPVCC`, no reset pin; the only I2C device |
| TF-Luna | RX 16 / TX 17 | `tfSerial` = UART2, 115200 8N1 | sensor TX → GPIO16; GPIO17 never written |
| SD card SCK / MISO / MOSI / CS | 18 / 19 / 23 / 5 | `SPI.begin`, `SD.begin(5, SPI, 4000000)` | file `/readings.csv` |
| Debug serial | UART0 (USB) | `Serial.begin(115200)` | matches `monitor_speed` |

**TF-Luna UART frame (input to `doMeasure()`; standard 9-byte Benewake format).**

| Byte | Field | Code variable | Use |
|---|---|---|---|
| 0 | 0x59 header | (read and compared) | sync |
| 1 | 0x59 header | (peeked and consumed) | sync |
| 2 | Dist_L | `buf[0]` | `cm = buf[0] + 256·buf[1]` (little-endian, centimetres) |
| 3 | Dist_H | `buf[1]` | |
| 4 | Amp_L | `buf[2]` | `flux = buf[2] + 256·buf[3]`; invalid if < 100 or == 65535 |
| 5 | Amp_H | `buf[3]` | |
| 6 | Temp_L (per datasheet) | `buf[4]` | ignored (checksum only) |
| 7 | Temp_H (per datasheet) | `buf[5]` | ignored (checksum only) |
| 8 | Checksum | `buf[6]` | must equal (sum of bytes 0–7) & 0xFF |

Accepted range is 20–800 cm. The output is `cm × 10` mm, plus 146 mm when `measureFromBottom` is set. The error value is `-1.0`.

**GATT database (ESP32 = peripheral/server; app = central/client).**

| Attribute | UUID | Properties | Content |
|---|---|---|---|
| GAP Device Name (auto, in 0x1800) | 0x2A00 | read | `"SmartMeasure Pro"` (from `BLEDevice::init`) |
| Primary service | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` | — | created and started in `setup()` |
| Measurement characteristic | `beb5483e-36e1-4688-b7f5-ea07361b26a8` | **NOTIFY only** (no READ, WRITE, INDICATE) | 4-byte packet below; empty until the first `bleSend` |
| CCCD descriptor | 0x2902 (`BLE2902`) | read/write by the client | the app writes "notifications on" via `setNotifyValue(true)`; the firmware sends nothing until it is enabled |

**Advertising (only after "Bluetooth Mode" is selected; restarted on every disconnect).**

| Item | Value |
|---|---|
| Name used for discovery | complete local name `"SmartMeasure Pro"`, in the scan response (`setScanResponse(true)`) |
| Advertised service | 128-bit `4fafc201-1fb5-459e-8fcc-c5c9c331914b` (`addServiceUUID`) |
| Type / address / interval | ADV_IND connectable, public address, 20–40 ms (library defaults) |
| App-side filter | `ScanResult.device.platformName == "SmartMeasure Pro"` (exact); no service filter |

**BLE payload: notification value of `beb5483e-…` (4 bytes).**

| Byte | Field | Firmware (`bleSend`, L364) | App (`BlePacket.fromBytes`, L12) | Type / unit |
|---|---|---|---|---|
| 0 | distance high byte | `(dist >> 8) & 0xFF` | `distanceMm = ((b0 << 8) OR b1).toDouble()` | uint16 **big-endian**, millimetres, `dist = (uint16_t)constrain(mm, 0, 65535)` (truncated) |
| 1 | distance low byte | `dist & 0xFF` | | |
| 2 | battery | constant `80` | `batteryPercent = b2` | uint8 "percent", a **placeholder** (no measurement) |
| 3 | flags | `capturing ? 0x01 : 0x00` | `isCapturing = (b3 & 0x01) != 0` | bit 0: 1 = laser on / aiming (distance 0), 0 = measurement result; bits 1–7 always 0 |

| Event (firmware) | Packet | App behaviour |
|---|---|---|
| BLE_MODE, IDLE → MEAS (laser on) | `00 00 50 01` | dropped by both consumers |
| BLE_MODE, LASER_ON → MEAS, valid | `hi lo 50 00` (200–8000 mm with T, 346–8146 mm with B; multiples of 10 mm, or +146) | applied to the selected wall if a consumer is waiting, otherwise dropped |
| payload shorter than 4 bytes (never produced by this firmware) | — | decoded as (0, 0, false) and dropped |

**App-side BLE API contract (`BleManager`), used by the sketch and 3D parts.**

| Member | Type | Semantics |
|---|---|---|
| `packetStream` | `Stream<BlePacket>` (broadcast) | every decoded notification, capturing packets included; no replay; possibly duplicated (see issues) |
| `connectStream` | `Stream<bool>` (broadcast) | `true` once `device.connect()` completes (before discovery); `false` only from `disconnect()` |
| `isConnected` | `bool` | `_device != null`; not the real link state |
| `connectToDevice()` | `Future<void>` | starts the scan; completes when scanning has started, not when connected |
| `disconnect()` | `Future<void>` | disconnects, clears state, emits `false` |
| `dispose()` | `void` | closes both controllers (never called) |
| `Room3DScreen.onWallMeasured` | `void Function(int wallIndex, double mm)?` | the 3D view reports a BLE distance (mm) for a wall index of its active shape; SketchScreen passes `_applyRealMeasurement` |
| `SketchShape.wallRealMm` | `Map<int, double>` | wall index → real length in **mm**; converted to world units by `/ mmPerUnit` (5.0) |

**Identifier cross-check.**

| Item | Firmware `main.cpp` | `ble_manager.dart` (used) | `AppConstants` (unused) | Result |
|---|---|---|---|---|
| Service UUID | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` (L32) | same (L5) | `12345678-1234-1234-1234-123456789abc` | firmware = app: **match**; AppConstants: **mismatch** |
| Characteristic UUID | `beb5483e-36e1-4688-b7f5-ea07361b26a8` (L33) | same (L6) | `abcdefab-cdef-abcd-efab-cdefabcdefab` | **match** / **mismatch** |
| Device name | `"SmartMeasure Pro"` (L434) | `"SmartMeasure Pro"` (literal, L30) | `"SmartMeasurePro"` | **match** / **mismatch** |
| Payload | 4 bytes, BE uint16 mm, 80, flag | parses BE uint16 mm, b2, bit 0 | — | **match** |
| Measure button named in app text | MEAS = GPIO32 (two presses) | "press BOOT button on ESP32" (sketch_dialogs.dart L180, sketch_screen.dart L3468) | — | **mismatch** (UI text) |

**SD card log `/readings.csv` (device-only; never transferred to the app).**

| Column | Type | Meaning |
|---|---|---|
| `count` | int | `recordCount` after increment; restarts at 1 every boot |
| `mm` | decimal, 1 place | saved distance in mm (B offset included) |
| `millis` | unsigned long | ms since ESP32 boot (no real time) |

The file starts with the header `count,mm,millis`, written when the file is created. Lines end in CRLF (`println`). The reader skips the header and lines shorter than 3 characters, and loads at most the first 100 rows.

### 3.5 Known issues and limitations

**Documentation versus reality**
- The project docs (CLAUDE.md, README.md, docs/README.md) claim a VL53L0X and an MPU6050/BNO055 IMU, with angle detection. The firmware uses a **TF-Luna on UART2** and has **no IMU code at all**, now or in git history. No orientation data exists anywhere in the data path.
- CLAUDE.md says the UUIDs live in `core/constants.dart`. The live UUIDs are in `ble_manager.dart`. `AppConstants.bleServiceUUID`, `bleCharacteristicUUID`, `deviceName` (`"SmartMeasurePro"`) and `dbName` (`"smart_measure.db"`, while the real DB is `smartmeasure.db`) are unused and do not match.
- App texts tell the user to "press BOOT button on ESP32". The firmware ignores BOOT/GPIO0; the user must press MEAS (GPIO32) twice in Bluetooth Mode.

**Firmware: protocol and BLE**
- The battery byte is hardcoded to 80, and the hardware has no battery monitoring.
- The BLE link is one-way: notify only, no commands. The app cannot trigger a measurement, read status, or learn about failures. Measurement failures send nothing, so the app waits indefinitely.
- Packets have no sequence number, wall identifier or T/B flag. Association with a wall is purely app-side state, so stray or late packets apply to whatever wall is waiting.
- Advertising starts in BLE mode and is never stopped; "OFF" is neither a radio-off nor a low-power state. There is no security (open connection, no pairing).
- `addServiceUUID` is re-added on every entry into BLE mode, so duplicates pile up.
- Connect and disconnect callbacks run on the BT task. They block it with `beep()`, draw on the OLED unsynchronised in any state (even OFF), and do not update the state machine. `bleConnected` is an unsynchronised plain `bool` with a single-client assumption.

**Firmware: measurement and UI**
- A measurement is one frame with no averaging. The first checksum-valid frame decides, so a single weak frame fails the measurement, and resolution is 10 mm. Weak signal, out of range and timeout all show the same "Out of range!" message.
- Everything is blocking: about 0.9 s of blinking per measurement, 1.5 s info screens, beeps and a busy-wait read. Button presses during these periods are lost.
- Handlers within a state are independent `if`s, so simultaneous presses can combine. For example, MEAS + SEL in IDLE ends in HISTORY with the laser on.
- The T/B toggle does not update a result already displayed, is not persisted, and is not transmitted.
- `recordCount` resets every boot, which duplicates CSV numbering. The `millis` column is not a timestamp. History loads the **first** 100 rows, hiding newer ones. The history footer text overlaps the page indicator and overflows the 128 px width.
- Dead or ineffective code:
  - `showBleSent()` is never called;
  - `bleMeasureCount` is always displayed as 0;
  - `Serial "BLE sent"` is printed even without a client;
  - `BLEUtils.h` is unused;
  - `TF_TX` is never written.
- `display.begin()` and SD initialisation failures are silent. GPIO35 depends on an external pull-up, and floating it causes phantom T/B toggles.
- The raw button-state dump prints to Serial every 500 ms.
- No firmware tests exist (`test/` holds only the README).

**Build**
- `platformio.ini` hardcodes `COM14` and does not pin the platform version.
- `.vscode/settings.json` contains machine-specific absolute paths and a stale VL53L0X include path.

**App: BleManager**
- `isConnected` is `_device != null`. It is set before `connect()` completes, stays true after a failed connect or link loss, and nothing listens to `connectionState`. There is no reconnect.
- `connectStream` emits `true` before discovery and subscription. A missing service or characteristic produces no error.
- Errors inside `_connect` (connect timeout, GATT errors) escape the `try/catch` and become uncaught async errors. The UI only reports "Device not found" after 12 s.
- An unsuccessful scan leaves its `scanResults` listener alive. Retrying then runs `_connect` twice, which duplicates every packet on `packetStream` and may call `onConnected()` twice. The replaced `SketchScreen` then disposes and disconnects the shared manager.
- `scanResults` replays the previous scan, so a second session in the same app run may connect from a stale result.
- `_characteristic` is dead state. `dispose()` is never called. The `onValueReceived` and `connectStream` subscriptions are never cancelled. `print` is used for logging.
- The scan filters only on the exact name; the first device named "SmartMeasure Pro" wins.

**App: BleConnectionScreen and navigation**
- The `connectStream` listener has no `mounted` guard and no `dispose()`. A connection that completes after the user leaves the screen throws inside the listener and leaves an orphaned connected manager. The ESP32 then stops advertising until that link drops.
- BLE is only reachable via "Start Room Sketch". Projects opened from My Projects, from the AR result or from collaboration (`bleManager: null`) cannot use the device.
- "Skip" passes a non-null, unconnected `BleManager`. The 3D view shows "Measure" based on `bleManager != null` and then waits forever.

**App: consumers (call-site level)**
- 2D:
  - `_waitingForBle` has no timeout or cancel, and choosing manual entry does not clear it.
  - The guard `_selectedWallIndex < _wallAngles.length` makes the closing wall of a closed room (index n−1) unmeasurable by BLE; the packet is ignored and waiting persists.
  - `_pendingBleMm` is dead.
  - The listener is never cancelled and calls `setState` without a `mounted` check.
  - The BLE toolbar hint is effectively unreachable.
- 3D:
  - There is no timeout or cancel.
  - The scene is not re-sent (`_sendRoomData`) after a measurement.
  - It writes `wallRealMm` on its own active shape while SketchScreen applies to its own `activeShape`; these can differ after switching rooms in 3D.
  - The undo snapshot is taken after the mutation.
  - If the 2D view is also waiting, both views can consume the same packet.


---

## Part 4 — Flutter app foundation: entry, navigation, state, local database, AR, platform config

### 4.1 Overview

Part 4 covers the base of the Flutter app in `code/` (Dart package `smart_measure_pro`) that every other part relies on:

- **Package and tooling configuration**: `pubspec.yaml` (SDK constraint, dependencies, assets, launcher-icon config), `analysis_options.yaml`, the only test (`test/widget_test.dart`, which is broken) and the two-line `README.md`.
- **Entry point and start-up gate**: `lib/main.dart`. `main()` → `ProviderScope` → `SmartMeasureApp` (`MaterialApp`) → `AppStartup`. `AppStartup` starts the background `SyncService` and redirects to `HomeScreen` or `LoginScreen`, depending on whether a JWT is stored.
- **Home hub**: `lib/screens/home_screen.dart`. It has four large buttons (sketch with the laser device, saved projects, AR scan, cloud/collaboration) and a logout action.
- **Local database**: `lib/database/database_helper.dart`. This is a singleton around one sqflite file, `smartmeasure.db` (schema version 4, 9 tables). It stores sketches relationally: projects → shapes → points and wall data, plus doors/windows and furniture. It also holds the offline upload queue (`pending_uploads`) that `SyncService` drains.
- **Saved-project picker**: `lib/database/project_list_screen.dart`. It lists and deletes local projects and returns the chosen id to its caller through `Navigator.pop`.
- **AR room scanning**:
  - `lib/ar/ar_scan_screen.dart`: ARCore/ARKit session through `ar_flutter_plugin_2`, with tap-to-capture of wall planes.
  - `lib/ar/ar_polygon_math.dart`: turns wall planes into an ordered room polygon in mm.
  - `lib/ar/ar_result_screen.dart`: corner editor and scale correction, then import into the sketch as a `SketchShape`.
- **Platform configuration**: the Android Gradle files, manifest and `MainActivity` (Android is the only realistic target), the iOS `Info.plist`, and the web template files.
- **App-wide cross-cutting tables owned by this part**: the complete navigation graph (§4.2.9) and the state-management census (§4.2.10). Both include screens that other parts document.
- **Empty file**: `lib/furniture_3d_viewer.dart` exists but is empty (0 bytes, tracked in git, never imported).

Vocabulary used below:

| Term | Meaning |
|---|---|
| world units | Sketch canvas coordinates. `mmPerUnit = 5.0` (`sketch/sketch_constants.dart` L5), so 1 unit = 5 mm and `unitsPerMeter = 200`. Used for `shape_points.x/y`, `wall_lengths.length` and furniture positions. Canvas y points **down**. |
| local project id | `projects.id` (SQLite `AUTOINCREMENT`). The cloud sync payload also sends it to the backend as `project.local_id`. |
| shape / room | `SketchShape` (`sketch/sketch_model.dart` L30). Fields: `id` (generated String), `points` (`List<Offset>`, world units), `isClosed`, `label`, `wallRealMm` (`Map<int,double>`), `roomObjects` (`List<RoomObject>`), `sharedWalls`, `furnitureItems` (`List<FurnitureItem>`), `heightMm` (default 2400). |
| wall chain | `_wallAngles` (radians) and `_wallDrawnLengths` (world units). These are **screen-level** lists in `SketchScreen` that describe the active shape's walls. They are persisted (duplicated) per shape in `wall_angles` / `wall_lengths`. |
| upload queue | Rows of `pending_uploads`. Each row holds one complete JSON sync payload for one local project. |
| WallPlane | AR capture record: a point on a wall plus that plane's unit normal. Both are in the AR world frame: metres, Y up. |
| polygonMm | AR result: ordered room corners as `Offset(x_mm, z_mm)`. |

```text
 main() ─ ProviderScope (no providers) ─ SmartMeasureApp = MaterialApp(home: AppStartup)
                                   │
      AppStartup.initState: SyncService.instance.init();  ApiService.isLoggedIn() (token present?)
                                   │ pushReplacement
               ┌───────────────────┴────────────────────┐
          LoginScreen ── login / register / "Skip" ──► HomeScreen ── logout icon ──► LoginScreen
                                                       │
     ┌──────────────────────┬──────────────────────────┼─────────────────────────┐
"Start Room Sketch"    "My Projects"          "Scan Room with AR"        "Restore from Cloud"
BleConnectionScreen    ProjectListScreen       ARScanScreen               CollaborationScreen
     │ connected / Skip      │ pop(id)              │ push(polygonMm)          │ "Open live"
     ▼ pushReplacement       ▼                     ARResultScreen              ▼
SketchScreen(bleManager) SketchScreen(             │ pushAndRemoveUntil      _LiveCollabWrapper
                         initialLocalProjectId)    ▼ (route.isFirst)          └─ SketchScreen(cloudProjectId)
                                                SketchScreen(initialShapes: [AR shape])

 Persistence / sync
 SketchScreen, CollaborationScreen ─ saveProject / loadProject / deleteProject ─► DatabaseHelper.instance ─► smartmeasure.db v4
 ProjectListScreen ─ getAllProjects / deleteProject ─┘                                            ▲ pending_uploads
 SketchScreen ─ SyncService.queueUpload(payload) ─► SyncService.instance ─ processQueue ─► ApiService.uploadProject ─► backend POST /sync
```

### 4.2 Features and how they work

#### 4.2.1 App start-up and login gate

Trigger: the app process starts.

1. `main()` (`main.dart` L10) calls `runApp(const ProviderScope(child: SmartMeasureApp()))`.
   - There is no `WidgetsFlutterBinding.ensureInitialized()` and nothing is awaited before `runApp`.
   - `ProviderScope` has no overrides, and no provider exists anywhere in the app (see §4.2.10).
2. `SmartMeasureApp.build` (L22) returns a `MaterialApp` with:
   - `title: AppConstants.appName` ("SmartMeasure Pro", from `core/constants.dart`)
   - `debugShowCheckedModeBanner: false`
   - `theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), useMaterial3: true)`
   - `home: const AppStartup()`

   The app sets no `darkTheme`/`themeMode`, `routes`, `onGenerateRoute`, `navigatorKey`, localisation delegates or navigator observers. Many screens hard-code a dark navy palette (`#0D1A27`, `#1A2A3A`, `#00AAFF`) that ignores this light Material-3 theme.
3. `_AppStartupState.initState` (L44) does two things:
   - It calls `SyncService.instance.init()` (`services/sync_service.dart` L32). This subscribes to `Connectivity().onConnectivityChanged`: whenever any interface is connected it calls `processQueue()`, otherwise it sets the status to `offline`. It also starts a 60-second `Timer.periodic` that calls `processQueue()`. Both run for the lifetime of the process; `SyncService.dispose()` is never called.
   - It then calls `_checkLogin()`.
4. `_checkLogin()` (L50) runs `await ApiService.isLoggedIn()`, which only checks that `FlutterSecureStorage.read(key: 'jwt_token')` is non-null. If the State is still mounted, it calls `Navigator.pushReplacement(MaterialPageRoute(builder: (_) => loggedIn ? const HomeScreen() : const LoginScreen()))`.
5. While waiting, `build` (L64) shows a `Scaffold` with background `#0D1A27` and a centred `CircularProgressIndicator(color: #00AAFF)`.

Side effects and what does not happen:
- The database is not opened at start-up. It opens lazily on the first `DatabaseHelper.instance.database` access.
- No runtime permissions are requested at start-up (see §4.2.11).
- Token validity is not checked. The backend issues JWTs with `expiresIn: '7d'` (`smartmeasure-backend/src/routes/auth.js` L76–80), but an expired token still routes to `HomeScreen`; later API calls then fail.
- The route created by `home:` is replaced, so after start-up the bottom route of the navigator is `HomeScreen` or `LoginScreen`. `ARResultScreen` relies on this (§4.2.8).

#### 4.2.2 Home screen hub

`HomeScreen` (`screens/home_screen.dart` L13) is a `StatefulWidget` whose only state is `_userEmail`.

**Showing the user's email.** `_loadUserEmail()` (L29):
1. Reads the JWT through `ApiService.getToken()`.
2. If the token has 3 dot-separated parts, it decodes the payload: `jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))`.
3. It then calls `setState(() => _userEmail = payload['email'])`.

The signature is not verified (the email is display-only). There is no `try/catch` (a malformed token gives an unhandled async error) and no `mounted` check. The backend payload is `{ userId, email }`.

**UI.**
- AppBar:
  - title `AppConstants.appName`, background `colorScheme.inversePrimary`
  - if an email is known, a 12-pt email `Text`
  - `IconButton(Icons.logout, tooltip 'Logout')` → `_logout()`
- Body: a centred `Column` (not scrollable, so it may overflow on short or landscape screens) containing:
  - `Icon(Icons.straighten, 80, blue)`
  - title "SmartMeasure Pro" (24, bold)
  - subtitle "Precision hardware. Smart sketching." (14, grey)
  - four `ElevatedButton.icon`s, 32×16 padding, font 18:

| Button (line) | Icon / colour | Action |
|---|---|---|
| "Start Room Sketch" (L89) | `Icons.edit`, theme default | Creates a new `BleManager()` and pushes `BleConnectionScreen(bleManager, onConnected: …)`. The `onConnected` closure runs `Navigator.pushReplacement(context, SketchScreen(bleManager: bleManager))` using HomeScreen's `context`, so it replaces the BLE screen. It fires 1 s after a successful connection, or immediately when the user taps "Skip (test without device)"; after Skip the sketch receives an unconnected manager. |
| "My Projects" (L121) | `Icons.folder_open`, bg `#1A2A3A` | `final projectId = await Navigator.push<int>(ProjectListScreen())`. If the result is non-null and the State is mounted, it pushes `SketchScreen(initialLocalProjectId: projectId)`. **No `BleManager` is passed**, so laser measurement is unavailable in a project opened this way. |
| "Scan Room with AR" (L152) | `Icons.view_in_ar`, bg `#00AA66` | Pushes `ARScanScreen()`. There is no ARCore-availability check first. |
| "Restore from Cloud" (L173) | `Icons.cloud_download`, bg `#8844FF` | Pushes `CollaborationScreen()`: the whole cloud/collaboration hub (owned and shared tabs, join, invite, open live, restore), not just a restore action. |

**Logout.** `_logout()` (L43) runs `await ApiService.logout()` (deletes `jwt_token`) and then `Navigator.pushReplacement(LoginScreen())`. It does **not** stop `SyncService`, clear the upload queue, or clear local projects (see §4.5: no per-user scoping).

#### 4.2.3 Local project picker (open / delete)

`ProjectListScreen` (`database/project_list_screen.dart` L6) is pushed with `Navigator.push<int>` by `HomeScreen` ("My Projects") and by `SketchScreen._loadProject` (toolbar "Load Project", `sketch_screen.dart` L750).

1. `initState` → `_loadProjects()` (L23) → `DatabaseHelper.instance.getAllProjects()` (`SELECT * FROM projects ORDER BY updated_at DESC`) → `setState(_projects = rows; _loading = false)`. There is no `mounted` check.
2. The UI is dark, with background and AppBar `#0D1A27` and the title "Saved Projects" in white:
   - while loading: a spinner
   - with no rows: "No saved projects yet" (`#556677`)
   - otherwise a `ListView.builder` of `ListTile`s, each with:
     - `title`: `p['name']`
     - `subtitle`: raw `p['updated_at']` ISO-8601 string, e.g. `2026-10-22T14:03:11.123456` (11 pt)
     - `leading`: `Icons.folder_outlined` (`#00AAFF`)
     - `trailing`: delete `IconButton` (`Icons.delete_outline`, `#FF4444`)
3. Tapping the delete icon calls `_deleteProject(id)` (L31): `DatabaseHelper.instance.deleteProject(id)` and then `_loadProjects()` (not awaited). There is **no confirmation dialog**. Deleting also removes that project's queued uploads.
4. Tapping a row calls `Navigator.pop(context, p['id'])`, returning the `int` id to the caller. The caller (HomeScreen or SketchScreen) then loads it through `SketchScreen._loadProjectById` (§4.2.4).

Only the name and timestamp are shown: no room count, thumbnail or sync status.

#### 4.2.4 Local persistence in SQLite (`DatabaseHelper`)

**Opening.**
- `DatabaseHelper.instance` is a `static final` singleton with a private constructor `_init()` (L11–13). The `Database` is cached in a static `_database`.
- The getter `database` (L17) opens the file on first use via `_initDB('smartmeasure.db')` (L23). That builds the path `join(await getDatabasesPath(), 'smartmeasure.db')` (on Android, `/data/data/com.example.smart_measure_pro/databases/smartmeasure.db`) and calls `openDatabase(path, version: 4, onCreate: _createTables, onUpgrade: _onUpgrade)`.
- No `onConfigure` exists, so **`PRAGMA foreign_keys` is never enabled** and every `FOREIGN KEY … ON DELETE CASCADE` clause is inert. The comment in `deleteProject` acknowledges this; the comment in `updateProject` contradicts it.
- `AppConstants.dbName = "smart_measure.db"` (`core/constants.dart`) is never used. The real file name is hard-coded as `smartmeasure.db`.

**Schema and migrations.**
- A fresh install runs `_createTables` (L35), which creates 9 tables: `projects`, `shapes`, `shape_points`, `wall_real_mm`, `wall_angles`, `wall_lengths`, `room_objects`, `furniture_items`, `pending_uploads`. The full column reference is in §4.4.
- Upgrades run `_onUpgrade` (L156):
  - `oldVersion < 2`: `CREATE TABLE IF NOT EXISTS pending_uploads`
  - `< 3`: `CREATE TABLE IF NOT EXISTS furniture_items`
  - `< 4`: `ALTER TABLE room_objects ADD COLUMN shape_index INTEGER NOT NULL DEFAULT 0` and `… ADD COLUMN swing_flipped INTEGER NOT NULL DEFAULT 0`. Each is guarded by `_hasColumn` (L151), which checks `PRAGMA table_info(<table>)`.
- There is no `onDowngrade`.

**Saving: `saveProject(...)` (L203), always an INSERT.** Everything below runs in one `db.transaction`:
1. `INSERT projects(name, created_at = now, updated_at = now)`. `now = DateTime.now().toIso8601String()`: local time, no UTC offset.
2. For each shape `s` (index = list position):
   - `INSERT shapes(project_id, shape_index = s, is_closed = 0/1)`
   - one `shape_points` row per point (`order_index`, `x`, `y`, in world units)
   - one `wall_real_mm` row per map entry (`wall_index`, `real_mm`)
   - **the global** `wallAngles` list as `wall_angles(order_index, angle)` and the global `wallDrawnLengths` as `wall_lengths(order_index, length)`. The same two lists are written under **every** shape.
   - one `room_objects` row per `shape.roomObjects` element: `object_id`, `type = RoomObjectType.name` (`door|window|opening`), `wall_index`, `position_along`, `width_mm`, `height_mm`, `elevation_mm`, `swing_flipped` 0/1, `shape_index = s`.
3. Furniture: `furniturePerShape ?? shapes.map((s) => List<FurnitureItem>.from(s.furnitureItems))`, giving one `furniture_items` row per item: `furniture_id`, `type = FurnitureType.name`, `position_x/y` (world units), `rotation_deg`, `width_mm`, `depth_mm`, `shape_index`.
4. Returns the new `projects.id`.

Parameter quirks:
- `shapes` is `List<dynamic>` and accessed dynamically (`shape.isClosed`, `shape.points`, …), so there is no compile-time type safety.
- The `roomObjects` parameter is **ignored**; doors and windows come from each `shape.roomObjects`.
- No caller passes `furniturePerShape`.

**Callers' save semantics.** These are implemented in `sketch_screen.dart`, but they define how this table is used:

| Caller | Trigger | DB calls | Consequence |
|---|---|---|---|
| `_saveProject` (L468) | Toolbar "Save Project" (enabled when the active shape has ≥1 point) | Name dialog (default "Room Project"), then `saveProject(...)` | Always inserts a **new** project and sets `_localProjectId` to it. An earlier row for the same sketch is kept, so repeated saves create duplicates. |
| `_handleBackPressed` (L324), existing project, `_isDirty` | Back arrow (L3564) or system back (`PopScope(canPop: false)`, L3065) | "Save Changes" dialog (rename allowed) → `saveProject(...)` (new row) → `deleteProject(oldId)` (errors ignored) → pop | An "update" is insert-new plus delete-old. The local id changes, `created_at` is reset, and `deleteProject` also deletes the old id's `pending_uploads`. |
| `_handleBackPressed`, never saved, any shape with ≥2 points | Back | "Unsaved Project" → `save` → `_saveProject()`; pops only if `_isDirty` is now false | — |
| `_queueAutoSync` (L612) | After edits (room naming, real-measurement application, shape closing, point drags…), only if `canEdit` and logged in | If `_localProjectId == null`: `saveProject(name: 'Auto Save')` once. Then `SyncService.queueUpload(projectId, _buildProjectPayload(...), lastModifiedAt)` | Later edits are **only queued for the cloud**. The local SQLite copy keeps the geometry from its first save until the user saves explicitly. |
| `_backupToCloud` (L645) | Toolbar "Backup to Cloud" | If there is no local id, `saveProject(chosenName)`; then `queueUpload` | — |
| `_loadProject` / `_loadProjectById` (L750 / L760) | Toolbar "Load Project", or `initialLocalProjectId` | `loadProject(id)` | Replaces all shapes **without** an unsaved-changes prompt. |
| `CollaborationScreen._restoreProject` (L66) | Cloud popup "Restore to device" | `ApiService.downloadProject` → `_parseProjectData` (doors/windows and furniture attached to shapes) → `saveProject(name)` → pop | Every restore creates another local copy. A cloud type `opening` becomes `window` and `swing_flipped` is lost (the cloud payload carries neither). |
| `CloudProjectsScreen._restoreProject` (L35) | **Unreachable**: the screen is never pushed | `saveProject` with room objects built into a separate list that is never attached to shapes | Would drop all doors, windows and furniture. Dead code. |

**Loading.** `loadProject(id)` (L411) returns `null` if the project row is missing. Otherwise it returns `{project, shapes, room_objects, furniture_items}` (exact shape in §4.4). `SketchScreen._loadProjectById` (L760–846) rebuilds the model:
1. For each shape row in `shape_index` order it builds `SketchShape.empty()`, which gets a **new** `id`, `label ''` and `heightMm 2400`. It then sets `isClosed = is_closed == 1`, `points = Offset(x, y)`, and refills `wallRealMm`.
2. Furniture rows become `FurnitureItem`s in `shapes[shape_index]`. An unknown `type` falls back to `FurnitureType.sofa`.
3. `_wallAngles` / `_wallDrawnLengths` are taken from the **first** shape's `wall_angles` / `wall_lengths` rows.
4. Room-object rows become `RoomObject`s, with `ownerShapeId = shapes[si].id` and type `'door'` → door, `'opening'` → opening, anything else → window. `swingFlipped` is `swing_flipped == 1`. Rows whose `shape_index` is out of range are skipped.
5. It sets `activeIndex = 0`, `_localProjectId`, `_localProjectName` and `_isDirty = false`, then calls `_fitShapesToView()` after the next frame.

If a project has zero shape rows, `shapes` stays empty and `activeShape` (`shapes[activeIndex]`) throws during build. Nothing guards against this.

**Deleting.** `deleteProject(id)` (L499) runs in one transaction:
1. For every shape id of the project: delete its `shape_points`, `wall_real_mm`, `wall_angles` and `wall_lengths` rows (a manual cascade).
2. Delete the project's `shapes`, `room_objects` and `pending_uploads` rows.
3. Delete its `furniture_items` rows, wrapped in `try/catch`.
4. Delete the `projects` row.

**Dead method.** `updateProject(...)` (L313) is **never called**. It would:
- update `updated_at` but not `name`
- delete `shapes`, `room_objects` and `furniture_items`, relying on the disabled CASCADE for the child tables, which would leave orphan point and wall rows
- re-insert everything

`pendingUploadCount()` (L581) is also never called.

#### 4.2.5 Offline upload queue (`pending_uploads`)

The `SyncService` part covers the sync protocol. This part owns the table and its helper methods.

1. `SketchScreen` calls `SyncService.queueUpload(projectId, projectData, lastModifiedAt)`. That JSON-encodes `{...projectData, if (lastModifiedAt != null) 'last_modified_at': lastModifiedAt}` and calls `DatabaseHelper.queueUpload(projectId, payloadJson)` (L526), which inserts `status = 'pending'`, `created_at = now` and `attempts = 0` (default). It then sets the status to `idle` and calls `processQueue()` immediately.
2. `processQueue()` loops:
   - It takes the oldest pending row with `getNextPendingUpload()` (L540): `WHERE status = 'pending' ORDER BY created_at ASC LIMIT 1`, comparing local-time ISO strings.
   - It decodes `payload` and calls `ApiService.uploadProject(payload)`.
   - If the response has `conflict == true`: `markUploadConflict(id)` (L559) sets `status = 'conflict'` and `last_attempt = now`, then the loop stops.
   - If the response has an `error`, or an exception is thrown: `markUploadAttempted(id)` (L570) runs `UPDATE pending_uploads SET attempts = attempts + 1, last_attempt = ? WHERE id = ?`, then the loop stops.
   - On success: `deletePendingUpload(id)` (L553), then `uploadSuccessStream` emits `{local_project_id, cloud_project_id, updated_at}`.
3. Retries come from connectivity changes, the 60-s timer and new enqueues. There is no attempt cap or backoff.

Limitations of the queue:
- Rows marked `conflict` are never retried or cleaned up, except by `deleteProject`.
- Rows are not scoped to a user. Whoever is logged in when the queue drains uploads every queued payload.

**Cloud-id tracking.** The `projects` table has **no** cloud-id, user-id or dirty-flag column. Cloud linkage exists only in:
- the queued JSON (`project.local_id`, optionally `project.cloud_project_id`, optionally `last_modified_at`)
- memory (`SketchScreen._cloudProjectId` and `_lastCloudUpdatedAt`, learned from `uploadSuccessStream` or from `widget.cloudProjectId` in live sessions)

The backend first matches `cloud_project_id`, and otherwise falls back to `(user_id, local_id)` (`smartmeasure-backend/src/routes/sync.js` L25–40). After an app restart the cloud id is forgotten, so matching depends on `local_id`. That value changes on every back-press save (§4.2.4) and is not unique across devices or reinstalls.

#### 4.2.6 AR room scan: session, plane detection, wall capture

Trigger: HomeScreen "Scan Room with AR" pushes `ARScanScreen` (`ar/ar_scan_screen.dart` L30). The code comments label this file as phases AR-1/AR-2 and the polygon/result files as AR-3/AR-5. No AR-4 or AR-6 code exists. All AR code arrived in commit `169022a` ("implement AR room scanning track (AR-1 through AR-5)").

1. **Permission.** The plugin's `ARView` widget (built at `ar_scan_screen.dart` L178) requests `Permission.camera` in its own `initState`, using `permission_handler` through the plugin.
   - Granted or limited: the native platform view is shown.
   - Denied: the plugin shows `permissionPromptDescription` ("Camera access is needed for AR room scanning.") and a button "Grant Camera Access" that re-requests.
   - Permanently denied: the same button opens the app settings.
   - Restricted (iOS): a parental-restriction text.

   App code never calls `permission_handler` directly.
2. **Session configuration.** `ARView(planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical)` (enum index 3 → ARCore `PlaneFindingMode.HORIZONTAL_AND_VERTICAL`). `_onARViewCreated(session, objects, anchors, location)` (L68):
   - stores `_sessionManager = session`
   - calls `session.onInitialize(showAnimatedGuide: false, showFeaturePoints: false, showWorldOrigin: false, showPlanes: true, handleTaps: true)`
   - wires `session.onPlaneOrPointTap = _onPlaneTap` and `session.onPlaneDetected = (count) => setState(() => _detectedPlaneCount = count)`

   The object, anchor and location managers are received but unused.
3. **Plane detection.** The native side draws coloured plane overlays (`showPlanes: true`) and calls `onPlaneDetected(n)`.
   - `n` is cumulative and never decreases.
   - On Android it is `detectedPlanes.size`: distinct planes that ever reached `TRACKING`. On iOS it increments once per added `ARPlaneAnchor`.
   - It counts floors, tables and ceilings too.
   - The UI shows a chip "N surface(s) detected".
4. **Tap-to-capture.** A single tap makes the native side hit-test and call `_onPlaneTap(List<ARHitTestResult>)` (L90):
   1. Ignore the tap if `_generating` is true or the result list is empty.
   2. `hit` = the first result with `type == ARHitTestResultType.plane`, otherwise `results.first`.
   3. `t = hit.worldTransform` (a `Matrix4` in column-major storage).
   4. **Normal extraction:** `normal = Vector3(t.storage[4], t.storage[5], t.storage[6])`. This is matrix column 1, the pose's local +Y axis, which for a plane hit is the plane normal.
   5. **Floor/ceiling rejection:** `if (abs(normal.y) > 0.5) return;`. A surface counts as a wall only if its normal lies within 30° of horizontal.
   6. **Position:** `Vector3(t.storage[12], t.storage[13], t.storage[14])`, the translation column (metres, Y up). This is the tapped point, not the plane centre.
   7. **De-duplication:** for each captured wall `w`, `if (abs(w.normal.dot(normal)) > cos(25°) ≈ 0.9063) return;`. Because of `abs`, this rejects both "same wall tapped again" **and any wall parallel to an existing one, including the opposite wall**.
   8. Otherwise `setState(() => _walls.add(WallPlane(position: position, normal: normal.normalized())))`.

   Rejected taps give **no feedback**.
5. **Overlay UI** (a `Stack` over the `ARView`; black AppBar titled "AR Room Scan"):
   - **Pulsing instruction banner** (top 12): opacity animated 0.5↔1.0 over 2 s with `easeInOut`. Text: "Move slowly — coloured overlays show detected surfaces. Tap each wall surface to capture it." until the first capture, then "N wall(s) captured. Tap K more wall(s)." or "… Ready to generate!".
   - **Plane-count chip** (top 90, left 14).
   - **Captured-wall chips** "Wall i ×" (top 86, right 12, green): a tap calls `_removeWall(i)` (L126).
   - **AppBar action** `Icons.restart_alt` "Clear all walls" (shown only when walls exist): `_walls.clear()`.
   - **Bottom area:**
     - while fewer than 3 walls: "Tap K more wall(s) to enable generation", where `K = (3 - captured).clamp(0, 3)`
     - a full-width "Generate Floor Plan" button (`Icons.map_outlined`, `blueAccent`), enabled only when `captured >= 3 && !_generating`
6. **Generate.** `_generatePlan()` (L130):
   1. Guard: at least 3 walls and not already generating.
   2. `setState(_generating = true)`, then compute `polygonMm = wallPlanesToPolygonMm(_walls)` **synchronously**, then `setState(_generating = false)`. The "Calculating…" spinner therefore never actually renders.
   3. If fewer than 3 corners come back: SnackBar "Could not reconstruct a room polygon. Capture more walls and try again."
   4. Otherwise `await Navigator.push(ARResultScreen(polygonMm: polygonMm))`. The result is ignored, and the captured walls survive a back navigation.
7. **Cleanup.** `dispose()` (L60) disposes `_pulseCtrl` and calls `_sessionManager?.dispose()` (not awaited), which sends the native `dispose` call.

> **Platform reality check, from reading the plugin source `ar_flutter_plugin_2-0.0.3` in the local pub cache.** On Android, `ArView.kt` (L519–540) hit-tests the tap and keeps only hits on `TRACKING` `Plane`s. It sends `{type: 1, distance, position{x,y,z}}`. `Serialization/Serializers.kt::serializeHitResult` then builds `Pose(position, quaternion [0,0,0,1])`, which has **identity rotation**. So `worldTransform` column 1 is always `(0, 1, 0)`, and step 4.5 rejects **every** tap as floor/ceiling. **With the resolved plugin version, no wall can ever be captured on Android**, the app's primary platform. On iOS the plugin serialises ARKit's full `worldTransform`, so normals would be meaningful (but see §4.2.11 for iOS gaps). I have not verified this on a device.
>
> **Logic limitation, independent of platform.** Because the de-duplication test uses `abs(dot)`, a rectangular room yields at most **2** capturable walls (one per axis). The 3-wall minimum is therefore unreachable for rectangular rooms. An L-shaped room (6 walls, 4 directions) can never be captured fully either. Only rooms with at least 3 distinct wall directions can pass.

#### 4.2.7 AR polygon reconstruction (`wallPlanesToPolygonMm`)

`ar/ar_polygon_math.dart` L27. Input: `List<WallPlane>` (metres, AR world frame, Y up). Output: `List<Offset>` in **millimetres**, or `[]` when the geometry is degenerate.

1. If `walls.length < 3` → `[]`.
2. **Projection to the floor plane (XZ).** For each wall, with `(nx, nz) = (normal.x, normal.z)` and `len = sqrt(nx² + nz²)`:
   - if `len < 0.001`, skip it (horizontal surface)
   - otherwise keep a record `(pos: Offset(position.x, position.z), nor: Offset(nx/len, nz/len))`

   The tap height (Y) is discarded. If fewer than 3 walls remain → `[]`.
3. **Cyclic ordering.** Compute the centroid of the tap points, `cx = mean(pos.dx)` and `cz = mean(pos.dy)`. Sort the walls ascending by `atan2(pos.dy − cz, pos.dx − cx)`, which ranges over −π..π. This assumes a roughly convex room where each wall was tapped "around" the centroid. Concave rooms, or taps near corners, can mis-order the walls.
4. **Corners.** For `i = 0..n−1`, intersect `sorted[i]` with `sorted[(i+1) % n]` using `_intersect2D` (L75). Each wall is the line `n · x = d` with `d = n · p`. With `det = n1.x·n2.y − n1.y·n2.x`:
   - if `abs(det) < 1e-6` (parallel or anti-parallel), return `null` and the corner is **silently skipped**
   - otherwise `x = (d1·n2.y − d2·n1.y) / det` and `y = (n1.x·d2 − n2.x·d1) / det` (Cramer's rule)
5. If fewer than 3 corners → `[]`. Otherwise return `corners.map((c) => Offset(c.dx·1000, c.dy·1000))`, converting metres to mm.

Other properties:
- **Winding:** ascending `atan2` in (x, z). On the y-down sketch canvas this appears **clockwise**.
- **No validation:** the result is not checked for self-intersection or area, and the corner count may be less than the wall count.

Worked example (geometry that would work if all four walls could be captured): a 4 m × 3 m room tapped at the wall midpoints (0, 1.5), (4, 1.5), (2, 0), (2, 3) with normals (1,0), (−1,0), (0,1), (0,−1).
- The centroid is (2, 1.5). Sorting gives (2,0) [−π/2], (4,1.5) [0], (2,3) [π/2], (0,1.5) [π].
- Corners: (4,0), (4,3), (0,3), (0,0) m, i.e. `[(4000,0), (4000,3000), (0,3000), (0,0)]` mm.

#### 4.2.8 AR result editor and import into the sketch

`ARResultScreen(polygonMm)` (`ar/ar_result_screen.dart` L14). It uses the default light theme, AppBar "Scan Result", and an action `TextButton.icon(Icons.check, "Import to Sketch")`.

**State:**
- `_corners`: a mutable copy of `polygonMm` (raw mm, without scale)
- `_scaleCorrection`: 1.0
- `_draggingIndex`
- the view transform `_viewOrigin` / `_viewScale`

**Derived values and transforms:**
- `_displayed` = `_corners[i] × _scaleCorrection`
- `_toScreen(mm) = mm·_viewScale + _viewOrigin`
- `_toMm(s) = (s − _viewOrigin) / _viewScale`

**Layout (top to bottom):**
1. **Scale slider row** (`_buildScaleSlider`, L168): "Scale:" + `Slider(min 0.5, max 2.0, divisions 30` (step 0.05)`)` + value text "x.xx×". It sets `_scaleCorrection`; the intent is to correct AR scale drift.
2. A grey hint: "Drag corner handles to fine-tune. Tap "Import to Sketch" when ready."
3. **Polygon view** (`_buildPolygonView`, L196): a `LayoutBuilder` that calls `_recomputeView(box.biggest)` **on every build**, then a `GestureDetector` with pan handlers wrapping `CustomPaint(_PolygonPainter)`. `_recomputeView` (L52):
   - fits the bounding box of `_displayed` into the box with an 80-px total margin: `_viewScale = min((W − 80) / w, (H − 80) / h)`
   - centres it
   - returns early if `w < 1` or `h < 1`

   Consequences:
   - **The scale slider has no visible effect on the drawing.** Auto-fit cancels it; only the length labels change.
   - While dragging a corner that changes the bounding box, the whole drawing re-fits under the finger, so the dragged handle drifts.
4. **Dimension chips** (`_buildDimensionChips`, L216): one `Chip` per wall, "W{i+1}: {len}", where `len = |p[i+1] − p[i]|` in mm. The label is `"x.xx m"` if `len ≥ 1000`, otherwise `"n mm"`.

**Gestures:**
- `_onPanStart` (L74): selects the first displayed corner within **26 px** of the finger.
- `_onPanUpdate` (L84): `_corners[i] = _toMm(pos) / _scaleCorrection`, stored without scale.
- `_onPanEnd` (L91): clears the selection.

There is no way to add or delete corners.

**Painter** `_PolygonPainter` (L249):
- room fill: `Colors.blue` at 10 % alpha
- outline: `blue.shade700`, 2.5 px
- per-wall length label at the edge midpoint, shifted up 12 px (`blue.shade900`, 11 pt)
- corner handles: radius 9 blue, or 15 orange while dragging, with a 2-px white ring and a white bold corner number
- `shouldRepaint` compares fields, and `_displayed` is a new list each time, so it always repaints

**Import** `_importToSketch()` (L95):
1. `pts = _displayed` (mm, scale-corrected).
2. `unitPts = pts / mmPerUnit`, converting mm to world units (÷ 5).
3. Translate so the **vertex average** sits at the world anchor `(200, 200)`. The sketch re-fits the view anyway via `_fitShapesToView`, so the anchor only fixes the world coordinates.
4. `wallRealMm[i] = |pts[(i+1) % n] − pts[i]|` in mm for **every** wall `i = 0..n−1`, including the closing wall.
5. Create `SketchShape(points: centred, isClosed: true, label: 'AR Scan', wallRealMm: wallRealMm, heightMm: 2400)`. The new shape gets a fresh `id` and empty `roomObjects`, `furnitureItems` and `sharedWalls`.
6. `Navigator.pushAndRemoveUntil(MaterialPageRoute(SketchScreen(initialShapes: [shape])), (route) => route.isFirst)`. This removes `ARResultScreen` and `ARScanScreen`, leaving `[HomeScreen, SketchScreen]`.

Effects in the sketch:
- The sketch gets **no `BleManager`**, no `initialWallAngles` / `initialWallLengths` and no local project id.
- `_applyRealMeasurement` (`sketch_screen.dart` L1846) returns early while `wallIndex >= _wallAngles.length`. `_wallAngles` is empty until a gesture triggers `_syncWallDefinitions()` (L1815), so laser or 3D-view measurements on a freshly imported AR room are ignored until then.
- The label "AR Scan" and `heightMm` are not persisted by SQLite (§4.4).
- Nothing is saved until the user saves, or until `_queueAutoSync` creates "Auto Save" (logged-in users only).

#### 4.2.9 App-wide navigation graph

There are no named routes, deep links, `onGenerateRoute` or `navigatorKey`. Every navigation uses `MaterialPageRoute` on the root navigator.

| # | From → To | API (file:line) | Trigger | Arguments passed | Result / notes |
|---|---|---|---|---|---|
| 1 | MaterialApp → `AppStartup` | `home:` (`main.dart` L30) | App launch | — | — |
| 2 | `AppStartup` → `HomeScreen` or `LoginScreen` | `pushReplacement` (`main.dart` L53) | After `ApiService.isLoggedIn()` | — | The start-up route is replaced. |
| 3 | `LoginScreen` → `HomeScreen` | `pushReplacement` (`login_screen.dart` L58) | Successful login, or register followed by automatic login | — | — |
| 4 | `LoginScreen` → `HomeScreen` | `pushReplacement` (`login_screen.dart` L192) | "Skip for now (local only)" | — | No token, so cloud features fail. |
| 5 | `HomeScreen` → `LoginScreen` | `pushReplacement` (`home_screen.dart` L46) | AppBar logout icon | — | Runs after `ApiService.logout()`. |
| 6 | `HomeScreen` → `BleConnectionScreen` | `push` (`home_screen.dart` L99) | "Start Room Sketch" | `bleManager: BleManager()` (new instance), `onConnected` closure | — |
| 7 | `BleConnectionScreen` → `SketchScreen` | `pushReplacement` inside HomeScreen's closure (`home_screen.dart` L105) | `connectStream` emits `true`, then 1 s delay (`ble_connection_screen.dart` L26–35); or "Skip (test without device)" (L165) | `bleManager` (same instance; unconnected after Skip) | Replaces the BLE screen, so back from the sketch returns Home. The `connectStream` listener is never cancelled. |
| 8 | `HomeScreen` → `ProjectListScreen` | `push<int>` (`home_screen.dart` L132) | "My Projects" | — | Returns a local project id or `null`. |
| 9 | `ProjectListScreen` → caller | `pop(context, p['id'])` (`project_list_screen.dart` L70) | Tap a row | — | `int` id |
| 10 | `HomeScreen` → `SketchScreen` | `push` (`home_screen.dart` L138) | Non-null result of #8 | `initialLocalProjectId: id` | No `BleManager`. |
| 11 | `HomeScreen` → `ARScanScreen` | `push` (`home_screen.dart` L163) | "Scan Room with AR" | — | — |
| 12 | `ARScanScreen` → `ARResultScreen` | `await push` (`ar_scan_screen.dart` L147) | "Generate Floor Plan" with ≥3 walls and ≥3 corners | `polygonMm: List<Offset>` (mm) | Result ignored; walls are kept on back. |
| 13 | `ARResultScreen` → `SketchScreen` | `pushAndRemoveUntil(…, route.isFirst)` (`ar_result_screen.dart` L127) | AppBar "Import to Sketch" | `initialShapes: [SketchShape('AR Scan')]` | The stack becomes `[HomeScreen, SketchScreen]`. |
| 14 | `HomeScreen` → `CollaborationScreen` | `push` (`home_screen.dart` L184) | "Restore from Cloud" | — | — |
| 15 | `CollaborationScreen` → `_LiveCollabWrapper` (wraps `SketchScreen`) | `await push` (`collaboration_screen.dart` L106) | Popup "Open live" (owned projects: `canEdit: true`) or "Open live (auto-sync)" (shared projects: `canEdit = p['can_edit']`) | `cloudProjectId`, `projectName`, `initialShapes`, `initialWallAngles`, `initialWallLengths`, `lastKnownUpdatedAt`, `canEdit` | `SketchScreen` is an embedded child (`bleManager: null`). A 10-s poll rebuilds it with a new `UniqueKey` whenever the cloud copy changes (local state resets). |
| 16 | `CollaborationScreen` → previous | `pop` (`collaboration_screen.dart` L85) | After a successful "Restore to device" | — | — |
| 17 | `SketchScreen` → `ProjectListScreen` | `push<int>` (`sketch_screen.dart` L751) | Toolbar "Load Project" (`Icons.folder_open`, L3912) | — | The id goes to `_loadProjectById`. |
| 18 | `SketchScreen` → `Room3DScreen` | `push` (`sketch_screen.dart` L3420) | "3D View" button, visible only when the active shape is closed with ≥3 points and no furniture is selected or being placed | `shapes`, `initialActiveShapeIndex: activeIndex`, `bleManager`, `onWallMeasured` → `_applyRealMeasurement`, `onHeightChanged` → `activeShape.heightMm = mm` + `_saveUndo()` | The callbacks mutate sketch state; there is no return value. |
| 19 | `SketchScreen` → `DxfPreviewScreen` | `push` (`sketch_screen.dart` L3878) | Toolbar "Export DXF" (`Icons.architecture`) | `shapes`, `projectName` (`_localProjectName`, or `'SmartMeasure_Room'`) | — |
| 20 | `SketchScreen` → OS print/share UI | `exportSketchPdf` → `Printing.layoutPdf` (`sketch_pdf_export.dart` L80) | Toolbar "Export PDF" (enabled when the active shape has ≥2 points) | `shapes`, `projectName` | Not a Flutter route. |
| 21 | `DxfPreviewScreen` → OS share sheet | `Share.shareXFiles` (`dxf_exporter.dart` L34) | Export action (file written under `getTemporaryDirectory()`) | DXF file | Not a Flutter route. |
| 22 | `SketchScreen` → previous route | `Navigator.of(context).pop()` (`sketch_screen.dart` L326, L414, L416, L423, L460, L462) | `_handleBackPressed`: toolbar back arrow (L3564), or system back through `PopScope(canPop: false)` (L3065) | — | In live sessions this pops the `_LiveCollabWrapper` route. |
| 23 | `CloudProjectsScreen` → previous | `pop` (`cloud_projects_screen.dart` L126) | After a restore | — | **Unreachable**: no code pushes `CloudProjectsScreen`. |

Dialogs that return a value through `Navigator.pop(ctx, value)`:

| Dialog | Location | Returns |
|---|---|---|
| "Save Changes" (existing project, dirty) | `sketch_screen.dart` L334 | `'cancel'`, `'discard'`, or the (possibly edited) project name |
| "Unsaved Project" | `sketch_screen.dart` L426 | `'cancel'`, `'discard'` or `'save'` |
| "Save Project" | `sketch_screen.dart` L470 | Name `String` (prefilled "Room Project") or `null` |
| "Cloud Backup Name" | `sketch_screen.dart` L662 | Name `String` or `null` |
| "Join Project" (invite code) | `collaboration_screen.dart` L126 | Code `String` or `null` |
| Leave-project confirmation | `collaboration_screen.dart` L367 | `bool` |

These dialogs and sheets pop without a result and act inline:
- `sketch_screen.dart` L246 (room name), L1392, L1536, L2784, L2833, L2875 (bottom sheet), L3971
- `sketch_dialogs.dart` L38, L153 (bottom sheet), L244, `ObjectMeasurementDialog`
- `room_3d_screen.dart` L644
- `collaboration_screen.dart` L203, L268

#### 4.2.10 App-wide state-management census

**Riverpod is declared but not used.** A grep of all of `code/lib` for `Provider`, `StateProvider`, `StateNotifierProvider`, `ChangeNotifierProvider`, `FutureProvider`, `StreamProvider`, `NotifierProvider`, `ConsumerWidget`, `ConsumerStatefulWidget`, `Consumer`, `WidgetRef` and `ref.watch` / `ref.read` / `ref.listen` finds only:

| Riverpod element | Location | Notes |
|---|---|---|
| `import 'package:flutter_riverpod/flutter_riverpod.dart'` | `main.dart` L2 | The only Riverpod import. |
| `ProviderScope` | `main.dart` L12 | Root scope with no overrides. |
| Providers of any kind | — | **None.** |
| Consumer widgets / `ref` usage | — | **None.** |

(The other "Provider" matches are `SingleTickerProviderStateMixin` in `ar_scan_screen.dart` L38 and `collaboration_screen.dart` L22: Flutter animation mixins, not Riverpod.)

`CLAUDE.md`'s claim "Riverpod throughout" is inaccurate, as is its reference to a central `SketchModel` class (the model classes are `SketchShape` and `SharedWall` in `sketch_model.dart`).

**What actually holds state:**

| Holder | Kind | File | Holds | Consumers |
|---|---|---|---|---|
| `DatabaseHelper.instance` | Singleton (`static final`, private `_init()`) | `database/database_helper.dart` L11 | Lazily opened sqflite `Database` (`static _database`) | `ProjectListScreen`, `SketchScreen`, `CollaborationScreen`, `CloudProjectsScreen` (dead), `SyncService` |
| `SyncService.instance` | Singleton | `services/sync_service.dart` L11 | `_status` (`SyncStatus.idle/syncing/offline/conflict`); broadcast `statusStream` and `uploadSuccessStream`; connectivity subscription; 60-s timer; `_isProcessing` | `AppStartup` (`init`); `SketchScreen` (`queueUpload`, both streams, `status` at L4082); `_LiveCollabWrapper` (`uploadSuccessStream`) |
| `ApiService` | Static-only class; JWT in `FlutterSecureStorage` key `jwt_token`; `baseUrl` constant | `services/api_service.dart` | Auth token | `AppStartup`, `HomeScreen`, `LoginScreen`, `SketchScreen`, `CollaborationScreen`, `CloudProjectsScreen`, `SyncService` |
| `BleManager` | Plain instance, created per "Start Room Sketch" tap and passed by constructor | `ble/ble_manager.dart` L8 | Broadcast `packetStream` (`BlePacket`) and `connectStream` (`bool`) | `BleConnectionScreen`, `SketchScreen`, `Room3DScreen` |
| `_shapeIdCounter` | Top-level mutable global | `sketch/sketch_model.dart` L7 | Counter used by `generateShapeId()` | `SketchShape` constructor |
| `SketchDialogsMixin` contract | Mixin with abstract getters/setters implemented by `_SketchScreenState` (L155–172) | `sketch/sketch_dialogs.dart` | Shares sketch state with the dialog code | `SketchScreen` |

**Per-screen local state (`setState` counts from grep):**

| Widget | File | Mechanism | Main state |
|---|---|---|---|
| `AppStartup` | `main.dart` | StatefulWidget (no `setState`) | None; one-shot redirect |
| `HomeScreen` | `screens/home_screen.dart` | `setState` ×1 | `_userEmail` |
| `LoginScreen` | `screens/login_screen.dart` | `setState` ×3 | Text controllers, `_isLoading`, `_isLoginMode` |
| `ProjectListScreen` | `database/project_list_screen.dart` | `setState` ×1 | `_projects`, `_loading` |
| `CollaborationScreen` | `database/collaboration_screen.dart` | `setState` ×11 (whole file) + `TabController` | Owned/shared lists, loading flags, `_working` |
| `_LiveCollabWrapper` | `database/collaboration_screen.dart` L763 | `setState` + 10-s `Timer.periodic` + `uploadSuccessStream` subscription | `_shapes`, `_wallAngles`, `_wallLengths`, `_lastUpdatedAt`, `_sketchKey` |
| `CloudProjectsScreen` (unreachable) | `database/cloud_projects_screen.dart` | `setState` ×4 | `_projects`, `_loading`, `_restoring` |
| `BleConnectionScreen` | `ble/ble_connection_screen.dart` | `setState` ×3 + `connectStream` listener (never cancelled) | `_isScanning`, `_statusMessage` |
| `SketchScreen` | `sketch/sketch_screen.dart` | `setState` ×81 + three un-cancelled stream listeners (L203, L219, L223) + 30-s heartbeat `Timer` | `shapes`, `activeIndex`, undo/redo stacks, `_wallAngles` / `_wallDrawnLengths`, `_localProjectId`, `_cloudProjectId`, `_isDirty`, … |
| `Room3DScreen` | `sketch/room_3d_screen.dart` | `setState` ×12 + `WebViewController` | View/rotation state |
| `DxfPreviewScreen` | `screens/dxf_preview_screen.dart` | `setState` ×2 | `_isExporting` |
| `ARScanScreen` | `ar/ar_scan_screen.dart` | `setState` ×6 + `AnimationController` | `_walls`, `_detectedPlaneCount`, `_generating`, `_sessionManager` |
| `ARResultScreen` | `ar/ar_result_screen.dart` | `setState` ×4 | `_corners`, `_scaleCorrection`, `_draggingIndex`, view transform |
| `UnitSelector` | `sketch/sketch_widgets.dart` | `setState` ×1 | Selected unit |
| `ObjectMeasurementDialog` (+ mixin) | `sketch/sketch_dialogs.dart` | `setState` ×3 | Dialog fields |

Data flows between screens through:
- constructor arguments (`BleManager`, `initialShapes`, ids)
- callbacks (`onConnected`, `onWallMeasured`, `onHeightChanged`)
- `Navigator.pop` results
- the two singletons and their broadcast streams

No state survives an app restart except SQLite and the secure-storage token.

#### 4.2.11 Runtime permissions and platform capabilities

| Capability | Declared (Android manifest) | Who requests it at runtime | When |
|---|---|---|---|
| Camera | `CAMERA` (app and AR plugin manifests) | `ARView` in `ar_flutter_plugin_2` → `permission_handler` `Permission.camera.request()` | On opening `ARScanScreen` |
| BLE scan/connect | `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_SCAN` (`usesPermissionFlags="neverForLocation"`), `BLUETOOTH_CONNECT` | `flutter_blue_plus` itself (`FlutterBluePlusPlugin.ensurePermissions`): `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` on API 31+, `ACCESS_FINE_LOCATION` on API ≤30 | On `startScan` / `connect` from `BleManager.connectToDevice` |
| Location | `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | `flutter_blue_plus` on API 28–30 (BLE scanning needs location there). The AR plugin's `ARLocationManager` (geolocator) is never used by app code. | BLE scan on older Android |
| Network | `INTERNET`; `ACCESS_NETWORK_STATE` (merged from `connectivity_plus`) | Normal permissions | — |
| Storage | None | Not needed: DXF goes to `getTemporaryDirectory()` and is shared; PDF goes through `Printing.layoutPdf` | — |

**ARCore.**
- The app manifest says `<uses-feature android:name="android.hardware.camera.ar" android:required="false"/>` and `<meta-data com.google.ar.core = "optional"/>`.
- The plugin's own manifest declares `camera.ar` `required="true"` and `glEsVersion 0x00030000` required. In the locally built merged manifest (`code/build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`) **`camera.ar` ends up `required="true"`**.
- `uses-feature` only affects Google Play filtering, not APK sideloading. The app never checks ARCore availability before opening the AR screen. ARCore installation and errors are handled natively: the merged manifest contains `com.google.ar.core.InstallActivity`, and the plugin's default `onError` handler shows a SnackBar.

**Realistic platform support:**

| Platform | Status |
|---|---|
| **Android** | The only realistic target: minSdk 28 (Android 9), targetSdk = Flutter default (36 in the local merged manifest). |
| **iOS** | Scaffolding only. `Info.plist` has only `NSCameraUsageDescription`. **`NSBluetoothAlwaysUsageDescription` is missing** (iOS terminates apps that use CoreBluetooth without it). There is no App Transport Security exception, so every call to the plain-HTTP backend `http://13.214.196.211:3000` would be blocked. No `Podfile` is committed. Deployment target is 13.0 (matches the plugin podspec); bundle id `com.example.smartMeasurePro`. |
| **Web, Windows, Linux, macOS** | Template folders only: sqflite has no web, Windows or Linux implementation, the AR plugin is mobile-only, and `webview_flutter` has no web implementation configured. |

#### 4.2.12 Tests, linting and tooling

- **Tests.** `flutter test` **fails to compile**: `test/widget_test.dart` pumps `const MyApp()`, which does not exist (the root widget is `SmartMeasureApp`). The test is the unmodified Flutter counter template ('Counter increments smoke test': expects text '0', taps `Icons.add`, expects '1'). Even with the class renamed, `AppStartup` calls platform plugins (secure storage, connectivity) that are unavailable in widget tests.
- **Linting.** `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` (flutter_lints 6.0.0) with no custom rules.
- **Launcher icons.** They are generated by `flutter_launcher_icons` 0.13.1, run manually (`dart run flutter_launcher_icons`), using the `flutter_launcher_icons:` block in `pubspec.yaml` (Android and iOS, source `assets/icon/app_icon.png`).

### 4.3 File reference

#### `code/pubspec.yaml` — 109 lines

- **Purpose:** Flutter package manifest for the mobile app: name, version, SDK constraint, dependencies, assets, launcher-icon generation config.
- **Depends on:** pub.dev packages (table in §4.4); local assets under `code/assets/`.
- **Declarations (keys):**
  - `name: smart_measure_pro`; `description: "A new Flutter project."` (template text); `publish_to: "none"`; `version: 1.0.0+1` (versionName 1.0.0, versionCode 1)
  - `environment.sdk: ^3.10.7` (Dart ≥3.10.7 <4.0.0). There is no explicit `flutter:` constraint; the local `pubspec.lock` derives `flutter: ">=3.38.4"`.
  - `dependencies`: `flutter` (sdk), `path ^1.8.3`, `flutter_blue_plus ^1.31.0`, `riverpod ^2.5.1`, `flutter_riverpod ^2.5.1`, `sqflite ^2.3.2`, `path_provider ^2.1.3`, `pdf ^3.12.0`, `printing ^5.13.1`, `share_plus ^9.0.0`, `http ^1.2.0`, `flutter_secure_storage ^9.0.0`, `connectivity_plus ^6.0.3`, `webview_flutter ^4.10.0`, `ar_flutter_plugin_2 ^0.0.3`, `permission_handler ^11.3.1`, `vector_math ^2.1.0`, `cupertino_icons ^1.0.8`
  - `dev_dependencies`: `flutter_test` (sdk), `flutter_launcher_icons ^0.13.1`, `flutter_lints ^6.0.0`
  - `flutter.uses-material-design: true`; `flutter.assets`: `assets/icon/`, `assets/3d/`, `assets/models/`. **No fonts are declared** (only template comments).
  - `flutter_launcher_icons: {android: true, ios: true, image_path: "assets/icon/app_icon.png"}`
- **Key logic:** None. The code uses Dart 3 features (records in `ar_polygon_math.dart`, record destructuring and switch statements without `break` in `collaboration_screen.dart`), so the Dart 3 constraint is required.
- **State and data:** `code/pubspec.lock` exists locally but is **git-ignored** (`*.lock` in both the root and `code/` `.gitignore`), so builds are not reproducible from a clone. Resolved versions are in §4.4.
- **Connections:** Read by `flutter pub get` and by the Gradle and Xcode builds. The assets are loaded by `sketch/room_3d_screen.dart` (`rootBundle`, L90–92 and L113).
- **Notes and issues:**
  - Declared but unused in app code: `riverpod`, `permission_handler`, `cupertino_icons`; `flutter_riverpod` is effectively unused.
  - `assets/models/` is not committed (`*.glb` and `*.gltf` are ignored by the root `.gitignore`). Locally it holds 35 files (34 `.glb` + 1 `.gltf`, about 201 MB). A fresh clone lacks the directory, and Flutter's asset bundler reports a missing declared asset directory as an error, so the build fails until it is created or populated. The 3D-view part documents how the models are used. At least `assets/models/tv_unit.glb`, referenced at `room_3d_screen.dart` L133, is absent even locally.
  - `assets/icon/` is bundled into the app although only the icon generator needs it.

#### `code/analysis_options.yaml` — 28 lines

- **Purpose:** Static-analysis configuration.
- **Depends on:** `flutter_lints` (dev dependency).
- **Declarations:** `include: package:flutter_lints/flutter.yaml`. `linter.rules:` contains only commented-out examples (`avoid_print: false`, `prefer_single_quotes: true`), so no rules are customised. There is no `analyzer:` section (no excludes, no strict modes).
- **Notes and issues:** This is the unmodified template. Expected analyzer findings include an unused `package:flutter/material.dart` import in `database_helper.dart` (no Material or `dart:ui` symbol is referenced there).

#### `code/README.md` — 2 lines

- **Purpose:** Placeholder README: `# smart_measure_pro` / `SmartMeasure Pro Flutter app`.
- **Notes and issues:** No setup, build or architecture information. The repository-root `CLAUDE.md` is the only developer documentation, and parts of it are inaccurate (Riverpod, `SketchModel`).

#### `code/test/widget_test.dart` — 30 lines

- **Purpose:** The default Flutter template widget test.
- **Depends on:** `flutter/material.dart`, `flutter_test`, `package:smart_measure_pro/main.dart`.
- **Declarations:** `void main()` (L13) registers one `testWidgets('Counter increments smoke test', …)` (L14). It pumps `const MyApp()`, expects `find.text('0')` once and `'1'` not at all, taps `find.byIcon(Icons.add)`, pumps, then expects the reverse.
- **Notes and issues:** **Does not compile**, because `MyApp` does not exist (the app widget is `SmartMeasureApp`). It also tests counter behaviour that the app does not have. There are no real tests in the project.

#### `code/lib/main.dart` — 73 lines

- **Purpose:** Entry point. Creates the Riverpod root scope and the `MaterialApp`, starts the sync service, and redirects to home or login.
- **Depends on:**
  - `flutter/material.dart`
  - `flutter_riverpod` (`ProviderScope`)
  - `screens/home_screen.dart`, `screens/login_screen.dart` (redirect targets)
  - `services/api_service.dart` (`isLoggedIn`)
  - `services/sync_service.dart` (`SyncService.instance.init`)
  - `core/constants.dart` (`AppConstants.appName`)
- **Declarations:**
  - `void main()` (L10): `runApp(const ProviderScope(child: SmartMeasureApp()))`.
  - `class SmartMeasureApp extends StatelessWidget` (L18): `build` (L22) returns the `MaterialApp` described in §4.2.1.
  - `class AppStartup extends StatefulWidget` (L35): `createState()` → `_AppStartupState`.
  - `class _AppStartupState extends State<AppStartup>` (L42), no fields:
    - `initState()` (L44): `SyncService.instance.init()`, then `_checkLogin()` (not awaited).
    - `Future<void> _checkLogin()` (L50): `await ApiService.isLoggedIn()`; if mounted, `Navigator.pushReplacement` to `HomeScreen` or `LoginScreen`.
    - `build()` (L64): dark `Scaffold` (`#0D1A27`) with a centred `CircularProgressIndicator(color: #00AAFF)`.
- **Key logic:** The start-up gate only checks that a token exists.
- **State and data:** None persistent. `SyncService` starts its long-lived subscriptions here.
- **UI:** Only the loading spinner.
- **Connections:** `test/widget_test.dart` imports this file (and references a nonexistent `MyApp`).
- **Notes and issues:**
  - `ProviderScope` wraps an app that has no providers.
  - `SyncService.init()` runs even when the user is not logged in. Queue processing then fails without a token.
  - There is no splash or branding during the check.
  - No error handling if secure-storage reads throw.

#### `code/lib/screens/home_screen.dart` — 196 lines

- **Purpose:** Main hub after login. Shows the user's email and launches the four main flows.
- **Depends on:**
  - `dart:convert` (JWT payload decode)
  - `core/constants.dart` (title)
  - `ble/ble_manager.dart`, `ble/ble_connection_screen.dart` (sketch-with-device flow)
  - `sketch/sketch_screen.dart`
  - `services/api_service.dart` (`getToken`, `logout`)
  - `screens/login_screen.dart`
  - `database/project_list_screen.dart`
  - `database/collaboration_screen.dart`
  - `ar/ar_scan_screen.dart`
- **Declarations:**
  - `class HomeScreen extends StatefulWidget` (L13).
  - `class _HomeScreenState extends State<HomeScreen>` (L20):
    - field `String? _userEmail` (L21)
    - `initState()` (L24) → `_loadUserEmail()`
    - `Future<void> _loadUserEmail()` (L29): decodes the JWT payload's `email` claim (§4.2.2)
    - `Future<void> _logout()` (L43): `ApiService.logout()`, then `pushReplacement(LoginScreen())`
    - `build()` (L53): AppBar and button column (§4.2.2)
- **Key logic:** JWT decode: split on `.`; require exactly 3 parts; `base64Url.normalize` → `base64Url.decode` → `utf8.decode` → `jsonDecode` → `['email']`.
- **State and data:** `_userEmail` only.
- **UI:** AppBar (title, email text, logout icon). Buttons "Start Room Sketch" (L89), "My Projects" (L121), "Scan Room with AR" (L152), "Restore from Cloud" (L173); targets in §4.2.9 rows 5–14.
- **Connections:** Pushed by `AppStartup` and `LoginScreen`. It is the `route.isFirst` target for `ARResultScreen`.
- **Notes and issues:**
  - An unguarded JWT decode can throw; `setState` runs without a `mounted` check.
  - The button column is not scrollable, so small screens can overflow.
  - "Restore from Cloud" is a misleading label: it opens the full collaboration hub.
  - Projects opened from "My Projects" get no `BleManager`.
  - Every "Start Room Sketch" tap creates a new `BleManager`.
  - The Logout button is shown even when the user skipped login.

#### `code/lib/database/database_helper.dart` — 588 lines

- **Purpose:** Single access point to the local SQLite database: schema creation and migration, project save/load/delete, and the offline upload queue.
- **Depends on:**
  - `sqflite` (`Database`, `openDatabase`, `getDatabasesPath`)
  - `path` (`join`)
  - `flutter/material.dart` (appears unused)
  - `sketch/room_object.dart` (`RoomObject`, used for typing and `obj.type.name`)
  - `sketch/furniture_item.dart` (`FurnitureItem`)
- **Declarations:** `class DatabaseHelper` (L9). Fields: `static final DatabaseHelper instance` (L11), `static Database? _database` (L12). Private constructor `DatabaseHelper._init()` (L13). Methods (SQL details in §4.2.4 and §4.4):

| Member (line) | Signature | Behaviour / SQL | Returns |
|---|---|---|---|
| `database` (L17) | `Future<Database> get database` | Returns the cached DB, otherwise `_initDB('smartmeasure.db')` | Open `Database` |
| `_initDB` (L23) | `Future<Database> _initDB(String fileName)` | `openDatabase(join(getDatabasesPath(), fileName), version: 4, onCreate: _createTables, onUpgrade: _onUpgrade)` | `Database` |
| `_createTables` (L35) | `Future _createTables(Database db, int version)` | 9 × `CREATE TABLE` (`projects` L38, `shapes` L49, `shape_points` L60, `wall_real_mm` L72, `wall_angles` L83, `wall_lengths` L94, `room_objects` L105, `furniture_items` L122, `pending_uploads` L138) | — |
| `_hasColumn` (L151) | `Future<bool> _hasColumn(Database db, String table, String column)` | `PRAGMA table_info($table)`; true if any row has `name == column` | `bool` |
| `_onUpgrade` (L156) | `Future _onUpgrade(Database db, int oldVersion, int newVersion)` | v<2: create `pending_uploads`; v<3: create `furniture_items`; v<4: add `room_objects.shape_index` and `.swing_flipped` if missing | — |
| `saveProject` (L203) | `Future<int> saveProject({required String name, required List<dynamic> shapes, required List<RoomObject> roomObjects /* ignored */, required List<double> wallAngles, required List<double> wallDrawnLengths, List<List<FurnitureItem>>? furniturePerShape})` | One transaction of inserts (§4.2.4) | New project id |
| `updateProject` (L313) | `Future<void> updateProject({required int projectId, required List<dynamic> shapes, required List<RoomObject> roomObjects, required List<double> wallAngles, required List<double> wallDrawnLengths})` | `UPDATE projects SET updated_at`; `DELETE` `shapes` / `room_objects` / `furniture_items` by `project_id`; re-insert. **Never called; orphans child rows.** | — |
| `getAllProjects` (L405) | `Future<List<Map<String, dynamic>>> getAllProjects()` | `SELECT * FROM projects ORDER BY updated_at DESC` | Rows `{id, name, created_at, updated_at}` |
| `loadProject` (L411) | `Future<Map<String, dynamic>?> loadProject(int projectId)` | Project row; shapes `ORDER BY shape_index`; per shape: points, angles, lengths `ORDER BY order_index` and `wall_real_mm` (unordered); `room_objects` and `furniture_items` `ORDER BY shape_index` | Map (§4.4) or `null` |
| `deleteProject` (L499) | `Future<void> deleteProject(int projectId)` | Manual cascade in one transaction (§4.2.4), including `pending_uploads` | — |
| `queueUpload` (L526) | `Future<void> queueUpload({required int projectId, required String payloadJson})` | `INSERT pending_uploads(project_id, payload, created_at, status='pending')` | — |
| `getNextPendingUpload` (L540) | `Future<Map<String, dynamic>?> getNextPendingUpload()` | `… WHERE status='pending' ORDER BY created_at ASC LIMIT 1` | Row or `null` |
| `deletePendingUpload` (L553) | `Future<void> deletePendingUpload(int id)` | `DELETE … WHERE id=?` | — |
| `markUploadConflict` (L559) | `Future<void> markUploadConflict(int id)` | `UPDATE … SET status='conflict', last_attempt=now` | — |
| `markUploadAttempted` (L570) | `Future<void> markUploadAttempted(int id)` | `UPDATE pending_uploads SET attempts = attempts + 1, last_attempt = ? WHERE id = ?` | — |
| `pendingUploadCount` (L581) | `Future<int> pendingUploadCount()` | `SELECT COUNT(*) as c FROM pending_uploads WHERE status = 'pending'`. **Never called.** | `int` |

- **Key logic:**
  - Writes are wrapped in transactions, with sequential `await txn.insert` per row (no `Batch`).
  - Children are keyed by `shape_id`, but `room_objects` and `furniture_items` are keyed by `(project_id, shape_index)`.
  - Timestamps are local-time ISO-8601 without an offset.
- **State and data:** Schema in §4.4. Enum values are stored by `.name`.
- **Connections:**
  - `ProjectListScreen`: `getAllProjects`, `deleteProject`.
  - `SketchScreen`: `saveProject` at L388, L505, L621, L697; `deleteProject` at L407; `loadProject` at L761.
  - `CollaborationScreen`: `saveProject` at L76.
  - `CloudProjectsScreen` (dead): `saveProject` at L108.
  - `SyncService`: `queueUpload` L66, `getNextPendingUpload` L80, `markUploadConflict` L93, `markUploadAttempted` L97 and L111, `deletePendingUpload` L102.
- **Notes and issues:**
  - Foreign keys are never enabled, so the CASCADE clauses do nothing.
  - The ignored `roomObjects` parameter and the `dynamic` shapes parameter remove type safety.
  - Global wall angles and lengths are duplicated under every shape.
  - `label`, `heightMm`, `sharedWalls` and shape `id` are not persisted.
  - There is no user, cloud-id or sync-state column.
  - `updateProject` and `pendingUploadCount` are dead code.
  - `AppConstants.dbName` (`smart_measure.db`) disagrees with the real file name.
  - A race between two concurrent first calls of `database` is benign (sqflite returns a single instance per path).
  - `getNextPendingUpload` ordering uses local-time strings, which can misorder around DST changes.

#### `code/lib/database/project_list_screen.dart` — 76 lines

- **Purpose:** Lists local projects, lets the user delete one, and returns the tapped project's id.
- **Depends on:** `flutter/material.dart`, `database_helper.dart`.
- **Declarations:**
  - `class ProjectListScreen extends StatefulWidget` (L6).
  - `class _ProjectListScreenState` (L13):
    - fields `List<Map<String, dynamic>> _projects = []` (L14), `bool _loading = true` (L15)
    - `initState()` (L18) → `_loadProjects()`
    - `Future<void> _loadProjects()` (L23): `getAllProjects()`, then `setState`
    - `Future<void> _deleteProject(int id)` (L31): `deleteProject(id)`, then reload
    - `build()` (L37)
- **UI:** Described in §4.2.3. A row tap calls `Navigator.pop(context, p['id'])` (L70); the trash icon deletes immediately.
- **Connections:** Pushed with `push<int>` by `HomeScreen` (L132) and `SketchScreen._loadProject` (L751).
- **Notes and issues:**
  - No delete confirmation, and deleting also drops that project's queued uploads.
  - Shows the raw ISO timestamp.
  - `setState` without a `mounted` check.
  - No sync indicator.
  - Duplicate entries appear because of the insert-only save semantics (§4.2.4).

#### `code/lib/furniture_3d_viewer.dart` — 0 lines

- **Purpose:** None. The file is empty: 0 bytes, git blob `e69de29…`, last touched in commit `8fcd51c` "fix the 3d view issue".
- **Connections:** Not imported anywhere.
- **Notes and issues:** Dead placeholder. The 3D view is implemented in `sketch/room_3d_screen.dart` (see the 3D part).

#### `code/lib/ar/ar_polygon_math.dart` — 84 lines

- **Purpose:** Pure geometry for phase AR-3: converts captured wall planes into an ordered 2-D room polygon in mm.
- **Depends on:** `dart:math` (`sqrt`, `atan2`); `flutter/material.dart` (`Offset`); `vector_math/vector_math_64.dart` (`Vector3`; `Colors` hidden to avoid a clash).
- **Declarations:**
  - `class WallPlane` (L18):
    - fields `final Vector3 position` (a point on the wall, AR metres, Y up) and `final Vector3 normal` (documented as the "unit outward normal"; in practice it is the plane pose's +Y axis, which for ARCore/ARKit vertical planes faces the observed side)
    - constructor `WallPlane({required position, required normal})`
  - `List<Offset> wallPlanesToPolygonMm(List<WallPlane> walls)` (L27): public entry point. Returns ordered corners in mm, or `[]`.
  - `Offset? _intersect2D(Offset p1, Offset n1, Offset p2, Offset n2)` (L75): intersection of the lines `n1·x = n1·p1` and `n2·x = n2·p2`; `null` if `abs(det) < 1e-6`.
- **Key logic:** The full algorithm and formulas are in §4.2.7. The local list `walls2d` holds Dart records `({Offset pos, Offset nor})`, where `Offset.dy` carries Z.
- **State and data:** Stateless.
- **Connections:** Called only by `ARScanScreen._generatePlan` (`ar_scan_screen.dart` L134). `WallPlane` is built in `_onPlaneTap`.
- **Notes and issues:**
  - Hard-coded magic numbers: minimum 3 walls, horizontal-normal threshold 0.001, determinant epsilon 1e-6, ×1000 scale.
  - Parallel consecutive walls are dropped silently, so the corner count can be less than the wall count.
  - Ordering assumes a convex room.
  - The output is not validated.
  - Output winding is clockwise on the y-down canvas.

#### `code/lib/ar/ar_scan_screen.dart` — 340 lines

- **Purpose:** AR-1 and AR-2: runs the ARCore/ARKit session, shows detected planes, captures wall planes on tap, and launches polygon generation (AR-3 entry).
- **Depends on:**
  - `dart:math`
  - `flutter/material.dart`
  - `ar_flutter_plugin_2`: `ar_flutter_plugin.dart` (`ARView`), `datatypes/config_planedetection.dart`, `managers/ar_anchor_manager.dart`, `ar_location_manager.dart`, `ar_object_manager.dart`, `ar_session_manager.dart`, `datatypes/hittest_result_types.dart`, `models/ar_hittest_result.dart`
  - `vector_math_64` (`Vector3`)
  - `ar_polygon_math.dart`, `ar_result_screen.dart`
- **Declarations:**
  - `class ARScanScreen extends StatefulWidget` (L30): no parameters.
  - `class _ARScanScreenState extends State<ARScanScreen> with SingleTickerProviderStateMixin` (L37). Fields:
    - `ARSessionManager? _sessionManager` (L39)
    - `final List<WallPlane> _walls` (L40)
    - `int _detectedPlaneCount = 0` (L41)
    - `bool _generating = false` (L42)
    - `late final AnimationController _pulseCtrl` (L44): 2 s, repeat with reverse
    - `late final Animation<double> _pulseAnim` (L45): `Tween(0.5 → 1.0)` with `Curves.easeInOut`
  - Methods:
    - `initState()` (L48): creates the pulse animation.
    - `dispose()` (L60): disposes the animation and calls `_sessionManager?.dispose()`.
    - `_onARViewCreated(ARSessionManager, ARObjectManager, ARAnchorManager, ARLocationManager)` (L68): session init and callback wiring (§4.2.6 step 2).
    - `_onPlaneTap(List<ARHitTestResult>)` (L90): hit selection, normal and position extraction, floor/ceiling rejection, 25° de-duplication, append.
    - `_removeWall(int index)` (L126).
    - `Future<void> _generatePlan()` (L130).
    - `build()` (L156).
- **Key logic:**
  - `worldTransform.storage` is column-major: indices 4–6 are column 1 (the local Y axis, used as the normal) and 12–14 the translation.
  - Thresholds: `abs(normal.y) > 0.5` → reject; `abs(dot) > cos(25°)` → reject.
- **State and data:** `_walls` exists in memory only and is lost when the screen is popped. Nothing is persisted.
- **UI:** AppBar "AR Room Scan" with a conditional "Clear all walls" action. A `Stack` of:
  - `ARView` (plugin permission prompt texts set here)
  - pulsing instruction banner (top 12)
  - surfaces-detected chip (top 90, left 14)
  - removable "Wall i" chips (top 86, right 12)
  - bottom hint and the "Generate Floor Plan" / "Calculating…" button (bottom 32)
- **Connections:** Pushed by `HomeScreen` (L163). Pushes `ARResultScreen` (L147). Uses `wallPlanesToPolygonMm`.
- **Notes and issues:**
  - **Android wall capture cannot succeed with plugin 0.0.3** (identity rotation in hit results, §4.2.6).
  - `abs(dot)` de-duplication rejects opposite walls, so rectangular rooms cannot reach 3 walls.
  - Rejected taps give no feedback.
  - The "Calculating…" state never renders (synchronous computation).
  - The plane counter includes non-wall planes.
  - The object, anchor and location managers are unused.
  - ARCore availability is not checked.
  - A mis-captured wall can only be fixed by removing its chip. There is no visual marker of captured walls in the AR scene.

#### `code/lib/ar/ar_result_screen.dart` — 344 lines

- **Purpose:** AR-5: preview and edit of the reconstructed polygon (drag corners, global scale correction, wall lengths) and import into `SketchScreen` as a closed `SketchShape`.
- **Depends on:** `dart:math`; `flutter/material.dart`; `sketch/sketch_constants.dart` (`mmPerUnit`); `sketch/sketch_model.dart` (`SketchShape`); `sketch/sketch_screen.dart` (`SketchScreen`).
- **Declarations:**
  - `class ARResultScreen extends StatefulWidget` (L14): `final List<Offset> polygonMm` (ordered corners in mm); constructor `ARResultScreen({super.key, required this.polygonMm})`.
  - `class _ARResultScreenState` (L24). Fields:
    - `late List<Offset> _corners` (L25)
    - `double _scaleCorrection = 1.0` (L26)
    - `int? _draggingIndex` (L27)
    - `Offset _viewOrigin = Offset.zero` (L30)
    - `double _viewScale = 1.0` (L31)
  - Methods:
    - `initState()` (L34): `_corners = List.of(widget.polygonMm)`.
    - getter `_displayed` (L41): corners × `_scaleCorrection`.
    - `_toScreen(Offset mm)` (L44) and `_toMm(Offset screen)` (L48): view transforms.
    - `_recomputeView(Size size)` (L52): fit-to-view with an 80-px total margin.
    - `_onPanStart(Offset)` (L74): selects a handle within 26 px.
    - `_onPanUpdate(Offset)` (L84): `_corners[i] = _toMm(pos) / _scaleCorrection`.
    - `_onPanEnd()` (L91).
    - `_importToSketch()` (L95): §4.2.8.
    - `build()` (L139), `_buildScaleSlider()` (L168), `_buildPolygonView()` (L196), `_buildDimensionChips()` (L216).
  - `class _PolygonPainter extends CustomPainter` (L249):
    - fields `corners` (mm), `viewOrigin`, `viewScale`, `draggingIndex`
    - `_s(Offset mm)` (L262): mm → screen
    - `paint` (L267): fill, outline, length labels, numbered handles
    - `shouldRepaint` (L339)
- **Key logic:**
  - Import transform: `world = (mm × scale) / 5 − vertexMean + (200, 200)`.
  - `wallRealMm[i] = |p(i+1 mod n) − p(i)|` in mm.
  - Length labels: ≥1000 mm shows "x.xx m", otherwise "n mm".
- **State and data:** Edited corners exist in memory only. Output: one `SketchShape(points, isClosed: true, label: 'AR Scan', wallRealMm, heightMm: 2400)`.
- **UI:** AppBar "Scan Result" with the "Import to Sketch" action; scale slider (0.5–2.0, 30 divisions); hint text; interactive polygon canvas; wall-length chips "W1: …".
- **Connections:** Pushed by `ARScanScreen`. Replaces the AR stack with `SketchScreen(initialShapes: [shape])` through `pushAndRemoveUntil(route.isFirst)`.
- **Notes and issues:**
  - Auto-fit on every build makes the scale slider visually inert (only the labels change) and makes dragged handles drift.
  - `_recomputeView` mutates state during build.
  - No add/remove-corner tools and no self-intersection check.
  - Hard-coded `heightMm: 2400`, label `'AR Scan'` and anchor `(200, 200)`.
  - The imported sketch has no BLE manager and an empty wall chain (measurements are ignored until the first gesture).
  - The label "AR Scan" is lost on a local save and load.

#### Android platform files (`code/android/…`) — 7 files, 172 lines

| File | Lines |
|---|---|
| `code/android/app/build.gradle.kts` | 44 |
| `code/android/build.gradle.kts` | 24 |
| `code/android/settings.gradle.kts` | 26 |
| `code/android/gradle.properties` | 8 |
| `code/android/gradle/wrapper/gradle-wrapper.properties` | 5 |
| `code/android/app/src/main/AndroidManifest.xml` | 60 |
| `code/android/app/src/main/kotlin/com/example/smart_measure_pro/MainActivity.kt` | 5 |

- **Purpose:** Android build and manifest configuration for the only realistically supported platform.
- **`settings.gradle.kts`:**
  - `pluginManagement` reads `flutter.sdk` from `local.properties` (git-ignored; generated by Flutter) with `require(... != null)` and calls `includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")`.
  - Repositories: `google()`, `mavenCentral()`, `gradlePluginPortal()`.
  - Plugins: `dev.flutter.flutter-plugin-loader` **1.0.0**, `com.android.application` **8.11.1** (AGP) `apply false`, `org.jetbrains.kotlin.android` **2.2.20** `apply false`.
  - `include(":app")`.
- **`build.gradle.kts` (root):**
  - `allprojects` repositories `google()` and `mavenCentral()`.
  - Moves the build output to `code/build` (`rootProject.layout.buildDirectory` = `../../build`) and each subproject to `code/build/<name>`.
  - `subprojects { evaluationDependsOn(":app") }`; a `clean` (`Delete`) task.
- **`app/build.gradle.kts`:**
  - Plugins: `com.android.application`, `kotlin-android`, `dev.flutter.flutter-gradle-plugin` (applied last).
  - `namespace = applicationId = "com.example.smart_measure_pro"` (template TODO to change).
  - `compileSdk = flutter.compileSdkVersion`; `ndkVersion = flutter.ndkVersion`.
  - Java 17 source and target; `kotlinOptions.jvmTarget = "17"` (the legacy `kotlinOptions` DSL).
  - `minSdk = 28` with the comment "ar_flutter_plugin_2 requires API 28+" (the plugin's own `minSdkVersion` is 28).
  - `targetSdk = flutter.targetSdkVersion` (36 in the local merged manifest).
  - `versionCode` / `versionName` from pubspec (1 / "1.0.0").
  - The `release` build uses **`signingConfigs.getByName("debug")`** (TODO).
  - `flutter { source = "../.." }`.
- **`gradle.properties`:**
  - `org.gradle.jvmargs=-Xmx8G -XX:MaxMetaspaceSize=4G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError`
  - `android.useAndroidX=true`, `kotlin.incremental=false`
  - HTTP(S) socket timeout 300000 ms and connection timeout 60000 ms, as `systemProp` entries (for slow dependency downloads)
- **`gradle-wrapper.properties`:** `distributionUrl=https://services.gradle.org/distributions/gradle-8.14-all.zip`; standard `GRADLE_USER_HOME` paths.
- **`AndroidManifest.xml`:**
  - Permissions: `INTERNET`, `CAMERA`, `BLUETOOTH`, `BLUETOOTH_ADMIN`, `BLUETOOTH_SCAN` (`usesPermissionFlags="neverForLocation"`), `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`.
  - `<uses-feature android.hardware.camera.ar required="false">`.
  - `<application>`: `label="smart_measure_pro"`, **`usesCleartextTraffic="true"`** (needed for the plain-HTTP backend `http://13.214.196.211:3000` in `ApiService.baseUrl`), `name="${applicationName}"`, `icon="@mipmap/ic_launcher"`.
  - `MainActivity`: `exported`, `launchMode="singleTop"`, `taskAffinity=""`, `theme=@style/LaunchTheme`, the full Flutter `configChanges` list, `hardwareAccelerated="true"`, `windowSoftInputMode="adjustResize"`, meta-data `io.flutter.embedding.android.NormalTheme`, and a MAIN/LAUNCHER intent filter.
  - Application meta-data: `flutterEmbedding=2` and `com.google.ar.core=optional`.
  - `<queries>` for `PROCESS_TEXT`.
- **What the locally built merged manifest adds** (verified in `code/build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`):
  - `camera.ar` becomes `required="true"`; `glEsVersion 0x00030000` required
  - `ACCESS_NETWORK_STATE`
  - share_plus and printing `FileProvider`s
  - geolocator's `GeolocatorLocationService` (from the AR plugin's dependency)
  - ARCore `min_apk_version 240350000` and `InstallActivity`
  - package queries for `com.google.ar.core` and `com.android.vending`
- **`MainActivity.kt`:** `package com.example.smart_measure_pro`; `class MainActivity : FlutterActivity()`. No method channels or native code.
- **Connections:** These files configure every Android plugin: `flutter_blue_plus`, `ar_flutter_plugin_2` (SceneView/ARCore), `sqflite`, `webview_flutter`, `share_plus`, `printing`, `connectivity_plus`, `flutter_secure_storage`.
- **Notes and issues:**
  - `com.example.*` id and debug-signed release.
  - Cleartext traffic carries the JWT and project data unencrypted.
  - The merged `camera.ar required="true"` contradicts `com.google.ar.core=optional` and would restrict Play distribution to ARCore devices.
  - Builds need about 8 GB of heap plus 4 GB of metaspace.
  - `BLUETOOTH` and `BLUETOOTH_ADMIN` are not capped with `maxSdkVersion="30"` (harmless).
  - The launcher label is "smart_measure_pro", not the brand name.

#### iOS and web platform files — `code/ios/Runner/Info.plist` (53 lines), `code/web/index.html` (38 lines), `code/web/manifest.json` (35 lines)

- **Purpose:** iOS bundle metadata and web PWA shell. Both are essentially templates.
- **`Info.plist`:**
  - `CFBundleDisplayName` "Smart Measure Pro"; `CFBundleName` `smart_measure_pro`; identifier, executable and versions from build variables (`$(PRODUCT_BUNDLE_IDENTIFIER)` = `com.example.smartMeasurePro` in `project.pbxproj`; `FLUTTER_BUILD_NAME` / `NUMBER`)
  - `LSRequiresIPhoneOS`; `UILaunchStoryboardName` LaunchScreen; `UIMainStoryboardFile` Main
  - Orientations: iPhone portrait and landscape left/right; iPad all four
  - **`NSCameraUsageDescription`** "Used for AR room scanning to detect walls and reconstruct a floor plan."
  - `io.flutter.embedded_views_preview` true (obsolete key); `CADisableMinimumFrameDurationOnPhone` true; `UIApplicationSupportsIndirectInputEvents` true
  - The Xcode project's deployment target is 13.0, matching the AR plugin podspec (`s.platform = :ios, '13.0'`; pods `GLTFSceneKit`, `SwiftJWT`, `ARCoreNanoPbUpdated/CloudAnchors ~> 1.46.0.2`).
- **`index.html`:** Flutter web template: `<base href="$FLUTTER_BASE_HREF">`, description "A new Flutter project.", Apple web-app meta tags, `favicon.png`, `manifest.json` link, loader `flutter_bootstrap.js`.
- **`manifest.json`:** `name` / `short_name` "smart_measure_pro", `start_url "."`, `display "standalone"`, `background_color` / `theme_color` "#0175C2", `orientation "portrait-primary"`, icons `Icon-192.png`, `Icon-512.png` and maskable 192/512.
- **Connections:** None to app code.
- **Notes and issues:**
  - **iOS:**
    - No `NSBluetoothAlwaysUsageDescription`, so the app would be terminated on the first CoreBluetooth access.
    - No `NSAppTransportSecurity` exception, so the HTTP backend is unreachable.
    - No location usage string (geolocator is linked through the AR plugin).
    - No committed `Podfile`.
    - No evidence the app was ever built for iOS.
  - **Web:** Unmodified template; the app cannot run on web (sqflite, AR plugin and WebView have no web implementation).
  - Naming is inconsistent across platforms: "SmartMeasure Pro" (in-app), "Smart Measure Pro" (iOS), "smart_measure_pro" (Android label, web).

### 4.4 Data contracts

#### SQLite schema: `smartmeasure.db`, version 4

The file is in `getDatabasesPath()`. Foreign keys are **not** enforced: there is no `PRAGMA foreign_keys=ON`.

| Table | Column | Type / constraints | Meaning / units |
|---|---|---|---|
| `projects` | `id` | `INTEGER PRIMARY KEY AUTOINCREMENT` | Local project id. Also the backend `local_id`. |
| | `name` | `TEXT NOT NULL` | Project name |
| | `created_at` | `TEXT NOT NULL` | Local-time ISO-8601 (`DateTime.now().toIso8601String()`) |
| | `updated_at` | `TEXT NOT NULL` | Same format. Equals `created_at`, because the only writer is the insert-only `saveProject`. |
| `shapes` | `id` | `INTEGER PRIMARY KEY AUTOINCREMENT` | Row id (not the `SketchShape.id` string) |
| | `project_id` | `INTEGER NOT NULL`, FK → `projects(id)` `ON DELETE CASCADE` (inert) | — |
| | `shape_index` | `INTEGER NOT NULL` | Position in the `shapes` list |
| | `is_closed` | `INTEGER NOT NULL DEFAULT 0` | 0/1 |
| `shape_points` | `id` | `INTEGER PK AUTOINCREMENT` | — |
| | `shape_id` | `INTEGER NOT NULL`, FK → `shapes(id)` CASCADE (inert) | — |
| | `order_index` | `INTEGER NOT NULL` | Point order |
| | `x`, `y` | `REAL NOT NULL` | World units (1 = 5 mm), y down |
| `wall_real_mm` | `id` | `INTEGER PK AUTOINCREMENT` | — |
| | `shape_id` | `INTEGER NOT NULL`, FK → `shapes` (inert) | — |
| | `wall_index` | `INTEGER NOT NULL` | Wall i = segment from point i to point i+1 (wrapping for closed shapes) |
| | `real_mm` | `REAL NOT NULL` | Measured or real length, mm |
| `wall_angles` | `id` | `INTEGER PK AUTOINCREMENT` | — |
| | `shape_id` | `INTEGER NOT NULL`, FK → `shapes` (inert) | — |
| | `order_index` | `INTEGER NOT NULL` | — |
| | `angle` | `REAL NOT NULL` | Radians, `atan2(dy, dx)` in world coordinates. A copy of the screen-global `_wallAngles` written under every shape. |
| `wall_lengths` | `id` | `INTEGER PK AUTOINCREMENT` | — |
| | `shape_id` | `INTEGER NOT NULL`, FK → `shapes` (inert) | — |
| | `order_index` | `INTEGER NOT NULL` | — |
| | `length` | `REAL NOT NULL` | Drawn length in world units. A copy of the global `_wallDrawnLengths`. |
| `room_objects` | `id` | `INTEGER PK AUTOINCREMENT` | — |
| | `project_id` | `INTEGER NOT NULL`, FK → `projects` (inert) | — |
| | `shape_index` | `INTEGER NOT NULL DEFAULT 0` | Owning shape (added by the v4 migration) |
| | `object_id` | `TEXT NOT NULL` | `RoomObject.id` |
| | `type` | `TEXT NOT NULL` | `door` / `window` / `opening` (`RoomObjectType.name`) |
| | `wall_index` | `INTEGER NOT NULL` | Host wall |
| | `position_along` | `REAL NOT NULL` | 0.0 = wall start, 1.0 = wall end |
| | `width_mm`, `height_mm`, `elevation_mm` | `REAL NOT NULL` | mm (elevation is sill height above the floor) |
| | `swing_flipped` | `INTEGER NOT NULL DEFAULT 0` | 0/1 door-swing side (added by v4) |
| `furniture_items` | `id` | `INTEGER PK AUTOINCREMENT` | — |
| | `project_id` | `INTEGER NOT NULL`, FK → `projects` (inert) | — |
| | `shape_index` | `INTEGER NOT NULL` | Owning shape |
| | `furniture_id` | `TEXT NOT NULL` | `FurnitureItem.id` |
| | `type` | `TEXT NOT NULL` | `FurnitureType.name`: one of 31 camelCase values (`sofa`, `armchair`, `coffeeTable`, `floorLamp`, `bookshelf`, `tvUnit`, `singleBed`, `doubleBed`, `queenBed`, `kingBed`, `dresser`, `nightstand`, `wardrobe`, `diningTable`, `roundDiningTable`, `barStool`, `chair`, `kitchenCounter`, `islandCounter`, `refrigerator`, `stove`, `sink`, `bathtub`, `shower`, `toilet`, `basinSink`, `vanity`, `desk`, `officeChair`, `filingCabinet`, `washingMachine`). Unknown values load as `sofa`. |
| | `position_x`, `position_y` | `REAL NOT NULL` | Centre, world units |
| | `rotation_deg` | `REAL NOT NULL` | Degrees clockwise, 0 = facing right |
| | `width_mm`, `depth_mm` | `REAL NOT NULL` | mm |
| `pending_uploads` | `id` | `INTEGER PK AUTOINCREMENT` | Queue item |
| | `project_id` | `INTEGER NOT NULL` (no FK) | Local project id |
| | `payload` | `TEXT NOT NULL` | JSON sync payload (below) |
| | `created_at` | `TEXT NOT NULL` | Local ISO-8601; queue order key |
| | `attempts` | `INTEGER NOT NULL DEFAULT 0` | Incremented by `markUploadAttempted` |
| | `last_attempt` | `TEXT` (nullable) | Local ISO-8601 |
| | `status` | `TEXT NOT NULL DEFAULT 'pending'` | `pending` or `conflict` (no other value is written) |

SQLite also creates `sqlite_sequence` automatically because of `AUTOINCREMENT`.

**Version history** (as implied by `_onUpgrade`):
- v1: `projects`, `shapes`, `shape_points`, `wall_real_mm`, `wall_angles`, `wall_lengths`, `room_objects` (without `shape_index` / `swing_flipped`)
- v2: + `pending_uploads`
- v3: + `furniture_items`
- v4: + `room_objects.shape_index` and `room_objects.swing_flipped`

Fresh installs get the v4 schema directly from `_createTables`.

#### Not persisted locally

| Not stored | Effect |
|---|---|
| `SketchShape.label` | Room names, including "AR Scan", are lost after a save and load. |
| `SketchShape.heightMm` | Ceiling height resets to 2400. |
| `SketchShape.sharedWalls`, `SketchShape.id` | A new id is generated on load; `RoomObject.ownerShapeId` is re-derived from `shape_index`. |
| Per-shape wall chains | Only the global chain is stored (duplicated), and only the first shape's copy is read back. |
| Cloud project id, owner/user id, dirty or sync flags, canvas pan/zoom | — |

#### `DatabaseHelper.loadProject()` return value

```text
{
  "project": { "id": int, "name": String, "created_at": String, "updated_at": String },
  "shapes": [                                   // ORDER BY shape_index; no shape_index / id keys included
    { "is_closed": int(0|1),
      "points":       [ {id, shape_id, order_index, x, y} ... ],     // ORDER BY order_index
      "wall_real_mm": [ {id, shape_id, wall_index, real_mm} ... ],   // unordered
      "wall_angles":  [ {id, shape_id, order_index, angle} ... ],    // ORDER BY order_index
      "wall_lengths": [ {id, shape_id, order_index, length} ... ] }  // ORDER BY order_index
  ],
  "room_objects":    [ full room_objects rows ... ],     // ORDER BY shape_index
  "furniture_items": [ full furniture_items rows ... ]   // ORDER BY shape_index
}
```

#### `pending_uploads.payload` JSON

Built by `SketchScreen._buildProjectPayload` (L537) and wrapped by `SyncService.queueUpload`. The sync part documents its server semantics.

```json
{
  "project": { "name": "Room Project", "local_id": 12, "cloud_project_id": 5 },
  "shapes": [
    { "shape_index": 0, "is_closed": true,
      "points":       [ { "order_index": 0, "x": 400.0, "y": -100.0 } ],
      "wall_real_mm": [ { "wall_index": 0, "real_mm": 3000.0 } ],
      "wall_angles":  [ { "order_index": 0, "angle": 1.5708 } ],
      "wall_lengths": [ { "order_index": 0, "length": 600.0 } ] }
  ],
  "roomObjects":    [ { "object_id": "…", "shape_index": 0, "type": "door", "wall_index": 1,
                        "position_along": 0.5, "width_mm": 900, "height_mm": 2100, "elevation_mm": 0 } ],
  "furnitureItems": [ { "furniture_id": "…", "shape_index": 0, "type": "sofa", "position_x": 380.0,
                        "position_y": 200.0, "rotation_deg": 0, "width_mm": 2000, "depth_mm": 900 } ],
  "last_modified_at": "2026-10-22T09:12:01.000Z"
}
```

`cloud_project_id` and `last_modified_at` are optional. Differences from the SQLite rows:
- `is_closed` is a JSON bool.
- `wall_angles` / `wall_lengths` are recomputed **per shape** from consecutive points (n−1 entries).
- `swing_flipped`, labels and heights are absent.
- In auto-sync the project `name` is the active room's label (or "Room Project"), not the local project name.

#### AR → sketch import format

| Stage | Data | Units / frame |
|---|---|---|
| Tap capture | `WallPlane{position: Vector3(t[12], t[13], t[14]), normal: Vector3(t[4], t[5], t[6]).normalized()}` | Metres, AR world (Y up) |
| Reconstruction | `List<Offset> polygonMm`, each `Offset(X·1000, Z·1000)`, ordered by ascending `atan2` around the tap-point centroid | mm; canvas-style x right, y = Z (down) |
| Editing | `_corners` (raw mm); displayed = `_corners × scale` (0.5–2.0) | mm |
| Import | `SketchShape(points: (mm·scale/5) − vertexMean + (200,200), isClosed: true, label: 'AR Scan', wallRealMm: {i: segment length mm for i = 0..n−1}, heightMm: 2400)` | World units (5 mm) and mm |
| Hand-off | `SketchScreen(initialShapes: [shape])` (no `bleManager`, no wall chain, no project id) | — |

#### Dependency table

Constraints come from `pubspec.yaml`, resolved versions from the local, uncommitted `pubspec.lock`.

| Package | Constraint | Resolved | Imported in (`code/lib`) | Purpose / status |
|---|---|---|---|---|
| `flutter` (sdk) | sdk | — | Everywhere | Framework |
| `path` | ^1.8.3 | 1.9.1 | `database/database_helper.dart` | `join` for the DB path |
| `flutter_blue_plus` | ^1.31.0 | 1.36.8 | `ble/ble_manager.dart` | BLE scan, connect and notifications. Also requests BLE/location permissions natively. |
| `riverpod` | ^2.5.1 | 2.6.1 | none | **Unused** (and redundant with `flutter_riverpod`) |
| `flutter_riverpod` | ^2.5.1 | 2.6.1 | `main.dart` | Only `ProviderScope`; **effectively unused** |
| `sqflite` | ^2.3.2 | 2.4.2 | `database/database_helper.dart` | Local DB |
| `path_provider` | ^2.1.3 | 2.1.5 | `screens/dxf_exporter.dart` | `getTemporaryDirectory()` for the DXF file |
| `pdf` | ^3.12.0 | 3.12.0 | `sketch/sketch_pdf_export.dart` | PDF document building |
| `printing` | ^5.13.1 | 5.13.1 | `sketch/sketch_pdf_export.dart` | `Printing.layoutPdf` (system print/share) |
| `share_plus` | ^9.0.0 | 9.0.0 | `screens/dxf_exporter.dart` | `Share.shareXFiles` for DXF |
| `http` | ^1.2.0 | 1.6.0 | `services/api_service.dart` | REST client |
| `flutter_secure_storage` | ^9.0.0 | 9.2.4 | `services/api_service.dart` | JWT under key `jwt_token` |
| `connectivity_plus` | ^6.0.3 | 6.1.5 | `services/sync_service.dart` | Connectivity changes trigger queue processing |
| `webview_flutter` | ^4.10.0 | 4.14.1 | `sketch/room_3d_screen.dart` | Three.js 3D view |
| `ar_flutter_plugin_2` | ^0.0.3 | 0.0.3 | `ar/ar_scan_screen.dart` | ARCore (SceneView 2.2.1) / ARKit view, planes, hit tests. The plugin declares Dart SDK `<3.0.0` but resolves under Dart 3. It brings in `permission_handler`, `geolocator` and `json_annotation`. |
| `permission_handler` | ^11.3.1 | 11.4.0 | none | **Unused directly**; only used transitively by `ar_flutter_plugin_2` |
| `vector_math` | ^2.1.0 | 2.2.0 | `ar/ar_scan_screen.dart`, `ar/ar_polygon_math.dart` | `Vector3`, `Matrix4` storage |
| `cupertino_icons` | ^1.0.8 | 1.0.8 | none | **Unused** (no `CupertinoIcons`) |
| `flutter_test` (dev, sdk) | sdk | — | `test/widget_test.dart` | Broken test |
| `flutter_launcher_icons` (dev) | ^0.13.1 | 0.13.1 | pubspec config only | Icon generation from `assets/icon/app_icon.png` |
| `flutter_lints` (dev) | ^6.0.0 | 6.0.0 | `analysis_options.yaml` | Lint set |

Lock-file SDK bounds: `dart: ">=3.10.7 <4.0.0"`, `flutter: ">=3.38.4"`.

#### Declared assets

| `pubspec.yaml` entry | Tracked in git | Local contents | Used by |
|---|---|---|---|
| `assets/icon/` | Yes (`app_icon.png`) | 1 file, about 12 KB | Icon generator only (also bundled) |
| `assets/3d/` | Yes (`three.min.js`, `gltf_loader.js`, `three_room.html`) | 3 files, about 764 KB | `room_3d_screen.dart` L90–92 (`rootBundle.loadString`) |
| `assets/models/` | **No.** Ignored via `*.glb` / `*.gltf` in the root `.gitignore`; the directory has no tracked files. | 35 files (34 `.glb` + 1 `.gltf`), about 201 MB | `room_3d_screen.dart` L113 and L128+ (`rootBundle.load`); see the 3D part |

No fonts are bundled. Some widgets request `fontFamily: 'monospace'`, which falls back to a system font.

### 4.5 Known issues and limitations

**AR**
- **AR capture is broken on Android with `ar_flutter_plugin_2` 0.0.3.** Android hit results carry an identity rotation (`Serializers.kt` builds `Pose(position, [0,0,0,1])`). The extracted normal is therefore always (0,1,0), and every tap is rejected as floor/ceiling. This was established from the plugin source, not tested on a device.
- **The AR de-duplication rejects opposite walls.** `abs(dot) > cos 25°` means a rectangular room yields at most 2 walls, so "Generate Floor Plan" (minimum 3) is unreachable. L-shaped rooms cannot be fully captured.
- **AR reconstruction:**
  - walls are ordered by tap-point angle around the centroid, which works only for convex rooms
  - parallel consecutive walls silently drop corners
  - there is no polygon validation
  - the "Calculating…" state never shows
  - rejected taps give no feedback
  - ARCore availability is not checked before opening the screen
- **AR result editor:** auto-fit on every build makes the scale slider visually inert and makes dragged corners drift. Corners cannot be added or removed. `heightMm` (2400), label ("AR Scan") and anchor (200, 200) are hard-coded.
- **AR import side effects:**
  - the sketch opens without a `BleManager`
  - `_wallAngles` is empty, so `_applyRealMeasurement` ignores laser and 3D-view measurements until a gesture rebuilds the chain
  - the label is not persisted in SQLite

**Local persistence and sync**
- **Save semantics create duplicates and id churn.**
  - The toolbar Save always inserts a new project.
  - Saving on back is insert-new plus delete-old: the local id changes, `created_at` is reset, and the old project's queued uploads are deleted.
  - `updated_at` always equals `created_at`.
  - `updateProject` exists but is unused and would orphan rows because the CASCADE is inert.
- **After `Auto Save`, local data goes stale.** Later edits are only queued for the cloud and are not written to SQLite unless the user saves.
- **Foreign keys are never enabled** (no `onConfigure`). All `ON DELETE CASCADE` clauses are inert; `deleteProject` deletes children manually.
- **Lossy local storage:** room labels, ceiling heights, shared walls and per-shape wall chains are not stored. The global wall chain is duplicated under every shape and only shape 0's copy is restored.
- **`saveProject` API quirks:** the `roomObjects` parameter is ignored, `shapes` is `List<dynamic>` (no type safety), and `furniturePerShape` is never used.
- **No user scoping.**
  - Local projects and `pending_uploads` are device-wide.
  - Logout clears only the token.
  - Another user who logs in sees all local projects, and their account uploads any queued payloads.
- **Cloud identity relies on `local_id`.** SQLite autoincrement ids are not unique across devices or reinstalls, and they change on back-press saves. The backend's `(user_id, local_id)` fallback can therefore create duplicate cloud projects or overwrite the wrong one. No cloud id is persisted locally.
- **Upload queue:** no attempt cap or backoff; `conflict` rows are never retried or cleared; `pendingUploadCount` is unused; queue order uses local-time strings.
- **Cloud round-trip loses data:** `opening` objects become `window` and `swing_flipped` is lost (the payload omits it and the parsers map anything that isn't a door to window). Repeated "Restore to device" creates duplicate local projects.
- **Load edge case:** loading a project with zero shapes leaves `shapes` empty, and `SketchScreen.activeShape` would throw a `RangeError`. Loading also replaces the current sketch without an unsaved-changes prompt.

**Dead and unused code**
- `CloudProjectsScreen` is unreachable, and its restore path would drop doors, windows and furniture.
- `furniture_3d_viewer.dart` is an empty tracked file.
- `AppConstants.dbName` (`smart_measure.db`) is unused and differs from the real `smartmeasure.db`.
- **Riverpod is not used.** `ProviderScope` wraps the app but there are no providers or consumers. `CLAUDE.md` ("Riverpod throughout", "`SketchModel`") is inaccurate. State lives in `setState`, two singletons, static `ApiService`, constructor-passed `BleManager` and broadcast streams.
- **Unused dependencies:** `riverpod`, `permission_handler` (transitive only), `cupertino_icons`; `flutter_riverpod` is effectively unused. `assets/icon/` is bundled needlessly.

**App shell and UI**
- **Start-up checks only that a token exists.** Expired 7-day JWTs are not detected. `SyncService` starts even for logged-out users and is never disposed.
- **Home screen:**
  - JWT decode is unguarded, and `setState` runs without a `mounted` check
  - the column is not scrollable
  - "Restore from Cloud" actually opens the full collaboration hub
  - projects opened from "My Projects" have no BLE connection
  - a new `BleManager` is created per tap
  - the `BleConnectionScreen` `connectStream` listener is never cancelled
- **Project list:** no delete confirmation, a raw ISO timestamp, and `setState` without a `mounted` check.
- **Stream subscriptions not cancelled:** `SketchScreen` stores no subscriptions for its BLE and sync streams (L203, L219, L223), so they leak after the screen is disposed.

**Build, tooling and platforms**
- **Tests are broken.** `test/widget_test.dart` references a nonexistent `MyApp`, so `flutter test` fails to compile. There are no real tests.
- **A fresh clone does not build as-is.**
  - `assets/models/` (about 201 MB, 35 model files locally) is git-ignored and absent, so the declared asset directory is missing.
  - `pubspec.lock` is git-ignored, so dependency resolution is not reproducible.
  - `assets/models/tv_unit.glb`, referenced by `room_3d_screen.dart` L133, is missing even locally.
- **Android:**
  - placeholder `com.example.smart_measure_pro` id
  - release build signed with the debug key
  - `usesCleartextTraffic="true"` with a hard-coded HTTP backend IP (credentials and data in clear text)
  - the merged manifest forces `camera.ar required="true"`, contrary to the app's `required="false"` and `com.google.ar.core=optional`
  - Gradle needs about 8 GB of heap plus 4 GB of metaspace
  - the launcher label is "smart_measure_pro"
- **iOS is not realistically supported:**
  - no `NSBluetoothAlwaysUsageDescription` (crash on BLE use)
  - no ATS exception (HTTP backend blocked)
  - no location usage string
  - no committed `Podfile`
  - an obsolete `io.flutter.embedded_views_preview` key
  - no sign of iOS builds
- **Web and desktop folders are untouched templates.** sqflite, the AR plugin and `webview_flutter` do not support those targets.
- **Naming is inconsistent:** "SmartMeasure Pro" (`MaterialApp`, AppBar), "Smart Measure Pro" (iOS), "smart_measure_pro" (Android label, web), and the pubspec description is "A new Flutter project."


---

## Part 5 — Sketch editor: data model, editing screen and geometry

### 5.1 Overview

The sketch editor is the core of the Flutter app. It is one full-screen `StatefulWidget`, `SketchScreen` (`code/lib/sketch/sketch_screen.dart`). In it the user:

- draws one or more rooms as polygons on a zoomable, pannable grid canvas;
- gives walls real lengths, either typed in or measured over BLE with the ESP32 laser;
- places doors, windows and plain openings on walls, and furniture inside rooms;
- drags rooms against each other so that they share walls;
- saves and loads projects (SQLite), syncs and collaborates (REST via `SyncService`/`ApiService`), exports PDF and DXF, and opens the Three.js 3D view.

This part covers:
- the data model: `SketchShape`, `SharedWall`, `RoomObject`;
- the screen and its dialogs/widgets;
- the pure geometry modules: `wall_topology.dart`, `wall_openings.dart`, `room_object_utils.dart`, and the constants/formatters in `sketch_constants.dart`.

Other parts document the painter (`sketch_painter.dart`, `furniture_painter.dart`), the furniture catalogue (`furniture_item.dart`), the PDF/DXF exporters, the 3D screen, BLE, the database and the backend. Here those are described only where this screen calls them: what it passes in and what comes back.

**State management.** All editor state lives in `_SketchScreenState` and is changed with plain `setState`. There are no Riverpod providers: `flutter_riverpod` is only used for the `ProviderScope` in `main.dart`. There is also no class called `SketchModel`; `sketch_model.dart` defines `SketchShape` and `SharedWall`. CLAUDE.md is out of date on both points. The model classes have no `toJson`/`fromJson`. Serialisation is written by hand in three places:
- the screen (`_buildProjectPayload`, `_loadProjectById`);
- `DatabaseHelper`;
- the collaboration/cloud screens.

**Vocabulary**

- **World unit (u)**: the canvas coordinate unit, with 1 u = `mmPerUnit` = 5 mm.
  - All `SketchShape.points`, furniture positions and cursor positions are in world units.
  - x grows to the right and y grows **downward** (screen convention). The origin is arbitrary; at the default view it is at the top-left screen corner.
- **Screen coordinates**: logical pixels. `screen = world * _scale + _panOffset`.
- **Shape / room**: one `SketchShape`. It is an open polyline while being drawn and a closed polygon once `isClosed == true`.
- **Active shape**: `shapes[activeIndex]` (getter `activeShape`, L108). Almost every tool works only on it.
- **Wall i**: the segment `points[i] → points[(i + 1) % n]`.
  - An open shape has n−1 walls and a closed shape has n.
  - The **closing wall** is index n−1, from the last point back to point 0.
- **Drawn length vs real length**:
  - The drawn length is the geometric length in u.
  - The real length is `wallRealMm[i]` in mm, typed or BLE-measured.
  - Applying a real length rebuilds the geometry so that the drawn length becomes real/5.
- **Wall chain**: two screen-level lists, not stored per shape.
  - `_wallAngles` holds radians, `atan2(dy, dx)` in y-down world coordinates.
  - `_wallDrawnLengths` holds lengths in u.
  - Both describe walls 0..n−2 of the active shape (closing wall excluded). They are used to rebuild the polygon after a real measurement.
- **Room object / opening**: a `RoomObject` of type `door`, `window` or `opening`. It is anchored to a wall of its shape by `wallIndex` and by `positionAlong` (0..1, the centre position along the wall).
- **Shared wall** has two different meanings:
  1. the derived topological `Wall` built by `buildWalls()` wherever walls of two closed rooms are almost collinear and overlap. The painter and the conflict checks use these;
  2. the `SharedWall` records that move mode stores on shapes. Nothing ever reads them.
- **Furniture item**: a `FurnitureItem` (from `furniture_item.dart`): a free-floating rotated rectangle.
  - Its centre is in u; width and depth are in mm.
  - It is stored in `SketchShape.furnitureItems`.

```text
 Entry points (constructor params)                       ┌────────────────────────────┐
 HomeScreen ─ BLE "Start Room Sketch" (bleManager)       │ ProjectListScreen (returns │
 HomeScreen ─ "My Projects" (initialLocalProjectId)  ───►│ local project id)          │
 ArResultScreen (initialShapes:[AR shape])               └────────────────────────────┘
 _LiveCollabWrapper (initialShapes, initialWallAngles,
   initialWallLengths, cloudProjectId, canEdit)
                 │
                 ▼
 ┌──────────────────────── SketchScreen / _SketchScreenState ─────────────────────────┐
 │  with SketchDialogsMixin (sketch_dialogs.dart: angle editor, wall edit sheet,      │
 │                           manual length dialog) + ObjectMeasurementDialog          │
 │  state: shapes, activeIndex, _wallAngles/_wallDrawnLengths, undo/redo stacks,      │
 │         selection + gesture flags, furniture/object drag state, cloud/presence     │
 │  Listener + GestureDetector ──► _onPointerDown/Move/Up/Hover/Signal,               │
 │                                 _onScaleStart/Update/End, _onTapDown→_commitTap    │
 │  CustomPaint(SketchPainter) ◄── shapes + flags; painter fills _labelHitRects,      │
 │                                 _roomLabelHitRects (tap targets)                   │
 │  overlays: top toolbar, polar HUD, angle strip, bottom toolbar (StatusItem),       │
 │            object panel (_ObjectPanelButton), furniture bar, 3D button             │
 │  geometry: wall_topology.dart (buildWalls, wallOverlapSegment)                     │
 │            wall_openings.dart (openingsForWall, findWallForObject, wouldConflict)  │
 │            room_object_utils.dart (findNearestWall, objectCentreWorld, …)          │
 │  model:    sketch_model.dart (SketchShape, SharedWall), room_object.dart,          │
 │            furniture_item.dart; constants/formatters: sketch_constants.dart        │
 └──────┬──────────────┬──────────────────┬─────────────┬────────────────────────────┘
        │              │                  │             │
  DatabaseHelper  SyncService /       BleManager    Room3DScreen · exportSketchPdf ·
  (SQLite save/   ApiService (upload   packetStream  DxfPreviewScreen ·
  load/delete)    queue, heartbeat,    (distanceMm)  furnitureRotationHandlePos
                  presence, invite)
```

Line counts in this part are editor line counts. Files without a trailing newline show one line more than `wc -l` reports; `sketch_screen.dart` is 4162 editor lines (4161 per `wc -l`).

---

### 5.2 Features and how they work

#### 5.2.1 Opening the editor (entry points and constructor)

`SketchScreen` (L29) has seven optional constructor parameters:

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `bleManager` | `BleManager?` | null | Connected BLE device. If present, wall editing offers "Use Device" and the screen listens to `packetStream`. `dispose()` disconnects it. |
| `initialShapes` | `List<SketchShape>?` | null | Rooms to show instead of one empty shape. Copied shallowly with `List.from`, so the shape objects are shared with the caller. |
| `initialWallAngles` | `List<double>?` | null | Preloads `_wallAngles` (radians). |
| `initialWallLengths` | `List<double>?` | null | Preloads `_wallDrawnLengths` (u). |
| `cloudProjectId` | `int?` | null | Cloud project id for a live collaboration session. Starts the heartbeat. |
| `initialLocalProjectId` | `int?` | null | SQLite project id, loaded after the first frame. |
| `canEdit` | `bool` | true | If false, `_queueAutoSync()` does nothing. It does not make the editor read-only. |

Callers (verified call sites):

| Caller | Call | Result |
|---|---|---|
| `home_screen.dart` L97–116, "Start Room Sketch" | Creates `BleManager()`, pushes `BleConnectionScreen`, and in `onConnected` calls `pushReplacement(SketchScreen(bleManager: bleManager))` | Empty project with one empty shape; BLE measuring available |
| `home_screen.dart` L131–146, "My Projects" | `ProjectListScreen` pops an `int` id, then `SketchScreen(initialLocalProjectId: projectId)` | Post-frame `_loadProjectById(id)`; no BLE |
| `ar_result_screen.dart` L95–134, `_importToSketch` | `pushAndRemoveUntil(SketchScreen(initialShapes: [shape]), route.isFirst)` | One closed shape: points converted from mm to u and centred on (200, 200) u, `label: 'AR Scan'`, `wallRealMm` filled for **all** n walls (closing wall included), `heightMm: 2400`; no BLE; chain empty until the first canvas pointer-up |
| `collaboration_screen.dart` L935–943, `_LiveCollabWrapper.build` | `SketchScreen(key: _sketchKey, bleManager: null, initialShapes, initialWallAngles, initialWallLengths, cloudProjectId, canEdit)` | Cloud project opened live. The wrapper polls every 10 s; on a remote change it replaces `_sketchKey` with a new `UniqueKey()`, which rebuilds a fresh `SketchScreen` and throws away all local editor state |

`initState` (L176) runs these steps in order:
1. If `initialShapes` is non-empty: copy it into `shapes`, set `activeIndex = 0`, and schedule `_fitShapesToView()` after the first frame.
2. If `cloudProjectId` is set: copy it into `_cloudProjectId` and schedule `_startHeartbeat()` after the first frame.
3. Preload the chain lists from `initialWallAngles` / `initialWallLengths`.
4. If `initialLocalProjectId` is set: schedule `_loadProjectById(id)` after the first frame.
5. Subscribe to `widget.bleManager?.packetStream` (see 5.2.8).
6. Subscribe to `SyncService.instance.statusStream`. Each event calls `setState` (if mounted) so the sync icon refreshes.
7. Subscribe to `SyncService.instance.uploadSuccessStream`. On each event it stores `event['cloud_project_id']` into `_cloudProjectId` and `event['updated_at']` into `_lastCloudUpdatedAt`, then calls `_startHeartbeat()`. It does **not** check `event['local_project_id']`.

None of the three subscriptions is stored or cancelled. `dispose` (L236) only cancels `_heartbeatTimer` and calls `widget.bleManager?.disconnect()`, so leaving the editor drops the BLE connection.

#### 5.2.2 Canvas coordinates, zoom and pan

- **Transform**:
  - `worldToScreen(w) = w * _scale + _panOffset` (L276);
  - `screenToWorld(s) = (s - _panOffset) / _scale` (L277).
  - `_scale` is pixels per world unit: default `0.35`, clamped to [`_minCanvasScale` 0.001, `_maxCanvasScale` 5.0]. At 0.35, 1 m (200 u) is 70 px. At 1.0 ("100 %"), 1 px is 5 mm.
  - `_panOffset` starts at `Offset.zero`.
- **Grid**:
  - minor grid `minorGrid` = 40 u = 200 mm (the toolbar badge text `'1div=200mm'` is hardcoded);
  - major grid `majorGrid` = 200 u = 1 m.
  - The painter draws both. The screen uses `minorGrid` for `snapToGrid` (L279): `round(x / 40) * 40` on each axis.
- **Two-finger pinch** (`_onScaleUpdate`, L2480): if `pointerCount >= 2` and no point, room or object drag is in progress:
  - `_scale = clamp(_scaleStart * d.scale)`;
  - `_panOffset = d.focalPoint - focalWorld * _scale`, so the world point under the fingers stays fixed.
  - It also sets `_isMultiTouch`, `_tapCancelled = true` and `_pendingTap = null`, which suppresses tap-to-add-point.
  - `_onScaleEnd` clears `_isMultiTouch` and `_tapCancelled` after 150 ms.
- **One-finger pan**: `_onScaleUpdate` sets `_panConfirmed` once the focal point has moved more than `panThreshold` (6 px) from `_panStartPosition`, which `_onPointerDown` records. After that it adds `d.focalPointDelta` to `_panOffset`.
  - Grabbing a furniture item, rotation handle or opening sets `_panStartPosition = null`, which blocks panning.
- **Mouse wheel** (`_onPointerSignal`, L2430): a `PointerScrollEvent` multiplies the scale by 0.92 (scroll down) or 1.08 (scroll up), zooming about `event.position`.
- **Zoom preset menu** in the top toolbar (`PopupMenuButton<double>`): values `0.001, 0.0025, 0.005, 0.01, 0.05, 0.2, 0.35, 1.0, 2.0, 5.0`.
  - Labels are `value*100` with 2 decimals when `value < 0.01`, otherwise 0 decimals ("0.10%", "1%", "35%", …).
  - Choosing one zooms about the centre of `MediaQuery.sizeOf(context)`.
- **Fit** (`_fitShapesToView`, L1862; called after initial/loaded shapes and by the `fit_screen` button):
  1. Bounding box of all points of all shapes. It returns early if there are no points or if both box dimensions are < 1 u.
  2. `scale = clamp(min((W − 120) / w, (H − 120) / h), 0.001, 5)`, using 60 px padding on each side.
  3. `pan = (W/2 − cx·scale, H/2 − cy·scale)`.
  - W and H are the size of the state's own `RenderBox`, i.e. the whole screen. The top bar (48 px plus status bar) and bottom bar (52 px) are not subtracted, so fitted content can sit under them.

#### 5.2.3 Drawing a room (open shape)

The trigger is a tap on the canvas while the active shape is open. The sequence is:

1. `Listener.onPointerDown` → `_onPointerDown` (L1938) resets per-gesture flags.
   - If a point is selected (`_activePointIndex >= 0`), it may start dragging that point or select another one. Otherwise, if the touch is within `lastPointGlowRadius` (28 px) of the last point, it sets `_isDraggingLastPoint = true`.
2. `GestureDetector.onTapDown` → `_onTapDown` (L2556) goes through these checks in order:
   1. dimension-label hit rects → wall edit dialog;
   2. room-label hit rects → rename dialog;
   3. move mode → ignore;
   4. `_dragOccurred` or `_objectDragOccurred` → swallow the tap and reset the flag;
   5. furniture rotation/drag guard;
   6. furniture placement mode (5.2.15);
   7. **tap inside a different closed shape → that shape becomes active** (`activeIndex = s`; `_activePointIndex`, `_selectedWallIndex` and `_cursorWorld` are reset);
   8. closed-shape handling (5.2.6, 5.2.13), or for an open shape:
      - if ≥3 points and the tap is within `pointSelectRadiusScreen` (22 px) of `points.first` → **close** (5.2.5);
      - `_findNearPoint` (excluding the last point; only when the shape has more than 1 point) → select that vertex;
      - if a vertex is already selected: deselect it if the tap is more than 22 px away, then return;
      - if the tap is near the last point → return (the last point is a drag handle, not an add target);
      - otherwise store `_pendingTap` and call `_commitTap` 80 ms later, unless `_tapCancelled` was set by a multi-touch gesture.
3. `_commitTap` (L2741):
   1. `raw = snapToGrid(screenToWorld(tap))`.
   2. `crossSnap = _findSnapPointAcrossShapes(tap)`: the first vertex of any **other closed** shape within `pointSnapRadiusScreen` (30 px).
   3. `pos = crossSnap ?? (points.isNotEmpty ? _computeAngle(points.last, raw) : raw)`. The first point is only grid-snapped.
   4. Reject the point if `(pos − last).distance < minPointDistance` (8 u = 40 mm).
   5. `_saveUndo()`, append `pos`, clear the angle/cursor state, then `_syncWallDefinitions()`.
   - Adding a point does **not** call `_queueAutoSync()`.
4. **Angle snap** (`_computeAngle`, L1036): if the distance from the last point to the raw point is < `minAngleDistance` (10 u = 50 mm), the angle state is cleared and the raw point is returned. Otherwise:
   - `θ = atan2(−dy, dx)` in degrees, normalised to [0, 360) (counter-clockwise from east on screen);
   - `_nearestSnapAngle` picks the nearest entry of `snapAngles` = {0, 30, 45, 60, 75, 90, 105, 120, 135, 150, 180, 210, 225, 240, 255, 270, 285, 300, 315, 330}, using circular difference;
   - if the difference is ≤ `snapThresholdDeg` (3°), the point is rotated onto that ray keeping its distance: `from + d·(cos θs, −sin θs)`, and `_isAngleSnapped = true`.
   - Grid snap is applied **before** angle snap, so an angle-snapped point is usually off the grid.
   - `_currentAngleDeg`, `_nearestSnapAngleDeg`, `_snapDiffDeg` and `_snappedAngle` are side effects that feed the painter and the HUD.
5. **Rubber band**:
   - `_onPointerMove` (finger) sets `_cursorWorld` to the result of the same pipeline: grid snap, then cross-shape vertex snap, then angle snap.
   - `_onPointerHover` (mouse) does the same but without the cross-shape vertex snap.
   - The rubber band follows the finger even during a one-finger pan.
   - The painter draws the line from the last point to `_cursorWorld`. The **polar tracking HUD** (L3573) shows:
     - ANGLE: `_currentAngleDeg`, 1 decimal;
     - LENGTH: `formatLength(distance last→cursor)`;
     - NEAREST/SNAPPED: `_nearestSnapAngleDeg`;
     - "delta": `_snapDiffDeg`, yellow when < 1.5°;
     - a lock icon when snapped.
   - The HUD sits 60 px from the bottom, or 86 px when the angle strip is visible.
6. **Dragging the last point** (started in `_onPointerDown` when the touch is within 28 px of it): `_onPointerMove` moves `points.last`.
   - If another vertex of the same shape is within 30 px, the last point snaps exactly onto it and `_snapTargetIndex` is set.
   - Otherwise the point is angle-snapped relative to the second-to-last point. There is no grid snap while dragging.
   - The toolbar shows `Drag | <angle>`.

What the user sees: thick walls with length labels and the rubber band, a live HUD, the top-bar hint "Tap next corner | Drag orange to adjust", and in the bottom bar MODE = DRAW and PTS = point count.

#### 5.2.4 Snapping and hit-test thresholds (summary)

| Rule | Value | Space | Where |
|---|---|---|---|
| Grid snap for new points and the cursor | 40 u (200 mm) | world | `snapToGrid` L279 |
| Angle snap tolerance | 3° to the nearest `snapAngles` entry | degrees (CCW) | `_computeAngle` L1036, `_trySnap` L1079 |
| Minimum distance before angles are computed | 10 u (50 mm) | world | `minAngleDistance` |
| Minimum new-point spacing | 8 u (40 mm) | world | `_commitTap` |
| Vertex select / tap-to-close on first point | 22 px | screen | `pointSelectRadiusScreen` |
| Vertex snap while dragging (same shape) and cross-shape vertex snap | 30 px | screen | `pointSnapRadiusScreen` |
| Last-point drag handle | 28 px | screen | `lastPointGlowRadius` |
| Wall hit (tap to edit length) | 18 px to segment | screen | `_findNearWall` L1168 |
| Object hit on pointer-down (start drag) | centre distance < half width (screen) + 16 px | screen | `_onPointerDown` L2010–2033 |
| Object hit on tap (open dialog) | < 14 px to the object's segment | screen | `_onTapDown` L2637–2670 |
| Object drop onto wall | 30 px; t clamped to [0.05, 0.95] | screen | `findNearestWall` |
| Furniture body hit | inside rotated rect + 10 px | screen | `_isInsideFurnitureItem` L1198 |
| Furniture rotation handle | < 50 px from the handle centre | screen | `_onPointerDown` L1977 |
| Pan start | 6 px | screen | `panThreshold` |
| Room-move vertex snap | 18 u (90 mm) | world | `wallSnapThresholdWorld` |
| Room-move wall snap | perpendicular offset ≤ 3 u (15 mm), abs(dot) ≥ 0.92 (about 23°), overlap ≥ 4 u | world | `wallOverlapSegment` defaults |
| Painter close-loop cue | 15 u (75 mm) | world | `snapRadiusWorld` (painter only) |

All "find" helpers (`_findNearPoint`, `_findNearWall`, `_findSnapPointAcrossShapes`, `_findWallSnapCandidate`, `_findVertexSnapCandidate`) return the **first** match within the threshold, not the nearest one.

#### 5.2.5 Closing and naming a room

- **By tap**: with ≥3 points, a tap within 22 px of `points.first` runs `_onTapDown` L2690–2709:
  1. `_saveUndo()`;
  2. `isClosed = true`; the angle and cursor state is reset and `_activePointIndex = -1`;
  3. `_syncWallDefinitions()`;
  4. `_showRoomNameDialog()`;
  5. `_queueAutoSync()`.
- **By drag**: release the dragged last point while it is snapped to vertex 0 (`_snapTargetIndex == 0`, ≥3 points). `_onPointerUp` L2384–2402 runs the same steps.
  - The dragged last point now **coincides with point 0 and is not removed**. The polygon therefore keeps a duplicate vertex and a zero-length closing wall (bug).
- **Naming** (`_showRoomNameDialog([int? shapeIndex])`, L242): a non-dismissible `AlertDialog` titled "Room Name".
  - It contains a `TextField` pre-filled with `shapes[idx].label`, hint "e.g. Bedroom, Kitchen...".
  - Buttons: "Skip" pops; "Save" sets `label = text.trim()`, pops and calls `_queueAutoSync()`.
  - `onSubmitted` (keyboard Done) **only pops without saving** (bug).
  - The dialog can be reopened at any time by tapping a room's name label, which the painter registers in `_roomLabelHitRects` for every closed room with ≥3 points.
  - Renaming does not set `_isDirty`.
  - The label is not persisted to SQLite or sent in the cloud payload (5.2.17, 5.2.19).

The user sees the filled room with its name and area label at the centroid. The right-hand object panel and the "3D View" button appear, MODE becomes DONE, and PERIM/AREA appear in the bottom bar.

#### 5.2.6 Selecting and dragging vertices

- **Closed shape**: `_onPointerDown` (L2035) selects the first vertex within 22 px and immediately sets `_isDraggingActivePoint = true`. A pointer-down that hits no vertex clears `_selectedObjectId`.
- **Open shape**: a vertex other than the last is selected by a tap (`_onTapDown` → `existingIdx`) and turns orange. The next pointer-down within 28 px of it starts the drag, while a pointer-down near another vertex (22 px) switches the selection.
- **Drag** (`_onPointerMove` L2173–2220):
  - `raw = screenToWorld(finger)`.
  - If another vertex of the same shape is within 30 px, the dragged vertex is placed exactly on it (`_snapTargetIndex`). No merge happens, so the result is a duplicate vertex.
  - Otherwise `_updateMiddlePointAngles(idx, raw)` (L1084) runs:
    1. prev = `points[idx−1]` (for a closed shape with idx 0: `points.last`); next = `points[idx+1]` (for a closed shape with the last idx: `points[0]`).
    2. For the previous wall (prev→raw) and the next wall (raw→next), each at least 10 u long, compute the CCW angle and `_trySnap` it (3°).
    3. If only the previous wall snaps: raw is rotated about prev onto the snapped ray, keeping its distance. If only the next wall snaps: raw is rotated about next onto the reverse ray.
    4. If **both** snap: the vertex goes to `_rayIntersection(prev, prevSnap, next, (nextSnap + 180) % 360)`, which is a line–line intersection:
       - `dA = (cos a, −sin a)`, `dB = (cos b, −sin b)`;
       - `det = dAx·(−dBy) − dAy·(−dBx)`; if `abs(det) < 1e-10` there is no intersection;
       - `t = (dx·(−dBy) − dy·(−dBx)) / det`;
       - the result is `P = prev + t·dA`.
       This keeps both adjacent walls at exact snap angles.
    - `_prevWallAngle`, `_nextWallAngle`, `_prevWallSnapped` and `_nextWallSnapped` are passed to the painter for the angle labels.
- **Release** (`_onPointerUp` L2404–2416): if a drag happened:
  1. `wallRealMm` is removed for wall idx−1 (if idx > 0) and for wall idx (if `idx < _wallAngles.length`). For a closed shape the closing wall n−1 is never cleared when dragging vertex 0 or n−1.
  2. `_saveUndo()` is called **after** the move, so this snapshot cannot undo the drag.
  3. `_syncWallDefinitions()` (called twice) and `_queueAutoSync()`.

#### 5.2.7 Editing the last wall's angle (angle strip and angle editor)

The angle strip appears above the bottom bar when `showAngleStrip` is true: `_currentAngleDeg != null`, no selected vertex, ≥2 points and an open shape.
- It shows a lock or rotate icon, "ANGLE" with `_angleLabel()` (the snapped angle with 0 decimals, else the current angle with 1 decimal), and an "EDIT" chip.
- Tapping it calls the mixin's `showSketchAngleEditor()` (sketch_dialogs.dart L31):
  - The text field is pre-filled with `_currentAngleDeg`. That is the last cursor/rubber-band angle, which is not necessarily the angle of the last placed wall.
  - Preset chips: 0, 30, 45, 60, 75, 90, 135, 180, 270.
  - APPLY: `ref = points[n−2]`, `L = |last − ref|`, then `sketchSaveUndo()` and `last = ref + L·(cos θ, −sin θ)`. It also sets `_currentAngleDeg = _snappedAngle = θ % 360`, `_isAngleSnapped = false` and `_cursorWorld = null`.
  - It neither re-syncs the chain nor calls autosync.

#### 5.2.8 Real wall lengths: manual entry, BLE, 3D view and the chain rebuild

**Trigger**: one of the following:
- a tap on a wall of the closed active shape (`_findNearWall`, 18 px);
- a tap on a wall dimension label (`_labelHitRects`, which the painter registers only for the active shape, in both open and closed states);
- a measurement made in the 3D view.

The first two set `_selectedWallIndex` and call the mixin's `showSketchWallEditDialog(wallIndex)` (L147):
- If `widget.bleManager != null && isConnected`, a bottom sheet opens with the header "Wall N — <formatLength(drawn)> drawn" and two buttons:
  - **"Use Device — press BOOT button on ESP32"**: sets `_selectedWallIndex = wallIndex` and `_waitingForBle = true` inside `setState`;
  - **"Enter manually"**: calls `showSketchManualEntryDialog(wallIndex)`.
- Otherwise the manual dialog opens directly.

**Manual dialog** (`showSketchManualEntryDialog`, L232):
- Title "Wall N", or "Wall N (closing)" when the shape is closed and `wallIndex == n − 1`. It shows the drawn length.
- The input is pre-filled with the existing `wallRealMm` value as an integer.
- `UnitSelector` (mm/m) converts the text when toggled.
- Preset chips: 1000, 1500, 2000, 2400, 3000, 4000, 5000 mm.
- CANCEL resets `_selectedWallIndex = -1`.
- "APPLY & RESCALE" parses the text and, if it is > 0, pops and calls `sketchApplyRealMeasurement(wallIndex, val)`. The value is **always treated as mm**, even when the selector shows "m" (bug, see 5.3).

**BLE path** (listener registered in `initState`, L203–217):
1. Packets with `isCapturing` (laser on) or `distanceMm <= 0` are ignored.
2. If `_waitingForBle && 0 <= _selectedWallIndex < _wallAngles.length`, the listener sets `_waitingForBle = false`, `_pendingBleMm = mm` (never read), `_selectedWallIndex = -1`, then calls `_applyRealMeasurement(wallIdx, packet.distanceMm)`.
3. There is no timeout and no cancel button. The hint text "Point device at wall → press BOOT button" can only appear once `_selectedWallIndex` has been reset to −1, and by then the listener ignores packets.
4. `distanceMm` is decoded from 2 big-endian bytes, so the maximum is 65 535 mm.

**3D path**: `Room3DScreen(onWallMeasured: (wallIndex, mm) => _applyRealMeasurement(wallIndex, mm))`.
- The 3D screen has already written `wallRealMm[wallIdx]` on **its** active room. That room can differ from the editor's `activeShape`, because the callback carries no room id.

**`_applyRealMeasurement(wallIndex, realMm)`** (L1846):
1. Return silently if `wallIndex >= _wallAngles.length`. Because the chain covers only walls 0..n−2, **the closing wall of a closed room can never be rescaled**. The manual dialog closes with no effect and BLE packets are ignored.
2. Return if the drawn wall length is < 1e-6.
3. `_saveUndo()`.
4. `activeShape.wallRealMm[wallIndex] = realMm`.
5. `_rebuildPointsFromChain()` (L1829): starting from the unchanged `points[0]`, for each i in `0 ≤ i < _wallAngles.length`:
   - `L_i = wallRealMm[i] / mmPerUnit` if present, else `_wallDrawnLengths[i]`;
   - `p_{i+1} = p_i + L_i·(cos α_i, sin α_i)`;
   - the point list is then replaced by these `_wallAngles.length + 1` points.
   - Effect: every vertex downstream of the measured wall is translated along that wall's direction. In a closed room the closing wall absorbs the change in both length and angle.
6. `_syncWallDefinitions()` (L1815): recomputes `_wallAngles[i] = atan2(dy, dx)` and `_wallDrawnLengths[i] = |p_{i+1} − p_i|` for i < n−1. From now on the drawn length equals the real length for measured walls.
7. Reset `_selectedWallIndex` and `_activePointIndex`, then `_queueAutoSync()`.

**Chain consistency (important):**
- `_wallAngles` and `_wallDrawnLengths` are screen-level, not per shape. They are re-synced by `_commitTap`, by closing, by `_applyRealMeasurement`, and by **every ordinary canvas pointer-up** (`_onPointerUp`, else-branch, L2411).
- Changing the active room (tap inside another room, `_addNewRoom`, a move-mode grab, `_loadProjectById`, `_undo`/`_redo`) does not re-sync them.
- For a quick tap, Flutter delivers the raw pointer-up to the `Listener` before the tap recognizer fires `onTapDown`. A room switch done in `_onTapDown` can therefore leave the chain of the *previous* room in place until the next canvas pointer-up.
- If `_applyRealMeasurement` runs in that window, for example via the 3D view's `onWallMeasured` right after switching rooms, `_rebuildPointsFromChain` rebuilds the active room from another room's angles and lengths. That corrupts its geometry and can change its point count (bug).

What the user sees: the wall label switches to the real value and the polygon snaps to the new length.

#### 5.2.9 Area, perimeter and the status bar

- `_totalPerimeter()` (L1900): sum of `|p_{i+1} − p_i|` over the active shape, plus the closing segment when closed. The result is in u; `formatLength` multiplies by 5.
- `_totalArea()` (L1916): shoelace formula `abs(Σ(x_i·y_j − x_j·y_i)) / 2` over the closed active shape with ≥3 points, in u². `formatArea` multiplies by 25 to get mm², then divides by 1e6 to get m².
- Both use **drawn** geometry. After measurements the measured walls match their real lengths; unmeasured walls and the closing wall stay as drawn.
- `formatLength` gives `"X.XX m"` at ≥ 1000 mm, else `"N mm"`. `formatArea` gives `"X.XX m²"` at ≥ 0.01 m², else `"N mm²"`.
- Bottom-bar `StatusItem`s:
  - MODE: closed → `EDIT` if a vertex is selected, else `DONE`; open → `DRAG` while dragging the last point, `EDIT` if a vertex is selected, else `DRAW`;
  - PTS: point count;
  - PERIM: closed with ≥2 points;
  - AREA: closed with ≥3 points;
  - PT: selected vertex number.
- Only the active room is measured. There is no total over all rooms here (the PDF has one).

#### 5.2.10 Multiple rooms

- **Add Room** (bottom bar, `_addNewRoom` L316): `_saveUndo()`, append `SketchShape.empty()`, make it active. It does not call autosync.
- **Switch room**: tap inside another closed room (`_onTapDown` L2611–2623; ray casting in screen space via `_pointInsidePolygon`, L1182).
  - Taps inside any *other closed* room always switch, even while an open room is being drawn. A new room's corner can never be placed inside an existing room, and the half-drawn open room is left behind as an open polyline.
  - Open rooms cannot be re-activated by tapping: `_pointInsidePolygon` is only tried for closed shapes.
- **Cross-room vertex snap**: a new corner placed within 30 px of a vertex of another closed room takes that vertex's exact world position (`_findSnapPointAcrossShapes`).
- **No delete-room function** exists. "Clear" (5.2.16) only empties the active room in place.
- The painter draws all rooms, but dimension labels and point handles only for the active room.

#### 5.2.11 Move mode (dragging rooms) and room-to-room snapping

The trigger is the `open_with` toggle in the bottom bar. It flips `_isMoveMode` (the icon turns green when on) and resets `_movingShapeIndex`, `_moveStartWorld` and `_activePointIndex`.

1. **Grab** (`_onPointerDown` L1947–1962): the first closed room containing the touch is grabbed.
   - `_saveUndo()` runs even if the room is not then moved, which sets `_isDirty`.
   - `_movingShapeIndex = activeIndex = s` and `_moveStartWorld = screenToWorld(touch)`.
   - Touches outside every room do nothing.
2. **Drag** (`_onPointerMove` L2139–2170):
   - Removes every `SharedWall` that links the moving room to others, on both sides.
   - Translates all of its `points` by the world delta.
   - **`furnitureItems` are not moved.** Furniture positions are absolute, so moving a room leaves its furniture behind (bug). Doors and windows move with the walls because they are wall-relative.
   - Computes `_findWallSnapCandidate(moving)` (L1757): the first pair of moving wall and other-room wall for which `wallOverlapSegment` is non-null. The painter highlights the other room's wall in green through `_snapCandidateShape` / `_snapCandidateWall`.
3. **Release** (`_onPointerUp` L2297–2381):
   1. **Wall snap**: if a candidate exists:
      - translate the room by `oMid − myMid`, the midpoints of the overlap on the other wall and on the moving wall. This removes the perpendicular gap of ≤ 3 u;
      - recompute the overlap;
      - replace older `SharedWall` entries for these wall indices;
      - append a `SharedWall` on **both** rooms, with `tStart`/`tEnd` from the screen's `_tAlong` (L1746), clamped to [0, 1].
   2. **Vertex snap**: `_findVertexSnapCandidate` (L1798) finds the first pair of vertices closer than 18 u (90 mm) and translates the room so they coincide exactly. This runs after the wall snap and can make the stored `SharedWall` t-values stale; nothing reads them anyway.
   3. Clear the snap highlight and `_movingShapeIndex`, then `_queueAutoSync()`.
   - The chain is not re-synced on this path.
   - Because the wall-snap perpendicular tolerance is only 3 u (15 mm, about 1 px at the default zoom), the forgiving 18 u vertex snap does most of the practical alignment.

The visible "shared wall" rendering does not come from `SharedWall`. The painter recomputes shared segments geometrically every frame with `buildWalls()` (5.2.12).

#### 5.2.12 Wall topology: detecting shared walls (`wall_topology.dart`)

`buildWalls(List<SketchShape> shapes)` (L93) produces a `List<Wall>` that covers every wall of every **closed** room exactly once. Open rooms produce nothing.

1. For every pair of closed rooms (si < sj) and every wall pair (ai, bi), call `wallOverlapSegment(mA, mB, oA, oB)` (L29) with defaults `perpThresh = 3.0` and `parallelThresh = 0.08`:
   - null if either wall is shorter than 1 u;
   - `dot = abs(mUnit·oUnit)` must be ≥ 0.92 (almost parallel, about ±23°);
   - the perpendicular offset of `oA` from the line of m, `abs((oA − mA) × mUnit)`, must be ≤ 3 u. Only `oA` is checked, not `oB`;
   - project `oA` and `oB` onto m (`tOA`, `tOB` in u from `mA`), clamp to [0, mLen], and require an overlap of ≥ 4 u (20 mm);
   - return `start`/`end` on m, and `oStart`/`oEnd` as the projections of those points onto o (clamped to o).
   - `oUnitSigned`/`oBase` test `dot > 0`, but `dot` is already an absolute value, so that branch is dead. It is harmless because the projections are clamped.
2. For each overlap, add a shared `Wall`:
   - `id = 'w_${A.id}_${ai}_${B.id}_$bi'`, endpoints = the overlap on A;
   - `sources = [WallSource(A.id, ai, tA0, tA1), WallSource(B.id, bi, tB0, tB1)]`, where the t values come from `_tAlong` (L71), unclamped, on each wall's own direction. `tB0 > tB1` when B runs the opposite way;
   - record the covered t ranges per (shapeId, wallIndex).
3. For every closed room and wall i, `_subtractRanges` (L78) takes the complement in [0, 1] of the union of covered ranges. Each free range of length ≥ 0.01 becomes a single-source `Wall` with `id = 'w_${shape.id}_${i}_${start.toStringAsFixed(3)}'`.

Cost is O(S²·N²). It is recomputed on every paint (by the painter) and on every object tap or drop. Three rooms sharing the same stretch yield overlapping duplicate shared walls (A–B, A–C, B–C).

#### 5.2.13 Doors, windows and openings

- **Placement** (only when the active room is closed): drag the "Door", "Window" or "Opening" button from the right-hand panel (`_ObjectPanelButton`, a `Draggable<String>`).
  1. `onDragStarted` sets `_draggingObjectType`.
  2. `onDragEnd(details)` calls the build-local `_onObjectDropped(details.offset)` (L2967). `details.offset` is the global **top-left** of the 52×52 feedback widget, not the finger position, so the drop point is offset by the finger's position within the button.
  3. `findNearestWall(screenPos, points, isClosed, worldToScreen, screenToWorld)` searches with a 30 px threshold and t clamped to [0.05, 0.95]. With no hit, the drag is cancelled silently.
  4. Defaults: a window is 1200 mm wide, 1200 mm high, 900 mm elevation; a door or opening is 900 mm wide, 2100 mm high, 0 elevation. The width is reduced to `min(default, 0.8 × wallLenMm)`. Then `positionAlong = clamp(hit.t, h, 1 − h)` with `h = (widthMm/5) / (2·wallLen)`.
  5. The candidate is `RoomObject(id: 'obj_${++_objectCounter}', ownerShapeId: activeShape.id, …)`. If `wouldConflict(candidate, activeShape, shapes, buildWalls(shapes))` is true, a red snackbar says "This spot already has a door, window, or opening on the other side of this shared wall." and the object is not added. Otherwise: `_saveUndo()`, add the object, `_queueAutoSync()`.
- **Selection and drag** (`_onPointerDown` L2010–2033): a touch within (half the on-screen width + 16 px) of an object's centre sets `_selectedObjectId`, `_isDraggingObject` and `_objectDragOccurred = false`.
  - `_onPointerMove` (L2111–2135) projects the finger onto the wall line: `t = ((touch − a)·(b − a)) / |b − a|²`, then `clamp(t, h, 1 − h)`. If the object is wider than the wall, `h > 0.5` and `clamp` throws an `ArgumentError`.
  - On release, `_saveUndo()` runs only if the object moved (after the move), followed by autosync.
- **Tap → dialog** (`_onTapDown` L2637–2670): the object's segment is rebuilt in screen space (centre via `objectCentreWorld`, direction via `wallDirectionScreen`, width clamped to [50 u, 0.98·wallLen]). A tap within 14 px selects it and calls `_onObjectTapped(id)` (L2771):
  1. `buildWalls(shapes)`, then `findWallForObject(obj, activeShape, walls)`, then `openingsForWall(wall, shapes)`. If `hasConflict`, the conflict dialog opens instead (5.2.14).
  2. Otherwise `ObjectMeasurementDialog` opens with `roomObject`, `wallLengthMm` = drawn length × 5, and three callbacks:
     - `onFlip` (doors only): `_saveUndo()` and toggle `swingFlipped`;
     - `onSave`: replace the object with the dialog's `copyWith(widthMm, heightMm, elevationMm)`, then `_queueAutoSync()`. There is **no** `_saveUndo()` and no `_isDirty`, and no check against the wall length;
     - `onDelete`: `_saveUndo()`, remove the object, clear the selection, autosync.
- **Pinch resize** (object selected and ≥2 pointers at scale start): width = `clamp(startWidth × d.scale, 200, 0.95 × wallLenMm)`. This throws if the wall is shorter than about 210 mm. `_onScaleEnd` then calls `_saveUndo()` (post-change) and autosync.
- Objects keep their relative `positionAlong` when walls change length. They are never re-clamped, so after shrinking a wall an object can be wider than its wall.

#### 5.2.14 Opening conflicts on shared walls (`wall_openings.dart`)

`openingsForWall(wall, shapes)` (L20):
- For each source of the wall, collect that shape's `roomObjects` on `src.wallIndex` whose `positionAlong` lies inside the source's t range (±1e-6).
- Convert each to a wall-local `localT = clamp((pos − tStart)/(tEnd − tStart), 0, 1)`. This maps to 0 at `wall.a` and 1 at `wall.b` for both sources.
- Two openings from **different** `ownerShapeId`s conflict if their intervals `localT ± (widthMm/5/2)/wallLen` overlap, where `wallLen` is the length of the shared segment.

`wouldConflict(candidate, owner, shapes, walls)` (L85) runs the same test for a not-yet-added object against openings whose `ownerShapeId != owner.id`, and only when its wall is shared. Only the object's centre decides which wall segment it belongs to; an object straddling the end of a shared stretch is tested only against the segment its centre falls on.

`_showConflictDialog(wall, resolved)` (L2819):
- Title "Conflicting openings".
- One button per resolved opening on that wall: "Keep door/opening/window (this room|other room)".
- Choosing one removes **every other** opening on that wall segment, including non-conflicting ones from the same room. Each removal is a separate `_saveUndo()` and autosync.
- Removal looks up the owner by `shape.id == ownerShapeId`. After any undo or redo, shape ids are regenerated and no longer match `ownerShapeId`, so the removal silently does nothing (bug).

#### 5.2.15 Furniture

1. **Library**: the "Furn." tile in the right panel calls `_showFurnitureLibrary()` (L2874).
   - It is a bottom sheet with a `DraggableScrollableSheet` (initial 0.60, min 0.35, max 0.90) and a 4-column grid of every `FurnitureType.values` entry (31 types; icon, colour and `displayName` come from `furniture_item.dart`).
   - Tapping a type sets `_furniturePlacingType`. The top bar shows "Tap inside room to place X" and a strip at bottom 52 offers CANCEL.
2. **Place** (`_onTapDown` L2589–2608): a tap inside the closed active room adds `FurnitureItem(id: 'fur_${++_furnitureCounter}', type, position: screenToWorld(tap))` with the type's default size, after `_saveUndo()`, then autosync. A tap anywhere else cancels placement. No wall snapping is applied: `_snapFurnitureToWall` (L1213) exists but is never called.
3. **Select**: a tap inside an item, rotated rectangle + 10 px (`_isInsideFurnitureItem`), sets `_selectedFurnitureId`. The painter draws the selection and the rotation handle. A tap on empty space clears the selection.
4. **Move**: a pointer-down inside the *selected* item followed by a drag adds the world delta to `position` (free, no constraints). On release, `_saveUndo()` runs only if it moved (post-change), then autosync.
5. **Rotate**: a pointer-down within 50 px of `furnitureRotationHandlePos(item, worldToScreen, scale)`, which is `centre − (0, max(w, d)/5·scale/2 + 52)`, starts a rotation.
   - `rotationDeg = (startDeg + Δatan2·180/π) % 360` (clockwise-positive in y-down coordinates).
   - Release: `_saveUndo()` always (post-change), then autosync.
6. **Pinch**: with an item selected and ≥2 pointers, both width and depth become `clamp(start × d.scale, 100, 6000)` mm. `_onScaleEnd` saves undo and autosyncs. The canvas cannot be pinch-zoomed while furniture is selected.
7. **Action bar** (bottom 52, while an item is selected):
   - a size readout "W: Xcm × D: Ycm" (tap opens the size dialog);
   - rotate −45° and +45° (`_saveUndo()`, no autosync);
   - Edit size → `_showFurnitureSizeDialog`;
   - Position → `_showFurniturePositionDialog`;
   - Delete (`_saveUndo`, remove, autosync);
   - "Done" (deselect).
8. **Size dialog** (L1383):
   - Width and Depth fields in cm (`mm/10`, 0 decimals) and the tip "pinch-zoom with 2 fingers to resize".
   - Cancel / Reset (back to `type.defaultSizeMm`) / Apply (both values > 0, `×10`, clamped to [100, 6000] mm).
   - The chosen action is stored in `pendingAction` and run after the dialog's future completes. The controllers are disposed 500 ms later so the IME does not crash during the close animation.
9. **Position dialog** (L1492, closed room with ≥3 points only):
   - A `StatefulBuilder` with radio "From wall" / "From corner".
   - **From wall**: dropdown "Wall i+1", distance field in cm. Initial value `_wallEdgeGapMm(item, 0)/10`.
   - **From corner**: dropdown "Corner i+1 (W{prev} ↔ W{i})" and direction radio "→ Wall i+1" (along the wall after the corner) or "← Wall prev" (along the wall before it).
   - Changing a selection refreshes the field with the current gap. Apply (value ≥ 0) runs one of:
     - `_applyWallDist(itemIdx, wallIdx, distMm)` (L1290): keeps the projection t along the wall and sets the perpendicular offset to `sign·(halfExtent(normal) + dist/5)` on the same side;
     - `_applyCornerDistAfter` (L1341): `newT = halfExtent(wallDir) + dist/5` from corner P along P→Q, keeping the perpendicular offset;
     - `_applyCornerDistBefore` (L1362): `newT = wallLen − halfExtent − dist/5` along prevP→P.
   - Gap read-outs: `_wallEdgeGapMm` (L1273) = `(abs(signedDist) − halfExtent)·5`, clamped to [0, 99999]; `_cornerGapAfterMm` (L1312) and `_cornerGapBeforeMm` (L1326) work analogously along the wall.
   - `_furnitureHalfExtent(item, dir)` (L1264) is the support function of the rotated rectangle: `abs(hw·(cos r·dx + sin r·dy)) + abs(hd·(−sin r·dx + cos r·dy))`.
   - Distances are to the infinite wall *line*, not the segment.

Furniture is drawn only for closed rooms (painter). It is stored per room in `furnitureItems`, persisted to SQLite and the cloud, and shown in the 3D view.

#### 5.2.16 Undo, redo and clear

- **Snapshot** (`_saveUndo`, L851): sets `_isDirty = true` and pushes:
  - one copy of each room's `points`;
  - `isClosed` flags;
  - a shallow copy of each `roomObjects` list (`RoomObject`s are always replaced through `copyWith`, never mutated in place, so this is safe);
  - copies of each `wallRealMm`;
  - `activeIndex`;
  - `_wallAngles` and `_wallDrawnLengths`;
  - deep copies of furniture (`copyWith()`) — **pushed twice** (L862 and L872, bug).
  It then clears all redo stacks. The stacks have no size limit.
- **Undo** (`_undo`, L877):
  1. Push the current state to the redo stacks, including furniture.
  2. Pop one entry from every undo stack.
  3. **Rebuild `shapes` with `SketchShape.empty()`** for each snapshot, copying points, closed flag, objects, `wallRealMm` and furniture.
     - Labels are lost, `heightMm` resets to 2400, `sharedWalls` are dropped, and the room ids are regenerated, so `RoomObject.ownerShapeId` no longer matches (bugs).
  4. Restore `activeIndex` and the chain lists, clear the selection and angle state, then `_queueAutoSync()`.
- **Redo** (`_redo`, L934): the mirror of undo, but it **does not push the furniture snapshot** to the undo stack. Combined with the double push, the furniture history gets out of step with the geometry after the first undo (bug).
- Snapshots taken *after* the change (furniture drag/rotate/pinch, object drag/pinch, vertex drag, 3D height change) mean those operations cannot be undone separately: the first undo restores the same state.
- The Undo and Redo buttons are enabled when `_undoAllPointsStack` or `_redoAllPointsStack` is non-empty. Undo history is **not cleared** when a project is loaded, so undo can bring back the previous project's rooms.
- **Clear** (`_clear`, L986; trash button, enabled when the active room has points):
  - `_saveUndo()`, then empty the active room's points, `isClosed`, `roomObjects` and `wallRealMm`, the chain lists, and all gesture/angle/selection flags; then autosync.
  - `furnitureItems` and `label` are kept. The furniture becomes invisible because the painter only draws furniture for closed rooms, but it is still saved, exported and synced.

#### 5.2.17 Local save and load (SQLite via `DatabaseHelper`)

- **Save** (bottom bar, enabled when the active room has points): `_saveProject()` (L468).
  1. Dialog "Save Project", name field pre-filled with `'Room Project'`. Cancel or an empty name aborts.
  2. `DatabaseHelper.instance.saveProject(name, shapes, roomObjects: activeShape.roomObjects, wallAngles: _wallAngles, wallDrawnLengths: _wallDrawnLengths)`. This **always INSERTs a new project**; the helper ignores its `roomObjects` argument and reads each shape's own objects and furniture.
  3. Set `_localProjectId`, `_localProjectName`, `_isDirty = false`, then show the snackbar "Project saved successfully". Errors show "Save failed: $e".
  - Saving again creates another row. `DatabaseHelper.updateProject` exists but is never called.
- **What is written to SQLite**:
  - tables `projects`, `shapes`(`is_closed`), `shape_points`(x, y in u), `wall_real_mm`, `wall_angles`, `wall_lengths`, `room_objects` (including `swing_flipped`) and `furniture_items`;
  - the screen-level chain is written **under every shape**, even though it belongs only to the active room;
  - `label` and `heightMm` have no column and are **not saved**.
- **Load** (folder icon) `_loadProject()` (L750) pushes `ProjectListScreen`, which pops an `int` id, and calls `_loadProjectById(id)` (L760).
  1. `DatabaseHelper.instance.loadProject(id)` returns a map (shape in 5.4).
  2. `shapes` is cleared and, for each shape row, a `SketchShape.empty()` (new id) is filled with:
     - `is_closed == 1`;
     - points `Offset(r['x'] as double, r['y'] as double)`;
     - `wallRealMm` entries.
  3. Furniture rows go to `shapes[shape_index]` (an unknown type falls back to `FurnitureType.sofa`).
  4. The chain is taken from the **first** shape's `wall_angles`/`wall_lengths` rows.
  5. Room-object rows go to `shapes[shape_index ?? 0]` with `ownerShapeId` = the new shape id; type `'door'`, `'opening'`, or otherwise window; `swing_flipped == 1`.
  6. `activeIndex = 0`; `_localProjectId`, `_localProjectName` (`project['name']`) and `_isDirty = false` are set, then `_fitShapesToView()` runs after the next frame.
  - `_cloudProjectId`, the heartbeat and the undo stacks are **not** reset (see 5.5).
  - The object and furniture counters are not advanced past loaded ids, so new items can reuse `'obj_1'`/`'fur_1'` (bug).

#### 5.2.18 Leaving the editor (back handling)

`PopScope(canPop: false, onPopInvokedWithResult: …)` sends the system back gesture, and the toolbar `arrow_back` button, to `_handleBackPressed()` (L324):
- **Not dirty** → pop. An AR-imported or collaborative sketch that was never edited is left without any prompt.
- **Dirty and a local project exists** → dialog "Save Changes" with a project-name field (initial `_localProjectName`) and Cancel / Discard / Save.
  - Save calls `saveProject` with the name (empty becomes `'My Project'`). This is a new row. Then it **deletes the old project** (`deleteProject(oldId)`, errors ignored), updates the id and name, clears dirty and pops.
  - `deleteProject` also deletes the old id's `pending_uploads` rows, so queued offline sync jobs for this project are dropped.
  - If the user types "cancel" or "discard" as the project name, it is treated as that button.
- **Dirty, never saved, and some room has ≥2 points** → dialog "Unsaved Project" ("Save this project locally before leaving?") with Cancel / Discard / Save Locally. Save Locally calls `_saveProject()` and pops only if `_isDirty` was cleared. If no room has ≥2 points it pops directly.

`_isDirty` is set only by `_saveUndo()`. Room renames and object dimension edits do not mark the project dirty.

#### 5.2.19 Cloud autosync and manual backup

- **Autosync** (`_queueAutoSync`, L612) is called after most committed edits: close, rename, real length, vertex/object/furniture drag ends, move-mode release, undo/redo/clear, object add/flip/save/delete, furniture add/delete/size/position, pinch end.
  - It is **not** called after adding a point, Add Room, the rotate ±45° buttons, the angle editor or a 3D height change.
  - Steps:
    1. Return if `!widget.canEdit`, if `!await ApiService.isLoggedIn()`, or if no local id exists and every room is empty.
    2. If there is no local id, `saveProject(name: 'Auto Save', …)` creates one.
    3. Build `_buildProjectPayload(activeShape.label or 'Room Project')`. The **active room's label becomes the cloud project name**.
    4. `SyncService.instance.queueUpload(projectId: _localProjectId!, projectData: payload, lastModifiedAt: _lastCloudUpdatedAt)`.
  - The local SQLite copy is **not** updated by autosync, so local and cloud versions drift apart until the user saves.
- **Backup to Cloud** (cloud_upload button, enabled when the active room has points): `_backupToCloud()` (L645).
  1. If not logged in: orange snackbar "Please login first to backup to cloud".
  2. Dialog "Cloud Backup Name" (default `'Room Project'`).
  3. If there is no local id, save one (`_localProjectName` is not updated).
  4. Snackbar "Uploading to cloud...", then `queueUpload(_buildProjectPayload(chosenName))`, then "Queued for sync — will upload automatically", or "Backup failed: $e".
  - It ignores `canEdit`.
- **Payload** (`_buildProjectPayload`, L537): the JSON shape is in 5.4.
  - Per shape, `wall_angles`/`wall_lengths` are recomputed from that shape's own points (n−1 entries, radians), unlike the SQLite path.
  - It sends neither `label` nor `heightMm` nor `swing_flipped`.
  - `SyncService` adds `last_modified_at`; the backend uses it for conflict detection.
- **After upload**: `uploadSuccessStream` sets `_cloudProjectId` and `_lastCloudUpdatedAt` and starts the heartbeat (5.2.1).

#### 5.2.20 Collaboration: heartbeat, presence, invite code and sync icon

- `_startHeartbeat()` (L4018) runs once per state:
  - an immediate `_sendHeartbeat()`, then `Timer.periodic(30 s)`;
  - `_sendHeartbeat()` (L4026) calls `ApiService.sendHeartbeat(cloudId)` (POST `/sync/heartbeat`) and `ApiService.getActiveCollaborators(cloudId)` (GET `/sync/active-collaborators/:id`), then stores the result in `_activeCollaborators`.
- `_buildPresenceAvatars()` (L4039) shows up to 4 `CircleAvatar`s (radius 10):
  - the letter is the first character of `email` in upper case, and the tooltip is the email;
  - the colour comes from a 5-colour palette indexed by `email.hashCode.abs() % 5` (`_avatarColor`, L4070). `String.hashCode` is not guaranteed stable across runs.
- **Share** (shown only when `_cloudProjectId != null`): `_showInviteCodeDialog()` (L3959).
  - `ApiService.getInviteCode(id)` (GET `/projects/:id/invite-code`).
  - The dialog "Share Project" shows the code in large monospace with letter-spacing 6. On failure a red snackbar says "Could not fetch invite code".
- **Sync icon** (`_buildSyncIcon`, L4081) reflects the global `SyncService.instance.status`:

  | Status | Icon |
  |---|---|
  | `syncing` | 16 px spinner |
  | `offline` | orange `cloud_off` |
  | `conflict` | red `warning_amber` |
  | `idle` | green `cloud_done` (also shown when the user never synced or is not logged in) |

- The editor does **not** poll for remote changes itself. Polling and re-creation are done by `_LiveCollabWrapper` (Part on collaboration).

#### 5.2.21 Exports and 3D view (interfaces)

- **PDF** (picture_as_pdf button, enabled when the active room has ≥2 points): `exportSketchPdf(context: context, shapes: shapes, projectName: _localProjectName)`. The name may be `''`. The function builds the PDF itself and hands it to `Printing.layoutPdf` (the system print/preview sheet), or shows "Draw a room first" when no room has ≥2 points. Nothing is returned.
- **DXF** (architecture button, always enabled): `Navigator.push(DxfPreviewScreen(shapes: shapes, projectName: _localProjectName.isNotEmpty ? _localProjectName : 'SmartMeasure_Room'))`.
- **3D View** (purple button at right 8 / bottom 62; shown when the active room is closed with ≥3 points and no furniture is selected or being placed):
  - `Navigator.push(Room3DScreen(shapes: shapes /* live list, by reference */, initialActiveShapeIndex: activeIndex, bleManager: widget.bleManager, onWallMeasured: (i, mm) => _applyRealMeasurement(i, mm), onHeightChanged: (mm) { setState(() => activeShape.heightMm = mm); _saveUndo(); }))`.
  - The 3D screen mutates the shared `SketchShape` objects directly, including `wallRealMm`.
  - The two callbacks carry no room id, so they always act on the editor's `activeShape`.
  - `heightMm` is neither in the undo snapshot nor persisted.
- **Painter**: `CustomPaint(painter: SketchPainter(…32 named arguments…))`, listed in 5.4.
  - The screen clears `_labelHitRects` and `_roomLabelHitRects` in `build()`; the painter appends tap rectangles during `paint`; `_onTapDown` reads them.
  - `shouldRepaint` always returns true.

#### 5.2.22 Mode and gesture matrix

| Mode (condition) | Tap | Drag (1 finger) | Pinch (2 fingers) | Other |
|---|---|---|---|---|
| Drawing (active room open) | Add point (grid, angle and cross-room vertex snap, 80 ms deferral); tap first point with ≥3 points → close; tap a vertex → select; tap a dimension label → wall dialog; tap inside another closed room → switch | Last point (from 28 px) → move with angle/vertex snap, release on point 0 → close; selected vertex → move with dual angle snap; elsewhere → pan (6 px) plus rubber band | Zoom about the focal point | Mouse hover → rubber band; wheel → zoom; angle strip → angle editor |
| Edit (active room closed, nothing selected) | Wall (18 px) or label → wall length dialog/BLE sheet; vertex → select; object (14 px) → object or conflict dialog; furniture → select; room name → rename; inside another room → switch | Vertex (22 px) → move (clears adjacent real lengths on release); object → slide along the wall; elsewhere → pan | Zoom | Drag Door/Window/Opening from the panel onto a wall; Furn. → library; 3D View |
| Object selected | Same as Edit | Slide along the wall | Resize width [200 mm, 95 % of the wall] | — |
| Furniture placing | Inside room → place; outside → cancel | Pan | Zoom | CANCEL strip |
| Furniture selected | Inside another item → select it; empty → deselect | Inside item → move; handle (50 px) → rotate; elsewhere → pan | Resize width and depth [100, 6000] mm | Action bar (rotate ±45°, size, position, delete, Done) |
| Move mode (`_isMoveMode`) | Labels still open dialogs; other taps ignored | Inside a closed room → translate it (furniture stays); release → wall snap (≤3 u) then vertex snap (18 u) | Zoom | Toggle via the `open_with` button |

---

### 5.3 File reference

#### `code/lib/sketch/sketch_screen.dart` — 4162 lines

- **Purpose:** The sketch editor screen. It owns all project state (rooms, chain, undo history, selection), interprets every gesture, runs the geometry for drawing, measuring, openings, furniture and room moves, and drives persistence, sync, collaboration presence, export and the 3D view.
- **Depends on:**
  - `flutter/material.dart` (UI); `flutter/gestures.dart` (pointer event types such as `PointerScrollEvent`); `dart:async` (`Timer`); `dart:math`.
  - `../ble/ble_manager.dart` (`BleManager`: `packetStream`, `isConnected`, `disconnect()`) and `../ble/ble_packet.dart` (`BlePacket.distanceMm`, `.isCapturing`).
  - `sketch_constants.dart` (constants, formatters); `sketch_model.dart` (`SketchShape`, `SharedWall`); `furniture_item.dart` (`FurnitureItem`, `FurnitureType` and its extension); `sketch_painter.dart` (`SketchPainter`); `sketch_dialogs.dart` (`SketchDialogsMixin`, `ObjectMeasurementDialog`); `sketch_widgets.dart` (`StatusItem`).
  - `sketch_pdf_export.dart` (`exportSketchPdf`); `../screens/dxf_preview_screen.dart` (`DxfPreviewScreen`); `room_3d_screen.dart` (`Room3DScreen`); `furniture_painter.dart` (`furnitureRotationHandlePos`).
  - `room_object.dart`; `room_object_utils.dart` (`findNearestWall`, `objectCentreWorld`, `wallDirectionScreen`, `WallHitResult`); `wall_topology.dart` (`buildWalls`, `wallOverlapSegment`, `Wall`); `wall_openings.dart` (`openingsForWall`, `findWallForObject`, `wouldConflict`, `WallOpenings`).
  - `../database/database_helper.dart` (`saveProject`/`loadProject`/`deleteProject`); `../database/project_list_screen.dart`; `../services/api_service.dart` (`isLoggedIn`, `getInviteCode`, `sendHeartbeat`, `getActiveCollaborators`); `../services/sync_service.dart` (`SyncService`, `SyncStatus`).
- **Declarations:**

  **`class SketchScreen extends StatefulWidget` (L29)**: fields `bleManager`, `initialShapes`, `initialWallAngles`, `initialWallLengths`, `cloudProjectId`, `initialLocalProjectId`, `canEdit` (see 5.2.1); const constructor (L38); `createState()` returns `_SketchScreenState`.

  **`class _SketchScreenState extends State<SketchScreen> with SketchDialogsMixin<SketchScreen>` (L53)**: fields (L57–152):

  | Field | Type, initial value | Meaning |
  |---|---|---|
  | `_localProjectId` | `int?` null | SQLite id of the open project (set by save, load or autosave) |
  | `_localProjectName` | `String` `''` | Used for PDF/DXF names and the back dialog |
  | `_isDirty` | `bool` false | Set by `_saveUndo`; cleared by a successful save or load |
  | `_panOffset` | `Offset.zero` | Screen position of the world origin |
  | `_scale`, `_scaleStart` | `double` 0.35 | px per u; scale at pinch start |
  | `_minCanvasScale`, `_maxCanvasScale` | static const 0.001 / 5.0 | Zoom limits |
  | `shapes` | `List<SketchShape>` `[SketchShape.empty()]` | All rooms (public name) |
  | `activeIndex` | `int` 0 | Index of the active room |
  | `_cursorWorld` | `Offset?` | Rubber-band end point (u) |
  | `_isDraggingLastPoint`, `_dragOccurred`, `_isMultiTouch` | `bool` | Gesture flags |
  | `_activePointIndex` | `int` −1 | Selected vertex |
  | `_isDraggingActivePoint` | `bool` | Selected vertex being dragged |
  | `_snapTargetIndex` | `int?` | Vertex the dragged point snapped onto (0 means close) |
  | `_undoAllPointsStack`, `_undoAllClosedStack`, `_undoAllObjectsStack`, `_undoAllRealMmStack`, `_undoActiveIndexStack` | `List<List<List<Offset>>>`, `List<List<bool>>`, `List<List<List<RoomObject>>>`, `List<List<Map<int,double>>>`, `List<int>` | Undo snapshots (parallel stacks) |
  | `_redoAll…` (same five) | same types | Redo snapshots |
  | `_pendingTap`, `_tapCancelled` | `TapDownDetails?`, `bool` | 80 ms deferred tap and its cancel flag |
  | `_snappedAngle`, `_isAngleSnapped`, `_currentAngleDeg` | `double?`, `bool`, `double?` | Angle state (degrees CCW) |
  | `_prevWallAngle`, `_nextWallAngle`, `_prevWallSnapped`, `_nextWallSnapped` | `double?`, `bool` | Vertex-drag angle feedback |
  | `_panStartPosition`, `_panConfirmed` | `Offset?`, `bool` | One-finger pan detection |
  | `_nearestSnapAngleDeg`, `_snapDiffDeg` | `double?` | HUD values |
  | `_selectedWallIndex` | `int` −1 | Wall being edited |
  | `_labelHitRects` | `List<({Rect rect, int wallIndex, int shapeIndex})>` | Dimension-label tap targets (filled by the painter) |
  | `_roomLabelHitRects` | `List<({Rect rect, int shapeIndex})>` | Room-name tap targets (filled by the painter) |
  | `_pendingBleMm` | `double?` | Written by the BLE listener, never read (dead) |
  | `_waitingForBle` | `bool` | Waiting for a BLE reading for `_selectedWallIndex` |
  | `_lastCloudUpdatedAt` | `String?` | Server `updated_at`, sent as `last_modified_at` |
  | `_cloudProjectId` | `int?` | Linked cloud project |
  | `_heartbeatTimer` | `Timer?` | 30 s presence timer |
  | `_activeCollaborators` | `List<Map<String,dynamic>>` | Presence list (uses `email`) |
  | `_draggingObjectType` | `RoomObjectType?` | Type being dragged from the panel |
  | `_selectedObjectId` | `String?` | Selected opening |
  | `_dragObjectScreenPos`, `_dragWallHit` | `Offset?`, `WallHitResult?` | Only ever set to null (dead) |
  | `_objectCounter` | `int` 0 | Suffix for `'obj_N'` ids |
  | `_furniturePlacingType` | `FurnitureType?` | Placement mode |
  | `_selectedFurnitureId` | `String?` | Selected furniture item |
  | `_isDraggingFurniture`, `_furnitureDragStartWorld`, `_furnitureDragOccurred` | `bool`, `Offset?`, `bool` | Furniture drag state |
  | `_isRotatingFurniture`, `_furnitureRotationStartAngle` (rad), `_furnitureRotationStartDeg` | `bool`, `double`, `double` | Rotation-handle state |
  | `_furniturePinchStartWidthMm`, `_furniturePinchStartDepthMm` | `double` 0 | Pinch-resize baseline (> 0 means a pinch is active) |
  | `_furnitureCounter` | `int` 0 | Suffix for `'fur_N'` ids |
  | `_undoAllFurnitureStack`, `_redoAllFurnitureStack` | `List<List<List<FurnitureItem>>>` | Furniture history |
  | `_wallAngles`, `_wallDrawnLengths` | `List<double>` | Wall chain of the active room (radians, u) |
  | `_undoWallAnglesStack`, `_undoWallLengthsStack`, `_redoWallAnglesStack`, `_redoWallLengthsStack` | `List<List<double>>` | Chain history |
  | `_movingObjectId`, `_moveStartScreenPos`, `_objectMoveOccurred` | `String?`, `Offset?`, `bool` | Never used (dead) |
  | `_isDraggingObject`, `_objectDragOccurred` | `bool` | Opening drag state |
  | `_objectPinchStartScale` | `double` 1.0 | Written, never read (dead) |
  | `_objectPinchStartWidthMm` | `double` 0 | Opening pinch baseline |
  | `_isMoveMode`, `_movingShapeIndex` (−1), `_moveStartWorld` | `bool`, `int`, `Offset?` | Move mode |
  | `_snapCandidateShape`, `_snapCandidateWall` | `int` −1 | Wall highlighted during a move |

  Getter `SketchShape get activeShape => shapes[activeIndex]` (L108).

  **Mixin contract (L155–172)**, implementing the abstract members of `SketchDialogsMixin`:
  - `sketchPoints` → `activeShape.points` (the live list);
  - `sketchIsClosed`;
  - `sketchCurrentAngleDeg` → `_currentAngleDeg`; `sketchSnappedAngle`;
  - `sketchWallRealMm` → `activeShape.wallRealMm`;
  - `sketchWaitingForBle`;
  - `sketchBleManager` → `widget.bleManager` (typed `dynamic`);
  - plain setters with no `setState`: `sketchSetSnappedAngle`, `sketchSetCursorWorld`, `sketchSetCurrentAngleDeg`, `sketchSetIsAngleSnapped`, `sketchSetSelectedWallIndex`, `sketchSetWaitingForBle`;
  - `sketchSaveUndo()` → `_saveUndo()`; `sketchApplyRealMeasurement(i, mm)` → `_applyRealMeasurement`; `sketchWallLengthWorld(i)` → `_wallLengthWorld`.

  **Methods by concern**

  *Lifecycle and build*
  - `void initState()` (L176): see 5.2.1.
  - `void dispose()` (L236): cancels the heartbeat and disconnects BLE. Stream subscriptions leak.
  - `Widget build(BuildContext context)` (L2964):
    1. Defines the local closure `_onObjectDropped(Offset screenPos)` (L2967; 5.2.13).
    2. Computes the painter's `angleRefWorld`/`angleTargetWorld`: the second-to-last and last point while dragging the last point; otherwise the last point and `_cursorWorld` when no vertex is selected.
    3. Computes `liveDistance` (open room, cursor set) and `showAngleStrip`.
    4. Clears both hit-rect lists.
    5. Returns `PopScope` → `Scaffold(backgroundColor: white)` → `Stack` (layout under **UI**).

  *Coordinates and hit testing*
  - `Offset worldToScreen(Offset world)` (L276) and `Offset screenToWorld(Offset screen)` (L277): the transform.
  - `Offset snapToGrid(Offset worldPos)` (L279): rounds to 40 u.
  - `bool _isNearLastPoint(Offset screenPos)` (L288): open room, no vertex selected, within 28 px of the last point.
  - `int _findNearPoint(Offset screenPos, {int excludeIndex = -1, double radius = pointSelectRadiusScreen})` (L294): index of the first active-room vertex within the radius, or −1.
  - `Offset? _findSnapPointAcrossShapes(Offset screenPos, {double radius = pointSnapRadiusScreen})` (L304): the first vertex of another *closed* room within the radius.
  - `int _findNearWall(Offset screenPos)` (L1168): the first active-room wall within 18 px (point-to-segment distance in screen space).
  - `bool _pointInsidePolygon(Offset screenPos, List<Offset> worldPoints)` (L1182): even-odd ray casting in screen space.
  - `bool _isInsideFurnitureItem(FurnitureItem item, Offset screenPos)` (L1198): rotates the screen offset by −rotation and tests `abs(x) ≤ w/2 + 10` and `abs(y) ≤ d/2 + 10` (sizes `mm / 5 · _scale`).
  - `double _pointToSegmentDist(Offset p, Offset a, Offset b)` (L1726): clamped projection distance.
  - `(double, Offset) _projectPointOnSegment(Offset p, Offset a, Offset b)` (L1737): **never called**.
  - `double _tAlong(Offset base, Offset vec, double len, Offset pt)` (L1746): `((pt − base)·vec)/len²`. Used for the `SharedWall` t values; shadows the file-private `_tAlong` in `wall_topology.dart` in name only.

  *Angle math*
  - `double _computeAngleDeg(Offset from, Offset to)` (L1017): CCW degrees in [0, 360) with the y axis inverted.
  - `(double, double) _nearestSnapAngle(double angleDeg)` (L1025): returns (nearest snap angle, circular difference).
  - `Offset _computeAngle(Offset fromWorld, Offset toWorld)` (L1036): sets the HUD angle state and returns the angle-snapped point (5.2.3).
  - `Offset? _rayIntersection(Offset oA, double degA, Offset oB, double degB)` (L1066): line–line intersection for CCW-degree directions.
  - `(double?, bool) _trySnap(double angleDeg)` (L1079): (nearest, `diff ≤ 3°`).
  - `Offset _updateMiddlePointAngles(int idx, Offset rawPos)` (L1084): dual-wall snapping for vertex drags (5.2.6).
  - `String _angleLabel()` (L1929): text for the toolbar and the angle strip.

  *Wall chain and real lengths*
  - `double _wallLengthWorld(int wallIndex)` (L1161): drawn length in u (indices wrap modulo n; no bounds check).
  - `void _syncWallDefinitions()` (L1815): rebuilds `_wallAngles` and `_wallDrawnLengths` from the active room's consecutive points (n−1 entries).
  - `void _rebuildPointsFromChain()` (L1829) and `void _applyRealMeasurement(int wallIndex, double realMm)` (L1846): see 5.2.8.

  *Geometry and view*
  - `void _fitShapesToView()` (L1862), `double _totalPerimeter()` (L1900), `double _totalArea()` (L1916): see 5.2.2 and 5.2.9.

  *Rooms*
  - `void _showRoomNameDialog([int? shapeIndex])` (L242): rename dialog (5.2.5); its controller is never disposed.
  - `void _addNewRoom()` (L316).
  - `void _clear()` (L986).

  *Move mode*
  - `_findWallSnapCandidate(SketchShape movingShape)` (L1757): returns the record `({int mw, int os, int ow, Offset sharedStart, Offset sharedEnd, Offset oSharedStart, Offset oSharedEnd})?` for the first overlapping wall pair against other closed rooms, skipping `_movingShapeIndex`. The doc comment above it (L1752–1756) partly describes `wallOverlapSegment`, which moved to `wall_topology.dart` (orphaned comment).
  - `({int mp, int os, int op})? _findVertexSnapCandidate(SketchShape movingShape)` (L1798): the first vertex pair closer than `wallSnapThresholdWorld` (18 u).

  *Gestures*
  - `void _onPointerDown(PointerDownEvent event)` (L1938). It resets the drag flags and pan start, then checks, in this order:
    1. move mode grab;
    2. closed room: rotation handle (selected furniture), then body drag (selected furniture), then opening hit (starts a drag), then vertex select;
    3. open room: selected-vertex drag or reselection, then last-point drag.
  - `void _onPointerMove(PointerMoveEvent event)` (L2074). Branches in priority order:
    1. furniture rotation;
    2. furniture drag;
    3. opening drag;
    4. room move (including shared-wall cleanup and snap-candidate search);
    5. closed-room vertex drag;
    6. open-room vertex drag;
    7. last-point drag;
    8. otherwise the rubber-band cursor.
  - `void _onPointerUp(PointerUpEvent event)` (L2261): finishes, in the same priority:
    1. rotation (`_saveUndo` + sync);
    2. furniture drag;
    3. opening drag (undo only if moved);
    4. room move (wall snap, `SharedWall` creation, vertex snap, autosync; contains a redundant nested `if (_movingShapeIndex >= 0)` at L2298);
    5. close-by-drag;
    6. vertex-drag commit (clears adjacent `wallRealMm`, `_saveUndo`, autosync);
    7. finally, on every ordinary pointer-up, `_syncWallDefinitions()` and reset of the snap indicators.
  - `void _onPointerHover(PointerHoverEvent event)` (L2424): mouse rubber band (grid and angle snap only).
  - `void _onPointerSignal(PointerSignalEvent event)` (L2430): wheel zoom.
  - `void _onScaleStart(ScaleStartDetails d)` (L2441): starts a furniture pinch or an opening pinch when something is selected and ≥2 pointers are down; otherwise records `_scaleStart` and flags multi-touch.
  - `void _onScaleUpdate(ScaleUpdateDetails d)` (L2480): furniture pinch; opening pinch; returns early during point, room or opening drags; two-finger zoom; one-finger pan.
  - `void _onScaleEnd(ScaleEndDetails d)` (L2534): commits pinches (`_saveUndo` + autosync), resets the pan, and clears multi-touch after 150 ms.
  - `void _onTapDown(TapDownDetails details)` (L2556) and `void _commitTap(TapDownDetails details)` (L2741): see 5.2.3, 5.2.5, 5.2.13, 5.2.15.

  *Openings*
  - `double _wallLengthMmForObject(RoomObject obj)` (L2764): drawn wall length × 5 (0 if the index is out of range).
  - `void _onObjectTapped(String id)` (L2771) and `void _showConflictDialog(Wall wall, WallOpenings resolved)` (L2819): see 5.2.13 and 5.2.14.
  - The build-local `_onObjectDropped` (L2967).

  *Furniture*
  - `Offset _snapFurnitureToWall(Offset newPos, FurnitureItem item, SketchShape shape)` (L1213): meant to make an edge flush with the nearest wall within 300 mm. **Never called**.
  - `double _furnitureHalfExtent(FurnitureItem item, Offset dir)` (L1264).
  - `double _wallEdgeGapMm(FurnitureItem item, int wallIdx)` (L1273).
  - `void _applyWallDist(int itemIdx, int wallIdx, double distMm)` (L1290).
  - `double _cornerGapAfterMm(FurnitureItem item, int cornerIdx)` (L1312).
  - `double _cornerGapBeforeMm(FurnitureItem item, int cornerIdx)` (L1326).
  - `void _applyCornerDistAfter(int itemIdx, int cornerIdx, double distMm)` (L1341).
  - `void _applyCornerDistBefore(int itemIdx, int cornerIdx, double distMm)` (L1362).
  - `void _showFurnitureSizeDialog(int itemIdx)` (L1383).
  - `Widget _furnitureDimField(String label, TextEditingController ctrl)` (L1473): styled numeric `TextField`.
  - `void _showFurniturePositionDialog(int itemIdx)` (L1492).
  - `void _showFurnitureLibrary()` (L2874).
  - See 5.2.15 for the behaviour of all of the above.

  *Undo and redo*
  - `void _saveUndo()` (L851), `void _undo()` (L877), `void _redo()` (L934): see 5.2.16.

  *Persistence and navigation*
  - `Future<void> _handleBackPressed()` (L324), `Future<void> _saveProject()` (L468), `Future<void> _loadProject()` (L750), `Future<void> _loadProjectById(int projectId)` (L760): see 5.2.17 and 5.2.18.

  *Cloud and collaboration*
  - `Map<String, dynamic> _buildProjectPayload(String name)` (L537), `Future<void> _queueAutoSync()` (L612), `Future<void> _backupToCloud()` (L645): see 5.2.19.
  - `Future<void> _showInviteCodeDialog()` (L3959), `void _startHeartbeat()` (L4018), `Future<void> _sendHeartbeat()` (L4026), `Widget _buildPresenceAvatars()` (L4039), `Color _avatarColor(String email)` (L4070), `Widget _buildSyncIcon()` (L4081): see 5.2.20.

  **`class _ObjectPanelButton extends StatelessWidget` (L4105)**: fields `icon`, `label`, `onDragStarted` (`VoidCallback`), `onDragEnd` (`void Function(DraggableDetails)`). `build` returns `Draggable<String>(data: label, …)`:
  - `feedback`: a 52×52 blue (0xFF00AAFF) tile with a 28 px white icon and a shadow;
  - `child`: a 52×52 dark tile with a blue icon and a 9 pt label.
  - There is no `DragTarget` anywhere; the drop is handled entirely in `onDragEnd`.

- **Key logic:** See 5.2.3 (angle snapping), 5.2.6 (dual-wall snap with ray intersection), 5.2.8 (chain rebuild), 5.2.11 (room snap), 5.2.13 (object projection and clamping), 5.2.15 (support-function furniture positioning) and 5.2.16 (snapshot undo). Hardcoded numbers in the file:
  - 0.35 default scale and 0.001–5.0 limits;
  - 0.92 / 1.08 wheel factors;
  - 80 ms tap deferral and 150 ms multi-touch reset;
  - 60 px fit padding;
  - 18 px wall hit, 14 px object tap, +16 px object grab, +10 px furniture hit, 50 px handle hit;
  - 300 mm snap in the dead furniture-snap helper;
  - default sizes: window 1200×1200 mm at 900 mm elevation; door/opening 900×2100 mm; 0.8 / 0.95 / 0.98 wall-length factors;
  - limits: 200 mm minimum opening width; 100–6000 mm furniture size;
  - 30 s heartbeat; 4 avatars; 5 avatar colours;
  - strings `'Room Project'`, `'My Project'`, `'Auto Save'`, `'SmartMeasure_Room'`, `'1div=200mm'`, "press BOOT button on ESP32".
- **State and data:** Everything lives in `_SketchScreenState`.
  - The model is the mutable `List<SketchShape> shapes`. Shapes are edited in place, e.g. `activeShape.points[i] = …` or `furnitureItems[i] = item.copyWith(...)`, and then `setState`.
  - Room objects and furniture are always replaced with `copyWith`.
  - Serialisation formats: `_buildProjectPayload` (cloud JSON) and `_loadProjectById` (reads the `DatabaseHelper.loadProject` map); both are listed in 5.4.
  - Ids: rooms use `generateShapeId()`, regenerated on load/undo/redo; openings use `'obj_N'`; furniture uses `'fur_N'`. The counters start at 0 for each screen instance.
- **UI** (Stack children, bottom to top):
  1. **Canvas**: `Listener` (`onPointerSignal/Down/Move/Up/Hover`) → `GestureDetector` (`onScaleStart/Update/End`, `onTapDown`) → `CustomPaint(SketchPainter, child: SizedBox.expand())`.
  2. **Object panel** (right 8, top 80; active room closed): Door, Window, Opening (`_ObjectPanelButton`) and "Furn." (calls `_showFurnitureLibrary`).
  3. **Furniture action bar** (bottom 52; furniture selected): size readout, rotate ±45°, size, position, delete, Done.
  4. **Furniture placing strip** (bottom 52; placing): "Placing X — tap inside room" and CANCEL.
  5. **3D View** button (right 8, bottom 62).
  6. **Top toolbar** (height 48 plus status-bar padding, colour 0xFF2D2D2D): ruler icon, context hint text, `'1div=200mm'` badge, zoom menu (shows the current %), Fit, presence avatars, Share (only with a cloud id), sync icon, Back.
     - Hint precedence:
       1. placing → "Tap inside room to place X";
       2. furniture selected → "Drag to move · Rotate or delete below";
       3. closed room, in order:
          - "Wall N selected — enter real measurement";
          - "Drag point N to reposition";
          - "Point device at wall → press BOOT button" (when `_waitingForBle`);
          - "Tap a wall to edit its length";
       4. open room, in order:
          - "Tap to place first corner";
          - "Drag | <angle>";
          - "Drag point N to reposition";
          - "Snapped: <angle>";
          - "Tap next corner | Drag orange to adjust".
     - The hint is orange when a vertex is selected, green when the angle is snapped, grey otherwise.
  7. **Polar tracking HUD** (5.2.3).
  8. **Bottom area**: the optional angle strip (5.2.7) above a 52 px horizontally scrollable bar with:
     - MODE, PTS, PERIM, AREA and PT status items;
     - Undo, Redo;
     - Clear (enabled when the active room has points);
     - PDF (active room has ≥2 points);
     - DXF (always);
     - Add Room;
     - Save (active room has points);
     - Load;
     - Backup to Cloud (active room has points);
     - Move-mode toggle.
     The Save, Backup and Clear conditions look at the *active* room only, so they are disabled right after "Add Room" even when other rooms have content.
- **Connections:**
  - Opened by `home_screen.dart`, `ar_result_screen.dart` and `collaboration_screen.dart` (`_LiveCollabWrapper`).
  - Uses `SketchPainter`, `furnitureRotationHandlePos`, `exportSketchPdf`, `DxfPreviewScreen`, `Room3DScreen`, `ProjectListScreen`, `DatabaseHelper`, `SyncService`, `ApiService` and `BleManager`.
- **Notes and issues:** see 5.5; the file-specific dead code is listed there.

#### `code/lib/sketch/sketch_model.dart` — 64 lines

- **Purpose:** Core room model: `SketchShape` (one room) and the `SharedWall` link record, plus a unique-id generator.
- **Depends on:** `package:flutter/material.dart` (`Offset`); `furniture_item.dart` (`FurnitureItem`); `room_object.dart` (`RoomObject`).
- **Declarations:**
  - `int _shapeIdCounter` (L7): a library-private counter.
  - `String generateShapeId()` (L9): increments the counter and returns `'${DateTime.now().microsecondsSinceEpoch}_$_shapeIdCounter'`.
  - `class SharedWall` (L14): all fields final, `required` named constructor:
    - `otherShapeId` (String): id of the neighbouring room;
    - `myWallIndex` (int): wall on this room;
    - `otherWallIndex` (int): wall on the neighbour;
    - `tStart`, `tEnd` (double, 0..1 along `myWallIndex`).
  - `class SketchShape` (L30): fields
    - `final String id`;
    - `List<Offset> points` (u);
    - `bool isClosed` (default false);
    - `String label` (default `''`);
    - `Map<int, double> wallRealMm` (wall index → mm);
    - `List<RoomObject> roomObjects`;
    - `List<SharedWall> sharedWalls`;
    - `List<FurnitureItem> furnitureItems`;
    - `double heightMm` (default 2400).
    - Constructor (L42): every argument is optional named; `id` defaults to `generateShapeId()`; null collections become new empty ones.
    - `factory SketchShape.empty()` (L60) is the same as `SketchShape()`.
    - Getter `int get wallCount` (L63): `isClosed ? points.length : clamp(points.length − 1, 0, 999)`.
- **Key logic:** None beyond id generation and `wallCount`.
- **State and data:** Plain mutable data with no serialisation methods. Field persistence is listed in 5.4: `label`, `heightMm`, `id` and `sharedWalls` are not persisted anywhere.
- **Connections:**
  - Imported by `sketch_screen.dart`, `sketch_painter.dart`, `wall_topology.dart`, `wall_openings.dart`, `room_3d_screen.dart`, `sketch_pdf_export.dart`, `dxf_exporter.dart`, `dxf_preview_screen.dart`, `ar_result_screen.dart`, `collaboration_screen.dart` and `cloud_projects_screen.dart`.
  - `wallCount` is used by `dxf_preview_screen.dart`.
- **Notes and issues:**
  - `SharedWall` / `sharedWalls` is **write-only**: the screen writes it during room moves; nothing reads it (the painter uses `buildWalls`).
  - Ids are not stable across save/load, undo/redo or cloud round-trips. Every reconstruction calls `SketchShape.empty()`.
  - `wallCount` caps at 999 for open shapes (harmless).

#### `code/lib/sketch/sketch_constants.dart` — 64 lines

- **Purpose:** Shared constants (units, grid, thresholds, snap angles), wall-rectangle geometry and the length/area formatters used across the sketch files.
- **Depends on:** `package:flutter/material.dart` (`Offset`), `dart:math`.
- **Declarations:**

  | Constant (line) | Value | Unit / meaning |
  |---|---|---|
  | `mmPerUnit` (L5) | 5.0 | mm per world unit |
  | `unitsPerMeter` (L6) | 200.0 | u per metre — **unused anywhere** |
  | `panThreshold` (L8) | 6.0 | px before a one-finger drag pans |
  | `minorGrid` (L9) | 40.0 | u (200 mm), grid snap step |
  | `majorGrid` (L10) | 200.0 | u (1 m) |
  | `snapRadiusWorld` (L11) | 15.0 | u (75 mm); painter's close-loop cue |
  | `minPointDistance` (L12) | 8.0 | u (40 mm) between consecutive points |
  | `lastPointGlowRadius` (L13) | 28.0 | px; last-point drag handle, also the painter's glow |
  | `lastPointRingRadius` (L14) | 14.0 | px (painter) |
  | `pointSnapRadiusScreen` (L15) | 30.0 | px; vertex snap |
  | `pointSelectRadiusScreen` (L16) | 22.0 | px; vertex select and tap-close |
  | `snapThresholdDeg` (L17) | 3.0 | degrees |
  | `minAngleDistance` (L18) | 10.0 | u (50 mm) |
  | `wallThickness` (L19) | 30.0 | u (150 mm); painter and PDF wall rectangles |
  | `snapAngles` (L36) | [0, 30, 45, 60, 75, 90, 105, 120, 135, 150, 180, 210, 225, 240, 255, 270, 285, 300, 315, 330] | degrees CCW; symmetric under +180°, no 15°/165° family |
  | `wallSnapThresholdWorld` (L64) | 18.0 | u (90 mm); used **only** for the move-mode vertex snap, despite its comment ("walls must be close to snap/merge") |

  - `List<Offset> thickWallRect(Offset a, Offset b, double thickness)` (L21): returns the four corners of the rectangle centred on segment a–b, offset ±thickness/2 along the left normal `(−dy, dx)/len`, in the order a+n, b+n, b−n, a−n. Returns an empty list for a zero-length segment.
  - `String formatLength(double worldUnits)` (L42): mm = u × 5; `"X.XX m"` when ≥ 1000, else `"N mm"`.
  - `String formatArea(double worldUnitsSquared)` (L50): mm² = u² × 25; m² = mm²/1e6; `"X.XX m²"` when ≥ 0.01, else `"N mm²"`.
  - `Offset? lineIntersect(Offset p1, Offset d1, Offset p2, Offset d2)` (L57): parametric line intersection, null when `abs(cross) < 1e-6`. **Unused anywhere.**
- **Connections:** Used by the screen, dialogs, painter, furniture painter, PDF export, DXF preview, wall_openings and ar_result_screen.
- **Notes and issues:**
  - The trailing comment `}// world units (~50mm real)` after `thickWallRect` is misplaced and wrong: `wallThickness` is 30 u = 150 mm.
  - Thresholds mix screen pixels and world units, so behaviour changes with zoom.

#### `code/lib/sketch/room_object.dart` — 52 lines

- **Purpose:** Model for wall openings (doors, windows, plain openings).
- **Depends on:** nothing.
- **Declarations:**
  - `enum RoomObjectType { door, window, opening }` (L3).
  - `class RoomObject` (L5): fields
    - `final String id`;
    - `final String ownerShapeId` (the `SketchShape.id` of its room);
    - `final RoomObjectType type`;
    - `int wallIndex`;
    - `double positionAlong` (0 = wall start `points[wallIndex]`, 1 = wall end; the centre of the opening);
    - `double widthMm`;
    - `double heightMm` (for 3D);
    - `double elevationMm` (sill height; doors and openings use 0);
    - `final bool swingFlipped` (draw the door arc on the other side).
  - Constructor (L16) defaults: `positionAlong` 0.5, `widthMm` 900, `heightMm` 2100, `elevationMm` 0, `swingFlipped` false.
  - Getters `isDoor`, `isWindow`, `isOpening` (L28–30).
  - `RoomObject copyWith({int? wallIndex, double? positionAlong, double? widthMm, double? heightMm, double? elevationMm, bool? swingFlipped})` (L32): `id`, `ownerShapeId` and `type` cannot change.
- **State and data:** Persistence keys are in 5.4. `type` is stored as `type.name` (`'door'|'window'|'opening'`).
- **Connections:** Screen, dialogs, `room_object_utils.dart`, `wall_openings.dart`, the painter (via shapes), PDF/DXF, 3D, database and collaboration/cloud screens.
- **Notes and issues:**
  - The fields are mutable except id/owner/type/swing, but the editor always replaces objects with `copyWith`.
  - `ownerShapeId` becomes stale whenever room ids are regenerated (undo/redo); the conflict logic depends on it.

#### `code/lib/sketch/room_object_utils.dart` — 106 lines

- **Purpose:** Screen-space helpers for placing openings on walls and locating them.
- **Depends on:** `dart:math`, `flutter/material.dart`, `room_object.dart`.
- **Declarations:**
  - `class WallHitResult` (L7): const constructor; fields `final int wallIndex`, `final double positionAlong` (0..1), `final Offset snapPoint` (world).
  - `WallHitResult? findNearestWall({required Offset screenPos, required List<Offset> points, required bool isClosed, required Offset Function(Offset) worldToScreen, required Offset Function(Offset) screenToWorld, double hitThreshold = 30.0})` (L21):
    - for each wall (n or n−1), project the screen position onto the screen-space segment and clamp `t` to **[0.05, 0.95]** to keep away from corners;
    - measure the distance to the clamped projection and keep the nearest wall under the threshold;
    - returns null if fewer than 2 points or nothing is within range; walls shorter than 1 px² are skipped.
  - `Offset objectCentreWorld({required RoomObject obj, required List<Offset> points, int? wallCount})` (L76): `a + t·(b − a)`; falls back to `points[0]` when `wallIndex >= wallCount` (default n).
  - `Offset wallDirectionScreen({required int wallIndex, required List<Offset> points, required Offset Function(Offset) worldToScreen})` (L93): unit a→b vector in screen space; `(1, 0)` when shorter than 1 px.
- **Connections:** Only `sketch_screen.dart`, through the object drop and the object tap hit test.
- **Notes and issues:** `findNearestWall` returns `snapPoint`, but the screen never reads it. `objectCentreWorld` has no lower-bound or empty-list check.

#### `code/lib/sketch/wall_openings.dart` — 118 lines

- **Purpose:** Maps room openings onto topological walls and detects overlapping openings that two rooms placed on the same shared wall.
- **Depends on:** `wall_topology.dart` (`Wall`, `WallSource`), `sketch_model.dart`, `room_object.dart`, `sketch_constants.dart` (`mmPerUnit`).
- **Declarations:**
  - `class ResolvedOpening` (L6): `final RoomObject source`; `final double positionAlong` (0..1 local to the `Wall`, from `wall.a` to `wall.b`).
  - `class WallOpenings` (L13): `final List<ResolvedOpening> openings`; `final bool hasConflict`; positional constructor.
  - `WallOpenings openingsForWall(Wall wall, List<SketchShape> shapes)` (L20): see 5.2.14. A source shape that cannot be found is skipped. Conflicts are tested pairwise between different `ownerShapeId`s; walls shorter than 1 u never conflict.
  - `Wall? findWallForObject(RoomObject obj, SketchShape owner, List<Wall> walls)` (L71): the first wall with a source `(owner.id, obj.wallIndex)` whose t range contains `obj.positionAlong` (±1e-6).
  - `bool wouldConflict(RoomObject candidate, SketchShape owner, List<SketchShape> shapes, List<Wall> walls)` (L85): false unless the candidate's wall is shared. Otherwise it converts the candidate to local t on its own source and tests interval overlap against `openingsForWall(...).openings` whose owner is not `owner.id`.
- **Key logic:** half width in local t = `(widthMm / 5 / 2) / |wall.b − wall.a|`. Two intervals overlap when `aLo < bHi && bLo < aHi`.
- **Connections:** The painter (`openingsForWall` per wall, to cut and draw openings and flag conflicts) and the screen (`_onObjectTapped`, `_onObjectDropped`).
- **Notes and issues:**
  - Conflict ownership is decided by `RoomObject.ownerShapeId`, but `wouldConflict` compares it with the *current* `owner.id`. After undo/redo, which regenerates shape ids, a room's own openings count as "other", producing false conflicts.
  - `openingsForWall` uses the *shape's* objects, not the object's stored owner, so owner ids only matter for the conflict test and for the conflict dialog.

#### `code/lib/sketch/wall_topology.dart` — 165 lines

- **Purpose:** Derives the set of distinct physical walls from all closed rooms, merging collinear overlapping wall stretches of different rooms into shared walls.
- **Depends on:** `flutter/material.dart` (`Offset`), `sketch_model.dart`.
- **Declarations:**
  - `class WallSource` (L4): `final String shapeId`, `final int wallIndex`, `final double tStart`, `final double tEnd`. These are parameters along the source room's wall (0..1). They are not ordered and may be descending.
  - `class Wall` (L18): `final String id`, `final Offset a`, `final Offset b` (world), `final List<WallSource> sources`; getter `bool get isShared => sources.length > 1` (L26).
  - `({Offset start, Offset end, Offset oStart, Offset oEnd})? wallOverlapSegment(Offset mA, Offset mB, Offset oA, Offset oB, {double perpThresh = 3.0, double parallelThresh = 0.08})` (L29): see 5.2.12.
  - `double _tAlong(Offset p1, Offset p2, Offset p)` (L71): unclamped projection parameter; 0 for degenerate segments.
  - `List<(double, double)> _subtractRanges(List<(double, double)> covered)` (L78): complement in [0, 1] of the union of ranges (sorted sweep with a cursor).
  - `List<Wall> buildWalls(List<SketchShape> shapes)` (L93): see 5.2.12.
- **State and data:** Pure functions. `Wall.id` formats are `'w_<A.id>_<ai>_<B.id>_<bi>'` (shared) and `'w_<shape.id>_<i>_<start 3 decimals>'` (free). Ids change whenever room ids change.
- **Connections:**
  - `buildWalls` is used by the painter (`_drawAllWalls`) and by the screen (`_onObjectTapped`, `_onObjectDropped`).
  - `wallOverlapSegment` is used by the screen (`_findWallSnapCandidate` and move-mode release).
- **Notes and issues:**
  - The `dot > 0` sign selection is dead because `dot` is an absolute value.
  - Only `oA`'s perpendicular distance is checked.
  - The 23° parallel tolerance is loose while the 3 u (15 mm) offset is tight.
  - O(S²N²) work on every paint.
  - Triple overlaps duplicate shared walls.

#### `code/lib/sketch/sketch_widgets.dart` — 82 lines

- **Purpose:** Two small reusable widgets for the editor.
- **Depends on:** `flutter/material.dart`.
- **Declarations:**
  - `class UnitSelector extends StatefulWidget` (L6): `final void Function(String unit) onUnitChanged`.
    - `_UnitSelectorState` (L14) holds `String _unit = 'mm'`.
    - `build` renders a vertical column of two 44 px tiles, "mm" and "m"; the active one is blue 0xFF00AAFF.
    - Tapping the inactive tile does `setState(_unit = u)` and calls `onUnitChanged(u)`.
  - `class StatusItem extends StatelessWidget` (L58): `final String label`, `final String value`. A `Row` with the label (0xFF555555) and value (0xFF888888) in 11 pt monospace.
- **Connections:** `UnitSelector` is used only in `showSketchManualEntryDialog`; `StatusItem` only in the screen's bottom bar.
- **Notes and issues:** `UnitSelector` does not expose its current unit, so the parent cannot know which unit the text is in (this causes the m/mm bug in the dialog).

#### `code/lib/sketch/sketch_dialogs.dart` — 596 lines

- **Purpose:** Wall-angle and wall-length dialogs, provided as a mixin so they can read and change the screen's private state, plus the editable dialog for door/window/opening dimensions.
- **Depends on:** `flutter/material.dart`, `dart:math`, `sketch_constants.dart` (`formatLength`), `sketch_widgets.dart` (`UnitSelector`), `room_object.dart`.
- **Declarations:**
  - `mixin SketchDialogsMixin<T extends StatefulWidget> on State<T>` (L9).
    - Abstract interface (L12–28), implemented by `_SketchScreenState` L155–172:
      - getters `sketchPoints`, `sketchIsClosed`, `sketchCurrentAngleDeg`, `sketchSnappedAngle` (unused by the mixin), `sketchWallRealMm`, `sketchWaitingForBle` (unused by the mixin), `sketchBleManager` (`dynamic`, so BLE is not imported);
      - setters `sketchSetSnappedAngle`, `sketchSetCursorWorld`, `sketchSetCurrentAngleDeg`, `sketchSetIsAngleSnapped`, `sketchSetSelectedWallIndex`, `sketchSetWaitingForBle`;
      - actions `sketchSaveUndo()`, `sketchApplyRealMeasurement(int, double)`, `sketchWallLengthWorld(int)`.
    - `void showSketchAngleEditor()` (L31):
      - inputs: the angle in degrees (CCW from east) with preset chips;
      - validation: `double.tryParse` and ≥2 points; otherwise it just closes;
      - effect: moves the last point (5.2.7); returns nothing;
      - used by the screen's angle strip (L3706).
    - `void showSketchWallEditDialog(int wallIndex)` (L147):
      - chooses between BLE and manual (5.2.8). `isConnected` is read dynamically as `ble.isConnected as bool? ?? false`;
      - "Use Device" sets the selected wall and the waiting flag inside `setState`;
      - used by the wall tap (L2678) and the dimension-label tap (L2567).
    - `void showSketchManualEntryDialog(int wallIndex)` (L232):
      - inputs: the length (pre-filled with the existing real mm), `UnitSelector`, presets 1000–5000 mm;
      - validation: must parse and be > 0, otherwise the dialog stays open;
      - result: `sketchApplyRealMeasurement(wallIndex, val)`; CANCEL sets `_selectedWallIndex = -1`.
  - `class ObjectMeasurementDialog extends StatefulWidget` (L399):
    - params `required RoomObject roomObject`, `required ValueChanged<RoomObject> onSave`, `required VoidCallback onDelete`, `VoidCallback? onFlip`, `double? wallLengthMm`.
    - `_ObjectMeasurementDialogState` (L420):
      - `initState` (L426) creates `_widthCtrl`, `_heightCtrl` and `_elevationCtrl` with 0-decimal values; `dispose` (L437) disposes them;
      - `build` (L445): title "Edit Door / Edit Opening / Edit Window" with a matching icon; fields "Width (mm)" (plus "Wall: N mm" when `wallLengthMm` is given), "Height (mm)", and "Elevation from floor (mm)" for windows only;
      - actions: **FLIP SWING** (doors with `onFlip`: calls `onFlip`, then pops); **DELETE** (pops, then `onDelete`); **CANCEL**; **SAVE**.
      - SAVE parses each field, falling back to the old value when parsing fails, forces elevation to 0 for doors and openings, calls `onSave(roomObject.copyWith(widthMm, heightMm, elevationMm))`, then pops.
      - There is no range validation: values can be negative, zero or wider than the wall.
    - Used only by `_onObjectTapped`.
- **Key logic:**
  - Angle editor: `last = ref + L·(cos θ, −sin θ)`.
  - Unit toggle: mm→m `v/1000` (3 decimals); m→mm `v*1000` (0 decimals).
- **UI:** Dark dialogs (0xFF2D2D2D and 0xFF1E2A3A) with monospace fonts. The BLE choice is a bottom sheet with rounded top corners.
- **Connections:** Mixed into `_SketchScreenState`; `ObjectMeasurementDialog` is built in `_onObjectTapped`.
- **Notes and issues:**
  - **Unit bug**: after switching to "m", or typing metres, APPLY sends the number as mm, which is 1000× too small, because the dialog never tracks the selected unit.
  - Dismissing the manual dialog or the BLE sheet by tapping outside does not reset `_selectedWallIndex`.
  - The angle editor neither re-syncs the chain nor autosyncs.
  - The "(closing)" wall title is shown, but applying to that wall is a silent no-op in the screen (5.2.8).
  - Object SAVE is not undoable and does not mark the project dirty (the screen's `onSave` does neither).

---

### 5.4 Data contracts

**Units and coordinates**

| Quantity | Unit / convention |
|---|---|
| Points, cursor, furniture `position`, `Wall.a/b` | World units (u); 1 u = 5 mm; x right, y down; origin arbitrary (initially at the top-left of the screen) |
| Screen position | `world * _scale + _panOffset` (logical px); `_scale` 0.001–5, default 0.35 |
| `wallRealMm` values, `RoomObject` sizes, furniture `widthMm`/`depthMm`, `heightMm` | Millimetres |
| `positionAlong`, `WallSource.tStart/tEnd`, `SharedWall.tStart/tEnd`, `ResolvedOpening.positionAlong` | 0..1 along a wall segment |
| UI angles (`_computeAngleDeg`, `snapAngles`, angle editor, HUD, `_prevWallAngle`/`_nextWallAngle`) | Degrees, counter-clockwise from +x **as seen on screen** (computed with −dy), range [0, 360) |
| Chain `_wallAngles`, payload/SQLite `wall_angles.angle` | Radians, `atan2(dy, dx)` in y-down world coordinates (clockwise-positive on screen), range (−π, π] |
| `FurnitureItem.rotationDeg` | Degrees, clockwise on screen (y-down), normalised with `% 360` |
| Chain `_wallDrawnLengths`, `wall_lengths.length` | World units |
| Area / perimeter | Computed in u² / u, displayed via `formatArea`/`formatLength` |

**`SketchShape` field persistence**

| Field | Type | SQLite (`DatabaseHelper`) | Cloud payload | Notes |
|---|---|---|---|---|
| `id` | String | — | — | Regenerated by every load, undo/redo and cloud parse |
| `points` | `List<Offset>` u | `shape_points(order_index, x, y)` | `points[{order_index, x, y}]` | |
| `isClosed` | bool | `shapes.is_closed` 0/1 | `is_closed` bool | |
| `label` | String | **not stored** | **not sent** | Used by the painter, PDF, DXF and 3D |
| `wallRealMm` | `Map<int,double>` | `wall_real_mm(wall_index, real_mm)` | `wall_real_mm[{wall_index, real_mm}]` | |
| `roomObjects` | `List<RoomObject>` | `room_objects` (per project, `shape_index`) | top-level `roomObjects[]` | |
| `sharedWalls` | `List<SharedWall>` | — | — | Write-only |
| `furnitureItems` | `List<FurnitureItem>` | `furniture_items` | top-level `furnitureItems[]` | |
| `heightMm` | double (2400) | **not stored** | **not sent** | Set from the 3D view |
| (screen) `_wallAngles` | `List<double>` rad | `wall_angles(order_index, angle)`, **the screen list duplicated under every shape** | per shape, recomputed from its points | |
| (screen) `_wallDrawnLengths` | `List<double>` u | `wall_lengths(order_index, length)`, duplicated the same way | per shape, recomputed | |

**`RoomObject` serialisation**

| Field | Payload / SQLite key | Notes |
|---|---|---|
| `id` | `object_id` | `'obj_N'` |
| (owner) | `shape_index` | `ownerShapeId` itself is not stored; rebuilt from the index |
| `type` | `type` | `'door'`, `'window'` or `'opening'` (`.name`) |
| `wallIndex` | `wall_index` | |
| `positionAlong` | `position_along` | 0..1 |
| `widthMm`, `heightMm`, `elevationMm` | `width_mm`, `height_mm`, `elevation_mm` | mm |
| `swingFlipped` | `swing_flipped` 0/1 | **SQLite only**; not in the cloud payload |

**`FurnitureItem` as serialised by this screen**: `furniture_id` (`'fur_N'`), `shape_index`, `type` (`FurnitureType.name`), `position_x`, `position_y` (u), `rotation_deg`, `width_mm`, `depth_mm`.

**Cloud upload payload** (`_buildProjectPayload(name)`, sent through `SyncService.queueUpload` → `ApiService.uploadProject` → POST `/sync/upload`):

```json
{
  "project": { "name": "<active room label | 'Room Project' | backup name>",
               "local_id": 12,
               "cloud_project_id": 34 },
  "shapes": [
    { "shape_index": 0,
      "is_closed": true,
      "points":       [ { "order_index": 0, "x": 120.0, "y": 80.0 } ],
      "wall_real_mm": [ { "wall_index": 0, "real_mm": 3000.0 } ],
      "wall_angles":  [ { "order_index": 0, "angle": 0.0 } ],
      "wall_lengths": [ { "order_index": 0, "length": 600.0 } ] }
  ],
  "roomObjects": [
    { "object_id": "obj_1", "shape_index": 0, "type": "door", "wall_index": 0,
      "position_along": 0.5, "width_mm": 900.0, "height_mm": 2100.0, "elevation_mm": 0.0 }
  ],
  "furnitureItems": [
    { "furniture_id": "fur_1", "shape_index": 0, "type": "sofa",
      "position_x": 150.0, "position_y": 120.0, "rotation_deg": 0.0,
      "width_mm": 0.0, "depth_mm": 0.0 }
  ],
  "last_modified_at": "<server updated_at, added by SyncService when known>"
}
```

Notes on the payload:
- `cloud_project_id` is included only when `_cloudProjectId != null`. `wall_angles`/`wall_lengths` have n−1 entries (consecutive point pairs, closing wall excluded).
- The example numbers are illustrative. The keys match `smartmeasure-backend/src/routes/sync.js`, which destructures `project, shapes, roomObjects, furnitureItems, last_modified_at`.
- Upload success emits `{local_project_id, cloud_project_id, updated_at}` on `uploadSuccessStream`.

**Map consumed by `_loadProjectById`** (from `DatabaseHelper.loadProject`):

```text
{ 'project': {id, name, created_at, updated_at},
  'shapes': [ { 'is_closed': int(0|1),
                'points': [ {id, shape_id, order_index, x: double, y: double} ],
                'wall_real_mm': [ {wall_index: int, real_mm: double, …} ],
                'wall_angles':  [ {order_index, angle: double, …} ],   // only shapes.first used
                'wall_lengths': [ {order_index, length: double, …} ] } ],
  'room_objects':    [ {object_id, shape_index, type, wall_index, position_along,
                        width_mm, height_mm, elevation_mm, swing_flipped} ],
  'furniture_items': [ {furniture_id, shape_index, type, position_x, position_y,
                        rotation_deg, width_mm, depth_mm} ] }
```

**Derived (non-persisted) geometry types**

| Type | Fields | Producer → consumer |
|---|---|---|
| `Wall` | `id`, `a`, `b` (u), `sources`, `isShared` | `buildWalls` → painter, `findWallForObject`, `openingsForWall` |
| `WallSource` | `shapeId`, `wallIndex`, `tStart`, `tEnd` | inside `Wall` |
| `ResolvedOpening` | `source: RoomObject`, `positionAlong` (wall-local 0..1) | `openingsForWall` → painter, conflict dialog |
| `WallOpenings` | `openings`, `hasConflict` | `openingsForWall` |
| `WallHitResult` | `wallIndex`, `positionAlong` (0.05–0.95), `snapPoint` | `findNearestWall` → `_onObjectDropped` |
| `SharedWall` | `otherShapeId`, `myWallIndex`, `otherWallIndex`, `tStart`, `tEnd` | move-mode release → nobody |

**External interfaces called by the editor**

| Callee | Arguments passed | Returned / effect |
|---|---|---|
| `SketchPainter(...)` | `panOffset, scale, minorGrid, majorGrid, cursorWorld, snapRadiusWorld, isDraggingLastPoint, lastPointGlowRadius, lastPointRingRadius, snappedAngle, isAngleSnapped, currentAngleDeg, nearestSnapAngleDeg, snapDiffDeg, angleRefWorld, angleTargetWorld, snapAngles, activePointIndex, snapTargetIndex, prevWallAngle, nextWallAngle, prevWallSnapped, nextWallSnapped, selectedWallIndex, snapCandidateShape, snapCandidateWall, labelHitRects, shapes, activeIndex, selectedObjectId, selectedFurnitureId, roomLabelHitRects` | Paints; appends `(rect, wallIndex, shapeIndex)` / `(rect, shapeIndex)` tap targets to the two lists |
| `furnitureRotationHandlePos(item:, worldToScreen:, scale:)` | selected item | Screen position of the handle |
| `exportSketchPdf(context:, shapes:, projectName:)` | all rooms, `_localProjectName` | `Future<void>`; builds the PDF and opens `Printing.layoutPdf` |
| `DxfPreviewScreen(shapes:, projectName:)` | all rooms, name or `'SmartMeasure_Room'` | Pushed route |
| `Room3DScreen(shapes:, initialActiveShapeIndex:, bleManager:, onWallMeasured:, onHeightChanged:)` | live `shapes` list | Callbacks `(int wallIndex, double mm)` and `(double heightMm)`; no room id |
| `DatabaseHelper.instance.saveProject(name:, shapes:, roomObjects:, wallAngles:, wallDrawnLengths:)` | — | `Future<int>` new project id (always an insert) |
| `DatabaseHelper.instance.loadProject(id)` / `.deleteProject(id)` | — | Map above / deletes the project, including its `pending_uploads` |
| `SyncService.instance.queueUpload(projectId:, projectData:, lastModifiedAt:)` | payload above | Queued in `pending_uploads`, processed immediately and retried |
| `ApiService.isLoggedIn()`, `.getInviteCode(id)`, `.sendHeartbeat(id)`, `.getActiveCollaborators(id)` | cloud id | bool / `String?` / void / `List` of maps with `email` |
| `BleManager.packetStream` | — | `BlePacket{distanceMm (16-bit, mm), batteryPercent, isCapturing}` |
| `ProjectListScreen` (pushed with `Navigator.push<int>`) | — | Local project id, or null |

**Inbound contracts** (built by callers):
- **AR import** (`ArResultScreen._importToSketch`): `SketchShape(points: mm/5, centred at (200,200) u; isClosed: true; label: 'AR Scan'; wallRealMm: {i: segment mm for all n walls}; heightMm: 2400)`.
- **Collaboration** (`_LiveCollabWrapper`):
  - `initialShapes` are parsed from cloud JSON with new ids; that parser maps every non-`'door'` type to window, so `'opening'` is lost, and it does not read `swing_flipped`;
  - `initialWallAngles`/`initialWallLengths` come from the first shape's `wall_angles`/`wall_lengths`;
  - plus `cloudProjectId` and `canEdit`;
  - the wrapper's `lastKnownUpdatedAt` is **not** passed in, so the editor's first upload carries no `last_modified_at`.

---

### 5.5 Known issues and limitations

**Data loss and corruption**
- Room `label` and `heightMm` are not persisted to SQLite (no columns) and not included in the cloud payload. They are also dropped by `_undo`/`_redo`, which rebuild rooms with `SketchShape.empty()`. After any save/load, undo or sync, room names are blank and heights reset to 2400 mm.
- `_undo`/`_redo` regenerate room ids. As a result `RoomObject.ownerShapeId` no longer matches:
  - conflict-dialog removals silently do nothing (they look up `shape.id == ownerShapeId`);
  - "this room / other room" is mislabelled;
  - `wouldConflict` treats a room's own openings as foreign and blocks valid placements.
- Furniture undo is broken:
  - `_saveUndo` pushes the furniture snapshot twice (L862, L872);
  - `_redo` never pushes the current furniture onto the undo stack;
  - after the first undo, furniture states no longer match the geometry.
- Many edits snapshot **after** the change: vertex drag commit (L2407), furniture rotation/drag end, object drag end, pinch end, 3D height change. These edits cannot be undone on their own.
- The wall chain (`_wallAngles`/`_wallDrawnLengths`) is screen-level.
  - It is not re-synced when the active room changes (room switch in `_onTapDown`, `_addNewRoom`, move-mode grab, load).
  - `_applyRealMeasurement` called before the next canvas pointer-up — e.g. via `Room3DScreen.onWallMeasured` right after switching rooms — rebuilds the active room from another room's chain. Its geometry and point count are corrupted.
- `Room3DScreen` callbacks (`onWallMeasured`, `onHeightChanged`) carry no room id. When the user picks a different room inside the 3D view, the measurement and height are applied to the editor's `activeShape`, while the 3D screen has already written `wallRealMm` on the room it showed.
- **The closing wall of a closed room cannot be given a real length** (manual or BLE): `_applyRealMeasurement` requires `wallIndex < _wallAngles.length` = n−1. The dialog closes with no effect, and a waiting BLE measurement is never consumed. Values written there by AR import or the 3D view are not applied to the geometry and go stale after later rescales.
- The manual length dialog interprets the number as mm even when the unit selector shows "m" (1000× error).
- Closing a room by dragging the last point onto point 0 keeps a duplicate vertex, i.e. a zero-length closing wall. Snapping a dragged vertex onto another vertex also creates duplicates; there is no merge.
- After a vertex drag, `wallRealMm` is not cleared for the closing wall when vertex 0 or n−1 moved, leaving stale "real" labels.
- Moving a room (move mode) does not move its furniture.
- `_clear()` keeps the room's furniture and label. The furniture becomes invisible (drawn only for closed rooms) but is still saved and synced.
- Loading a project does not clear the undo/redo stacks, so undo can restore the previously open project.
- Loading also keeps `_cloudProjectId` and the heartbeat. The `uploadSuccessStream` listener accepts events for any project (it never checks `local_project_id`). Either way, later autosyncs can upload one project's content into another cloud project.
- The id counters `_objectCounter`/`_furnitureCounter` restart at 0 for each screen. After loading, new items can reuse `'obj_1'`/`'fur_1'`, so selection, deletion (`removeWhere` by id) and conflict logic affect several items at once.
- Objects are never re-clamped when their wall shrinks. Width can exceed the wall via the object dialog, which has no validation.
  - Dragging such an object calls `clamp(h, 1 − h)` with h > 0.5, which throws `ArgumentError`.
  - An opening pinch on a wall shorter than about 210 mm, and an object tap hit test on a wall shorter than about 255 mm, have the same `clamp` hazard.

**Persistence and sync**
- "Save" always inserts a new SQLite project, so repeated saves create duplicates. `DatabaseHelper.updateProject` is unused.
- The back-dialog save inserts a new project and deletes the old one. This changes the local id and deletes the old id's `pending_uploads`, dropping queued offline uploads. Typing "cancel"/"discard" as the name is treated as that button.
- Autosync and backup upload to the cloud but never refresh the local SQLite copy.
- Autosync names the cloud project after the active room's label, or `'Room Project'`.
- In a live collaboration session, each re-keyed `SketchScreen` starts with `_localProjectId == null`. The first autosync then creates a new local `'Auto Save'` project, so they accumulate.
- `canEdit == false` only disables autosync. View-only collaborators can still edit locally and use "Backup to Cloud", which sends the shared `cloud_project_id`.
- `_isDirty` is only set by `_saveUndo`:
  - room renames and object dimension edits do not trigger the save prompt;
  - AR-imported sketches left without editing are discarded silently.
- The sync icon shows the global `SyncService` status and shows "idle" (green) even when the user is not logged in.
- `swing_flipped` and the `'opening'` type do not survive the cloud round-trip (payload and collaboration parser).
- Stream subscriptions created in `initState` are never cancelled. Several `setState` calls after `await` lack a `mounted` check (`_saveProject`, `_queueAutoSync`, `_backupToCloud`).

**Interaction and UX**
- Tapping inside any other closed room switches the active room. Corners can never be placed inside an existing room, and a half-drawn room is abandoned when that happens.
- There is no delete-room command.
- The room-name dialog's keyboard submit closes it without saving.
- The angle editor pre-fills with the last cursor angle rather than the last wall's angle.
- `_waitingForBle` has no timeout or cancel. Its hint text only shows once `_selectedWallIndex` was reset, by which time packets are ignored.
- The opening drop position uses the Draggable feedback's top-left corner (`details.offset`), not the finger, so drops can miss the 30 px wall threshold.
- Move-mode wall snapping needs walls within 3 u (15 mm) perpendicular but accepts up to about 23° non-parallel. The 18 u vertex snap usually does the alignment. `wallSnapThresholdWorld`'s comment is misleading.
- The conflict dialog's "Keep" deletes every other opening on that wall stretch, not only the conflicting one.
- Hit helpers return the first match within the threshold, not the nearest.
- Thresholds mix screen pixels and world units. The painter's close cue uses 15 u while closing uses 22/30 px.
- Save/Backup/Clear enablement looks only at the active room.
- The 80 ms deferred tap is cancelled only by multi-touch. A one-finger pan does not cancel a tap-down that has already been delivered.
- The furniture size and position dialogs use cm while everything else uses mm.
- No room constraint for furniture; `_snapFurnitureToWall` exists but is unused.

**Performance**
- `buildWalls` is O(S²·N²) and is recomputed on every paint and on object taps and drops.
- Undo stacks are unbounded and store full copies of all rooms per edit.

**Dead or inconsistent code**
- Dead methods: `_snapFurnitureToWall` (L1213), `_projectPointOnSegment` (L1737).
- Dead or write-only fields: `_pendingBleMm`, `_movingObjectId`, `_moveStartScreenPos`, `_objectMoveOccurred`, `_dragObjectScreenPos`, `_dragWallHit`, `_objectPinchStartScale`, and the whole `SharedWall`/`sharedWalls` mechanism.
- Mixin getters `sketchSnappedAngle` and `sketchWaitingForBle` are declared and implemented but never used.
- Constants `unitsPerMeter` and `lineIntersect` are unused.
- Leftovers in `sketch_screen.dart`: an orphaned doc comment (L1752–1756), a redundant nested `if` (L2298), and a duplicate `_syncWallDefinitions()` call (L2408/L2411).
- `wallOverlapSegment` contains a dead sign test because `dot` is already an absolute value.
- The misplaced/wrong comment after `thickWallRect`.
- `findNearestWall` returns `snapPoint`, which the screen never uses.
- Hardcoded UI strings and values:
  - `'1div=200mm'` (would be wrong if `minorGrid` changed);
  - "press BOOT button on ESP32";
  - default names `'Room Project'`, `'My Project'`, `'Auto Save'`, `'SmartMeasure_Room'`;
  - the zoom presets, default opening sizes and the 5 avatar colours.
- CLAUDE.md is inaccurate here: the editor does not use Riverpod and there is no `SketchModel` class.
- There are no automated tests for any sketch file (`code/test` contains none).


---

## Part 6 — 2D plan rendering and furniture

### 6.1 Overview

This part covers **how the 2D floor plan is painted on the sketch screen**, plus the **furniture data model, catalogue and plan symbols**. It has three files:

| File | Role |
|---|---|
| `code/lib/sketch/sketch_painter.dart` | `SketchPainter`, the only `CustomPainter` of the sketch canvas. It paints the grid and axes, room fills, one combined wall mass with door, window and opening cut-outs, door/window symbols, dimension lines, room name and area labels, vertex markers, and every live drawing aid (rubber band, angle-snap rays, angle arc, snap cursor, close-loop ring). It calls the furniture painter for each furniture item. It also **writes tap targets** (hit rectangles for dimension labels and room labels) back into lists owned by the screen. |
| `code/lib/sketch/furniture_item.dart` | `enum FurnitureType` (31 values), `extension FurnitureTypeExtension` (display name, default size, 3D height, theme colour, Material icon for each type) and the `FurnitureItem` data class (id, type, centre position, rotation, width, depth). |
| `code/lib/sketch/furniture_painter.dart` | **Top-level functions only. There is no `FurniturePainter` class.** `drawFurnitureItem()` draws one item as a black-and-white architectural plan symbol, plus its selection overlay, rotation handle and size labels when selected. `furnitureRotationHandlePos()` gives the handle position; the gesture code uses the same function for hit-testing. |

**Vocabulary**

- **World units** ("units"): the internal plan coordinates. `mmPerUnit = 5.0` (from `sketch_constants.dart`), so 1 unit = 5 mm and `unitsPerMeter = 200`. World x points right and **world y points down**: the world→screen transform has no Y flip.
- **Screen px**: logical pixels on the canvas. `screen = world * scale + panOffset` (`SketchPainter.worldToScreen`). The inverse lives in the screen: `screenToWorld(s) = (s - panOffset) / scale` (sketch_screen L277). Pixels from mm: `px = mm / 5 * scale`. The default `scale` is 0.35 (1 m = 70 px) and it is clamped to [0.001, 5.0] (`_minCanvasScale`/`_maxCanvasScale`, sketch_screen L63–64).
- **Shape / room**: a `SketchShape` (sketch_model.dart). It has `points` (world units), `isClosed`, `label`, `wallRealMm` (Map wall index → measured mm), `roomObjects`, `furnitureItems` and `heightMm`. **Wall *i*** of a shape is the segment `points[i] → points[(i+1) % n]`.
- **Merged wall**: a `Wall` object (wall_topology.dart) made by `buildWalls(shapes)` from **closed** shapes only. When two rooms overlap along an edge, the overlapping part becomes one `Wall` with two `sources`; each remaining free part becomes its own `Wall`.
- **Room object / opening**: a `RoomObject` (room_object.dart) of type `door`, `window` or `opening`. It sits on its owner's wall `wallIndex` at `positionAlong` (0..1), with `widthMm` and `swingFlipped`. `openingsForWall()` re-expresses it as a `ResolvedOpening` whose `positionAlong` is local to the merged wall.
- **Measured wall**: a wall index present in `shape.wallRealMm`. Its dimension label shows the real value in green.
- **Furniture item**: a free-floating rectangular footprint. Its centre is in **world units**, its size is in **mm**, and its rotation is in **degrees, clockwise on screen**.

```text
SketchScreen (sketch_screen.dart, owns all state)
  build(): _labelHitRects.clear(); _roomLabelHitRects.clear();
           CustomPaint(painter: SketchPainter(...32 named args...))
      │
      ▼
SketchPainter.paint(canvas, size)                         [sketch_painter.dart]
  1 _drawGrid → _drawAxes
  2 Pass 1 (per shape with ≥1 point): _drawSnapGuides → _drawRoom
        (fill, active outline, snap-candidate glow, dimension labels
         [_drawWallLengthLabel / _drawSegmentedWallDimension],
         open-shape wall bands, rubber band + live length, close ring)
  3 Pass 2: _drawAllWalls ── buildWalls()        [wall_topology.dart]
                         └─ openingsForWall()   [wall_openings.dart]
        union(thickWallRect bands) − opening holes → fill #1A1A1A
        → _drawOpeningSymbol (_drawDoor / _drawWindow) → _drawConflictHighlight
  4 Pass 3 (per shape): [closed] drawFurnitureItem() ×N → _drawRoomLabel
                        → _drawPoints → _drawAngleIndicator
                        → _drawNearestSnapLine → _drawMiddlePointAngles
  5 _drawSnapCursor(active shape)
      │  side effects: labelHitRects.add(...), roomLabelHitRects.add(...)
      ▼
SketchScreen._onTapDown reads the hit rects → wall-edit dialog / rename dialog

drawFurnitureItem(), furnitureRotationHandlePos()      [furniture_painter.dart]
  uses FurnitureItem / FurnitureType                    [furniture_item.dart]
  uses mmPerUnit                                        [sketch_constants.dart]
FurnitureItem is also used by: sketch_model, sketch_screen, database_helper,
  collaboration_screen, sketch_pdf_export, dxf_exporter, dxf_preview_screen,
  room_3d_screen (each has its own simplified furniture rendering)
```

### 6.2 Features and how they work

#### 6.2.1 Frame composition (paint order)

- **Trigger:** every `setState` in `_SketchScreenState` rebuilds the widget. A new `SketchPainter` is built (sketch_screen L3087) and `shouldRepaint` always returns `true` (L1207), so the whole plan is repainted from scratch after every rebuild: pointer move, zoom, selection, and so on.
- **Order inside `paint(Canvas, Size)`** (L105). Later steps paint on top of earlier ones:
  1. `_drawGrid` (L880), then `_drawAxes` (L918).
  2. **Pass 1:** for each shape index `s` with `points.isNotEmpty`, run `_drawSnapGuides` (active shape only) and then `_drawRoom(canvas, shape, isActive, s)`.
  3. **Pass 2:** `_drawAllWalls(canvas, shapes)` draws every closed-room wall once, with openings cut once.
  4. **Pass 3:** for each shape with points:
     - if `isClosed`, call `drawFurnitureItem(...)` for every item in `shape.furnitureItems`, with `isSelected: item.id == selectedFurnitureId`, then `_drawRoomLabel`;
     - then always `_drawPoints`, `_drawAngleIndicator`, `_drawNearestSnapLine` and `_drawMiddlePointAngles`. These last three return early unless the shape is active and in the right mode.
  5. If `shapes` is not empty, `_drawSnapCursor(canvas, shapes[activeIndex])`.
- **Background:** the painter paints none. The white comes from the `Scaffold(backgroundColor: 0xFFFFFFFF)` in sketch_screen L3071.
- **Result of this order:**
  - Furniture, room labels and vertex dots appear **above** walls.
  - Anything drawn in pass 1 that overlaps a closed room's wall band ends up **under** the opaque walls. This affects the active-room outline, the snap-candidate glow and the dimension lines of closed rooms; see 6.5.
  - Rooms later in `shapes` paint over earlier rooms' labels and furniture within pass 3.

#### 6.2.2 Viewport, grid and axes

- **Transform:** `worldToScreen(world) = world * scale + panOffset` (L82). It is passed as a function tear-off to the furniture painter.
- **Grid** (`_drawGrid` L880):
  - Nothing is drawn when `scale < 0.15`.
  - Spacing is `minorSpacing = minorGrid * scale` and `majorSpacing = majorGrid * scale`. The screen passes the constants `minorGrid = 40` units (200 mm) and `majorGrid = 200` units (1 m).
  - Minor lines are drawn if `minorSpacing > 4` px: colour `0xFFE6E6E6`, width 0.6.
  - Major lines are drawn if `majorSpacing > 4` px: colour `0xFFC8C8C8`, width 0.9.
  - If `minorSpacing > 12` px, a filled dot of radius 1.5 (`0xFFD6D6D6`) is drawn at every minor intersection.
  - Lines start at `panOffset.dx % spacing` and `panOffset.dy % spacing` (`_drawGridLines` L907), so they stay aligned to world multiples.
  - At the default zoom (0.35), minor spacing is 14 px, major spacing is 70 px, and dots are on.
- **Axes** (`_drawAxes` L918): the world x-axis (screen y = `panOffset.dy`) and y-axis (screen x = `panOffset.dx`) in `0xFFAAAAAA`, width 1.5. Each is drawn only if it is inside the canvas.

#### 6.2.3 Room fill, active outline and room label

- **Trigger:** any shape with points (fill); any closed shape (label).
- **Fill** (`_drawRoom` L955, step "1"):
  - Only for closed shapes with ≥ 3 points.
  - The polygon is built from the screen-space vertices (wall centrelines).
  - Colour `0xFF00AAFF` at opacity **0.07** if active, **0.03** otherwise.
- **Active outline:**
  - The same polygon is stroked in `0xFF00AAFF` @0.5, width 2.0.
  - It is drawn in pass 1, so the opaque wall band covers it whenever the on-screen wall thickness (30 × scale px) is ≥ 2 px. In practice it is invisible.
- **Room label** (`_drawRoomLabel` L504, pass 3, every closed shape with ≥ 3 points):
  - Centroid = arithmetic mean of the vertices (not the area centroid).
  - Area = shoelace sum `Σ(xᵢ·yᵢ₊₁ − xᵢ₊₁·yᵢ)`; `|sum|/2` gives world units², × `mmPerUnit²` gives mm², ÷ 1e6 gives m². It is printed as `"${m2.toStringAsFixed(2)} m²"`.
  - Name = `shape.label`, or `'Room'` if the label is empty.
  - Name style: `0xFF333333`, 13 px, `fontFamily: 'monospace'`, bold. Area style: `0xFF666666`, 10 px, monospace. The two lines are stacked with a 3 px gap and centred on the centroid.
  - A tap target `Rect.fromCenter(center, width: max(nameW, areaW) + 20, height: totalH + 14)` is appended to `roomLabelHitRects` together with `shapeIndex`. `SketchScreen._onTapDown` (L2573) opens the rename dialog for any room whose label is tapped.

#### 6.2.4 Walls: one unified wall mass, shared walls and opening cut-outs

- **Trigger:** every frame, in pass 2 (`_drawAllWalls` L1209).
- **Steps:**
  1. `walls = buildWalls(shapes)`. Only closed shapes take part. Edge parts that overlap collinearly between two rooms become a single shared `Wall`; the rest become single-source walls.
  2. Each wall becomes a band `thickWallRect(wall.a, wall.b, wallThickness)`:
     - `wallThickness = 30` units = **150 mm**;
     - corners are `[a+p, b+p, b−p, a−p]` with `p = (−dy, dx)/len · 15`, i.e. the band is centred on the edge;
     - the corners are mapped to screen and every band is unioned into one `Path` with `Path.combine(PathOperation.union, …)`.
  3. For each wall, `openingsForWall(wall, shapes)` gives `WallOpenings(openings, hasConflict)`. For each `ResolvedOpening`, `_openingHoleScreen` (L1260) builds a world-space rectangle and subtracts it from the union (`PathOperation.difference`). The rectangle:
     - is centred at `wall.a + (wall.b − wall.a) * positionAlong`;
     - extends `± (widthMm / mmPerUnit) / 2` along the wall;
     - extends `± 0.6 · wallThickness` (18 units, 90 mm) across it, slightly more than the band's half-thickness of 15 units, so the cut goes fully through.
  4. The result is filled with **`0xFF1A1A1A`**.
  5. For each wall, each opening gets `_drawOpeningSymbol` (6.2.5). If `hasConflict` is true, `_drawConflictHighlight` (L1337) strokes the outline of a band 1.15× as thick (`thickWallRect(a, b, wallThickness * 1.15)`) in amber `0xFFEF9F27`, width 2.5. A conflict means openings from different owner rooms overlap on the same merged wall.
- **Why the union:** neighbouring rooms' bands overlap on shared walls. Cutting holes after the union makes a door owned by one room go through both rooms' bands. `shape.sharedWalls` (sketch_model) is **not** read by the painter; shared walls are derived purely from geometry each frame.
- **Open (unfinished) shapes** are not in `buildWalls`. `_drawRoom` draws each segment `points[i]→points[i+1]` as its own `thickWallRect` band in `0xFF1A1A1A`, with no cut-outs (L1041–1061).
- **What the user sees:** solid dark walls 150 mm thick, centred on the drawn lines, with clean gaps where doors, windows and openings are. Wall ends are butt-cut rectangles, so outer corners show a small square notch (see 6.5).

#### 6.2.5 Door, window and opening symbols; opening selection

`_drawOpeningSymbol(canvas, wall, opening)` (L1281):

- **Geometry:**
  - `centreScreen` = screen position of `wall.a + (wall.b − wall.a)·positionAlong`.
  - `dir` = unit screen vector a→b (falls back to (1,0) if it is under 1 px).
  - `perp = swingFlipped ? (dir.dy, −dir.dx) : (−dir.dy, dir.dx)`.
  - `halfWScreen = (widthMm / mmPerUnit / 2) · (screenLen / worldLen)`, i.e. world half-width × scale.
- **Selection** (`opening.source.id == selectedObjectId`): a quad is filled with `0xFF0099FF` @0.08 and stroked with `0xFF0099FF`, width 1.5. Its extent:
  - along `dir`: `±(halfW + 6)` px;
  - across: from `−4` px on the −perp side to `halfW + 6` px on the +perp side.
- **Door** (`_drawDoor` L1353):
  - Colour: `0xFF1A1A1A`, or orange `0xFFFF8800` when selected.
  - The hinge is at `centre − dir·halfW`, always the wall-`a` end of the opening. The tip is at `centre + dir·halfW`. The radius is `2·halfW` (the full door width).
  - Lines (width 2.0 if selected, 1.5 otherwise): the **leaf**, from the hinge to `hinge + perp·radius`; and the **closed-position line**, from the hinge to the tip along the wall centreline.
  - **Swing arc:** a quarter circle around the hinge from angle `leafAngle + sweepAngle` with sweep `−sweepAngle`, width 1.5 if selected, 1.0 otherwise. `leafAngle = atan2(tip − hinge)`. `sweepAngle = ±π/2`, whichever of `leafAngle ∓ π/2` is closer (after wrapping) to `atan2(perp)`. The arc therefore runs from the open-leaf tip to the closed position.
- **Window** (`_drawWindow` L1414):
  - Colour `0xFF0099CC`, or orange when selected.
  - `spread = wallThickness · scale · 0.4` (12·scale px).
  - Three lines parallel to the wall across the full opening width, offset by −0.5, 0 and +0.5 × spread. The middle line has width 2.0 and the outer lines 1.0.
- **Plain opening** (`RoomObjectType.opening`): nothing extra is drawn. The cut gap is the whole symbol (code comment L1333–1334).

#### 6.2.6 Wall dimension labels (plain walls) — placement algorithm

- **Trigger:**
  - Pass 1, for the **active** shape only.
  - Closed shapes: every wall that has no `RoomObject` on it (L1022–1034).
  - Open shapes: every drawn segment (L1053–1060).
  - The rubber-band segment (6.2.8).
- **Function:** `_drawWallLengthLabel(canvas, fromWorld, toWorld, {centroid, overrideMm, isSelected=false, wallIndex=-1, shapeIndex=-1})` (L152). Steps:
  1. **Visibility gates:** return if the world length is < 5 units (25 mm) or the screen length is < 28 px.
  2. **Axes in screen space:** `u = (to − from)/|to − from|`, normal `n = (−u.y, u.x)`.
  3. **Outside test:** let `c` = screen centroid and `m` = wall midpoint. If `(c − m)·n > 0`, flip `n`, so the dimension always lies on the side away from the centroid ("outside the room"). For closed shapes the centroid is the vertex mean. For an open active shape the cursor position is added to the mean (L973–984).
  4. **Constants (screen px, independent of zoom):**
     - `dimOffset = 26.0` (wall centreline to dimension line)
     - `extGap = 3.0`
     - `extOverrun = 5.0`
     - `arrowSize = 6.0`
  5. **Colour (`dimColor`):**
     - **green `0xFF00AA44`** if `overrideMm != null`, i.e. the wall has a measured length in `wallRealMm`;
     - else **orange `0xFFFF8800`** if `isSelected` (`i == selectedWallIndex`);
     - else **blue `0xFF2255CC`**.
  6. **Extension lines:** dashed (4 px dash, 3 px gap; local closure `drawDashedLine`, L202), in `dimColor` @0.7, width 0.7. They run from `endpoint + 3n` to `endpoint + 31n` at both wall ends.
  7. **Dimension line:** solid, `dimColor`, width 0.8, from `from + 26n` to `to + 26n`.
  8. **Arrowheads** (closure `drawArrow`, L250): filled triangles 6 px long and ±2.1 px (0.35 × 6) wide. The tips sit on the dimension-line ends and point **outward** toward the extension lines. The inline comments "pointing toward dTo/dFrom" are wrong.
  9. **Text:**
     - `formatLength(overrideMm / mmPerUnit)` if measured, else `formatLength(worldLength)`. `formatLength` gives `"x.xx m"` for ≥ 1000 mm, otherwise `"N mm"`.
     - Style: 9 px, monospace, bold, colour orange if `isSelected` (even when `dimColor` is green), else `dimColor`.
     - The canvas is translated to the dimension-line midpoint and rotated by `atan2(u.y, u.x)`. π is added when that angle is outside [−π/2, π/2], so text is never upside down.
     - A white (`0xFFFFFFFF` @0.92) box of `(textW + 8) × (textH + 4)` is drawn behind the text.
  10. **Hit target:** only if `wallIndex >= 0`, append `(rect: Rect.fromCenter(mid, width: textW + 18, height: 24), wallIndex, shapeIndex)` to `labelHitRects`. The rect is axis-aligned, not rotated. `SketchScreen._onTapDown` (L2560) makes that shape active, selects the wall and opens `showSketchWallEditDialog(wallIndex)`.
- **What the user sees:** architectural dimensions 26 px outside each wall of the active room. Blue means drawn length, green means measured length, orange means selected.

#### 6.2.7 Segmented dimensions for walls with doors/windows

- **Trigger:** an active closed shape whose wall *i* has at least one `RoomObject` with `wallIndex == i`. `_drawRoom` then calls `_drawSegmentedWallDimension(canvas, shape, i, centroid!)` (L314).
- **Algorithm:**
  1. Set `L` = world length (return if < 5). Sort that wall's objects by `positionAlong`.
  2. Build the segments. For each object:
     - `halfT = (widthMm/mmPerUnit/2)/L`, `tS = clamp(pos − halfT, 0, 1)`, `tE = clamp(pos + halfT, 0, 1)`;
     - if `tS − prevT > 0.001`, add a **gap** segment `[prevT, tS]` labelled `formatLength(gapWorldLength)`;
     - add an **object** segment `[tS, tE]` labelled `formatLength(widthMm/mmPerUnit)` (the full nominal width, even if clamped);
     - set `prevT = tE`.
     
     After the loop, add a final gap if `1 − prevT > 0.001`. Each segment is the record `(Offset start, Offset end, String label, bool isObject, bool isLocked)`. `isLocked = widthMm > 0` is never used.
  3. **Total:** `_drawWallLengthLabel(wA, wB, centroid, overrideMm: wallRealMm[i], isSelected: false, wallIndex: -1)`. It is drawn at 26 px, green when measured, **with no hit rect and never orange**.
  4. **Segments:** drawn at `segDimOffset = 14` px on the same outward side, using the same centroid test. Segments shorter than 8 px on screen are skipped. For each segment:
     - colour `0xFF0066CC` for objects, `0xFF2255CC` for gaps;
     - tick marks from 10 to 18 px (±4 around 14), width 0.8;
     - dimension line at 14 px, width 0.8;
     - outward-pointing filled arrows 5 px long (closure `drawSegArrow`, L461);
     - label: 8 px monospace, bold for objects, **not rotated** (always horizontal), on a white @0.92 box of `(textW + 4) × (textH + 2)`. The label is drawn only if the segment is longer than `textW + 10` px.
- **What the user sees:** two rows of dimensions. The outer row is the total wall length; the inner row is the chain gap–door–gap and so on. Segment values come from the drawn geometry, while the total uses `wallRealMm` when present.

#### 6.2.8 Live drawing aids (rubber band, angle snapping, cursor, close-loop ring)

These depend on screen state computed in sketch_screen. Angles there use **mathematical convention**: degrees in 0–360, counter-clockwise, y up, from `_computeAngleDeg` (sketch_screen L1017), which negates dy. The painter therefore converts an angle `a` to a screen direction as `(cos a, −sin a)`. `snapAngles` = `[0, 30, 45, 60, 75, 90, 105, 120, 135, 150, 180, 210, 225, 240, 255, 270, 285, 300, 315, 330]`. Snapping happens within `snapThresholdDeg = 3°`.

- **Rubber band** (`_drawRoom` L1064–1086):
  - Conditions: active, open shape, `cursorWorld != null`, `activePointIndex < 0`.
  - A line from the last vertex to the cursor: `0xFF00AAFF` width 1.5, or green `0xFF00CC44` width 2.0 when `isAngleSnapped`; round caps.
  - A live length label `_drawWallLengthLabel(points.last, cursorWorld, centroid)`: blue, no hit rect.
  - If the shape has ≥ 3 points and `|cursor − first| < snapRadiusWorld` (15 units = 75 mm), a green ring (radius 14 px, width 2.0) is drawn around the first vertex. This is the "close the room" hint.
- **Snap guide rays** (`_drawSnapGuides` L734, pass 1, active shape only):
  - **Vertex-edit mode** (`activePointIndex >= 0`): faint rays 2000 px long from that vertex in all 20 snap directions, `0xFFFFAA00` @0.07, width 1.0.
  - **Drawing mode** (open shape, with `angleRefWorld`, `angleTargetWorld` and `currentAngleDeg` set): the same rays from `angleRefWorld` in `0xFF00AAFF` @0.06. The `snappedAngle` ray is emphasised in green @0.35 if snapped, else `0xFF00AAFF` @0.20, width 1.5. The screen sets `_snappedAngle` to the nearest angle even when it is not snapped.
- **Angle indicator** (`_drawAngleIndicator` L789, active shape, `activePointIndex < 0`, reference-to-target distance ≥ 5 px):
  - Arc radius 22 px around the reference point, from screen angle 0 to `atan2(dy, dx)` in screen coordinates (the short way). Colour green if snapped, else `0xFF888888`; width 1.5.
  - A short baseline tick from `ref + (18, 0)` to `ref + (28, 0)`, `0xFF888888` @0.5.
  - A label at radius 38 px, at half the arc angle:
    - text: snapped → `snappedAngle` with 0 decimals; else `currentAngleDeg` with 1 decimal, followed by `°`;
    - style: 11 px monospace, green or `0xFF666666`, bold if snapped;
    - box: rounded rect (r = 3) `0xFFFAFAFA` @0.92 with a green @0.4 or `0xFFCCCCCC` border.
  - When snapped, an extra ring at radius 26 px, green @0.15, width 3.0.
- **Nearest-snap line** (`_drawNearestSnapLine` L574, pass 3):
  - Conditions: active, open shape, `activePointIndex < 0`, and `snapDiffDeg ≤ 6`.
  - Opacity factor `o = clamp(1 − diff/20, 0, 1)`, which lies in 0.7–1.0 here.
  - A 2000 px ray at `nearestSnapAngleDeg`: green @0.5·o width 2.0 if snapped, else `0xFFFFAA33` @0.45·o width 1.5; round cap.
  - A `"N°"` label 120 px along the ray: 11 px monospace bold, on a `0xFFFAFAFA` @0.85·o rounded box.
- **Snap cursor** (`_drawSnapCursor` L931, end of frame):
  - Conditions: active shape open, `cursorWorld` set, `activePointIndex < 0`.
  - A crosshair of ±8 px plus either a diamond (±10 px, when angle-snapped) or a 10×10 square.
  - Colour green width 1.5 when snapped, else `0xFF00AAFF` width 1.0.

#### 6.2.9 Vertex markers and vertex-edit angle labels

- **Vertex markers** (`_drawPoints` L1089, pass 3, every shape):
  - **Radius:** `pointRadius(r) = max(0.75, r · scale · 3.0)`, so marker sizes **scale with zoom**. The base sizes `r` are:

    | Vertex kind | `r` | Radius at scale 0.35 |
    |---|---|---|
    | normal | 4 | 4.2 px |
    | first | 6 | 6.3 px |
    | active, or last of the active open shape | 7 | 7.35 px |
    | glow (`lastPointGlowRadius`) | 28 | 29.4 px |
    | ring (`lastPointRingRadius`) | 14 | 14.7 px |
    | snap target | 20 | 21 px |

  - **Snap target** (`i == snapTargetIndex`, active shape): a green @0.25 fill and a green stroke (width 2.0) at `pointRadius(20)`.
  - **Active (edited) vertex:** an orange `0xFFFF6600` glow @0.10, a ring @0.30, and a ring stroke of width 1.5.
  - **Last vertex of the active open shape:**
    - glow: green @0.10 if angle-snapped, else orange @0.08;
    - ring fill: green @0.25 if snapped, else orange @0.35 while `isDraggingLastPoint`, else orange @0.15;
    - ring stroke: green or orange, width 1.5.
  - **Dot colours:**
    - active vertex: orange;
    - active open shape's last vertex: green if snapped, else orange;
    - **first vertex of every shape: green `0xFF00CC44`**;
    - all others: white fill with a `0xFF1A1A1A` border.
    - Every dot border has width 2.0.
- **Vertex-edit wall angles** (`_drawMiddlePointAngles` L701):
  - Conditions: active shape with `0 ≤ activePointIndex < points.length`.
  - The previous and next vertices are found, wrapping round for closed shapes.
  - `_drawWallAngleLabel` (L634) is called for prev→active (with `prevWallAngle`/`prevWallSnapped`) and for active→next (with `nextWallAngle`/`nextWallSnapped`).
  - Placement: wall midpoint + 20 px along `(−dy, dx)/len`. This normal is not flipped, so the side depends on the wall direction.
  - The label shows the nearest snap angle (0 decimals) if it is snapped or within 3.0° (`_nearestSnapAnglePure`, L84), otherwise the raw angle with 1 decimal.
  - Style: 12 px monospace, green and bold, or `0xFF888888`.
  - Box: rounded rect (r = 4) `0xFFFAFAFA` @0.95, with a border that is green width 1.5 or `0xFFCCCCCC` width 1.0. When snapped, a green dot of radius 3 sits at the box's top-right corner (inset 5 px).

#### 6.2.10 Painter → screen feedback (tap targets)

- `labelHitRects` (type `List<({Rect rect, int wallIndex, int shapeIndex})>`) and `roomLabelHitRects` (type `List<({Rect rect, int shapeIndex})>`) are **mutable lists owned by `_SketchScreenState`** (L100–101).
- The screen clears them at the start of `build()` (L3062–3063). The painter appends to them during `paint()`.
- `_onTapDown` (L2556) tests them right after its multi-touch guard and **before** all other tap logic (move mode, furniture placement, selection): dimension labels first, then room labels.
- Only plain-wall dimension labels and open-shape segment labels register targets. Rubber-band labels and the totals of segmented walls do not.

#### 6.2.11 Furniture placement and rendering on the plan

- **Placing an item** (logic in sketch_screen, listed here for context):
  1. In the furniture picker sheet (L2918–2953), a 4-column grid of all `FurnitureType.values` in enum order shows each type's `icon`, `displayName` and `color`. Tapping a type sets `_furniturePlacingType` and shows a strip saying "Placing {displayName} — tap inside room" (L3364–3394).
  2. The next tap inside the active **closed** room (`_pointInsidePolygon`) adds `FurnitureItem(id: 'fur_$_furnitureCounter', type, position: screenToWorld(tap))`. The size comes from `defaultSizeMm` and the rotation is 0 (L2589–2608).
  3. A tap outside the room cancels placement.
  4. The painter draws **no ghost preview** during placement.
- **Rendering** (`drawFurnitureItem`, furniture_painter.dart L20). Pass 3 calls it for every item of every **closed** shape, active or not.
  1. `center = worldToScreen(item.position)`; `w = widthMm / mmPerUnit · scale` and `d = depthMm / mmPerUnit · scale` in px.
  2. **If `w < 4` or `d < 4`, return.** Nothing is drawn, not even the selection UI.
  3. `canvas.save()`, `translate(center)`, then `rotate(rotationDeg · π/180)`. Positive rotation is **clockwise on screen** because y points down.
  4. `_drawSymbol(canvas, type, w, d, isSelected)` dispatches to a per-type symbol (table in 6.3.3). Symbols are drawn in local coordinates centred on the item: x across the width, y across the depth. The "back" of seating and beds (sofa back, bed headboard, chair back arc, toilet tank) is at local −y, which is screen-top at 0°.
  5. If selected, `_drawSelectionOverlay` runs while the canvas is still rotated.
  6. `canvas.restore()`. If selected, the rotation handle and dimension labels are drawn in un-rotated screen space (6.2.12).
- **Plan styling:**
  - Symbols are monochrome. **`FurnitureType.color` is not used on the 2D plan.**
  - Fill: `_fill` = `0xFFF7F7F7`, or `0xFFE3F2FD` when selected.
  - Outline: `_stroke` = `0xFF222222`, or `0xFF1565C0` when selected; width 1.5 by default.
  - Detail lines: `_detail` = `0xFF444444`, width 0.8, round cap. Not selection-dependent.
  - Accent strips use `0xFFDDDDDD`/`0xFFCCCCCC` (`0xFF90CAF9` when selected). Chair seats use `0xFFEEEEEE` (`0xFFBBDEFB` when selected).
  - All stroke widths are fixed in px; they do not scale with zoom.
- **Moving, rotating and resizing** (sketch_screen):
  - **Drag:** dragging inside a selected item moves its `position` by the world-space pointer delta each move event (L2094–2109).
  - **Rotate with the handle:** `rotationDeg = (startDeg + Δangle) % 360` (L2076–2092). Δangle is the change in `atan2` of the finger relative to the item centre.
  - **Rotate with the toolbar:** buttons rotate by ±45° (L3245–3296).
  - **Pinch:** a two-finger pinch scales width and depth by `d.scale`, clamped to 100–6000 mm (L2480–2496).
  - **Size dialog:** values are entered in cm and clamped to 100–6000 mm. "Reset" restores `defaultSizeMm` (L1386–1460).
  - Every change is a `copyWith` replacement. No code mutates the fields in place.

#### 6.2.12 Furniture selection visuals: overlay, rotation handle, size labels, hit-testing

- **Selection overlay** (`_drawSelectionOverlay` L146, in the rotated local frame):
  - A dashed rectangle of size `(w + 4) × (d + 4)` (6 px dash, 4 px gap, via `_drawDashedRect` L170 using `PathMetric.extractPath`) in `0xFF1976D2`, width 1.5.
  - Four 8 × 8 px squares at `(±(w/2 + 2), ±(d/2 + 2))`, filled `0xFF1976D2` with a white stroke of width 1.5. These "corner resize handles" are **decorative only**: no gesture code hit-tests them.
- **Rotation handle** (screen space, never rotated):
  - Position: `furnitureRotationHandlePos` (L9) = `center − (0, max(wPx, dPx)/2 + 52)`, i.e. straight above the item on screen.
  - A stem line from the centre to the handle in `0xFF1976D2` @0.6, width 1.2.
  - A filled circle of radius 22 px in `0xFF1565C0` with a white width-2.5 rim.
  - A white arc glyph inside a 26 × 26 rect: start −0.8π, sweep 1.4π, width 2.0, round cap, no arrowhead.
  - Gesture hit test: `SketchScreen._onPointerDown` (L1967–1990) starts a rotation when the pointer is **within 50 px** of the same handle position. It tests this before body drag and before door/window hits.
- **Size labels** (`_drawDimensionLabels` L79, screen space):
  - The local axes are mapped to screen as +x → `(cos θ, sin θ)` and +y → `(−sin θ, cos θ)`.
  - **Width label**: `"${(widthMm/10).round()} cm"` at `center + localY · (dPx/2 + 16)`, beside the edge that runs along the width.
  - **Depth label**: `"${(depthMm/10).round()} cm"` at `center + localX · (wPx/2 + 16)`.
  - Drawn by `_drawDimLabel` (L100): text in `0xFF1565C0`, 10 px, bold, `letterSpacing: 0.3`, **default font** (not monospace). The box is a rounded rect (r = 3) of `(textW + 8) × (textH + 4)`, filled `0xDDE3F2FD` and stroked `0xFF1565C0` at width 0.8. Text is not rotated.
- **Body hit test** (sketch_screen `_isInsideFurnitureItem` L1198):
  1. Take the tap vector relative to the item centre and rotate it by `−rotationDeg`.
  2. The tap is inside if `|x| ≤ w/2 + 10` and `|y| ≤ d/2 + 10` px.
  
  This matches the painter's rotation convention. Round symbols and the chairs drawn around dining tables do not match this rectangle exactly.

#### 6.2.13 How furniture appears outside the plan canvas (other renderers)

None of these renderers uses `furniture_painter.dart`. Each one has its own simplified drawing:

- **PDF** (`sketch_pdf_export.dart`):
  - `_paintFurniture` (L669): the rotated footprint rectangle, filled with a lightened type colour (`0.65 + c·0.35` per channel), a border at `c·0.7` width 0.8, and a diagonal **X** at `c·0.5` width 0.4.
  - `_furnitureTable` (L1108): a table with columns `#`, `Item` (`displayName`), `W`, `D` (mm).
- **DXF** (`dxf_exporter.dart` `_writeFurniture` L300):
  - Layer `FURNITURE`: four `LINE`s (ACI colour 3) and two diagonals (colour 8).
  - A `TEXT` of `displayName` at the centre, height 40, rotation 0.
  - Y is flipped (`_wy`) and the rotation is converted to match.
- **DXF preview** (`dxf_preview_screen.dart` `_drawFurnitureItem` L576): a dark-green rectangle and X, plus a `displayName` label at 7.5 px.
- **3D/Three.js** (`room_3d_screen.dart` `_buildHouseJson` L162): JSON with metres (`toM = mmPerUnit/1000 = 0.005`), `heightM` from `type.heightMm` and `colorHex` from `type.color`. GLB models come from `_modelPathForType` (L126); types with no model fall back to a box (comment L117).
- **Legacy 3D painter** (`_Room3DPainter` L746): extruded boxes using `heightMm`, `color` and `displayName`.

### 6.3 File reference

#### `code/lib/sketch/sketch_painter.dart` — 1435 lines

**Purpose:** `SketchPainter` renders the whole 2D sketch canvas for all rooms: grid, rooms, walls with openings, door and window symbols, dimensions, labels, vertex markers, live drawing and snapping aids, and furniture (delegated). As a side effect it collects tap targets for dimension and room labels.

**Depends on:**
- `package:flutter/material.dart`: `CustomPainter`, `Canvas`, `Paint`, `Path`, `TextPainter`, `Color`, `Offset`, `Rect`, `RRect`.
- `dart:math as math`: `sqrt`, `atan2`, `cos`, `sin`, `pi`, `min`, `max`.
- `furniture_painter.dart`: `drawFurnitureItem`.
- `sketch_constants.dart`: `mmPerUnit`, `formatLength`, `wallThickness`, `thickWallRect`.
- `sketch_model.dart`: `SketchShape`.
- `wall_topology.dart`: `buildWalls`, `Wall`.
- `wall_openings.dart`: `openingsForWall`, `WallOpenings`, `ResolvedOpening`.
- `RoomObject` members (`widthMm`, `positionAlong`, `wallIndex`, `id`, `isDoor`, `isWindow`, `swingFlipped`) are reached through `shape.roomObjects` and `ResolvedOpening.source`; `room_object.dart` is not imported directly.

**Declarations:**

`class SketchPainter extends CustomPainter` (L9). It has a `const` constructor (L46) with **32 required named parameters**, all stored in `final` fields. The list fields are mutated in place.

| Field | Type | Meaning (value supplied by `SketchScreen`, L3087–3120) |
|---|---|---|
| `panOffset` | `Offset` | Screen position (px) of the world origin (`_panOffset`). |
| `scale` | `double` | px per world unit (`_scale`; default 0.35, range 0.001–5.0). |
| `minorGrid` | `double` | Minor grid spacing in world units (constant 40 = 200 mm). |
| `majorGrid` | `double` | Major grid spacing (constant 200 = 1 m). |
| `shapes` | `List<SketchShape>` | All rooms. The comment L15 notes this replaced older single-room fields. |
| `activeIndex` | `int` | Index of the active room. |
| `cursorWorld` | `Offset?` | Current (snapped) drawing cursor in world units. |
| `snapRadiusWorld` | `double` | Close-loop radius in world units (constant 15). |
| `isDraggingLastPoint` | `bool` | The last vertex of the open shape is being dragged. |
| `lastPointGlowRadius` | `double` | Constant 28, passed through `pointRadius()`. |
| `lastPointRingRadius` | `double` | Constant 14, passed through `pointRadius()`. |
| `snappedAngle` | `double?` | Nearest snap angle of the current segment (deg, math convention). Set even when not snapped. |
| `isAngleSnapped` | `bool` | Current segment is within 3° of `snappedAngle`. |
| `currentAngleDeg` | `double?` | Raw angle of the current segment, 0–360° counter-clockwise, y up. |
| `nearestSnapAngleDeg` | `double?` | Nearest snap angle (same value as `snappedAngle`). |
| `snapDiffDeg` | `double?` | Angular distance to the nearest snap angle. |
| `angleRefWorld` | `Offset?` | Segment start: the second-to-last point while dragging the last point, otherwise the last point (computed in `build`, L3035–3046). |
| `angleTargetWorld` | `Offset?` | Segment end: the last point or the cursor. |
| `snapAngles` | `List<double>` | The 20 snap angles from `sketch_constants.dart`. |
| `activePointIndex` | `int` | Vertex being edited in the active shape; −1 when none. |
| `snapTargetIndex` | `int?` | Vertex that the dragged point would snap onto. |
| `prevWallAngle` | `double?` | Angle of the wall ending at the active vertex. |
| `nextWallAngle` | `double?` | Angle of the wall starting at the active vertex. |
| `prevWallSnapped` | `bool` | Whether the previous wall angle is snapped. |
| `nextWallSnapped` | `bool` | Whether the next wall angle is snapped. |
| `selectedWallIndex` | `int` | Selected wall of the active shape (−1 when none). Only changes label colour. |
| `snapCandidateShape` | `int` | During move mode, the index of the *other* room whose wall is the merge candidate (`candidate.os`). |
| `snapCandidateWall` | `int` | Wall index on that room (`candidate.ow`). |
| `labelHitRects` | `List<({Rect rect, int wallIndex, int shapeIndex})>` | **Output**: tap targets of dimension labels. |
| `selectedObjectId` | `String?` | Selected `RoomObject` id. |
| `selectedFurnitureId` | `String?` | Selected `FurnitureItem` id. |
| `roomLabelHitRects` | `List<({Rect rect, int shapeIndex})>` | **Output**: tap targets of room labels. |

**Methods** (descriptions of what each draws are in 6.2; listed here with signatures):
- `Offset worldToScreen(Offset world)` (L82): `world * scale + panOffset`. Public, and passed as a tear-off to `drawFurnitureItem`.
- `(double, double) _nearestSnapAnglePure(double angleDeg)` (L84): returns `(nearest snap angle, diff)` with wrap-around (`diff > 180 → 360 − diff`). Initialised from `snapAngles.first`, so it would throw on an empty list. It duplicates `_nearestSnapAngle` in sketch_screen (L1025).
- `double _worldDist(Offset a, Offset b)` (L98): Euclidean distance. Despite the name it is also used on screen points.
- `void paint(Canvas canvas, Size size)` (L105): the pass structure in 6.2.1.
- `void _drawWallLengthLabel(Canvas, Offset fromWorld, Offset toWorld, {Offset? centroid, double? overrideMm, bool isSelected = false, int wallIndex = -1, int shapeIndex = -1})` (L152): plain dimension (6.2.6). Local closures `drawDashedLine(Offset a, Offset b)` (L202) and `drawArrow(Offset tip, double dirX, double dirY)` (L250).
- `void _drawSegmentedWallDimension(Canvas, SketchShape shape, int wallIndex, Offset centroid)` (L314): chain dimensions (6.2.7). Local closure `drawSegArrow` (L461).
- `void _drawRoomLabel(Canvas, SketchShape shape, int shapeIndex)` (L504): name and area at the vertex centroid; registers the room hit rect.
- `void _drawNearestSnapLine(Canvas, Size size, SketchShape shape, bool isActive)` (L574): fading ray and label toward the nearest snap angle. `size` is unused.
- `void _drawWallAngleLabel(Canvas, Offset fromScreen, Offset toScreen, double angleDeg, bool isSnapped)` (L634): angle badge beside a wall.
- `void _drawMiddlePointAngles(Canvas, SketchShape shape, bool isActive)` (L701): calls `_drawWallAngleLabel` for the two walls adjacent to the edited vertex.
- `void _drawSnapGuides(Canvas, Size size, SketchShape shape, bool isActive)` (L734): faint snap rays. `size` is unused.
- `void _drawAngleIndicator(Canvas, SketchShape shape, bool isActive)` (L789): arc, baseline tick, angle badge and snapped ring.
- `void _drawGrid(Canvas, Size)` (L880), `void _drawGridLines(Canvas, Size, double spacing, Paint paint)` (L907), `void _drawAxes(Canvas, Size)` (L918): background reference.
- `void _drawSnapCursor(Canvas, SketchShape activeShape)` (L931): crosshair cursor.
- `void _drawRoom(Canvas, SketchShape shape, bool isActive, int s)` (L955): fill, active outline, snap-candidate glow, dimension dispatch, open-shape wall bands, rubber band and close ring.
- `void _drawPoints(Canvas, SketchShape shape, bool isActive)` (L1089): vertex markers. Local `double pointRadius(double worldRadius)` (L1090).
- `bool shouldRepaint(SketchPainter oldDelegate)` (L1207): always `true`. It carries a duplicated `@override` annotation (L1205–1206).
- `void _drawAllWalls(Canvas, List<SketchShape> shapes)` (L1209): unified wall mass. The parameter shadows the field.
- `Path? _openingHoleScreen(Wall wall, ResolvedOpening opening)` (L1260): screen-space cut rectangle. Returns `null` if the wall is shorter than 1 unit.
- `void _drawOpeningSymbol(Canvas, Wall wall, ResolvedOpening opening)` (L1281): selection quad, then door, window or nothing.
- `void _drawConflictHighlight(Canvas, Wall wall)` (L1337): amber outline.
- `void _drawDoor(Canvas, Offset centre, Offset dir, Offset perp, double halfW, bool isSelected)` (L1353): door leaf, closed line and swing arc.
- `void _drawWindow(Canvas, Offset centre, Offset dir, double halfW, bool isSelected)` (L1414): three parallel lines.

**Key logic:**

- **Dimension side selection:** the centroid dot-product test, with constants 26/3/5/6 px for plain dimensions and 14/±4/5 px for segments; see 6.2.6 and 6.2.7.
- **Text orientation:** `angle = atan2(u.y, u.x)`; add π if `angle > π/2` or `angle < −π/2`. Only plain and total labels rotate.
- **Door sweep sign:** `wrap(x) = ((x + π) mod 2π) − π`. Dart `%` returns non-negative values, so the wrap is correct. `sweepAngle = |wrap(leafAngle − π/2 − perpAngle)| < |wrap(leafAngle + π/2 − perpAngle)| ? −π/2 : +π/2`. The arc is `drawArc(rect(hinge, 2r), leafAngle + sweepAngle, −sweepAngle)`.
- **Hole depth** is `±0.6 · wallThickness` (18 u). **Conflict outline** uses `1.15 · wallThickness`. **Window spread** is `0.4 · wallThickness · scale`.
- **Room area** comes from the shoelace sum as in 6.2.3. It always prints `toStringAsFixed(2)` m² and does not use `formatArea`.
- **Grid thresholds:** off below `scale < 0.15`; lines only when spacing > 4 px; dots only when minor spacing > 12 px.
- **Marker scaling:** `max(0.75, r · scale · 3)`.

**State and data:** the painter holds no state of its own. Its only outputs are the two hit-rect lists (record types above). It reads these model fields: `SketchShape.points`, `isClosed`, `label`, `wallRealMm`, `roomObjects` (`wallIndex`, `positionAlong`, `widthMm`), `furnitureItems`, `id` (indirectly, via `buildWalls`/`openingsForWall`). It ignores `sharedWalls` and `heightMm`.

**Connections:**
- Constructed only by `SketchScreen.build` (sketch_screen L3087), inside `CustomPaint(child: SizedBox.expand())`, which is wrapped in a `Listener` and a `GestureDetector`.
- Hit rects are consumed by `_onTapDown` (sketch_screen L2560, L2573).
- Calls `drawFurnitureItem` (furniture_painter L20), `buildWalls` (wall_topology L93), `openingsForWall` (wall_openings L20), and `thickWallRect`/`formatLength` (sketch_constants L21/L42).
- No other file imports `sketch_painter.dart`. The PDF, DXF preview and 3D views each have their own painters (`sketch_pdf_export.dart`, `_BlueprintPainter` in `dxf_preview_screen.dart` L273, `_Room3DPainter` in `room_3d_screen.dart` L746).

**Notes and issues:**
- **Rendering order:** pass 1 items are covered by pass 2 walls. This hides:
  - (a) the snap-candidate wall glow: 4 px green line (L1004–1019), invisible once the wall band is ≥ 4 px, i.e. `scale ≳ 0.13`;
  - (b) the active-room outline;
  - (c) closed-room dimension lines and labels when zoomed in: the half-thickness is `15·scale` px, so the 14 px segment dimension lines are covered above about `scale 0.93` (their labels completely by about 1.3), and 26 px totals start being covered around `scale ≈ 1.2` and are fully hidden around `scale ≈ 2.3` (max 5.0). Their hit rects stay active.
- Walls are butt-ended rectangles, so outer corners of non-collinear walls get a notch of up to half the wall thickness. There is no mitre or join logic.
- "Outside" detection and room-label placement use the vertex mean. Concave rooms can get inside-facing dimensions or a label outside the polygon.
- Segment labels are horizontal while totals are rotated. Segment values come from geometry, but the total uses `wallRealMm`, so the chain may not add up to the total.
- Walls that carry openings register no label hit target and never show the selected (orange) state.
- Hit rects are axis-aligned (`textW + 18` × 24) even when the label is rotated, e.g. vertical walls.
- The door hinge is always at the `wall.a` end. On a shared wall, `wall.a→b` follows the first room's edge direction (`buildWalls`), so doors owned by the second room may show mirrored hinge or swing sides compared with the same door on an unshared wall.
- The door selection quad extends only `halfW + 6` px toward the swing side, but the leaf reaches `2·halfW`.
- `_drawSnapGuides` indexes `shape.points[activePointIndex]` without an upper-bound check (L738). `_drawMiddlePointAngles` has the check, so a stale index could throw a `RangeError` here.
- Unused: local `gapMm` (L353), `wallDir` (L340), and the record field `isLocked`/`hasRealMm` (L360); the `size` parameters of `_drawSnapGuides`/`_drawNearestSnapLine`.
- Misleading comments:
  - arrow comments (L267–268, L486–487): the arrows actually point outward;
  - the "1./5." step numbering in `_drawRoom` and the "2./3./4." numbering in `_drawDoor` are leftovers.
- The angle-indicator arc is drawn the short way in screen space, while its label shows the 0–360° math angle. For example, a target below-right gives a 30° arc labelled "330.0°".
- `paint()` has side effects on caller-owned lists. If Flutter repaints without a rebuild, entries are duplicated. This is harmless for hit-testing but unbounded until the next `build`.
- **Per-frame cost** (always repaints):
  - `buildWalls` is O(E²) over all edges;
  - iterative `Path.combine` unions and differences;
  - up to about 10⁴ grid-dot `drawCircle` calls at default zoom;
  - many `TextPainter.layout` calls.
- All colours, offsets and font sizes are hard-coded. Plan annotations use `fontFamily: 'monospace'`. `Color.withOpacity` (used throughout) is deprecated in the Flutter version this codebase targets, since elsewhere it uses `toARGB32()`/`Color.r`, so `flutter analyze` reports deprecation infos.
- The 3.0° threshold in `_drawWallAngleLabel` is hard-coded rather than using `snapThresholdDeg`, which has the same value.

#### `code/lib/sketch/furniture_item.dart` — 262 lines

**Purpose:** the furniture catalogue and data model. `FurnitureType` lists the 31 placeable types. The extension gives each type a name, default footprint, 3D height, theme colour and icon. `FurnitureItem` is one placed instance.

**Depends on:** `package:flutter/material.dart` for `Offset`, `Color`, `IconData` and `Icons`. No internal imports.

**Declarations:**
- `enum FurnitureType` (L3), 31 values in this order:
  - Living: `sofa`, `armchair`, `coffeeTable`, `floorLamp`, `bookshelf`, `tvUnit`
  - Bedroom: `singleBed`, `doubleBed`, `queenBed`, `kingBed`, `dresser`, `nightstand`, `wardrobe`
  - Dining: `diningTable`, `roundDiningTable`, `barStool`, `chair`
  - Kitchen: `kitchenCounter`, `islandCounter`, `refrigerator`, `stove`, `sink`
  - Bathroom: `bathtub`, `shower`, `toilet`, `basinSink`, `vanity`
  - Office / Utility: `desk`, `officeChair`, `filingCabinet`, `washingMachine`
  
  The categories exist **only as source comments**. There is no category getter, and the picker does not group by category.
- `extension FurnitureTypeExtension on FurnitureType` (L43). Each getter is an exhaustive `switch` with no default:
  - `String get displayName` (L44): UI and export name.
  - `(double, double) get defaultSizeMm` (L81): record `(widthMm, depthMm)`.
  - `double get heightMm` (L118): height in mm. The comment says it is for 3D rendering; it is also used by the legacy 3D painter.
  - `Color get color` (L156): theme colour, used by the picker, the placing strip, 3D `colorHex` and the PDF fill. **Not** used on the 2D plan.
  - `IconData get icon` (L192): Material icon for the picker and placing strip.
  - Lines L154–155 are stray blank lines.
- `class FurnitureItem` (L229):

  | Field | Type | Mutability | Meaning |
  |---|---|---|---|
  | `id` | `String` | final | Unique id. New items get `'fur_<n>'` (sketch_screen L2597). Loaded items keep their stored id. |
  | `type` | `FurnitureType` | final | Catalogue type. |
  | `position` | `Offset` | mutable | **World-coordinate centre** (units of 5 mm, y down). The comment says "free-floating, NOT wall-anchored". |
  | `rotationDeg` | `double` | mutable, default `0.0` | Degrees, **clockwise on screen**. The comment says "0 = facing right", but see Notes. |
  | `widthMm` | `double` | mutable | Extent along local x, in mm. Defaults to `type.defaultSizeMm.$1`. |
  | `depthMm` | `double` | mutable | Extent along local y, in mm. Defaults to `type.defaultSizeMm.$2`. |

  - **Constructor** `FurnitureItem({required id, required type, required position, rotationDeg = 0.0, double? widthMm, double? depthMm})` (L237). Width and depth fall back to the type defaults in the initializer list.
  - `FurnitureItem copyWith({Offset? position, double? rotationDeg, double? widthMm, double? depthMm})` (L247): returns a **new** instance. It cannot change `id` or `type`. Calling `copyWith()` with no arguments is used as a deep copy in undo snapshots (sketch_screen L862–873, L891).
  - There are no `toJson`/`fromJson`, `==`/`hashCode` or `toString`. Equality is identity; lookups everywhere use `id`.

**Key logic:** pure lookup tables, with no computation beyond default resolution in the constructor. The full catalogue is in 6.4.2.

**State and data:**
- In memory: `SketchShape.furnitureItems` (`List<FurnitureItem>`, default `[]`, sketch_model L39).
- The class has no serialisation of its own. Five external places serialise or deserialise it with the same snake_case keys (6.4.1).

**Connections** (call sites):
- **`sketch_model.dart`:** L4, L39, L50, L57 (`SketchShape.furnitureItems`).
- **`sketch_screen.dart`:**
  - state: L116 `_furniturePlacingType`, L117 `_selectedFurnitureId`, L126 `_furnitureCounter`, L128–129 undo/redo stacks;
  - persistence: L537/L595–607 `_buildProjectPayload` (cloud payload key `furnitureItems`), L766–806 load from `loadProject` (key `furniture_items`; unknown type → `FurnitureType.sofa`);
  - undo: L851–875 `_saveUndo`;
  - geometry helpers: L1198 `_isInsideFurnitureItem`, L1213 `_snapFurnitureToWall` (**never called**), L1264–1337 wall and corner gap helpers;
  - dialogs: L1386–1460 size dialog (uses `displayName`, `defaultSizeMm`), L1547 position dialog title;
  - gestures: L1972 handle hit test, L2076–2109 rotate/drag, L2263–2281 gesture end, L2441–2496 pinch, L2589–2608 placement, L2627–2636 tap selection;
  - UI: L2926–2953 picker, L3197–3361 toolbar ("W: xcm × D: ycm", rotate ±45°, size, position, delete, Done), L3364–3394 and L3459 placing hints.
- **`sketch_painter.dart`:** L130–138 (draw loop).
- **`furniture_painter.dart`:** all drawing.
- **`database_helper.dart`:** L123–136 / L172–185 (table `furniture_items`), `saveProject` L203 (rows L289–307), `updateProject` L313 (rows L369–381), `loadProject` L411 (returns `'furniture_items'`, L482–493).
- **`collaboration_screen.dart`:** L455–473 and L880–898 (reads cloud `data['furnitureItems']`).
- **`sketch_pdf_export.dart`:** L268–269, L423–424, `_paintFurniture` L669, `_furnitureTable` L1108.
- **`dxf_exporter.dart`:** L60 (bounds), L120, `_writeFurniture` L300.
- **`dxf_preview_screen.dart`:** L67 (count), L300 (bounds), L407–408, `_drawFurnitureItem` L576.
- **`room_3d_screen.dart`:** `_loadFurnitureModels` L101, `_modelPathForType` L126, `_buildHouseJson` L191–205, L219–222, L574, `_Room3DPainter` L746/L843–1071, `shouldRepaint` L1471 (compares the furniture count).
- **Backend:** `sync.js` L15, L91, L171–189, L281–290, L351–360. Not Dart, but the same keys.

**Notes and issues:**
- The comment "0 = facing right" contradicts the symbols. At 0° the backs and headboards are at local −y (screen top), so items **face screen-down (+y)**, and the width lies along screen-x.
- Shared values:
  - icons: `bed` for double, queen and king; `door_sliding` for dresser and wardrobe; `table_restaurant` for both dining tables; `chair_alt` for bar stool, chair and office chair; `countertops` for both counters;
  - colour: `stove` and `filingCabinet` are both `0xFF78909C`.
- Some icons are loose fits: `Icons.microwave` for the stove, `Icons.face` for the vanity, `Icons.folder` for the filing cabinet, `Icons.door_sliding` for the dresser.
- There is no per-item height. 3D always uses the type height even after the footprint is resized.
- The id scheme `fur_<counter>` is generated by the screen. `_furnitureCounter` restarts at 0 per screen session and is **not** seeded from loaded items, so duplicate ids can appear after reopening a project (see 6.5).
- Type names are persisted via `.name`. Renaming an enum value breaks stored data, which silently becomes `sofa`.

#### `code/lib/sketch/furniture_painter.dart` — 682 lines

**Purpose:** draws furniture as plan symbols on the sketch canvas. For a selected item it also draws the selection overlay, rotation handle and cm size labels. It exposes the rotation handle position for gesture hit-testing.

**Depends on:**
- `package:flutter/material.dart`: `Canvas`, `Paint`, `Path`, `PathMetric`, `TextPainter`, `Colors`, `Rect`, `RRect`.
- `dart:math`.
- `furniture_item.dart`: `FurnitureItem`, `FurnitureType`.
- `sketch_constants.dart`: `mmPerUnit`.

**Declarations** (all top-level; **no class**):

- `Offset furnitureRotationHandlePos({required FurnitureItem item, required Offset Function(Offset) worldToScreen, required double scale})` (L9): returns `worldToScreen(item.position) − Offset(0, max(widthMm, depthMm)/mmPerUnit·scale/2 + 52)`. Used by `drawFurnitureItem` (L47) and `SketchScreen._onPointerDown` (sketch_screen L1972, 50 px hit radius).
- `void drawFurnitureItem({required Canvas canvas, required FurnitureItem item, required Offset Function(Offset) worldToScreen, required double scale, required bool isSelected})` (L20): the public entry point (see 6.2.11 and 6.2.12). Its only caller is `SketchPainter.paint` (L131).
- `void _drawDimensionLabels(Canvas, FurnitureItem item, Offset center, double wPx, double dPx)` (L79): width and depth cm labels outside the bottom and right edges, in screen space.
- `void _drawDimLabel(Canvas, String text, Offset pos)` (L100): one boxed blue label.
- `Paint _fill(bool sel)` (L130), `Paint _stroke(bool sel, [double sw = 1.5])` (L134), `Paint _detail()` (L139): shared paints (colours in 6.2.11).
- `void _drawSelectionOverlay(Canvas, double w, double d)` (L146): dashed rectangle and four corner squares.
- `void _drawDashedRect(Canvas, Rect rect, Paint paint)` (L170): dashes along the `addRect` path with `computeMetrics()`/`extractPath()`, 6 px on and 4 px off.
- `void _drawSymbol(Canvas, FurnitureType type, double w, double d, bool sel)` (L186): exhaustive `switch` dispatcher.
- 27 symbol functions, each `void _drawX(Canvas canvas, double w, double d, bool sel)` except `_drawBed(…, {required bool single})`. They are described in the table below.

**Key logic — per-type symbols.** Local frame: origin at the item centre, `w`/`d` = width/depth in px, x across the width, y across the depth (−y = top at 0°). Unless noted, each symbol does three things in order:

1. fills the footprint rectangle `Rect.fromLTWH(−w/2, −d/2, w, d)` with `_fill(sel)`;
2. draws its details;
3. strokes the footprint with `_stroke(sel)` (1.5 px).

"accent" = `0xFFDDDDDD` (`0xFF90CAF9` when selected). "detail" = `_detail()` (`0xFF444444`, 0.8 px). "handle line" = `0xFF666666` width 1.5 round cap. Any number written with "px" is a fixed screen size that does not scale with zoom.

| Type(s) | Function | Shapes drawn |
|---|---|---|
| `sofa` | `_drawSofa` L223 | backH = 0.28d, armW = 0.12w. Back strip along the top (full width, height backH, accent). Two armrests (width armW, from backH to the bottom, accent). Two vertical cushion lines at 1/3 and 2/3 of the seat width (detail). Outline. |
| `armchair` | `_drawArmchair` L254 | Like the sofa with backH = 0.30d and armW = 0.20w, but no cushion lines. |
| `singleBed` / `doubleBed`, `queenBed`, `kingBed` | `_drawBed` L272 (`single: true` / `false`) | Headboard strip height 0.15d (`0xFFCCCCCC`, `0xFF90CAF9` when selected). Pillows at y = −d/2 + 0.15d + 3 px, height 0.18d, white rounded rects (r = 4) with detail outline. Single: one pillow `w − 12` px wide. Others: two pillows `(w − 20)/2` wide at x = −w/2 + 6 and x = +8 px. Cover fold line at y = −d/2 + 0.30d (detail, inset 4 px). Outline. |
| `chair`, `barStool` | `_drawChair` L311 | Base fill. Back = upper half of an ellipse in rect (−w/2, −d/2, w, 2·0.20d), stroke 1.8. Seat = rounded rect (r = 4) inset 3 px, from y = −d/2 + 0.20d, height 0.65d, fill `0xFFEEEEEE` (`0xFFBBDEFB` when selected) with outline. **No outer footprint outline.** |
| `diningTable` | `_drawDiningTable` L334 | **No base rect.** Four chairs (fill `0xFFEEEEEE` + detail, not selection-coloured), centred just **outside** the footprint (2 px overlap): top and bottom are 1.8·(0.18w) × 0.22d, left and right are 0.18w × 1.8·(0.22d). Table = **oval** 0.72w × 0.72d (`_fill`/`_stroke`) with one horizontal grain line (inset 6 px). |
| `roundDiningTable` | `_drawRoundDiningTable` L358 | r = min(w,d)/2, chairD = 0.35r. Four chairs at 0°, 90°, 180°, 270°, centred at distance r + chairD/2. All are the same un-rotated 1.6·chairD × chairD rects, so side chairs are oriented differently from top/bottom. They extend beyond the footprint. Circle r (`_fill`/`_stroke`), plus a horizontal and a vertical cross line (inset 6 px). |
| `coffeeTable` | `_drawCoffeeTable` L377 | Rounded rect (r = 6) fill. Inner rounded rect inset 6 px (r = 4), `0xFFE0E0E0` ("glass top"). Four leg dots (r = 3, `0xFFBBBBBB`) inset 8 px from the corners. Rounded outline. |
| `wardrobe` | `_drawWardrobe` L399 | Vertical centre divider. In each half (centres x = ±w/4), an X with half-size `(w/2 − 5)/2` × `(d − 8)/2` (detail). Outline. |
| `bookshelf` | `_drawBookshelf` L413 | Three horizontal shelf lines at d/4, d/2 and 3d/4 from the top (inset 3 px). Outline. |
| `dresser` | `_drawDresser` L423 | Three rows: dividers after rows 1 and 2, and a handle line ±8 px at the centre of each row. Outline. |
| `nightstand` | `_drawNightstand` L438 | Divider at y = 0. Handle line ±7 px at y = d/4. Outline. |
| `desk` | `_drawDesk` L448 | Drawer line at y = d/2 − 0.32d. Two handle lines ±8 px at x = ±w/4, y = drawer line + 0.16d. Outline. |
| `vanity` | `_drawVanity` L462 | Divider at y = 0. "Mirror" oval `Rect.fromLTWH(−w/4, −d/2 + 4, w/2, 0.35d)` (detail). Outline. |
| `officeChair` | `_drawOfficeChair` L471 | Circle r = min(w,d)/2 (`_fill` + `_stroke`). Five star-base spokes to 0.65r at 72° steps (detail). Backrest arc in a 1.5r square centred at (0, −0.1r), from π + 0.3 sweeping π − 0.6 rad, stroke 1.8. **No footprint rect.** |
| `tvUnit` | `_drawTvUnit` L486 | Inner "screen" rounded rect inset 6 px horizontally and 4 px vertically (r = 2, `0xFFDDDDDD`). Diagonal X inset 8/6 px (detail). Outline. |
| `floorLamp` | `_drawFloorLamp` L499 | Circle r = min(w,d)/2 (`_fill`/`_stroke`). Bulb circle 0.25r filled `0xFFFFEE88` with detail ring. **No footprint rect.** |
| `kitchenCounter` | `_drawKitchenCounter` L509 | Front-edge line at y = d/2 − 5 px. Back line at y = −d/2 + 6 px. Sink oval centred (0.25w, 0), size 2.4·sR × 1.8·sR with sR = min(0.14w, 0.3d), `0xFFE0E0E0` + detail. Outline. |
| `islandCounter` | `_drawIslandCounter` L527 | Rounded rect (r = 4). Inner rounded rect inset 8 px (r = 3), `0xFFE8E8E8`. Rounded outline. |
| `refrigerator` | `_drawRefrigerator` L540 | Door divider at y = −d/2 + 0.62d. Two vertical handles at x = w/2 − 7 px (`0xFF888888`, width 2.5): from −d/2 + 0.15d to −d/2 + 0.45d, and from divider + 0.06d to divider + 0.22d. Outline. |
| `stove` | `_drawStove` L556 | Four burners at (±w/4, ±d/4): radius 0.16·min(w,d), `0xFFE8E8E8` + detail ring, inner 0.35× disc `0xFFCCCCCC`. Outline. |
| `sink` (Kitchen Sink) | `_drawSink` L573 | Basin oval inset 8 px (`0xFFE0E0E0` + detail). Drain dot r = 3 at (0, 6 px), `0xFF888888`. Outline. |
| `bathtub` | `_drawBathtub` L584 | Rounded rect (r = 10). Inner tub oval `Rect.fromLTWH(−w/2 + 8, −d/2 + 10, w − 16, d − 28)`, `0xFFE8E8E8` + detail. Two taps r = 3.5 at (±9 px, −d/2 + 7), `0xFFAAAAAA`. Drain r = 4 at (0, d/2 − 10), `0xFFBBBBBB` + detail. Rounded outline. |
| `shower` | `_drawShower` L607 | Central drain circle radius 0.14·min(w,d) (`0xFFDDDDDD` + detail). Showerhead dot r = 5 at (−w/2 + 10, −d/2 + 10) (`0xFFCCCCCC` + detail). Four spray ticks from 8 to 14 px at 45°, 135°, 225° and 315°. Outline. |
| `toilet` | `_drawToilet` L629 | Tank: rounded rect (r = 4) on the top 0.30d (`_fill` + `_stroke`). Bowl: oval from y = −d/2 + 0.30d + 2 to the bottom, full width (`_fill`), inner oval inset 6 px horizontally and 6–8 px vertically (detail), then the bowl outline. **No footprint rect.** |
| `basinSink` | `_drawBasinSink` L644 | Rounded rect (r = 8). Basin oval inset 8 px (`0xFFE0E0E0` + detail). Drain dot r = 3 at the centre. Rounded outline. |
| `filingCabinet` | `_drawFilingCabinet` L659 | Dividers at d/4, d/2 and 3d/4 (the guard `if (i < 4)` is always true). Handle lines ±7 px centred in the first three drawers only; the bottom drawer has no handle. Outline. |
| `washingMachine` | `_drawWashingMachine` L672 | Drum circle r = 0.33·min(w,d) at (0, 0.06d), `0xFFE0E0E0` + `_stroke`, inner 0.5r detail ring. Control-strip line at y = −d/2 + 6 px. Outline. |

**State and data:** stateless. `Paint` objects are allocated on every call. All sizes are derived from `w`/`d` in px, plus fixed px insets.

**Connections:**
- `drawFurnitureItem` is called only from `SketchPainter.paint` (sketch_painter L131).
- `furnitureRotationHandlePos` is called from `drawFurnitureItem` (L47) and `SketchScreen._onPointerDown` (sketch_screen L1972).
- It is **not** used by the PDF, DXF, DXF-preview or 3D renderers, which draw generic rectangles or boxes (6.2.13). So the app's plan view and the exported drawings look different.

**Notes and issues:**
- Fixed-px insets and radii (e.g. `w − 16`, `d − 28`, ±7/±8 px handles, ±9 px taps, `+52` handle offset) do not scale with zoom. Small on-screen items (in pixels) get negative-size inner rects or ovals that overflow the outline. Examples: the bathtub's inner oval once `d < 28` px, which is the default 800 mm depth below scale 0.175; the sink and basin once `w`/`d < 16` px. The only guard is the `< 4 px` early return.
- That early return also hides the selection overlay and handle, while the screen still hit-tests the invisible handle within 50 px.
- Dining-table chairs lie outside the footprint, the selection rectangle and the hit-test area. The rectangular "Dining Table" is drawn as an oval. Round-table chairs are not rotated.
- `barStool` uses the side-chair symbol, which has a back arc.
- The two bed pillows are asymmetric: the left margin is 6 px and the right is 2 px, because the second pillow starts at a fixed x = +8. The fold line at 0.30d crosses the pillows, which reach 0.33d + 3 px.
- The filing cabinet draws four drawers with three handles, and has a dead `if (i < 4)`.
- The corner resize squares are not interactive.
- The size labels use the default font, unlike the rest of the plan (monospace), and round to whole cm.
- `withOpacity` is deprecated (see sketch_painter notes).

### 6.4 Data contracts

#### 6.4.1 `FurnitureItem` model and serialised shape

In-memory shape: `FurnitureItem{ id: String, type: FurnitureType, position: Offset (world units), rotationDeg: double (deg, clockwise on screen), widthMm: double, depthMm: double }`. Items are owned by `SketchShape.furnitureItems`, one list per room.

**Every persisted or transmitted form uses the same flat snake_case record.** There is no shared (de)serialiser.

| Key | JSON/SQL type | Source | Units / notes |
|---|---|---|---|
| `furniture_id` | string / `TEXT NOT NULL` | `id` | e.g. `fur_3`. |
| `shape_index` | int / `INTEGER NOT NULL` | index of the owning shape in the project's shape list | Readers ignore rows with an out-of-range index. Collaboration defaults a missing value to 0; the backend defaults it to 0. |
| `type` | string / `TEXT NOT NULL` | `type.name` | The enum identifier, e.g. `coffeeTable`, `roundDiningTable`. Unknown values become `FurnitureType.sofa` on read. |
| `position_x` | number / `REAL` | `position.dx` | **World units** (×5 = mm), x right. |
| `position_y` | number / `REAL` | `position.dy` | **World units**, **y down** (screen convention). |
| `rotation_deg` | number / `REAL` | `rotationDeg` | Degrees, clockwise on screen, normally in [0, 360). The backend defaults it to 0. |
| `width_mm` | number / `REAL` | `widthMm` | mm along local x. |
| `depth_mm` | number / `REAL` | `depthMm` | mm along local y. |

Where the record appears:
- **SQLite** table `furniture_items`: the columns above plus `id INTEGER PRIMARY KEY AUTOINCREMENT` and `project_id INTEGER NOT NULL` (FK → `projects(id) ON DELETE CASCADE`). It is created in `_createTables` (the `onCreate` callback, database_helper L29/L123), or by `_onUpgrade` for `oldVersion < 3` (L170–185).
- **Local load map** (`DatabaseHelper.loadProject`, L411): list under key **`'furniture_items'`**. It is read by sketch_screen L766, which casts with `as double`.
- **Cloud payload** (`_buildProjectPayload`, sketch_screen L537): list under key **`'furnitureItems'`** (camelCase container, snake_case records). The backend `sync.js` writes it to PostgreSQL `furniture_items` and returns `furnitureItems: rows`. `collaboration_screen.dart` reads `data['furnitureItems']` using `(num).toDouble()`.
- **3D JSON** (`room_3d_screen._buildHouseJson`), per room under `'furnitureItems'`. This is a different shape: `{type, x, z, rotationDeg, widthM, depthM, heightM, colorHex}`, where `x = position.dx·0.005`, `z = position.dy·0.005`, the sizes are mm/1000, `heightM = type.heightMm/1000`, and `colorHex` is `'#rrggbb'` from `type.color`. A sibling `furnitureModels` map holds type name → base64 GLB.

#### 6.4.2 Complete furniture catalogue

Sizes are `defaultSizeMm` (width × depth) and `heightMm`. Colours are ARGB hex from `color`. Icons are `Icons.*` from `icon`. "2D symbol" is the furniture_painter function. The "3D asset" column is from `room_3d_screen.dart` `_modelPathForType` (L126) and was checked against `code/assets/models/`:
- ✓ = the file exists;
- ✗ = it is mapped but the file is missing (falls back to a box);
- — = the type is not mapped (box).

| # | `FurnitureType` | `displayName` | Category (comment) | W × D (mm) | H (mm) | `color` | `icon` | 2D symbol | 3D asset |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `sofa` | Sofa | Living | 2200 × 900 | 850 | `0xFF4CAF50` | `weekend` | `_drawSofa` | `Sofa.glb` ✓ |
| 2 | `armchair` | Armchair | Living | 800 × 800 | 900 | `0xFF66BB6A` | `chair` | `_drawArmchair` | `armchair.gltf` ✓ (embedded buffer) |
| 3 | `coffeeTable` | Coffee Table | Living | 1100 × 600 | 450 | `0xFF8D6E63` | `table_bar` | `_drawCoffeeTable` | `coffee_table.glb` ✓ |
| 4 | `floorLamp` | Floor Lamp | Living | 300 × 300 | 1600 | `0xFFFFD54F` | `light` | `_drawFloorLamp` | `Floorlamp.glb` ✓ |
| 5 | `bookshelf` | Bookshelf | Living | 900 × 300 | 1800 | `0xFF795548` | `menu_book` | `_drawBookshelf` | `bookshelf.glb` ✓ |
| 6 | `tvUnit` | TV Unit | Living | 1600 × 450 | 450 | `0xFF9C27B0` | `tv` | `_drawTvUnit` | `tv_unit.glb` ✗ |
| 7 | `singleBed` | Single Bed | Bedroom | 900 × 2000 | 600 | `0xFF2196F3` | `single_bed` | `_drawBed(single: true)` | — (`Singlebed.glb` exists, unused) |
| 8 | `doubleBed` | Double Bed | Bedroom | 1400 × 2000 | 600 | `0xFF3F51B5` | `bed` | `_drawBed(single: false)` | — |
| 9 | `queenBed` | Queen Bed | Bedroom | 1600 × 2000 | 600 | `0xFF5C6BC0` | `bed` | `_drawBed(single: false)` | `doublebed.glb` ✓ (`Queenbed.glb` unused) |
| 10 | `kingBed` | King Bed | Bedroom | 1800 × 2000 | 600 | `0xFF3949AB` | `bed` | `_drawBed(single: false)` | `doublebed.glb` ✓ |
| 11 | `dresser` | Dresser | Bedroom | 1000 × 500 | 1300 | `0xFFA1887F` | `door_sliding` | `_drawDresser` | `dresser.glb` ✗ (file is `dresser (2).glb`) |
| 12 | `nightstand` | Nightstand | Bedroom | 500 × 400 | 600 | `0xFFBCAAA4` | `nightlight` | `_drawNightstand` | — |
| 13 | `wardrobe` | Wardrobe | Bedroom | 1200 × 600 | 2100 | `0xFF6D4C41` | `door_sliding` | `_drawWardrobe` | `wardrobe.glb` ✓ |
| 14 | `diningTable` | Dining Table | Dining | 1200 × 900 | 750 | `0xFFFF9800` | `table_restaurant` | `_drawDiningTable` | `dining_table.glb` ✓ |
| 15 | `roundDiningTable` | Round Table | Dining | 1200 × 1200 | 750 | `0xFFFFA726` | `table_restaurant` | `_drawRoundDiningTable` | — (`round_table.glb` unused) |
| 16 | `barStool` | Bar Stool | Dining | 400 × 400 | 750 | `0xFFFFB74D` | `chair_alt` | `_drawChair` | `bar_stool.glb` ✓ |
| 17 | `chair` | Chair | Dining | 500 × 500 | 900 | `0xFF8BC34A` | `chair_alt` | `_drawChair` | `chair.glb` ✓ |
| 18 | `kitchenCounter` | Kitchen Counter | Kitchen | 1800 × 600 | 900 | `0xFFFF5722` | `countertops` | `_drawKitchenCounter` | `kitchen_counter.glb` ✓ |
| 19 | `islandCounter` | Island Counter | Kitchen | 1500 × 900 | 900 | `0xFFFF7043` | `countertops` | `_drawIslandCounter` | `island_counter.glb` ✓ |
| 20 | `refrigerator` | Refrigerator | Kitchen | 700 × 700 | 1700 | `0xFF90A4AE` | `kitchen` | `_drawRefrigerator` | — (`refrigerator.glb` unused) |
| 21 | `stove` | Stove | Kitchen | 600 × 600 | 900 | `0xFF78909C` | `microwave` | `_drawStove` | `gas_stove.glb` ✓ |
| 22 | `sink` | Kitchen Sink | Kitchen | 600 × 500 | 900 | `0xFF80DEEA` | `water` | `_drawSink` | `kitchen_sink.glb` ✓ |
| 23 | `bathtub` | Bathtub | Bathroom | 1700 × 800 | 550 | `0xFF00BCD4` | `bathtub` | `_drawBathtub` | `Bathtub-new.glb` ✓ |
| 24 | `shower` | Shower | Bathroom | 900 × 900 | 2100 | `0xFF00ACC1` | `shower` | `_drawShower` | `shower.glb` ✓ |
| 25 | `toilet` | Toilet | Bathroom | 450 × 650 | 800 | `0xFF9E9E9E` | `wc` | `_drawToilet` | `toilet.glb` ✓ |
| 26 | `basinSink` | Basin Sink | Bathroom | 600 × 500 | 850 | `0xFF80CBC4` | `water_drop` | `_drawBasinSink` | `basinSink.glb` ✓ |
| 27 | `vanity` | Vanity | Bathroom | 1200 × 500 | 900 | `0xFF4DB6AC` | `face` | `_drawVanity` | — (`vanity.glb` unused) |
| 28 | `desk` | Desk | Office / Utility | 1200 × 600 | 750 | `0xFF607D8B` | `desk` | `_drawDesk` | `desk.glb` ✓ |
| 29 | `officeChair` | Office Chair | Office / Utility | 600 × 600 | 900 | `0xFF546E7A` | `chair_alt` | `_drawOfficeChair` | `office_chair.glb` ✓ |
| 30 | `filingCabinet` | Filing Cabinet | Office / Utility | 450 × 600 | 1200 | `0xFF78909C` | `folder` | `_drawFilingCabinet` | `FilingCabinet.glb` ✗ (file is `FillingCabinet.glb`) |
| 31 | `washingMachine` | Washing Machine | Office / Utility | 600 × 600 | 850 | `0xFF42A5F5` | `local_laundry_service` | `_drawWashingMachine` | `Washingmachine.glb` ✓ |

The 3D map also contains the key `'kitchenStove'` → `kitchen_stove.glb`, which matches **no** enum value and is therefore dead. These 3D asset files exist but nothing references them: `bed.glb`, `coffeetable.glb`, `cupboard.glb`, `kitchensink.glb`, `refrigerator (1).glb`, `shower_cabin.glb`, plus those noted in the table. The 3D part owns these details.

#### 6.4.3 Rendering conventions other parts must match

- **Units:**
  - 1 world unit = 5 mm (`mmPerUnit`); 200 units = 1 m.
  - Furniture size is in mm; furniture and plan positions are in world units.
  - `wallThickness` = 30 units = **150 mm**, centred on the room polygon edges. The trailing comment in `sketch_constants.dart` L34 says "~50mm real", which is wrong. The 3D JSON uses `wallThicknessM: 0.2`, which is inconsistent.
  - Grid: minor 200 mm, major 1 m.
- **Axes:** world x right, **y down**. There is no Y flip on screen. The DXF exporter flips Y (`_wy`).
- **Angles:**
  - Drawing and snapping angles are math convention (counter-clockwise, y up, 0–360°); screen direction = `(cos a, −sin a)`.
  - Furniture `rotationDeg` is **clockwise on screen**. Local +x maps to `(cos θ, sin θ)` and local +y to `(−sin θ, cos θ)` in world/screen coordinates. The PDF (`rotW`), the DXF preview and the hit test use the same mapping; the DXF converts it for its Y-up space.
- **Wall-relative positions:** `RoomObject.positionAlong` is in 0..1 from `points[wallIndex]` toward the next vertex. In the painter, `ResolvedOpening.positionAlong` is re-based to the merged wall `a→b`.
- **Fixed screen sizes** (do not scale with zoom):
  - dimension offset 26 px, segment offset 14 px;
  - label fonts 9/8 px; room name 13 px, area 10 px;
  - furniture outline 1.5 px;
  - rotation handle radius 22 px at +52 px above the item.
- **Core colours:**

  | Element | Colour |
  |---|---|
  | Walls | `0xFF1A1A1A` |
  | Room fill | `0xFF00AAFF` @0.07 active / @0.03 inactive |
  | Dimensions | blue `0xFF2255CC`, measured green `0xFF00AA44`, selected orange `0xFFFF8800`, segment-object `0xFF0066CC` |
  | Door | `0xFF1A1A1A` |
  | Window | `0xFF0099CC` |
  | Selected opening | orange `0xFFFF8800`, highlight `0xFF0099FF` |
  | Opening conflict | `0xFFEF9F27` |
  | Snapping | green `0xFF00CC44`; drawing blue `0xFF00AAFF`; vertex orange `0xFFFF6600` |
  | Grid | `0xFFE6E6E6` / `0xFFC8C8C8` / dots `0xFFD6D6D6`; axes `0xFFAAAAAA` |
  | Room name / area | `0xFF333333` / `0xFF666666` |
  | Furniture | fill `0xFFF7F7F7`, stroke `0xFF222222`, detail `0xFF444444` |
  | Furniture selected | fill `0xFFE3F2FD`, stroke `0xFF1565C0`, overlay `0xFF1976D2`, handle `0xFF1565C0`, labels `0xFF1565C0` on `0xDDE3F2FD` |

- **Selection identity:** furniture is selected by `id` (`selectedFurnitureId`); openings by `RoomObject.id` (`selectedObjectId`); walls by index within the active shape (`selectedWallIndex`).

### 6.5 Known issues and limitations

**Rendering and painter**
- **Covered highlights:** the snap-candidate wall glow and the active-room outline are drawn in pass 1 and painted over by the opaque walls in pass 2, so they are effectively invisible at normal zoom.
- **Dimensions disappear when zoomed in:** closed-room dimension lines and labels (pass 1) are progressively covered by walls as zoom increases. Segment lines (14 px) are covered above `scale ≈ 0.93` and their labels by about 1.3; totals (26 px) start being covered around `1.2` and are hidden around `2.3` (max 5.0). Their hit rects remain tappable.
- **Notched corners:** walls are butt-ended `thickWallRect` bands, so non-collinear outer corners show a notch. There are no mitred joins.
- **Concave rooms:** the vertex-mean "centroid" is used for the outside test and the room label. In concave rooms, dimensions can land inside and the label can fall outside the room.
- **Segmented dimensions:**
  - segment labels are unrotated, while totals are rotated;
  - segment values come from geometry while the total uses `wallRealMm`, so they may disagree;
  - walls with openings get no label hit target and no selected state;
  - object segments show the nominal `widthMm` even when clamped at the wall end.
- **Label hit rects** are axis-aligned 24 px boxes, so they do not cover rotated labels on steep walls.
- **Vertex markers scale with zoom** (`r·scale·3`): a 60 px radius dot and a 420 px glow at scale 5, but only 0.75 px dots when zoomed far out.
- **Door rendering:**
  - the hinge is always at the merged wall's `a` end, and `swingFlipped` only mirrors the swing side;
  - on shared walls, doors owned by the second room can appear mirrored;
  - the selection quad does not cover the whole swing;
  - an opening whose centre lies exactly on the boundary between two merged-wall pieces could be resolved on both. In that case it is cut twice and its symbol may be drawn twice, possibly in different directions. This is an edge case in `openingsForWall`'s ±1e-6 tolerance.
- **Possible crash:** `_drawSnapGuides` uses an unguarded `points[activePointIndex]`, which can throw a `RangeError` on a stale index.
- **Angle-indicator mismatch:** the arc spans the short screen angle while the text shows the 0–360° value.
- **Performance and side effects:**
  - `shouldRepaint` is always true;
  - per-frame `buildWalls` is O(E²), plus `Path.combine` unions/differences, about 10⁴ grid dots and many `TextPainter`s;
  - `paint()` appends to caller-owned lists, which is a side effect.
- **Code hygiene:**
  - dead locals (`gapMm`, `wallDir`, `isLocked`);
  - unused `size` parameters;
  - duplicated `@override`;
  - misleading arrow comments;
  - the duplicated snap-angle helper (`_nearestSnapAnglePure` vs sketch_screen `_nearestSnapAngle`);
  - the area string duplicates `formatArea` without its mm² fallback;
  - hard-coded 3.0° instead of `snapThresholdDeg`;
  - deprecated `withOpacity`.

**Furniture**
- **Inconsistent looks across outputs:** the plan symbols are monochrome and ignore `FurnitureType.color`. PDF, DXF, DXF preview and 3D each use their own generic rectangle or box renderer, so furniture looks different in every output.
- **Detail sizing:** fixed-px detail sizes do not scale. Small on-screen items get inverted or overflowing inner shapes, and large zoom makes the details look tiny. Items under 4 px are skipped entirely, including their selection UI, while the hidden rotation handle stays hit-testable (50 px radius).
- **Symbol oddities:**
  - dining-table chairs are drawn outside the footprint and hit area;
  - the rectangular dining table is an oval;
  - round-table chairs are not rotated;
  - `barStool` reuses the backed chair;
  - double-bed pillows are asymmetric and crossed by the fold line;
  - the filing cabinet has 4 drawers but 3 handles, and a dead condition.
- **Decorative handles:** the corner "resize handles" have no gesture. Resizing is only by pinch (proportional) or the dialog.
- **Wrong orientation comment:** `rotationDeg`'s comment "0 = facing right" is wrong; at 0° items face screen-down (+y).
- **No per-item height:** 3D uses the type's `heightMm` regardless of resizing, and height is not persisted.
- **No shared serialiser:** five ad-hoc (de)serialisers exist. The container key differs between local (`furniture_items`) and cloud (`furnitureItems`). Unknown `type` strings silently become `sofa`.
- **Duplicate ids:** `_furnitureCounter` (sketch_screen L126) restarts at 0 per session and is never seeded from loaded items. New `fur_<n>` ids can therefore duplicate stored ones. When that happens:
  - the painter shows every item with that id as selected (across all rooms);
  - edits act on the first match;
  - delete (`removeWhere`) removes all matches in the active room.
- **Categories:** furniture categories are comments only, and the picker is a flat grid in enum order.

**Cross-part observations** (owned by other parts; listed so the editor can check them)
- `SketchScreen._snapFurnitureToWall` (L1213) is never called, so furniture does not snap to walls.
- `_saveUndo` (sketch_screen L851) pushes the furniture snapshot **twice** (L862 and L872) while every other stack gets one entry, which desynchronises undo stacks.
- Furniture rotate and drag call `_saveUndo()` on pointer-up, *after* the change, so the snapshot already contains the change.
- In the 3D asset mapping, `tv_unit.glb`, `dresser.glb` and `FilingCabinet.glb` are missing. The `kitchenStove` key is dead. `singleBed`, `doubleBed`, `nightstand`, `roundDiningTable`, `refrigerator` and `vanity` are unmapped even though suitable files exist for several of them.
- The 3D wall thickness (0.2 m) differs from the 2D 150 mm.
- `code/lib/furniture_3d_viewer.dart` is an empty (0-line) file.


---

## Part 7 — Exports: PDF and DXF

### 7.1 Overview

This part turns the in-memory floor-plan model (the `List<SketchShape>` held by `_SketchScreenState` in `code/lib/sketch/sketch_screen.dart`) into two kinds of output files:

1. **PDF "Floor Plan Guide"** (`code/lib/sketch/sketch_pdf_export.dart`). The `pdf` package builds a multi-page A4 portrait document: a cover/table-of-contents page, a full-plan overview page, and one detail page per shape. The `printing` package then hands it to the operating system's print dialog, where the user can print it or choose "Save as PDF". The app itself never writes or shares the PDF file.
2. **DXF drawing** (`code/lib/screens/dxf_exporter.dart`). An AutoCAD R12 (`AC1009`) ASCII DXF of all closed rooms is written by hand into a `StringBuffer` (no DXF library). It is saved to the app's temporary directory and handed to the Android share sheet through `share_plus`. The DXF export is only reachable through a dark "blueprint" preview screen (`code/lib/screens/dxf_preview_screen.dart`). That screen redraws the model on a Flutter canvas; it does **not** generate or parse DXF text. When no closed room exists, it substitutes a synthetic 4 m × 3 m sample room.
3. `docs/export_feature_explained.md` is a plain-language explanation of both exporters. It was written on 2026-07-29 (commit `86429e3`) and is partly outdated: more than a dozen exporter commits followed on 2026-09-16/17, including the wall-thickness change, the dimension lines, the enlarged overview, the area labels and the "opening" object type.

Both exporters only read the model: they never modify `SketchShape`s, write to SQLite, or talk to the backend.

**Vocabulary**

| Term | Meaning in this part |
|---|---|
| World unit | Sketch coordinate unit. `mmPerUnit = 5.0` (`sketch_constants.dart` L5): 1 unit = 5 mm, 200 units = 1 m. +Y points **down** (screen convention). The DXF exporter hard-codes the same factor as `DxfExporter._mm = 5.0`. |
| pt | PDF point = 1/72 in ≈ 0.3528 mm. A4 = 595.28 × 841.89 pt. |
| Valid shape (PDF) | `SketchShape` with `points.length >= 2`. Open polylines are included. |
| Closed room (DXF and preview) | `SketchShape` with `isClosed && points.length >= 3`. |
| Wall *i* | Segment `points[i] → points[(i+1) % n]`. Wall count is `n` if closed, otherwise `n-1`. |
| Drawn length | Distance between the two wall vertices in world units (× 5 = mm). |
| Calibrated length | `SketchShape.wallRealMm[i]` (mm), entered from the laser device or manually. The editor's `_applyRealMeasurement` (`sketch_screen.dart` L1846) rebuilds the open point chain from calibrated lengths, so drawn and calibrated lengths usually agree. They can differ for the closing wall of a polygon (not part of the rebuilt chain, L1821) or after later vertex edits. |
| Room object | `RoomObject` (`room_object.dart`) with `type` ∈ {`door`, `window`, `opening`}, `wallIndex`, `positionAlong` (0..1, the object's **centre** along the wall), `widthMm`, `heightMm`, `elevationMm`, `swingFlipped`. |
| Centroid | Always the **vertex average** of a shape's points, not the area centroid. |
| Inward normal | The unit normal of a wall that points toward the centroid. It is negated again when `swingFlipped` is true. Door leaves and arcs go to the inward side; dimension lines go to the outward side. |
| `_Tx` | PDF world→page coordinate transformer (uniform scale + Y flip). |
| `referenceScale` | The overview page's world→pt scale. Room pages use it so walls look equally thick on every page. |
| ACI | AutoCAD Color Index: 1 red, 2 yellow, 3 green, 4 cyan, 5 blue, 7 white/black, 8 dark grey. |
| Group code | DXF integer tag on its own line, followed by its value on the next line. |

**How the files fit together**

```text
_SketchScreenState (code/lib/sketch/sketch_screen.dart)
   state: List<SketchShape> shapes (L65), String _localProjectName (L58), activeShape = shapes[activeIndex] (L108)
   │
   ├── [IconButton Icons.picture_as_pdf "Export PDF"]  enabled iff activeShape.points.length >= 2   (L3861)
   │      exportSketchPdf(context, shapes, projectName: _localProjectName)        sketch_pdf_export.dart
   │        ├─ valid = shapes with >= 2 points ; referenceScale = overview scale
   │        ├─ pw.Document: _coverPage → _overviewPage → _roomPage × valid.length
   │        └─ Printing.layoutPdf(name: 'floor_plan_guide')  ──► OS print dialog (print / Save as PDF)
   │
   └── [IconButton Icons.architecture "Export DXF"]  always enabled                                  (L3876)
          Navigator.push → DxfPreviewScreen(shapes, projectName or 'SmartMeasure_Room')  dxf_preview_screen.dart
            ├─ _previewShapes = closed rooms (>= 3 pts)  OR  synthetic 4 m × 3 m sample room
            ├─ _BlueprintPainter (Flutter canvas, redrawn from the model)  + _FileInfoCard + _WallTable
            └─ [EXPORT DXF / DOWNLOAD SAMPLE DXF button] → DxfExporter.export(shapes, projectName)
                   dxf_exporter.dart
                   ├─ _buildDxf → AC1009 text: HEADER, TABLES(LTYPE, LAYER, STYLE), ENTITIES, EOF
                   ├─ File('<getTemporaryDirectory()>/<sanitised name>.dxf').writeAsString(...)
                   └─ Share.shareXFiles([XFile(mimeType 'application/dxf')]) ──► Android share sheet

Model inputs (read-only): SketchShape (sketch_model.dart), RoomObject (room_object.dart),
FurnitureItem / FurnitureType extension (furniture_item.dart), and from sketch_constants.dart:
mmPerUnit, wallThickness (=30 units), thickWallRect(), formatLength(), formatArea().
```

No other file in `code/lib` imports `pdf`, `printing` or `share_plus`, and no other screen triggers an export. The two `IconButton`s above are the only call sites.

### 7.2 Features and how they work

#### 7.2.1 PDF export ("Floor Plan Guide")

**Trigger.** `_SketchScreenState.build` contains a 52-px-high, horizontally scrollable dark status/action bar (`Container(height: 52, color: 0xFF2D2D2D)`, L3788). It also holds the MODE/PTS/PERIM/AREA status items, undo/redo/clear, Add Room, Save/Load and Cloud buttons. The PDF button is `IconButton(Icons.picture_as_pdf, color 0xFFFF4488, tooltip 'Export PDF')` (L3861–3875):
- It is enabled only when `activeShape.points.length >= 2`. Only the **active** room is checked, so after "Add Room" creates an empty active room, the button is disabled even if other rooms exist.
- `onPressed: () => exportSketchPdf(context: context, shapes: shapes, projectName: _localProjectName)`. The future is not awaited and errors are not caught.
- `shapes` is the live editor list and may contain empty shapes.
- `_localProjectName` is `''` until the project is saved, loaded or auto-saved (set at L411, L514, L630 to `'Auto Save'`, and L842 from cloud data).

**Processing order (`exportSketchPdf`, L55).**
1. `valid = shapes.where((s) => s.points.length >= 2)`. If empty, it shows `SnackBar('Draw a room first', backgroundColor 0xFF333333)` and returns. The current button's enable condition makes this branch practically unreachable.
2. `totalPages = 2 + valid.length`. `pdf = pw.Document()`. `referenceScale = _txAll(valid, _daOv).scale`, which is `444 / max(bboxW, bboxH)` over every vertex of every valid shape, in pt per world unit.
3. It adds the pages: `_coverPage(valid, projectName, totalPages)` is page 1, `_overviewPage(valid, projectName, 2, totalPages)` is page 2, and `_roomPage(valid[i], i, 3 + i, totalPages, referenceScale)` is pages 3..N+2.
4. `await Printing.layoutPdf(onLayout: (_) async => pdf.save(), name: 'floor_plan_guide')`.
   - In `pdf` 3.12.0 the `pw.Page.build` closures run inside the first `pdf.save()` (`Document.save` → `Page.postProcess`), so the live `SketchShape` objects are read at that moment. Later `save()` calls reuse the painted document.
   - The `PdfPageFormat` argument passed to `onLayout` is ignored, so the document is always A4 portrait whatever paper the user picks.

**Coordinate transformation.** `_Tx.call(w) = PdfPoint(margin + (w.dx − minX)·scale, canvasSize − margin − (w.dy − minY)·scale)`.
- `pw.CustomPaint` paints with its origin at the bottom-left of its box and +Y up (pdf 3.12 `CustomPaint.paint` translates to `box.left, box.bottom`). That is why world Y (down) is flipped.
- Text overlays are `pw.Positioned` widgets with a top-left origin, so they convert back with `top = canvasSize − y`.

**Scale.** The plan is fitted into a box with a uniform scale: `scale = da / max(max(bboxW, 1), max(bboxH, 1))`.
- The bounding box uses only wall vertices (`points`), never furniture.
- The overview uses `da = 444` pt inside a 504 pt canvas (30 pt dimension margin each side). Room pages use `da = 260` pt inside a 304 pt canvas (22 pt margin).
- Each room page therefore has its own scale.
- No numeric scale (1:n), scale bar, north arrow or legend is printed.
- Example: one 4 m × 3 m room (800 × 600 units) gives an overview scale of 0.555 pt/unit (≈ 1:25.5 on paper) and a room-page scale of 0.325 pt/unit.

**Wall thickness.**
- The overview draws each wall as a filled rectangle `thickWallRect(a, b, wallThickness)` with `wallThickness = 30` world units (150 mm). A 4 × 3 m room gives 16.65 pt.
- Room pages use `effectiveWallThickness = wallThickness × referenceScale / tx.scale` world units. The printed thickness (pt) therefore equals the overview's, even though the room is drawn at a different scale.

**What the user sees.**
- The Android print UI opens with a preview of the document. The user can print or "Save as PDF"; the job/document name is `floor_plan_guide`, which Android normally proposes as the file name.
- Nothing is stored inside the app and there is no share action.
- The `bool` returned by `layoutPdf` is ignored.
- The page contents are described in 7.2.2 and 7.4.

#### 7.2.2 PDF plan content (walls, openings, furniture, labels, dimensions)

The overview page draws in **three passes** so that one room's door cut also removes a neighbouring room's coincident wall:
1. White fill of every closed shape with at least 3 points.
2. Black thick-wall rectangles for every wall of every valid shape.
3. For each shape: furniture (`_paintFurniture`), then door/window/opening symbols (`_paintRoomObjects`, closed shapes with objects only). After all shapes, `_paintFullPlanDimensions`.

Over the painter, a `pw.Stack` adds widget overlays: room names (`_roomLabelOverlay`), areas (`_roomAreaOverlay`) and dimension texts (`_fullPlanDimensionLabels`).

Room pages draw, in order: grid → light-blue fill `PdfColor(0.90, 0.95, 1.00)` → walls in `PdfColors.blueGrey800` → corner dots (radius 3 pt; vertex 0 `green700`, others `blue700`) → furniture → room objects (closed shapes only) → per-wall dimensions. The overlays are the area label and the wall-length labels. There is no room-name overlay because the name is the page title.

**Room objects (`_paintRoomObjects`).**
- Wall `wA → wB` gives `wallDir`. The object centre is at `tCenter = positionAlong × wallLen`.
- The opening runs from `tCenter − w/2` to `tCenter + w/2`, with `w = widthMm / mmPerUnit` world units. It is not clamped to the wall.
- The inward normal is chosen toward the centroid, then negated if `swingFlipped`.
- Every symbol first strokes a **white** line along the opening with width `wallThicknessWorld × scale + 1` pt (butt caps), erasing the wall band.
- Door: hinge = opening start. A leaf of length `w` (pt) runs along the inward normal, a "frame" line runs hinge → far jamb (1.5 pt, blueGrey800), and a 90° arc of radius `w` is drawn as a 25-point polyline (0.8 pt).
- Window: three lines parallel to the wall, offset 0 and ±2.66 pt (±0.38 × 7), colour `PdfColor(0, 0.49, 0.76)`. The centre line is 1.5 pt and the outer lines 0.8 pt.
- Opening: only ±4 pt jamb ticks at both ends (blueGrey400, 0.8 pt).

**Furniture (`_paintFurniture`).** The rectangle is `widthMm × depthMm`, rotated by `rotationDeg` about `position`.
- Pastel fill `0.65 + 0.35·c` per channel of `FurnitureType.color`.
- Border `0.7·c` at 0.8 pt, and an X cross `0.5·c` at 0.4 pt.
- There is no text label: names appear only in the furniture table, and neither furniture nor doors/windows are numbered on the plan.

**Dimensions.**
- *Overview:* dimension chains on all four sides of the overall bounding box.
  - The segment chain sits 7 pt (`_dimSegOffset`) outside the bounding-box edge and the overall dimension 16 pt (`_dimTotalOffset`) outside.
  - Extension lines run to 3 pt beyond the overall line. Arrowheads are filled triangles of 3 pt (`_dimArrowSize`).
  - Chain "breakpoints" are the x (or y) coordinates of any vertex lying within 3 world units (15 mm) of that bounding-box edge, plus the two bounding-box extremes. Values within 3 units of each other are merged.
  - Horizontal texts use `formatLength` ("850 mm" / "4.00 m"); vertical texts use `_formatVerticalMeters` (always "x.xx m").
  - All overview dimensions use drawn geometry and ignore `wallRealMm`.
- *Room pages:* each wall at least 1 world unit long gets a dimension line 7 pt outside its centreline (outward = away from the centroid), with extension lines from the wall vertices to 10 pt and arrowheads.
  - The label is placed 14 pt outside the wall midpoint and rotated when the wall is closer to vertical.
  - The text is `_wallLenMeters`: calibrated mm if present, else drawn, always "x.xx m".

**Tables.** Overview: "Room Index" (#, Room Name, Perimeter, Area, Pg). Room pages:
- Stats row (WALLS, PERIMETER, AREA, HEIGHT), for closed shapes only.
- "Doors, Windows & Openings" (#, Type, Width, Height, Elev.) and "Furniture" (#, Item, W, D), side by side when present.
- "Wall Measurements", split into two column pairs.

Perimeter and area always come from drawn geometry: the area is the shoelace area of the centreline polygon, so it is a gross area including half the wall thickness, not net floor area.

**Fonts.**
- No font is loaded. Every `pw.TextStyle` falls back to the theme default `TextStyle.defaultStyle()`, i.e. the PDF standard Type1 Helvetica / Helvetica-Bold (not embedded).
- In pdf 3.12.0 `PdfType1Font.isRuneSupported` accepts only U+0000–U+00FF. Any other character is replaced by a small crossed `Placeholder` box (`text.dart` `_addPlaceholder`), and debug builds print "Unable to find a font to draw …".
- This affects the em dash `—` (U+2014) in every page footer and in "—" table cells, the bullet `•` (U+2022) on the cover, and any non-Latin-1 room name.
- `m²` (U+00B2) renders correctly.

#### 7.2.3 DXF preview screen

**Trigger.** `IconButton(Icons.architecture, color 0xFF00CCFF, tooltip 'Export DXF')` (L3876–3893) is always enabled. It calls `Navigator.push(context, MaterialPageRoute(builder: (_) => DxfPreviewScreen(shapes: shapes, projectName: _localProjectName.isNotEmpty ? _localProjectName : 'SmartMeasure_Room')))`. `shapes` is the live list, passed by reference.

**What it shows**, top to bottom in a `SingleChildScrollView`:
1. App bar "DXF EXPORT" with an architecture icon, plus an amber `SAMPLE` badge when no real room exists.
2. A blueprint canvas (`AspectRatio(1.55)`) painted by `_BlueprintPainter` from the model:
   - dark background with a 36-px grid and dark room fills;
   - cyan 1.8-px centreline walls and green corner dots;
   - orange door leaf, frame line and arc; three cyan window lines 4 px apart;
   - green furniture rectangles with an X and the type name;
   - per-wall dimension ticks/lines with mm/m labels (bright green when calibrated, yellow-green when drawn) and `W1…Wn` wall indices;
   - a faint watermark `SMARTMEASURE  ·  DXF AC1009`.
3. A file-info card: file name, format `AutoCAD DXF  (AC1009 / R12)`, units `Millimetres  (INSUNITS = 4)`, scale `1 world unit = 5 mm`, layer list, room/wall counts, door/window/opening/furniture counts when greater than 0, and today's date.
4. A "WALL MEASUREMENTS" table (WALL / DRAWN / CALIBRATED), with a room separator row when there are several rooms.
5. A full-width export button, followed either by the sample-mode info box or the caption "DXF opens in AutoCAD, LibreCAD, QCAD and other CAD tools."

**Gestures and controls.** There are no canvas gestures: no pan, zoom or tap, and no `InteractiveViewer`. The only interactions are vertical scrolling, the AppBar back arrow and the export button, which is disabled while exporting.

**Model vs DXF.** The preview is a separate re-implementation of the geometry. It does not read the DXF text, and it differs from the exported file in several ways:
- Openings are invisible (a bug, see 7.3).
- There are no door/window dimension lines.
- Window spacing is a fixed 4 px instead of 55 mm.
- Text sizes are fixed in pixels.
- The bounding box includes furniture centres.

#### 7.2.4 DXF export

**Steps.**
1. The export button calls `_DxfPreviewScreenState._exportDxf()` (L69). It first runs `setState(_isExporting = true)`, which switches the label to "GENERATING DXF…" with a spinner.
2. It calls `await DxfExporter.export(shapes: _previewShapes, projectName: _hasRealRoom ? widget.projectName : 'Sample_Room')`.
3. Any exception is caught and shown as a red `SnackBar('Export failed: $e')`. `finally` resets `_isExporting` if the widget is still mounted.

**Inside `DxfExporter.export` (L20).**
1. `closed = shapes.where(isClosed && points.length >= 3)`. If empty, it throws `Exception('No closed rooms to export')`.
2. `content = _buildDxf(shapes: closed)`.
3. It writes `File('${(await getTemporaryDirectory()).path}/$safe.dxf')` with `writeAsString` (UTF-8, overwritten on every export, never deleted). Here `safe = projectName.replaceAll(RegExp(r'[^\w\-]'), '_')`, so only ASCII letters, digits, `_` and `-` survive (e.g. "My House" → `My_House.dxf`).
4. It calls `Share.shareXFiles([XFile(path, mimeType: 'application/dxf')], subject: '$projectName — Floor Plan')`. The `ShareResult` is ignored.

**Coordinate and unit conversion.** `X_dxf = 5·x`, `Y_dxf = −5·y` (`_wx`/`_wy`), Z = 0. Drawing units are millimetres.
- Normals and directions are computed in world space, then their Y component is negated.
- Angles are written in degrees, counter-clockwise from +X, as the DXF format requires.
- Text rotation is normalised to keep text upright: if the angle is greater than 90° or less than −90°, 180° is added.

**Entities written per closed room, in order:**
1. Closed wall `POLYLINE`.
2. For every wall at least 25 mm long: length `TEXT` plus 3 `LINE`s (two extension lines and one dimension line).
3. Per room object:
   - door: leaf `LINE`, frame `LINE`, `ARC`, then 3 dimension `LINE`s and a width `TEXT`;
   - window: 3 parallel `LINE`s, 2 jamb `LINE`s, then 3 dimension `LINE`s and a `TEXT`;
   - opening: 2 jamb ticks, then 3 dimension `LINE`s and a `TEXT`.
4. Per furniture item: 4 outline `LINE`s, 2 diagonal `LINE`s and a name `TEXT`.
5. A room-name `TEXT`, only when `label` is non-empty.

Details are in 7.3 and 7.4.

**What the user sees:** the Android share sheet offering the `.dxf` file (email, Drive, Files, etc.), with subject "‹project› — Floor Plan".

#### 7.2.5 Sample-room fallback

If `widget.shapes` has no closed room with at least 3 points, `_previewShapes` returns a new synthetic room on every access:

```dart
SketchShape(points: [(0,0),(800,0),(800,600),(0,600)], isClosed: true,
            wallRealMm: {0: 4000, 1: 3000, 2: 4000, 3: 3000})
```

That is 4 m × 3 m with all four walls "calibrated" and no label.

- The UI shows `SAMPLE` badges and the info text "Draw and close a room in the sketch editor to export your actual floor plan. The preview above shows a 4 m × 3 m sample."
- The button reads "DOWNLOAD SAMPLE DXF".
- Exporting really writes and shares `Sample_Room.dxf`. The info card advertises the name as `sample_room.dxf` (different case).

#### 7.2.6 Which measurement each output shows

| Output element | Value used | Text format |
|---|---|---|
| PDF overview chains, top/bottom | Drawn bounding-box/breakpoint distances | `formatLength`: `< 1000 mm` → "850 mm", else "4.00 m" |
| PDF overview chains, left/right | Drawn | `_formatVerticalMeters`: always "x.xx m" |
| PDF room-page wall labels | `wallRealMm[i]` if present, else drawn × 5 | always "x.xx m" |
| PDF "Wall Measurements" table | `wallRealMm[i]` → `_fmtMm` ("x.xxx m" if ≥ 1000, else "n mm"); otherwise drawn → `formatLength` ("x.xx m"/"n mm") | 3 decimals for calibrated walls, 2 for drawn ones |
| PDF perimeter, area (cover, index, stats row, overlays) | Drawn geometry only | `formatLength` / `formatArea` ("x.xx m²", or "n mm²" below 0.01 m²) |
| PDF objects/furniture tables | `widthMm`, `heightMm`, `elevationMm` (shown as "—" if 0), `depthMm` | `_fmtMm` |
| PDF HEIGHT stat | `SketchShape.heightMm` (default 2400) | "2400 mm" |
| DXF wall `TEXT` | `wallRealMm[i]` (ACI 3 green) else drawn × 5 (ACI 2 yellow) | DXF `_fmtMm`: "x.xx m" / "n mm" |
| DXF door/window/opening `TEXT` | `widthMm` | DXF `_fmtMm` |
| Preview canvas wall labels | `wallRealMm[i]` (0xFF00FF88) else drawn × `mmPerUnit` (0xFFCCEE88) | preview `_fmtMm` (same as DXF) |
| Preview wall table | DRAWN: `formatLength(drawn)`; CALIBRATED: `"${mm.toStringAsFixed(0)} mm"` or "—" | mixed units for the same wall |

### 7.3 File reference

#### `code/lib/sketch/sketch_pdf_export.dart` — 1499 lines

- **Purpose:** Builds the multi-page A4 "Floor Plan Guide" PDF from the sketch shapes and opens the OS print dialog for it. The file contains its own coordinate transformer, vector painters for walls, doors, windows, openings and furniture, an architectural dimensioning subsystem, and table/layout helpers.

- **Depends on:**
  - `dart:math` as `math` (min/max/atan2/cos/sin/pi).
  - `package:flutter/material.dart` with `show BuildContext, Color, Offset, ScaffoldMessenger, SnackBar, Text`. These are used only for the "Draw a room first" SnackBar and for `Offset` geometry.
  - `package:pdf/pdf.dart` (`PdfColor`, `PdfColors`, `PdfPageFormat`, `PdfGraphics`, `PdfPoint`) and `package:pdf/widgets.dart` as `pw` (pdf ^3.12.0, locked 3.12.0).
  - `package:printing/printing.dart` (`Printing.layoutPdf`; printing ^5.13.1, locked 5.13.1).
  - `sketch_constants.dart`: `mmPerUnit`, `wallThickness`, `thickWallRect`, `formatLength`, `formatArea`.
  - `sketch_model.dart`: `SketchShape`. `room_object.dart`: `RoomObject`. `furniture_item.dart`: `FurnitureItem`, plus the `FurnitureType` extension getters `color` and `displayName`.

- **Declarations:**

  *Layout constants (L15–24):*

  | Name | Value | Meaning / use |
  |---|---|---|
  | `_cs` | 296.0 | Original canvas square size. Still the default `size` of `_canvasBox` and the `canvasSize` that `_txFor` picks for `da == _da`. Both of those are overridden by every caller, so it is effectively legacy. |
  | `_cm` | 18.0 | Default `_Tx.margin`. |
  | `_da` | 260.0 (`_cs − 2·_cm`) | Drawable plan size on room pages. |
  | `_csOv` | 480.0 | Original overview size. Only used inside `_txFor` (overridden) and to derive `_daOv`. |
  | `_daOv` | 444.0 (`_csOv − 2·_cm`) | Drawable plan size on the overview. |
  | `_dimMargin` | 30.0 | Overview margin reserved for dimension chains (comment: "the plan keeps its existing scale"). |
  | `_csOvDim` | 504.0 (`_daOv + 2·_dimMargin`) | Real overview canvas size. |
  | `_roomDimMargin` | 22.0 | Room-page margin for wall dimensions. |
  | `_csRoomDim` | 304.0 (`_da + 2·_roomDimMargin`) | Real room canvas size. |

  *Dimension constants (L730–739):* `_dimColor = PdfColor(0.30, 0.30, 0.30)`, `_dimArrowSize = 3.0`, `_dimSegOffset = 7.0`, `_dimTotalOffset = 16.0`, and the getter `_dimTextStyle` (6.5 pt, normal weight, `_dimColor`).

  *`class _Tx` (L27)*: immutable world→PDF transformer.
  - Fields (all `double`): `minX`, `minY` (world bounding-box origin), `scale` (pt per world unit), `canvasSize` (pt, square canvas side), `margin` (pt, default `_cm`).
  - Constructor `const _Tx(this.minX, this.minY, this.scale, this.canvasSize, [this.margin = _cm])`.
  - `PdfPoint call(Offset w)` (L32) returns `(margin + (w.dx−minX)·scale, canvasSize − margin − (w.dy−minY)·scale)`.

  *Transform factories:*
  - `_Tx _txFor(List<Offset> pts, [double da = _da])` (L38): computes the bounding box with `reduce`, which throws on an empty list, so callers must not pass one. It returns `_Tx(minX, minY, s, canvasSize)` with `s = da / max(clamp(maxX−minX, 1, ∞), clamp(maxY−minY, 1, ∞))` and `canvasSize = da == _da ? _cs : _csOv`.
  - `_Tx _txAll(List<SketchShape> shapes, [double da = _da])` (L49): flattens all points of all shapes and calls `_txFor`.

  *Public entry:*
  - `Future<void> exportSketchPdf({required BuildContext context, required List<SketchShape> shapes, required String projectName})` (L55). See 7.2.1.

  *Page builders (each returns a single `pw.Page`, not `MultiPage`):*
  - `pw.Page _coverPage(List<SketchShape> valid, String projectName, int totalPages)` (L91). A4, `margin: EdgeInsets.zero`, `Column(stretch)` with:
    1. Navy header `Container(color: PdfColor(0.13, 0.20, 0.30), padding LTRB 44,52,44,36)` containing:
       - "FLOOR PLAN GUIDE" (26 pt bold white, letterSpacing 2);
       - `projectName` or `'SmartMeasure Project'` if empty (13 pt blueGrey100);
       - `'Generated  ${_date()}   •   SmartMeasure Pro'` (8.5 pt blueGrey300).
    2. Stats bar `PdfColor(0.19, 0.29, 0.41)` (padding h44 v14, `spaceAround`) with `_coverStat('ROOMS', closedCount)`, where `closedCount` counts the closed valid shapes; `_coverStat('TOTAL AREA', formatArea(Σ _shapeArea))`; and `_coverStat('TOTAL PAGES', totalPages)`.
    3. A 32 pt gap.
    4. Table of contents (padding h44):
       - "TABLE OF CONTENTS" (10 pt bold navy, letterSpacing 1.8), then a navy 1.5 divider;
       - `_tocRow('Full Floor Plan Overview', 2, bold: true)`;
       - one `_tocRow(_roomName(valid[i], i), 3 + i, sub: _roomSub(valid[i]))` per valid shape, with blueGrey dividers.
    5. `Spacer`.
    6. Footer (padding LTRB 44,0,44,28): "SmartMeasure Pro — Floor Plan Guide" and "Page 1 of N" (7.5 pt grey500).
  - `pw.Page _overviewPage(List<SketchShape> valid, String projectName, int pageNum, int totalPages)` (L202). `baseTx = _txAll(valid, _daOv)` and `tx = _Tx(baseTx.minX, baseTx.minY, baseTx.scale, _csOvDim, _dimMargin)`. A4, margin 32. The Column contains:
    1. `_pageHeader('Full Floor Plan', projectName, …)`, then a 10 pt gap.
    2. `Center(_canvasBox(Stack[...], size: 504))`. The Stack holds `Positioned.fill(CustomPaint(painter: grid + passes 1–3 + _paintFullPlanDimensions))`, then name and area overlays for closed shapes with at least 3 points, then `..._fullPlanDimensionLabels(valid, tx)`.
    3. A 14 pt gap, `_sectionLabel('Room Index')`, a 5 pt gap.
    4. A `pw.Table` with a blueGrey200 0.5 border. Columns: 0 = Fixed 22 "#", 1 = Flex 2.2 "Room Name", 2 = Flex 1.4 "Perimeter", 3 = Flex 1.4 "Area", 4 = Fixed 30 "Pg". The header row has blueGrey100 shading. Each row holds `i+1`, `_roomName`, `_perimStr`, `_areaStr` and `3+i`.
    5. `Spacer` and `_pageFooter`.
    In pass 3 the centroid is recomputed inline, and objects are painted only `if (s.isClosed && s.roomObjects.isNotEmpty)`, with `wallThickness` as the gap thickness.
  - `pw.Page _roomPage(SketchShape shape, int roomIdx, int pageNum, int totalPages, double referenceScale)` (L342). It computes `n`, `wallCount` (`n` if closed, else `n−1`), `baseTx = _txFor(shape.points)` (da 260), `tx = _Tx(..., _csRoomDim, _roomDimMargin)`, `effectiveWallThickness`, the centroid, and the flags `hasDW`/`hasFurn`. A4, margin 32. The Column contains:
    1. `_pageHeader(_roomName(shape, roomIdx), null, …, accent: true)`, then a 10 pt gap.
    2. A 304 pt canvas: grid, fill, walls, corner dots, furniture, objects (if closed), `_paintRoomWallDimensions`; overlays `_roomAreaOverlay` (closed, at least 3 points) and `..._roomWallDimensionLabels`.
    3. A 10 pt gap, then `_statsRow` if closed, then a 10 pt gap.
    4. If there are objects or furniture: a `Row` with `Expanded(_dwTable)` and `Expanded(_furnitureTable)` separated by 10 pt, then a 10 pt gap.
    5. `_wallsTable`, `Spacer`, `_pageFooter`.

  *Canvas painters:*
  - `void _paintGrid(PdfGraphics g, PdfPoint size)` (L480): grey200 lines, 0.3 pt, every 20 pt across the whole canvas.
  - `void _paintRoomObjects(PdfGraphics g, List<Offset> pts, int n, int wallCount, List<RoomObject> objects, _Tx tx, Offset centroid, double wallThicknessWorld)` (L496). For each object it:
    1. skips it if `wallIndex >= wallCount` or the wall is shorter than 1 unit;
    2. computes the opening endpoints `startW`/`endW` in world space;
    3. orients the inward normal `inW`;
    4. converts to PDF: `sP = tx(startW)`, `eP = tx(endW)`, `wdPdf = (wallDir.dx, −wallDir.dy)`, `inPdf = (inW.dx, −inW.dy)`, `widPdf = widthMm/mmPerUnit·tx.scale`, `wallGapPdf = wallThicknessWorld·tx.scale + 1.0`;
    5. dispatches to `_paintDoor` if `isDoor`, `_paintOpening` if `isOpening`, else `_paintWindow`.
  - `void _paintDoor(PdfGraphics g, PdfPoint start, PdfPoint end, Offset wallDirPdf, Offset inWPdf, double widthPdf, double gapWidthPdf)` (L556). It strokes:
    1. the white gap;
    2. the leaf `start → start + inWPdf·widthPdf` and the frame `start → end`, both blueGrey800 at 1.5 pt;
    3. the swing arc, 0.8 pt: `cross = wd × in`, `sweepSign = cross > 0 ? −1 : +1`, `arcStart = atan2(in)`, with 25 points at `arcStart + sweepSign·(s/24)·π/2`, radius `widthPdf` around the hinge. The arc runs from the leaf tip back to the far jamb.
  - `void _paintWindow(PdfGraphics g, PdfPoint start, PdfPoint end, Offset inWPdf, double widthPdf, double gapWidthPdf)` (L615): white gap, then three lines at `inWPdf·t·7` for `t ∈ {−0.38, 0, 0.38}`, colour `PdfColor(0.00, 0.49, 0.76)`, width 1.5 for the centre line and 0.8 otherwise. `widthPdf` is unused.
  - `void _paintOpening(PdfGraphics g, PdfPoint start, PdfPoint end, Offset inWPdf, double gapWidthPdf)` (L643): white gap, then a tick at each end from `p − inW·4` to `p + inW·4` (blueGrey400, 0.8 pt).
  - `void _paintFurniture(PdfGraphics g, FurnitureItem item, _Tx tx)` (L669):
    - Half sizes in world units: `hw = widthMm/mmPerUnit/2`, `hd = depthMm/mmPerUnit/2`.
    - The local closure `rotW(lx, ly) = position + (lx·cos − ly·sin, lx·sin + ly·cos)` maps corners `c1(−hw,−hd)`, `c2(hw,−hd)`, `c3(hw,hd)`, `c4(−hw,hd)`, which are then passed through `tx`.
    - Fill `PdfColor(0.65+0.35r, 0.65+0.35g, 0.65+0.35b)`, where r/g/b are `Color.r/.g/.b` doubles in 0–1 from `item.type.color`.
    - Border `PdfColor(0.7r, 0.7g, 0.7b)` at 0.8 pt; diagonals c1–c3 and c2–c4 at `0.5×` colour, 0.4 pt.

  *Dimension subsystem:*
  - `void _drawLine(PdfGraphics g, double x1, double y1, double x2, double y2, {double width = 0.4})` (L741): stroke in `_dimColor`.
  - `void _drawArrowHead(PdfGraphics g, double tipX, double tipY, double angleRad)` (L750): filled triangle with tip at (tipX, tipY) and barbs at `angle ± 2.6` rad, length 3 pt. The half-opening is about 31°, pointing along `angleRad`.
  - `void _drawHDimLine(PdfGraphics g, double x1, double x2, double lineY)` (L764): 0.5 pt line, with arrows at x1 (angle π) and x2 (angle 0). It assumes `x1 < x2`.
  - `void _drawVDimLine(PdfGraphics g, double y1, double y2, double lineX)` (L770): 0.5 pt line, with arrows at y1 (−π/2) and y2 (+π/2). Callers pass min/max.
  - `pw.Widget _dimLabel(double x, double y, String text, double canvasSize, {bool vertical = false, double rotation = -math.pi / 2})` (L776):
    - Returns a `pw.Positioned` with `left = x − 16` and `top = canvasSize − y − h/2`, where h = 14, or 32 when vertical.
    - Vertical labels wrap a 32 × 14 one-line text in `pw.Transform.rotate(angle: rotation)`. The rotation is counter-clockwise in PDF space, so +π/2 reads bottom-to-top and −π/2 top-to-bottom.
    - `final width = vertical ? 32.0 : 32.0` is a redundant ternary.
  - `Offset _centroidOf(SketchShape s)` (L808): vertex average.
  - `List<double> _xBreakpointsAtY(List<SketchShape> shapes, double y, double minX, double maxX, {double tol = 3.0})` (L816) and its mirror `_yBreakpointsAtX(...)` (L833): collect `{minX, maxX}` plus the x of every vertex (across all shapes) with `|p.dy − y| < tol`, sort, and merge values closer than `tol`.
  - `void _paintFullPlanDimensions(PdfGraphics g, List<SketchShape> shapes, _Tx tx)` (L850). It recomputes the bounding box over all points. For each side:
    - **Top** uses `topY = tx(minX, minY).y`, which is the top of the page because of the Y flip. Extension lines (0.3 pt) run from `topY` to `topY + 16 + 3` at each breakpoint; segment dimensions sit at `topY + 7` and the overall dimension at `topY + 16`.
    - **Bottom** mirrors this at `botY − 7` / `botY − 16`; **left** at `leftX − 7` / `leftX − 16`; **right** at `rightX + 7` / `rightX + 16`.
  - `List<pw.Widget> _fullPlanDimensionLabels(List<SketchShape> shapes, _Tx tx)` (L921): matching texts at the midpoint of each segment.
    - Top: `topY + 11` (segments) and `topY + 20` (overall). Bottom: `botY − 11` and `botY − 20`.
    - Left: `leftX − 11` and `leftX − 20`, rotated +π/2. Right: `rightX + 10` and `rightX + 19`, default −π/2.
    - Horizontal texts use `formatLength(Δ)`; vertical texts use `_formatVerticalMeters(Δ)`.
  - `void _paintRoomWallDimensions(PdfGraphics g, SketchShape shape, _Tx tx, int wallCount)` (L991). For each wall at least 1 unit long:
    - outward normal `(−dy, dx)/len`, flipped if `(mid − centroid)·normal < 0`, then converted to PDF space (`y` negated);
    - dimension line from `pa + N·7` to `pb + N·7` (0.5 pt);
    - extension lines from `pa`/`pb` to 3 pt beyond the dimension line (0.3 pt);
    - arrowheads at both ends, oriented by `atan2` of the line.
  - `List<pw.Widget> _roomWallDimensionLabels(SketchShape shape, _Tx tx, int wallCount)` (L1030): one `_dimLabel` per wall at `midpoint + N·14`. It is vertical when `|Δx| < |Δy|` in PDF space and uses the default −π/2 rotation. The text is `_wallLenMeters(shape, i, n)`.

  *Table builders:*
  - `pw.Widget _dwTable(List<RoomObject> objects)` (L1068): `_sectionLabel('Doors, Windows & Openings')` plus a table with columns # (Fixed 18), Type (Flex 1.5), Width (1.4), Height (1.4), Elev. (1.3).
    - Type is `'Door'`, `'Opening'` or `'Window'`.
    - Width and Height use `_fmtMm`. Elev. uses `_fmtMm` when `elevationMm > 0`, else "—".
    - It lists **all** objects, including those skipped in the drawing because `wallIndex >= wallCount`.
  - `pw.Widget _furnitureTable(List<FurnitureItem> items)` (L1108): `_sectionLabel('Furniture')` plus columns # (18), Item (Flex 2.2, `type.displayName`), W (1.3, `_fmtMm(widthMm)`), D (1.3, `_fmtMm(depthMm)`). Rotation and position are not listed.
  - `pw.Widget _wallsTable(SketchShape shape, int wallCount)` (L1144):
    - Returns an empty `SizedBox` when there are no walls.
    - Otherwise `half = (wallCount+1) ~/ 2`, with five columns: Wall (Flex 0.8), Length (1.6), blank spacer (Fixed 12), Wall (0.8), Length (1.6).
    - Row `i` shows `W i+1` and `_wallLen(i)` on the left, and `W i+half+1` and its length on the right when it exists.

  *Widget helpers:*
  - `_roomLabelOverlay(SketchShape s, int idx, _Tx tx)` (L1195): `Positioned(left: x−24, top: canvasSize − y − 6)` holding a 48 pt-wide centred `_roomName` (7 pt bold blueGrey900). Long names wrap onto more lines.
  - `_roomAreaOverlay(SketchShape s, _Tx tx)` (L1224): `Positioned(left: x−32, top: canvasSize − y + 7)` holding a 64 pt-wide `formatArea(_shapeArea(s))` (7 pt blueGrey700).
  - `_canvasBox(pw.Widget child, {double size = _cs})` (L1245): `Container(size × size, white, Border.all(blueGrey300), radius 4)`.
  - `_pageHeader(String title, String? subtitle, int pageNum, int totalPages, {bool accent = false})` (L1256):
    - Title is 14 pt bold, blue `PdfColor(0.09, 0.40, 0.71)` when `accent`, else blueGrey800.
    - Optional subtitle is 8.5 pt grey500.
    - A "Page X of N" badge (blueGrey50 fill, blueGrey200 border, 7.5 pt blueGrey600).
  - `_pageFooter(String label, int pageNum, int totalPages)` (L1302): blueGrey200 `Divider`, then the label and "Page X of N" (7 pt grey500).
  - `_statsRow(SketchShape shape, int wallCount)` (L1318): blueGrey50 box with WALLS = `wallCount`, PERIMETER = `_perimStr`, AREA = `_areaStr`, HEIGHT = `'${heightMm.toStringAsFixed(0)} mm'`, separated by `_vDiv`.
  - Small styled text helpers:
    - `_statItem` (L1341): 7 pt blueGrey500 label over a 9 pt bold blueGrey800 value.
    - `_vDiv` (L1353): 0.5 × 26 blueGrey200 divider.
    - `_sectionLabel` (L1356): 8.5 pt bold blueGrey700.
    - `_thCell` (L1362): padding 5/4, 7.5 pt bold blueGrey700.
    - `_tdCell` (L1372): padding 5/3, 7.5 pt blueGrey800.
    - `_coverStat` (L1380): 7.5 pt blueGrey200 label over a 14 pt bold white value.
  - `_tocRow(String name, int page, {String? sub, bool bold = false})` (L1395): 14 pt indent unless `bold`; name 10 pt (bold if `bold`); optional 7.5 pt grey500 sub-line; right-aligned 20 pt-wide page number (10 pt bold blue).

  *Data helpers:*
  - `double _shapeArea(SketchShape s)` (L1435): shoelace `|Σ(xᵢ·yⱼ − xⱼ·yᵢ)|/2` in world units², and 0 unless closed with at least 3 points.
  - `double _shapePerimeter(SketchShape s)` (L1447): sum of the wall lengths (`n` or `n−1` walls).
  - `_perimStr` (L1458) and `_areaStr` (L1463): formatted value, or "—" when 0.
  - `String _wallLen(SketchShape s, int i, int n)` (L1468): `_fmtMm(wallRealMm[i])` if calibrated, else `formatLength(drawn)`.
  - `String _wallLenMeters(SketchShape s, int i, int n)` (L1475): `(wallRealMm[i] ?? drawn·mmPerUnit)/1000` with 2 decimals plus " m".
  - `String _formatVerticalMeters(double worldUnits)` (L1481): `worldUnits·5/1000` with 2 decimals plus " m".
  - `String _roomName(SketchShape s, int idx)` (L1484): `label` if non-empty, else `'Room ${idx+1}'`, where `idx` is the index within `valid`.
  - `String _roomSub(SketchShape s)` (L1487): `'Area: …'` or `''`.
  - `String _fmtMm(double mm)` (L1492): `≥ 1000` → `'x.xxx m'` (**3** decimals), else `'n mm'`.
  - `String _date()` (L1495): local `yyyy-MM-dd`.

- **Key logic:**
  1. *Fit-to-box transform.* Each canvas maps the world bounding box of the wall vertices into a square `da` area: `s = da / max(w, h)`, with the margin added on the left and the Y axis flipped. The plan is anchored at the canvas's bottom-left (`minX → margin`, `minY → top`). It is not centred: a wide plan leaves empty space at the bottom of the square canvas, and a tall plan leaves it on the right.
  2. *Wall-thickness normalisation.* `effectiveWallThickness = wallThickness × referenceScale / tx.scale`, so `thickness_pt = 30 × referenceScale` on every page.
  3. *Inward/outward orientation.* The sign of `(centroid − wallMid) · normal` decides the side. This is correct for convex rooms. For concave rooms (L-shapes) the vertex average can lie on the wrong side of a wall, flipping that wall's door swing or putting its dimension inside the room.
  4. *Door arc direction.* `cross = wd × in` (2-D cross product in PDF space). If it is positive, the inward vector is 90° counter-clockwise from the wall direction, so the arc sweeps clockwise (`−1`) from the leaf to the jamb, and vice versa.
  5. *Draw order.* On the overview, furniture of room B can paint over walls; door gaps are painted after all walls. On room pages, furniture paints over walls and corner dots, while the comment at L422 claims the opposite ("drawn before doors/windows so walls overlay them"). The white gap over the light-blue fill leaves a white notch half a wall thick on the room side.
  6. *Dimension chains* are built only from vertices that touch the bounding box (±15 mm). Interior jogs of irregular outlines are not dimensioned, and extension lines start at the bounding-box edge even where the wall is set back.

- **State and data:** This is a stateless functional module: no globals beyond `const`s, and nothing cached or persisted. Input is `List<SketchShape>` plus a project name. Output is an in-memory `pw.Document` that is serialised by `pdf.save()` inside the print callback. Page count is `2 + valid.length`, and page numbers are hard-coded (`3 + i`), which is correct because each shape gets exactly one page.

- **UI:** The PDF itself is the UI (described above and in 7.4). The only Flutter UI is the "Draw a room first" SnackBar and the platform print dialog opened by `printing`.

- **Connections:** Imported and called only by `sketch_screen.dart` (import L14, call L3864). It uses `sketch_constants.dart`, `sketch_model.dart`, `room_object.dart` and `furniture_item.dart`. It does not use `SketchShape.sharedWalls`, `id`, `RoomObject.id/ownerShapeId`, `FurnitureType.heightMm/icon`, or `wall_openings.dart` / `wall_topology.dart`.

- **Notes and issues:**
  - **Glyph bug (confirmed against pdf 3.12.0 source):** `—` (U+2014) and `•` (U+2022) are outside Helvetica's supported U+0000–00FF range. They render as crossed placeholder boxes in every footer, the cover subtitle, and the "—" table cells. Non-Latin-1 room names (e.g. Sinhala or Tamil) are affected the same way. No font is embedded and no `fontFallback` is set.
  - **No pagination:** every page is a single `pw.Page`. Content taller than A4 is not paginated and runs off the bottom of the page. Rough estimates: the overview's room index overflows at about a dozen rooms, a room page at about 20 table rows (objects + furniture + half the walls), and the cover's table of contents at about 15 rooms.
  - **Dimensions can disappear into thick walls (derived from the formulas):** dimension offsets are fixed in pt (7/16 pt from the wall **centreline**), while wall half-thickness scales with the plan. For small plans the dimension lines and labels fall inside the black wall band; one 4 × 3 m room gives a half-thickness of 8.3 pt.
  - **Calibrated lengths are mostly ignored:** the overview dimensions, perimeters and areas use drawn geometry; only the room-page labels and the walls table use `wallRealMm`.
  - **Inconsistent number formats:** 3 decimals for calibrated walls in the table, 2 for drawn ones; horizontal overview dimensions switch between mm and m, vertical ones are always m; the DXF uses 2 decimals.
  - **Wall corners are not joined:** each wall is an independent centred rectangle, so every outer corner shows a notch of `t/2 × t/2`.
  - **Clipping:** the bounding box ignores furniture, and `pw.Stack` clips by default (`Overflow.clip`), so furniture outside the wall bounding box is cut at the canvas edge.
  - **Open shapes are treated inconsistently:** shapes with at least 2 points that are not closed get a "Room N" page and table-of-contents entry, but are not counted in the cover's ROOMS stat and have no fill, area, name overlay or door/window symbols. Their furniture is still drawn.
  - **Different scale per page:** no scale ratio or scale bar is printed, and rooms of different sizes are printed at different scales.
  - **Print-only delivery:** there is no direct save or share. The chosen paper format is ignored, the `layoutPdf` result is ignored, and errors are unhandled because the call is not awaited.
  - **Dead or misleading code:**
    - the `canvasSize` branch in `_txFor` is always overridden, which makes `_cs` and `_csOv` effectively legacy;
    - `_paintWindow`'s `widthPdf` parameter is unused;
    - `_dimLabel` contains the redundant ternary `vertical ? 32.0 : 32.0`;
    - the comment at L422 contradicts the actual draw order;
    - the centroid is computed in four places (`_overviewPage`, `_roomPage`, `_roomLabelOverlay`, `_centroidOf`);
    - the "Draw a room first" SnackBar branch is unreachable from the current call site.
  - **Cross-part inconsistency:** wall thickness is 150 mm in the PDF (`wallThickness = 30` units), 200 mm in the 3D view (`'wallThicknessM': 0.2`, `room_3d_screen.dart` L174), and 0 in the DXF and preview. The trailing comment `// world units (~50mm real)` after `thickWallRect` in `sketch_constants.dart` L34 is wrong: 30 units = 150 mm.

#### `code/lib/screens/dxf_exporter.dart` — 381 lines

- **Purpose:** A static utility that serialises closed rooms (walls, wall-length annotations, doors, windows, openings, furniture, room names) into an AutoCAD R12 ASCII DXF string, writes it to a temporary file, and opens the system share sheet.

- **Depends on:**
  - `dart:io` (`File`); `dart:math` as `math`.
  - `package:flutter/material.dart`, imported only for `Offset`.
  - `package:path_provider/path_provider.dart` (`getTemporaryDirectory`; ^2.1.3, locked 2.1.5).
  - `package:share_plus/share_plus.dart` (`Share.shareXFiles`, `XFile`; ^9.0.0, locked 9.0.0).
  - `../sketch/sketch_model.dart` (`SketchShape`), `../sketch/room_object.dart` (`RoomObject`), `../sketch/furniture_item.dart` (`FurnitureItem`, `displayName`).
  - It does **not** import `sketch_constants.dart`, so the 5 mm factor is duplicated.

- **Declarations:** `class DxfExporter` (L17) has only static members. It has no private constructor, so `DxfExporter()` is constructible but useless. The header comment (L10–15) says "AutoCAD R12 (AC1009)", lists layers WALLS (blue-5), DOORS (red-1), WINDOWS (cyan-4), OPENINGS (**"yellow-8"**, but ACI 8 is dark grey) and FURNITURE (green-3), omits ROOM_NAMES, and states "Units: millimetres | 1 world unit = 5 mm | Y axis flipped".

  | Member | Line | Signature and behaviour |
  |---|---|---|
  | `_mm` | L18 | `static const double _mm = 5.0`: world units → mm (duplicates `mmPerUnit`). |
  | `export` | L20 | `static Future<void> export({required List<SketchShape> shapes, String projectName = 'SmartMeasure_Room'})`: filter, build, write the temp file, share (see 7.2.4). Throws `Exception('No closed rooms to export')`. |
  | `_wx` | L41 | `static double _wx(double worldX) => worldX * _mm`. |
  | `_wy` | L42 | `static double _wy(double worldY) => -(worldY * _mm)` (Y flip). |
  | `_f` | L43 | `static String _f(double v) => v.toStringAsFixed(4)`. |
  | `_buildDxf` | L46 | `static String _buildDxf({required List<SketchShape> shapes})`: writes bounds, HEADER, TABLES, ENTITIES and EOF (see Key logic). |
  | `_writeWalls` | L131 | `(StringBuffer buf, List<Offset> points, int n)`: one closed `POLYLINE` (layer WALLS, colour 5, `66=1`, `70=1`, dummy `10/20/30 = 0,0,0`), a `VERTEX` (layer WALLS) per point, and `SEQEND` (layer WALLS). `n` is unused inside. |
  | `_writeWallDims` | L144 | `(StringBuffer buf, List<Offset> points, Map<int,double> wallRealMm, int n)`: per-wall length text and dimension lines (see Key logic). |
  | `_writeRoomObjects` | L181 | `(StringBuffer buf, List<Offset> points, int n, List<RoomObject> roomObjects)`: computes opening endpoints and inward normals in world space, converts to DXF, and dispatches to door, opening or window. |
  | `_writeDoor` | L224 | `(StringBuffer buf, double sx, double sy, double ex, double ey, double widthMm, double wux, double wuy, double iux, double iuy)`: leaf, frame, arc, dimensions and width text on layer DOORS, colour 1. |
  | `_writeOpening` | L252 | Same parameters as `_writeDoor`: jamb ticks plus dimensions, layer OPENINGS, colour 8. |
  | `_writeWindow` | L273 | Same parameters: three parallel lines, jambs and dimensions, layer WINDOWS, colour 4. |
  | `_writeFurniture` | L300 | `(StringBuffer buf, List<FurnitureItem> items)`: rotated outline, X diagonals and name text. |
  | `_writeRoomLabel` | L330 | `(StringBuffer buf, List<Offset> points, int n, String label)`: `TEXT` at the vertex average, layer ROOM_NAMES, colour 2, height 80, rotation 0. |
  | `_line` | L338 | `(buf, String layer, int color, x1, y1, x2, y2)` emits `0 LINE`, `8 layer`, `62 color`, `10/20/30` start (z `0.0`), `11/21/31` end. |
  | `_arc` | L346 | `(buf, layer, color, cx, cy, radius, startAngle, endAngle)` emits `0 ARC`, `8`, `62`, `10/20/30` centre, `40` radius, `50` start°, `51` end° (drawn counter-clockwise from start to end). |
  | `_writeText` | L357 | `(buf, layer, color, tx, ty, angleDeg, height, text)` emits `0 TEXT`, `8`, `62`, `10/20/30`, `40` height, `1` text, `50` rotation°, `7 STANDARD`, `72 1` (horizontal centre), `73 2` (vertical middle), and `11/21/31` alignment point = the same point. |
  | `_w` | L370 | `(StringBuffer buf, int code, String value)`: writes `code.toString().padLeft(3)`, CRLF, `value`, CRLF. |
  | `_fmtMm` | L377 | `static String _fmtMm(double mm)`: `≥ 1000` → `'x.xx m'`, else `'n mm'`. |

- **Key logic:**
  1. **Bounds (L49–64):** min/max over `(_wx, _wy)` of every wall vertex and every furniture **centre** of all exported rooms. Padding `px = 0.15·width + 300` and `py = 0.15·height + 300` mm is applied on every side. These values feed both `$EXTMIN/$EXTMAX` and `$LIMMIN/$LIMMAX`.
  2. **HEADER (L66–76):**
     - `$ACADVER` (1) = `AC1009`;
     - `$INSUNITS` (70) = `4` (mm);
     - `$MEASUREMENT` (70) = `1` (metric);
     - `$EXTMIN`, `$EXTMAX`, `$LIMMIN`, `$LIMMAX` written with group codes 10/20 only (no 30).
  3. **TABLES (L78–109):**
     - `LTYPE` table (`70=1`): `CONTINUOUS` (`70=0`, `3='Solid line'`, `72=65`, `73=0`, `40=0.0`).
     - `LAYER` table with `70=6`, although **7** records are written: `0`/7, `WALLS`/5, `DOORS`/1, `WINDOWS`/4, `OPENINGS`/8, `FURNITURE`/3, `ROOM_NAMES`/2. Each has `70=0` and `6=CONTINUOUS`.
     - `STYLE` table (`70=1`): `STANDARD` (`70=0`, `40=0.0` variable height, `41=1.0` width factor, `50=0.0` oblique, `71=0`, `42=2.5` last height, `3='txt'` font file, `4=''` big font).
     - There is no BLOCKS section, no VPORT/VIEW/UCS/APPID/DIMSTYLE table, and no entity handles.
  4. **ENTITIES (L111–125):** for each closed room, in order: `_writeWalls`, `_writeWallDims`, `_writeRoomObjects`, `_writeFurniture`, then `_writeRoomLabel` if `label.isNotEmpty`. The file ends with `ENDSEC` and `EOF`.
  5. **Wall dimensions (`_writeWallDims`).** Everything here is in DXF mm.
     - The centroid `(cx, cy)` is the vertex average.
     - For each wall `i` in `0..n−1`, walls shorter than 25 mm are skipped.
     - Unit direction `u`; normal `n = (−uy, ux)`, flipped if `(c − mid)·n > 0` so that it points **away** from the room.
     - Text: at `mid + n·80`, rotation `atan2(u)` in degrees normalised to stay upright, height 50, content `_fmtMm(wallRealMm[i] ?? drawnLen·5)`. Colour is **3** (green) if `wallRealMm` contains `i`, else **2** (yellow).
     - Lines (layer WALLS, colour 8): extension lines from `a + n·8` to `a + n·100` and `b + n·8` to `b + n·100`, and the dimension line from `a + n·80` to `b + n·80`. There are no ticks or arrowheads, and this is not a `DIMENSION` entity.
     - The text centre lies exactly on the dimension line, so the line strikes through the text.
  6. **Room objects (`_writeRoomObjects`).** These steps work in world units:
     - The centroid is the vertex average.
     - Objects with `wallIndex >= n` or walls shorter than 1 unit are skipped.
     - `halfW = widthMm/5/2` and `tCenter = positionAlong·wallLen`. `startW` and `endW` are `wA + wallDir·(tCenter ∓ halfW)`.
     - `inW = (−dir.dy, dir.dx)` is flipped toward the centroid, then flipped again if `swingFlipped`.
     - Conversion to DXF: `s = (_wx, _wy)(startW)`, `e = …(endW)`, `wu = (dir.dx, −dir.dy)`, `iu = (inW.dx, −inW.dy)`.
  7. **Door (`_writeDoor`):**
     - Leaf `LINE` from `s` to `s + iu·widthMm` (the door is drawn fully open, 90°).
     - Frame `LINE` from `s` to `e`.
     - `ARC` centred at `s` with radius `widthMm`. `wallAng = atan2(wu)` and `inwardAng = atan2(iu)` (degrees). If `cross(wu, iu) > 0` the arc runs `wallAng → inwardAng`, otherwise `inwardAng → wallAng`, which always gives the 90° counter-clockwise sweep between the two.
     - Dimension on the side **opposite** the swing (`o = −iu`): extension lines from `s/e + o·5` to `s/e + o·65`, dimension line at `o·50`, and a width `TEXT` (height 40) at `mid + o·50`, again centred on the line.
  8. **Window (`_writeWindow`):**
     - Three `LINE`s from `s + iu·t` to `e + iu·t` for `t ∈ {−55, 0, 55}` mm.
     - Jamb `LINE`s from `s − iu·130` to `s + iu·130`, and the same at `e` (260 mm long).
     - The same dimension block at 50 mm. The dimension line sits only 5 mm from the outer window line at 55 mm, and the 40 mm text overlaps the window symbol.
  9. **Opening (`_writeOpening`):** jamb ticks of ±60 mm at `s` and `e`, plus the same dimension block, all colour 8 on layer OPENINGS.
  10. **Furniture (`_writeFurniture`).** Here `(cx, cy)` is the item centre in DXF coordinates and `rad = rotationDeg·π/180`.
      - Axes: `u = (cos, −sin)` and `v = (sin, cos)`. Half sizes `hw = widthMm/2` and `hd = depthMm/2` are already in mm.
      - Corners: `c0 = c + u·hw + v·hd`, `c1 = c − u·hw + v·hd`, `c2 = c − u·hw − v·hd`, `c3 = c + u·hw − v·hd`.
      - These are exactly the world rectangle corners, Y-flipped. The rotation is consistent with the PDF and preview: positive `rotationDeg` is clockwise on screen, and becomes clockwise in the Y-up DXF as well because of the mirror.
      - Output: 4 outline `LINE`s (colour 3), diagonals c0–c2 and c1–c3 (colour **8**), and `TEXT(displayName)` at the centre (colour 3, height 40, rotation 0, not rotated with the item).
  11. **Room label:** `TEXT` at the vertex average (height 80, ROOM_NAMES, colour 2), written only for non-empty `label`. There is no "Room N" fallback.

- **State and data:** Stateless. The output is plain ASCII/UTF-8 text with CRLF line endings, group codes right-aligned to 3 characters, and every real number formatted with 4 decimals, except that `30/31` are written as the literal `0.0` and `40=0.0`. The file is written to `<getTemporaryDirectory()>/<safe>.dxf` (the Android cache dir) and overwritten each time. An illustrative excerpt, derived by hand-tracing the code for wall 0 of the 4 m × 3 m sample room (calibrated 4000 mm), with values on the line after each group code:

  ```text
    0
  TEXT
    8
  WALLS
   62
  3
   10
  2000.0000
   20
  80.0000
   30
  0.0
   40
  50.0000
    1
  4.00 m
   50
  0.0000
    7
  STANDARD
   72
  1
   73
  2
   11
  2000.0000
   21
  80.0000
   31
  0.0
  ```

  This text is followed by three `LINE`s on WALLS, colour 8: (0, 8)→(0, 100), (4000, 8)→(4000, 100) and (0, 80)→(4000, 80).

- **UI:** None directly; the platform share sheet is shown.

- **Connections:** Called only from `_DxfPreviewScreenState._exportDxf` (`dxf_preview_screen.dart` L72). It reads `SketchShape.points/isClosed/label/wallRealMm/roomObjects/furnitureItems`, `RoomObject.wallIndex/positionAlong/widthMm/swingFlipped/isDoor/isOpening`, and `FurnitureItem.position/rotationDeg/widthMm/depthMm/type.displayName`. It ignores `heightMm`, `elevationMm`, `sharedWalls`, furniture colour and height, and open shapes.

- **Notes and issues:**
  - **Header and units:** `$INSUNITS` and `$MEASUREMENT` are not AC1009 (R12) header variables; they come from later releases. A strict R12 reader ignores them, so the "millimetres" declaration may be lost even though the coordinates are numerically in mm. `$EXTMIN/$EXTMAX` lack Z.
  - **Layer table:** the `LAYER` table count (`70=6`) does not match the 7 entries written.
  - **Explicit colours everywhere:** every entity has an explicit ACI colour (`62`) instead of BYLAYER (256), so changing layer colours in CAD does not recolour anything. Text and dimension lines on WALLS use 3/2/8 rather than the layer's 5.
  - **Walls are bare centrelines:** they are zero-width polylines with no wall thickness and **no gaps** at doors, windows or openings. Symbols are drawn over a continuous wall line, and an opening is only two ticks across an unbroken wall.
  - **Dimensions are not real `DIMENSION` entities:** they are not associative, have no arrows or ticks, and the text is centred on the line (strike-through).
  - **Overlapping annotations:**
    - window dimension line 5 mm from the outer window line;
    - door, window and opening width texts (offset 30–70 mm) overlap the wall length text (55–105 mm) when the object is centred on its wall (`positionAlong` defaults to 0.5).
  - **Shared walls are duplicated:** adjacent rooms produce overlapping polylines and two dimension texts, each drawn on its room's "outward" side, i.e. inside the neighbouring room. `sharedWalls` is not used.
  - **No text sanitisation:**
    - output is UTF-8 with no `$DWGCODEPAGE`, so non-ASCII labels are garbled in R12/ANSI readers;
    - `%%` control codes in labels are interpreted by CAD (e.g. `%%d` becomes a degree symbol);
    - a newline in a label would corrupt the group-code stream. Room-name `TextField`s are normally single-line, so this is unlikely.
  - **Silent omissions:** only closed rooms with at least 3 points are exported; open shapes **and their furniture** are dropped without notice, and unnamed rooms get no label.
  - **Duplicated constant:** `_mm = 5.0` duplicates `mmPerUnit`; if one changes, the other silently disagrees.
  - **Number format differs from the PDF:** `_fmtMm` uses 2 decimals, the PDF 3.
  - **Imprecise extents:** only furniture centres are included in the bounds, not their extents or the annotations. The 15% + 300 mm padding usually covers this.
  - **Sharing details:**
    - the MIME type `application/dxf` is non-standard (`image/vnd.dxf` is the registered type), so some target apps may not offer to open it;
    - there is no `sharePositionOrigin`, which `share_plus` needs on iPad. The app targets Android, so this is minor.
  - **Unused parameter:** `n` in `_writeWalls`.

#### `code/lib/screens/dxf_preview_screen.dart` — 919 lines

- **Purpose:** A full-screen, dark "CAD blueprint" preview of all closed rooms with file metadata and a wall table, plus the button that runs `DxfExporter.export`. It substitutes a 4 m × 3 m sample room when no closed room exists.

- **Depends on:**
  - `dart:math` as `math`; `package:flutter/material.dart`.
  - `../sketch/sketch_model.dart` (`SketchShape`).
  - `../sketch/sketch_constants.dart` (`mmPerUnit`, `formatLength`).
  - `../sketch/room_object.dart` (`RoomObject`); `../sketch/furniture_item.dart` (`FurnitureItem`, `displayName`).
  - `dxf_exporter.dart` (`DxfExporter`).

- **Declarations:**
  - **`class DxfPreviewScreen extends StatefulWidget` (L18).** Fields: `final List<SketchShape> shapes` (all editor shapes) and `final String projectName`. Constructor `const DxfPreviewScreen({super.key, required this.shapes, this.projectName = 'SmartMeasure_Room'})`. `createState()` returns `_DxfPreviewScreenState` (L29).
  - **`class _DxfPreviewScreenState` (L32):**

    | Member | Line | Behaviour |
    |---|---|---|
    | `bool _isExporting` | L33 | Button and spinner state. |
    | `static const List<Offset> _mockPoints` | L36 | `[(0,0), (800,0), (800,600), (0,600)]` world units (4 × 3 m). |
    | `static const Map<int,double> _mockWallMm` | L39 | `{0: 4000, 1: 3000, 2: 4000, 3: 3000}`. |
    | `List<SketchShape> get _closedShapes` | L41 | `widget.shapes` filtered to `isClosed && points.length >= 3` (a new list on every call). |
    | `bool get _hasRealRoom` | L44 | `_closedShapes.isNotEmpty`. |
    | `List<SketchShape> get _previewShapes` | L46 | The closed shapes, or a new mock `SketchShape` (copied points and map, `isClosed: true`, fresh `generateShapeId()`) on every access. |
    | `_totalWalls`, `_totalDoors`, `_totalWindows`, `_totalOpenings`, `_totalFurniture` | L58–67 | Folds over `_previewShapes`: `wallCount`; `isDoor`, `isWindow` and `isOpening` counts; `furnitureItems.length`. |
    | `Future<void> _exportDxf()` | L69 | See 7.2.4. |
    | `Widget build(BuildContext)` | L91 | See UI. |

  - **`class _BlueprintPainter extends CustomPainter` (L273).** Field `final List<SketchShape> shapes`; constructor `const _BlueprintPainter({required this.shapes})`.
    - `void paint(Canvas, Size)` (L279):
      1. Background `0xFF040A12`, then a 36-px grid (`0xFF091820`, 0.6 px).
      2. `allPts` = all points plus all furniture positions. If empty, it calls `_drawPlaceholder` and returns.
      3. Bounding box; `margin = width·0.13`; `drawW/H = size − 2·margin`; `worldW/H` clamped to at least 1; `sc = min(drawW/worldW, drawH/worldH)·0.78`.
      4. `toC(p) = (margin + (drawW − worldW·sc)/2 + (p.dx−minX)·sc, margin + (drawH − worldH·sc)/2 + (p.dy−minY)·sc)`. This centres the plan with **no Y flip**, because canvas Y-down matches world Y-down.
      5. Pass 1: fill closed rooms (≥ 3 points) with `0xFF061020`.
      6. Pass 2: `_drawShapeContent` for each non-empty shape.
      7. Watermark text `'SMARTMEASURE  ·  DXF AC1009'` (`0xFF0A1E2A`, 10 px bold, letterSpacing 2), centred 18 px above the bottom.
    - `void _drawShapeContent(Canvas, SketchShape, Offset Function(Offset) toC, double sc)` (L357). If `n >= 2`, `wallCount = closed ? n : n−1`. It computes the canvas centroid `centC` and the world centroid `worldCent` (both vertex averages), then draws in this order:
      1. Gap covers (`_drawGapCover`) for closed shapes.
      2. Walls: `0xFF00CCFF`, 1.8 px, round caps.
      3. Corner dots `0xFF00FF99` (radius 4.0 for vertex 0, else 2.8).
      4. For closed shapes: `_drawObject` per object with `wallIndex < n`, then `_drawFurnitureItem` per item.
      5. For each wall at least 24 px long on screen: outward canvas normal; ticks from `+5` to `+21` px at both ends and a dimension line at `+20` px (all `0xFF005577`, 0.8 px).
      6. Label `_fmtMm(wallRealMm[i] ?? drawn·mmPerUnit)` at `mid + n·23` (9 px bold; `0xFF00FF88` if calibrated, else `0xFFCCEE88`).
      7. Wall index `'W${i+1}'` (`0xFF336688`, 8 px) at vertex `a + (5, −13)`.
    - `void _drawGapCover(Canvas, List<Offset> pts, int n, RoomObject obj, Offset Function(Offset) toC)` (L478): a 14-px butt-capped line in background colour `0xFF040A12` along the opening span.
    - `void _drawObject(Canvas, List<Offset> pts, int n, RoomObject obj, Offset worldCent, Offset Function(Offset) toC, double sc)` (L499): the same opening/inward-normal maths as the exporters (including `swingFlipped`). It calls `_drawDoorPreview(startC, endC, inW, widthMm/mmPerUnit·sc)` for doors, `_drawWindowPreview` for windows, and draws nothing for openings.
    - `void _drawDoorPreview(Canvas, Offset startC, Offset endC, Offset inWorld, double radiusPx)` (L532):
      - Leaf `startC → startC + inWorld·radiusPx` and frame `startC → endC` (`0xFFFF6644`, 1.5 px).
      - Arc via `canvas.drawArc(Rect.fromCircle(startC, radiusPx), wallAngle + sweep, −sweep, false, …)` (1.0 px), with `sweep = cross(wall, leaf) > 0 ? π/2 : −π/2`. It runs from the leaf direction back to the wall direction.
    - `void _drawWindowPreview(Canvas, Offset startC, Offset endC, Offset inWorld)` (L561): three lines at `inWorld·t` for `t ∈ {−4, 0, 4}` px (`0xFF44DDEE`; 1.5 px centre, 0.8 px outer). The comment reads "Fixed 4 px spacing — readable at all zoom levels".
    - `void _drawFurnitureItem(Canvas, FurnitureItem, Offset Function(Offset) toC, double sc)` (L576):
      - Rotated rectangle with `u = (cos, sin)` and `v = (−sin, cos)` in world space.
      - Fill `0xFF001A08`, stroke `0xFF44CC77` 1.2 px, diagonals `0xFF226644` 0.7 px.
      - `displayName` label (7.5 px bold `0xFF44CC77`), laid out with `maxWidth = clamp(width_px, 28, 110)` and centred, not rotated.
    - `void _drawPlaceholder(Canvas, Size)` (L625): "No room drawn yet" (`0xFF1A3A4A`, 14 px), centred.
    - `static String _fmtMm(double mm)` (L636): same as the DXF `_fmtMm`.
    - `bool shouldRepaint(_BlueprintPainter old) => old.shapes != shapes` (L642). This is reference inequality and always true, because `_previewShapes` returns a new list each build.
  - **`class _FileInfoCard extends StatelessWidget` (L647).** Fields `bool isMock`, `String projectName`, `int roomCount`, `wallCount`, `doorCount`, `windowCount`, `openingCount`, `furnitureCount`, with a `const` constructor taking all fields as required named parameters.
    - `build` (L669) computes `dateStr` (`yyyy-MM-dd`, local) and `safeName`: `'sample_room.dxf'` if mock, else `'${projectName.replaceAll(RegExp(r'[^\w\-]'), '_')}.dxf'`. It renders:
      - a card (`0xFF0A1520`, border `0xFF1A3A4A`) with a header row: `Icons.description_outlined`, the file name (monospace 13 bold cyan, ellipsis), and a `SAMPLE` badge if mock;
      - a divider;
      - rows: Format `'AutoCAD DXF  (AC1009 / R12)'`, Units `'Millimetres  (INSUNITS = 4)'`, Scale `'1 world unit = 5 mm'` (hard-coded), Layers `'WALLS · DOORS · WINDOWS · OPENINGS · FURNITURE'` (omits ROOM_NAMES and 0), Rooms, Walls `'N total'`;
      - Doors, Windows, Openings and Furniture `'N items'`, each only if greater than 0;
      - Date.
    - `Widget _row(String label, String value)` (L745): 78-px label column (`0xFF335566`, 11 px) and value (`0xFFAABBCC`, 11 px).
  - **`class _WallTable extends StatelessWidget` (L774).** Field `final List<SketchShape> shapes`.
    - `build` (L780): `displayShapes` = shapes with at least 2 points; if none, `SizedBox.shrink()`. Otherwise the title "WALL MEASUREMENTS" and a bordered `Table` (column flex 1.1 / 2 / 2.2) with header cells WALL, DRAWN and CALIBRATED (`_TCell(header: true)`, row colour `0xFF0C1A24`), followed by `_buildRows`.
    - `static List<TableRow> _buildRows(List<SketchShape>)` (L828):
      - When there is more than one shape, it adds a separator row per shape: `label` or `'Room ${si+1}'` (cyan 9 px bold) plus two empty cells. `si` is the index among the **closed** preview shapes.
      - Then one row per wall: `_TCell('W${i+1}', accent: true)`, `_TCell(formatLength(drawn))`, and `_TCell(calibrated ? '${mm.toStringAsFixed(0)} mm' : '—', calibrated: hasCal)`.
      - Row background alternates `0xFF070E16`/`0xFF090F18` by `rows.length` parity (separator rows are counted).
  - **`class _TCell extends StatelessWidget` (L885).** Fields `String text`, `bool header`, `bool accent`, `bool calibrated`; constructor `const _TCell(this.text, {this.header = false, this.accent = false, this.calibrated = false})`.
    - `build` (L899): colour precedence default `0xFF7799AA` → header `0xFF335566` → accent `0xFF00BBEE` → calibrated `0xFF00EE88` (later wins).
    - Font size 9 for headers (bold, letterSpacing 1.0), otherwise 11. Monospace unless the cell is a header and not accented.

- **Key logic:**
  - The preview is a **model-based approximation** of the DXF: it uses the same opening, inward-normal and outward-normal maths, but its own sizes in pixels.
  - Scaling fits `0.78 ×` the area inside a 13%-of-width margin, so on a 1.55 aspect ratio the vertical margin is relatively large. The bounding box includes furniture centres, like the DXF exporter but unlike the PDF.
  - Outward normals for the dimensions use the **canvas-space** vertex average; inward normals for the objects use the **world** vertex average. Both are equivalent under the uniform, unflipped transform.

- **State and data:**
  - Only `_isExporting` is mutable.
  - Everything else is derived on each build from `widget.shapes`. `_previewShapes` is recomputed many times per build (one call per getter), and in mock mode each call allocates a new `SketchShape` and increments the global id counter (`generateShapeId`).
  - The screen holds a reference to the editor's live list but never mutates it.

- **UI:**
  - **Scaffold:** background `0xFF050C14`.
  - **AppBar:** background `0xFF0A1520`, foreground `0xFF00CCFF`, elevation 0. Title row: `Icons.architecture` and 'DXF EXPORT' (15 px bold, letterSpacing 2). Action: an amber `SAMPLE` outline badge when `!_hasRealRoom`.
  - **Body:** a `SingleChildScrollView` with a `Column(stretch)` containing:
    1. The canvas container (margin 14,14,14,0; border `0xFF1A3A4A` 1.5 px; radius 3), holding `ClipRRect` → `AspectRatio(1.55)` → `CustomPaint(_BlueprintPainter(shapes: _previewShapes))`.
    2. `_FileInfoCard`, a 10 px gap, `_WallTable`, a 20 px gap.
    3. A `SizedBox(height 50)` with a full-width `ElevatedButton.icon`:
       - colours: background `0xFF003A55`, foreground `0xFF00CCFF`, disabled `0xFF1A2530`/`0xFF335566`; 1-px border (`0xFF005577` while exporting, else `0xFF00CCFF`), radius 3;
       - icon: an 18-px spinner while exporting, else `Icons.file_download_outlined`;
       - label: "GENERATING DXF…", "EXPORT DXF  (N room/rooms)" or "DOWNLOAD SAMPLE DXF";
       - `onPressed: _isExporting ? null : _exportDxf`.
    4. An 8 px gap, then either the sample info box (`0xFF140F00`, `Icons.info_outline`, text quoted in 7.2.5) or the centred caption "DXF opens in AutoCAD, LibreCAD, QCAD and other CAD tools." (`0xFF335566`, 11 px).
    5. A 30 px bottom gap.
  - **Interaction:** there are no gestures on the canvas, no menus and no dialogs. Errors appear as a red SnackBar.

- **Connections:** Pushed only by `sketch_screen.dart` (import L15, route L3878–3888). It calls `DxfExporter.export` and uses `SketchShape.wallCount`, `RoomObject.isDoor/isWindow/isOpening`, `formatLength` and `mmPerUnit`.

- **Notes and issues:**
  - **Bug, openings invisible:** gap covers are painted **before** the walls (L375–391), so the cyan wall line is redrawn over every gap. Openings are therefore invisible, and doors and windows sit on a continuous wall line. The comments at L335, L375 and L528–529 claim the gap erases the wall.
  - **Sample room can be exported as real:** with no closed room, a fake `Sample_Room.dxf` is shared. The info card names it `sample_room.dxf`, and the button says "DOWNLOAD" although it shares, not downloads.
  - **Stale or partial metadata:** the Layers row omits ROOM_NAMES; the Units row advertises `INSUNITS = 4`, which R12 readers ignore (see the exporter notes); the scale string is hard-coded.
  - **Dead code:** `_drawPlaceholder` is unreachable, since `_previewShapes` is never empty.
  - **Wasteful rebuilds:** `shouldRepaint` is always true and `_previewShapes` is recomputed and re-allocated on every getter call.
  - **Inconsistent room numbering:** "Room N" is numbered among closed shapes here, among shapes with at least 2 points in the PDF, and unnamed rooms are unlabelled in the DXF.
  - **Mixed units in the wall table:** DRAWN shows "4.00 m" while CALIBRATED shows "4000 mm".
  - **Third copy of the geometry:** door/window/opening/furniture maths is repeated, with subtle differences, in the PDF exporter, the DXF exporter and this painter.

#### `docs/export_feature_explained.md` — 186 lines

- **Purpose:** A plain-language "how it works" note for the PDF and DXF exports, aimed at students and reviewers. It was added in commit `86429e3` (2026-07-29, "Add DXF/pdf design manual md file") and has not been updated since. The exporter code changed in at least 13 later commits (2026-09-16/17: "change wall thickness in the pdf", "Enlarge the full floor plan", "Display measurements along the walls", "Show area inside a room", "add hole for wall", the multi-room merge).
- **Depends on:** Nothing; it is not referenced by code. `CLAUDE.md` points to the exporter files, not to this doc.
- **Declarations / structure:**
  - The Big Picture (L5): a PDF vs DXF table; both read `SketchShape`, `RoomObject` and `FurnitureItem`.
  - Part 1 — PDF Export (L19): the `pdf` package and `CustomPaint`; the coordinate transformer `_Tx` with its formulas; the page contents; door, window and furniture symbols.
  - Part 2 — DXF Export (L90): the group-code format with a `LINE` example; the layers table; coordinates `X = 5x`, `Y = −5y`; wall dimensions; door, window and furniture entities; delivery through a temp file and `share_plus`.
  - Summary table of key concepts (L171).
- **Key logic stated in the doc that matches the code:** the `_Tx` formulas including the Y flip; 1 pt ≈ 0.35 mm; centroid-based inward direction; furniture rotation by cos/sin with a pastel fill, border and X; DXF scale 5 mm per unit with Y flip; wall dimension 80 mm outside, with extension lines, calibrated length if present else drawn; door = leaf `LINE` + frame `LINE` + `ARC` + dimension; window = 3 `LINE`s at −55/0/+55 mm + 2 jamb `LINE`s + dimension; furniture = 4 `LINE`s + 2 diagonals + `TEXT`; DXF built with a `StringBuffer`; temp file + `share_plus`.
- **Notes and issues — discrepancies with the code:**

  | # | Doc says | Code actually does |
  |---|---|---|
  | 1 | "The app stores room corners as **pixel positions** on the phone screen." | Points are world units (1 unit = 5 mm, `mmPerUnit`), independent of screen zoom. The doc itself uses "1 world unit = 5 mm" in the DXF part. |
  | 2 | `_Tx` scales "to fit inside the canvas box (**296 × 296 pt**)". | `_cs = 296` is legacy. The overview canvas is **504 × 504 pt** (444 pt plan + 30 pt dimension margin each side); room canvases are **304 × 304 pt** (260 + 22·2). |
  | 3 | Overview: "ALL rooms with **coloured fills**". | Overview fills are **white** with **black** walls. Only room pages use a light-blue fill. |
  | 4 | Page lists omit dimensioning. | The overview has 4-side segment and overall dimension chains plus room-name and area labels; room pages have per-wall dimension lines with "x.xx m" labels and an area label. |
  | 5 | Overview room index: "(name, perimeter, area)". | Columns are `#`, Room Name, Perimeter, Area, `Pg`. |
  | 6 | Door is a "**3-line** symbol" (gap, leaf, arc). | PDF also draws a hinge→far-jamb frame line (4 elements). The swing side is reversed when `RoomObject.swingFlipped` is set, which the doc never mentions. |
  | 7 | "the door always swings toward the room centre". | Not when `swingFlipped`. The "centre" is the vertex average, which can be wrong for concave rooms. |
  | 8 | Only doors and windows exist. | A third type, `RoomObjectType.opening`, is handled: PDF white gap + ±4 pt ticks; DXF layer **OPENINGS** (ACI 8) with ±60 mm ticks and a dimension; the preview draws nothing for it (bug). Its table type is "Opening". |
  | 9 | DXF layers table: WALLS, DOORS, WINDOWS, FURNITURE, ROOM_NAMES. | The code also writes layer `0` (ACI 7) and **OPENINGS** (ACI 8). The code's own header comment wrongly calls ACI 8 "yellow". |
  | 10 | DXF example shows walls written as `LINE` on WALLS. | Wall outlines are a closed R12 `POLYLINE` + `VERTEX` + `SEQEND`. `LINE`s on WALLS are only dimension and extension lines. Every entity also carries an explicit `62` colour. |
  | 11 | DXF version and units are unspecified ("DXF uses millimetres"). | The header declares `AC1009` (R12) plus `$INSUNITS=4` and `$MEASUREMENT=1`, which are not R12 variables. |
  | 12 | Wall dimensions: steps 1–5. | Also: walls under 25 mm are skipped; text colour is ACI 3 for calibrated and 2 for drawn; text height 50 mm, centred on the dimension line. |
  | 13 | Window jambs are "**short** LINE entities". | Each jamb is 260 mm long (±130 mm). |
  | 14 | Doc summary: `printing` gives a "PDF preview/print/**share** dialog". | Only `Printing.layoutPdf` (the print dialog) is used. There is no `sharePdf` or `share_plus` call for PDFs; saving happens via the dialog's "Save as PDF". |
  | 15 | Not mentioned. | The DXF is exported only through `DxfPreviewScreen`; only closed rooms with at least 3 points are exported (the PDF includes open shapes); there is a 4 × 3 m sample fallback; the file is named `<sanitised project>.dxf`; DXF text height, colour and offset values. |
  | 16 | Not mentioned. | PDF details absent from the doc: default Helvetica (with the placeholder-glyph bug), the `referenceScale` wall-thickness normalisation, and the A4 single-page layouts. |

### 7.4 Data contracts

**Input contract — model fields read by each output**

| Field | PDF | DXF | Preview |
|---|---|---|---|
| `SketchShape.points` (world units, Y down) | yes | yes | yes |
| `SketchShape.isClosed` | yes (fills, objects, stats) | filter (closed only) | filter (closed only) |
| `SketchShape.label` | page and TOC titles (fallback "Room N") | ROOM_NAMES `TEXT` only if non-empty | table separator (fallback "Room N") |
| `SketchShape.wallRealMm` (`Map<int,double>`, mm) | room-page labels, walls table | wall `TEXT` value and colour | canvas labels, CALIBRATED column |
| `SketchShape.heightMm` | HEIGHT stat | — | — |
| `SketchShape.roomObjects` | symbols + table | entities | symbols + counts |
| `RoomObject.wallIndex/positionAlong/widthMm/swingFlipped/type` | yes | yes | yes |
| `RoomObject.heightMm/elevationMm` | table only | — | — |
| `SketchShape.furnitureItems` | symbols + table | entities | symbols + count |
| `FurnitureItem.position/rotationDeg/widthMm/depthMm` | yes | yes | yes |
| `FurnitureType.displayName` | table | `TEXT` | label |
| `FurnitureType.color` | fill, border and X colour | — | — |
| `SketchShape.sharedWalls`, `id`, `FurnitureType.heightMm` | — | — | — |

**PDF document structure** (A4 portrait 595.28 × 841.89 pt; one `pw.Page` per row; N = number of shapes with at least 2 points; total pages = N + 2)

| Page | Builder | Margin | Content, top to bottom |
|---|---|---|---|
| 1 | `_coverPage` | 0 | Navy header ("FLOOR PLAN GUIDE", project name or "SmartMeasure Project", "Generated yyyy-MM-dd • SmartMeasure Pro") → stats bar (ROOMS = closed count, TOTAL AREA, TOTAL PAGES) → "TABLE OF CONTENTS" (Overview p.2; each shape p.3+i with an "Area: …" sub-line) → spacer → footer "SmartMeasure Pro — Floor Plan Guide" / "Page 1 of N+2" |
| 2 | `_overviewPage` | 32 | Header "Full Floor Plan" + project subtitle + page badge → 504 pt canvas (grid, white fills, black 150 mm walls, furniture, door/window/opening symbols, room name + area labels, 4-side dimension chains) → "Room Index" table (#, Room Name, Perimeter, Area, Pg) → spacer → footer |
| 3…N+2 | `_roomPage` | 32 | Header = room name (blue) + badge → 304 pt canvas (grid, light-blue fill, blue-grey walls at overview thickness, corner dots, furniture, symbols, per-wall dimension lines + "x.xx m" labels, area label) → stats row (WALLS, PERIMETER, AREA, HEIGHT; closed only) → "Doors, Windows & Openings" and "Furniture" tables side by side (if any) → "Wall Measurements" (two column pairs) → spacer → footer |

**PDF canvas geometry**

| Canvas | Box (pt) | Plan area `da` (pt) | Margin (pt) | Scale (pt per world unit) | Wall thickness drawn |
|---|---|---|---|---|---|
| Overview | 504 × 504 (`_csOvDim`) | 444 (`_daOv`) | 30 (`_dimMargin`) | `444 / max(bboxW, bboxH)` over all shapes | `30 units × scale` |
| Room page | 304 × 304 (`_csRoomDim`) | 260 (`_da`) | 22 (`_roomDimMargin`) | `260 / max(bboxW, bboxH)` of that shape | `30 × referenceScale` pt (same as overview) |
| Transform | `x = margin + (wx − minX)·s`; `y = box − margin − (wy − minY)·s` (Y up). Overlays use `top = box − y`. | | | | |

**PDF symbology**

| Element | Geometry | Style |
|---|---|---|
| Grid | every 20 pt | grey200, 0.3 pt |
| Room fill | centreline polygon (closed, ≥ 3 pts) | white (overview) / `PdfColor(0.90,0.95,1.00)` (room page) |
| Wall | `thickWallRect` per wall, no joins | black (overview) / blueGrey800 (room page) |
| Corner dots (room page only) | radius 3 pt | vertex 0 green700, others blue700 |
| Opening gap (all object types) | stroke along opening, width = wall thickness + 1 pt | white |
| Door | leaf (inward, length = width), frame line, 90° arc (25 points) | blueGrey800; leaf/frame 1.5 pt, arc 0.8 pt |
| Window | 3 parallel lines at 0, ±2.66 pt | `PdfColor(0,0.49,0.76)`; 1.5 pt centre, 0.8 pt outer |
| Opening | ±4 pt jamb ticks | blueGrey400, 0.8 pt |
| Furniture | rotated rectangle + X | fill `0.65+0.35c`, border `0.7c` 0.8 pt, X `0.5c` 0.4 pt |
| Dimension lines | 0.5 pt lines, 0.3 pt extension lines, filled 3 pt arrows; offsets 7 pt (segment / room wall) and 16 pt (overall) | `PdfColor(0.3,0.3,0.3)`, text 6.5 pt |
| Room name / area overlays | centred at vertex average | 7 pt bold blueGrey900 / 7 pt blueGrey700 |
| Fonts | default Helvetica / Helvetica-Bold (Type1, not embedded, Latin-1 only) | — |

**DXF file format**

| Aspect | Specification |
|---|---|
| Flavour | AutoCAD R12, `$ACADVER = AC1009`, ASCII |
| Encoding / line ends | Dart `writeAsString` default UTF-8; CRLF after every code and value |
| Group code line | `code.toString().padLeft(3)` (e.g. `"  0"`, `" 10"`) |
| Reals | `toStringAsFixed(4)`; Z (`30/31`) is the literal `0.0` |
| Units | millimetres. `$INSUNITS=4` and `$MEASUREMENT=1` are declared, but they are not R12 variables |
| Coordinates | `X = 5·x_world`, `Y = −5·y_world`, `Z = 0`; angles in degrees, counter-clockwise from +X |
| Sections | `HEADER` → `TABLES` (LTYPE, LAYER, STYLE) → `ENTITIES` → `EOF`. No BLOCKS, no handles |
| Header variables | `$ACADVER`, `$INSUNITS`, `$MEASUREMENT`, `$EXTMIN`, `$EXTMAX`, `$LIMMIN`, `$LIMMAX` (extents = vertex + furniture-centre bounds padded by 15% + 300 mm; 10/20 only) |
| File | `<getTemporaryDirectory()>/<projectName with [^\w-] → _>.dxf`, overwritten per export |
| Delivery | `Share.shareXFiles([XFile(path, mimeType: 'application/dxf')], subject: '<projectName> — Floor Plan')` |

**DXF layers** (LAYER table header says `70=6`; 7 records; all `70=0`, linetype `CONTINUOUS`)

| Layer | ACI (62) | Colour | Contents |
|---|---|---|---|
| `0` | 7 | white/black | nothing written |
| `WALLS` | 5 | blue | room outline `POLYLINE`s (entity colour 5); wall-length `TEXT` (entity colour 3 calibrated / 2 drawn); extension and dimension `LINE`s (entity colour 8) |
| `DOORS` | 1 | red | leaf and frame `LINE`, swing `ARC`, dimension `LINE`s, width `TEXT` (all colour 1) |
| `WINDOWS` | 4 | cyan | 3 parallel `LINE`s, 2 jamb `LINE`s, dimension `LINE`s, width `TEXT` (all colour 4) |
| `OPENINGS` | 8 | dark grey | 2 jamb ticks, dimension `LINE`s, width `TEXT` (all colour 8) |
| `FURNITURE` | 3 | green | 4 outline `LINE`s (3), 2 diagonals (**8**), name `TEXT` (3) |
| `ROOM_NAMES` | 2 | yellow | room label `TEXT` (2), non-empty labels only |

**DXF entity mapping** (all sizes in mm; "outward" = away from the vertex-average centroid; "inward" = toward it, reversed by `swingFlipped`)

| Model element | Entities | Geometry |
|---|---|---|
| Closed room outline | `POLYLINE` (`66=1`, `70=1` closed, `10/20/30 = 0,0,0`) + one `VERTEX` per point + `SEQEND` | Wall centreline, zero width, no gaps |
| Wall *i* length (skipped if < 25 mm) | `TEXT` + 3 `LINE` | Text at midpoint + 80 outward, height 50, rotation = wall angle kept upright, centred (`72=1`, `73=2`, `11/21` = insertion point). Extension lines 8→100 outward at both vertices; dimension line at 80 |
| Door | `LINE` leaf, `LINE` frame, `ARC`, 3 `LINE` dimension, `TEXT` width | Hinge = opening start `(positionAlong·L − w/2)`; leaf to hinge + inward·w; `ARC` centre hinge, radius w, 90° between wall and inward directions; dimension on the side opposite the swing: extension lines 5→65, line at 50, text at 50 (height 40) |
| Window | 5 `LINE` symbol + 3 `LINE` dimension + `TEXT` | Parallels at inward offsets −55/0/+55 between the opening ends; jambs ±130 at each end; dimension as for doors |
| Opening | 2 `LINE` ticks + 3 `LINE` dimension + `TEXT` | Ticks ±60 at each end; dimension as for doors |
| Furniture item | 4 `LINE` outline + 2 `LINE` diagonals + `TEXT` | Rectangle `widthMm × depthMm` about `(5x, −5y)`, rotated by `rotationDeg` (mirror-consistent); text = `displayName`, height 40, rotation 0, centred |
| Room label | `TEXT` | Vertex average, height 80, rotation 0, centred |
| Not exported | — | Wall thickness and gaps, room height, object heights and elevations, areas and perimeters, title block / project name inside the drawing, open shapes and their furniture, `sharedWalls` |

**Preview canvas contract** (Flutter pixels, no Y flip): `sc = 0.78·min(drawW/worldW, drawH/worldH)` with margin = 13% of the width, centred. Walls are 1.8 px centrelines; dimension offset 20 px; window spacing 4 px; door radius = width·sc; gap covers 14 px (ineffective, see 7.3).

### 7.5 Known issues and limitations

**Visible bugs**
- **PDF glyph placeholders:** `—` (U+2014) and `•` (U+2022) are outside the default Helvetica's Latin-1 range. They print as crossed placeholder boxes in every page footer, the cover subtitle and empty table cells. Non-Latin-1 room names are affected the same way. No font is embedded and no `fontFallback` is set.
- **DXF preview hides openings:** gap covers are painted before the walls, so they never erase anything (`dxf_preview_screen.dart` L375–391). Openings are invisible and doors/windows sit on a continuous wall line, contrary to the code comments.
- **PDF dimensions inside thick walls (derived from the formulas):** dimension lines and labels are offset a fixed 7/16 pt from the wall **centreline**, while wall half-thickness scales with the plan. In small plans they fall inside the wall band; one 4 × 3 m room gives a half-thickness of 8.3 pt, and the overview walls are black.
- **DXF annotation overlaps:** all dimension texts are centred on their dimension lines (strike-through). The window dimension line is 5 mm from the outer window line. Door, window and opening width texts collide with the wall-length text when the object is centred on its wall.
- **Concave rooms (PDF, DXF, preview):** the vertex-average centroid can put a door swing on the wrong side or a dimension inside the room.

**Format and compatibility**
- **DXF header and layers:**
  - `AC1009` header contains `$INSUNITS` and `$MEASUREMENT`, which are not R12 variables, so R12 readers may not pick up the mm unit;
  - `$EXTMIN/$EXTMAX` lack Z;
  - the LAYER table count is 6 for 7 records;
  - there is no BLOCKS section and no handles (legal for R12, but minimal).
- **DXF entity choices:**
  - every entity has an explicit ACI colour instead of BYLAYER;
  - dimensions are `LINE` + `TEXT`, not associative `DIMENSION` entities;
  - walls are zero-width polylines without opening gaps.
- **DXF text handling:** no `$DWGCODEPAGE` and no text escaping. UTF-8 labels are garbled in ANSI readers, and `%%` codes are interpreted by CAD.
- **PDF delivery:** the PDF goes only to the print dialog (`Printing.layoutPdf`); there is no in-app save or share. The page format chosen in the dialog is ignored (always A4). The DXF goes only to the share sheet, with a non-standard MIME type (`application/dxf`) and no iPad `sharePositionOrigin`.

**Data fidelity and inconsistencies**
- **Calibrated vs drawn values:**
  - PDF overview dimensions, all PDF perimeters and areas, and the cover TOTAL AREA use drawn geometry, not `wallRealMm`. Areas are gross (centreline) areas.
  - Room-page labels, the PDF walls table, DXF wall texts and the preview use calibrated values when present.
- **Number formats differ across outputs:**
  - PDF `_fmtMm` uses 3 decimals, DXF and preview `_fmtMm` 2, `formatLength` 2;
  - vertical overview dimensions are always in m;
  - the preview table shows DRAWN in m and CALIBRATED in mm.
- **Scope of exported shapes:**
  - the PDF includes open shapes (at least 2 points) as "rooms", but the cover's ROOMS stat counts only closed ones;
  - the DXF and preview silently drop open shapes **and their furniture**;
  - unnamed rooms are "Room N" in the PDF and preview (numbered differently), but unlabelled in the DXF.
- **Wall thickness:** 150 mm in the PDF (`wallThickness = 30` units), 200 mm in the 3D view (`wallThicknessM: 0.2`), and 0 in the DXF and preview. The comment `// world units (~50mm real)` in `sketch_constants.dart` L34 is wrong.
- **Shared walls:** `sharedWalls` is ignored by all exporters. In the DXF, adjacent rooms produce duplicate overlapping walls and two dimension texts per shared wall.
- **No common scale:** PDF room pages use per-room scales, with no scale ratio, scale bar or north arrow. Furniture and doors/windows are not labelled or numbered on the PDF plan, so table rows cannot be matched to symbols.
- **Bounding boxes:** the PDF ignores furniture, and `pw.Stack` clips, so furniture outside the walls is cut off. The DXF and preview include furniture centres only.

**Robustness, UX and maintainability**
- **No PDF pagination:** each page is a single `pw.Page`. Long tables of contents (about 15+ rooms), room indexes (about a dozen rooms) or object/furniture/wall tables (about 20+ rows) run off the page.
- **PDF button and call:** the button's enable test checks only the active room. `exportSketchPdf` is not awaited and has no error handling. Its "Draw a room first" SnackBar is unreachable from the current UI.
- **Sample-room export:** the DXF screen can export a synthetic 4 × 3 m sample room as `Sample_Room.dxf`. It is advertised as `sample_room.dxf`, and the button says "DOWNLOAD" although it shares.
- **Duplicated code:** door, window, opening, furniture and normal geometry is implemented three times (PDF, DXF, preview) with diverging details. The 5 mm/unit factor is duplicated as `DxfExporter._mm`, and "1 world unit = 5 mm" is hard-coded in the preview UI.
- **Dead or misleading code:**
  - `_txFor`'s `canvasSize` branch, and with it `_cs` and `_csOv`, are legacy;
  - `_paintWindow(widthPdf)` and `_writeWalls(n)` are unused parameters;
  - `_dimLabel` contains a redundant ternary;
  - `_drawPlaceholder` is unreachable;
  - the comment at `sketch_pdf_export.dart` L422 contradicts the draw order;
  - the header comment in `dxf_exporter.dart` calls OPENINGS "yellow-8" and omits ROOM_NAMES.
- **Preview inefficiency:** `shouldRepaint` is always true, and `_previewShapes` is reallocated on every getter call; in sample mode each call creates a new `SketchShape` id.
- **Outdated documentation:** `docs/export_feature_explained.md` (2026-07-29) predates the September exporter changes. See the 16 discrepancies in 7.3: canvas size, fill colours, openings, layers, POLYLINE walls, dimensions, R12 header, print vs share.


---

## Part 8 — 3D room view (Flutter WebView + Three.js)

### 8.1 Overview

The 3D room view turns the 2D floor plan into an interactive 3D model. The plan is every `SketchShape` room of the current project, with its doors, windows, openings and furniture. The model is textured and shadowed, and the user orbits it with touch. The user can also select a wall in 3D and measure it with the BLE laser device, or change the room height. Everything lives in one Flutter screen, `Room3DScreen` (`code/lib/sketch/room_3d_screen.dart`). That screen hosts two interchangeable renderers:

1. **WebView mode** (default, `_use3D == true`). A `webview_flutter` WebView runs a Three.js **r148** scene defined in `code/assets/3d/three_room.html`.
   - Dart serialises the plan to JSON: metres, floor in the X/Z plane, Y up. The JSON also carries base64-encoded GLB/glTF furniture models. Dart pushes it into the page with `runJavaScript`.
   - The page reports taps and screenshots back through the single JavaScript channel `FlutterBridge`.
2. **Painter mode** (legacy, `_use3D == false`). This is the original "Phase 3D-1" pure-Dart pseudo-3D renderer `_Room3DPainter`.
   - It is a `CustomPainter` that does its own rotation, perspective projection and painter's-algorithm depth sort.
   - It draws only the active room.
   - It is reached only through a manual AppBar toggle. Nothing switches to it automatically when WebGL fails.

**Vocabulary**
- **World units.** The 2D sketch coordinates of `SketchShape.points` and `FurnitureItem.position`. 1 unit = `mmPerUnit` = 5 mm (`sketch_constants.dart`), so 200 units = 1 m. x points right and y points down (screen convention).
- **House.** All rooms sent in one JSON payload `{rooms, furnitureModels}`. In JS, `houseGroup` (a `THREE.Group`) holds one **room group** per room.
- **Room objects.** `RoomObject`s of type door, window or opening. Each is anchored to a wall by `wallIndex` plus `positionAlong` (0 to 1 along the wall).
- **Opening.** A `RoomObjectType.opening`, i.e. a plain hole. In 3D it is the only object type that is actually cut out of the wall mesh.
- **Wall index.** Wall *i* is the edge `points[i] → points[(i+1) % n]`. The same index is used in Dart, in JS `userData.wallIndex` and in `SketchShape.wallRealMm`.
- **Global centroid `(gcx, gcz)`.** The vertex average (in metres) of every point of every room. JS subtracts it from all coordinates so the house is centred on the scene origin.
- **Phases.** Code comments refer to the 3D development track:
  - 3D-1: the painter.
  - 3D-2: WebView + Three.js.
  - 3D-3: procedural furniture and better doors/windows.
  - 3D-4: PBR materials, canvas textures and contact shadows.
  - 3D-5: screenshot sharing — announced but not implemented.

```text
SketchScreen "3D View" button (sketch_screen.dart L3400–3439)
  │ Navigator.push(MaterialPageRoute(Room3DScreen(shapes: <all shapes>,
  │   initialActiveShapeIndex: activeIndex, bleManager, onWallMeasured, onHeightChanged)))
  ▼
_Room3DScreenState (room_3d_screen.dart)
  initState → _initWebView → _loadInlinedHtml
     rootBundle.loadString: assets/3d/three_room.html (template with <!--THREE_JS-->)
                            assets/3d/three.min.js   (Three.js r148 UMD → window.THREE)
                            assets/3d/gltf_loader.js (non-module THREE.GLTFLoader)
     template.replaceFirst('<!--THREE_JS-->','<script>…three…</script><script>…loader…</script>')
     WebViewController.loadHtmlString(html)
  onPageFinished (or JS {type:'ready'}) → _sendRoomData → _sendRoomDataAsync
     _buildHouseJson()       world units → metres, plan x→X, plan y→Z
     _loadFurnitureModels()  assets/models/*.glb|.gltf → base64 map by type name
     runJavaScript: window._roomDataChunks=[] ; push(chunk)×N ; window.initHouse(join)
  ▼
three_room.html (Three.js inside the WebView)
  initHouse → buildHouse → buildRoomGroup × rooms
     floor (ShapeGeometry + wood canvas texture) · ceiling (BackSide) ·
     walls (BoxGeometry, or ExtrudeGeometry with holes for openings) ·
     doors/windows (_buildDoor/_buildWindow) · furniture (GLTFLoader, else
     createFurnitureGroup → buildX) · one PointLight per room
  custom THREE.OrbitControls (1-finger orbit, pinch zoom toward pinch point)
  tap → Raycaster → FlutterBridge.postMessage({wallTap|roomTap|furnitureTap})
  ▲ runJavaScript: highlightWall / highlightRoom / resetCamera / captureScreenshot
  │                (captureScreenshot → {type:'screenshot', data:<PNG data URL>})
Room3DScreen ── BLE: bleManager.packetStream → wallRealMm[i] + onWallMeasured
             └─ Painter mode: _Room3DPainter (CustomPainter, active room only)

code/temp.js — stale, unreferenced copy of an intermediate version of the
               <script> body of three_room.html (not bundled, never loaded)
```

### 8.2 Features and how they work

#### Opening the 3D view
- **Trigger.** In `SketchScreen` (outside this part) a purple `ElevatedButton.icon` labelled "3D View" (colour `0xFF7B2FBE`, `Icons.view_in_ar`) is shown when:
  - the active shape `isClosed`,
  - it has at least 3 points,
  - no furniture is selected or being placed.
- **What the button passes.** It pushes `Room3DScreen(...)` with:
  - `shapes: shapes` — the live list of **all** shapes, including unclosed or empty ones,
  - `initialActiveShapeIndex: activeIndex`,
  - `bleManager: widget.bleManager`,
  - `onWallMeasured: (wallIndex, mm) => _applyRealMeasurement(wallIndex, mm)`,
  - `onHeightChanged: (mm) { setState(() => activeShape.heightMm = mm); _saveUndo(); }`.
- **`initState` (L65).**
  - Sets `_activeShapeIndex = widget.initialActiveShapeIndex`.
  - Sets `_wallHeightMm = _activeShape.heightMm`.
  - Calls `_initWebView()`.
- **What the user sees.** The AppBar reads "3D Room (WebView)". Under it the page shows its own overlay "Initializing 3D view… / Loading scene" on a `#0D1117` background until the first `buildHouse` finishes.

#### Bootstrapping the page (inlined Three.js)
1. `_initWebView` (L72) builds a `WebViewController` with:
   - `setJavaScriptMode(JavaScriptMode.unrestricted)`,
   - `addJavaScriptChannel('FlutterBridge', onMessageReceived: _onJsMessage)`,
   - `setNavigationDelegate(NavigationDelegate(onPageFinished: (_) { _webLoaded = true; _sendRoomData(); }))`.

   No background colour is set (`setBackgroundColor` is never called), and there is no `onWebResourceError` handler. It then calls `_loadInlinedHtml()` without awaiting it, so asset errors are unhandled.
2. `_loadInlinedHtml` (L89) does the following:
   - Reads `assets/3d/three.min.js`, `assets/3d/gltf_loader.js` and `assets/3d/three_room.html` with `rootBundle.loadString`.
   - Replaces the first `<!--THREE_JS-->` comment (HTML L32) with `<script>{three.min.js}</script><script>{gltf_loader.js}</script>`.
   - Calls `loadHtmlString(html)` with no `baseUrl`. The result is about 0.78 MB of HTML.

   The code comment says this inlining avoids `file://` requests that the Android WebView blocks via CORS. Neither JS file contains a `</script` sequence, so inlining is safe.
3. The inline `<script>` of the HTML then runs top to bottom:
   - error handler, custom `THREE.OrbitControls` and a queueing `initHouse` stub;
   - renderer, scene, camera, controls, lights and `houseGroup`;
   - helper and builder functions and the `window.*` API;
   - tap listeners and the resize listener;
   - the `animate` loop, which starts rendering an empty scene;
   - pending-data processing;
   - finally `FlutterBridge.postMessage('{"type":"ready"}')` (L1647–1649).

#### Sending the plan to the scene (serialisation and chunked transfer)
- **Triggers:**
  - `onPageFinished`,
  - the JS `ready` message (`_onJsMessage` → `_sendRoomData`),
  - **APPLY** in the height dialog,
  - `didUpdateWidget` when `shapes.length` changed (in practice never; see the file reference).
- `_sendRoomData` (L211) returns unless `_webLoaded`, then calls `_sendRoomDataAsync` (L216):
  1. `_buildHouseJson()` (L162):
     - `toM = mmPerUnit / 1000 = 0.005` m per world unit.
     - Each room becomes `{id, label, points:[{x: p.dx*toM, z: p.dy*toM}], wallHeightM: heightMm/1000, wallThicknessM: 0.2 (hard-coded), roomObjects:[…], furnitureItems:[…]}`.
     - Room objects become `{wallIndex, positionAlong, widthM, heightM, elevationM, isDoor, isOpening, kind: 'door'|'opening'|'window'}`.
     - Furniture becomes `{type: item.type.name, x, z (m), rotationDeg, widthM, depthM, heightM: item.type.heightMm/1000, colorHex}`. `colorHex` is `'#' + argb.toRadixString(16).padLeft(8,'0').substring(2)`, i.e. lower-case `#rrggbb` with alpha dropped.
  2. `_loadFurnitureModels(all furniture of all rooms)` (L101):
     - Takes the set of distinct `type.name`s and maps each through `_modelPathForType` (L126).
     - Calls `rootBundle.load(path)` and then `base64Encode`.
     - Missing files are caught (`debugPrint('Model not found …')`) and skipped.
     - The result is stored as `data['furnitureModels'] = {typeName: base64}` at top level.
  3. `jsonEncode(data)`, then the string is split into 250 000-character slices. Dart then calls:
     - `runJavaScript('window._roomDataChunks = [];')`,
     - one `runJavaScript('window._roomDataChunks.push(<jsonEncode(slice)>);')` per slice, each awaited in order,
     - `runJavaScript('window.initHouse(window._roomDataChunks.join(""));')`.

     The comment says chunking prevents `TransactionTooLargeException` "when sending multiple base64 GLB models".
  4. Any exception is caught: `debugPrint` plus a SnackBar "Failed to load 3D view: $e".
- **JS side.** `window.initHouse(data)` (L1504) does `JSON.parse` when given a string, then `buildHouse(data)`. Exceptions are shown in the `#error` overlay as "initHouse error: <message>".
- **Payload size.** It is dominated by the base64 models (×4/3 of file size). For example, `Sofa.glb` is 9.98 MB, about 13.3 MB in base64; `toilet.glb` is 28.2 MB, about 37.6 MB, roughly 150 chunks on its own. Every (re)send reloads and re-encodes everything; nothing is cached.

#### Building the scene (`buildHouse`, `buildRoomGroup`)
`buildHouse(data)` (L1465):
1. `lastData = data`. The whole payload, including base64 models, is retained for `resetCamera`.
2. `disposeGroup(houseGroup)`.
3. `rooms = data.rooms || []`. If `rooms` is empty it returns, and the loading overlay stays visible.
4. `furnitureModels = data.furnitureModels || {}`.
5. Global centroid `gcx, gcz` = mean of all room points.
6. For each room, `houseGroup.add(buildRoomGroup(room, gcx, gcz, furnitureModels))` and track `maxH = max(wallHeightM || 2.4)`.
7. Camera fit: `maxR` = the largest distance of any point from the centroid; `camD = maxR*1.8 + 2`; `controls.target = (0, maxH/2, 0)`; `controls.setPosition(camD, 0.75*camD, camD)`. For a 4 × 3 m room this gives `maxR = 2.5`, `camD = 6.5`, and the camera looks down from the south-east diagonal.
8. Hides `#loading`.

`buildRoomGroup(data, gcx, gcz, furnitureModels)` (L1253):
- Creates a group with `userData.roomId = data.id`.
- `H = wallHeightM || 2.4`, `T = wallThicknessM || 0.2`.
- If there are fewer than 3 points it returns the empty group. Local coordinates are `lx(p) = p.x − gcx`, `lz(p) = p.z − gcz`.
- It then builds, in this order: floor, ceiling, walls, doors/windows, furniture, and a ceiling `PointLight(0xFFF0CC, 0.4, H*5)` at `(0, 0.95H, 0)`.

  Room groups are never translated; their vertices are already centroid-relative. So **every room's point light sits at the global centroid**, not at its own room's centre.

#### Floor, ceiling and walls (with real holes for openings)
- **Floor.**
  - `buildFloorShape(pts, lx, lz)` (L1003) computes twice the signed area `Σ lx_i·lz_{i+1} − lx_{i+1}·lz_i` and reverses the points if it is > 0. It then builds a `THREE.Shape` from `(lx, −lz)`.
  - `ShapeGeometry(shape).rotateX(−π/2)` maps shape `(x, y)` to world `(x, 0, −y)`, so world Z = +lz, matching the walls. The comment explains this as the fix for mirrored L-shaped floors.
  - The manual reversal is redundant: r148's `ShapeGeometry` normalises the outer contour itself with `ShapeUtils.isClockWise` (checked in `three.min.js`).
  - Material: `MeshStandardMaterial({map: woodClone, roughness 0.55, metalness 0})`, `receiveShadow`, `position.y = 0.001`.
  - Repeat:
    - `woodClone = _woodTex.clone()`.
    - `rptX = max(2, round(floorW / 0.72))`, where 0.72 m = 6 planks × 0.12 m.
    - `rptZ = max(1, round(floorD / 1.5))`.
    - The bounding box is in metres.
  - The formula assumes UVs normalised to the floor's bounding box. In r148, however, `ShapeGeometry` writes world-space UVs (`uv = shape (x, y)` in metres), so the texture repeats `rptX` times **per metre**. For a 4 m-wide room the planks are about 1/(6·6) m ≈ 2.8 cm wide instead of 12 cm, and they get narrower as rooms get wider.
- **Ceiling.**
  - Built from the same shape.
  - Material: `MeshStandardMaterial({color 0xDDDAD4, roughness 0.95, side: THREE.BackSide})` at `y = H`.
  - Its front face points up, so it is invisible (and not raycast-hit) from above but visible from inside. The camera can always look into rooms from above. There is no ceiling toggle in WebView mode.
- **Walls**, for each edge *i*:
  - Length `len` from the local endpoints; edges with `len < 0.01` are skipped and the index is preserved.
  - Plaster texture: `wt = _plasterTex.clone()` with `repeat = (max(1, round(len)), max(1, round(H)))`, about one tile per metre on the 0–1 UVs of `BoxGeometry`.
  - Openings on this wall (`roomObjects` with `wallIndex === i && isOpening`) are mapped to `{centerX: positionAlong*len − len/2, halfW: widthM/2, bottomY: elevationM, topY: elevationM + heightM}`.
  - Geometry: `buildWallGeometry(len, H, T, openings)` (L1221) if there are any openings, otherwise `BoxGeometry(len + T, H, T)`.
  - Material: `MeshStandardMaterial({map: wt, color 0xFFFFFF, roughness 0.9, metalness 0})`, `castShadow` and `receiveShadow`.
  - Placement: position `((ax+bx)/2, H/2, (az+bz)/2)`, `rotation.y = −atan2(dz, dx)` (local +X runs along the edge), `userData = {wallIndex: i, roomId}`.
  - Walls are **centred** on the polygon edge (half the thickness on each side) and extended by T/2 past each vertex. At right-angle corners the two boxes overlap and their outer faces coincide over a T/2 square, which can z-fight. At other angles the outer corners show small notches or spurs.
- **`buildWallGeometry`.**
  - A rectangle `±(len+T)/2 × ±H/2`.
  - Each opening becomes a rectangular `THREE.Path` hole, clamped 1 cm inside the slab edges. Degenerate holes are skipped. A floor-level opening therefore keeps a 1 cm lip of wall at the bottom.
  - The result goes through `ExtrudeGeometry(shape, {depth: T, bevelEnabled: false, curveSegments: 1})` and `translate(0, 0, −T/2)`.
  - `ExtrudeGeometry` also generates world-space (metre) UVs. Walls with openings therefore show the plaster texture `round(len) × round(H)` times denser than box walls.

#### Doors and windows
- **Placement.** For each room object:
  - Wall endpoints `a`, `b`; unit vector `u`.
  - Centre `a + u·positionAlong·len`.
  - Group `og` at floor level (`y = 0`), `rotation.y = −atan2(dz, dx)`, `userData.roomId`.
  - Local space: x along the wall, y up, z through the wall.
- **Dispatch.** Doors use `_buildDoor(og, widthM, heightM, elevationM, T)` (L875). Windows (`!isOpening`) use `_buildWindow` (L938). For openings `og` stays empty, because the hole is already in the wall mesh.
- **Wall index is not validated.** The Dart side does not check it. An object whose `wallIndex ≥ n` makes `pts[wi]` undefined and throws. That aborts `buildHouse`, so that room and all later rooms are missing and the error overlay appears.
- **`_buildDoor`:**
  - Frame strip `fT = min(0.065, 0.08w)`, leaf thickness `lT = 0.038`, frame depth `fd = T + 0.064`.
  - An opaque dark "void" box `(w, h, 1.06T)` of colour `0x050810` covers the wall in the opening. The door is **not** cut into the wall.
  - Jambs `(fT, h, fd)` sit at `x = ±(w/2 + fT/2)`, outside the clear width. The header `(w+2fT, fT, fd)` sits above the opening. Frame colour is `0xD6CAB8`.
  - Closed leaf `(w−0.014, h−fT−0.008, lT)`, colour `0x9B6540`, at `z = −T/2 − lT/2`. It is flush with the local −Z wall face, and its top stops `fT` below the header.
  - Two raised panels of colour `0x7A5030`, `0.72·leafW` wide and 0.46/0.36 of the leaf height, on the −Z side.
  - A backplate `0xBB9020` and grip `0xD4AF37` at `x = 0.34·leafW`, `y = el + 0.48·leafH`.
  - There is no swing arc, and `swingFlipped` is not sent.
- **`_buildWindow`:**
  - `fT = min(0.055, 0.065w)`, glass thickness `gT = 0.010`, frame depth `fd = T + 0.05`.
  - The same void box `(w, h, 1.06T)`.
  - A four-piece frame of colour `0xECEAE4` inside the opening.
  - A glass box `(w−2fT, h−2fT, 0.010)`: `MeshStandardMaterial` `0xB8D8F5`, opacity 0.28.
  - Horizontal and vertical muntins of colour `0xDDD9D2`, `0.018` deep.
  - A sill `(w+0.06, 0.04, 0.11)` of colour `0xCDC8C0` at `z = −(T/2 + 0.03)`.
  - **Bug:** the glass (±0.005 m) and muntins (±0.009 m) lie entirely inside the opaque void box (±0.53T = ±0.106 m). They are never visible, so windows render as dark panels with a frame and sill.
- **Which side is "inside"?** The comments say "Inner face is −z". Local −Z maps to world `(dz, −dx)/len`. That is the room interior only if the polygon runs counter-clockwise on screen (negative area in `buildFloorShape` terms). For rooms drawn clockwise on screen, door leaves, panels, handles and window sills appear on the **outside**. Openings have no winding normalisation; the floor does.

#### Furniture: GLB models with procedural fallback
For each `furnitureItems` entry, `color = parseInt(colorHex.replace('#',''), 16)`. One `new THREE.GLTFLoader()` is created per room. There are three paths:
- **Model available** (`furnitureModels[item.type]` exists):
  - `loader.load('data:model/gltf-binary;base64,' + b64, onLoad, undefined, onError)`. This is asynchronous and runs after the camera fit.
  - `onLoad` takes `gltf.scene` and measures it with `Box3.setFromObject`.
  - It scales non-uniformly so the bounding box becomes exactly `widthM × heightM × depthM`, which distorts proportions.
  - It marks every mesh `castShadow`/`receiveShadow` and tags it `userData.furnitureType` and `roomId`.
  - It sets `position = (x − gcx, 0, z − gcz)`, `rotation.y = −rotationDeg·π/180`, and tags the root too.
  - The pivot is **not** re-centred: a model whose origin is not at its bottom centre floats, sinks or is offset. No contact shadow is added.
  - `armchair.gltf` is a JSON glTF with embedded `data:` buffers. GLTFLoader detects the non-`glTF` magic and parses it as text, so it works despite the binary MIME type.
- **Load or parse error:** `console.log('Model load failed for <type>, using fallback')`, then the procedural `createFurnitureGroup` is placed the same way, **without** a contact shadow.
- **No model** (type unmapped or asset missing): `createFurnitureGroup(item, color)` (L822).
  - Computes `dark = darkenHex(col, 0.62)` and `lite = lightenHex(col, 1.35)` and dispatches on `item.type` to a `buildX(g, w, d, h, col, dark[, lite])` (table in 8.4); unknown types get a plain box.
  - Sets `g.userData.furnitureType`.
  - Adds a contact-shadow plane: `PlaneGeometry(1.3w, 1.3d)` with the shared `_shadowTex` in a `MeshBasicMaterial({transparent, depthWrite: false})`, rotated flat at `y = 0.003`.
  - The group is placed and rotated as above.
- **Builder convention:** the group origin is the footprint centre at floor level; width along local X, depth along Z, height along Y; backrest, headboard or tank at −Z, front at +Z. This matches `furniture_painter.dart`, which draws the back at local −y and uses `canvas.rotate(+θ)`. `rotation.y = −θ` maps a clockwise on-screen rotation of the plan into Three.js correctly.

#### Materials, procedural textures, lights, shadows and colour management
- **Renderer:**
  - `WebGLRenderer({antialias: true, preserveDrawingBuffer: true})`.
  - `setPixelRatio(min(devicePixelRatio, 2))`.
  - Full-window size.
  - `shadowMap.enabled = true` with `PCFSoftShadowMap`.
  - No tone mapping, and `physicallyCorrectLights` is left at its default (false).
- **Scene and camera:** background `0x1A2030`. `PerspectiveCamera(55°, aspect, near 0.01, far 200)`.
- **Lights:**
  - `HemisphereLight(0xC8D8FF sky, 0x5A3D1A ground, 0.45)`.
  - "Sun": `DirectionalLight(0xFFF4E0, 1.0)` at (10, 18, 10), `castShadow`.
    - Shadow map 2048².
    - Orthographic shadow camera ±25 m, near 0.1, far 100.
    - Bias −0.0003.
  - "Fill": `DirectionalLight(0xC0D8FF, 0.25)` at (−8, 10, −8), no shadows.
  - One non-shadowing `PointLight(0xFFF0CC, 0.4, distance 5H)` per room. All of them sit at the centroid (see above).
- **Colour management bug (L164–169):**
  - The code tries `renderer.outputColorSpace = THREE.SRGBColorSpace` if `THREE.SRGBColorSpace !== undefined`, otherwise `outputEncoding = THREE.sRGBEncoding` ("Three.js < r152 fallback").
  - The bundled r148 **does** export `SRGBColorSpace = "srgb"` (for its `ColorManagement`) but has **no** `outputColorSpace` renderer property. The assignment is inert and the fallback never runs, so `outputEncoding` stays `LinearEncoding`.
  - Canvas textures (default `LinearEncoding`) and hex colours (r148 `ColorManagement.legacyMode = true`) pass through unconverted and look as authored.
  - GLB textures, which the loader tags `sRGBEncoding`, are decoded but never re-encoded. They are likely to look darker than authored.
- **`makeWoodTexture()` (L1028).** Draws a 512² canvas once per page and caches it in `_woodTex`:
  - 6 vertical planks, each with a random tint shift of ±18 on base `[186,148,90]`.
  - A vertical gradient towards `LIGHT [215,178,118]` / `DARK [130,88,35]`.
  - 28–42 wavy grain strokes. Each stroke's x offset is the sum of three sines, of amplitude 2.8, 1.3 and 1.1 px, with frequencies 0.013, 0.034 and 0.006 per px of y.
  - A knot with 55 % probability: 6 concentric ellipses plus a dark core.
  - A joint line with a 5 px shadow gradient at the left edge of planks 1–5. The comment says "right edge … except last".
  - `Math.random` makes it different on every page load. `RepeatWrapping`.
- **`makePlasterTexture()` (L1132).** 512² canvas, cached in `_plasterTex`:
  - Base `rgb(240,238,234)`.
  - 160 near-horizontal "trowel" ellipses (25–110 × 2–7 px, ±0.25 rad, α 0.018–0.055, white or `rgba(168,158,142)`).
  - 900 grain dots (r 0.7–3.2, α 0.025–0.08).
  - 5000 one-pixel dust flecks (α 0.008–0.035).
  - The comment mentions multiplying with `0xCDC8BC`, but the wall colour is `0xFFFFFF`, so that comment is stale.
- **`makeContactShadowTex()` (L1199).** 256² radial gradient with black alpha 0.55 → 0.32 (25 %) → 0.12 (55 %) → 0.03 (80 %) → 0, cached in `_shadowTex`.
- **`makeProceduralTexture(baseColor, pattern)` (L220).** 256² canvas, `repeat 3×3`:
  - `'fabric'`: base colour plus a woven grid of 4 px stripes every 8 px, alternating white and black, α 0.15.
  - `'wood'`: always `#8B6914` (ignores `baseColor`) plus diagonal strokes every 6 px.
  - `'ceramic'`: `#F5F5F0` plus a faint 32 px grid.
  - `'metal'`: `#9AABB8` plus 1 px lines every 3 px. Never used.
  - Default: flat colour.
- **Material helpers.** `mkMat(color, pattern, roughness=0.8, metalness=0)` wraps the canvas texture in `MeshStandardMaterial({map, color 0xFFFFFF})`. `mkBox(w, h, d, color, opts)` creates a `BoxGeometry` mesh with its own `MeshStandardMaterial` (roughness 0.75 and metalness 0.05 by default, or `opts.material`), `castShadow` and `receiveShadow`.

#### Camera and touch controls (custom `THREE.OrbitControls`)
- **Why a custom class.** r148's UMD build has no OrbitControls (the examples are not included), so the HTML defines a minimal touch-only `THREE.OrbitControls(camera, domElement)` (L43). It stores a `THREE.Spherical` offset `_sph` from `target`.
- **One finger:**
  - `theta −= (Δx / clientWidth)·3.0`, i.e. 3 rad per full-width swipe.
  - `phi = clamp(phi − (Δy / clientHeight)·2.0, 0.05, maxPolarAngle)`.
  - `maxPolarAngle` is 0.88π (about 158°), so the camera can go below the floor.
- **Two fingers:**
  - On `touchstart` it records `_pinch0` (finger distance) and `_pinchFocus = focusPointAt(midpoint)`. That is the first raycast hit on `houseGroup`; otherwise the intersection with the horizontal plane `y = target.y`; otherwise `target`.
  - On `touchmove`, `radius = clamp(radius·_pinch0/d2, minDistance, maxDistance)`. The target is then moved toward the focus by `clamp((radiusBefore − radiusAfter)·0.6, −dist, dist)`. Zooming in converges on the pinched spot; zooming out pushes the target away from it.
  - `_pinchFocus` is cleared when fewer than 2 touches remain.
- **What is missing.** There is no pan gesture, no two-finger rotate and no mouse support. All three listeners are registered `passive: false` and call `preventDefault()` on `touchstart`/`touchmove`.
- **Limits.** After construction the page sets `minDistance 0.5`, `maxDistance 50`, `maxPolarAngle 0.88π`, `target (0, 1.2, 0)` and `setPosition(6, 5, 6)`.
- **Per-frame update.** `controls.update()` runs every frame and sets `camera.position = target + fromSpherical(_sph)`, then `lookAt(target)`.
- **Reset view** (AppBar `Icons.center_focus_strong`):
  - In WebView mode, `_resetView` → `runJavaScript('window.resetCamera()')`. `resetCamera` (L1515) recomputes the centroid, `maxH`, `maxR` and `camD` from `lastData` (duplicated code from `buildHouse`) and re-applies the same camera fit.
  - In painter mode it resets `_rotX 1.1, _rotY 0.6, _zoom 0.7, _panOffset 0`.

#### Tap selection (walls, rooms, furniture)
**JS: detecting a tap** (L1567–1624). Separate passive touch listeners on the canvas:
- `touchstart` with exactly one touch records `_tapOrigin`; with more touches it clears it.
- `touchmove` beyond `TAP_SLOP = 12` px sets `_tapDragged`.
- `touchend` with one changed touch and no drag does the raycast:
  - NDC coordinates from the bounding rect.
  - `raycaster.intersectObjects(houseGroup.children, true)`.
  - Takes `hits[0].object` and walks up `.parent`.
- The first ancestor that matches decides the message:
  - `userData.wallIndex !== undefined` → `{type:'wallTap', roomId, index}`,
  - truthy `userData.furnitureType` → `{type:'furnitureTap', roomId, furnitureType}`,
  - `userData.roomId !== undefined` → `{type:'roomTap', roomId}`.
- Consequences:
  - Floor, ceiling (from inside), door and window parts (via `og`) all produce `roomTap`.
  - Furniture contact-shadow planes produce `furnitureTap`, so tapping the floor right next to an item hits the item.
  - Taps on empty space send nothing, so there is no deselect.

**Dart: handling the message** (`_onJsMessage`, L246):
- `wallTap`:
  - Sets `_activeShapeIndex` to the room's index, outside `setState`.
  - `setState`: `_selectedRoomId = roomId` and `_selectedWallIndex = (_selectedWallIndex == idx) ? null : idx`. The toggle compares only the index, so wall 2 of room B after wall 2 of room A *deselects*.
  - Then `runJavaScript('window.highlightWall(<roomId JSON>, <index or -1>)')`.
  - `highlightWall` (L1544) tints the matching wall's material `0x6AABEE` and resets every other wall to `0xFFFFFF`. The colour multiplies the plaster map.
- `roomTap`: `_activeShapeIndex = si`, `_selectedRoomId`, `_selectedWallIndex = null`, then `runJavaScript('window.highlightRoom(<roomId JSON>)')`. `highlightRoom` (L1555) tints **all** walls of that room and clears the others.
- `furnitureTap`: ignored (`break`).
- Every exception in `_onJsMessage` is swallowed (`catch (_) {}`).

**What the user sees.** With a wall selected, the bottom bar shows "Wall N selected". `_selectedRoomId` is never read, so the selected room is not shown anywhere except as blue walls.

#### Measuring the selected wall with BLE
- **Trigger.** The bottom bar shows a `Measure` link (bluetooth icon, bold) only when a wall is selected **and** `widget.bleManager != null`. There is no connection check.
- **`_triggerBleMeasurement` (L713):**
  - Sets `_waitingForBle`, which shows a spinner and "Measuring…".
  - Subscribes to `bleManager.packetStream` (a broadcast stream) with `.where((p) => !p.isCapturing && p.distanceMm > 0).first`. There is no timeout and no cancel.
- **On the first matching packet:**
  - If still mounted, `setState`: `_waitingForBle = false`, `_activeShape.wallRealMm[wallIdx] = mm` (direct mutation of the shared `SketchShape`), `_selectedWallIndex = null`.
  - Calls `widget.onWallMeasured?.call(wallIdx, mm)`. In SketchScreen this is `_applyRealMeasurement`, which writes `wallRealMm` of **SketchScreen's** active shape, rebuilds its points, re-syncs and queues cloud sync.
  - Clears `_selectedRoomId`.
  - Runs `highlightWall(null, -1)`, which un-tints everything.
  - Shows the green SnackBar "Wall N: X mm — updated!".
- **Problems:**
  - The callback carries no room id. If the tapped wall belongs to another room than SketchScreen's active one, two different rooms are modified.
  - The WebView scene is **not** re-sent after the points are rebuilt, so the 3D geometry stays stale.
  - The painter repaints, because `selectedWallIndex` changed.

#### Editing the room height
- **Trigger.** The AppBar chip (`Icons.height` plus `"{_wallHeightMm/1000 with 2 decimals}m"`, green `0xFF00AA66`) calls `_editHeight` (L640).
- **The dialog.** An `AlertDialog` titled "Room height" with "Enter the real height of the room walls.". The `TextField` is pre-filled with metres to 3 decimals, has suffix `m` and hint `e.g. 2.400`. Buttons are **CANCEL** and **APPLY**.
- **APPLY:**
  - Accepts `0.5 < v < 20.0`; other values close the dialog silently.
  - Sets `_wallHeightMm = v*1000`.
  - Calls `widget.onHeightChanged(v*1000)`, which sets SketchScreen's active shape `heightMm` and runs `_saveUndo`.
  - Calls `_sendRoomData()`. The JSON uses each `shape.heightMm`, so the change shows in 3D only because the callback mutated the shared shape first.
- **What is stale.** `_wallHeightMm` is initialised from the room that was active when the screen opened, and is never updated on `roomTap`/`wallTap`. The chip, the painter's wall height and the edit target can therefore disagree with the room selected in 3D.

#### Screenshot
- **Trigger.** AppBar `Icons.camera_alt` (WebView mode only) → `runJavaScript('window.captureScreenshot()')`.
- **JS (L1536).** `renderer.render(scene, camera)`, then `canvas.toDataURL('image/png')`, then posts `{type:'screenshot', data}`.
- **Dart.** `_handleScreenshot` ignores the data and shows the SnackBar "Screenshot ready — share in Phase 3D-5". Nothing is saved or shared.

#### Legacy painter mode (`_Room3DPainter`)
- **Trigger.** The AppBar toggle (`Icons.view_in_ar` in WebView mode, `Icons.layers` in painter mode; tooltip "Switch to Painter" / "Switch to Three.js") flips `_use3D`. The `WebViewController` and its page persist while the `WebViewWidget` is out of the tree.
- **Gestures** (`_buildPainterView`, L539):
  - One finger: `rotY += Δx·0.01`, `rotX = clamp(rotX − Δy·0.008, 0.05, π/2)`.
  - Two or more fingers: `zoom = clamp(_lastZoom·scale, 0.3, 5)` and `pan += focalPointDelta`.
  - Tap: even-odd `_pointInPolygon` against `_wallPolygons`, which `paint()` refills on every paint with each wall's outer-face quad. Walls are tested in index order, not depth order. A hit toggles `_selectedWallIndex`; a miss clears it.
- **Extra controls (painter only):**
  - Ceiling toggle (`Icons.roofing` / `roofing_outlined`).
  - Dimension-label toggle (`Icons.straighten`).
  - A top-left legend (Door `0xFF8B4513`, Window `0xFF4FC3F7`; no Opening entry) when the active room has objects.
- **What it draws.** Only `_activeShape`, with walls thick **inward** from the outline (200 mm). Three.js centres walls on the outline, so the two modes show different geometry. Details are in the file reference.

#### Resize, render loop and cleanup
- **Resize.** `window.resize` updates `camera.aspect`, calls `updateProjectionMatrix()` and `renderer.setSize`.
- **Render loop.** `animate()` (L1634) runs `requestAnimationFrame` → `controls.update()` → `render` forever, even when nothing changes.
- **Cleanup.** `disposeGroup(group)` (L288) recursively disposes geometries and materials and removes the children. It does **not** dispose textures:
  - per-builder canvas textures,
  - wood and plaster clones,
  - GLB textures.
- **No teardown.** `OrbitControls.dispose` is a no-op. The Dart `State` has no `dispose()`. GLB loads still in flight when `buildHouse` re-runs add their models to the already-detached old room group.

### 8.3 File reference

#### `code/lib/sketch/room_3d_screen.dart` — 1472 lines
- **Purpose:** The 3D screen. It creates and feeds the Three.js WebView, handles JS→Dart messages, offers BLE wall measurement and height editing, and contains the legacy pure-Dart pseudo-3D renderer `_Room3DPainter`.
- **Depends on:**
  - `dart:convert`: `jsonEncode`, `jsonDecode`, `base64Encode`.
  - `package:flutter/material.dart`.
  - `package:flutter/services.dart`: `rootBundle`.
  - `package:webview_flutter` 4.14.1 (resolved; Android impl 4.12.0): `WebViewController`, `JavaScriptMode`, `NavigationDelegate`, `JavaScriptMessage`, `WebViewWidget`.
  - `dart:math`: painter trigonometry.
  - `room_object.dart`: `RoomObject` (`wallIndex`, `positionAlong`, `widthMm`, `heightMm`, `elevationMm`, `isDoor`, `isOpening`).
  - `furniture_item.dart`: `FurnitureItem` (`type`, `position`, `rotationDeg`, `widthMm`, `depthMm`) and the `FurnitureTypeExtension` getters `name`, `color`, `heightMm`, `displayName`.
  - `sketch_model.dart`: `SketchShape` (`id`, `label`, `points`, `heightMm`, `roomObjects`, `furnitureItems`, `wallRealMm`).
  - `sketch_constants.dart`: `mmPerUnit = 5.0`.
  - `../ble/ble_manager.dart`: `BleManager.packetStream`, a broadcast `Stream<BlePacket>` with `distanceMm` and `isCapturing`.
  - Assets: `assets/3d/three_room.html`, `assets/3d/three.min.js`, `assets/3d/gltf_loader.js`, and the `assets/models/*` files declared in `pubspec.yaml` (`assets/3d/`, `assets/models/`).
- **Declarations:**
  - **`class Room3DScreen extends StatefulWidget` (L14)**
    - Fields:
      - `shapes: List<SketchShape>` — all rooms; this is the live, mutable list from SketchScreen.
      - `initialActiveShapeIndex: int` (default 0).
      - `bleManager: BleManager?`.
      - `onWallMeasured: void Function(int wallIndex, double mm)?`.
      - `onHeightChanged: void Function(double heightMm)?`.
    - Const constructor (L22). `createState()` → `_Room3DScreenState` (L32).
  - **`class _Room3DScreenState` (L35)**
    - Painter view state:
      - `_rotX = 1.1`, `_rotY = 0.6` (radians).
      - `_zoom = 0.7`, `_lastZoom = 0.7` (zoom at gesture start).
      - `_panOffset = Offset.zero`.
    - Selection and BLE: `_selectedWallIndex: int?`, `_selectedRoomId: String?` (written, never read), `_waitingForBle: bool`.
    - `_wallPolygons: List<List<Offset>>` — screen quads of the outer wall faces, written by the painter during `paint`, read by tap hit-testing.
    - Painter toggles: `_showCeiling = false`, `_showDimensions = true`.
    - `_wallHeightMm: late double` — height used by the AppBar chip and the painter.
    - `static const _mmScale = 0.10` — painter pixels per millimetre before perspective and zoom.
    - `_activeShapeIndex: late int` with getter `_activeShape => widget.shapes[_activeShapeIndex]`.
    - WebView state: `_use3D = true`, `_webController: late WebViewController`, `_webLoaded = false` (set true in `onPageFinished`, never reset).
    - Methods:
      - `initState()` (L65): see 8.2.
      - `_initWebView()` (L72): builds the controller (unrestricted JS, `FlutterBridge` channel, `onPageFinished` → `_webLoaded = true; _sendRoomData()`), then calls `_loadInlinedHtml()` without awaiting.
      - `Future<void> _loadInlinedHtml()` (L89): loads the three assets as strings, injects both scripts at `<!--THREE_JS-->`, and calls `loadHtmlString`.
      - `Future<Map<String,String>> _loadFurnitureModels(List<FurnitureItem>)` (L101): for each distinct `type.name` with a mapped path, `rootBundle.load` → `base64Encode`. Errors are caught and logged. Loads run sequentially.
      - `String? _modelPathForType(String typeName)` (L126): a const map from type name to asset path, listed in 8.4. It has 26 keys: three point to missing files and one (`kitchenStove`) is not a `FurnitureType`.
      - `Map<String,dynamic> _buildHouseJson()` (L162): serialises all `widget.shapes` (schema in 8.4). Not sent: `isClosed`, `wallRealMm`, `sharedWalls`, `RoomObject.swingFlipped`/`id`, `FurnitureItem.id`.
      - `void _sendRoomData()` (L211): guard on `_webLoaded`, then fire-and-forget `_sendRoomDataAsync()`.
      - `Future<void> _sendRoomDataAsync()` (L216): JSON plus models, then chunked `runJavaScript` (250 000 chars per chunk), then `initHouse`. On error a SnackBar. There is no in-flight guard.
      - `void _onJsMessage(JavaScriptMessage)` (L246): `jsonDecode` and switch on `type`: `ready` → `_sendRoomData`; `wallTap`, `roomTap` (see 8.2); `furnitureTap` → ignored; `screenshot` → `_handleScreenshot(data['data'])`. All errors are swallowed.
      - `void _handleScreenshot(String dataUrl)` (L293): placeholder SnackBar (dark green `0xFF003311`, 2 s, monospace).
      - `didUpdateWidget(Room3DScreen old)` (L308): if `_use3D && _webLoaded && old.shapes.length != widget.shapes.length`, calls `_sendRoomData()`. The route builder always passes the same list instance, so this practically never fires. The comment ("new furniture dropped, room edited") is aspirational.
      - `Widget build(BuildContext)` (L319): see **UI**.
      - `Widget _buildPainterView()` (L539): `GestureDetector` (tap and scale) around `RepaintBoundary(CustomPaint(_Room3DPainter(...), child: SizedBox.expand()))`. It passes `_activeShape.points`, `roomObjects`, `wallRealMm`, `furnitureItems` and the view state.
      - `void _resetView()` (L592): see 8.2.
      - `Widget _legendDot(Color, String)` (L605): a 10 px circle plus a 10 pt monospace label.
      - `bool _pointInPolygon(Offset p, List<Offset> poly)` (L623): even-odd ray-casting test.
      - `Future<void> _editHeight()` (L640): the height dialog. Its `TextEditingController` is never disposed.
      - `void _triggerBleMeasurement()` (L713): see 8.2.
  - **`class _Room3DPainter extends CustomPainter` (L746)** — legacy renderer ("kept as fallback / Phase 3D-1 baseline").
    - Fields:
      - `points`, `roomObjects`, `wallRealMm`, `furnitureItems`,
      - `rotX`, `rotY`, `zoom`, `panOffset`, `selectedWallIndex`,
      - `wallHeightMm`, `mmScale`,
      - `wallPolygons` (output list, mutated),
      - `showCeiling`, `showDimensions`.
    - Constructor at L762.
    - `Offset _project(x, y, z, Size)` (L779):
      - Rotate about Y by `rotY`: `x1 = x cos − z sin`, `z1 = x sin + z cos`.
      - Rotate about X by `rotX`: `y2 = y cos − z1 sin`, `z2 = y sin + z1 cos`.
      - Perspective `p = 700 / (700 + z2 + 500)`.
      - Screen point `(W/2 + x1·p·zoom + pan.dx, H/2 + y2·p·zoom + pan.dy)`.
      - Up is **negative** y; walls go from `y = 0` to `y = −H`.
    - `void paint(Canvas, Size)` (L798): see **Key logic**.
    - `_drawReveal(canvas, a, b, c, d)` (L1290): a jamb quad filled `0xFF0D1117` with a `0xFF333333` 0.8 px outline.
    - `_drawDoor3D(...)` (L1307):
      - Dark hole `0xFF0A0E14` and three reveals (left, right, top).
      - Inner hole.
      - Leaf inset 5 % toward the centre, filled `0xFF8B4513` with a `0xFF5C2E00` stroke.
      - Frame stroke `0xFF4A3728` at 2.5 px.
      - Gold knob `0xFFFFD700`, r = 3, 15 % in from the right edge and 45 % up.
    - `_drawOpening3D(...)` (L1365): hole, three reveals, inner hole, faint `0xFF4A5568` outline. No leaf or glass.
    - `_drawWindow3D(...)` (L1403):
      - Hole plus a `0xFF4FC3F7` tint at 25 %.
      - Four reveals, including the sill.
      - Inner tint at 15 %.
      - Frame `0xFF90A4AE` at 2.5 px, a 1.5 px cross muntin, and a white 20 % glint line at 10 % from the left.
    - `shouldRepaint(old)` (L1461): compares rotX, rotY, zoom, panOffset, selectedWallIndex, wallHeightMm, showCeiling, showDimensions and the `roomObjects`/`furnitureItems` **lengths**. It does not compare points or `wallRealMm`.
- **Key logic (painter `paint`):**
  1. Clears `wallPolygons` and adds one empty list per wall.
  2. Centroid `(cx, cy)` in mm is the vertex mean. `wx/wz(world) = (world·mmPerUnit − c)·mmScale`; `H = wallHeightMm·mmScale`.
  3. Floor polygon: fill `0xFFB0B8C0`, stroke `0xFF666666` at 1.5 px.
  4. Draw-order list of records `(kind, index, depth)`:
     - kind 0: walls, depth at the edge midpoint,
     - kind 1: furniture, depth at its position,
     - kind 2: corner caps, depth at the vertex,
     - where `depth = X·sin(rotY) + Z·cos(rotY)`, sorted descending (far to near).
  5. Inward unit normals per wall: the perpendicular `(dy, −dx)/len`, flipped so it points toward the centroid. Wall thickness is `200 mm / mmPerUnit = 40` world units.
  6. Mitred inner corners. For each vertex `j`:
     - Offset the previous and next edges inward: `p1 = pj + nPrev·T`, `p2 = pj + nNext·T`.
     - If `|d1 × d2| < 1e-6` (collinear), the corner is `pj + (nPrev + nNext)·T/2`.
     - Otherwise `t = ((p2 − p1) × d2) / (d1 × d2)`, clamped to `±3T/|d1|`, and the corner is `p1 + t·d1`.
  7. Corner cap (kind 2):
     - A vertical quad from the outer vertex to the inner corner.
     - Drawn only if its outward normal faces the viewer (`capVis > 0`).
     - Grey level `clamp(175 + clamp(depth·8, ±60), 90, 230)` at 90 % opacity.
  8. Furniture (kind 1):
     - Footprint corners rotated by `rotationDeg` (clockwise on screen) around `position`; height `type.heightMm·mmScale`.
     - A soft black 22 % ellipse shadow, 0.65 × the summed parallel edge lengths.
     - Side faces depth-sorted and back-face-culled (`fvis >= 0` is skipped), shaded `lerp(black, base, 0.45 + 0.55·(−fvis))`.
     - Top face `lerp(white, base, 0.65)`, edges black at 20 %.
     - `displayName` label (8 pt, white, shadowed) at the top-face centroid.
  9. Wall (kind 0):
     - Stores the outer quad `s0..s3` in `wallPolygons[i]`.
     - Projects the inner quad from the mitred corners.
     - Grey levels: `outerL = clamp(180 + clamp(depth·8, ±60), 100, 240)`, `topL = outerL + 35`, `innerL = outerL − 45`.
     - `innerVis = n·(sin rotY, cos rotY)`.
     - If `innerVis > 0` (far wall), fill the inner face (selected: `0xFF2A5F8A`).
     - Always fill the top cap (selected: `0xFF5AAAE0`).
     - Otherwise (near wall) fill the outer face at 85 % (selected: `0xFF4A90D9` plus a `0xFF00AAFF` 2.5 px stroke).
     - Then doors, windows and openings on this wall: outer quad on the outline, inner quad offset by `normal·T`, `halfW = widthMm/mmPerUnit/2`, heights `·mmScale`.
     - Then, if `showDimensions`, the label `W{i+1}  {len}` at the face centre. `len = wallRealMm[i] ?? |b − a|·mmPerUnit`, shown as `x.xx m` (≥ 1000 mm) or `N mm`; colour `0xFF00AAFF` when selected, else `0xFF4A5568`.
  10. If `showCeiling`, a polygon at `−H` (`0xFF161B22` at 70 %, `0xFF2D3748` outline) drawn over everything.
  11. Corner dots (r 3.5): the first vertex green `0xFF48BB78`, the others blue `0xFF4299E1`.

  The projection maps plan +x to screen right and plan +y (= Z) to screen **up** when seen from above. The frame is therefore left-handed and the painter shows a **mirror image** of the 2D plan. The Three.js view does not. This is derived from `_project`; with `rotY = 0` and `rotX = π/2` the screen point is `(x, −z)`.
- **State and data:** All state is in `_Room3DScreenState` fields. Room data is read from the live `widget.shapes` objects, and two of them are mutated: `wallRealMm` (BLE) and, indirectly through callbacks, `heightMm` and points. The JSON contracts are in 8.4.
- **UI** (`build`, L319):
  - `Scaffold` with background `0xFF0D1117`.
  - AppBar `0xFF161B22` with title "3D Room (WebView)" / "3D Room (Painter)" in 14 pt monospace. Actions in order:
    1. Height chip → `_editHeight`.
    2. Screenshot `Icons.camera_alt` (WebView only).
    3. Reset `Icons.center_focus_strong`.
    4. Ceiling toggle (painter only).
    5. Dimensions toggle (painter only).
    6. 3D/Painter toggle.
  - Body: a `Stack` of:
    - `WebViewWidget(controller: _webController)` or `_buildPainterView()`;
    - a bottom bar (`Positioned` 16 px from the bottom, 12 px sides, `0xFF161B22` with a `0xFF30363D` border, radius 8) showing either:
      - a hint ("Pinch/drag to orbit & zoom • tap wall to select" in WebView mode, "1 finger = rotate • 2 fingers = zoom/pan • tap wall to select" in painter mode), or
      - "Wall N selected" plus the BLE **Measure** link or the "Measuring…" spinner;
    - in painter mode only, the top-left legend.
- **Connections:**
  - Used only by `sketch_screen.dart` (import at L19, push at L3423).
  - Calls `SketchScreen._applyRealMeasurement` and the height setter through the callbacks.
  - Reads BLE packets (Part BLE).
  - Talks to `three_room.html` through `runJavaScript` and `FlutterBridge`.
- **Notes and issues:**
  - The painter is used only by manual toggle and has no automatic fallback.
  - `_selectedRoomId` is dead state; `furnitureTap` is ignored.
  - `withOpacity` is deprecated in current Flutter, so analyzer infos are expected.
  - There is no `dispose()`. Pending `.first` BLE futures are only neutralised by the `mounted` check.
  - The `runJavaScript` calls from buttons and taps are not awaited, so a JS error (for example before the page has loaded) surfaces as an unhandled async error.
  - Hard-coded values: wall thickness (0.2 m in JSON, 200 mm in the painter), chunk size 250 000, the asset map, the BLE packet filter, and the valid height range 0.5–20 m.

#### `code/assets/3d/three_room.html` — 1652 lines
- **Purpose:** A self-contained HTML page that, once Dart has injected Three.js and GLTFLoader, builds and renders the 3D house. It handles touch orbit, zoom and tap selection and talks to Flutter through `window.FlutterBridge`.
- **Depends on:**
  - The global `THREE` from the injected `three.min.js` (r148).
  - `THREE.GLTFLoader` from the injected `gltf_loader.js`.
  - `window.FlutterBridge`, the JavaScriptChannel object provided by webview_flutter.
  - DOM canvas 2D for the procedural textures.
  - No network or external files. GLB data arrives as base64 data URLs.
- **Declarations** (in order):
  - **Markup and CSS (L1–33):**
    - Viewport with `user-scalable=no`; `body` background `#0D1117`, `overflow: hidden`.
    - `#loading`: centred, `#00AA66` monospace, `pointer-events: none`, text "Initializing 3D view…" plus `<small>` "Loading scene".
    - `#error`: hidden, red `#FF6666` on 85 % black, max 80vw.
    - The `<!--THREE_JS-->` injection marker (L32), then one inline `<script>` (L34–1650).
  - `window.onerror` (L36) — shows `'Error (line N): msg'` in `#error`.
  - **`THREE.OrbitControls = function(camera, domElement)` (L43)**
    - Public fields:
      - `camera`, `domElement`, `target: Vector3`,
      - `enableDamping = false` and `dampingFactor = 0.05` (both unused),
      - `minDistance = 0.1`, `maxDistance = 1000`, `maxPolarAngle = 0.88π` (overridden after construction).
    - Private state: `_sph: Spherical`, `_prev: Touch[]`, `_pinch0: number`, `_pinchFocus: Vector3|null`.
    - Private helpers: `clamp(v, a, b)` (L61), `pinchDist(touches)` (L63), `focusPointAt(screenX, screenY)` (L72).
    - Listeners: `touchstart` (L89), `touchmove` (L100), `touchend` (L131).
    - Methods:
      - `update()` (L136): positions the camera from `target + _sph` and calls `lookAt`.
      - `setPosition(x, y, z)` (L142): sets the spherical offset from a world position relative to `target`, clamps the radius, then calls `update`.
      - `dispose()` (L149): no-op.
  - `window._pendingRoomData = null`, plus a stub `window.initHouse = data => _pendingRoomData = data` (L153–156). It queues data that arrives before the real `initHouse` exists. This never happens in practice, because Dart sends only after page load.
  - Globals:
    - `renderer` (L159), `scene` (L173), `camera` (L177), `controls` (L181),
    - an anonymous `HemisphereLight`, `sun` (L192), `fill` (L204),
    - `houseGroup` (L209),
    - `lastData`, `_woodTex`, `_plasterTex`, `_shadowTex` (L212–215),
    - `_textureLoader = new THREE.TextureLoader()` (L217, **unused**).
  - Texture and material helpers:
    - `makeProceduralTexture(baseColor, pattern)` (L220),
    - `mkMat(color, pattern, roughness, metalness)` (L278),
    - `disposeGroup(group)` (L288),
    - `darkenHex(hex, f)` (L308) and `lightenHex(hex, f)` (L313) — per-channel multiply with clamping to 0/255,
    - `mkBox(w, h, d, color, opts)` (L320).
  - **Furniture builders** — all `(g, w, d, h, col, dark)` and all add meshes to `g` with the origin at floor centre:
    - `buildChair` (L338):
      - seat `(0.88w, 0.07h, 0.62d)` at height `0.46h`, `z = 0.05d`;
      - back `(0.84w, h − 0.53h, min(0.1d, 0.055))` at `z ≈ −0.48d`;
      - 4 legs `min(0.1w, 0.055)` square at `(±0.35w, ±0.28d)`.
    - `buildArmchair` (L362):
      - dark base `(w, 0.40h, d)` and dark back `(w, 0.60h, 0.22d)`;
      - cushion `(innerW − 0.02, 0.14h, 0.87·seatD)`;
      - two arms `(0.12w, 0.75h, seatD)` in the item colour.
    - `buildSofa` (L395): like the armchair with arm 0.09w, back 0.20d, seat 0.38h, cushion 0.13h, arms 0.72h. Uses fabric `mkMat` textures. Cushion count is 3 if `w > 2.0`, 2 if `w > 1.4`, else 1.
    - `buildBed(…, lite)` (L436):
      - wood-textured headboard `(w, 0.85h, max(0.08, 0.07d))` at −Z and frame `(w, 0.28h, d)`;
      - fabric mattress in `lite` colour `(0.93w, 0.14h, d − headT)`;
      - pillows `0xF5F0EB`, two of `0.35w` at `±0.2w` if `w > 1.3`, otherwise one of `0.7w`.
    - `buildTable` (L476): top `(w, 0.06h, d)` and 4 legs `min(0.05w, 0.06)` inset `0.8·legT`.
    - `buildRoundTable` (L495):
      - cylinder top `r = min(w, d)/2`, 28 segments;
      - tapered post (`legR = min(0.12r, 0.045)`, bottom `1.3·legR`, metalness 0.3);
      - cross-shaped foot `2·0.72r × 0.04 × 3·legR`.
    - `buildToilet` (L527): forces `col 0xF5F5F0` and `dark 0xE0E0DC`; tank `(0.62w, 0.82h, 0.28d)` at −Z, bowl `(w, 0.45h, d − tank)`, seat `0xEEEEEC`. Its `ceramicMat` is created but unused.
    - `buildWardrobe` (L553):
      - wood-textured body (brown regardless of `col`);
      - cap `(1.01w, 0.045h, 1.01d)`;
      - centre divider `(0.025, 0.78h, 0.015)`;
      - two `0xAAAAAA` handles at `±0.22w`.
      - Its `darkMat` is unused.
    - `buildBathtub` (L577): forced white; outer box `(w, h, d)` plus inner box `(w − 0.36h, 0.82h, d − 0.36h)`. Both tops are at `y = h`, so they z-fight and the tub is not hollow. `ceramicMat` unused.
    - `buildSink` (L594): forced white; pedestal `(0.35w, 0.72h, 0.35d)`, basin `(w, 0.18h, d)`, tap `0xCCCCCC` at `z = −0.3d`. `ceramicMat` unused.
    - `buildFloorLamp` (L617): `r = 0.5·min(w, d)`; metal base cylinder (`0.75r`/`0.9r`, `0.04h`), pole (`0.1r`), tapered shade (`0.55r`/`r`, `0.16h`) in the item colour. It emits no light.
    - `buildNightstand` (L653): body `(w, 0.92h, d)`, overhanging top, drawer groove at `0.58h`, one handle.
    - `buildDresser` (L676): body plus top `(1.04w, 0.035h, 1.04d)` sitting *above* `h`; 3 drawer rows in `0.80h` starting at `0.08h`, with dividers and two `0xBBBBBB` handles per row.
    - `buildRefrigerator` (L710): body, cap, freezer split at `0.72h`, tall and short handles at `x = 0.34w`.
    - `buildShower` (L740): tray `(w, 0.04h, d)`; three transparent glass walls (`0xCCEEFF`, opacity 0.22, 0.022 thick) of height `h` *above* the tray; arm; rose disc (metalness 0.8). `col` is unused and the front is open.
    - `buildWashingMachine` (L785): body, cap, porthole cylinder (`r = 0.3·min(w, h)`, `0x112233`, rotated to face +Z) with a chrome ring, control strip at `0.87h`.
  - `createFurnitureGroup(item, col)` (L822) — the dispatcher (table in 8.4). The default is `mkBox(w, h, d, col)`. It sets `userData.furnitureType`.
  - `_buildDoor(g, w, h, el, T)` (L875) and `_buildWindow(g, w, h, el, T)` (L938) — see 8.2.
  - Floor and wall geometry:
    - `buildFloorShape(rawPts, lxFn, lzFn)` (L1003),
    - `makeWoodTexture()` (L1028), `makePlasterTexture()` (L1132), `makeContactShadowTex()` (L1199),
    - `buildWallGeometry(len, H, T, openings)` (L1221).
  - Scene building: `buildRoomGroup(data, gcx, gcz, furnitureModels)` (L1253) and `buildHouse(data)` (L1465).
  - Window API:
    - `window.initHouse(data)` (L1504),
    - `window.resetCamera()` (L1515),
    - `window.captureScreenshot()` (L1536),
    - `window.highlightWall(roomId, index)` (L1544),
    - `window.highlightRoom(roomId)` (L1555).
  - Tap detection globals (L1567–1571): `raycaster`, `mouse2`, `_tapOrigin`, `_tapDragged`, `TAP_SLOP = 12`, plus three passive listeners (L1573, L1582, L1590).
  - Resize listener (L1627), the `animate()` IIFE (L1634), the pending-data flush (L1641) and the `ready` post (L1647).
- **Key logic:** see 8.2 (scene build, walls and holes, doors and windows, furniture paths, textures, controls, tap walk-up).
- **State and data:**
  - Module-level `var`s: `lastData` (whole last payload), cached base textures, `houseGroup` (scene graph), control and tap state.
  - Scene-graph tagging:
    - room group: `{roomId}`,
    - floor and ceiling: `{roomId}`,
    - wall: `{wallIndex, roomId}`,
    - door/window group: `{roomId}`,
    - procedural furniture group: `{furnitureType, roomId}`,
    - GLB root and each GLB mesh: `{furnitureType, roomId}`,
    - shadow plane: no tags (its parent has them).
  - Message formats are in 8.4.
- **UI:**
  - A full-window WebGL canvas.
  - The `#loading` overlay until the first successful `buildHouse` with ≥ 1 room.
  - The `#error` overlay, which shows only the latest error and, unlike `#loading`, catches touches.
  - Gestures: one-finger orbit, two-finger pinch zoom toward the pinch point, tap to select.
  - No on-page buttons.
- **Connections:** Loaded only by `room_3d_screen.dart` (`rootBundle` plus `loadHtmlString`). Calls `FlutterBridge.postMessage`. Called through `runJavaScript`.
- **Notes and issues:** see 8.5, in particular:
  - the inert sRGB setting,
  - world-space UV tiling (floor planks; walls with openings),
  - hidden window glass,
  - winding-dependent door/sill side,
  - centroid-stacked point lights,
  - shared walls duplicated,
  - texture leaks in `disposeGroup`,
  - the always-on render loop,
  - `preserveDrawingBuffer: true`, which is probably unnecessary because `captureScreenshot` renders immediately before `toDataURL`,
  - unused `_textureLoader`, `'metal'` pattern, `ceramicMat`/`darkMat`, `enableDamping`/`dampingFactor`,
  - the duplicated camera-fit code in `resetCamera`,
  - the stale comments: wood joint "right edge", plaster "multiplied with 0xCDC8BC", "Three.js < r152 fallback".

#### `code/temp.js` — 1502 lines
- **Purpose (what it is):** A **stale scratch copy** of the inline `<script>` body of an *intermediate* version of `three_room.html`.
  - It starts with an empty line and ends with the two-space indentation that preceded `</script>`, which is consistent with copying the text between the `<script>` and `</script>` lines.
  - It was committed together with the multi-room rewrite in commit `b98f9a9` ("fix 3d multiroom", 2026-09-16) and has not changed since (`git show b98f9a9:code/temp.js` is identical to the working copy).
  - It is already multi-room: `initHouse`, `houseGroup`, `buildRoomGroup`, global centroid, `highlightRoom`, `roomTap`.
  - It descends from the pre-fix version `8fcd51c`, which lacked `buildTable`. In history, `buildTable` was removed in `37e2836`, restored in `1a50461`, removed in `8fcd51c`, and restored in `b98f9a9`.
- **Depends on:** Nothing. It is **not referenced anywhere**: no hits for `temp.js` outside `build/`, it is not under a declared asset folder, so it is not bundled, and no Dart code loads it.
- **Declarations:** The same functions and globals as `three_room.html`, with the same names and bodies, except for the differences below. Line offsets: temp.js `Lk` ≈ HTML `L(k+33)` up to OrbitControls, then shifted.
- **Meaningful differences from the current `three_room.html` script** (from `diff --strip-trailing-cr` of HTML L35–1650 against `temp.js`):
  1. **OrbitControls without pinch-to-focus.** There is no `clamp`, `focusPointAt` or `_pinchFocus`; pinch only changes the radius around a fixed target (temp.js L10–76).
  2. **`buildTable` is missing.** `createFurnitureGroup` still calls it for `diningTable`, `coffeeTable`, `desk`, `kitchenCounter`, `islandCounter`, `stove` and `tvUnit` (temp.js L744–746). That would throw `ReferenceError: buildTable is not defined`, aborting `buildHouse` ("initHouse error" overlay).
  3. **No `buildWallGeometry` and no `isOpening` handling.** All walls are plain `BoxGeometry` (L1191). Every non-door object, including openings, is drawn with `_buildWindow` (L1225–1227).
  4. **`buildRoomGroup(data, gcx, gcz)` reads `data.furnitureModels` per room** (L1241). The Dart payload puts `furnitureModels` at top level, so with the current Dart code this is always `{}`: GLB models would never be used, and `buildHouse` passes no models (L1336).
  5. Everything else (builders, textures, doors and windows, highlight, tap, resize, render loop, `ready`) is byte-for-byte identical apart from line endings.
- **Key logic / State and data / UI:** Identical to `three_room.html` apart from the above.
- **Connections:** None.
- **Notes and issues:** Dead file that can confuse readers and tools. It should be deleted or moved out of the Flutter project root.

#### `code/assets/3d/three.min.js` — 6 lines
- **Purpose:** The Three.js core library.
- **Identification:**
  - Header comment: `@license Copyright 2010-2022 Three.js Authors, SPDX-License-Identifier: MIT`.
  - The minified UMD wrapper defines the global `THREE`.
  - `REVISION` is `"148"`, i.e. **r148**.
  - The file is 608 319 bytes: a 5-line header plus one 608 220-character line.
  - It contains neither `OrbitControls` nor `GLTFLoader` (examples are not bundled), which is why the HTML defines its own controls.
  - It exports `SRGBColorSpace = "srgb"` and `sRGBEncoding = 3001`, has `outputEncoding` (default `LinearEncoding = 3000`), but no `outputColorSpace`. This is the root of the colour-management bug.
- **How loaded:** Read as a string by `_loadInlinedHtml` (`rootBundle.loadString('assets/3d/three.min.js')`) and **inlined** as a `<script>` element replacing `<!--THREE_JS-->`. It is not loaded by URL, `loadFlutterAsset` or `runJavaScript`.
- **Connections:** Required by everything in `three_room.html`. Bundled via the `assets/3d/` entry in `pubspec.yaml`.
- **Notes:** None beyond the version facts above.

#### `code/assets/3d/gltf_loader.js` — 3628 lines
- **Purpose:** The three.js glTF 2.0 loader in its legacy **non-module "examples/js" form**: `( function () { class GLTFLoader extends THREE.Loader {…} … THREE.GLTFLoader = GLTFLoader; } )();`. It has no import/export statements, so it works as a classic script.
- **Identification:**
  - No version header.
  - Supported extensions: `KHR_binary_glTF`, `KHR_draco_mesh_compression`, `KHR_lights_punctual`, `KHR_materials_clearcoat`, `KHR_materials_pbrSpecularGlossiness`, `KHR_materials_transmission`, `KHR_materials_unlit`, `KHR_texture_basisu`, `KHR_texture_transform`, `KHR_mesh_quantization`, `EXT_texture_webp`, `EXT_meshopt_compression`. There is no volume, ior, specular, sheen or iridescence.
  - It still sets `material.skinning`, `morphTargets` and `vertexTangents`.
  - It assigns `THREE.RGBFormat` to alpha-less (JPEG) textures.
  - These traits mark it as an **r12x-era build, older than the r148 core** (inference; the exact revision is not stated).
  - Version-mismatch effects:
    - r148 still maps `RGBFormat (1022)` to RGBA, but with a console warning.
    - The obsolete material flags are ignored.
    - The spec-gloss shader patching (`GLTFMeshStandardSGMaterial.onBeforeCompile`) was not verified against r148 shader chunks.
- **How loaded:** Inlined exactly like `three.min.js`, as the second `<script>` element.
- **Is glTF actually used?**
  - **Yes, in `three_room.html`:** `buildRoomGroup` creates `new THREE.GLTFLoader()` and calls `loader.load('data:model/gltf-binary;base64,…')` for every furniture item whose type has data in `furnitureModels`.
  - That data comes from Dart `_loadFurnitureModels`. 22 of the 31 `FurnitureType`s have an existing asset (see 8.4).
  - `temp.js` contains the same code but would never receive model data.
  - No other code uses glTF.
- **Connections:** Requires `THREE` (load order: after `three.min.js`). Used only by `buildRoomGroup`.

### 8.4 Data contracts

**Dart → JS (`WebViewController.runJavaScript`)**

| Call (exact JS) | Sent from | Purpose |
|---|---|---|
| `window._roomDataChunks = [];` | `_sendRoomDataAsync` | Reset the chunk buffer, a global created by Dart and never cleared after use. |
| `window._roomDataChunks.push("<slice>");` (×⌈len/250 000⌉) | `_sendRoomDataAsync` | Each slice is a ≤ 250 000-char substring of the house JSON, wrapped by `jsonEncode` as a JS string literal. |
| `window.initHouse(window._roomDataChunks.join(""));` | `_sendRoomDataAsync` | Parse and build the whole house. |
| `window.highlightWall(<"roomId" or null>, <wallIndex or -1>)` | `wallTap` handling; after a BLE measurement as `highlightWall(null, -1)` | Tint the selected wall `0x6AABEE`, all others white. |
| `window.highlightRoom(<"roomId">)` | `roomTap` handling | Tint all walls of the room. |
| `window.captureScreenshot()` | Screenshot button | Render and post a PNG data URL. |
| `window.resetCamera()` | Reset button (WebView mode) | Re-fit the camera to the house. |

**House JSON** (argument of `initHouse`, built by `_buildHouseJson` plus `furnitureModels`):

```json
{
  "rooms": [
    {
      "id": "1726493212345678_3",
      "label": "Bedroom",
      "points": [ { "x": 1.25, "z": 0.40 }, { "x": 5.25, "z": 0.40 }, { "x": 5.25, "z": 3.40 } ],
      "wallHeightM": 2.4,
      "wallThicknessM": 0.2,
      "roomObjects": [
        { "wallIndex": 0, "positionAlong": 0.5, "widthM": 0.9, "heightM": 2.1,
          "elevationM": 0.0, "isDoor": true, "isOpening": false, "kind": "door" }
      ],
      "furnitureItems": [
        { "type": "sofa", "x": 2.10, "z": 1.30, "rotationDeg": 90.0,
          "widthM": 2.2, "depthM": 0.9, "heightM": 0.85, "colorHex": "#4caf50" }
      ]
    }
  ],
  "furnitureModels": { "sofa": "<base64 of assets/models/Sofa.glb>" }
}
```

- `id` is `SketchShape.id` (`'<microsecondsSinceEpoch>_<counter>'`) and is used as `roomId`.
- `label` and `kind` are sent but **never read** by JS.
- JS defaults: `wallHeightM || 2.4`, `wallThicknessM || 0.2`, `roomObjects || []`, `furnitureItems || []`, `furnitureModels || {}`.
- All shapes are included, even unclosed polylines (rendered as closed rooms) and empty shapes (skipped when `points` has fewer than 3 entries).

**JS → Dart (`FlutterBridge.postMessage(JSON.stringify(…))`, handled by `_onJsMessage`)**

| Message | When | Dart reaction |
|---|---|---|
| `{"type":"ready"}` | End of the page script | `_sendRoomData()`, a no-op if `onPageFinished` has not fired yet. |
| `{"type":"wallTap","roomId":"<id>","index":<int>}` | Tap whose hit chain reaches a wall mesh | Select or toggle the wall, set the active room, `highlightWall`. |
| `{"type":"roomTap","roomId":"<id>"}` | Tap on floor, ceiling (from inside), or door/window parts | Set the active room, clear the wall selection, `highlightRoom`. |
| `{"type":"furnitureTap","roomId":"<id>","furnitureType":"<FurnitureType.name>"}` | Tap on furniture or its contact-shadow plane | Ignored. |
| `{"type":"screenshot","data":"data:image/png;base64,…"}` | `captureScreenshot()` | Placeholder SnackBar; data discarded. |

**Units and axes**

| Quantity | 2D model (Dart) | JSON | Three.js scene |
|---|---|---|---|
| Plan point | `Offset(dx, dy)` world units (5 mm), y down | `{x: dx·0.005, z: dy·0.005}` metres | `(x − gcx, 0, z − gcz)`; X = plan x, **Z = plan y**, Y up, floor at y = 0 |
| Wall height | `SketchShape.heightMm` (default 2400) | `wallHeightM = heightMm/1000` | `H` (default 2.4); walls span y ∈ [0, H] |
| Wall thickness | — | `wallThicknessM: 0.2` (hard-coded) | `T`, centred on the edge; box length `len + T` |
| Object on wall | `wallIndex`, `positionAlong` 0..1, `widthMm`, `heightMm`, `elevationMm` | metres (`/1000`) | Centre `a + u·positionAlong·len`; local x along the wall, z through it |
| Furniture position | `position` (world units, footprint centre) | `x`, `z` metres | Group at `(x − gcx, 0, z − gcz)` |
| Furniture rotation | `rotationDeg`, clockwise on screen | `rotationDeg` | `rotation.y = −rotationDeg·π/180` (consistent with the 2D painter) |
| Furniture size | `widthMm`, `depthMm` per item; height = `type.heightMm` | `widthM`, `depthM`, `heightM` | Local X = width, Z = depth, Y = height; back at −Z, front at +Z |
| Colour | `FurnitureType.color` (ARGB) | `colorHex` `'#rrggbb'` (lower-case) | `parseInt(hex, 16)` |
| Painter (legacy) | — | — | Own frame: centroid-relative mm × 0.1 px/mm; up = −y; walls thick inward (200 mm) |

**Furniture type → 3D representation.** "Model" = GLB/glTF path in `_modelPathForType`. "Builder" = procedural fallback in `createFurnitureGroup`. The builder is used when there is no model data or loading fails.

| FurnitureType | Model asset (`assets/models/…`) | Asset present? | Procedural builder |
|---|---|---|---|
| `sofa` | `Sofa.glb` | yes | `buildSofa` |
| `armchair` | `armchair.gltf` (JSON, embedded buffers) | yes | `buildArmchair` |
| `coffeeTable` | `coffee_table.glb` | yes | `buildTable` |
| `floorLamp` | `Floorlamp.glb` | yes | `buildFloorLamp` |
| `bookshelf` | `bookshelf.glb` | yes | `buildWardrobe` |
| `tvUnit` | `tv_unit.glb` | **no**, so always procedural | `buildTable` |
| `singleBed` | — (unmapped; `Singlebed.glb` exists, unused) | — | `buildBed` |
| `doubleBed` | — (unmapped) | — | `buildBed` |
| `queenBed` | `doublebed.glb` (`Queenbed.glb` unused) | yes | `buildBed` |
| `kingBed` | `doublebed.glb` | yes | `buildBed` |
| `dresser` | `dresser.glb` | **no** (file is `dresser (2).glb`) | `buildDresser` |
| `nightstand` | — | — | `buildNightstand` |
| `wardrobe` | `wardrobe.glb` | yes | `buildWardrobe` |
| `diningTable` | `dining_table.glb` | yes | `buildTable` |
| `roundDiningTable` | — (`round_table.glb` unused) | — | `buildRoundTable` |
| `barStool` | `bar_stool.glb` | yes | `buildChair` |
| `chair` | `chair.glb` | yes | `buildChair` |
| `kitchenCounter` | `kitchen_counter.glb` | yes | `buildTable` |
| `islandCounter` | `island_counter.glb` | yes | `buildTable` |
| `refrigerator` | — (`refrigerator.glb` unused) | — | `buildRefrigerator` |
| `stove` | `gas_stove.glb` | yes | `buildTable` |
| `sink` | `kitchen_sink.glb` | yes | `buildSink` |
| `bathtub` | `Bathtub-new.glb` | yes | `buildBathtub` |
| `shower` | `shower.glb` | yes | `buildShower` |
| `toilet` | `toilet.glb` | yes | `buildToilet` |
| `basinSink` | `basinSink.glb` | yes | `buildSink` |
| `vanity` | — (`vanity.glb` unused) | — | `buildWardrobe` |
| `desk` | `desk.glb` | yes | `buildTable` |
| `officeChair` | `office_chair.glb` | yes | `buildChair` |
| `filingCabinet` | `FilingCabinet.glb` | **no** (file is misspelt `FillingCabinet.glb`) | `buildWardrobe` |
| `washingMachine` | `Washingmachine.glb` | yes | `buildWashingMachine` |
| (map-only key `kitchenStove`) | `kitchen_stove.glb` | yes, but there is no such `FurnitureType` | — |
| any other string | — | — | default `mkBox(w, h, d, col)` |

The dispatcher covers all 31 enum values, so the default box is unreachable for valid types. In total 22 types load a model; the other 9 always use builders. Unreferenced files are still bundled because `pubspec.yaml` lists the whole `assets/models/` folder (201 MB in total, of which about 76 MB is never referenced):
- `cupboard.glb` 30 MB,
- `bed.glb`, `Queenbed.glb`, `Singlebed.glb`, `coffeetable.glb`, `kitchensink.glb`,
- `refrigerator.glb`, `refrigerator (1).glb`, `round_table.glb`, `shower_cabin.glb`, `vanity.glb`,
- `FillingCabinet.glb`, `dresser (2).glb`,
- plus `kitchen_stove.glb`, which is effectively unused.

### 8.5 Known issues and limitations

**Bridge and data flow**
- **Huge payloads.** Every send base64-encodes each used model again: about ×1.33 of file size, e.g. `toilet.glb` becomes about 37.6 MB of JSON. The payload is pushed in 250 000-char `runJavaScript` chunks and parsed with `JSON.parse`. Afterwards it stays referenced in `window._roomDataChunks` and `lastData`. There is no caching, and memory spikes are likely on low-end devices.
- **Possible double send.** `ready` and `onPageFinished` both trigger `_sendRoomData`. Normally `ready` arrives first and is ignored (`_webLoaded` is still false). If both arrive with `_webLoaded` true, two concurrent `_sendRoomDataAsync` calls share `window._roomDataChunks` and can interleave chunks, corrupting the JSON. There is no in-flight guard or sequence id.
- **Stale scene.**
  - After a BLE measurement the points are rebuilt in SketchScreen but the WebView is never refreshed.
  - `didUpdateWidget` only compares `shapes.length` of the same list instance, so it effectively never fires.
- **Room identity is lost on the way back to SketchScreen.**
  - `onWallMeasured(wallIndex, mm)` and `onHeightChanged(mm)` carry no room id, and SketchScreen applies them to *its* active shape.
  - Meanwhile `Room3DScreen` writes `wallRealMm` directly into the 3D-selected shape.
  - When a wall or room of a different room was tapped in 3D, two different rooms get modified, or the wrong one.
  - `_wallHeightMm` and the height chip never follow the room selected in 3D.
- **Ignored or dead fields:**
  - `label` and `kind` are sent but unused.
  - `furnitureTap` is ignored.
  - `_selectedRoomId` is never read.
  - `isClosed`, `sharedWalls`, `wallRealMm`, `swingFlipped` and per-item heights are not represented.
  - Unclosed shapes are rendered as closed rooms.
  - An out-of-range `wallIndex` in `roomObjects` throws and aborts the build of that room and all following rooms.
- **Error handling:**
  - `_onJsMessage` swallows all exceptions.
  - `_loadInlinedHtml` and the button-triggered `runJavaScript` calls are not awaited, so their errors go unhandled.
  - JS errors are shown only in the on-page `#error` box, and GLB failures only in `console.log`.
- **Selection quirks:**
  - The `wallTap` toggle compares only the index, not the room.
  - Taps on empty space do not deselect.
  - The furniture contact-shadow planes capture taps on the surrounding floor.
- **BLE measurement:** there is no timeout or cancel. It accepts the first non-capturing packet with distance > 0, and it does not check that the device is connected.
- **Screenshot:** produced but discarded (placeholder for "Phase 3D-5"; `share_plus` is not used here).

**Rendering correctness**
- **Colour management is inert.** In r148, `THREE.SRGBColorSpace` exists but `renderer.outputColorSpace` does not. The output stays linear, and GLB textures (tagged sRGB by the loader) are likely to render darker. There is no tone mapping.
- **Floor plank scale is wrong.** The repeat formula assumes normalised UVs, but r148 `ShapeGeometry` UVs are in metres. Planks become about 1/(6·rptX) m wide, e.g. about 2.8 cm in a 4 m room, and shrink as rooms grow. Walls with openings (`ExtrudeGeometry`, world UVs) tile the plaster far more densely than box walls.
- **Hidden window glass.** Glass and muntins are fully enclosed in the opaque `1.06T` void box. Doors and windows are not cut into the wall (only openings are), and floor-level or full-height openings keep 1 cm lips.
- **Door/sill side depends on winding.** Door leaves, panels, handles and window sills are on local −Z. That is inside the room only for rooms drawn counter-clockwise on screen; there is no winding normalisation (unlike the floor).
- **Shared walls are not handled.** Adjacent rooms produce coincident duplicate walls (z-fighting), and a hole cut for an opening in one room is still covered by the neighbour's wall. Wall corners overlap or notch because of the `len + T` boxes.
- **Point lights.** All per-room point lights sit at the global centroid instead of their room centres.
- **GLB models:**
  - non-uniform stretch to the footprint;
  - pivot not re-centred (models may float, sink or be offset);
  - native front direction assumed to be +Z;
  - no contact shadow on the GLB path or the GLB-error fallback.
- **Procedural builder simplifications:**
  - Counters, stove, TV unit and desk render as four-legged tables.
  - The kitchen sink renders as a pedestal basin.
  - Bookshelf, filing cabinet and vanity render as two-door wardrobes.
  - The bathtub is a solid block with z-fighting top faces.
  - Toilet, bathtub and sink ignore the item colour.
  - The `'wood'` pattern ignores colour, so wardrobes and bed frames are always brown.
  - The dresser top and shower glass exceed the item height.

**Performance and resources**
- An always-on `requestAnimationFrame` loop renders even when idle.
- Rendering is costly: `preserveDrawingBuffer: true`, a 2048² PCF-soft shadow map, antialiasing, a separate material per box mesh, and a new `GLTFLoader` per room.
- **Leaks:**
  - `disposeGroup` never disposes textures (per-builder canvas textures, unused `ceramicMat`/`darkMat` textures, GLB textures).
  - Async GLB loads attach to detached groups after a rebuild.
  - `OrbitControls.dispose()` is a no-op and listeners are never removed.
  - The Dart `State` has no `dispose()`.
- About 0.78 MB of HTML with inlined Three.js is re-sent and re-parsed every time the screen opens.
- About 76 MB of unreferenced models are bundled into the app.

**Controls and UI**
- The custom controls are touch-only (no mouse) and have no pan gesture.
- `maxPolarAngle` 0.88π lets the camera go under the floor.
- Pinch-zoom-out pushes the target away from the pinch point, and the target is unbounded.
- `#loading` never hides if `rooms` is empty. `#error` shows only the last error.
- No ceiling or dimension toggles in WebView mode, no wall labels in 3D, and no indicator of which room is selected.

**Legacy painter**
- It draws a single room only.
- Its geometry differs from the Three.js view: walls are thick inward, not centred.
- Its projection is left-handed, so it shows a mirror image of the plan (derived from `_project`).
- Depth sorting is an approximate painter's algorithm.
- Wall tap hit-testing goes by index order, not depth.
- `shouldRepaint` ignores point changes.
- It is reached only by manual toggle; there is no automatic fallback.
- It uses the deprecated `withOpacity`.

**Repository hygiene**
- `code/temp.js` is a dead, divergent copy of the page script. It is missing `buildTable` (would throw), looks up models per room (GLB never used), and has no opening holes and no pinch focus.
- `_modelPathForType` points to 3 missing files and 1 non-existent type.
- `gltf_loader.js` is an older r12x examples/js build running on the r148 core (RGBFormat warnings, obsolete material flags).
- Several comments are stale or misleading:
  - "Three.js < r152 fallback",
  - the wood joint "right edge",
  - plaster "0xCDC8BC",
  - `didUpdateWidget` "new furniture dropped",
  - `FurnitureItem` "0 = facing right" versus the 3D/2D back-at-−y convention.


---

## Part 9 — Backend, authentication, cloud sync and collaboration

### 9.1 Overview

This part covers everything that leaves the phone over the network:

- **The backend** in `code/smartmeasure-backend/` is a small Node.js REST API (Express 5.2.1, `pg` 8.20.0 against PostgreSQL, `bcryptjs`, `jsonwebtoken`). It provides:
  - user accounts with bcrypt password hashes and 7-day JWTs;
  - cloud copies of floor-plan projects, which are uploaded as whole snapshots and stored relationally;
  - invite-code sharing, with a per-collaborator `can_edit` permission;
  - change polling for live viewing;
  - presence: who else currently has a project open.
- **The Flutter side** is made up of:
  - `ApiService`: static HTTP wrapper for every endpoint, and JWT storage.
  - `SyncService`: a singleton offline upload queue persisted in the SQLite table `pending_uploads`.
  - `LoginScreen`.
  - `CollaborationScreen`, with its private wrapper `_LiveCollabWrapper` that implements "Open live" polling.
  - The legacy, unreachable `CloudProjectsScreen`.
- The code that **builds upload payloads, triggers auto-sync, sends heartbeats and shows presence avatars and the sync icon** is in `code/lib/sketch/sketch_screen.dart`. That file belongs to the sketch part and is described here only at call-site level (line numbers refer to that file).

None of this part uses Riverpod. State is plain `setState`, static methods (`ApiService`) and a hand-written singleton with broadcast streams (`SyncService`).

**Vocabulary**

| Term | Meaning |
|---|---|
| local project / local id | Row in the phone's SQLite `projects` table and its `id` (see the database part). |
| cloud project / cloud id | Row in PostgreSQL `projects` and its `id`. `projects.user_id` is the owner. |
| `local_id` | Column of the cloud project that stores the uploader's local id at first upload. Used as a fallback match key. |
| shape | One room polygon (`SketchShape`). Stored in `shapes`, with children `shape_points`, `wall_real_mm`, `wall_angles` and `wall_lengths`. |
| room object | Door, window or opening (`RoomObject`). Stored in `room_objects`. |
| snapshot upload | `POST /sync/upload` carrying the complete project. The server deletes every child row and re-inserts everything. There are no delta updates. |
| pending upload | A serialized snapshot waiting in SQLite `pending_uploads` until the server accepts it. |
| invite code | 8-character `[0-9A-Z]` code in `projects.invite_code`. Anyone who holds it can join. |
| collaborator | `project_collaborators` row. `role` is always `'editor'`, `status` is always `'accepted'`, and `can_edit` defaults to `FALSE`. |
| `can_edit` | The only permission flag that is enforced. It lets a collaborator upload. |
| presence | `project_presence.last_seen_at`, refreshed by a 30-s heartbeat. "Active" means seen within the last 2 minutes. |
| live mode | "Open live" in `CollaborationScreen`. A sketch view that polls `/sync/updates` every 10 s and remounts when the server copy changes. |
| conflict | An upload whose `last_modified_at` is older than the server's `projects.updated_at`. Returns HTTP 409. |

```text
 FLUTTER APP (code/lib)                                         BACKEND (code/smartmeasure-backend)
 main.dart AppStartup                                           src/app.js  Express 5, listens on $PORT or 3000, 0.0.0.0
   ├─ SyncService.instance.init()  (connectivity + 60 s timer)    cors() [origin *]   express.json() [100 kb]
   └─ ApiService.isLoggedIn() ─┬─ false ─► LoginScreen            GET  /health
                               └─ true  ─► HomeScreen             /auth      routes/auth.js      (public)
 LoginScreen ── login()/register() ──────────────┐               /projects  routes/projects.js ┐ router.use(authMiddleware)
 HomeScreen "Restore from Cloud" ─► CollaborationScreen          /sync      routes/sync.js     ┘ "Authorization: Bearer <JWT>"
   tabs: My Projects (GET /projects) | Shared With Me             middleware/auth_middleware.js (jwt.verify, JWT_SECRET)
   "Open live" ─► _LiveCollabWrapper ─ every 10 s GET /sync/updates      │
                    └─► SketchScreen(cloudProjectId, canEdit)       src/db/db.js  pg.Pool (DATABASE_URL + SSL, or DB_* vars)
 SketchScreen edits ─► _queueAutoSync / _backupToCloud                  │
   └─► SyncService.queueUpload ─► SQLite pending_uploads                ▼
         processQueue ─► ApiService.uploadProject ─ POST /sync/upload ─► PostgreSQL: users, projects, shapes, shape_points,
 SketchScreen every 30 s ─ POST /sync/heartbeat + GET /sync/active-…      wall_real_mm, wall_angles, wall_lengths, room_objects,
                                                                          furniture_items, project_collaborators, project_presence
 ApiService: baseUrl = http://13.214.196.211:3000 ; JWT in FlutterSecureStorage key 'jwt_token'
```

**Where the server lives.** `ApiService.baseUrl` is hard-coded as `'http://13.214.196.211:3000'`: a raw public IPv4 address over plain HTTP. Git history shows how it changed:

1. `http://192.168.1.102:3000` (LAN; commit 67f13ec, 2026-04-24).
2. `https://e21-3yp-smart-laser-distance-meter-production.up.railway.app` (87c45b1, 2026-04-26).
3. The current value (6dd1dcb, 2026-09-11).

Comments in `db.js` and in the migrations still mention Railway. The unmerged remote branch `origin/backend-host-azure` changes `db.js` for Azure. The repository has no deployment files (Dockerfile, Procfile, `.env.example`, CI) and no automated tests for any file in this part.

---

### 9.2 Features and how they work

#### 9.2.1 Backend bootstrap and request pipeline

**Trigger:** `npm start` (`node src/app.js`) or `npm run dev` (`nodemon src/app.js`) in `code/smartmeasure-backend/`.

1. `app.js` L1–3 loads `express`, `cors` and `dotenv`. `require('dotenv').config()` reads `.env` from the current working directory into `process.env`. dotenv 17 prints an "injecting env" line every time `config()` runs, and it runs twice (app.js and db.js).
2. L5–7 require the three routers. Each router requires `db/db.js`. That module builds the shared `pg.Pool` and immediately checks out one connection. It logs `Connected to PostgreSQL database` or `Database connection failed: <message>`. The process keeps running even if the database is unreachable.
3. Global middleware:
   - `cors()` with library defaults: `Access-Control-Allow-Origin: *`, methods `GET,HEAD,PUT,PATCH,POST,DELETE`, preflight answered with 204. CORS is irrelevant for the native Android client; it only matters for browsers.
   - `express.json()` with defaults: 100 kb body limit, parses only `Content-Type: application/json`. In Express 5 (body-parser 2.2.2), `req.body` stays `undefined` when nothing is parsed.
4. Mounts:
   - `/auth` → `routes/auth.js` (public).
   - `/projects` → `routes/projects.js`.
   - `/sync` → `routes/sync.js`.
   - `GET /health`, inline, returns `{"status":"OK","message":"SmartMeasure backend running"}` without touching the database.

   Both `projects.js` and `sync.js` call `router.use(authMiddleware)` first, so **every** path under `/projects` and `/sync` requires a JWT, including unknown sub-paths.
5. `app.listen(process.env.PORT || 3000, '0.0.0.0')` logs `Server running on port <PORT>`.
6. **Error handling.** There is no custom error middleware and no 404 handler. Every route handler wraps its body in `try/catch` and returns JSON `500` with a generic message.

   Anything not caught falls to Express 5's built-in final handler, which answers with an **HTML** page and logs the stack to stderr. The page includes the stack trace unless `NODE_ENV=production`. Cases that reach it:
   - malformed JSON → 400;
   - body over 100 kb → 413;
   - unknown route → 404 `Cannot GET /x`;
   - a rejected promise outside a `try`, such as `pool.connect()` in `/sync/upload` or the double `client.release()` described in 9.2.6. Express 5 forwards rejected async-handler promises to `next(err)` automatically.

#### 9.2.2 App start-up session check

`main.dart` → `_AppStartupState.initState`:

1. `SyncService.instance.init()`.
2. `_checkLogin()` → `ApiService.isLoggedIn()`. This returns `true` iff secure storage holds a value under `jwt_token`. It does **not** check validity or expiry.
3. `Navigator.pushReplacement` to `HomeScreen` (token present) or `LoginScreen` (no token). A spinner on `0xFF0D1A27` is shown meanwhile.

`HomeScreen._loadUserEmail` (home_screen.dart L29) base64url-decodes the JWT payload and shows its `email` claim in the AppBar.

#### 9.2.3 Registration and login

**UI:** `LoginScreen` (email + password fields, Login/Register button, mode toggle, "Skip for now (local only)").

1. `_submit()` trims both fields; the password is trimmed too. If either is empty it shows the SnackBar "Please enter email and password". It then sets `_isLoading` (button shows a spinner and is disabled).
2. **Login mode:** `ApiService.login(email, password)` → `POST /auth/login` with body `{"email","password"}` and header `Content-Type: application/json` only.

   Server, `auth.js` L50:
   - Missing field → 400 `{"error":"Email and password are required"}`.
   - `SELECT * FROM users WHERE email = $1` (exact, case-sensitive). No row → 401 `{"error":"Invalid email or password"}`.
   - `bcrypt.compare` fails → the same 401.
   - Otherwise `jwt.sign({ userId: user.id, email: user.email }, JWT_SECRET, { expiresIn: '7d' })` (HS256 default) and 200 `{"message":"Login successful","token":"<jwt>","user":{"id":<int>,"email":"..."}}`.

   Client: if the decoded body contains `token`, it is written to secure storage (`saveToken`). The decoded body is returned whatever the status code.
3. **Register mode:** `ApiService.register` → `POST /auth/register`.

   Server, `auth.js` L9:
   - Missing field → 400 `{"error":"Email and password are required"}`.
   - `password.length < 6` → 400 `{"error":"Password must be at least 6 characters"}`.
   - `SELECT id FROM users WHERE email=$1` finds a row → 409 `{"error":"Email already registered"}`.
   - Otherwise `bcrypt.hash(password, 10)`, then `INSERT INTO users (email, password_hash) VALUES ($1,$2) RETURNING id, email`, then 201 `{"message":"Registration successful","user":{"id","email"}}`.

   Client: if `result['message'] != null && result['error'] == null`, it immediately calls `ApiService.login` with the same credentials. The registration message is never shown.
4. **Result:**
   - If the final map has `error`, a SnackBar shows the server text. On a socket exception or a non-JSON body the text is "Cannot connect to server. Check your connection.".
   - Otherwise `pushReplacement(HomeScreen)`.
5. **"Skip for now (local only)"** goes to `HomeScreen` with no token. Cloud features are still reachable but every protected call returns 401. The UI shows this only as empty lists or an orange "offline" sync icon.

#### 9.2.4 Logout and token lifetime

- **Logout:** the HomeScreen logout icon calls `ApiService.logout()`, which deletes `jwt_token`, then `pushReplacement(LoginScreen)`.
  - The server is not contacted; JWTs are stateless, so the token stays valid until `exp`.
  - SQLite `pending_uploads` is **not** cleared. Queued snapshots of the previous user are later uploaded with the next user's token (see 9.5).
- **Expiry:** tokens last 7 days (`exp = iat + 604800`). After that, `isLoggedIn()` still returns `true` and every protected endpoint answers 401 `{"error":"Invalid or expired token. Please login again."}`.
  - No client code reacts to 401: there is no automatic logout and no re-login prompt.
  - The user must log out and log in manually.

#### 9.2.5 Uploading a project: manual backup and auto-sync through the offline queue

**Triggers** (in `sketch_screen.dart`):

- **"Backup to Cloud"** toolbar button (`Icons.cloud_upload`, enabled only when the active room has points) → `_backupToCloud()` (L645):
  1. Not logged in → orange SnackBar "Please login first to backup to cloud".
  2. Dialog "Cloud Backup Name" (default "Room Project", buttons Cancel/Upload).
  3. If the sketch has no local id yet, it saves to SQLite first (`DatabaseHelper.saveProject`).
  4. SnackBar "Uploading to cloud..." (60 s).
  5. `_buildProjectPayload(chosenName)`, then `SyncService.instance.queueUpload(...)`.
  6. SnackBar "Queued for sync — will upload automatically".

  The real upload outcome is visible only through the sync icon. `widget.canEdit` is **not** checked here.
- **Auto-sync:** `_queueAutoSync()` (L612) is called from 26 call sites after editing operations (closing or moving rooms, point edits, door/window/furniture placement, move, resize, rotate and delete, room rename, undo/redo, …).
  - It returns early if `!widget.canEdit`, if `ApiService.isLoggedIn()` is false, or if the project was never saved and nothing is drawn.
  - With no local id it first saves locally under the name `'Auto Save'`.
  - Payload name = active room's `label` if not empty, otherwise `'Room Project'`. This **overwrites the cloud project name** on every edit.
- The payload is built by `_buildProjectPayload(name)` (L537). The exact JSON is in 9.4.3. It sends `project.cloud_project_id` when the screen knows the cloud id.
  - It also sends `last_modified_at` = `_lastCloudUpdatedAt`: the server `updated_at` returned by this screen's last successful upload, or `null`. A `null` value is omitted from the JSON.

**Queue algorithm** (`sync_service.dart`):

1. `queueUpload(projectId: <local id>, projectData, lastModifiedAt)` (L57):
   - JSON-encodes `{...projectData, 'last_modified_at'?}`.
   - `DatabaseHelper.queueUpload` inserts a `pending_uploads` row (`project_id`, `payload`, `created_at` = local ISO time, `status = 'pending'`).
   - Status is set to `idle`, then `processQueue()` is called without `await`.

   Each call adds a new full snapshot. Nothing de-duplicates older snapshots of the same project.
2. `processQueue()` (L74):
   - Re-entrancy guard `_isProcessing`.
   - Loop: `getNextPendingUpload()` returns the oldest `status='pending'` row (`ORDER BY created_at ASC LIMIT 1`). An empty queue ends the loop.
   - Status → `syncing`.
   - `ApiService.uploadProject(payload)`. The `lastModifiedAt` named parameter is not used because it is already inside the payload.
3. Outcomes:

   | Result | Action |
   |---|---|
   | `result['conflict'] == true` (HTTP 409) | `markUploadConflict(id)` (`status='conflict'`, `last_attempt`). Status → `conflict`. Stop. The row is never retried. |
   | Any `error` key (socket exception, non-JSON body, or any 400/401/403/404/413/500) | `markUploadAttempted(id)` (`attempts+1`, `last_attempt`). Status → `offline`. Stop. The row stays `pending` and is retried first next time. |
   | Success | `deletePendingUpload(id)`. Emit `{local_project_id: row.project_id, cloud_project_id, updated_at}` on `uploadSuccessStream`. Status → `idle`. Continue with the next row. |
   | Thrown exception in the loop body | Same as error. |

4. **Retry triggers:** `init()` (L32) subscribes to `Connectivity().onConnectivityChanged`:
   - Any result other than `ConnectivityResult.none` → `processQueue()`.
   - All `none` → status `offline`.

   It also starts `Timer.periodic(60 s)` → `processQueue()`, which runs for the whole app lifetime. Every new `queueUpload` also triggers processing.
5. **Consumers:**
   - `SketchScreen.initState` listens to `uploadSuccessStream` (L223). It stores `_cloudProjectId = cloud_project_id` and `_lastCloudUpdatedAt = updated_at`, then calls `_startHeartbeat()`. It does **not** check `local_project_id`.
   - `statusStream` (L219) only triggers `setState` so the icon redraws.
   - `_LiveCollabWrapper` also listens to `uploadSuccessStream` (9.2.15).

#### 9.2.6 Server-side snapshot upload and conflict detection (`POST /sync/upload`, sync.js L12)

1. `const client = await pool.connect()` takes a dedicated client so the work can run in a transaction. This line is outside `try`, so a connection failure becomes an Express default 500 HTML page.
2. Destructure `{ project, shapes, roomObjects, furnitureItems, last_modified_at }`, then `BEGIN`.
3. **Find the target project.**
   - If `project.cloud_project_id` is truthy: `SELECT id, updated_at FROM projects WHERE id = $1`, with **no owner filter**, so collaborators can update shared projects.
   - Then `existing` is either the same query by id (if found) or the fallback `SELECT id, updated_at FROM projects WHERE user_id = $1 AND local_id = $2`, which finds the caller's own project with that local id.
4. **Existing project:**
   1. **Permission:** `SELECT user_id FROM projects WHERE id=$1`. If the caller is not the owner, it requires `SELECT can_edit FROM project_collaborators WHERE project_id=$1 AND user_id=$2 AND status='accepted'` to return a row with `can_edit = true`. Otherwise `ROLLBACK` and 403 `{"error":"Edit access not granted"}`.
   2. **Optimistic concurrency:** if `last_modified_at` is present and `new Date(projects.updated_at) > new Date(last_modified_at)`, then `ROLLBACK` and 409 `{"conflict":true,"server_updated_at":"<ISO>"}`. With no `last_modified_at` there is no check (blind overwrite).
   3. `UPDATE projects SET name = $1, updated_at = NOW() WHERE id = $2`. `local_id` and `user_id` are never changed, so a collaborator's upload renames the owner's project.
   4. Full child wipe:
      - `SELECT id FROM shapes WHERE project_id`;
      - for each shape, `DELETE` from `shape_points`, `wall_real_mm`, `wall_angles` and `wall_lengths` by `shape_id`;
      - then `DELETE` from `shapes`, `room_objects` and `furniture_items` by `project_id`.
5. **New project:**
   - Invite code = `Math.random().toString(36).substring(2,6).toUpperCase()` concatenated twice (8 chars).
   - `INSERT INTO projects (user_id, name, local_id, invite_code, updated_at) VALUES ($1,$2,$3,$4,NOW()) RETURNING id`.
6. **Re-insert everything,** one `INSERT` per row:
   - each shape: `(project_id, shape_index, is_closed) RETURNING id`;
   - its `shape_points (shape_id, order_index, x, y)`;
   - `wall_real_mm (shape_id, wall_index, real_mm)`;
   - `wall_angles (shape_id, order_index, angle)`;
   - `wall_lengths (shape_id, order_index, length)`;
   - each room object: `room_objects (project_id, object_id, type, wall_index, position_along, width_mm, height_mm, elevation_mm, shape_index ?? 0)`;
   - each furniture item: `furniture_items (project_id, shape_index ?? 0, furniture_id, type, position_x, position_y, rotation_deg ?? 0, width_mm, depth_mm)`.

   `furnitureItems` may be absent (`|| []`). `shapes`, `roomObjects` and each shape's four arrays are mandatory; a missing one throws a TypeError, which leads to `ROLLBACK` and 500.
7. `COMMIT`, then `SELECT updated_at FROM projects WHERE id=$1`, then 200 `{"message":"Project uploaded successfully","cloud_project_id":<int>,"updated_at":"<ISO>"}`. `NOW()` is the transaction **start** time.
8. Any exception → `ROLLBACK` and 500 `{"error":"Upload failed"}`. `finally` → `client.release()`.

**Defect in steps 4.1 and 4.2:** both early returns call `client.release()` themselves, and then `finally` calls it again.
- pg-pool throws `Release called on client which has already been released to the pool.`
- Express 5 receives the rejected promise. Because the 403/409 response was already sent, its final handler logs the error and **destroys the socket**.
- The JSON body is usually already flushed, so the client normally sees it. When it is not, the client gets a connection error instead and treats the 409 as a network error (retries) rather than a conflict.

#### 9.2.7 Mapping local projects to cloud projects

- **Server:** `projects.local_id` holds the uploader's SQLite id. It is set only on INSERT. The fallback match is `(user_id, local_id)`.
- **Client:**
  - The cloud id is **never persisted** (the SQLite `projects` table has no cloud column). It lives only in `SketchScreen._cloudProjectId`, which comes from `widget.cloudProjectId` (live mode) or from the first `uploadSuccessStream` event. Later payloads include it as `project.cloud_project_id`.
  - `_lastCloudUpdatedAt` is likewise memory-only.
- **Consequences** (details in 9.5):
  1. Re-opening a local project later depends on the `(user_id, local_id)` fallback and sends no `last_modified_at`, so it is a blind overwrite.
  2. `_handleBackPressed` → "Save Changes" saves a **new** local row and deletes the old one, together with its pending uploads. The next session no longer matches `local_id` and creates a **duplicate** cloud project with a new invite code.
  3. Local ids from another device or a reinstall can equal an existing `local_id` of the same user. That cloud project is then silently overwritten.
  4. `_loadProjectById` ("Load Project" inside an open sketch) does not reset `_cloudProjectId`. The newly loaded project is uploaded **into the previously linked cloud project**.
  5. The success-event listener ignores `local_project_id`. A sketch can adopt the cloud id of another project's queued upload.
  6. "Restore to device" creates an unlinked local copy. Editing it makes the owner upload a new duplicate, or makes a collaborator create a fork owned by themselves.

#### 9.2.8 Sync status indicator

`SketchScreen._buildSyncIcon()` (L4081) reads `SyncService.instance.status`:

| Status | Icon |
|---|---|
| `syncing` | 16 px `CircularProgressIndicator` (0xFF00AAFF) |
| `offline` | `Icons.cloud_off` (orange 0xFFFF8800). Used for **any** failure, including 401/403/500. |
| `conflict` | `Icons.warning_amber` (red) |
| `idle` | `Icons.cloud_done` (green 0xFF00CC44) |

There is no conflict-resolution UI. The red icon stays until a later upload succeeds or a new item is queued, because `queueUpload` resets the status to `idle`.

#### 9.2.9 Browsing cloud projects (Collaboration screen)

**Entry:** HomeScreen button "Restore from Cloud" (home_screen.dart L173) → `CollaborationScreen`.

- `initState` creates a 2-tab `TabController` and fires `_loadOwned()` and `_loadShared()` in parallel.
- **My Projects tab:**
  - Data: `ApiService.getCloudProjects()` → `GET /projects` → `SELECT * FROM projects WHERE user_id = $1 ORDER BY updated_at DESC`.
  - Each card: purple cloud icon, `name`, `updated_at` formatted `d/m/yyyy` in local time.
  - ⋮ menu: **Open live**, **Restore to device**, **Share invite code**, **View collaborators**.
  - Pull-to-refresh calls `_loadOwned`.
  - Empty text: "No cloud projects yet.\nBackup a project from the sketch screen." The empty state has no pull-to-refresh.
- **Shared With Me tab:**
  - Data: `GET /projects/shared` (accepted collaborations).
  - Each card: people icon, `name`, "Owner: <owner_email> · d/m/yyyy".
  - ⋮ menu: **Open live (auto-sync)**, **Restore to device**, **Leave project**.
  - Empty state: "No shared projects yet." plus a "Join a project" button.
- Any failure (401, network, 500) produces `[]`, which looks exactly like "no projects".

#### 9.2.10 Restore to device (download)

**Trigger:** ⋮ "Restore to device" on either tab → `_restoreProject(id, name)` (collaboration_screen.dart L66).

1. `_working = true`: the whole body becomes a spinner with "Working...".
2. `ApiService.downloadProject(id)` → `GET /sync/download/:id`.
   - Server: access is allowed for the owner **or** an accepted collaborator (no `can_edit` needed); otherwise 404 `{"error":"Project not found or access denied"}`.
   - Response: `{project, shapes[], roomObjects[], furnitureItems[]}` (9.4.3).
3. `null` → red SnackBar "Restore failed. Try again.".
4. `_parseProjectData(data)` (L401):
   - **Shapes,** in array order (the server orders by `shape_index`): `SketchShape.empty()` (fresh random id), `isClosed = is_closed`, `points = [Offset(x,y)]`, `wallRealMm[wall_index] = real_mm`.
   - **Wall data:** `wallAngles` / `wallLengths` come from the **first** shape's `wall_angles[].angle` / `wall_lengths[].length` only.
   - **Room objects:** built as `RoomObject(id: object_id, ownerShapeId: shapes[shape_index].id, type: 'door' → door, anything else → window, …)`. Each is appended to `shapes[shape_index].roomObjects` and also to a flat list.
   - **Furniture:** built as `FurnitureItem(id: furniture_id, type: FurnitureType by name (unknown → sofa), position: Offset(position_x, position_y), rotationDeg, widthMm, depthMm)` and appended to `shapes[shape_index].furnitureItems`.
5. `DatabaseHelper.saveProject(name, shapes, roomObjects, wallAngles, wallDrawnLengths)` creates a **new** local project. `saveProject` ignores its `roomObjects` argument and stores `shape.roomObjects` and `shape.furnitureItems` per shape. It also stores the given angle/length lists under every shape.
6. Green SnackBar "Project restored to device", then `Navigator.pop` back to Home. The project then appears in Home → "My Projects" (local list).

**Not round-tripped by the cloud:**
- room `label`, room `heightMm`, `sharedWalls`;
- door `swingFlipped`;
- `RoomObjectType.opening`, which becomes `window`.

The local copy is not linked to the cloud project (9.2.7).

#### 9.2.11 Sharing a project with an invite code

- **Generation** happens server-side when a cloud project is created (upload insert branch, or the unused `POST /projects`). The code is two 4-character slices of `Math.random().toString(36)`, upper-cased. The code does not check uniqueness or that the result is exactly 8 characters.
- **Retrieval:** `GET /projects/:id/invite-code` is **owner-only** (`WHERE id=$1 AND user_id=$2`); otherwise 404 `{"error":"Not found"}`.
- **UI 1:** CollaborationScreen, owned ⋮ "Share invite code" → `_showInviteCode(id, name)` (L196).
  - Failure → red "Could not fetch invite code.".
  - Success → dialog "Invite Code — <name>" with the text "Share this with your collaborators.\nThey tap "Join Project" and enter it.", the code in a 28 pt monospace box, a "Copy code" button and "Close".
  - "Copy code" runs `Clipboard.setData`, closes the dialog and shows the SnackBar "Invite code copied!".
- **UI 2:** SketchScreen top-bar share icon, shown whenever `_cloudProjectId != null` → `_showInviteCodeDialog` (sketch_screen.dart L3959).
  - Dialog "Share Project" with no copy button.
  - For collaborators it always fails with "Could not fetch invite code" because the endpoint is owner-only.
- **Limits and leak:**
  - Codes never expire and cannot be rotated or revoked.
  - The code is also returned to collaborators inside `p.*` from `/projects/shared` and inside `project` from `/sync/download` and `/sync/updates`. This undermines the owner-only endpoint.

#### 9.2.12 Joining a shared project

**Trigger:** AppBar "Join" action or the empty-state "Join a project" button → `_showJoinDialog()` (L124).

1. Dialog "Join Project": the hint "Enter the 8-character invite code\nshared by the project owner.", a TextField (upper-case capitalization, monospace, letter spacing 4, `maxLength: 8`, hint `ABCD1234`), and Cancel/Join buttons.
2. A null result or a length other than 8 after trimming is **silently ignored**.
3. `ApiService.joinProject(code)` → `POST /projects/join {"invite_code"}`. Server (projects.js L69):
   - missing → 400 `{"error":"Invite code required"}`;
   - `invite_code.toUpperCase().trim()` is looked up with owner email; not found → 404 `{"error":"Invalid invite code"}`;
   - caller is the owner → 400 `{"error":"You already own this project"}`;
   - an existing `accepted` row → 409 `{"error":"Already a collaborator"}`;
   - an existing non-accepted row → `UPDATE … SET status='accepted', joined_at=NOW()`;
   - no row → `INSERT (project_id, user_id, role='editor', status='accepted')`, with `can_edit` defaulting to FALSE;
   - success → 200 `{"message":"Joined successfully","project":{"id","name","owner_email","updated_at"}}`.
4. Client:
   - Any `error` → red SnackBar with that text.
   - Success → green "Joined "<name>" successfully!", then `_loadShared()` and switch to tab 2.
5. Joining grants immediate **read** access: download, updates polling, heartbeat and presence. Uploads stay forbidden until the owner enables `can_edit`.

#### 9.2.13 Viewing collaborators and granting edit access

**Trigger:** owned ⋮ "View collaborators" → `_showCollaborators(id, name)` (L264).

1. `ApiService.getCollaborators(id)` → `GET /projects/:id/collaborators`.
   - Owner only; otherwise 403, which the client turns into `[]`.
   - Returns every collaborator row (all statuses) as `{email, role, status, joined_at, can_edit}`, ordered by `joined_at ASC`.
2. Dialog "Collaborators — <name>":
   - Empty → "No one has joined yet.".
   - Otherwise the hint "Toggle "Can Edit" to let a collaborator\nmake and sync changes." and one row per person:
     - leading icon `Icons.edit` (green) or `Icons.visibility`;
     - the email;
     - the subtitle "Can edit & sync" or "View only";
     - a trailing `Switch`.
3. Switch change → `ApiService.setEditAccess(id, email, val)` → `PATCH /projects/:id/edit-access {"email","can_edit"}`. Server (L170):
   - either field undefined → 400;
   - caller not owner → 403;
   - email unknown → 404 `{"error":"User not found"}`;
   - otherwise `UPDATE project_collaborators SET can_edit=$1 WHERE project_id=$2 AND user_id=$3` → `{"ok":true}`, even if that user is not a collaborator (0 rows).
4. HTTP 200 → the row is updated in the dialog through `setDialogState`. Otherwise the SnackBar "Failed to update access".
5. The UI does not show `role`, `status` or `joined_at`. There is no "remove collaborator" action and no matching endpoint.

The collaborator's client only learns about a permission change after refreshing the Shared tab. An already-open live session keeps the `canEdit` value it was opened with.

#### 9.2.14 Leaving a shared project

**Trigger:** shared ⋮ "Leave project" → `_leaveProject(id, name)` (L366).

1. Confirmation dialog "Leave "<name>"?" / "You will lose access to this shared project." with Cancel and a red "Leave".
2. `ApiService.leaveProject(id)` → `DELETE /projects/:id/leave` → `DELETE FROM project_collaborators WHERE project_id=$1 AND user_id=$2`. The server always answers 200 `{"message":"Left project"}`.
3. HTTP 200 → "Left project" and reload of the Shared tab. Otherwise "Failed".

#### 9.2.15 Live collaboration ("Open live")

**Triggers:** owned ⋮ "Open live" (always `canEdit: true`), or shared ⋮ "Open live (auto-sync)" (`canEdit` = the `can_edit` value from the last `/projects/shared` load) → `_openLive(id, name, canEdit:)` (L90):
- download;
- `_parseProjectData`;
- `lastUpdatedAt = data['project']['updated_at'] ?? ''`;
- push `_LiveCollabWrapper(cloudProjectId, projectName, initialShapes, initialWallAngles, initialWallLengths, lastKnownUpdatedAt, canEdit)`.

**Wrapper (`_LiveCollabWrapperState`):**

- **`initState` (L798):**
  - Copies the initial data.
  - Starts `Timer.periodic(10 s, _poll)`. The first poll runs after 10 s.
  - If `canEdit`, subscribes to `SyncService.uploadSuccessStream` and sets `_lastUpdatedAt = event['updated_at']`, so the user's own upload is not treated as a remote change. The event's project ids are not checked.
- **`_poll()` (L824):**
  1. Guard `_syncing`.
  2. `ApiService.pollForUpdates(id, _lastUpdatedAt)` → `GET /sync/updates/:id?since=<URI-encoded ISO>`.
     - The server runs the same access check as download (404 `{"error":"Access denied"}`).
     - If `since` is present and `projects.updated_at <= since` (compared as JS Date milliseconds) → `{"updated":false}`, which the client maps to `null` (nothing happens).
     - Otherwise it returns `{"updated":true, project, shapes, roomObjects, furnitureItems}`.
  3. Client:
     - `_lastUpdatedAt = project.updated_at`.
     - Rebuilds shapes, room objects and furniture. This repeats `_parseProjectData` inline, without the flat list.
     - Takes angles and lengths from the first shape.
     - `setState` with a **new `UniqueKey`** for the `SketchScreen`, so the sketch is fully remounted.
     - SnackBar "Project updated" (2 s, 0xFF004488).
- **`build` (L932):** `Stack` containing:
  - `SketchScreen(key: _sketchKey, bleManager: null, initialShapes, initialWallAngles, initialWallLengths, cloudProjectId, canEdit)` (no BLE in live mode);
  - a badge `Positioned(top: 56, right: 8)`:
    - `canEdit`: edit icon and "Edit mode · live" (text 0xFF88FF00 on 0xFF1A3A00);
    - otherwise: eye icon and "View only · live" (0xFF00AA44 on 0xFF004422);
    - after the first remote update: "… · Ns ago" or "… · Nm ago" (`_timeAgo`).

    The label is computed only when the wrapper rebuilds, so it shows "0s ago" until the next update.
- **`dispose`:** cancels the timer and the subscription.

**Behaviour inside `SketchScreen` in live mode:**

- `cloudProjectId` → `_cloudProjectId` is set and `_startHeartbeat()` runs after the first frame.
- `canEdit == false` only makes `_queueAutoSync` return early. Drawing is **not** disabled; local edits are never uploaded and are wiped by the next remote update. "Backup to Cloud" is still enabled and gets 403, which blocks the queue (9.5).
- `canEdit == true`:
  - The first edit saves a local `'Auto Save'` project and queues an upload carrying `cloud_project_id`.
  - `_lastCloudUpdatedAt` is not passed in and starts `null`, so the first upload after every (re)mount skips conflict detection.
  - Every remote update remounts the sketch. This discards unsynced edits, the undo history and the local id, so the next edit creates yet another `'Auto Save'` row.
  - In practice, concurrent editors overwrite each other (last writer wins).

#### 9.2.16 Presence: heartbeat and active-collaborator avatars

**Start:** `SketchScreen._startHeartbeat()` (L4018) runs when the sketch was opened with `cloudProjectId`, or after any upload-success event. It does nothing if already running. It calls `_sendHeartbeat()` immediately and then every **30 s**.

`_sendHeartbeat()` (L4026):
1. `ApiService.sendHeartbeat(id)` → `POST /sync/heartbeat {"project_id"}`. The server checks access (owner or accepted collaborator, else 404) and then runs `INSERT INTO project_presence (project_id, user_id, last_seen_at) VALUES ($1,$2,NOW()) ON CONFLICT (project_id, user_id) DO UPDATE SET last_seen_at = NOW()` → `{"ok":true}`. Errors are swallowed.
2. `ApiService.getActiveCollaborators(id)` → `GET /sync/active-collaborators/:id`. The server returns `[{email, last_seen_at}]` for **other** users with `last_seen_at > NOW() - INTERVAL '2 minutes'`, newest first.
3. `_activeCollaborators` is updated.

`_buildPresenceAvatars()` (L4039) shows up to 4 `CircleAvatar`s (radius 10) in the sketch top bar:
- each shows the upper-cased first letter of the email and has the email as tooltip;
- the colour is one of 5 (`0xFF00AAFF`, `0xFFFF6644`, `0xFF44BB66`, `0xFFAA44FF`, `0xFFFFAA00`), chosen by `email.hashCode.abs() % 5`.

The timer is cancelled in `dispose`. Presence rows are never deleted; a user simply drops off other users' lists within 2 minutes of their last heartbeat (up to three missed heartbeats are tolerated).

#### 9.2.17 Deleting projects and other removals

- **Inside a project:** deleted rooms, objects and furniture disappear from the cloud because every upload replaces all child rows.
- **Whole project:** deletion is not propagated.
  - Local delete (`ProjectListScreen` → `DatabaseHelper.deleteProject`) removes the local rows and the project's `pending_uploads`. The cloud copy stays.
  - `DELETE /projects/:id` exists but no `ApiService` method calls it. It would fail with 500 when the project has `furniture_items` (FK without `ON DELETE CASCADE`, migration 005) and possibly other children (base-schema cascades are unknown). It answers 200 even when nothing was deleted.
- **Membership:** collaborators can only remove themselves (`/leave`). Owners cannot kick anyone or revoke read access.
- **Presence:** rows are never cleaned up. **Conflict queue rows:** removed only when the local project is deleted.

#### 9.2.18 Legacy cloud restore screen (`CloudProjectsScreen`)

`code/lib/database/cloud_projects_screen.dart` is an older single-list restore screen (`GET /projects`, with a download button per project). **No code navigates to it.** HomeScreen's "Restore from Cloud" opens `CollaborationScreen` instead.

Its restore path is weaker than the collaboration screen's:
- room objects are not attached to shapes, and `saveProject` ignores the flat list, so doors and windows are lost;
- furniture is not parsed at all.

---

### 9.3 File reference

#### `code/smartmeasure-backend/package.json` — 24 lines

- **Purpose:** npm manifest of the backend: name, scripts and dependencies.
- **Depends on:** the packages below. Resolved versions come from `package-lock.json` (`lockfileVersion: 3`).

  | Package | Declared | Resolved | Used for |
  |---|---|---|---|
  | `bcryptjs` | ^3.0.3 | 3.0.3 | Password hashing in `routes/auth.js` (pure JS; v3 emits `$2b$` hashes) |
  | `cors` | ^2.8.6 | 2.8.6 | `app.use(cors())` |
  | `dotenv` | ^17.4.2 | 17.4.2 | Loads `.env` (app.js, db.js) |
  | `express` | ^5.2.1 | 5.2.1 | HTTP framework (bundles router 2.2.0, body-parser 2.2.2) |
  | `jsonwebtoken` | ^9.0.3 | 9.0.3 | `jwt.sign` / `jwt.verify` |
  | `pg` | ^8.20.0 | 8.20.0 | PostgreSQL `Pool` |
  | `nodemon` (dev) | ^3.1.14 | 3.1.14 | `npm run dev` auto-reload |

- **Declarations:**
  - `"name": "smartmeasure-backend"`, `"version": "1.0.0"`, `"license": "ISC"`.
  - `"main": "index.js"`.
  - `scripts.start = "node src/app.js"`, `scripts.dev = "nodemon src/app.js"`.
  - `description`, `author` and `keywords` are empty.
- **Notes and issues:**
  - `main` points to a non-existent `index.js` (harmless).
  - There is no `engines` field (Node version unspecified) and no `test`, `lint` or `migrate` script.
  - `node_modules/` exists locally but is git-ignored and untracked. `package-lock.json` is committed.

#### `code/smartmeasure-backend/src/app.js` — 29 lines

- **Purpose:** Express entry point. Loads env, installs global middleware, mounts routers and starts the HTTP server.
- **Depends on:** `express`, `cors`, `dotenv`, `./routes/auth`, `./routes/projects`, `./routes/sync`.
- **Declarations:**

  | Line | Declaration | Behaviour |
  |---|---|---|
  | L1–3 | requires, then `require('dotenv').config()` | Loads env. |
  | L5–7 | `authRoutes`, `projectRoutes`, `syncRoutes` | Requiring them also creates the DB pool via db.js. |
  | L9 | `const app = express()` | |
  | L12 | `app.use(cors())` | Comment says "allows Flutter app to talk to this server"; a native app does not need CORS. |
  | L13 | `app.use(express.json())` | Default 100 kb limit. |
  | L16–18 | `app.use('/auth', authRoutes)`, `app.use('/projects', projectRoutes)`, `app.use('/sync', syncRoutes)` | Mounts. |
  | L22 | `GET /health` | `res.json({ status: 'OK', message: 'SmartMeasure backend running' })`. No auth, no DB check. |
  | L26 | `PORT` | `process.env.PORT`, otherwise `3000`. |
  | L27 | `app.listen(PORT, '0.0.0.0', cb)` | Logs `Server running on port ${PORT}`. |

- **Key logic:** order matters only in that `cors` and `json` run before the routers. Auth is applied inside the `projects` and `sync` routers, not here.
- **State and data:** none.
- **Connections:** started by the npm scripts. The Flutter `ApiService.baseUrl` points at this server on port 3000.
- **Notes and issues:**
  - No error-handling middleware and no 404 handler. Express 5 defaults produce HTML errors with stack traces unless `NODE_ENV=production` (9.2.1).
  - The JSON limit is not raised, although whole-project snapshots are posted.
  - `X-Powered-By: Express` is left enabled. There are no security headers (no `helmet`), no request logging and no rate limiting.
  - `app` is not exported, so it cannot be tested with supertest without changes.
  - No graceful shutdown (`pool.end()`).

#### `code/smartmeasure-backend/src/db/db.js` — 32 lines

- **Purpose:** creates and exports the single shared `pg.Pool` used by all routes.
- **Depends on:** `pg` (`Pool`), `dotenv`.
- **Declarations:**
  - **`pool` (L7).** The configuration depends on `process.env.DATABASE_URL` (L8):
    - If set: `{ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false } }` (comment: "required by Railway").
    - Otherwise (L13–19): `{ host: DB_HOST, port: DB_PORT, database: DB_NAME, user: DB_USER, password: DB_PASSWORD }` with **no SSL**.
  - **Startup probe (L23):** `pool.connect((err, client, release) => …)` logs `Database connection failed: <err.message>` or `Connected to PostgreSQL database`, then `release()`s.
  - **Export (L32):** `module.exports = pool`.
- **Key logic:** no pool tuning, so pg defaults apply: `max: 10` clients, `idleTimeoutMillis: 10000`, no connection timeout (waits forever). In discrete mode, unset `DB_*` values fall back to node-postgres' own `PGHOST`/`PGUSER`/`PGPASSWORD`/`PGDATABASE`/`PGPORT` env vars, then to `localhost:5432` and the OS user name.
- **Connections:** required by `routes/auth.js`, `routes/projects.js` and `routes/sync.js`.
- **Notes and issues:**
  - `rejectUnauthorized: false` disables server-certificate verification, so the database link is open to MITM.
  - No `pool.on('error', …)` listener. An error on an idle client (database restart, network drop) is emitted as an unhandled `'error'` event, which can crash the Node process.
  - Startup failure is only logged.
  - The comment says Railway. The unmerged `origin/backend-host-azure` branch adds `ssl` to the discrete mode for Azure.

#### `code/smartmeasure-backend/src/middleware/auth_middleware.js` — 33 lines

- **Purpose:** Express middleware that requires a valid JWT and exposes its payload as `req.user`.
- **Depends on:** `jsonwebtoken`; `process.env.JWT_SECRET`.
- **Declarations:** `function authMiddleware(req, res, next)` (L5); exported at L33.
- **Key logic:**
  1. `const authHeader = req.headers['authorization']` (L8).
  2. If it is missing or does not start with exactly `'Bearer '` (case-sensitive, one space) → 401 `{"error":"No token provided. Please login."}` (L11).
  3. `token = authHeader.split(' ')[1]` (L15).
  4. `jwt.verify(token, process.env.JWT_SECRET)` (L19). For a string secret, jsonwebtoken 9 allows only HS256/HS384/HS512 and checks `exp`.
  5. Success: `req.user = decoded` (`{ userId, email, iat, exp }`), then `next()`.
  6. Any error (bad signature, expired, malformed, `JWT_SECRET` undefined) → 401 `{"error":"Invalid or expired token. Please login again."}` (L29).
- **Connections:** `router.use(authMiddleware)` in `projects.js` L8 and `sync.js` L8. Routes then read `req.user.userId`.
- **Notes and issues:**
  - No revocation or deny-list.
  - Expired and invalid tokens produce the same message.
  - The `email` claim is not re-checked against the database: a deleted user's token stays valid until it expires.

#### `code/smartmeasure-backend/src/routes/auth.js` — 94 lines

- **Purpose:** public registration and login.
- **Depends on:** `express.Router`, `bcryptjs`, `jsonwebtoken`, `../db/db` (pool); env `JWT_SECRET`.
- **Declarations:**
  - **`router` (L6).**
  - **`POST /auth/register` (L9):**
    1. Reads `{ email, password }` from `req.body`.
    2. Missing either → 400 `{"error":"Email and password are required"}`.
    3. `password.length < 6` → 400 `{"error":"Password must be at least 6 characters"}`.
    4. `SELECT id FROM users WHERE email = $1` returns a row → 409 `{"error":"Email already registered"}`.
    5. `bcrypt.hash(password, 10)`.
    6. `INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email`.
    7. 201 `{"message":"Registration successful","user":{"id","email"}}`.
    8. catch → `console.error`, 500 `{"error":"Server error"}`.
  - **`POST /auth/login` (L50):**
    1. Missing field → 400 (same message).
    2. `SELECT * FROM users WHERE email = $1`. No row → 401 `{"error":"Invalid email or password"}`.
    3. `bcrypt.compare(password, user.password_hash)` false → the same 401.
    4. `jwt.sign({ userId: user.id, email: user.email }, process.env.JWT_SECRET, { expiresIn: '7d' })`.
    5. 200 `{"message":"Login successful","token","user":{"id","email"}}`.
    6. catch → 500 `{"error":"Server error"}`.
  - **Export (L94):** `module.exports = router`.
- **Key logic:** the bcrypt cost factor is **10**. JWT algorithm is the default HS256 and the expiry is 7 days.
- **State and data:** table `users` (`id`, `email`, `password_hash`; see 9.4.4).
- **Connections:** `ApiService.register` / `ApiService.login`. `HomeScreen` decodes the `email` claim.
- **Notes and issues:**
  - No email-format validation or normalisation (case or whitespace on the server). Lookups are exact, so `A@x.com` and `a@x.com` are different accounts unless the database enforces otherwise (unknown).
  - The existence check is not atomic. Two concurrent registrations rely on a DB UNIQUE constraint, if one exists, and would then get 500.
  - A non-string `password` skips the length check and makes bcrypt throw (500).
  - Without a JSON body, `req.body` is `undefined` and destructuring throws (500 instead of 400).
  - Register reveals whether an email exists (409). There is no rate limiting or lockout.
  - A missing `JWT_SECRET` makes every login return 500.

#### `code/smartmeasure-backend/src/routes/projects.js` — 217 lines

- **Purpose:** project listing and creation, plus all sharing and collaboration management.
- **Depends on:** `express.Router`, `../db/db`, `../middleware/auth_middleware`.
- **Declarations** (all behind `router.use(authMiddleware)` at L8; `req.user.userId` is the caller):

  | Line | Route | Behaviour |
  |---|---|---|
  | L11 | `GET /projects` | `SELECT * FROM projects WHERE user_id = $1 ORDER BY updated_at DESC` → JSON array of full project rows (includes `invite_code`, `local_id`, `user_id`). 500 `{"error":"Server error"}`. |
  | L25 | `POST /projects` | Body `{name, local_id}`. No `name` → 400 `{"error":"Project name is required"}`. Generates an invite code (L33–34), then `INSERT INTO projects (user_id, name, local_id, invite_code) VALUES ($1,$2,$3,$4) RETURNING *` → 201 row. Does **not** set `updated_at`. **Not used by the app.** |
  | L50 | `GET /projects/shared` | `SELECT p.*, pc.role, pc.can_edit, u.email AS owner_email FROM project_collaborators pc JOIN projects p ON p.id = pc.project_id JOIN users u ON u.id = p.user_id WHERE pc.user_id = $1 AND pc.status = 'accepted' ORDER BY p.updated_at DESC` → array. |
  | L69 | `POST /projects/join` | Body `{invite_code}`. Full flow in 9.2.12. SQL: `SELECT p.*, u.email AS owner_email FROM projects p JOIN users u ON u.id = p.user_id WHERE p.invite_code = $1`, then `SELECT id, status FROM project_collaborators WHERE project_id=$1 AND user_id=$2`, then `UPDATE project_collaborators SET status='accepted', joined_at=NOW() …` or `INSERT INTO project_collaborators (project_id, user_id, role, status) VALUES ($1,$2,'editor','accepted')`. 200 `{"message":"Joined successfully","project":{"id","name","owner_email","updated_at"}}`. |
  | L123 | `GET /projects/:id/invite-code` | `SELECT invite_code FROM projects WHERE id = $1 AND user_id = $2`. None → 404 `{"error":"Not found"}`, else `{"invite_code"}`. The catch does not log. |
  | L137 | `GET /projects/:id/collaborators` | Owner check `SELECT id FROM projects WHERE id=$1 AND user_id=$2` (fails → 403 `{"error":"Access denied"}`), then `SELECT u.email, pc.role, pc.status, pc.joined_at, pc.can_edit FROM project_collaborators pc JOIN users u ON u.id = pc.user_id WHERE pc.project_id = $1 ORDER BY pc.joined_at ASC` (all statuses). The catch does not log. |
  | L157 | `DELETE /projects/:id/leave` | `DELETE FROM project_collaborators WHERE project_id=$1 AND user_id=$2`. Always 200 `{"message":"Left project"}`. The catch does not log. |
  | L170 | `PATCH /projects/:id/edit-access` | Body `{email, can_edit}`. Either `=== undefined` → 400 `{"error":"email and can_edit required"}`. Owner check → 403 `{"error":"Access denied"}`. `SELECT id FROM users WHERE email=$1` empty → 404 `{"error":"User not found"}`. `UPDATE project_collaborators SET can_edit=$1 WHERE project_id=$2 AND user_id=$3` → `{"ok":true}`. |
  | L204 | `DELETE /projects/:id` | `DELETE FROM projects WHERE id=$1 AND user_id=$2`. Always 200 `{"message":"Project deleted successfully"}`; 500 on FK violation. **Not used by the app.** |
  | L217 | `module.exports = router` | |

- **Key logic:**
  - **Invite code** (L33–34, duplicated in sync.js L93–94): `Math.random().toString(36).substring(2, 6).toUpperCase()` + the same again. That gives 8 characters from `[0-9A-Z]` in practice. It is not a CSPRNG, and uniqueness and length are not verified.
  - **Join comparison:** `project.user_id === req.user.userId` works because both are JS numbers (INTEGER ids).
  - **Route order:** `/shared` and `/join` are declared before the `/:id/...` routes. No conflict arises because the segment counts differ.
- **State and data:** tables `projects`, `project_collaborators`, `users`.
- **Connections:** `ApiService.getCloudProjects`, `getSharedProjects`, `joinProject`, `getInviteCode`, `getCollaborators`, `leaveProject` and `setEditAccess`. Unused: `POST /` and `DELETE /:id`.
- **Notes and issues:**
  - **`role`:** always `'editor'` and never consulted. The actual gate is `can_edit` (FALSE by default), so a fresh "editor" cannot edit.
  - **Invite-code leak:** `invite_code` reaches collaborators via `p.*` in `/shared`.
  - **Join edge cases:**
    - A non-string `invite_code` → `toUpperCase` TypeError → 500.
    - The re-accept UPDATE branch can only be reached by rows with a status other than `accepted`, which no code creates.
  - **Response and error edge cases:**
    - Non-numeric `:id` → PostgreSQL cast error → 500.
    - `edit-access` returns `{"ok":true}` for a registered email that is not a collaborator (0 rows updated). It also lets an owner probe whether an email is registered (404 vs 200).
    - `can_edit` is passed straight to PostgreSQL, so `'yes'`/`'no'` strings are accepted and other strings → 500.
  - **Missing features:** no endpoint to remove a collaborator, rotate the invite code or rename a project.

#### `code/smartmeasure-backend/src/routes/sync.js` — 454 lines

- **Purpose:** whole-project upload and download, change polling and presence.
- **Depends on:** `express.Router`, `../db/db`, `../middleware/auth_middleware`.
- **Declarations** (all behind `router.use(authMiddleware)` at L8):
  - **`POST /sync/upload` (L12).** Transactional snapshot replace; full algorithm in 9.2.6.
    - Body: `{project:{name, local_id, cloud_project_id?}, shapes[], roomObjects[], furnitureItems?[], last_modified_at?}`.
    - Responses: 200 `{"message":"Project uploaded successfully","cloud_project_id","updated_at"}`; 403 `{"error":"Edit access not granted"}`; 409 `{"conflict":true,"server_updated_at"}`; 500 `{"error":"Upload failed"}`.
  - **`GET /sync/download/:projectId` (L214):**
    1. Access query (L219–232): `SELECT p.* FROM projects p WHERE p.id = $1 AND (p.user_id = $2 OR EXISTS (SELECT 1 FROM project_collaborators pc WHERE pc.project_id = p.id AND pc.user_id = $2 AND pc.status = 'accepted'))`. No row → 404 `{"error":"Project not found or access denied"}`.
    2. `SELECT * FROM shapes WHERE project_id=$1 ORDER BY shape_index ASC`.
    3. Per shape, with shapes processed in parallel (`Promise.all`) and the four queries run one after another:
       - `shape_points … ORDER BY order_index ASC`;
       - `wall_real_mm` (unordered);
       - `wall_angles … ORDER BY order_index ASC`;
       - `wall_lengths … ORDER BY order_index ASC`.
    4. `SELECT * FROM room_objects WHERE project_id=$1` and `SELECT * FROM furniture_items WHERE project_id=$1` (both unordered).
    5. 200 `{project, shapes:[{...shapeRow, points, wall_real_mm, wall_angles, wall_lengths}], roomObjects, furnitureItems}`. catch → 500 `{"error":"Download failed"}`.
  - **`GET /sync/updates/:projectId?since=<ISO>` (L300):**
    - The same access query; failure → 404 `{"error":"Access denied"}`.
    - If `since` and `project.updated_at` are both truthy and `new Date(updated_at).getTime() <= new Date(since).getTime()` → `{"updated":false}`.
    - Otherwise the same data as download, with the four per-shape queries run in parallel → `{"updated":true, project, shapes, roomObjects, furnitureItems}`.
    - catch → `console.error('Updates error:', err)`, 500 `{"error":"Failed to check updates"}`.
  - **`POST /sync/heartbeat` (L371):**
    - Body `{project_id}`. Missing or falsy → 400 `{"error":"project_id required"}`.
    - Access check (`SELECT 1 …`) fails → 404 `{"error":"Access denied"}`.
    - Upsert `INSERT INTO project_presence (project_id, user_id, last_seen_at) VALUES ($1,$2,NOW()) ON CONFLICT (project_id, user_id) DO UPDATE SET last_seen_at = NOW()` → `{"ok":true}`.
    - catch → 500 `{"error":"Heartbeat failed"}`. The comment says Flutter calls it every 30 s.
  - **`GET /sync/active-collaborators/:projectId` (L413):**
    - Access check → 404 `{"error":"Access denied"}`.
    - `SELECT u.email, pp.last_seen_at FROM project_presence pp JOIN users u ON u.id = pp.user_id WHERE pp.project_id = $1 AND pp.user_id != $2 AND pp.last_seen_at > NOW() - INTERVAL '2 minutes' ORDER BY pp.last_seen_at DESC` → array.
    - catch → 500 `{"error":"Failed to get active collaborators"}`.
  - **Export (L454):** `module.exports = router`.
- **Key logic:**
  - **Access rule** (repeated verbatim four times): owner, or `project_collaborators` row with `status='accepted'`. Reading needs no `can_edit`; uploading needs owner or `can_edit = true`.
  - **Timestamp comparisons** run in JS (`Date`, millisecond precision). PostgreSQL microseconds are truncated identically on both sides, so the values a client echoes back compare as equal.
  - `projects.updated_at` must parse to a JS `Date` (the code calls `.toISOString()`), so it is a `timestamp`/`timestamptz` column.
- **State and data:** tables `projects`, `shapes`, `shape_points`, `wall_real_mm`, `wall_angles`, `wall_lengths`, `room_objects`, `furniture_items`, `project_collaborators`, `project_presence`, `users`.
- **Connections:** `ApiService.uploadProject` (via `SyncService`), `downloadProject`, `pollForUpdates`, `sendHeartbeat` and `getActiveCollaborators`.
- **Notes and issues:**
  - **Double `client.release()`** in the 403 (L58) and 409 (L68) paths plus `finally` (L208); see 9.2.6.
  - `pool.connect()` (L13) is outside `try`.
  - **Upload rename:** the upload `UPDATE` always overwrites `name`, including with a collaborator's or auto-sync's name.
  - **Upload efficiency:**
    - Redundant queries: the second lookup when found by id, and `projectMeta`.
    - No row lock (`SELECT … FOR UPDATE`): the conflict check runs before the row is locked, so two concurrent writers can both pass it.
    - One INSERT per point or measurement (N+1 round-trips while a pooled client is held).
  - **Missing payload arrays** (`shapes`, `roomObjects` or a shape's sub-array) → 500 rather than 400.
  - **Download/updates output:**
    - The response includes `project.invite_code`, `user_id` and `local_id` for collaborators.
    - `wall_real_mm`, `room_objects` and `furniture_items` are returned in unspecified order.
  - **`since` edge cases:** a `since` that is not parseable as a date (`NaN`) or empty always returns full data.
  - **Updates fan-out:** issues 4×(number of shapes) parallel queries against a 10-client pool (requests queue).
  - **Duplication:**
    - download and updates duplicate the response-building code;
    - the access-check SQL is duplicated four times.
  - **Presence:** no cleanup of `project_presence`.

#### `code/smartmeasure-backend/migrations/003_project_presence.sql` — 13 lines

- **Purpose:** adds presence tracking for the heartbeat feature.
- **Declarations:**
  - L5–10 `CREATE TABLE IF NOT EXISTS project_presence`:
    - `project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE`;
    - `user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE`;
    - `last_seen_at TIMESTAMP NOT NULL DEFAULT NOW()`;
    - `PRIMARY KEY (project_id, user_id)`.
  - L12–13 `CREATE INDEX IF NOT EXISTS idx_presence_project_seen ON project_presence (project_id, last_seen_at DESC)`.
- **Key logic:** the PK is the target of `ON CONFLICT (project_id, user_id)` in `/sync/heartbeat`. The index serves the 2-minute window query.
- **Connections:** `sync.js` heartbeat and active-collaborators routes.
- **Notes and issues:**
  - Header comment: "Run this once against your Railway PostgreSQL database: `psql $DATABASE_URL -f migrations/003_project_presence.sql`". There is no migration runner or tracking table; migrations are applied by hand.
  - It proves that `projects.id` and `users.id` are INTEGER-compatible.
  - `TIMESTAMP` has no time zone. That is consistent inside SQL, but differs from the time-zone semantics of other columns, which are unknown.

#### `code/smartmeasure-backend/migrations/004_room_objects_shape_index.sql` — 7 lines

- **Purpose:** multi-room support for doors and windows.
- **Declarations:** L6–7 `ALTER TABLE room_objects ADD COLUMN IF NOT EXISTS shape_index INTEGER NOT NULL DEFAULT 0;`.
- **Key logic:** existing rows get room 0. Upload writes `obj.shape_index ?? 0`. Clients map `shape_index` to the n-th shape in the downloaded array (no FK, logical link only).
- **Connections:** `sync.js` upload, download and updates; `_parseProjectData` / `_poll` in `collaboration_screen.dart`.
- **Notes and issues:** implies that `room_objects` was created by a missing base migration (001/002). The header comment again references Railway and `psql $DATABASE_URL`.

#### `code/smartmeasure-backend/migrations/005_furniture_items.sql` — 13 lines

- **Purpose:** cloud storage for furniture.
- **Declarations:** L2–13 `CREATE TABLE IF NOT EXISTS furniture_items` with:
  - `id SERIAL PRIMARY KEY`;
  - `project_id INTEGER NOT NULL REFERENCES projects(id)`;
  - `shape_index INTEGER NOT NULL DEFAULT 0`;
  - `furniture_id TEXT NOT NULL`, `type TEXT NOT NULL`;
  - `position_x DOUBLE PRECISION NOT NULL`, `position_y DOUBLE PRECISION NOT NULL`;
  - `rotation_deg DOUBLE PRECISION NOT NULL DEFAULT 0`;
  - `width_mm DOUBLE PRECISION NOT NULL`, `depth_mm DOUBLE PRECISION NOT NULL`.
- **Key logic:**
  - `type` holds the Dart `FurnitureType.name` (e.g. `sofa`, `doubleBed`).
  - `position_x/y` are sketch world coordinates of the item centre.
  - `rotation_deg` is clockwise degrees.
- **Connections:** `sync.js` upload, download and updates; client parsing in `collaboration_screen.dart`.
- **Notes and issues:**
  - The FK has **no `ON DELETE CASCADE`**, so `DELETE /projects/:id` fails for projects with furniture. Upload deletes furniture rows explicitly, so it is unaffected.
  - No index on `project_id`.
  - Unlike the other migrations, there is no header comment about how to run it.

#### `code/smartmeasure-backend/migrations/006_can_edit.sql` — 4 lines

- **Purpose:** per-collaborator write permission.
- **Declarations:** L3–4 `ALTER TABLE project_collaborators ADD COLUMN IF NOT EXISTS can_edit BOOLEAN NOT NULL DEFAULT FALSE;`.
- **Key logic:** new and existing collaborators are view-only until the owner flips the switch (`PATCH /projects/:id/edit-access`). It is enforced only in `POST /sync/upload`.
- **Connections:** `projects.js` (`/shared`, `/collaborators`, `/edit-access`), `sync.js` upload; Flutter `CollaborationScreen` switch and the `canEdit` flag passed into live mode.
- **Notes and issues:** implies that `project_collaborators` comes from the missing base migrations.

#### `code/smartmeasure-backend/.gitignore` — 2 lines

- **Purpose:** keeps dependencies and secrets out of git.
- **Declarations:** `node_modules/` and `.env`. The file has CRLF line endings and no trailing newline.
- **Notes and issues:**
  - Confirmed that no `.env` is tracked and none exists in the working tree.
  - There is no `.env.example` either, so the required variables are documented only in 9.4.6.

#### `code/smartmeasure-backend/git` — 0 lines

- **Purpose:** none. It is a **zero-byte file named `git`** that is tracked in the repository.
- **Origin:** it was added in commit 7c87089, "3D room view update" (2026-05-14), together with unrelated 3D-view files. It is almost certainly an accident, such as a mistyped shell command or redirection that created an empty file called `git`.
- **Connections:** none. Nothing references it and it does not affect the build or runtime.
- **Notes and issues:** safe to delete.

#### `code/lib/services/api_service.dart` — 272 lines

- **Purpose:** the single HTTP client layer between the Flutter app and the backend. It also stores the JWT.
- **Depends on:**
  - `dart:convert` (`jsonEncode` / `jsonDecode`);
  - `package:flutter/foundation.dart` (`debugPrint`);
  - `package:http/http.dart` as `http` (constraint ^1.2.0, resolved 1.6.0);
  - `package:flutter_secure_storage` (^9.0.0, resolved 9.2.4).
- **Declarations:** `class ApiService` (L8). It is not meant to be instantiated; everything is static.

  | Line | Member | Endpoint | Request | Returns / error handling |
  |---|---|---|---|---|
  | L9 | `static const String baseUrl = 'http://13.214.196.211:3000'` | – | – | Hard-coded host and port, plain HTTP. |
  | L11 | `static const _storage = FlutterSecureStorage()` | – | – | Default options (Android Keystore-backed encryption). |
  | L15 | `saveToken(String token)` | – | – | Writes key `'jwt_token'`. |
  | L19 | `getToken() → String?` | – | – | Reads `'jwt_token'`. |
  | L23 | `deleteToken()` | – | – | Deletes `'jwt_token'`. |
  | L27 | `isLoggedIn() → bool` | – | – | `getToken() != null`. No expiry check. |
  | L34 | `_authHeaders() → Map<String,String>` | – | – | `{'Content-Type': 'application/json', 'Authorization': 'Bearer <token>'}`; the Authorization header is omitted when there is no token. |
  | L44 | `register(email, password) → Map` | `POST /auth/register` | `{"email","password"}`, Content-Type only | Decoded body for **any** status. Exception or non-JSON → `{'error': 'Cannot connect to server. Check your connection.'}`. |
  | L58 | `login(email, password) → Map` | `POST /auth/login` | same | If `data['token'] != null`, then `saveToken`. Returns decoded body. Same catch message. |
  | L77 | `logout()` | – | – | `deleteToken()` only. |
  | L83 | `uploadProject(Map projectData, {String? lastModifiedAt}) → Map` | `POST /sync/upload` | `{...projectData, 'last_modified_at'?}` with auth headers | 409 → `{'conflict': true, 'server_updated_at': …}`. Any other status → decoded body (success map or `{error}`). Exception → `debugPrint('UPLOAD EXCEPTION: …')`, `debugPrint('STACK: …')`, `{'error': 'Upload failed: <e>'}`. |
  | L111 | `downloadProject(int cloudProjectId) → Map?` | `GET /sync/download/:id` | auth | 200 → decoded map; otherwise `null`; exception → `null`. |
  | L128 | `getCloudProjects() → List` | `GET /projects` | auth | 200 → decoded list; otherwise `[]`; exception → `[]`. |
  | L144 | `pollForUpdates(int cloudProjectId, String since) → Map?` | `GET /sync/updates/:id?since=<Uri.encodeComponent(since)>` | auth | Non-200 → `null`. `updated == false` → `null`. Otherwise the full map. Exception → `null`. |
  | L160 | `joinProject(String inviteCode) → Map` | `POST /projects/join` | `{"invite_code"}` | Decoded body for any status. Exception → `{'error': 'Cannot connect to server.'}`. |
  | L174 | `getSharedProjects() → List` | `GET /projects/shared` | auth | 200 → list, else `[]`. |
  | L188 | `getInviteCode(int id) → String?` | `GET /projects/:id/invite-code` | auth | 200 → `invite_code`, else `null`. |
  | L204 | `getCollaborators(int id) → List` | `GET /projects/:id/collaborators` | auth | 200 → list, else `[]`. |
  | L218 | `setEditAccess(int id, String email, bool canEdit) → bool` | `PATCH /projects/:id/edit-access` | `{"email","can_edit"}` | `true` iff status 200. |
  | L233 | `leaveProject(int id) → bool` | `DELETE /projects/:id/leave` | auth | `true` iff 200. |
  | L248 | `sendHeartbeat(int id)` | `POST /sync/heartbeat` | `{"project_id"}` | Fire-and-forget. Response ignored, errors swallowed. |
  | L259 | `getActiveCollaborators(int id) → List` | `GET /sync/active-collaborators/:id` | auth | 200 → list, else `[]`. |

- **Key logic:** every call fetches the token from secure storage again. JSON maps come back as `dynamic` and are implicitly cast to `Map<String, dynamic>` / `List<dynamic>`.
- **State and data:** the only persisted state is the secure-storage key `jwt_token`.
- **Connections:**
  - `main.dart` (`isLoggedIn`);
  - `home_screen.dart` (`getToken`, `logout`);
  - `login_screen.dart` (`login`, `register`);
  - `sync_service.dart` (`uploadProject`);
  - `sketch_screen.dart` (`isLoggedIn` L614/L647, `getInviteCode` L3962, `sendHeartbeat` L4029, `getActiveCollaborators` L4030);
  - `collaboration_screen.dart` (most methods);
  - `cloud_projects_screen.dart` (`getCloudProjects`, `downloadProject`).
- **Notes and issues:**
  - Cleartext HTTP to a hard-coded IP. Changing the server needs a new build; there is no flavour or env configuration. The main `AndroidManifest.xml` sets `android:usesCleartextTraffic="true"` to make this work.
  - No request timeouts, so a hung connection blocks callers (and `SyncService`) until the OS TCP timeout.
  - No 401 handling or token refresh.
  - List and boolean methods collapse every error into `[]`, `null` or `false`, so the UI cannot tell "empty" from "failed".
  - `register` and `login` misreport HTML error pages (e.g. 413/400 from Express) as "Cannot connect to server".
  - `uploadProject`'s `lastModifiedAt` parameter is never passed by any caller (`SyncService` embeds the field in the payload).
  - No methods exist for `POST /projects`, `DELETE /projects/:id` or `GET /health`.

#### `code/lib/services/sync_service.dart` — 125 lines

- **Purpose:** offline-first upload queue. It persists snapshots in SQLite, uploads them in FIFO order, retries on connectivity changes and every 60 s, and broadcasts status and upload results.
- **Depends on:**
  - `dart:async` (`StreamController`, `Timer`, `StreamSubscription`);
  - `dart:convert`;
  - `package:connectivity_plus` (^6.0.3, resolved 6.1.5; `onConnectivityChanged` emits `List<ConnectivityResult>`);
  - `package:flutter/foundation.dart` (**unused import**);
  - `../database/database_helper.dart`: `queueUpload` (L526), `getNextPendingUpload` (L540), `deletePendingUpload` (L553), `markUploadConflict` (L559), `markUploadAttempted` (L570);
  - `api_service.dart`.
- **Declarations:**
  - **`enum SyncStatus { idle, syncing, offline, conflict }` (L8).**
  - **`class SyncService` (L10).** Singleton: `static final SyncService instance = SyncService._init()` (L11) with private constructor `SyncService._init()` (L12).

    Fields:

    | Line | Field | Type | Meaning |
    |---|---|---|---|
    | L14 | `_status` | `SyncStatus` | Current status, initially `idle`. Public getter `status` (L15). |
    | L18 | `_statusController` | broadcast `StreamController<SyncStatus>` | Public `statusStream` (L19). |
    | L22 | `_uploadSuccessController` | broadcast `StreamController<Map<String,dynamic>>` | Public `uploadSuccessStream` (L24). Events are `{local_project_id, cloud_project_id, updated_at}`. |
    | L27 | `_connectivitySub` | `StreamSubscription?` | Connectivity listener. |
    | L28 | `_retryTimer` | `Timer?` | 60-s periodic retry. |
    | L29 | `_isProcessing` | `bool` | Re-entrancy guard. |

    Methods:
    - **`void init()` (L32):** subscribes to connectivity. Any result other than `none` → `processQueue()`; otherwise `_setStatus(offline)`. Starts `Timer.periodic(Duration(seconds: 60), (_) => processQueue())`. No guard against being called twice.
    - **`void dispose()` (L49):** cancels the subscription and timer and closes both controllers. **Never called anywhere.**
    - **`Future<void> queueUpload({required int projectId, required Map projectData, String? lastModifiedAt})` (L57):** `jsonEncode({...projectData, if (lastModifiedAt != null) 'last_modified_at': lastModifiedAt})`, then `DatabaseHelper.instance.queueUpload(projectId: projectId, payloadJson: …)`, then `_setStatus(idle)`, then `processQueue()` (not awaited).
    - **`Future<void> processQueue()` (L74):** loop algorithm in 9.2.5. `_isProcessing` is reset in `finally`.
    - **`void _setStatus(SyncStatus s)` (L121):** stores the status and adds it to `statusStream` (even when unchanged).
- **Key logic:**
  - Strict FIFO by `created_at`.
  - Only `status='pending'` rows are picked up. Conflict rows are parked forever. Error rows stay pending and are retried first, which causes head-of-line blocking.
  - No back-off and no maximum attempts. `attempts` / `last_attempt` are written but never read.
- **State and data:**
  - The queue lives in SQLite `pending_uploads` (`id`, `project_id` = local id, `payload` = JSON text of the upload body, `created_at`, `attempts`, `last_attempt`, `status` ∈ `pending`|`conflict`). That table is defined in the database part.
  - In-memory: status and the two streams.
- **Connections:**
  - `main.dart` L46 (`init`);
  - `sketch_screen.dart` (`queueUpload` L638/L721, `statusStream` L219, `uploadSuccessStream` L223, `status` L4082);
  - `collaboration_screen.dart` L810 (`uploadSuccessStream`).
- **Notes and issues:**
  - `offline` is reported for every kind of failure (auth, permission, server bug), not only network loss.
  - Each snapshot carries the `last_modified_at` it was queued with. That causes self-conflicts when several snapshots are queued (9.5).
  - No coalescing, so every edit's full snapshot is uploaded in turn.
  - Logout does not clear the queue.
  - `queueUpload` resets a visible `conflict` state to `idle` without resolving anything.
  - Listeners subscribed by `SketchScreen` are never cancelled (the leak is in `sketch_screen.dart`).

#### `code/lib/screens/login_screen.dart` — 208 lines

- **Purpose:** combined login/registration form with a local-only skip option.
- **Depends on:** `package:flutter/material.dart`, `../services/api_service.dart`, `../screens/home_screen.dart`.
- **Declarations:**
  - **`class LoginScreen extends StatefulWidget` (L7):** `const LoginScreen({super.key})`; `createState` → `_LoginScreenState`.
  - **`class _LoginScreenState` (L14).**

    Fields:
    - `_emailController` (L15), `_passwordController` (L16): `TextEditingController`s.
    - `_isLoading` (L17): bool, initially false.
    - `_isLoginMode` (L18): bool, initially true; true = login, false = register.

    Methods:
    - **`dispose()` (L21):** disposes both controllers.
    - **`Future<void> _submit()` (L27):** the flow in 9.2.3.
    - **`void _showMessage(String)` (L65):** SnackBar with background `0xFF1A2A3A`.
    - **`build` (L75):** see UI below.
- **UI:**
  - `Scaffold`, background `0xFF0D1A27`, centred scrollable column with 32 padding.
  - Icon `Icons.straighten` (80, `0xFF00AAFF`).
  - Title "SmartMeasure Pro" (24, bold, white).
  - Subtitle "Login to your account" or "Create an account" (`0xFF556677`).
  - Email `TextField` (email keyboard, `Icons.email_outlined`, outlined borders `0xFF334466` / focused `0xFF00AAFF`).
  - Password `TextField` (`obscureText`, `Icons.lock_outlined`).
  - Full-width 50-px `ElevatedButton` "Login" or "Register" (`0xFF00AAFF`). It shows a white spinner and is disabled while loading.
  - Toggle `TextButton` "Don't have an account? Register" / "Already have an account? Login".
  - `TextButton` "Skip for now (local only)" → `pushReplacement(HomeScreen)`.
- **Connections:** shown by `main.dart` `_AppStartupState._checkLogin` when there is no token, and by `HomeScreen._logout`. Navigates to `HomeScreen`.
- **Notes and issues:**
  - `_isLoading = false` is set with `setState` **before** the `mounted` check (L50 vs L52). If the screen is left during the request (Skip and Toggle stay enabled), Flutter throws "setState() called after dispose".
  - The password is `trim()`med.
  - No email-format check and no password-length hint; the server enforces ≥6 characters.
  - The registration success message is never shown (auto-login replaces it).
  - No "forgot password".

#### `code/lib/database/cloud_projects_screen.dart` — 189 lines

- **Purpose:** earlier "Cloud Projects" restore list. **Dead code:** no `Navigator` route references `CloudProjectsScreen` anywhere in `code/lib`.
- **Depends on:**
  - `material`;
  - `../services/api_service.dart` (`getCloudProjects`, `downloadProject`);
  - `../database/database_helper.dart` (`saveProject`);
  - `../sketch/room_object.dart`;
  - `../sketch/sketch_model.dart`.
- **Declarations:**
  - **`class CloudProjectsScreen extends StatefulWidget` (L9).**
  - **`class _CloudProjectsScreenState` (L16).**

    Fields:
    - `_projects` (`List<dynamic>`, L17);
    - `_loading` (true, L18);
    - `_restoring` (false, L19).

    Methods:
    - **`initState` (L22):** calls `_loadCloudProjects()`.
    - **`_loadCloudProjects()` (L27):** `ApiService.getCloudProjects()`, then `setState`. There is no `mounted` check.
    - **`_restoreProject(int cloudProjectId, String name)` (L35):**
      1. `_restoring = true`, then `downloadProject`. `null` → red SnackBar "Restore failed. Try again.".
      2. Otherwise it rebuilds `shapes` (`List<dynamic>` of `SketchShape.empty()` with `is_closed`, `points` and `wall_real_mm`).
      3. `wallAngles` / `wallLengths` come from the first shape.
      4. It builds a flat `List<RoomObject>` (`'door'` → door, otherwise window; `ownerShapeId` from `shape_index`) **without attaching it to shapes**.
      5. `DatabaseHelper.saveProject(...)`.
      6. Green SnackBar "Project restored to local storage" (`0xFF00AA44`), then `Navigator.pop`.
    - **`build` (L131):** see UI below.
- **UI:**
  - AppBar "Cloud Projects".
  - Body states: loading spinner; "Restoring project..." with spinner; empty text "No cloud projects found".
  - Otherwise a `ListView` of `ListTile`s: title = `name`; subtitle = raw `updated_at` ISO string (11 pt); leading purple `Icons.cloud`; trailing `IconButton(Icons.download, tooltip 'Restore to device')`.
- **Connections:** none inbound. It would call `GET /projects` and `GET /sync/download/:id`.
- **Notes and issues:**
  - It drops doors and windows, because `saveProject` ignores the `roomObjects` argument and reads `shape.roomObjects`.
  - It ignores `furnitureItems`, and `opening` becomes window.
  - No pull-to-refresh and no error state.
  - The parsing code is a third copy of the logic in `collaboration_screen.dart`.
  - Superseded by `CollaborationScreen` and safe to delete.

#### `code/lib/database/collaboration_screen.dart` — 1001 lines

- **Purpose:** the cloud and collaboration hub. It lists own and shared cloud projects; handles restore, join by code, invite-code display, collaborator management with edit permission, and leaving; and hosts the live-polling wrapper around `SketchScreen`.
- **Depends on:**
  - `dart:async` (`Timer`, `StreamSubscription`);
  - `material`;
  - `flutter/services.dart` (`Clipboard`);
  - `../services/api_service.dart`;
  - `../database/database_helper.dart` (`saveProject`);
  - `../sketch/sketch_screen.dart` (`SketchScreen` constructor: `bleManager`, `initialShapes`, `initialWallAngles`, `initialWallLengths`, `cloudProjectId`, `canEdit`);
  - `../sketch/sketch_model.dart` (`SketchShape.empty()`, `.points`, `.isClosed`, `.wallRealMm`, `.roomObjects`, `.furnitureItems`, `.id`);
  - `../sketch/room_object.dart` (`RoomObject`, `RoomObjectType`);
  - `../sketch/furniture_item.dart` (`FurnitureItem`, `FurnitureType`);
  - `../services/sync_service.dart` (`uploadSuccessStream`).
- **Declarations:**
  - **`class CollaborationScreen extends StatefulWidget` (L14):** `const CollaborationScreen({super.key})`.
  - **`class _CollaborationScreenState` (L21), `with SingleTickerProviderStateMixin`.**

    Fields:

    | Line | Field | Type | Meaning |
    |---|---|---|---|
    | L23 | `_tabController` | `late TabController` | 2 tabs. |
    | L24 | `_ownedProjects` | `List<dynamic>` | Rows from `GET /projects`. |
    | L25 | `_sharedProjects` | `List<dynamic>` | Rows from `GET /projects/shared`. |
    | L26 | `_loadingOwned` | `bool` | Initially true. |
    | L27 | `_loadingShared` | `bool` | Initially true. |
    | L28 | `_working` | `bool` | Full-screen "Working..." overlay for restore, open and join. |

    Methods:
    - **`initState` (L31):** `TabController(length: 2, vsync: this)`, then `_loadOwned()` and `_loadShared()`.
    - **`dispose` (L39):** disposes the controller.
    - **`_loadOwned()` (L44)** / **`_loadShared()` (L54):** fetch the lists and `setState` if mounted.
    - **`_restoreProject(int, String)` (L66):** 9.2.10.
    - **`_openLive(int, String, {bool canEdit = false})` (L90):** 9.2.15. The parsed flat `roomObjects` list is discarded.
    - **`_showJoinDialog()` (L124):** 9.2.12. The dialog's `TextEditingController` is never disposed.
    - **`_showInviteCode(int, String)` (L196):** 9.2.11.
    - **`_showCollaborators(int, String)` (L264):** 9.2.13. Uses a `StatefulBuilder` so each switch updates in place (`list[i] = {...c, 'can_edit': val}`).
    - **`_leaveProject(int, String)` (L366):** 9.2.14.
    - **`(List<SketchShape>, List<RoomObject>, List<double>, List<double>) _parseProjectData(Map data)` (L401):** a Dart 3 record. Parsing rules are in 9.2.10. It reads the keys `shapes[].is_closed`, `points[].x|y`, `wall_real_mm[].wall_index|real_mm`, `shapes[0].wall_angles[].angle`, `shapes[0].wall_lengths[].length`, `roomObjects[].object_id|type|wall_index|position_along|width_mm|height_mm|elevation_mm|shape_index`, and `furnitureItems[].furniture_id|type|position_x|position_y|rotation_deg|width_mm|depth_mm|shape_index`. `shapes[].shape_index` is **not** read; the array order is trusted.
    - **`_snack(String, {bool error = false})` (L479):** red or green (`0xFF00AA44`) SnackBar if mounted.
    - **`_shortDate(dynamic raw)` (L487):** parses an ISO date to local time as `d/m/yyyy`; null or invalid → `''`.
    - **`build` (L500):**
      - Scaffold, background `0xFF0D1A27`.
      - AppBar "Collaboration" with a `TabBar` (tabs "My Projects" and "Shared With Me").
      - AppBar action `TextButton.icon(Icons.group_add, 'Join')` → `_showJoinDialog`.
      - Body: the `_working` overlay or a `TabBarView`.
    - **`_buildOwnedTab()` (L549):** the owned list with `RefreshIndicator(onRefresh: _loadOwned)`. `PopupMenuButton` values: `open_live` → `_openLive(id, name, canEdit: true)`, `restore`, `invite`, `collaborators`.
    - **`_buildSharedTab()` (L651):** the shared list with `RefreshIndicator(onRefresh: _loadShared)`. Menu values: `open_live` (with `canEdit` from `p['can_edit']`), `restore`, `leave`.
  - **`class _LiveCollabWrapper extends StatefulWidget` (L763).**
    - Final fields: `cloudProjectId` (int), `projectName` (String; unused in build), `initialShapes` (`List<SketchShape>`), `initialWallAngles`, `initialWallLengths` (`List<double>`), `lastKnownUpdatedAt` (String), `canEdit` (bool, default false).
    - Constructor at L772; `createState` at L783.
  - **`class _LiveCollabWrapperState` (L786).**

    Fields:
    - `_pollTimer` (Timer?, L787);
    - `_uploadSub` (StreamSubscription?, L788);
    - `_lastUpdatedAt` (String, L789);
    - `_syncing` (bool, L790);
    - `_lastSyncTime` (DateTime?, L791);
    - `_sketchKey` (Key = `UniqueKey()`, L792);
    - `_shapes`, `_wallAngles`, `_wallLengths` (late, L793–795).

    Methods:
    - **`initState` (L798):** 10-s poll timer; upload-success subscription when `canEdit`.
    - **`dispose` (L818).**
    - **`_poll()` (L824):** 9.2.15.
    - **`build` (L932):** Stack of the SketchScreen and the badge.
    - **`String _timeAgo(DateTime)` (L996):** under 60 s → `'<s>s ago'`, otherwise `'<m>m ago'`.
- **Key logic:**
  - Owners always get `canEdit: true`. Collaborators get the `can_edit` value from the last shared-list load.
  - Polling interval is 10 s. A remote change remounts `SketchScreen` with a new `UniqueKey`.
  - The user's own uploads are kept from triggering a remount by tracking `updated_at` from `uploadSuccessStream`.
- **State and data:** server rows held as `List<dynamic>` maps. Restores are written to SQLite through `DatabaseHelper.saveProject`. The live wrapper keeps the latest server `updated_at` string as its `since` cursor.
- **UI:** see 9.2.9–9.2.15 for every menu item, dialog, SnackBar text and badge.
- **Connections:**
  - Opened from `HomeScreen` "Restore from Cloud" (home_screen.dart L187).
  - Endpoints used: `GET /projects`, `GET /projects/shared`, `GET /sync/download/:id`, `GET /sync/updates/:id`, `POST /projects/join`, `GET /projects/:id/invite-code`, `GET /projects/:id/collaborators`, `PATCH /projects/:id/edit-access`, `DELETE /projects/:id/leave`.
  - Pushes `SketchScreen`, which then runs heartbeat and presence and queues uploads.
- **Notes and issues:**
  - **Duplicated and lossy parsing:**
    - The parsing logic exists three times (`_parseProjectData`, `_poll`, `CloudProjectsScreen`).
    - `RoomObjectType.opening` is turned into `window`, although local loading handles `'opening'` (sketch_screen.dart L828).
    - Unknown furniture types become `sofa`.
  - **Remount side effects:**
    - A remount on every remote change loses local edits and undo history, and recreates `'Auto Save'` local projects.
    - Remount also re-subscribes `SketchScreen`'s never-cancelled stream listeners.
  - **Poll robustness:**
    - If parsing in `_poll` throws (unexpected server data), `_syncing` stays `true` and polling stops silently.
    - If `updated_at` is null or empty, every poll looks like an update.
  - **Stale data:** the "Ns ago" badge never ticks. The `canEdit` value is a snapshot taken when the list loaded.
  - **Dialog and input issues:**
    - Join codes that are not exactly 8 characters are silently ignored.
    - The collaborators dialog is a non-scrollable `AlertDialog` with a shrink-wrapped list and can overflow with many collaborators.
    - "View collaborators" shows "No one has joined yet." on a 403 or network error.
  - **Lifecycle:**
    - `setState` is called after `await` without a `mounted` check in `_restoreProject` (L83), `_openLive` (L103, before its mounted check) and `_showJoinDialog` (L183).
    - `_restoreProject` pops the whole collaboration screen after success.

---

### 9.4 Data contracts

#### 9.4.1 REST endpoint reference

Base URL used by the app: `http://13.214.196.211:3000`. "JWT" means the request needs `Authorization: Bearer <token>`; without it the response is 401 `{"error":"No token provided. Please login."}`, and with a bad or expired token it is 401 `{"error":"Invalid or expired token. Please login again."}`. All bodies are JSON (`Content-Type: application/json`).

| # | Method and path | Auth / access rule | Request | Success response | Error responses | SQL summary | Client caller |
|---|---|---|---|---|---|---|---|
| 1 | `GET /health` | none | – | 200 `{"status":"OK","message":"SmartMeasure backend running"}` | – | none | none |
| 2 | `POST /auth/register` | none | `{"email":str,"password":str}` | 201 `{"message":"Registration successful","user":{"id":int,"email":str}}` | 400 `Email and password are required`; 400 `Password must be at least 6 characters`; 409 `Email already registered`; 500 `Server error` | SELECT id FROM users WHERE email; INSERT INTO users(email,password_hash) RETURNING id,email | `ApiService.register` |
| 3 | `POST /auth/login` | none | `{"email","password"}` | 200 `{"message":"Login successful","token":str,"user":{"id","email"}}` | 400 (missing); 401 `Invalid email or password`; 500 `Server error` | SELECT * FROM users WHERE email | `ApiService.login` |
| 4 | `GET /projects` | JWT | – | 200 `[<projects row>…]`, ordered by `updated_at DESC` | 500 | SELECT * FROM projects WHERE user_id ORDER BY updated_at DESC | `getCloudProjects` |
| 5 | `POST /projects` | JWT | `{"name":str,"local_id"?:int}` | 201 `<projects row>` | 400 `Project name is required`; 500 | INSERT INTO projects(user_id,name,local_id,invite_code) RETURNING * | **unused** |
| 6 | `GET /projects/shared` | JWT | – | 200 `[{…projects row,"role","can_edit","owner_email"}]` | 500 | SELECT p.*, pc.role, pc.can_edit, u.email AS owner_email … WHERE pc.user_id AND pc.status='accepted' ORDER BY p.updated_at DESC | `getSharedProjects` |
| 7 | `POST /projects/join` | JWT | `{"invite_code":str}` | 200 `{"message":"Joined successfully","project":{"id","name","owner_email","updated_at"}}` | 400 `Invite code required`; 404 `Invalid invite code`; 400 `You already own this project`; 409 `Already a collaborator`; 500 | SELECT project by invite_code (+owner email); SELECT id,status FROM project_collaborators; UPDATE status='accepted',joined_at=NOW() **or** INSERT (role 'editor', status 'accepted') | `joinProject` |
| 8 | `GET /projects/:id/invite-code` | JWT, owner only | path `id` | 200 `{"invite_code":str}` | 404 `Not found`; 500 | SELECT invite_code FROM projects WHERE id AND user_id | `getInviteCode` |
| 9 | `GET /projects/:id/collaborators` | JWT, owner only | path `id` | 200 `[{"email","role","status","joined_at","can_edit"}]` | 403 `Access denied`; 500 | owner check; SELECT u.email, pc.role, pc.status, pc.joined_at, pc.can_edit … ORDER BY joined_at | `getCollaborators` |
| 10 | `DELETE /projects/:id/leave` | JWT | path `id` | 200 `{"message":"Left project"}` (always) | 500 | DELETE FROM project_collaborators WHERE project_id AND user_id | `leaveProject` |
| 11 | `PATCH /projects/:id/edit-access` | JWT, owner only | `{"email":str,"can_edit":bool}` | 200 `{"ok":true}` | 400 `email and can_edit required`; 403 `Access denied`; 404 `User not found`; 500 | owner check; SELECT id FROM users WHERE email; UPDATE project_collaborators SET can_edit | `setEditAccess` |
| 12 | `DELETE /projects/:id` | JWT, owner only (filter) | path `id` | 200 `{"message":"Project deleted successfully"}` (even if 0 rows) | 500 (incl. FK violation) | DELETE FROM projects WHERE id AND user_id | **unused** |
| 13 | `POST /sync/upload` | JWT. Existing project: owner, or accepted collaborator with `can_edit`. New project: anyone (becomes owner). | Upload body (9.4.3) | 200 `{"message":"Project uploaded successfully","cloud_project_id":int,"updated_at":ISO}` | 403 `{"error":"Edit access not granted"}`; 409 `{"conflict":true,"server_updated_at":ISO}`; 500 `{"error":"Upload failed"}` | Transaction: find project by `cloud_project_id`, else by (user_id, local_id); permission check; conflict check; UPDATE name and updated_at, delete all children, **or** INSERT project; INSERT every shape, point, wall row, room object and furniture item; COMMIT; SELECT updated_at | `SyncService` → `uploadProject` |
| 14 | `GET /sync/download/:projectId` | JWT, owner or accepted collaborator | path | 200 download body (9.4.3) | 404 `Project not found or access denied`; 500 `Download failed` | access SELECT p.*; shapes by shape_index; per shape: points/wall_real_mm/wall_angles/wall_lengths; room_objects; furniture_items | `downloadProject` |
| 15 | `GET /sync/updates/:projectId?since=ISO` | JWT, owner or accepted collaborator | path and `since` | 200 `{"updated":false}` **or** `{"updated":true,…download body}` | 404 `Access denied`; 500 `Failed to check updates` | as #14, short-circuits when `updated_at <= since` | `pollForUpdates` |
| 16 | `POST /sync/heartbeat` | JWT, owner or accepted collaborator | `{"project_id":int}` | 200 `{"ok":true}` | 400 `project_id required`; 404 `Access denied`; 500 `Heartbeat failed` | access check; INSERT … ON CONFLICT (project_id,user_id) DO UPDATE SET last_seen_at=NOW() | `sendHeartbeat` |
| 17 | `GET /sync/active-collaborators/:projectId` | JWT, owner or accepted collaborator | path | 200 `[{"email","last_seen_at"}]` (others only, last 2 min, newest first) | 404 `Access denied`; 500 `Failed to get active collaborators` | access check; SELECT u.email, pp.last_seen_at … last_seen_at > NOW() - INTERVAL '2 minutes' | `getActiveCollaborators` |

Error messages in the table are the value of the `"error"` key. Framework-level responses are HTML, not JSON:
- 400 for malformed JSON;
- 413 for a body over 100 kb;
- 404 `Cannot <METHOD> <path>` for unknown routes outside `/projects` and `/sync`. Under those prefixes the JWT check runs first.
- 500 for promise rejections outside `try`.

#### 9.4.2 JWT

- Algorithm HS256, secret `JWT_SECRET`, `expiresIn: '7d'`.
- Payload: `{"userId": <users.id int>, "email": <users.email>, "iat": <unix s>, "exp": <iat + 604800>}`.
- Server routes read `req.user.userId`. `HomeScreen` reads the `email` claim client-side without verifying the signature.
- The client stores the token in `FlutterSecureStorage` under the key `jwt_token`.

#### 9.4.3 JSON payloads

**Upload request** (`POST /sync/upload`). It is built by `SketchScreen._buildProjectPayload` (sketch_screen.dart L537). `SyncService.queueUpload` adds `last_modified_at`. The same JSON text is stored in SQLite `pending_uploads.payload`.

```json
{
  "project": {
    "name": "Room Project",          // dialog name (backup) or active room label / "Room Project" (auto-sync)
    "local_id": 12,                  // SQLite projects.id (always present, non-null)
    "cloud_project_id": 34           // only when SketchScreen knows it
  },
  "shapes": [{
    "shape_index": 0,                // position in SketchScreen.shapes
    "is_closed": true,
    "points":       [{"order_index": 0, "x": 120.0, "y": 80.0}],      // sketch world coordinates
    "wall_real_mm": [{"wall_index": 0, "real_mm": 3450.0}],           // measured wall lengths, mm (map entries)
    "wall_angles":  [{"order_index": 0, "angle": 1.5708}],            // radians, atan2 between consecutive points (n-1 entries)
    "wall_lengths": [{"order_index": 0, "length": 345.0}]             // world-unit distance between consecutive points (n-1 entries)
  }],
  "roomObjects": [{
    "object_id": "door_3", "shape_index": 0,
    "type": "door",                  // RoomObjectType.name: door | window | opening
    "wall_index": 2, "position_along": 0.5,   // 0..1 along the wall
    "width_mm": 900, "height_mm": 2100, "elevation_mm": 0
  }],
  "furnitureItems": [{
    "furniture_id": "f_1", "shape_index": 0,
    "type": "sofa",                  // FurnitureType.name
    "position_x": 150.0, "position_y": 90.0,  // world-coordinate centre
    "rotation_deg": 0.0,             // clockwise degrees
    "width_mm": 2000, "depth_mm": 900
  }],
  "last_modified_at": "2026-05-12T10:00:00.000Z"   // optional; server updated_at from last success in this SketchScreen
}
```

(The comments are explanatory; real JSON has none. The example values for `object_id` and `furniture_id` are illustrative; the real id formats are defined in the sketch part.)

Not sent, and therefore lost in the cloud: `SketchShape.label`, `SketchShape.heightMm`, `SketchShape.sharedWalls`, `RoomObject.swingFlipped`, the global `_wallAngles` / `_wallDrawnLengths` lists, and the local project name.

**Upload responses:**
- 200 `{"message":"Project uploaded successfully","cloud_project_id":34,"updated_at":"2026-05-12T10:00:05.123Z"}`.
- 409 `{"conflict":true,"server_updated_at":"…Z"}`, which `ApiService` re-maps to `{'conflict': true, 'server_updated_at': …}`.
- 403 `{"error":"Edit access not granted"}`.
- 500 `{"error":"Upload failed"}`.

**Download / updates response** (`GET /sync/download/:id`; `/sync/updates` adds `"updated": true`):

```json
{
  "project": {"id": 34, "user_id": 5, "name": "…", "local_id": 12, "invite_code": "K3J9QZ1A",
              "updated_at": "2026-05-12T10:00:05.123Z", "...": "any other projects columns"},
  "shapes": [{
    "id": 101, "project_id": 34, "shape_index": 0, "is_closed": true,
    "points":       [{"id": 1, "shape_id": 101, "order_index": 0, "x": 120.0, "y": 80.0}],
    "wall_real_mm": [{"id": 1, "shape_id": 101, "wall_index": 0, "real_mm": 3450.0}],
    "wall_angles":  [{"id": 1, "shape_id": 101, "order_index": 0, "angle": 1.5708}],
    "wall_lengths": [{"id": 1, "shape_id": 101, "order_index": 0, "length": 345.0}]
  }],
  "roomObjects":    [{"id": 7, "project_id": 34, "object_id": "door_3", "type": "door", "wall_index": 2,
                      "position_along": 0.5, "width_mm": 900, "height_mm": 2100, "elevation_mm": 0, "shape_index": 0}],
  "furnitureItems": [{"id": 9, "project_id": 34, "shape_index": 0, "furniture_id": "f_1", "type": "sofa",
                      "position_x": 150.0, "position_y": 90.0, "rotation_deg": 0, "width_mm": 2000, "depth_mm": 900}]
}
```

Child rows are `SELECT *`, so the exact column sets beyond the ones written by the upload come from the unknown base schema; the `id` columns shown are inferred. The keys the app actually reads are listed under `_parseProjectData` in 9.3.

The Dart casts also constrain the column types:
- `is_closed as bool` → BOOLEAN;
- `as int` on `id` / `wall_index` → INTEGER (not BIGINT/NUMERIC, which node-postgres returns as strings);
- `as num` on coordinates and sizes → REAL / DOUBLE PRECISION / INTEGER (not NUMERIC);
- `as String` on `object_id` / `furniture_id`.

**List element shapes:**

| Endpoint | Element | Keys the app reads |
|---|---|---|
| `GET /projects` | every `projects` column | `id`, `name`, `updated_at` |
| `GET /projects/shared` | every `projects` column + `role`, `can_edit`, `owner_email` | `id`, `name`, `updated_at`, `owner_email`, `can_edit` |
| `GET /projects/:id/collaborators` | `{"email","role","status","joined_at","can_edit"}` | `email`, `can_edit` |
| `GET /sync/active-collaborators/:id` | `{"email","last_seen_at"}` | `email` |

Other single responses: `POST /projects/join` → `project.name` is read. `GET …/invite-code` → `invite_code`.

#### 9.4.4 PostgreSQL schema (reconstructed)

The base migrations (001/002) that create `users`, `projects`, `shapes`, `shape_points`, `wall_real_mm`, `wall_angles`, `wall_lengths`, `room_objects` and `project_collaborators` are **not in the repository** and never existed in git history. Note also that CLAUDE.md's "`src/db/migrations/`" path is wrong; the files are in `code/smartmeasure-backend/migrations/`.

Source legend:
- **M00n** = migration file;
- **Q** = inferred from SQL in the routes;
- **C** = implied by client casts or JS usage;
- **?** = unknown (constraint or default not visible anywhere).

**`users`** (Q)

| Column | Type | Null / default | Keys / constraints | Source |
|---|---|---|---|---|
| `id` | integer (serial) | generated | PK | Q `RETURNING id`; M003 FK `INTEGER REFERENCES users(id)` |
| `email` | text/varchar | NOT NULL ? | UNIQUE ? (the app checks before insert) | Q |
| `password_hash` | text/varchar (bcrypt `$2b$10$…`, 60 chars) | NOT NULL ? | – | Q |
| other columns | ? | ? | – | `SELECT *` in login reads only the three above |

**`projects`** (Q)

| Column | Type | Null / default | Keys / constraints | Source |
|---|---|---|---|---|
| `id` | integer (serial) | generated | PK | Q, M003/M005 FKs, C `as int` |
| `user_id` | integer | NOT NULL ? | FK → `users(id)` ? (joined as owner) | Q |
| `name` | text | NOT NULL ? | – | Q |
| `local_id` | integer-compatible | nullable (POST /projects may insert NULL) | no uniqueness known | Q |
| `invite_code` | text, 8 chars | ? | UNIQUE ? (not checked in code) | Q |
| `updated_at` | `timestamp` or `timestamptz` | default ? (upload sets `NOW()` explicitly; POST /projects omits it) | – | Q, C (`.toISOString()` needs a Date) |
| other columns (e.g. `created_at`) | ? | ? | – | never referenced |

**`shapes`** (Q)

| Column | Type | Null / default | Keys | Source |
|---|---|---|---|---|
| `id` | integer (serial) | generated | PK | Q `RETURNING id` |
| `project_id` | integer | ? | FK → `projects(id)` ?; ON DELETE ? | Q |
| `shape_index` | integer | ? | – | Q (ORDER BY) |
| `is_closed` | boolean | ? | – | Q, C `as bool` |

**`shape_points`** (Q): `id` (? serial PK, returned but unused), `shape_id` integer (FK → `shapes(id)` ?), `order_index` integer, `x` float, `y` float (C `as num`).

**`wall_real_mm`** (Q): `id` ?, `shape_id` integer FK ?, `wall_index` integer (C `as int`), `real_mm` float (millimetres).

**`wall_angles`** (Q): `id` ?, `shape_id` integer FK ?, `order_index` integer, `angle` float (radians).

**`wall_lengths`** (Q): `id` ?, `shape_id` integer FK ?, `order_index` integer, `length` float (sketch world units).

**`room_objects`** (Q + M004)

| Column | Type | Null / default | Keys | Source |
|---|---|---|---|---|
| `id` | serial ? | ? | PK ? | ? |
| `project_id` | integer | ? | FK → `projects(id)` ? | Q |
| `object_id` | text | ? | – | Q, C `as String` |
| `type` | text (`door` / `window` / `opening`) | ? | – | Q |
| `wall_index` | integer | ? | – | Q, C `as int` |
| `position_along` | float | ? | – | Q, C |
| `width_mm`, `height_mm`, `elevation_mm` | float | ? | – | Q, C |
| `shape_index` | INTEGER | NOT NULL DEFAULT 0 | logical link to `shapes.shape_index` | M004 |

**`furniture_items`** (M005, complete)

| Column | Type | Null / default | Keys |
|---|---|---|---|
| `id` | SERIAL | – | PK |
| `project_id` | INTEGER | NOT NULL | FK → `projects(id)` (no ON DELETE → NO ACTION) |
| `shape_index` | INTEGER | NOT NULL DEFAULT 0 | logical link to `shapes.shape_index` |
| `furniture_id` | TEXT | NOT NULL | – |
| `type` | TEXT | NOT NULL | – |
| `position_x`, `position_y` | DOUBLE PRECISION | NOT NULL | – |
| `rotation_deg` | DOUBLE PRECISION | NOT NULL DEFAULT 0 | – |
| `width_mm`, `depth_mm` | DOUBLE PRECISION | NOT NULL | – |

**`project_collaborators`** (Q + M006)

| Column | Type | Null / default | Keys | Source |
|---|---|---|---|---|
| `id` | integer ? | ? | PK ? (selected in join) | Q |
| `project_id` | integer | ? | FK → `projects(id)` ? | Q |
| `user_id` | integer | ? | FK → `users(id)` ?; UNIQUE(project_id,user_id) ? | Q |
| `role` | text | ? | always `'editor'` | Q |
| `status` | text | ? | only `'accepted'` is ever written | Q |
| `joined_at` | timestamp | default ? (INSERT omits it; re-accept sets `NOW()`) | – | Q |
| `can_edit` | BOOLEAN | NOT NULL DEFAULT FALSE | – | M006 |

**`project_presence`** (M003, complete)

| Column | Type | Null / default | Keys |
|---|---|---|---|
| `project_id` | INTEGER | NOT NULL | PK part; FK → `projects(id)` ON DELETE CASCADE |
| `user_id` | INTEGER | NOT NULL | PK part; FK → `users(id)` ON DELETE CASCADE |
| `last_seen_at` | TIMESTAMP (no tz) | NOT NULL DEFAULT NOW() | index `idx_presence_project_seen (project_id, last_seen_at DESC)` |

**Known indexes:** primary keys and `idx_presence_project_seen`. Any indexes on `projects.user_id`, `projects.invite_code`, `shapes.project_id` or the `*.shape_id` columns are unknown (base schema).

#### 9.4.5 Relationships

- `users` 1 — N `projects` through `projects.user_id` (owner).
- `projects` 1 — N `shapes` (`shapes.project_id`).
- `shapes` 1 — N `shape_points`, `wall_real_mm`, `wall_angles` and `wall_lengths` (`shape_id`).
- `projects` 1 — N `room_objects` and `furniture_items` (`project_id`). Both also point at a room *logically* through `shape_index` = `shapes.shape_index` = position in the client's shape list (no FK).
- `users` N — M `projects` through `project_collaborators` (`role`, `status`, `joined_at`, `can_edit`).
- `users` N — M `projects` through `project_presence` (`last_seen_at`). Cascades on both sides.
- ON DELETE behaviour:
  - `project_presence` cascades.
  - `furniture_items` → `projects` blocks deletion.
  - All other foreign-key actions are unknown.
- Client mapping: SQLite `projects.id` ↔ PostgreSQL `projects.local_id` (first uploader only). The reverse mapping (cloud id) is kept only in memory in `SketchScreen._cloudProjectId`.

#### 9.4.6 Environment variables (backend `.env`, not committed)

| Variable | Read in | Required | Meaning |
|---|---|---|---|
| `PORT` | app.js L26 | no (defaults to 3000) | HTTP listen port (bound to 0.0.0.0). |
| `DATABASE_URL` | db.js L8–10 | either this or the `DB_*` group | Full PostgreSQL connection string. When set, SSL is used with `rejectUnauthorized: false`. |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | db.js L14–18 | when `DATABASE_URL` is absent | Discrete connection settings, no SSL. Unset values fall back to `PGHOST` etc., then `localhost:5432` and the OS user. |
| `JWT_SECRET` | auth.js L78; auth_middleware.js L19 | **yes** | HMAC secret for signing and verifying JWTs. If missing, login → 500 and all protected routes → 401. |
| `NODE_ENV` (implicit) | Express | no | Anything other than `production` makes Express's default error pages include stack traces. |
| `DOTENV_CONFIG_QUIET` (implicit) | dotenv 17 | no | `true` silences dotenv's start-up log line. |

A minimal `.env`:

```text
PORT=3000
JWT_SECRET=<long random string>
DATABASE_URL=postgres://user:password@host:5432/dbname
# or, instead of DATABASE_URL:
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=smartmeasure
# DB_USER=postgres
# DB_PASSWORD=...
```

#### 9.4.7 Timing constants and limits

| Constant | Value | Where |
|---|---|---|
| JWT lifetime | 7 days | auth.js L79 |
| bcrypt cost | 10 | auth.js L30 |
| Minimum password length | 6 | auth.js L17 |
| Invite code | 8 chars `[0-9A-Z]` | projects.js L33, sync.js L93; join dialog `maxLength: 8` |
| JSON body limit | 100 kb (default) | app.js L13 |
| pg pool | max 10, idle timeout 10 s (defaults) | db.js |
| Live poll | every 10 s | collaboration_screen.dart L805 |
| Heartbeat | every 30 s, plus one immediately | sketch_screen.dart L4021 |
| Presence window | 2 minutes | sync.js L442 |
| Upload-queue retry | every 60 s, plus on connectivity change | sync_service.dart L44 |
| Presence avatars shown | 4 maximum | sketch_screen.dart L4041 |
| "Project updated" SnackBar | 2 s | collaboration_screen.dart L925 |

---

### 9.5 Known issues and limitations

**Security**

- **Cleartext transport.** The app talks plain HTTP to a hard-coded raw IP (`http://13.214.196.211:3000`), with `android:usesCleartextTraffic="true"`. Passwords, JWTs and all project data cross the network unencrypted, and moving the server needs an app rebuild.
- **Database TLS without verification.** `ssl: { rejectUnauthorized: false }` in `DATABASE_URL` mode; the `DB_*` mode has no TLS at all.
- **Weak authentication hardening.**
  - No rate limiting or lockout on `/auth/login`, `/auth/register` or `/projects/join`.
  - The password policy is length ≥ 6 only.
  - No email validation or normalisation.
  - Account enumeration is possible through register (409) and edit-access (404 vs 200).
- **Token handling.**
  - JWTs live 7 days with no refresh or revocation. Logout only deletes the local copy.
  - The `JWT_SECRET` value is not validated at start-up.
  - `isLoggedIn()` ignores expiry, and 401s are never surfaced as "please log in".
- **Invite codes.**
  - Generated with `Math.random()` (not a CSPRNG).
  - They never expire and cannot be rotated or revoked. Joining grants immediate read access.
  - Owners cannot remove a collaborator or revoke read access; no endpoint exists.
  - The codes leak to every collaborator (including view-only ones) through `p.*` in `GET /projects/shared` and `project` in `/sync/download` and `/sync/updates`, which defeats the owner-only `GET /projects/:id/invite-code`.
- **Misleading `role` field.** `role` is always `'editor'` and never enforced; `can_edit` is the real permission.
- **Information leakage.**
  - Express's default error pages contain stack traces unless `NODE_ENV=production`.
  - `X-Powered-By: Express` is sent.
  - CORS is `*`. Low impact because the API uses bearer tokens, not cookies.
- **SQL injection:** none found. Every query uses `$n` parameters.
- **Shared-device leakage.** Logout does not clear `pending_uploads`. Snapshots queued by user A are later uploaded with user B's token: they create projects in B's account when no `cloud_project_id` is present, and return 403 (blocking the queue) when one is.
- **No quotas.** Any authenticated user can create unlimited cloud projects through `/sync/upload`.

**Sync correctness and data integrity**

- **Cloud id never persisted locally.** It lives only in `SketchScreen` memory, which leads to:
  - (a) Reopened projects rely on the `(user_id, local_id)` fallback and send no `last_modified_at`, so they overwrite blindly.
  - (b) Local ids from another device or a reinstall can collide with an existing `local_id` of the same user, silently overwriting an unrelated cloud project.
  - (c) Restored projects are unlinked, so editing them creates duplicates (owner) or forks (collaborator).
- **"Save Changes" on exit re-keys the local project.** It inserts a new row and deletes the old one together with its `pending_uploads`, so unsent offline edits are dropped. The next session creates a duplicate cloud project with a new invite code.
- **`_loadProjectById` does not reset `_cloudProjectId` or `_lastCloudUpdatedAt`.** Loading another local project inside an open sketch uploads it into the previously linked cloud project.
- **Upload-success listeners ignore `local_project_id`.** The listeners in `SketchScreen` and `_LiveCollabWrapper` can adopt another project's cloud id or timestamp.
- **Self-conflicts.**
  - Each queued snapshot carries the `last_modified_at` known when it was queued.
  - If two or more snapshots are queued while one is in flight (fast edits, or offline editing after a successful upload), every snapshot after the first gets 409.
  - Those snapshots are parked as `conflict` forever and the icon turns red.
  - The newest state is uploaded only after another edit.
- **No conflict resolution or merge.** Conflict handling is detect-and-park only. Live editing is effectively last-writer-wins, because `_lastCloudUpdatedAt` restarts at `null` after every remount.
- **Head-of-line blocking.**
  - Any non-409 failure keeps the oldest row `pending` and stops the loop: an expired token (401), a view-only collaborator pressing "Backup to Cloud" (403), a malformed or oversized payload (500/413), or a server bug.
  - No other upload, for any project, goes through until that row is removed (e.g. by deleting its local project).
  - There is no maximum-attempts limit. `attempts` and `last_attempt` are never read, and `pendingUploadCount()` is never called.
- **View-only is not enforced in the UI.** Drawing is still possible and "Backup to Cloud" stays enabled. Only `_queueAutoSync` checks `canEdit`.
- **Live-mode remount.** Every remote change remounts `SketchScreen`, which discards in-progress edits, undo history and selection, and creates a fresh `'Auto Save'` local project on the next edit. Owners editing their own project live can also see their own upload come back as a "remote" update if a poll races the success event.
- **Project name overwritten.** Auto-sync replaces the cloud project name with the active room's label or `'Room Project'`, discarding the name chosen in "Backup to Cloud". Collaborators' uploads rename the owner's project too.
- **Lossy round-trip.**
  - Not stored in the cloud: room labels, room heights, shared walls, door `swingFlipped`.
  - `opening` objects come back as `window`.
  - Per-shape `wall_angles` / `wall_lengths` are recomputed from points on upload, but only shape 0's lists are used on download (and then saved under every shape by `saveProject`).
- **Inefficient snapshot model.**
  - Every edit enqueues a full snapshot (no coalescing).
  - The server deletes and re-inserts every child row with one INSERT per row inside a held transaction.
  - Large projects can exceed the default 100 kb body limit; the resulting 413 HTML page blocks the queue.
- **No row locking in `/sync/upload`.** Concurrent writers can both pass the conflict check; the last commit wins.
- **No deletion propagation.** Deleting a local project leaves the cloud copy, and the server's `DELETE /projects/:id` is unused. It would also fail on the `furniture_items` FK and returns 200 even when nothing was deleted.

**Backend robustness**

- **Double `client.release()`.** The 403 and 409 paths of `/sync/upload` release explicitly and again in `finally`. pg-pool throws, Express logs the error and destroys the socket after the response, so delivery of the 403/409 depends on timing.
- `pool.connect()` in `/sync/upload` is outside `try`. No `pool.on('error')` handler exists, so idle-client errors can crash the process.
- **Express 5 `req.body`.** Without a JSON body, `req.body` is `undefined`, so destructuring throws and every body-reading route answers 500 instead of 400.
- **Unvalidated inputs.**
  - A non-string `invite_code` or `password` → 500.
  - A non-numeric `:id` / `:projectId` → 500.
  - `can_edit` is not type-checked.
- **Misleading success responses.** `DELETE /:id/leave`, `PATCH /:id/edit-access` and `DELETE /:id` report success even when no row changed.
- **No error logging** in the catch blocks of `/:id/invite-code`, `/:id/collaborators` and `/:id/leave`.
- **Duplicated code.** The access-check SQL is copied four times; the download and updates bodies are near-duplicates; the invite-code generator appears twice.
- **Migrations.**
  - There is no migration runner or tracking table; files are applied by hand with `psql`.
  - The base schema (001/002) is missing from the repository.
  - `project_presence` rows are never cleaned up.
  - `POST /projects` creates projects without `updated_at` (its default is unknown). With a NULL `updated_at`, `/sync/updates` reports every poll as an update and live mode remounts every 10 s.
- **Startup does not fail fast.** A missing database or missing `JWT_SECRET` is not fatal.

**Client robustness, dead code and documentation drift**

- **Networking.** No HTTP timeouts. Errors collapse into `[]`, `null` or `false` and look like empty data. `register` and `login` report HTML error pages as "Cannot connect to server".
- **Possible `setState` after dispose:**
  - `LoginScreen._submit` (L50);
  - `CollaborationScreen._restoreProject` (L83), `_openLive` (L103) and `_showJoinDialog` (L183);
  - `CloudProjectsScreen._loadCloudProjects` (L29).
- **Unclosed streams and subscriptions.** `SyncService.dispose()` is never called. `SketchScreen` never cancels its `statusStream` / `uploadSuccessStream` subscriptions; one leaks per mount, and live mode mounts repeatedly.
- **Silent edge cases.**
  - Join codes that are not exactly 8 characters are ignored without feedback.
  - The live badge "Ns ago" never ticks.
  - If parsing in `_poll` throws, polling stops silently.
  - The collaborators dialog is not scrollable.
  - The SketchScreen share icon always fails for collaborators.
- **Dead or unused code:**
  - `CloudProjectsScreen` (unreachable, and its restore loses doors, windows and furniture);
  - the unused `flutter/foundation.dart` import in `sync_service.dart`;
  - the unused `lastModifiedAt` parameter of `ApiService.uploadProject`;
  - the flat `roomObjects` list returned by `_parseProjectData` (ignored by `saveProject` and by `_openLive`);
  - the server routes `POST /projects`, `DELETE /projects/:id` and `GET /health` (no client caller);
  - the response fields `role`, `status`, `joined_at` and `last_seen_at` (never read);
  - the zero-byte file `code/smartmeasure-backend/git`;
  - `package.json` `"main": "index.js"` (the file does not exist).
- **Documentation drift.**
  - CLAUDE.md places migrations in `src/db/migrations/`; they are in `migrations/`.
  - CLAUDE.md says `routes/projects.js` does "CRUD for projects and room data"; room data is only in `routes/sync.js`, and there is no update route for projects.
  - CLAUDE.md's Express 5 note mentions error middleware, but the app defines none.
  - Code comments still say "Railway", while the app points at a raw IP.


---


---

## Part 10 — Cross-cutting reference

This part ties Parts 3–9 together. It does not repeat their detail; it shows how data moves across subsystem boundaries and where to look.

### 10.1 End-to-end flows across subsystems

#### 10.1.1 Measuring a wall with the device (the core use case)

1. **Home → "Start Room Sketch".** `HomeScreen` creates a new `BleManager` and pushes `BleConnectionScreen` (§4.2.2).
2. **CONNECT.** `BleManager.connectToDevice()`:
   1. scans with `flutter_blue_plus`;
   2. matches `platformName == "SmartMeasure Pro"`;
   3. connects, discovers services, finds service `4fafc201-1fb5-459e-8fcc-c5c9c331914b` and characteristic `beb5483e-36e1-4688-b7f5-ea07361b26a8`;
   4. calls `setNotifyValue(true)`.

   One second after `connectStream` emits `true`, the BLE screen is replaced by `SketchScreen(bleManager)` (§3.2).
3. **The user draws a room** and selects a wall. The app sets `_waitingForBle` for that wall (§5.2).
4. **On the device**, in Bluetooth mode:
   1. The first MEAS press switches the aiming laser on and notifies `00 00 50 01` ("capturing").
   2. The second press runs `doMeasure()`: it reads TF-Luna 9-byte UART frames in cm, computes `mm = cm × 10`, and adds 146 mm when the T/B toggle is on "B".
   3. It shows the result on the OLED, appends it to `/readings.csv`, and notifies `[mm >> 8, mm & 0xFF, 80, 0]` (§3.2, §3.4).
5. **The app parses the packet.** `BlePacket.fromBytes` yields `distanceMm`, and the packet goes out on `packetStream`. `SketchScreen`'s listener calls `_applyRealMeasurement(wall, mm)`. This stores `shape.wallRealMm[wall] = mm` and rebuilds the room's point chain from the screen-level `_wallAngles` / `_wallDrawnLengths` so that the wall gets its real length (§5.2).
6. **The painter redraws.** The wall's dimension label turns green (measured). Area and labels update (§6.2).

The same packet path is used from the 3D view: `Room3DScreen._triggerBleMeasurement` waits with `packetStream.where(...).first`, then sets `wallRealMm[i]` and calls back `onWallMeasured(i, mm)` into `SketchScreen._applyRealMeasurement` (§8.2).

**Limits of this flow:**
- The link is one-way: the app cannot trigger a measurement.
- A failed measurement sends nothing, so the app keeps waiting.
- The closing wall (index n−1) cannot receive a real length (§5.5).

#### 10.1.2 Saving and loading locally

`SketchScreen` → `DatabaseHelper.saveProject(...)` → SQLite `smartmeasure.db`:
- tables `projects` → `shapes` → `shape_points` / `wall_real_mm` / `wall_angles` / `wall_lengths`;
- plus `room_objects` and `furniture_items`.

Save always **inserts a new project**; "save on back" inserts a new one and deletes the old one.

Loading goes "My Projects" → `ProjectListScreen` (pops an id) → `SketchScreen(initialLocalProjectId)` → `DatabaseHelper.loadProject(id)`. Room labels, ceiling heights and shared walls are not persisted (§4.2.4, §4.4).

#### 10.1.3 Cloud backup and auto-sync

1. `SketchScreen._buildProjectPayload` builds a full snapshot (JSON shape in §4.4 and §9.4).
2. `SyncService.queueUpload` stores it in `pending_uploads`.
3. `processQueue` runs on connectivity change, every 60 s, and right after queueing. It calls `ApiService.uploadProject` → `POST /sync/upload` with `Authorization: Bearer <jwt>`.
4. The server:
   1. resolves the cloud project, by `cloud_project_id` or by the `(user_id, local_id)` fallback;
   2. checks ownership or `can_edit`;
   3. checks for a conflict: client `last_modified_at` older than `projects.updated_at` → **409**;
   4. in a transaction, deletes all child rows and re-inserts the snapshot.
5. On success, `uploadSuccessStream` reports `cloud_project_id` and `updated_at` back to the open `SketchScreen`.

The cloud id is kept only in memory, never in SQLite (§9.2, §9.5).

#### 10.1.4 Collaboration and live view

- **Sharing.** Every cloud project gets an 8-character `[0-9A-Z]` invite code when it is created. The owner reads it with `GET /projects/:id/invite-code`. Another user joins with `POST /projects/join`, which creates a `project_collaborators` row with `can_edit = false`. The owner can grant edit rights with `PATCH /projects/:id/edit-access`.
- **"Open live".** In `CollaborationScreen`, this downloads the project (`GET /sync/download/:id`) and wraps `SketchScreen` in `_LiveCollabWrapper`:
  - The wrapper polls `GET /sync/updates/:id` every **10 s**. When the server copy is newer, it rebuilds the sketch with a new key, which discards local, unsynced UI state.
  - While open, `SketchScreen` sends `POST /sync/heartbeat` every **30 s** and shows avatars from `GET /sync/active-collaborators/:id` (active = seen in the last 2 min).
  - Edits are auto-synced only when `canEdit` is true.

Details in §9.2.

#### 10.1.5 3D view

1. `SketchScreen` "3D View" → `Room3DScreen(shapes, activeIndex, bleManager, onWallMeasured, onHeightChanged)`.
2. Dart inlines `three.min.js` and `gltf_loader.js` into `three_room.html` (replacing `<!--THREE_JS-->`) and calls `loadHtmlString`.
3. Dart serialises every room. Coordinates are converted: world units → metres, plan x → X, plan y → Z, Y up. Wall height = `heightMm/1000`; thickness 0.2 m is hard-coded.
4. GLB models from `assets/models/` are added as base64.
5. The JSON is pushed in chunks with `runJavaScript` and assembled by `window.initHouse(...)`.
6. Taps come back over the `FlutterBridge` JavaScript channel as `wallTap`, `roomTap` or `furnitureTap`.

See §8.2 and §8.4.

#### 10.1.6 AR import

1. `ARScanScreen` captures `WallPlane`s (a position and a normal in metres) by tapping.
2. `wallPlanesToPolygonMm` intersects consecutive walls in the XZ plane, giving corners in mm.
3. `ARResultScreen` lets the user drag corners and correct the scale (0.5–2.0×).
4. "Import to Sketch" creates `SketchShape(label: 'AR Scan', points in world units, wallRealMm per wall, heightMm 2400)` and replaces the stack with `[HomeScreen, SketchScreen]`.

Static analysis suggests that wall capture never succeeds on Android with `ar_flutter_plugin_2` 0.0.3, and that opposite walls are rejected as duplicates (§4.5).

#### 10.1.7 Exports

- **PDF:** `exportSketchPdf(context, shapes, projectName)` builds an A4 document (cover, overview, one page per room) and calls `Printing.layoutPdf` (OS print / "Save as PDF").
- **DXF:** `DxfPreviewScreen` renders a blueprint preview. `DxfExporter.export` writes AC1009 text to the temporary directory and calls `Share.shareXFiles`.

Both exporters are read-only on the model (Part 7).

### 10.2 Units and coordinate systems (master table)

| Where | Unit | Axes / convention |
|---|---|---|
| TF-Luna frame | cm (uint16 LE) | — |
| Firmware display / CSV / BLE | mm (BLE: uint16 **big-endian**, so the maximum is 65,535 mm; the firmware caps readings at 8,000 mm) | B mode adds 146 mm |
| Sketch model `SketchShape.points`, `FurnitureItem.position` | world units (1 u = 5 mm) | x right, y **down**; wall i = `points[i] → points[(i+1) % n]` |
| `wallRealMm`, `RoomObject` sizes, `FurnitureItem.widthMm/depthMm`, `heightMm` | mm | `positionAlong` ∈ [0, 1] is the object's centre along the wall |
| Angles in the wall chain (`_wallAngles`) | radians, `atan2(dy, dx)` in world coordinates | UI shows counter-clockwise degrees; snapping within 3° |
| Furniture rotation `rotationDeg` | degrees, clockwise on screen | at 0° the item faces screen-down (the code comment says "right", which is wrong) |
| Sketch grid | 40 u = 200 mm | wall thickness 30 u = 150 mm in 2D |
| Canvas view | screen px = world × scale + pan | default scale 0.35, clamped to 0.001–5.0 |
| SQLite and cloud payload | world units for points and positions; mm for lengths and sizes | same as the model |
| 3D scene | metres | plan x → X, plan y → Z, Y up; centred on the global vertex centroid; wall thickness 0.2 m |
| AR capture | metres, ARCore world frame, Y up | polygon output in mm, `Offset(X·1000, Z·1000)` |
| PDF | points (1/72 in) | uniform fit-to-page scale, Y flipped |
| DXF | mm (`$INSUNITS = 4`) | `X = 5·x`, `Y = −5·y` (Y flipped), Z = 0 |

### 10.3 Identifier cross-reference

| Identifier | Value | Defined in | Must match |
|---|---|---|---|
| BLE device name | `SmartMeasure Pro` | `main.cpp` (`BLEDevice::init`) | `ble_manager.dart` scan filter |
| BLE service UUID | `4fafc201-1fb5-459e-8fcc-c5c9c331914b` | `main.cpp` | `ble_manager.dart` `serviceUuid` |
| BLE characteristic UUID | `beb5483e-36e1-4688-b7f5-ea07361b26a8` (NOTIFY) | `main.cpp` | `ble_manager.dart` `characteristicUuid` |
| BLE payload | `[dist_hi, dist_lo, battery=80, capturing 0/1]` | `main.cpp` `bleSend` | `ble_packet.dart` `BlePacket.fromBytes` |
| Stale placeholders (unused) | `AppConstants.bleServiceUUID`, `bleCharacteristicUUID`, `deviceName`, `dbName` | `core/constants.dart` | nothing; do not rely on them |
| Local DB file | `smartmeasure.db`, version 4 | `database_helper.dart` | — |
| JWT storage key | `jwt_token` (FlutterSecureStorage) | `api_service.dart` | — |
| JWT payload | `{ userId, email }`, `expiresIn: '7d'` | backend `routes/auth.js` | `auth_middleware.js`; `HomeScreen` decodes `email` |
| Backend base URL | `http://13.214.196.211:3000` | `ApiService.baseUrl` | server `PORT` (default 3000) |
| Backend env vars | `DATABASE_URL` or `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`, `JWT_SECRET`, `PORT` | `db.js`, `auth.js`, `app.js` | `.env` (not committed); see §9.4 for the exact list |
| Furniture type names | 31 `FurnitureType` enum names (`sofa`, `armchair`, `coffeeTable`, … `washingMachine`) | `furniture_item.dart` | SQLite `furniture_items.type`, cloud `furniture_items.type`, 3D model map, JS `createFurnitureGroup` |
| Room object types | `door`, `window`, `opening` | `room_object.dart` | SQLite, cloud, painter, exporters, 3D. The collaboration parser maps `opening` → `window` (bug). |
| Cloud payload list keys | `shapes`, `roomObjects`, `furnitureItems`, `project{name, local_id, cloud_project_id}`, `last_modified_at` | `SketchScreen._buildProjectPayload` | backend `POST /sync/upload`. Note: local `loadProject` uses `room_objects` / `furniture_items`. |
| JS bridge | channel `FlutterBridge`; JS → Dart messages `ready`, `wallTap`, `roomTap`, `furnitureTap`, `screenshot`; Dart → JS calls `initHouse`, `highlightWall`, `highlightRoom`, `resetCamera`, `captureScreenshot` | `room_3d_screen.dart`, `three_room.html` | both sides (§8.4) |

**REST endpoints** (all except `/auth/*` and `/health` need `Authorization: Bearer <JWT>`; full request and response shapes in §9.4):

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness check |
| POST | `/auth/register` | Create an account (bcrypt) and return a JWT |
| POST | `/auth/login` | Log in and return a JWT |
| GET | `/projects` | Projects owned by the user |
| POST | `/projects` | Create an empty cloud project |
| GET | `/projects/shared` | Projects shared with the user (`can_edit`, `owner_email`) |
| POST | `/projects/join` | Join with an invite code |
| GET | `/projects/:id/invite-code` | Owner fetches the invite code (generated when the cloud project is created) |
| GET | `/projects/:id/collaborators` | List collaborators |
| DELETE | `/projects/:id/leave` | Collaborator leaves |
| PATCH | `/projects/:id/edit-access` | Owner sets a collaborator's `can_edit` (by email) |
| DELETE | `/projects/:id` | Owner deletes a project |
| POST | `/sync/upload` | Upload a full snapshot (create/replace; 409 on conflict) |
| GET | `/sync/download/:projectId` | Download a full project |
| GET | `/sync/updates/:projectId` | Change polling for the live view |
| POST | `/sync/heartbeat` | Presence ping |
| GET | `/sync/active-collaborators/:projectId` | Who is active (last 2 min) |

### 10.4 Build, run and configure

**Firmware**
1. Install PlatformIO and connect the ESP32.
2. Edit `upload_port`/`monitor_port` in `firmware/platformio.ini` (they are hard-coded to `COM14`).
3. Run `pio run --target upload` and then `pio device monitor` (115200 baud).
4. Wiring is in §1.5 and §3.3.

**Backend**
1. `cd code/smartmeasure-backend && npm install`.
2. Create `.env` with `JWT_SECRET` and either `DATABASE_URL` or the `DB_*` variables (§9.4).
3. Create the database schema. **Migrations 001/002 are missing**, so create the base tables from the reconstructed schema in §9.4 first, then apply `migrations/003…006`.
4. Start with `npm run dev` (nodemon) or `npm start`. The server listens on `$PORT` or 3000, on `0.0.0.0`.

**App**
1. `cd code && flutter pub get`. `pubspec.lock` is not committed, so versions may differ from §2.3.
2. **Create `assets/models/`** (the directory is declared in `pubspec.yaml` but git-ignored); otherwise the asset build fails. Put the GLB files in it, or leave it empty: furniture then falls back to procedural shapes, which is fine.
3. Point `ApiService.baseUrl` (`lib/services/api_service.dart`) at your backend.
4. Run `flutter run` on an Android device (minSdk 28). AR needs ARCore. BLE needs a real phone and the device.
5. `flutter test` currently fails to compile (§4.5).

### 10.5 Most important known issues (prioritised)

Full lists are in each part's N.5 section. The ones that matter most:

1. **Fresh clones do not build.** `assets/models/` (and `pubspec.lock`) are git-ignored. `tv_unit.glb` is referenced but missing even locally, and some model names do not match the files (§6.5, §8.5).
2. **Security.**
   - Plain HTTP to a hard-coded IP, with cleartext allowed.
   - No rate limiting.
   - Invite codes are generated with `Math.random`, never expire, and leak to all collaborators.
   - Logout does not clear the device-wide upload queue, so another user can upload the first user's data (§9.5).
3. **Data loss and duplication.**
   - Room labels and heights are never saved (locally or in the cloud).
   - Save always inserts a new project.
   - The cloud id is not persisted, so re-opened projects overwrite blindly through the `local_id` fallback.
   - `opening` becomes `window` and `swing_flipped` is lost on the cloud round-trip (§4.5, §5.5, §9.5).
4. **Editor correctness.**
   - The closing wall cannot get a real length.
   - The manual length dialog ignores the "m" unit.
   - The screen-level wall chain can go stale across rooms.
   - Undo/redo regenerates room ids and gets out of step for furniture.
   - Furniture and opening ids collide after reload (§5.5, §6.5).
5. **AR is very likely non-functional on Android** (identity rotation from the plugin, plus opposite-wall rejection) (§4.5).
6. **Device protocol is minimal.**
   - One-way notifications, so the app cannot request a measurement.
   - No error packet.
   - The battery value is fake.
   - A measurement is a single frame with no averaging (§3.5).
7. **No working tests and no CI.** The only test does not compile; the backend has no tests.

### 10.6 Code status of the development tracks

Code comments and project notes describe two feature tracks. Current status in code:

**3D track**
- 3D-1: the Dart pseudo-3D painter is kept as a toggle.
- 3D-2: Three.js WebView, orbit controls and wall selection are done.
- 3D-3: procedural furniture builders are done, **and GLB models are now loaded** through `GLTFLoader` when present.
- 3D-4: PBR materials, a canvas wood-floor texture and contact shadows are done.
- 3D-5: screenshot sharing is only partly present: a `captureScreenshot` bridge exists, but there is no share UI.

**AR track**
- AR-1 (session), AR-2 (tap capture), AR-3 (polygon) and AR-5 (result editor) are implemented, but see the Android issue in §10.5.
- AR-4 (iOS RoomPlan) and AR-6 (AR furniture placement) are not started.

### 10.7 Errors in the existing project documentation

| Document claims | Reality (code) |
|---|---|
| CLAUDE.md / README: VL53L0X LiDAR, MPU6050 / BNO055 IMU, "angle detection" | TF-Luna on UART2; no IMU code in any commit; angles come from the drawing |
| CLAUDE.md: "Riverpod throughout", central `SketchModel` | No providers; `setState` + singletons; model classes are `SketchShape`, `SharedWall`, `RoomObject`, `FurnitureItem` |
| CLAUDE.md: BLE UUIDs live in `core/constants.dart` | The live UUIDs are in `ble/ble_manager.dart`; the constants file holds stale, unused placeholders |
| CLAUDE.md: migrations under `src/db/migrations/` | `code/smartmeasure-backend/migrations/`, and only 003–006 exist |
| CLAUDE.md: `routes/projects.js` = "CRUD for projects and room data" | Room data is handled only in `routes/sync.js`; there is no project update route |
| CLAUDE.md: Express 5 error middleware | No error middleware is defined |
| CLAUDE.md: current branch `feature-Dxf-export` | Work is on `main`; DXF export is merged |
| App text: "press BOOT button on ESP32" | The firmware ignores BOOT; press MEAS twice in Bluetooth mode |
| README: range "up to 20 m", battery monitoring | Readings over 8 m are rejected; battery is the constant 80 |
| `docs/export_feature_explained.md` | Predates the September 2026 exporter changes; 16 discrepancies are listed in §7.3 |
| Android minSdk 24 (older notes) | minSdk is 28 |

### 10.8 Glossary

| Term | Meaning |
|---|---|
| World unit (u) | Sketch coordinate unit, 5 mm |
| Shape / room | `SketchShape`: a polygon (open or closed) with walls, objects, furniture, label and height |
| Wall i | Edge from `points[i]` to `points[(i+1) % n]`; the closing wall of a closed room is n−1 |
| `wallRealMm` | Map from wall index to real (measured or typed) length in mm |
| Wall chain | Screen-level `_wallAngles` and `_wallDrawnLengths` used to rebuild a room when a real length is applied |
| Room object | Door, window or opening attached to a wall (`RoomObject`) |
| Shared wall | Coincident walls of two rooms detected in move mode (`SharedWall`, `wall_topology.dart`); written but never read |
| T / B | Device reference point: top (raw) or bottom (+146 mm) |
| Capturing packet | BLE packet `00 00 50 01`, sent when the laser is switched on in BLE mode |
| Snapshot upload | Full-project upload that replaces all server child rows |
| Pending upload | Queued snapshot in SQLite `pending_uploads` |
| Invite code | 8-character code that lets another user join a cloud project |
| Live mode | Collaboration view that polls for server changes every 10 s |
| Presence | Heartbeat-based list of users who currently have a project open |
| `FlutterBridge` | The JavaScript channel from the 3D WebView back to Dart |

### 10.9 File index

| File | Documented in |
|---|---|
| `firmware/src/main.cpp`, `firmware/platformio.ini` | §3.3 |
| `code/lib/core/constants.dart`, `code/lib/ble/*` | §3.3 |
| `code/pubspec.yaml`, `analysis_options.yaml`, `test/widget_test.dart`, `lib/main.dart`, `lib/screens/home_screen.dart` | §4.3 |
| `code/lib/database/database_helper.dart`, `project_list_screen.dart`, `lib/furniture_3d_viewer.dart` | §4.3 |
| `code/lib/ar/*` | §4.3 |
| `code/android/*`, `code/ios/Runner/Info.plist`, `code/web/*` | §4.3 |
| `code/lib/sketch/sketch_screen.dart`, `sketch_model.dart`, `sketch_constants.dart`, `room_object.dart`, `room_object_utils.dart`, `wall_openings.dart`, `wall_topology.dart`, `sketch_widgets.dart`, `sketch_dialogs.dart` | §5.3 |
| `code/lib/sketch/sketch_painter.dart`, `furniture_item.dart`, `furniture_painter.dart` | §6.3 |
| `code/lib/sketch/sketch_pdf_export.dart`, `code/lib/screens/dxf_exporter.dart`, `dxf_preview_screen.dart`, `docs/export_feature_explained.md` | §7.3 |
| `code/lib/sketch/room_3d_screen.dart`, `code/assets/3d/*`, `code/temp.js` | §8.3 |
| `code/smartmeasure-backend/**`, `code/lib/services/*`, `code/lib/screens/login_screen.dart`, `code/lib/database/collaboration_screen.dart`, `cloud_projects_screen.dart` | §9.3 |
| Repository-level configuration, `docs/`, desktop runners (`linux/`, `macos/`, `windows/`: unmodified `flutter create` templates) | §2.4 |
