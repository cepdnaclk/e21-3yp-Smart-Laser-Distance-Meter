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
            // Only zoom needs the start value; rotation/pan accumulate incrementally
            _lastZoom = _zoom;
          },
          onScaleUpdate: (d) {
            setState(() {
              if (d.pointerCount == 1) {
                // Accumulate rotation incrementally from each event's delta
                _rotY += d.focalPointDelta.dx * 0.01;
                _rotX = (_rotX - d.focalPointDelta.dy * 0.008)
                    .clamp(0.05, math.pi / 2);
              } else {
                // Zoom is relative to gesture start; pan accumulates incrementally
                _zoom = (_lastZoom * d.scale).clamp(0.3, 5.0);
                _panOffset += d.focalPointDelta;
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
    // Pre-size the list so index = actual wall index (not painter order)
    wallPolygons.clear();
    for (int k = 0; k < points.length; k++) wallPolygons.add([]);

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

    // ── Pre-compute inward normals (reused by door/window section) ────────
    const double wallThickMm = 200.0;
    final double wallThickW  = wallThickMm / mmPerUnit;
    final double cxWorld = cx / mmPerUnit;
    final double cyWorld = cy / mmPerUnit;
    final List<Offset> wallNormals = List.filled(n, Offset.zero);
    for (int k = 0; k < n; k++) {
      final Offset pa = points[k];
      final Offset pb = points[(k + 1) % n];
      final double dxW = pb.dx - pa.dx;
      final double dyW = pb.dy - pa.dy;
      final double len = math.sqrt(dxW * dxW + dyW * dyW);
      if (len < 1e-6) continue;
      double nx = dyW / len;
      double ny = -dxW / len;
      final double mx = (pa.dx + pb.dx) / 2;
      final double my = (pa.dy + pb.dy) / 2;
      if ((cxWorld - mx) * nx + (cyWorld - my) * ny < 0) {
        nx = -nx;
        ny = -ny;
      }
      wallNormals[k] = Offset(nx, ny);
    }

    for (final entry in wallOrder) {
      final int i = entry.key;
      final Offset a = points[i];
      final Offset b = points[(i + 1) % n];
      final bool isSelected = i == selectedWallIndex;
      final Offset norm = wallNormals[i];

      // Outer face corners
      final s0 = _project(wx(a.dx), 0,  wz(a.dy), size);
      final s1 = _project(wx(b.dx), 0,  wz(b.dy), size);
      final s2 = _project(wx(b.dx), -H, wz(b.dy), size);
      final s3 = _project(wx(a.dx), -H, wz(a.dy), size);

      wallPolygons[i] = [s0, s1, s2, s3];

      // Inner face corners (inset by wall thickness)
      final si0 = _project(wx(a.dx + norm.dx * wallThickW), 0,  wz(a.dy + norm.dy * wallThickW), size);
      final si1 = _project(wx(b.dx + norm.dx * wallThickW), 0,  wz(b.dy + norm.dy * wallThickW), size);
      final si2 = _project(wx(b.dx + norm.dx * wallThickW), -H, wz(b.dy + norm.dy * wallThickW), size);
      final si3 = _project(wx(a.dx + norm.dx * wallThickW), -H, wz(a.dy + norm.dy * wallThickW), size);

      // Depth-based lightness for each face
      final double depth = entry.value;
      final int outerL = (180 + (depth * 8).clamp(-60.0, 60.0)).toInt().clamp(100, 240);
      final int topL   = (outerL + 35).clamp(100, 255);
      final int innerL = (outerL - 45).clamp(60,  200);
      final outerCol = Color.fromARGB(255, outerL, outerL, outerL);
      final topCol   = Color.fromARGB(255, topL,   topL,   topL);
      final innerCol = Color.fromARGB(255, innerL, innerL, innerL);
      final stroke   = isSelected ? const Color(0xFF00AAFF) : const Color(0xFF888888);
      final strokeW  = isSelected ? 2.5 : 1.2;

      // 1. Inner face (faces room interior — darkest)
      final innerPath = Path()
        ..moveTo(si0.dx, si0.dy)
        ..lineTo(si1.dx, si1.dy)
        ..lineTo(si2.dx, si2.dy)
        ..lineTo(si3.dx, si3.dy)
        ..close();
      canvas.drawPath(innerPath,
          Paint()
            ..color = (isSelected ? const Color(0xFF2A5F8A) : innerCol).withOpacity(0.9)
            ..style = PaintingStyle.fill);
      canvas.drawPath(innerPath,
          Paint()..color = stroke..style = PaintingStyle.stroke..strokeWidth = strokeW);

      // 2. Top face (faces up — lightest, most visible from above)
      final topPath = Path()
        ..moveTo(s3.dx,  s3.dy)
        ..lineTo(s2.dx,  s2.dy)
        ..lineTo(si2.dx, si2.dy)
        ..lineTo(si3.dx, si3.dy)
        ..close();
      canvas.drawPath(topPath,
          Paint()
            ..color = (isSelected ? const Color(0xFF5AAAE0) : topCol).withOpacity(0.95)
            ..style = PaintingStyle.fill);
      canvas.drawPath(topPath,
          Paint()..color = stroke..style = PaintingStyle.stroke..strokeWidth = strokeW);

      // 3. Outer face (faces outside — mid brightness)
      final wallPath = Path()
        ..moveTo(s0.dx, s0.dy)
        ..lineTo(s1.dx, s1.dy)
        ..lineTo(s2.dx, s2.dy)
        ..lineTo(s3.dx, s3.dy)
        ..close();
      canvas.drawPath(wallPath,
          Paint()
            ..color = (isSelected ? const Color(0xFF4A90D9) : outerCol).withOpacity(0.85)
            ..style = PaintingStyle.fill);
      canvas.drawPath(wallPath,
          Paint()..color = stroke..style = PaintingStyle.stroke..strokeWidth = strokeW);

      // ── Doors and windows on this wall (drawn right after the wall ──────
      // so painter's algorithm keeps them behind closer walls)
      for (final obj in roomObjects) {
        if (obj.wallIndex != i) continue;

        final double ocx = a.dx + obj.positionAlong * (b.dx - a.dx);
        final double ocy = a.dy + obj.positionAlong * (b.dy - a.dy);

        final double dxW2    = b.dx - a.dx;
        final double dyW2    = b.dy - a.dy;
        final double wallLen = math.sqrt(dxW2 * dxW2 + dyW2 * dyW2);
        if (wallLen < 1) continue;
        final double udx = dxW2 / wallLen;
        final double udy = dyW2 / wallLen;

        final double halfWW   = (obj.widthMm / mmPerUnit) / 2;
        final double objH2    = obj.heightMm * mmScale;
        final double elevDraw = obj.elevationMm * mmScale;

        final double lx = ocx - udx * halfWW;
        final double ly = ocy - udy * halfWW;
        final double rx = ocx + udx * halfWW;
        final double ry = ocy + udy * halfWW;

        final obl = _project(wx(lx), -elevDraw,           wz(ly), size);
        final obr = _project(wx(rx), -elevDraw,           wz(ry), size);
        final otr = _project(wx(rx), -(elevDraw + objH2), wz(ry), size);
        final otl = _project(wx(lx), -(elevDraw + objH2), wz(ly), size);

        final ilx = lx + norm.dx * wallThickW;
        final ily = ly + norm.dy * wallThickW;
        final irx = rx + norm.dx * wallThickW;
        final iry = ry + norm.dy * wallThickW;

        final ibl = _project(wx(ilx), -elevDraw,           wz(ily), size);
        final ibr = _project(wx(irx), -elevDraw,           wz(iry), size);
        final itr = _project(wx(irx), -(elevDraw + objH2), wz(iry), size);
        final itl = _project(wx(ilx), -(elevDraw + objH2), wz(ily), size);

        if (obj.isDoor) {
          _drawDoor3D(canvas, obl, obr, otr, otl, ibl, ibr, itr, itl);
        } else {
          _drawWindow3D(canvas, obl, obr, otr, otl, ibl, ibr, itr, itl);
        }
      }

      // ── Wall dimension label ──────────────────────────────────────────
      if (showDimensions) {
        final mid    = Offset((s0.dx + s1.dx) / 2, (s0.dy + s1.dy) / 2);
        final topMid = Offset((s2.dx + s3.dx) / 2, (s2.dy + s3.dy) / 2);
        final labelPos = Offset((mid.dx + topMid.dx) / 2, (mid.dy + topMid.dy) / 2);
        final lenMm = wallRealMm[i] ?? ((b - a).distance * mmPerUnit);
        final label = lenMm >= 1000
            ? '${(lenMm / 1000).toStringAsFixed(2)} m'
            : '${lenMm.toStringAsFixed(0)} mm';

        final tp = TextPainter(
          text: TextSpan(
            text: 'W${i + 1}  $label',
            style: TextStyle(
              color: isSelected ? const Color(0xFF00AAFF) : const Color(0xFF4A5568),
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

  // ── Reveal: the visible surface inside a wall opening ────────────────────
  void _drawReveal(Canvas canvas, Offset a, Offset b, Offset c, Offset d) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
    canvas.drawPath(path,
        Paint()..color = const Color(0xFF0D1117)..style = PaintingStyle.fill);
    canvas.drawPath(path,
        Paint()
          ..color = const Color(0xFF333333)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
  }

  // ── Draw a door opening in 3D ─────────────────────────────────────────────
  void _drawDoor3D(Canvas canvas,
      Offset bl, Offset br, Offset tr, Offset tl,
      Offset ibl, Offset ibr, Offset itr, Offset itl) {
    // Outer dark hole
    final outerHole = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(tl.dx, tl.dy)
      ..close();
    canvas.drawPath(outerHole,
        Paint()..color = const Color(0xFF0A0E14)..style = PaintingStyle.fill);

    // Reveals: left jamb, right jamb, lintel (tunnel through wall thickness)
    _drawReveal(canvas, tl, bl, ibl, itl);
    _drawReveal(canvas, br, tr, itr, ibr);
    _drawReveal(canvas, tr, tl, itl, itr);

    // Inner dark hole
    canvas.drawPath(
      Path()
        ..moveTo(ibl.dx, ibl.dy)
        ..lineTo(ibr.dx, ibr.dy)
        ..lineTo(itr.dx, itr.dy)
        ..lineTo(itl.dx, itl.dy)
        ..close(),
      Paint()..color = const Color(0xFF0A0E14)..style = PaintingStyle.fill,
    );

    // Door panel (slightly inset from outer face)
    final centre = Offset(
        (bl.dx + br.dx + tr.dx + tl.dx) / 4,
        (bl.dy + br.dy + tr.dy + tl.dy) / 4);
    Offset ins(Offset p) => Offset(
        p.dx + (centre.dx - p.dx) * 0.05,
        p.dy + (centre.dy - p.dy) * 0.05);

    final doorPath = Path()
      ..moveTo(ins(bl).dx, ins(bl).dy)
      ..lineTo(ins(br).dx, ins(br).dy)
      ..lineTo(ins(tr).dx, ins(tr).dy)
      ..lineTo(ins(tl).dx, ins(tl).dy)
      ..close();
    canvas.drawPath(doorPath,
        Paint()..color = const Color(0xFF8B4513)..style = PaintingStyle.fill);
    canvas.drawPath(doorPath,
        Paint()
          ..color = const Color(0xFF5C2E00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    // Frame outline
    canvas.drawPath(outerHole,
        Paint()
          ..color = const Color(0xFF4A3728)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // Door knob
    final knobPos = Offset(
        ins(br).dx + (ins(bl).dx - ins(br).dx) * 0.15,
        ins(br).dy + (ins(tl).dy - ins(bl).dy) * 0.45);
    canvas.drawCircle(knobPos, 3, Paint()..color = const Color(0xFFFFD700));
  }

  // ── Draw a window opening in 3D ───────────────────────────────────────────
  void _drawWindow3D(Canvas canvas,
      Offset bl, Offset br, Offset tr, Offset tl,
      Offset ibl, Offset ibr, Offset itr, Offset itl) {
    // Outer dark hole + glass tint
    final outerPath = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(tl.dx, tl.dy)
      ..close();
    canvas.drawPath(outerPath,
        Paint()..color = const Color(0xFF0A0E14)..style = PaintingStyle.fill);
    canvas.drawPath(outerPath,
        Paint()
          ..color = const Color(0xFF4FC3F7).withOpacity(0.25)
          ..style = PaintingStyle.fill);

    // Reveals: left, right, head, sill
    _drawReveal(canvas, tl, bl, ibl, itl);
    _drawReveal(canvas, br, tr, itr, ibr);
    _drawReveal(canvas, tr, tl, itl, itr);
    _drawReveal(canvas, bl, br, ibr, ibl);

    // Inner glazing (faint tint on room side)
    canvas.drawPath(
      Path()
        ..moveTo(ibl.dx, ibl.dy)
        ..lineTo(ibr.dx, ibr.dy)
        ..lineTo(itr.dx, itr.dy)
        ..lineTo(itl.dx, itl.dy)
        ..close(),
      Paint()
        ..color = const Color(0xFF4FC3F7).withOpacity(0.15)
        ..style = PaintingStyle.fill,
    );

    // Frame
    canvas.drawPath(outerPath,
        Paint()
          ..color = const Color(0xFF90A4AE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    // Cross dividers
    final midTop   = Offset((tl.dx + tr.dx) / 2, (tl.dy + tr.dy) / 2);
    final midBot   = Offset((bl.dx + br.dx) / 2, (bl.dy + br.dy) / 2);
    final midLeft  = Offset((tl.dx + bl.dx) / 2, (tl.dy + bl.dy) / 2);
    final midRight = Offset((tr.dx + br.dx) / 2, (tr.dy + br.dy) / 2);
    final crossPaint = Paint()..color = const Color(0xFF90A4AE)..strokeWidth = 1.5;
    canvas.drawLine(midTop, midBot, crossPaint);
    canvas.drawLine(midLeft, midRight, crossPaint);

    // Glass highlight
    canvas.drawLine(
      Offset(tl.dx + (tr.dx - tl.dx) * 0.1, tl.dy + (tr.dy - tl.dy) * 0.1),
      Offset(bl.dx + (br.dx - bl.dx) * 0.1, bl.dy + (br.dy - bl.dy) * 0.1),
      Paint()..color = Colors.white.withOpacity(0.2)..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_Room3DPainter old) =>
      old.rotX != rotX ||
      old.rotY != rotY ||
      old.zoom != zoom ||
      old.panOffset != panOffset ||
      old.selectedWallIndex != selectedWallIndex ||
      old.wallHeightMm != wallHeightMm ||
      old.showCeiling != showCeiling ||
      old.showDimensions != showDimensions ||
      old.roomObjects.length != roomObjects.length;
}