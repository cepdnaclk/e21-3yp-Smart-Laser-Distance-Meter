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

  final void Function(int wallIndex, double mm)? onWallMeasured;
  final double initialHeightMm;
  final void Function(double heightMm)? onHeightChanged;

  const Room3DScreen({
    super.key,
    required this.points,
    required this.roomObjects,
    required this.wallRealMm,
    this.bleManager,
    this.onWallMeasured,
    this.initialHeightMm = 2400,
    this.onHeightChanged,
  });

  @override
  State<Room3DScreen> createState() => _Room3DScreenState();
}

class _Room3DScreenState extends State<Room3DScreen> {
  double _rotX = 1.1;   // steep top-down angle like reference image
  double _rotY = 0.6;   // slight horizontal rotation to show depth
  double _zoom = 0.7;   // zoom out so full room is visible
  Offset _panOffset = Offset.zero;

  double _lastRotX = 1.1;
  double _lastRotY = 0.6;
  double _lastZoom = 0.7;
  Offset _lastPanOffset = Offset.zero;

  int? _selectedWallIndex;
  bool _waitingForBle = false;

  // Wall polygons stored here (mutable, updated by painter each frame)
  final List<List<Offset>> _wallPolygons = [];

  // View options
  bool _showCeiling = false;
  bool _showDimensions = true;

  late double _wallHeightMm;
  static const double _mmScale = 0.10;

