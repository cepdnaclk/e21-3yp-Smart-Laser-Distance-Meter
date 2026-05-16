// lib/sketch/room_3d_screen.dart

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'room_object.dart';
import 'furniture_item.dart';
import 'sketch_constants.dart';
import '../ble/ble_manager.dart';

class Room3DScreen extends StatefulWidget {
  final List<Offset> points;
  final List<RoomObject> roomObjects;
  final Map<int, double> wallRealMm;
  final List<FurnitureItem> furnitureItems;
  final BleManager? bleManager;

  final void Function(int wallIndex, double mm)? onWallMeasured;
  final double initialHeightMm;
  final void Function(double heightMm)? onHeightChanged;

  const Room3DScreen({
    super.key,
    required this.points,
    required this.roomObjects,
    required this.wallRealMm,
    this.furnitureItems = const [],
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
          // Room height input — compact icon + text
          GestureDetector(
            onTap: _editHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.height, color: Color(0xFF00AA66), size: 16),
                  const SizedBox(width: 3),
                  Text(
                    '${(_wallHeightMm / 1000).toStringAsFixed(2)}m',
                    style: const TextStyle(
                        color: Color(0xFF00AA66),
                        fontFamily: 'monospace',
                        fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          // Reset camera
          IconButton(
            icon: const Icon(Icons.center_focus_strong,
                color: Color(0xFF556677), size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: _showDimensions ? 'Hide dimensions' : 'Show dimensions',
            onPressed: () =>
                setState(() => _showDimensions = !_showDimensions),
          ),
          const SizedBox(width: 4),
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
                furnitureItems: widget.furnitureItems,
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
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: _selectedWallIndex == null
                ? const Text(
                    '1 finger = rotate  •  2 fingers = zoom/pan  •  tap wall to select',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFF778899),
                        fontFamily: 'monospace',
                        fontSize: 11),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Wall ${_selectedWallIndex! + 1} selected',
                        style: const TextStyle(
                            color: Color(0xFF00AAFF),
                            fontFamily: 'monospace',
                            fontSize: 11),
                      ),
                      if (widget.bleManager != null)
                        _waitingForBle
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF00AAFF))),
                                  SizedBox(width: 6),
                                  Text('Measuring…',
                                      style: TextStyle(
                                          color: Color(0xFF00AAFF),
                                          fontFamily: 'monospace',
                                          fontSize: 11)),
                                ],
                              )
                            : GestureDetector(
                                onTap: _triggerBleMeasurement,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bluetooth,
                                        color: Color(0xFF00AAFF), size: 14),
                                    SizedBox(width: 4),
                                    Text('Measure',
                                        style: TextStyle(
                                            color: Color(0xFF00AAFF),
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                    ],
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
  final List<FurnitureItem> furnitureItems;
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
    required this.furnitureItems,
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

    // ── 2. Unified draw order: walls + furniture, sorted back-to-front ───────
    // (bool isWall, int idx, double depth)
    final drawOrder = <(bool, int, double)>[];
    for (int i = 0; i < n; i++) {
      final Offset a = points[i];
      final Offset b = points[(i + 1) % n];
      final double midX = (wx(a.dx) + wx(b.dx)) / 2;
      final double midZ = (wz(a.dy) + wz(b.dy)) / 2;
      drawOrder.add((true, i, midX * math.sin(rotY) + midZ * math.cos(rotY)));
    }
    for (int fi = 0; fi < furnitureItems.length; fi++) {
      final item = furnitureItems[fi];
      drawOrder.add((false, fi,
          wx(item.position.dx) * math.sin(rotY) +
          wz(item.position.dy) * math.cos(rotY)));
    }
    drawOrder.sort((a, b) => b.$3.compareTo(a.$3)); // far first

    // ── Pre-compute inward normals ─────────────────────────────────────────
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

    // ── Pre-compute miter inner corners so adjacent walls share exact points ─
    // For vertex j, find the intersection of the two adjacent walls' inner edges.
    // Both walls use the same intersection point → no gap or spike at corners.
    final List<Offset> innerCorners = List.filled(n, Offset.zero);
    for (int j = 0; j < n; j++) {
      final int prevW = (j - 1 + n) % n;
      final Offset pj    = points[j];
      final Offset pprev = points[prevW];
      final Offset pnext = points[(j + 1) % n];
      final Offset nPrev = wallNormals[prevW];
      final Offset nNext = wallNormals[j];

      // A point on each wall's inner edge at this vertex
      final double p1x = pj.dx + nPrev.dx * wallThickW;
      final double p1y = pj.dy + nPrev.dy * wallThickW;
      final double p2x = pj.dx + nNext.dx * wallThickW;
      final double p2y = pj.dy + nNext.dy * wallThickW;

      // Direction vectors along each wall
      final double d1x = pj.dx - pprev.dx;
      final double d1y = pj.dy - pprev.dy;
      final double d2x = pnext.dx - pj.dx;
      final double d2y = pnext.dy - pj.dy;

      final double cross = d1x * d2y - d1y * d2x;
      if (cross.abs() < 1e-6) {
        // Parallel walls: fall back to simple average offset
        innerCorners[j] = Offset(
          pj.dx + (nPrev.dx + nNext.dx) * wallThickW * 0.5,
          pj.dy + (nPrev.dy + nNext.dy) * wallThickW * 0.5,
        );
      } else {
        final double t = ((p2x - p1x) * d2y - (p2y - p1y) * d2x) / cross;
        // Miter limit: cap at 3× thickness to avoid extreme spikes on acute corners
        final double maxT = 3.0 * wallThickW /
            math.sqrt(d1x * d1x + d1y * d1y).clamp(1e-6, double.infinity);
        final double tc = t.clamp(-maxT, maxT);
        innerCorners[j] = Offset(p1x + tc * d1x, p1y + tc * d1y);
      }
    }

    for (final entry in drawOrder) {
      if (!entry.$1) {
        // ── Furniture item ───────────────────────────────────────────────────
        final item = furnitureItems[entry.$2];
        final double frad  = item.rotationDeg * math.pi / 180.0;
        final double fcosR = math.cos(frad);
        final double fsinR = math.sin(frad);
        final double fhw   = item.widthMm  / (2.0 * mmPerUnit);
        final double fhd   = item.depthMm  / (2.0 * mmPerUnit);
        final double fH2   = item.type.heightMm * mmScale;

        final fWorldPts = [
          const Offset(-1.0, -1.0),
          const Offset( 1.0, -1.0),
          const Offset( 1.0,  1.0),
          const Offset(-1.0,  1.0),
        ].map((lp) {
          final rx = lp.dx * fhw * fcosR - lp.dy * fhd * fsinR;
          final ry = lp.dx * fhw * fsinR + lp.dy * fhd * fcosR;
          return Offset(item.position.dx + rx, item.position.dy + ry);
        }).toList();

        final fBotPts = fWorldPts
            .map((wp) => _project(wx(wp.dx), 0,    wz(wp.dy), size)).toList();
        final fTopPts = fWorldPts
            .map((wp) => _project(wx(wp.dx), -fH2, wz(wp.dy), size)).toList();

        // Floor shadow
        double fscx = 0, fscy = 0;
        for (final bp in fBotPts) { fscx += bp.dx; fscy += bp.dy; }
        fscx /= 4; fscy /= 4;
        final double fsW = (fBotPts[1] - fBotPts[0]).distance +
                           (fBotPts[2] - fBotPts[3]).distance;
        final double fsD = (fBotPts[3] - fBotPts[0]).distance +
                           (fBotPts[2] - fBotPts[1]).distance;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(fscx, fscy),
              width: fsW * 0.65, height: fsD * 0.65),
          Paint()..color = Colors.black.withOpacity(0.22),
        );

        final fBaseColor = item.type.color;
        final double ffcx = item.position.dx;
        final double ffcz = item.position.dy;

        // Side faces — back-to-front, back-face culled
        final fFaceDepths = List.generate(4, (f) {
          final j  = (f + 1) % 4;
          final mx = (fWorldPts[f].dx + fWorldPts[j].dx) / 2;
          final mz = (fWorldPts[f].dy + fWorldPts[j].dy) / 2;
          return wx(mx) * math.sin(rotY) + wz(mz) * math.cos(rotY);
        });
        final fFaceOrder = [0, 1, 2, 3]
          ..sort((a, b) => fFaceDepths[b].compareTo(fFaceDepths[a]));

        for (final f in fFaceOrder) {
          final int j = (f + 1) % 4;
          final double fdx  = fWorldPts[j].dx - fWorldPts[f].dx;
          final double fdz  = fWorldPts[j].dy - fWorldPts[f].dy;
          final double flen = math.sqrt(fdx * fdx + fdz * fdz).clamp(1e-6, 1e9);
          double fnx = fdz / flen, fnz = -fdx / flen;
          final double fmx = (fWorldPts[f].dx + fWorldPts[j].dx) / 2;
          final double fmz = (fWorldPts[f].dy + fWorldPts[j].dy) / 2;
          if ((fmx - ffcx) * fnx + (fmz - ffcz) * fnz < 0) { fnx = -fnx; fnz = -fnz; }
          final double fvis = fnx * math.sin(rotY) + fnz * math.cos(rotY);
          if (fvis >= 0) continue;
          final double fshade = (-fvis).clamp(0.0, 1.0);
          final fFaceColor = Color.lerp(Colors.black, fBaseColor, 0.45 + fshade * 0.55)!;
          final sidePath = Path()
            ..moveTo(fBotPts[f].dx, fBotPts[f].dy)
            ..lineTo(fBotPts[j].dx, fBotPts[j].dy)
            ..lineTo(fTopPts[j].dx, fTopPts[j].dy)
            ..lineTo(fTopPts[f].dx, fTopPts[f].dy)
            ..close();
          canvas.drawPath(sidePath, Paint()..color = fFaceColor..style = PaintingStyle.fill);
          canvas.drawPath(sidePath,
              Paint()..color = Colors.black.withOpacity(0.25)
                ..style = PaintingStyle.stroke..strokeWidth = 0.7);
        }

        // Top face
        final fTopColor = Color.lerp(Colors.white, fBaseColor, 0.65)!;
        final fTopPath = Path()
          ..moveTo(fTopPts[0].dx, fTopPts[0].dy)
          ..lineTo(fTopPts[1].dx, fTopPts[1].dy)
          ..lineTo(fTopPts[2].dx, fTopPts[2].dy)
          ..lineTo(fTopPts[3].dx, fTopPts[3].dy)
          ..close();
        canvas.drawPath(fTopPath, Paint()..color = fTopColor..style = PaintingStyle.fill);
        canvas.drawPath(fTopPath,
            Paint()..color = Colors.black.withOpacity(0.2)
              ..style = PaintingStyle.stroke..strokeWidth = 0.7);
        for (int k = 0; k < 4; k++) {
          canvas.drawLine(fBotPts[k], fTopPts[k],
              Paint()..color = Colors.black.withOpacity(0.2)..strokeWidth = 0.7);
        }

        // Label
        final ftp = TextPainter(
          text: TextSpan(
            text: item.type.displayName,
            style: const TextStyle(color: Colors.white, fontSize: 8,
                fontFamily: 'monospace',
                shadows: [Shadow(blurRadius: 2, color: Colors.black)]),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        double flx = 0, fly = 0;
        for (final p in fTopPts) { flx += p.dx; fly += p.dy; }
        ftp.paint(canvas, Offset(flx / 4 - ftp.width / 2, fly / 4 - ftp.height / 2));
        continue;
      }

      // ── Wall ────────────────────────────────────────────────────────────────
      final int i = entry.$2;
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

      // Inner face corners — use miter points so adjacent walls share exact vertices
      final Offset icA = innerCorners[i];
      final Offset icB = innerCorners[(i + 1) % n];
      final si0 = _project(wx(icA.dx), 0,  wz(icA.dy), size);
      final si1 = _project(wx(icB.dx), 0,  wz(icB.dy), size);
      final si2 = _project(wx(icB.dx), -H, wz(icB.dy), size);
      final si3 = _project(wx(icA.dx), -H, wz(icA.dy), size);

      // Depth-based lightness for each face
      final double depth = entry.$3;
      final int outerL = (180 + (depth * 8).clamp(-60.0, 60.0)).toInt().clamp(100, 240);
      final int topL   = (outerL + 35).clamp(100, 255);
      final int innerL = (outerL - 45).clamp(60,  200);
      final outerCol = Color.fromARGB(255, outerL, outerL, outerL);
      final topCol   = Color.fromARGB(255, topL,   topL,   topL);
      final innerCol = Color.fromARGB(255, innerL, innerL, innerL);

      // 1. Inner face — only draw when it faces the camera (back-face culling).
      // dot(inward normal, camera direction in XZ) > 0  ⟹  face is visible.
      final double innerVis = norm.dx * math.sin(rotY) + norm.dy * math.cos(rotY);
      if (innerVis > 0) {
        canvas.drawPath(
          Path()
            ..moveTo(si0.dx, si0.dy)
            ..lineTo(si1.dx, si1.dy)
            ..lineTo(si2.dx, si2.dy)
            ..lineTo(si3.dx, si3.dy)
            ..close(),
          Paint()
            ..color = (isSelected ? const Color(0xFF2A5F8A) : innerCol).withOpacity(0.9)
            ..style = PaintingStyle.fill,
        );
      }

      // 2. Top face (faces up — lightest, most visible from above)
      canvas.drawPath(
        Path()
          ..moveTo(s3.dx,  s3.dy)
          ..lineTo(s2.dx,  s2.dy)
          ..lineTo(si2.dx, si2.dy)
          ..lineTo(si3.dx, si3.dy)
          ..close(),
        Paint()
          ..color = (isSelected ? const Color(0xFF5AAAE0) : topCol).withOpacity(0.95)
          ..style = PaintingStyle.fill,
      );

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
      // Selection outline on outer face only
      if (isSelected) {
        canvas.drawPath(wallPath,
            Paint()
              ..color = const Color(0xFF00AAFF)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
      }

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

    if (false) { // placeholder — furniture now drawn inside drawOrder loop above
      for (final item in furnitureItems) {
        final double rad  = item.rotationDeg * math.pi / 180.0;
        final double cosR = math.cos(rad);
        final double sinR = math.sin(rad);
        final double hw   = item.widthMm  / (2.0 * mmPerUnit);
        final double hd   = item.depthMm  / (2.0 * mmPerUnit);
        final double fH   = item.type.heightMm * mmScale;

        // 4 footprint corners in world sketch units (CW: fl, fr, br, bl)
        final worldPts = [
          const Offset(-1.0, -1.0),
          const Offset( 1.0, -1.0),
          const Offset( 1.0,  1.0),
          const Offset(-1.0,  1.0),
        ].map((lp) {
          final rx = lp.dx * hw * cosR - lp.dy * hd * sinR;
          final ry = lp.dx * hw * sinR + lp.dy * hd * cosR;
          return Offset(item.position.dx + rx, item.position.dy + ry);
        }).toList();

        final botPts = worldPts
            .map((wp) => _project(wx(wp.dx), 0,   wz(wp.dy), size))
            .toList();
        final topPts = worldPts
            .map((wp) => _project(wx(wp.dx), -fH, wz(wp.dy), size))
            .toList();

        // Floor shadow ellipse
        double scx = 0, scy = 0;
        for (final bp in botPts) { scx += bp.dx; scy += bp.dy; }
        scx /= 4; scy /= 4;
        final double sW = (botPts[1] - botPts[0]).distance +
                          (botPts[2] - botPts[3]).distance;
        final double sD = (botPts[3] - botPts[0]).distance +
                          (botPts[2] - botPts[1]).distance;
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(scx, scy),
              width:  sW * 0.65,
              height: sD * 0.65),
          Paint()..color = Colors.black.withOpacity(0.22),
        );

        final baseColor = item.type.color;
        final double fcx = item.position.dx;
        final double fcz = item.position.dy;

        // 4 side faces — sorted back-to-front, back-face culled
        final faceDepths = List.generate(4, (f) {
          final j   = (f + 1) % 4;
          final mx  = (worldPts[f].dx + worldPts[j].dx) / 2;
          final mz  = (worldPts[f].dy + worldPts[j].dy) / 2;
          return wx(mx) * math.sin(rotY) + wz(mz) * math.cos(rotY);
        });
        final faceOrder = [0, 1, 2, 3]
          ..sort((a, b) => faceDepths[b].compareTo(faceDepths[a]));

        for (final f in faceOrder) {
          final int j = (f + 1) % 4;
          final double dx  = worldPts[j].dx - worldPts[f].dx;
          final double dz  = worldPts[j].dy - worldPts[f].dy;
          final double len = math.sqrt(dx * dx + dz * dz).clamp(1e-6, 1e9);
          double nx = dz / len, nz = -dx / len;

          // Ensure normal points away from box centre
          final double mx = (worldPts[f].dx + worldPts[j].dx) / 2;
          final double mz = (worldPts[f].dy + worldPts[j].dy) / 2;
          if ((mx - fcx) * nx + (mz - fcz) * nz < 0) { nx = -nx; nz = -nz; }

          // Skip back faces (outward normal points away from camera)
          final double vis = nx * math.sin(rotY) + nz * math.cos(rotY);
          if (vis >= 0) continue;

          // Lambert shading: face perpendicular to camera = brightest
          final double shade = (-vis).clamp(0.0, 1.0);
          final faceColor = Color.lerp(
              Colors.black, baseColor, 0.45 + shade * 0.55)!;

          canvas.drawPath(
            Path()
              ..moveTo(botPts[f].dx, botPts[f].dy)
              ..lineTo(botPts[j].dx, botPts[j].dy)
              ..lineTo(topPts[j].dx, topPts[j].dy)
              ..lineTo(topPts[f].dx, topPts[f].dy)
              ..close(),
            Paint()..color = faceColor..style = PaintingStyle.fill,
          );
          // Subtle edge line
          canvas.drawPath(
            Path()
              ..moveTo(botPts[f].dx, botPts[f].dy)
              ..lineTo(botPts[j].dx, botPts[j].dy)
              ..lineTo(topPts[j].dx, topPts[j].dy)
              ..lineTo(topPts[f].dx, topPts[f].dy)
              ..close(),
            Paint()
              ..color = Colors.black.withOpacity(0.25)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.7,
          );
        }

        // Top face (always visible from above since camera angle > 0)
        final topColor =
            Color.lerp(Colors.white, baseColor, 0.65)!;
        canvas.drawPath(
          Path()
            ..moveTo(topPts[0].dx, topPts[0].dy)
            ..lineTo(topPts[1].dx, topPts[1].dy)
            ..lineTo(topPts[2].dx, topPts[2].dy)
            ..lineTo(topPts[3].dx, topPts[3].dy)
            ..close(),
          Paint()..color = topColor..style = PaintingStyle.fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(topPts[0].dx, topPts[0].dy)
            ..lineTo(topPts[1].dx, topPts[1].dy)
            ..lineTo(topPts[2].dx, topPts[2].dy)
            ..lineTo(topPts[3].dx, topPts[3].dy)
            ..close(),
          Paint()
            ..color = Colors.black.withOpacity(0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7,
        );

        // Vertical edges (bottom→top for visible corners)
        for (int k = 0; k < 4; k++) {
          canvas.drawLine(
            botPts[k], topPts[k],
            Paint()
              ..color = Colors.black.withOpacity(0.2)
              ..strokeWidth = 0.7,
          );
        }

        // Label on top face
        final tp = TextPainter(
          text: TextSpan(
            text: item.type.displayName,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontFamily: 'monospace',
                shadows: [Shadow(blurRadius: 2, color: Colors.black)]),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        double lx = 0, ly = 0;
        for (final p in topPts) { lx += p.dx; ly += p.dy; }
        tp.paint(canvas, Offset(lx / 4 - tp.width / 2, ly / 4 - tp.height / 2));
      }
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
      old.roomObjects.length != roomObjects.length ||
      old.furnitureItems.length != furnitureItems.length;
}