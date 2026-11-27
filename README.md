# Smart Laser Distance Meter

**A handheld LiDAR distance meter that sends each measurement to your phone over Bluetooth, where it becomes an accurate 2D and 3D floor plan.**

![Status](https://img.shields.io/badge/status-in%20active%20development-orange)
![ESP32](https://img.shields.io/badge/ESP32-Arduino%20%7C%20PlatformIO-E7352C?logo=espressif&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-Express%205-339933?logo=nodedotjs&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![Three.js](https://img.shields.io/badge/Three.js-3D-000000?logo=threedotjs&logoColor=white)

<!-- TODO(media): add a 10–20 s demo GIF (measure a wall → plan updates → 3D view), then uncomment:
<p align="center">
  <img src="docs/images/readme/demo.gif" alt="Measuring a room and viewing it in 3D" width="320">
</p>
-->

Measuring a room by hand and sketching it on paper is slow, and it's easy to make mistakes. This system replaces the tape measure and notepad. You draw the room shape on your phone, point the device at each wall, and the measured length is applied to the plan automatically. You can then view the room in 3D, add doors, windows and furniture, and export the plan as a PDF or a CAD-ready DXF file.

> Third-year engineering project — Department of Computer Engineering, University of Peradeniya.

---

## Table of Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Hardware](#hardware)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Roadmap](#roadmap)
- [My Contribution](#my-contribution)
- [Team](#team)
- [Links](#links)

---

## Features

**Measuring**
- 📏 **LiDAR measurement.** The handheld device measures distances up to 8 m and shows them on a built-in OLED screen.
- 📡 **Bluetooth Low Energy link.** Each measurement is sent to the app and applied directly to the selected wall.
- 💾 **On-device history.** Every reading is also saved to a micro-SD card and can be browsed on the device.

**Floor planning**
- ✏️ **2D room sketching.** Draw rooms as polygons, with angle snapping, a grid, pan and zoom, and undo/redo.
- 🏠 **Multi-room projects.** Place several rooms in one plan, move them, and let walls snap together into shared walls.
- 🚪 **Doors, windows and openings.** These attach to walls and have adjustable size, sill height and door swing.
- 🛋️ **Furniture library.** Choose from 31 furniture types in 6 categories, then place, rotate and resize them.
- 📐 **Automatic dimensions and area.** Wall lengths and room areas are calculated and labelled on the plan.

**3D and export**
- 🧊 **Interactive 3D view.** The plan is rendered with Three.js, including wall thickness, openings, textured materials and 3D furniture models. You can also measure walls from the 3D view.
- 📄 **PDF export.** A multi-page A4 floor-plan guide: a cover page, an overview, and one page per room.
- 📐 **DXF export.** An AutoCAD-compatible (R12) file, with a blueprint-style preview before you export.

**Storage and collaboration**
- 📴 **Offline-first.** Projects are saved locally in SQLite, and uploads are queued until the phone is back online.
- ☁️ **Cloud sync.** User accounts (JWT), automatic background sync, and detection of conflicting edits.
- 👥 **Live collaboration.** Share a project with an invite code, choose whether each collaborator can view or edit, and see who is online.

---

## Screenshots

<!-- TODO(media): add photos/screenshots to docs/images/readme/, then uncomment this table:
| Device | 2D floor plan | 3D view | Multi-room | Export |
|:---:|:---:|:---:|:---:|:---:|
| <img src="docs/images/readme/device.jpg" width="160"> | <img src="docs/images/readme/app-2d-plan.png" width="160"> | <img src="docs/images/readme/app-3d-view.png" width="160"> | <img src="docs/images/readme/app-multi-room.png" width="160"> | <img src="docs/images/readme/app-export.png" width="160"> |
-->

_Screenshots coming soon._

---

## Architecture

```mermaid
flowchart LR
    subgraph Device["Handheld device"]
        L[TF-Luna LiDAR] -->|UART| E[ESP32 firmware]
        E --> O[OLED display]
        E --> S[(micro-SD history)]
    end

    E -->|"BLE notify<br/>(4-byte packet)"| A

    subgraph App["Flutter mobile app"]
        A[BLE manager] --> SK[2D sketch editor]
        SK --> V3[3D view<br/>WebView + Three.js]
        SK --> EX[PDF / DXF export]
        SK --> DB[(SQLite<br/>offline storage)]
        DB --> Q[Sync service<br/>offline upload queue]
    end

    Q -->|"REST + JWT"| API

    subgraph Cloud["Backend"]
        API[Node.js / Express 5] --> PG[(PostgreSQL)]
    end
```

1. **Device.** The ESP32 reads distances from the TF-Luna LiDAR, shows them on the OLED and logs them to the SD card. In Bluetooth mode, it sends every measurement to the phone as a compact 4-byte BLE notification.
2. **Mobile app.** The app receives each measurement and applies it to the selected wall. It then rebuilds the room's geometry so the plan stays consistent. The 2D editor holds all the plan data, and the 3D view, the exporters and the storage layer are built on top of it.
3. **Backend.** A REST API handles user accounts, project snapshots, sharing and live collaboration. The app works fully offline and syncs when it reconnects.

For a detailed, file-by-file reference of the whole system, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Tech Stack

| Layer | Technologies |
|---|---|
| **Firmware** | C++ (Arduino), PlatformIO, ESP32 Bluedroid BLE, Adafruit SSD1306/GFX |
| **Mobile app** | Flutter / Dart, `flutter_blue_plus`, `sqflite`, `webview_flutter` + Three.js, `pdf` / `printing`, custom DXF writer |
| **Backend** | Node.js, Express 5, `pg`, `bcryptjs`, `jsonwebtoken` |
| **Database** | SQLite (on device), PostgreSQL (cloud) |

---

## Hardware

| Component | Purpose |
|---|---|
| ESP32 DevKit | Microcontroller with built-in Bluetooth LE |
| Benewake TF-Luna | Time-of-flight LiDAR distance sensor (UART) |
| SSD1306 0.96" OLED (128×64) | Shows measurements, menus and history |
| micro-SD module | Stores the measurement history |
| 5 push buttons | Power, select, down, measure, top/bottom reference |
| Laser pointer + buzzer | Shows where you're aiming and gives audio feedback |

<!-- TODO(media): optionally add a wiring diagram or PCB/enclosure photo here -->

---

## Repository Structure

```text
.
├── firmware/                  # ESP32 firmware (PlatformIO)
│   └── src/main.cpp
├── code/                      # Flutter mobile app
│   ├── lib/
│   │   ├── ble/               # BLE connection and packet parsing
│   │   ├── sketch/            # 2D editor, rendering, furniture, 3D view, PDF export
│   │   ├── database/          # SQLite storage, project list, collaboration
│   │   ├── screens/           # Home, login, DXF export
│   │   └── services/          # REST client and sync service
│   ├── assets/3d/             # Three.js scene
│   └── smartmeasure-backend/  # Node.js / Express REST API
│       ├── src/
│       └── migrations/
├── docs/                      # Department project page (GitHub Pages)
└── ARCHITECTURE.md            # Full system reference
```

---

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart ^3.10) and an Android phone with Bluetooth LE
- [PlatformIO](https://platformio.org/) (VS Code extension or CLI) for the firmware
- Node.js 20+ and PostgreSQL for the backend

### 1. Firmware
```bash
cd firmware
pio run --target upload    # set upload_port in platformio.ini to your board's port first
pio device monitor         # serial monitor at 115200 baud
```

### 2. Backend
```bash
cd code/smartmeasure-backend
npm install
```
Create a `.env` file:
```env
DATABASE_URL=postgres://user:password@localhost:5432/smartmeasure
JWT_SECRET=change-me
PORT=3000
```
Apply the SQL files in `migrations/`, then run:
```bash
npm run dev
```

### 3. Mobile app
```bash
cd code
flutter pub get
flutter run
```
To connect to your own backend, set `baseUrl` in `code/lib/services/api_service.dart`. If you only want to work offline, tap **Skip for now** on the login screen.

> **Note:** the 3D furniture models (`code/assets/models/`) aren't stored in git because of their size. Without them, the 3D view draws simple stand-in shapes for the furniture.

---

## Roadmap

- [ ] AR room scanning (ARCore): in progress, not yet working reliably
- [ ] IMU-based angle measurement on the device
- [ ] Battery level reporting over BLE
- [ ] Commit the base database schema and add a one-command backend setup
- [ ] Merge the backend unit tests and CI workflow into `main`

---

## My Contribution

**[RidmalChamod](https://github.com/RidmalChamod): lead contributor, 200+ commits (about 64% of the commits on `main`)**

- **Multi-room floor-plan engine.** Designed the `SketchShape` data model and moved the 2D editor from a single room to multiple rooms. Added cross-room snapping, wall snap-merging with shared-wall rendering, multi-room move mode and full-canvas undo/redo.
- **Interactive 3D room view.** Built the Three.js scene inside a Flutter WebView. It renders walls with real thickness and door/window openings, realistic materials, textures and contact shadows, and 3D furniture models. Later extended it to multi-room plans.
- **Live collaboration and cloud sync.** Built the feature end to end, in both the Express API and the Flutter app: invite codes, shared projects, edit permissions, presence avatars and live update polling. Also built the offline upload queue with automatic background sync.
- **Furniture library and local persistence.** Built the furniture system, saved furniture and projects to SQLite, and added save-on-exit with an unsaved-changes prompt.
- **Integration.** Merged teammates' feature branches (doors and windows, room objects, BLE measurement) into one working editor, and fixed the geometry bugs that came out of merging them.
- **Quality and documentation.** Wrote backend unit tests and a GitHub Actions CI workflow (on the `unitTest_Ridmal` branch), and wrote [ARCHITECTURE.md](ARCHITECTURE.md), the full system reference.

➡️ [See all my commits](https://github.com/cepdnaclk/e21-3yp-Smart-Laser-Distance-Meter/commits?author=RidmalChamod)

---

## Team

- E/21/065, CHAMOD S.A.R., [email](mailto:e21065@eng.pdn.ac.lk)
- E/21/068, CHANDRASIRI E.M.D.D.V, [email](mailto:e21068@eng.pdn.ac.lk)
- E/21/277, PADUKKA V.K., [email](mailto:e21277@eng.pdn.ac.lk)
- E/21/325, RASHMIKA W.B.R., [email](mailto:e21325@eng.pdn.ac.lk)

---

## Links

- [Project Page](https://cepdnaclk.github.io/e21-3yp-Smart-Laser-Distance-Meter)
- [Department of Computer Engineering](http://www.ce.pdn.ac.lk/)
- [University of Peradeniya](https://eng.pdn.ac.lk/)