  @override
  void initState() {
    super.initState();
    _wallHeightMm = widget.initialHeightMm;
  }

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
          // Room height input
          TextButton.icon(
            icon: const Icon(Icons.height,
                color: Color(0xFF00AA66), size: 16),
            label: Text(
              '${(_wallHeightMm / 1000).toStringAsFixed(2)} m',
              style: const TextStyle(
                  color: Color(0xFF00AA66),
                  fontFamily: 'monospace',
                  fontSize: 12),
            ),
            onPressed: _editHeight,
          ),
          // Reset camera
          IconButton(
            icon: const Icon(Icons.center_focus_strong,
                color: Color(0xFF556677), size: 20),
            tooltip: 'Reset view',
            onPressed: () => setState(() {
              _rotX = 1.1;
              _rotY = 0.6;
              _zoom = 0.7;
              _panOffset = Offset.zero;
            }),
          ),
          // Toggle ceiling
          IconButton(
            icon: Icon(
              _showCeiling ? Icons.roofing : Icons.roofing_outlined,
              color: _showCeiling
                  ? const Color(0xFF00AAFF)
                  : const Color(0xFF556677),
              size: 20,
            ),
            tooltip: _showCeiling ? 'Hide ceiling' : 'Show ceiling',
            onPressed: () => setState(() => _showCeiling = !_showCeiling),
          ),
          // Toggle dimensions
          IconButton(
            icon: Icon(
              Icons.straighten,
              color: _showDimensions
                  ? const Color(0xFF00AAFF)
                  : const Color(0xFF556677),
              size: 20,
            ),
            tooltip:
                _showDimensions ? 'Hide dimensions' : 'Show dimensions',
            onPressed: () =>
                setState(() => _showDimensions = !_showDimensions),
          ),
          // BLE measure button
          if (_selectedWallIndex != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _waitingForBle
                  ? const Row(children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00AAFF))),
                      SizedBox(width: 8),
                      Text('Waiting…',
                          style: TextStyle(
                              color: Color(0xFF00AAFF),
                              fontFamily: 'monospace')),
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
          onTapUp: (details) {
            // Hit-test stored wall polygons
            bool hit = false;
            for (int i = 0; i < _wallPolygons.length; i++) {
              if (_pointInPolygon(
                  details.localPosition, _wallPolygons[i])) {
                setState(() => _selectedWallIndex =
                    _selectedWallIndex == i ? null : i);
                hit = true;
                break;
              }
            }
            if (!hit) setState(() => _selectedWallIndex = null);
          },
          onScaleStart: (d) {
            _lastRotX = _rotX;
            _lastRotY = _rotY;
            _lastZoom = _zoom;
            _lastPanOffset = _panOffset;
          },
          onScaleUpdate: (d) {
            setState(() {
              if (d.pointerCount == 1) {
                _rotY = _lastRotY + d.focalPointDelta.dx * 0.01;
                _rotX = (_lastRotX - d.focalPointDelta.dy * 0.008)
                    .clamp(0.05, math.pi / 2);
              } else {
                _zoom = (_lastZoom * d.scale).clamp(0.3, 5.0);
                _panOffset = _lastPanOffset + d.focalPointDelta;
              }
            });
          },
          child: RepaintBoundary(
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
                wallPolygons: _wallPolygons,
                showCeiling: _showCeiling,
                showDimensions: _showDimensions,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),

        // ── Legend / info bar ─────────────────────────────────────────
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Text(
                _selectedWallIndex == null
                    ? '1 finger = rotate  •  2 fingers = zoom / pan  •  tap wall to select'
                    : 'Wall ${_selectedWallIndex! + 1} selected'
                        '${widget.bleManager != null ? '  —  tap "Measure" to use laser' : ''}',
                style: const TextStyle(
                    color: Color(0xFF778899),
                    fontFamily: 'monospace',
                    fontSize: 11),
              ),
            ),
          ),
        ),

        // ── Object legend (top-left) ──────────────────────────────────
        if (widget.roomObjects.isNotEmpty)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22).withOpacity(0.9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legendDot(const Color(0xFF8B4513), 'Door'),
                  const SizedBox(height: 4),
                  _legendDot(const Color(0xFF4FC3F7), 'Window'),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: Color(0xFF778899),
                fontFamily: 'monospace',
                fontSize: 10)),
      ],
    );
  }

  bool _pointInPolygon(Offset p, List<Offset> poly) {
    bool inside = false;
    int j = poly.length - 1;
    for (int i = 0; i < poly.length; i++) {
      if (((poly[i].dy > p.dy) != (poly[j].dy > p.dy)) &&
          (p.dx <
              (poly[j].dx - poly[i].dx) *
                      (p.dy - poly[i].dy) /
                      (poly[j].dy - poly[i].dy) +
                  poly[i].dx)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  Future<void> _editHeight() async {
    final ctrl = TextEditingController(
      text: (_wallHeightMm / 1000).toStringAsFixed(3),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A3A),
        title: const Text(
          'Room height',
          style: TextStyle(
              color: Color(0xFFCCDDEE),
              fontFamily: 'monospace',
              fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the real height of the room walls.',
              style: TextStyle(
                  color: Color(0xFF556677),
                  fontFamily: 'monospace',
                  fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                suffixText: 'm',
                suffixStyle: TextStyle(color: Color(0xFF00AA66)),
                hintText: 'e.g. 2.400',
                hintStyle: TextStyle(color: Color(0xFF445566)),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF334466))),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00AA66))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL',
                style: TextStyle(
                    color: Color(0xFF778899),
                    fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v != null && v > 0.5 && v < 20.0) {
                setState(() => _wallHeightMm = v * 1000);
                widget.onHeightChanged?.call(v * 1000);
              }
              Navigator.pop(ctx);
            },
            child: const Text('APPLY',
                style: TextStyle(
                    color: Color(0xFF00AA66),
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  void _triggerBleMeasurement() {
    if (_selectedWallIndex == null || widget.bleManager == null) return;
    final wallIdx = _selectedWallIndex!;
    setState(() => _waitingForBle = true);

    widget.bleManager!.packetStream
        .where((p) => !p.isCapturing && p.distanceMm > 0)
        .first
        .then((packet) {
      if (!mounted) return;
      final mm = packet.distanceMm;
      setState(() {
        _waitingForBle = false;
        widget.wallRealMm[wallIdx] = mm;
        _selectedWallIndex = null;
      });
      widget.onWallMeasured?.call(wallIdx, mm);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Wall ${wallIdx + 1}: ${mm.toStringAsFixed(0)} mm — updated!',
            style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: const Color(0xFF003311),
      ));
    });
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 3D Painter
// ════════════════════════════════════════════════════════════════════════════
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
  final List<List<Offset>> wallPolygons;
  final bool showCeiling;
  final bool showDimensions;

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
    required this.wallPolygons,
    required this.showCeiling,
    required this.showDimensions,
  });

  // ── Project 3D → 2D ───────────────────────────────────────────────────────
  Offset _project(double x, double y, double z, Size size) {
    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final x1 = x * cosY - z * sinY;
    final z1 = x * sinY + z * cosY;

    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final y2 = y * cosX - z1 * sinX;
    final z2 = y * sinX + z1 * cosX;

    const fov = 700.0;
    final perspective = fov / (fov + z2 + 500);

    return Offset(
      size.width / 2 + x1 * perspective * zoom + panOffset.dx,
      size.height / 2 + y2 * perspective * zoom + panOffset.dy,
    );
  }

  // ── Convenience: world point → screen ────────────────────────────────────
  Offset _w(double wx, double wy, double wz, Size size) =>
      _project(wx, wy, wz, size);

  @override
  void paint(Canvas canvas, Size size) {
    wallPolygons.clear();

    // Centre the model
    double cx = 0, cy = 0;
    for (final p in points) {
      cx += p.dx * mmPerUnit;
      cy += p.dy * mmPerUnit;
    }
    cx /= points.length;
    cy /= points.length;

    final int n = points.length;
    final double H = wallHeightMm * mmScale; // wall height in draw units

    // Helper: world mm → centred draw coords
    double wx(double worldX) => (worldX * mmPerUnit - cx) * mmScale;
    double wz(double worldZ) => (worldZ * mmPerUnit - cy) * mmScale;

    // ── 1. Floor ─────────────────────────────────────────────────────────
    final floorPath = Path();
    for (int i = 0; i < n; i++) {
      final s = _project(wx(points[i].dx), 0, wz(points[i].dy), size);
      if (i == 0) floorPath.moveTo(s.dx, s.dy);
      else floorPath.lineTo(s.dx, s.dy);
    }
    floorPath.close();
    canvas.drawPath(
        floorPath,
        Paint()
          ..color = const Color(0xFFB0B8C0)  // light grey floor
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        floorPath,
        Paint()
          ..color = const Color(0xFF666666)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // ── 2. Walls — sorted back to front (painter's algorithm) ────────────
    // Compute centre depth of each wall for sorting
    final wallOrder = List.generate(n, (i) {
      final Offset a = points[i];
      final Offset b = points[(i + 1) % n];
      final double midX = (wx(a.dx) + wx(b.dx)) / 2;
      final double midZ = (wz(a.dy) + wz(b.dy)) / 2;
      // Apply Y rotation to get depth (z after rotation)
      final double depth = midX * math.sin(rotY) + midZ * math.cos(rotY);
      return MapEntry(i, depth);
    });
    wallOrder.sort((a, b) => b.value.compareTo(a.value)); // far first

    for (final entry in wallOrder) {
      final int i = entry.key;
      final Offset a = points[i];
      final Offset b = points[(i + 1) % n];
      final bool isSelected = i == selectedWallIndex;

      final s0 = _project(wx(a.dx), 0, wz(a.dy), size);
      final s1 = _project(wx(b.dx), 0, wz(b.dy), size);
      final s2 = _project(wx(b.dx), -H, wz(b.dy), size);
      final s3 = _project(wx(a.dx), -H, wz(a.dy), size);

      wallPolygons.add([s0, s1, s2, s3]);

      final wallPath = Path()
        ..moveTo(s0.dx, s0.dy)
        ..lineTo(s1.dx, s1.dy)
        ..lineTo(s2.dx, s2.dy)
        ..lineTo(s3.dx, s3.dy)
        ..close();

      // Wall fill — simulate lighting: walls facing viewer are lighter
      final double depth = entry.value;
      final int lightness = (180 + (depth * 8).clamp(-60, 60)).toInt()
          .clamp(100, 240);
      final wallColor = Color.fromARGB(255, lightness, lightness, lightness);
      canvas.drawPath(
          wallPath,
          Paint()
            ..color = isSelected
                ? const Color(0xFF4A90D9).withOpacity(0.85)
                : wallColor.withOpacity(0.85)
            ..style = PaintingStyle.fill);
      canvas.drawPath(
          wallPath,
          Paint()
            ..color = isSelected
                ? const Color(0xFF00AAFF)
                : const Color(0xFF888888)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2.5 : 1.2);

      // ── Wall dimension label ────────────────────────────────────────
      if (showDimensions) {
        final mid = Offset((s0.dx + s1.dx) / 2, (s0.dy + s1.dy) / 2);
        final topMid = Offset((s2.dx + s3.dx) / 2, (s2.dy + s3.dy) / 2);
        final labelPos = Offset(
          (mid.dx + topMid.dx) / 2,
          (mid.dy + topMid.dy) / 2,
        );
        final lenMm =
            wallRealMm[i] ?? ((b - a).distance * mmPerUnit);
        final label = lenMm >= 1000
            ? '${(lenMm / 1000).toStringAsFixed(2)} m'
            : '${lenMm.toStringAsFixed(0)} mm';

        final tp = TextPainter(
          text: TextSpan(
            text: 'W${i + 1}  $label',
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFF00AAFF)
                  : const Color(0xFF4A5568),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2));
      }
    }

    // ── 3. Doors and windows ──────────────────────────────────────────────
    for (final obj in roomObjects) {
      if (obj.wallIndex >= n) continue;

      final Offset a = points[obj.wallIndex];
      final Offset b = points[(obj.wallIndex + 1) % n];

      // Object centre along wall (world coords)
      final double ocx = a.dx + obj.positionAlong * (b.dx - a.dx);
      final double ocy = a.dy + obj.positionAlong * (b.dy - a.dy);

      // Wall direction unit vector (world)
      final double dxW = b.dx - a.dx;
      final double dyW = b.dy - a.dy;
      final double wallLen = math.sqrt(dxW * dxW + dyW * dyW);
      if (wallLen < 1) continue;
      final double udx = dxW / wallLen;
      final double udy = dyW / wallLen;

      // Object half-width in world units
      final double halfWW = (obj.widthMm / mmPerUnit) / 2;
      // Object height in draw units
      final double objH = (obj.heightMm * mmScale);
      // Object elevation in draw units (distance from floor)
      final double elevDraw = obj.elevationMm * mmScale;

      // Four corners of the opening (bottom-left, bottom-right, top-right, top-left)
      // in world space, then projected
      final double lx = ocx - udx * halfWW;
      final double ly = ocy - udy * halfWW;
      final double rx = ocx + udx * halfWW;
      final double ry = ocy + udy * halfWW;

      final Offset bl = _project(wx(lx), -elevDraw, wz(ly), size);
      final Offset br = _project(wx(rx), -elevDraw, wz(ry), size);
      final Offset tr = _project(wx(rx), -(elevDraw + objH), wz(ry), size);
      final Offset tl = _project(wx(lx), -(elevDraw + objH), wz(ly), size);

      if (obj.isDoor) {
        _drawDoor3D(canvas, bl, br, tr, tl);
      } else {
        _drawWindow3D(canvas, bl, br, tr, tl);
      }
    }

    // ── 4. Ceiling (optional) ─────────────────────────────────────────────
    if (showCeiling) {
      final ceilPath = Path();
      for (int i = 0; i < n; i++) {
        final s = _project(wx(points[i].dx), -H, wz(points[i].dy), size);
        if (i == 0) ceilPath.moveTo(s.dx, s.dy);
        else ceilPath.lineTo(s.dx, s.dy);
      }
      ceilPath.close();
      canvas.drawPath(
          ceilPath,
          Paint()
            ..color = const Color(0xFF161B22).withOpacity(0.7)
            ..style = PaintingStyle.fill);
      canvas.drawPath(
          ceilPath,
          Paint()
            ..color = const Color(0xFF2D3748)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
    }

    // ── 5. Corner dots ────────────────────────────────────────────────────
    for (int i = 0; i < n; i++) {
      final s = _project(wx(points[i].dx), 0, wz(points[i].dy), size);
      canvas.drawCircle(
          s,
          3.5,
          Paint()
            ..color = i == 0
                ? const Color(0xFF48BB78)
                : const Color(0xFF4299E1));
    }
  }

  // ── Draw a door opening in 3D ─────────────────────────────────────────────
  void _drawDoor3D(Canvas canvas, Offset bl, Offset br, Offset tr, Offset tl) {
    // Dark hole (opening)
    final holePath = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(tl.dx, tl.dy)
      ..close();
    canvas.drawPath(holePath,
        Paint()..color = const Color(0xFF0A0E14)..style = PaintingStyle.fill);

    // Brown door panel (slightly inset — offset toward viewer)
    // We approximate inset by scaling toward centre
    Offset inset(Offset p, Offset centre, double f) =>
        Offset(p.dx + (centre.dx - p.dx) * f,
               p.dy + (centre.dy - p.dy) * f);
    final centre = Offset(
        (bl.dx + br.dx + tr.dx + tl.dx) / 4,
        (bl.dy + br.dy + tr.dy + tl.dy) / 4);
    const double ins = 0.05;
    final dbl = inset(bl, centre, ins);
    final dbr = inset(br, centre, ins);
    final dtr = inset(tr, centre, ins);
    final dtl = inset(tl, centre, ins);

    final doorPath = Path()
      ..moveTo(dbl.dx, dbl.dy)
      ..lineTo(dbr.dx, dbr.dy)
      ..lineTo(dtr.dx, dtr.dy)
      ..lineTo(dtl.dx, dtl.dy)
      ..close();
    canvas.drawPath(doorPath,
        Paint()..color = const Color(0xFF8B4513)..style = PaintingStyle.fill);
    canvas.drawPath(doorPath,
        Paint()
          ..color = const Color(0xFF5C2E00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    // Door frame (outline of opening)
    canvas.drawPath(holePath,
        Paint()
          ..color = const Color(0xFF4A3728)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // Door knob — small circle near right edge
    final knobPos = Offset(
        dbr.dx + (dbl.dx - dbr.dx) * 0.15,
        dbr.dy + (dtl.dy - dbl.dy) * 0.45);
    canvas.drawCircle(knobPos, 3,
        Paint()..color = const Color(0xFFFFD700));
  }

  // ── Draw a window opening in 3D ───────────────────────────────────────────
  void _drawWindow3D(Canvas canvas, Offset bl, Offset br, Offset tr, Offset tl) {
    // Dark hole (opening)
    final holePath = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(tl.dx, tl.dy)
      ..close();
    canvas.drawPath(holePath,
        Paint()..color = const Color(0xFF0A0E14)..style = PaintingStyle.fill);

    // Sky blue glass fill
    canvas.drawPath(holePath,
        Paint()
          ..color = const Color(0xFF4FC3F7).withOpacity(0.25)
          ..style = PaintingStyle.fill);

    // Window frame (outer border)
    canvas.drawPath(holePath,
        Paint()
          ..color = const Color(0xFF90A4AE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // Cross dividers (horizontal + vertical midline)
    final midTop = Offset((tl.dx + tr.dx) / 2, (tl.dy + tr.dy) / 2);
    final midBot = Offset((bl.dx + br.dx) / 2, (bl.dy + br.dy) / 2);
    final midLeft = Offset((tl.dx + bl.dx) / 2, (tl.dy + bl.dy) / 2);
    final midRight = Offset((tr.dx + br.dx) / 2, (tr.dy + br.dy) / 2);

    final crossPaint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..strokeWidth = 1.5;

    canvas.drawLine(midTop, midBot, crossPaint);  // vertical
    canvas.drawLine(midLeft, midRight, crossPaint); // horizontal

    // Glass highlight (thin bright line near top-left)
    final hiPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(tl.dx + (tr.dx - tl.dx) * 0.1, tl.dy + (tr.dy - tl.dy) * 0.1),
      Offset(bl.dx + (br.dx - bl.dx) * 0.1, bl.dy + (br.dy - bl.dy) * 0.1),
      hiPaint,
    );
  }

  @override
  bool shouldRepaint(_Room3DPainter old) =>
      old.rotX != rotX ||
      old.rotY != rotY ||
      old.zoom != zoom ||
      old.panOffset != panOffset ||
      old.selectedWallIndex != selectedWallIndex ||
      old.showCeiling != showCeiling ||
      old.showDimensions != showDimensions ||
      old.roomObjects.length != roomObjects.length;
}