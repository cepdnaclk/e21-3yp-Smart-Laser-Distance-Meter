import 'package:flutter/material.dart';
import 'ble_manager.dart';

class BleConnectionScreen extends StatefulWidget {
  final BleManager bleManager;
  final VoidCallback onConnected;

  const BleConnectionScreen({
    super.key,
    required this.bleManager,
    required this.onConnected,
  });

  @override
  State<BleConnectionScreen> createState() => _BleConnectionScreenState();
}

class _BleConnectionScreenState extends State<BleConnectionScreen> {
  bool _isScanning = false;
  String _statusMessage = 'Press the button to find SmartMeasure Pro';

  @override
  void initState() {
    super.initState();
    // Listen for connection events
    widget.bleManager.connectStream.listen((connected) {
      if (connected) {
        setState(() {
          _statusMessage = 'Connected!';
          _isScanning = false;
        });
        // Wait 1 second then go to sketch screen
        Future.delayed(const Duration(seconds: 1), () {
          widget.onConnected();
        });
      }
    });
  }

  void _startScan() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning for SmartMeasure Pro...';
    });

    await widget.bleManager.connectToDevice();

    // If still scanning after 12 seconds, it failed
    Future.delayed(const Duration(seconds: 12), () {
      if (_isScanning && mounted) {
        setState(() {
          _isScanning = false;
          _statusMessage = 'Device not found. Make sure ESP32 is powered on.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              // ── Logo area ──────────────────────────────
              const Icon(
                Icons.bluetooth_searching,
                size: 80,
                color: Color(0xFF00AAFF),
              ),
              const SizedBox(height: 24),
              const Text(
                'SmartMeasure Pro',
                style: TextStyle(
                  color: Color(0xFFEEEEEE),
                  fontSize: 24,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bluetooth Connection',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),

              const SizedBox(height: 60),

              // ── Status message ─────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1A27),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334466)),
                ),
                child: Row(
                  children: [
                    if (_isScanning)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00AAFF),
                        ),
                      )
                    else
                      const Icon(Icons.info_outline,
                          color: Color(0xFF556677), size: 16),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: Color(0xFFAABBCC),
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Connect button ─────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth),
                  label: Text(
                    _isScanning ? 'SCANNING...' : 'CONNECT TO DEVICE',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isScanning
                        ? const Color(0xFF334466)
                        : const Color(0xFF00AAFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isScanning ? null : _startScan,
                ),
              ),

              const SizedBox(height: 16),

              // ── Skip button (for testing without ESP32) ─
              TextButton(
                onPressed: widget.onConnected,
                child: const Text(
                  'Skip (test without device)',
                  style: TextStyle(
                    color: Color(0xFF556677),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}