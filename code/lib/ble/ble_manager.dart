import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_packet.dart';

const String serviceUuid        = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

class BleManager {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;

  final _packetController  = StreamController<BlePacket>.broadcast();
  final _connectController = StreamController<bool>.broadcast();

  Stream<BlePacket> get packetStream  => _packetController.stream;
  Stream<bool>      get connectStream => _connectController.stream;
  bool get isConnected => _device != null;

  // ── Scan and connect ──────────────────────────────────
  Future<void> connectToDevice() async {
    try {
      // Stop any previous scan first
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 200));

      StreamSubscription? scanSubscription;

      scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          if (r.device.platformName == "SmartMeasure Pro") {
            await scanSubscription?.cancel();
            await FlutterBluePlus.stopScan();
            await _connect(r.device);
            break;
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
      );

    } catch (e) {
      print("Scan error: $e");
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false);
    _connectController.add(true);
    print("Connected to SmartMeasure Pro");

    // Discover services
    List<BluetoothService> services = await device.discoverServices();
    for (BluetoothService s in services) {
      if (s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
        for (BluetoothCharacteristic c in s.characteristics) {
          if (c.uuid.toString().toLowerCase() == characteristicUuid.toLowerCase()) {
            _characteristic = c;
            await c.setNotifyValue(true);
            c.onValueReceived.listen((bytes) {
              final packet = BlePacket.fromBytes(bytes);
              _packetController.add(packet);
              print("Received: ${packet.distanceMm}mm  bat:${packet.batteryPercent}%");
            });
          }
        }
      }
    }
  }

  // ── Disconnect ────────────────────────────────────────
  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _characteristic = null;
    _connectController.add(false);
  }

  void dispose() {
    _packetController.close();
    _connectController.close();
  }
}