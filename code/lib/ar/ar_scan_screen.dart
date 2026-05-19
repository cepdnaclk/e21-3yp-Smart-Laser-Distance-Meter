// lib/ar/ar_scan_screen.dart
//
// Phase AR-1: ARCore/ARKit session setup via ar_flutter_plugin_2.
//   ARView handles camera permission internally — no separate flow needed.
//
// Phase AR-2: Plane detection + wall capture.
//   The SDK shows coloured plane overlays automatically.
//   User taps on a visible wall overlay → hit test → we extract the wall's
//   position and outward normal from the worldTransform Matrix4.
//   Walls are identified by |normal.y| < 0.5 (outward normal is horizontal).
//
// Phase AR-3 (entry point): "Generate Floor Plan" calls
//   wallPlanesToPolygonMm() and pushes ARResultScreen.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'ar_polygon_math.dart';
import 'ar_result_screen.dart';

class ARScanScreen extends StatefulWidget {
  const ARScanScreen({super.key});

  @override
  State<ARScanScreen> createState() => _ARScanScreenState();
}

class _ARScanScreenState extends State<ARScanScreen>
    with SingleTickerProviderStateMixin {
  ARSessionManager? _sessionManager;
  final List<WallPlane> _walls = [];
  int _detectedPlaneCount = 0;
  bool _generating = false;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _sessionManager?.dispose();
    super.dispose();
  }

  // ── ARCore / ARKit session ────────────────────────────────────────────────

  void _onARViewCreated(
    ARSessionManager session,
    ARObjectManager objects,
    ARAnchorManager anchors,
    ARLocationManager location,
  ) {
    _sessionManager = session;
    session.onInitialize(
      showAnimatedGuide: false,
      showFeaturePoints: false,
      showWorldOrigin: false,
      showPlanes: true,
      handleTaps: true,
    );
    session.onPlaneOrPointTap = _onPlaneTap;
    session.onPlaneDetected = (count) {
      if (mounted) setState(() => _detectedPlaneCount = count);
    };
  }

  // ── Wall capture ──────────────────────────────────────────────────────────

  void _onPlaneTap(List<ARHitTestResult> results) {
    if (_generating || results.isEmpty) return;

    // Prefer a plane hit over a feature-point hit.
    final hit = results.firstWhere(
      (r) => r.type == ARHitTestResultType.plane,
      orElse: () => results.first,
    );

    final t = hit.worldTransform;

    // Column 1 of the rotation part = plane's local Y-axis = outward normal.
    // Matrix4 is column-major: storage[4..6] = column 1, rows 0–2.
    final normal = Vector3(t.storage[4], t.storage[5], t.storage[6]);

    // Reject floor / ceiling hits — their outward normal points mostly up/down.
    if (normal.y.abs() > 0.5) return;

    // World position of the hit point (column 3 of the transform).
    final position = Vector3(t.storage[12], t.storage[13], t.storage[14]);

    // Reject this tap if we already have a wall with the same facing direction
    // (within 25°). This deduplicates repeat taps on the same wall.
    final cosThreshold = math.cos(25 * math.pi / 180);
    for (final w in _walls) {
      if (w.normal.dot(normal).abs() > cosThreshold) return;
    }

    setState(() {
      _walls.add(WallPlane(
        position: position,
        normal: normal.normalized(),
      ));
    });
  }

  void _removeWall(int index) => setState(() => _walls.removeAt(index));

  // ── Generate floor plan ───────────────────────────────────────────────────

  Future<void> _generatePlan() async {
    if (_walls.length < 3 || _generating) return;
    setState(() => _generating = true);

    final polygonMm = wallPlanesToPolygonMm(_walls);

    if (!mounted) return;
    setState(() => _generating = false);

    if (polygonMm.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Could not reconstruct a room polygon. Capture more walls and try again.'),
      ));
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ARResultScreen(polygonMm: polygonMm)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final captured = _walls.length;
    final needed = (3 - captured).clamp(0, 3);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('AR Room Scan'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_walls.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Clear all walls',
              onPressed: () => setState(() => _walls.clear()),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── AR camera (handles camera permission internally) ───────────
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
            permissionPromptDescription:
                'Camera access is needed for AR room scanning.',
            permissionPromptButtonText: 'Grant Camera Access',
          ),

          // ── Instruction banner (pulsing) ─────────────────────────────
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Opacity(
                opacity: _pulseAnim.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app,
                          color: Colors.cyanAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          captured == 0
                              ? 'Move slowly — coloured overlays show detected surfaces.'
                                  '\nTap each wall surface to capture it.'
                              : '$captured wall${captured == 1 ? '' : 's'} captured.'
                                  '${needed > 0 ? ' Tap $needed more wall${needed == 1 ? '' : 's'}.' : ' Ready to generate!'}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Plane count indicator (top-left, small) ──────────────────
          if (_detectedPlaneCount > 0)
            Positioned(
              top: 90,
              left: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$_detectedPlaneCount surface${_detectedPlaneCount == 1 ? '' : 's'} detected',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ),

          // ── Captured wall chips (top-right, tap to remove) ───────────
          if (_walls.isNotEmpty)
            Positioned(
              top: 86,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < _walls.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GestureDetector(
                        onTap: () => _removeWall(i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.shade600.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Wall ${i + 1}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.close,
                                  color: Colors.white, size: 14),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ── Bottom generate button ────────────────────────────────────
          Positioned(
            bottom: 32,
            left: 18,
            right: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (needed > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Tap $needed more wall${needed == 1 ? '' : 's'} to enable generation',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: captured >= 3 && !_generating
                        ? _generatePlan
                        : null,
                    icon: _generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.map_outlined),
                    label: Text(
                      _generating ? 'Calculating…' : 'Generate Floor Plan',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white24,
                      disabledForegroundColor: Colors.white38,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
