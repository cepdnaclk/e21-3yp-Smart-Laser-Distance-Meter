// lib/sketch/room_3d_screen.dart

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'room_object.dart';
import 'sketch_constants.dart';
import '../ble/ble_manager.dart';

class Room3DScreen extends StatefulWidget {
  final List<Offset> points;
  final List<RoomObject> roomObjects;
  final Map<int, double> wallRealMm;
  final BleManager? bleManager;

  const Room3DScreen({
    super.key,
    required this.points,
    required this.roomObjects,
    required this.wallRealMm,
    this.bleManager,
  });

  @override
  State<Room3DScreen> createState() => _Room3DScreenState();
}

class _Room3DScreenState extends State<Room3DScreen> {
  double _rotX = 0.45;  // radians — tilt (looking slightly down)
  double _rotY = 0.3;   // radians — horizontal spin
  double _zoom = 1.0;
  Offset _panOffset = Offset.zero;

  double _lastRotX = 0.45;
  double _lastRotY = 0.3;
  double _lastZoom = 1.0;
  Offset _lastPanOffset = Offset.zero;

  int? _selectedWallIndex;
  bool _waitingForBle = false;

  static const double _wallHeightMm = 2400;
  static const double _mmScale = 0.18; // mm → logical pixels for 3D view

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: const Color(0xFFCCDDEE),
        title: const Text('3D Room View',
            style: TextStyle(fontFamily: 'monospace', fontSize: 15)),
        actions: [
          if (_selectedWallIndex != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _waitingForBle
                  ? const Row(children: [
                      SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF00AAFF))),
                      SizedBox(width: 8),
                      Text('Waiting…',
                          style: TextStyle(
                              color: Color(0xFF00AAFF), fontFamily: 'monospace')),
                    ])
                  : TextButton.icon(
                      icon: const Icon(Icons.bluetooth,
                          color: Color(0xFF00AAFF), size: 16),
                      label: Text(
                        'Measure wall ${_selectedWallIndex! + 1}',
                        style: const TextStyle(
                            color: Color(0xFF00AAFF),
                            fontFamily: 'monospace',
                            fontSize: 12),
                      ),
                      onPressed: _triggerBleMeasurement,
                    ),
            ),
        ],
      ),
      body: Stack(children: [
        GestureDetector(
          onScaleStart: (d) {
            _lastRotX = _rotX;
            _lastRotY = _rotY;
            _lastZoom = _zoom;
            _lastPanOffset = _panOffset;
          },
          onScaleUpdate: (d) {
            setState(() {
              if (d.pointerCount == 1) {
                // Single finger: rotate
                _rotY = _lastRotY + d.focalPointDelta.dx * 0.01;
                _rotX = (_lastRotX - d.focalPointDelta.dy * 0.008)
                    .clamp(0.05, math.pi / 2);
              } else {
                // Two fingers: zoom + pan
                _zoom = (_lastZoom * d.scale).clamp(0.3, 5.0);
                _panOffset = _lastPanOffset + d.focalPointDelta;
              }
            });
          },
          child: CustomPaint(
            painter: _Room3DPainter(
              points: widget.points,
              roomObjects: widget.roomObjects,
              wallRealMm: widget.wallRealMm,
              rotX: _rotX,
              rotY: _rotY,
              zoom: _zoom,
              panOffset: _panOffset,
              selectedWallIndex: _selectedWallIndex,
              wallHeightMm: _wallHeightMm,
              mmScale: _mmScale,
              onWallTap: (i) => setState(() =>
                  _selectedWallIndex = _selectedWallIndex == i ? null : i),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Text(
                _selectedWallIndex == null
                    ? '1 finger = rotate  •  2 fingers = zoom/pan  •  tap wall to select'
                    : 'Wall ${_selectedWallIndex! + 1} selected — tap "Measure" or tap wall again to deselect',
                style: const TextStyle(
                    color: Color(0xFF778899),
                    fontFamily: 'monospace',
                    fontSize: 11),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  void _triggerBleMeasurement() {
    if (_selectedWallIndex == null || widget.bleManager == null) return;
    setState(() => _waitingForBle = true);
    widget.bleManager!.packetStream.first.then((packet) {
      if (!mounted) return;
      setState(() {
        _waitingForBle = false;
        // You can store this back to wallRealMm via a callback if needed
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Wall ${_selectedWallIndex! + 1}: ${packet.distanceMm.toStringAsFixed(0)} mm',
            style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: const Color(0xFF003311),
      ));
    });
  }
}

// ── 3D Painter ────────────────────────────────────────────────────────────
class _Room3DPainter extends CustomPainter {
  final List<Offset> points;
  final List<RoomObject> roomObjects;
  final Map<int, double> wallRealMm;
  final double rotX;
  final double rotY;
  final double zoom;
  final Offset panOffset;
  final int? selectedWallIndex;
  final double wallHeightMm;
  final double mmScale;
  final void Function(int) onWallTap;

  // Store wall polygons for hit-testing
  final List<List<Offset>> _wallPolygons = [];

  _Room3DPainter({
    required this.points,
    required this.roomObjects,
    required this.wallRealMm,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.panOffset,
    required this.selectedWallIndex,
    required this.wallHeightMm,
    required this.mmScale,
    required this.onWallTap,
  });

  // Project a 3D point [x, y, z] to 2D screen offset
  Offset _project(double x, double y, double z, Size size) {
    // Rotate around Y axis
    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final x1 = x * cosY - z * sinY;
    final z1 = x * sinY + z * cosY;

    // Rotate around X axis
    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final y2 = y * cosX - z1 * sinX;
    final z2 = y * sinX + z1 * cosX;

    // Simple perspective
    const fov = 700.0;
    final perspective = fov / (fov + z2 + 500);

    return Offset(
      size.width / 2 + x1 * perspective * zoom + panOffset.dx,
      size.height / 2 + y2 * perspective * zoom + panOffset.dy,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _wallPolygons.clear();

    // Centre the room model
    double cx = 0, cy = 0;
    for (final p in points) {
      cx += p.dx * mmPerUnit;
      cy += p.dy * mmPerUnit;
    }
    cx /= points.length;
    cy /= points.length;

    final int n = points.length;

    // Draw floor
    final floorPath = Path();
    bool firstFloor = true;
    for (final p in points) {
      final s = _project(
          (p.dx * mmPerUnit - cx) * mmScale,
          0,
          (p.dy * mmPerUnit - cy) * mmScale,
          size);
      if (firstFloor) { floorPath.moveTo(s.dx, s.dy); firstFloor = false; }
      else {
        floorPath.lineTo(s.dx, s.dy);
      }
    }
    floorPath.close();
    canvas.drawPath(floorPath,
        Paint()..color = const Color(0xFF1A2230)..style = PaintingStyle.fill);
    canvas.drawPath(floorPath,
        Paint()..color = const Color(0xFF30363D)
          ..style = PaintingStyle.stroke..strokeWidth = 1.0);

    // Draw walls
    for (int i = 0; i < n; i++) {
      final Offset a = points[i];
      final Offset b = points[(i + 1) % n];
      final bool isSelected = i == selectedWallIndex;

      final s0 = _project((a.dx * mmPerUnit - cx) * mmScale, 0,
          (a.dy * mmPerUnit - cy) * mmScale, size);
      final s1 = _project((b.dx * mmPerUnit - cx) * mmScale, 0,
          (b.dy * mmPerUnit - cy) * mmScale, size);
      final s2 = _project((b.dx * mmPerUnit - cx) * mmScale,
          -wallHeightMm * mmScale,
          (b.dy * mmPerUnit - cy) * mmScale, size);
      final s3 = _project((a.dx * mmPerUnit - cx) * mmScale,
          -wallHeightMm * mmScale,
          (a.dy * mmPerUnit - cy) * mmScale, size);

      _wallPolygons.add([s0, s1, s2, s3]);

      final wallPath = Path()
        ..moveTo(s0.dx, s0.dy)
        ..lineTo(s1.dx, s1.dy)
        ..lineTo(s2.dx, s2.dy)
        ..lineTo(s3.dx, s3.dy)
        ..close();

      canvas.drawPath(
        wallPath,
        Paint()
          ..color = isSelected
              ? const Color(0xFF1A3A5C)
              : const Color(0xFF161B22)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        wallPath,
        Paint()
          ..color = isSelected
              ? const Color(0xFF00AAFF)
              : const Color(0xFF30363D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.0 : 1.0,
      );

      // Wall label
      final mid = Offset((s0.dx + s1.dx) / 2, (s0.dy + s1.dy) / 2);
      final labelMid = Offset((mid.dx + (s2.dx + s3.dx) / 2) / 2,
          (mid.dy + (s2.dy + s3.dy) / 2) / 2);
      final lenMm = wallRealMm[i] ??
          ((b - a).distance * mmPerUnit);
      final label = lenMm >= 1000
          ? '${(lenMm / 1000).toStringAsFixed(2)} m'
          : '${lenMm.toStringAsFixed(0)} mm';

      final tp = TextPainter(
        text: TextSpan(
          text: 'W${i + 1}  $label',
          style: TextStyle(
            color: isSelected
                ? const Color(0xFF00AAFF)
                : const Color(0xFF556677),
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(
          labelMid.dx - tp.width / 2, labelMid.dy - tp.height / 2));
    }
  }

  @override
  bool hitTest(Offset position) {
    // Check if any wall was tapped
    for (int i = 0; i < _wallPolygons.length; i++) {
      if (_pointInPolygon(position, _wallPolygons[i])) {
        onWallTap(i);
        return true;
      }
    }
    return false;
  }

  bool _pointInPolygon(Offset p, List<Offset> poly) {
    bool inside = false;
    int j = poly.length - 1;
    for (int i = 0; i < poly.length; i++) {
      if (((poly[i].dy > p.dy) != (poly[j].dy > p.dy)) &&
          (p.dx < (poly[j].dx - poly[i].dx) *
                  (p.dy - poly[i].dy) /
                  (poly[j].dy - poly[i].dy) +
              poly[i].dx)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  @override
  bool shouldRepaint(_Room3DPainter old) => true;
}