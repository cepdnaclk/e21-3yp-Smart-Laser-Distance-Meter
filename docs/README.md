<!--
---

layout: home
permalink: index.html

# Please update this with your repository name and project title
repository-name: e21-3yp-Smart-Laser-Distance-Meter
title: Smart Laser Distance Meter
---
-->

# Smart Laser Distance Meter

<div align="center">
  <img src="images/download.png" alt="Icon" width="300">
</div>

---

## Team
-  E/21/065, CHAMOD S.A.R., [email](mailto:e21065@eng.pdn.ac.lk)
-  E/21/068, CHANDRASIRI E.M.D.D.V, [email](mailto:e21068@eng.pdn.ac.lk)
-  E/21/277, PADUKKA V.K., [email](mailto:e21277@eng.pdn.ac.lk)
-  E/21/325, RASHMIKA W.B.R., [email](mailto:e21325@eng.pdn.ac.lk) 

<!-- Image (photo/drawing of the final hardware) should be here -->

<!-- This is a sample image, to show how to add images to your page. To learn more options, please refer [this](https://projects.ce.pdn.ac.lk/docs/faq/how-to-add-an-image/) -->

<!-- ![Sample Image](./images/sample.png) -->

## Table of Contents
1. [Introduction](#introduction)
2. [Project Overview (Non-Technical)](#project-overview-non-technical)
3. [Key Features](#key-features)
4. [Solution Architecture](#solution-architecture)
5. [Repository Structure](#repository-structure)
6. [Technology Stack](#technology-stack)
7. [Hardware & Software Designs](#hardware-and-software-designs)
8. [BLE Protocol (Device ↔ App)](#ble-protocol-device--app)
9. [Backend API (App ↔ Cloud)](#backend-api-app--cloud)
10. [Getting Started (Run Locally)](#getting-started-run-locally)
11. [Testing](#testing)
12. [Detailed budget](#detailed-budget)
13. [Conclusion](#conclusion)
14. [Links](#links)

## Introduction

Accurate indoor measurement and floor plan creation are essential in construction, interior design, and architectural planning. Traditional manual measuring methods are time-consuming, error-prone, and require manual sketching.  

This project proposes a Smart Laser Distance Meter that combines a handheld time-of-flight (ToF) distance meter with a mobile app to create room sketches and floor plans.

This repository contains:
- Firmware for an ESP32-based handheld device that measures distances and sends them over Bluetooth Low Energy (BLE)
- A Flutter mobile app (“SmartMeasure Pro”) for sketching rooms, AR-assisted scanning, exporting, and saving projects
- A Node.js + PostgreSQL backend for authentication, cloud sync, and collaboration

Note: The original concept includes IMU-based angle/orientation measurement. The current firmware in this repo focuses on ToF distance measurement + BLE transfer (IMU integration can be added as an extension).

## Project Overview (Non-Technical)

**What it is**: A “smart measuring tape” for rooms. You measure walls using a handheld laser/ToF device, and the phone app turns those measurements into a clean floor plan.

**Who it helps**:
- Architects, civil engineers, and survey/estimation workflows
- Interior designers and renovation planning
- Anyone needing quick indoor measurements and a shareable plan

**Typical user flow**:
1. Open the app and start a project
2. Connect to the handheld device via Bluetooth
3. Sketch the room outline and shoot real measurements to each wall
4. Add doors/windows and furniture
5. Export (PDF/DXF) or sync to cloud for backup and collaboration

## Key Features

### End-user features
- **Bluetooth-connected distance measurements** from the handheld device
- **Room sketching** (2D floor plan) with measured wall lengths
- **AR room scan** option (ARCore/ARKit) to generate a polygon-based floor plan
- **Projects**: save locally (SQLite) and restore later
- **Cloud sync** with login (JWT)
- **Collaboration** using invite codes and optional edit access
- **Exports**: PDF export and DXF (CAD) export + share

### Developer features
- Clean separation: `firmware/` (embedded), `code/` (Flutter app + backend)
- Offline-first sync queue on the app (uploads retry when connectivity returns)
- Conflict detection on cloud uploads
- Presence/active collaborator tracking


## Solution Architecture

The system consists of a handheld embedded device and a mobile application. The embedded unit performs distance and orientation sensing, processes data using a microcontroller, and transmits results wirelessly to the mobile app.

**High-level data flow:**
- Handheld device measures distance (ToF)
- ESP32 sends measurements to the app via BLE notifications
- The mobile app applies measurements to walls/objects in the sketch
- Projects are saved locally (SQLite)
- Optional: app syncs to cloud backend (HTTPS + JWT) for backup/collaboration

```mermaid
flowchart LR
  Device[Handheld Device\nESP32 + ToF sensor] -- BLE notify --> App[Flutter App\nSmartMeasure Pro]
  App -->|Save locally| LocalDB[(SQLite)]
  App -->|Export| Export[PDF / DXF / Share]
  App -->|AR scan| AR[ARCore/ARKit]\n
  App -->|HTTPS + JWT| API[Node.js + Express API]
  API --> DB[(PostgreSQL)]
```

---

<div align="center">
  <img src="images/High%20Level%20Architecture%20Diagram.png" alt="Icon" width="1000">
</div>
<!-- *(Insert architecture diagram here)*

High level diagram + description -->

## Repository Structure

- `firmware/` — ESP32 firmware (PlatformIO/Arduino)
  - `firmware/src/main.cpp` — OLED UI, laser control, ToF read, BLE notify, SD logging
- `code/` — Flutter app root
  - `code/lib/` — Flutter application code
  - `code/assets/` — app assets (icons, 3D)
  - `code/smartmeasure-backend/` — backend API (Node.js + Express + PostgreSQL)
- `docs/` — project page content (GitHub Pages)
- `images/` — images used by documentation

## Technology Stack

### Firmware (device)
- ESP32 (Arduino framework via PlatformIO)
- I2C OLED: Adafruit SSD1306 + Adafruit GFX
- ToF sensor library: Pololu `VL53L0X`
- BLE GATT server (service + notify characteristic)
- SD card logging over SPI

### Mobile app
- Flutter / Dart
- State: Riverpod
- Bluetooth: `flutter_blue_plus`
- Local DB: `sqflite` + `path_provider`
- AR: `ar_flutter_plugin_2`
- 3D: `model_viewer_plus` + WebView
- Export/share: `pdf`, `printing`, `share_plus`
- Networking/auth: `http`, `flutter_secure_storage`

### Backend (cloud)
- Node.js + Express
- PostgreSQL (`pg`)
- Auth: JWT (`jsonwebtoken`) + password hashing (`bcryptjs`)
- CORS enabled for mobile clients

## Hardware and Software Designs

### Hardware Design
- ESP32 CP2102 Type-C development board
- ToF (LiDAR-like) distance sensor (range depends on module)
  - Repo firmware currently uses `VL53L0X`-class sensor logic (example limit ~2 m in code)
- Optional/Planned: IMU for orientation/angle (not implemented in current firmware code)
- 0.96" OLED display (I2C)
- Red line laser modules for alignment
- Buzzer and vibration motor for feedback
- 18650 battery with TP4056 charging module
- Custom PCB and 3D-printed enclosure

### Software Design
- Sensor interfacing and calibration
- Distance computation (implemented)
- Optional/Planned: angle/orientation computation with IMU
- Bluetooth communication protocol
- Mobile application for visualization, storage, and export

## BLE Protocol (Device ↔ App)

The device advertises as **`SmartMeasure Pro`** and exposes one service + one notify characteristic.

**UUIDs (must match on both sides):**
- Service UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- Notify characteristic UUID: `beb5483e-36e1-4688-b7f5-ea07361b26a8`

**Packet format (4 bytes, big-endian):**
- Byte 0–1: distance in millimeters (uint16)
- Byte 2: battery percent (uint8) — currently a placeholder value in firmware
- Byte 3: flags (bit0 = `isCapturing`)

## Backend API (App ↔ Cloud)

### Authentication
- `POST /auth/register`
- `POST /auth/login` (returns JWT)

### Projects & collaboration
- `GET /projects`, `POST /projects`
- `GET /projects/shared`, `POST /projects/join`
- `GET /projects/:id/invite-code`, `GET /projects/:id/collaborators`
- `PATCH /projects/:id/edit-access`
- `DELETE /projects/:id/leave`

### Sync
- `POST /sync/upload`
- `GET /sync/download/:projectId`
- `GET /sync/updates/:projectId?since=<ISO>`
- `POST /sync/heartbeat`
- `GET /sync/active-collaborators/:projectId`

## Getting Started (Run Locally)

### Prerequisites
- Flutter SDK
- Node.js
- PostgreSQL
- VS Code + PlatformIO extension

### Firmware (ESP32)
1. Open the `firmware/` folder in VS Code
2. Build/upload using PlatformIO environment `esp32dev`
3. Use Serial Monitor at `115200`

### Backend (Node.js + PostgreSQL)
1. From `code/smartmeasure-backend/` run `npm install` then `npm run dev`
2. Create a `.env` with `JWT_SECRET` and DB variables (`DATABASE_URL` or `DB_*`)

### Mobile app (Flutter)
1. From `code/` run `flutter pub get` then `flutter run`
2. If running backend locally, update the base URL in the app (`ApiService.baseUrl`)

## Testing

This repository includes multiple components, so testing is best done per-layer:

- **Firmware (device)**: verify OLED UI flow, measurement stability, BLE advertising/connect, and SD logging.
- **Mobile app**: basic UI sanity checks (login, connect BLE, sketch interactions, export). A minimal Flutter widget test exists under `code/test/`.
- **Backend**: validate `/health`, register/login, then upload/download a project.

For a reproducible test plan, start with:
1. Pair/connect device in BLE mode
2. Apply 3–4 wall measurements to a closed room sketch
3. Save locally, export DXF/PDF
4. Upload to cloud, download on a second device/account (or restore from cloud)
5. Join the same project via invite code and verify collaborator presence
## Detailed budget

### All items and costs

| Item          | Quantity  | Unit Cost  | Total  |
| ------------- |:---------:|:----------:|-------:|
| DTS6012M LiDAR Sensor  | 1  | 6000 LKR  | 6000 LKR |
| BNO055 9-Axis IMU Module | 1 | 4000 LKR | 4000 LKR |  
| ESP32 CP2102 Dev Board | 1 | 1500 LKR | 1500 LKR |
| Green Laser (5 mW) | 1 | 1500 LKR | 1500LKR |
| 18650 Li-ion Battery | 2 | 1400 LKR | 2800 LKR |
| 1.8" TFT LCD Display (MD0260) | 1 | 1000 LKR | 1000 LKR |
| TP4056 Charger + Boost conv. | 1 | 1000 LKR | 1000 LKR |
| Coin Vibration Motor | 1 | 200 LKR | 200 LKR |
| 2x18650 Batttery Holder | 1 | 150 LKR | 150 LKR |
| Active Buzzer | 1 | 100 LKR | 100 LKR |

## Conclusion

SmartMeasure Pro demonstrates an end-to-end indoor measurement workflow: a handheld ESP32-based distance meter streams measurements over BLE to a Flutter application that can sketch floor plans, export results, and sync projects to a cloud backend for collaboration.

Future improvements can include IMU-based orientation integration in firmware, improved battery telemetry, and support for additional ToF sensors with higher range/accuracy.
## Links

- [Project Repository](https://github.com/cepdnaclk/e21-3yp-Smart-Laser-Distance-Meter)
- [Project Page](https://cepdnaclk.github.io/e21-3yp-Smart-Laser-Distance-Meter)
- [Department of Computer Engineering](http://www.ce.pdn.ac.lk/)
- [University of Peradeniya](https://eng.pdn.ac.lk/)

[//]: # (Please refer this to learn more about Markdown syntax)
[//]: # (https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet)
