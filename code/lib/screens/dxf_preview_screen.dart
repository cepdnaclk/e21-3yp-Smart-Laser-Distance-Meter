// lib/screens/dxf_preview_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../sketch/sketch_model.dart';
import '../sketch/sketch_constants.dart';
import '../sketch/room_object.dart';
import '../sketch/furniture_item.dart';
import 'dxf_exporter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DXF Preview & Export Screen
// Shows a CAD-style blueprint preview of the full floor plan (all rooms) and
// triggers DXF download via share sheet. Falls back to a 4×3 m sample room
// when no closed room is available.
// ─────────────────────────────────────────────────────────────────────────────

class DxfPreviewScreen extends StatefulWidget {
  final List<SketchShape> shapes;
  final String projectName;

  const DxfPreviewScreen({
    super.key,
    required this.shapes,
    this.projectName = 'SmartMeasure_Room',
  });

  @override
  State<DxfPreviewScreen> createState() => _DxfPreviewScreenState();
}

class _DxfPreviewScreenState extends State<DxfPreviewScreen> {
  bool _isExporting = false;

  // 4 m × 3 m sample room in world units (1 unit = 5 mm)
  static const List<Offset> _mockPoints = [
    Offset(0, 0), Offset(800, 0), Offset(800, 600), Offset(0, 600),
  ];
  static const Map<int, double> _mockWallMm = {0: 4000, 1: 3000, 2: 4000, 3: 3000};

  List<SketchShape> get _closedShapes =>
      widget.shapes.where((s) => s.isClosed && s.points.length >= 3).toList();

  bool get _hasRealRoom => _closedShapes.isNotEmpty;

  List<SketchShape> get _previewShapes {
    if (_hasRealRoom) return _closedShapes;
    return [
      SketchShape(
        points: List<Offset>.from(_mockPoints),
        isClosed: true,
        wallRealMm: Map<int, double>.from(_mockWallMm),
      ),
    ];
  }

  // Stats computed from shapes
  int get _totalWalls =>
      _previewShapes.fold(0, (s, sh) => s + sh.wallCount);
  int get _totalDoors =>
      _previewShapes.fold(0, (s, sh) => s + sh.roomObjects.where((o) => o.isDoor).length);
  int get _totalWindows =>
      _previewShapes.fold(0, (s, sh) => s + sh.roomObjects.where((o) => !o.isDoor).length);
  int get _totalFurniture =>
      _previewShapes.fold(0, (s, sh) => s + sh.furnitureItems.length);

  Future<void> _exportDxf() async {
    setState(() => _isExporting = true);
    try {
      await DxfExporter.export(
        shapes: _previewShapes,
        projectName: _hasRealRoom ? widget.projectName : 'Sample_Room',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1520),
        foregroundColor: const Color(0xFF00CCFF),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.architecture, size: 20, color: Color(0xFF00CCFF)),
            SizedBox(width: 8),
            Text(
              'DXF EXPORT',
              style: TextStyle(
                color: Color(0xFF00CCFF),
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
        actions: [
          if (!_hasRealRoom)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFFAA00), width: 1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'SAMPLE',
                style: TextStyle(
                  color: Color(0xFFFFAA00),
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Blueprint canvas ───────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF1A3A4A), width: 1.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: AspectRatio(
                  aspectRatio: 1.55,
                  child: CustomPaint(
                    painter: _BlueprintPainter(shapes: _previewShapes),
                  ),
                ),
              ),
            ),

            // ── File info ──────────────────────────────────────────────
            _FileInfoCard(
              isMock: !_hasRealRoom,
              projectName: widget.projectName,
              roomCount: _previewShapes.length,
              wallCount: _totalWalls,
              doorCount: _totalDoors,
              windowCount: _totalWindows,
              furnitureCount: _totalFurniture,
            ),

            const SizedBox(height: 10),

            // ── Wall table ─────────────────────────────────────────────
            _WallTable(shapes: _previewShapes),

            const SizedBox(height: 20),

            // ── Export button ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF003A55),
                        foregroundColor: const Color(0xFF00CCFF),
                        disabledBackgroundColor: const Color(0xFF1A2530),
                        disabledForegroundColor: const Color(0xFF335566),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(3),
                          side: BorderSide(
                            color: _isExporting
                                ? const Color(0xFF005577)
                                : const Color(0xFF00CCFF),
                          ),
                        ),
                      ),
                      icon: _isExporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF00CCFF),
                              ),
                            )
                          : const Icon(Icons.file_download_outlined, size: 22),
                      label: Text(
                        _isExporting
                            ? 'GENERATING DXF…'
                            : _hasRealRoom
                                ? 'EXPORT DXF  (${_previewShapes.length} room${_previewShapes.length == 1 ? '' : 's'})'
                                : 'DOWNLOAD SAMPLE DXF',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      onPressed: _isExporting ? null : _exportDxf,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_hasRealRoom)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF140F00),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFF3D2800)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 15, color: Color(0xFFAA7700)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Draw and close a room in the sketch editor to export your actual '
                              'floor plan. The preview above shows a 4 m × 3 m sample.',
                              style: TextStyle(
                                color: Color(0xFFAA8833),
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Text(
                      'DXF opens in AutoCAD, LibreCAD, QCAD and other CAD tools.',
                      style: TextStyle(
                          color: Color(0xFF335566), fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ── CAD blueprint painter ──────────────────────────────────────────────────

class _BlueprintPainter extends CustomPainter {
  final List<SketchShape> shapes;

  const _BlueprintPainter({required this.shapes});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF040A12),
    );

    // Grid
    final gridPaint = Paint()..color = const Color(0xFF091820)..strokeWidth = 0.6;
    const double step = 36.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Collect all points for bounding box
    final allPts = <Offset>[];
    for (final s in shapes) {
      allPts.addAll(s.points);
      allPts.addAll(s.furnitureItems.map((f) => f.position));
    }
    if (allPts.isEmpty) {
      _drawPlaceholder(canvas, size);
      return;
    }

    double gMinX = allPts.map((p) => p.dx).reduce(math.min);
    double gMaxX = allPts.map((p) => p.dx).reduce(math.max);
    double gMinY = allPts.map((p) => p.dy).reduce(math.min);
    double gMaxY = allPts.map((p) => p.dy).reduce(math.max);

    final margin = size.width * 0.13;
    final drawW = size.width - margin * 2;
    final drawH = size.height - margin * 2;
    final worldW = (gMaxX - gMinX).clamp(1.0, double.infinity);
    final worldH = (gMaxY - gMinY).clamp(1.0, double.infinity);
    final sc = math.min(drawW / worldW, drawH / worldH) * 0.78;

    Offset toC(Offset p) => Offset(
          margin + (drawW - worldW * sc) / 2 + (p.dx - gMinX) * sc,
          margin + (drawH - worldH * sc) / 2 + (p.dy - gMinY) * sc,
        );

    // Pass 1: room fills
    for (final s in shapes) {
      if (s.points.length < 3 || !s.isClosed) continue;
      final path = Path()..moveTo(toC(s.points[0]).dx, toC(s.points[0]).dy);
      for (int i = 1; i < s.points.length; i++) {
        path.lineTo(toC(s.points[i]).dx, toC(s.points[i]).dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF061020));
    }

    // Pass 2: full room content (gap covers → walls → corners → objects → furniture → dims)
    for (final s in shapes) {
      if (s.points.isEmpty) continue;
      _drawShapeContent(canvas, s, toC, sc);
    }

    // Watermark
    final wm = TextPainter(
      text: const TextSpan(
        text: 'SMARTMEASURE  ·  DXF AC1009',
        style: TextStyle(
          color: Color(0xFF0A1E2A),
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    wm.paint(canvas, Offset(size.width / 2 - wm.width / 2, size.height - 18));
  }

  void _drawShapeContent(Canvas canvas, SketchShape shape,
      Offset Function(Offset) toC, double sc) {
    final pts = shape.points;
    final n = pts.length;
    if (n < 2) return;

    final int wallCount = shape.isClosed ? n : n - 1;

    // Centroid in canvas space (for outward normal)
    double cx = 0, cy = 0;
    for (final p in pts) { cx += toC(p).dx; cy += toC(p).dy; }
    cx /= n; cy /= n;
    final centC = Offset(cx, cy);

    // World centroid (for inward normal computation)
    Offset worldCent = pts.fold(Offset.zero, (s, p) => s + p);
    worldCent = Offset(worldCent.dx / n, worldCent.dy / n);

    // Gap covers (background-coloured line erasing wall at opening)
    if (shape.isClosed) {
      for (final obj in shape.roomObjects) {
        if (obj.wallIndex >= n) continue;
        _drawGapCover(canvas, pts, n, obj, toC);
      }
    }

    // Walls
    final wallPaint = Paint()
      ..color = const Color(0xFF00CCFF)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < wallCount; i++) {
      canvas.drawLine(toC(pts[i]), toC(pts[(i + 1) % n]), wallPaint);
    }

    // Corner dots
    for (int i = 0; i < n; i++) {
      canvas.drawCircle(toC(pts[i]), i == 0 ? 4.0 : 2.8,
          Paint()..color = const Color(0xFF00FF99));
    }

    // Room objects (doors, windows)
    if (shape.isClosed) {
      for (final obj in shape.roomObjects) {
        if (obj.wallIndex >= n) continue;
        _drawObject(canvas, pts, n, obj, worldCent, toC, sc);
      }

      // Furniture
      for (final item in shape.furnitureItems) {
        _drawFurnitureItem(canvas, item, toC, sc);
      }
    }

    // Dimension labels
    for (int i = 0; i < wallCount; i++) {
      final pA = pts[i];
      final pB = pts[(i + 1) % n];
      final a = toC(pA);
      final b = toC(pB);
      final midX = (a.dx + b.dx) / 2;
      final midY = (a.dy + b.dy) / 2;
      final wdx = b.dx - a.dx, wdy = b.dy - a.dy;
      final wLen = math.sqrt(wdx * wdx + wdy * wdy);
      if (wLen < 24) continue;

      double nx = -wdy / wLen, ny = wdx / wLen;
      if ((centC.dx - midX) * nx + (centC.dy - midY) * ny > 0) { nx = -nx; ny = -ny; }

      const double dimOffset = 20.0;
      const double tickGap = 5.0;
      const double tickLen = 16.0;

      final tickPaint = Paint()..color = const Color(0xFF005577)..strokeWidth = 0.8;
      canvas.drawLine(
          Offset(a.dx + nx * tickGap, a.dy + ny * tickGap),
          Offset(a.dx + nx * (tickGap + tickLen), a.dy + ny * (tickGap + tickLen)),
          tickPaint);
      canvas.drawLine(
          Offset(b.dx + nx * tickGap, b.dy + ny * tickGap),
          Offset(b.dx + nx * (tickGap + tickLen), b.dy + ny * (tickGap + tickLen)),
          tickPaint);
      canvas.drawLine(
          Offset(a.dx + nx * dimOffset, a.dy + ny * dimOffset),
          Offset(b.dx + nx * dimOffset, b.dy + ny * dimOffset),
          tickPaint);

      final drawnMm = (pB - pA).distance * mmPerUnit;
      final dispMm = shape.wallRealMm.containsKey(i) ? shape.wallRealMm[i]! : drawnMm;

      final tp = TextPainter(
        text: TextSpan(
          text: _fmtMm(dispMm),
          style: TextStyle(
            color: shape.wallRealMm.containsKey(i)
                ? const Color(0xFF00FF88)
                : const Color(0xFFCCEE88),
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(
        midX + nx * (dimOffset + 3) - tp.width / 2,
        midY + ny * (dimOffset + 3) - tp.height / 2,
      ));

      // Wall index
      final idxTp = TextPainter(
        text: TextSpan(
          text: 'W${i + 1}',
          style: const TextStyle(color: Color(0xFF336688), fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      idxTp.paint(canvas, Offset(a.dx + 5, a.dy - 13));
    }
  }

  void _drawGapCover(Canvas canvas, List<Offset> pts, int n, RoomObject obj,
      Offset Function(Offset) toC) {
    final wA = pts[obj.wallIndex];
    final wB = pts[(obj.wallIndex + 1) % n];
    final wallLen = (wB - wA).distance;
    if (wallLen < 1) return;
    final wallDir = (wB - wA) / wallLen;
    final halfW = (obj.widthMm / mmPerUnit) / 2;
    final tCenter = obj.positionAlong * wallLen;
    final startW = wA + wallDir * (tCenter - halfW);
    final endW   = wA + wallDir * (tCenter + halfW);
    canvas.drawLine(
      toC(startW), toC(endW),
      Paint()
        ..color = const Color(0xFF040A12)
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawObject(Canvas canvas, List<Offset> pts, int n, RoomObject obj,
      Offset worldCent, Offset Function(Offset) toC, double sc) {
    final wA = pts[obj.wallIndex];
    final wB = pts[(obj.wallIndex + 1) % n];
    final wallLen = (wB - wA).distance;
    if (wallLen < 1) return;

    final wallDir = (wB - wA) / wallLen;
    final halfW = (obj.widthMm / mmPerUnit) / 2;
    final tCenter = obj.positionAlong * wallLen;
    final startW = wA + wallDir * (tCenter - halfW);
    final endW   = wA + wallDir * (tCenter + halfW);

    // Inward normal in world space
    Offset inW = Offset(-wallDir.dy, wallDir.dx);
    final wallMid = (wA + wB) * 0.5;
    if ((worldCent - wallMid).dx * inW.dx + (worldCent - wallMid).dy * inW.dy < 0) {
      inW = Offset(-inW.dx, -inW.dy);
    }
    if (obj.swingFlipped) inW = Offset(-inW.dx, -inW.dy);

    final startC = toC(startW);
    final endC   = toC(endW);

    if (obj.isDoor) {
      _drawDoorPreview(canvas, startC, endC, inW, (obj.widthMm / mmPerUnit) * sc);
    } else {
      _drawWindowPreview(canvas, startC, endC, inW);
    }
  }

  void _drawDoorPreview(Canvas canvas, Offset startC, Offset endC,
      Offset inWorld, double radiusPx) {
    // inWorld is a unit vector; in canvas (Y-down matches world Y-down) direction is same
    final leafTip = startC + inWorld * radiusPx;

    final paint = Paint()
      ..color = const Color(0xFFFF6644)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(startC, leafTip, paint);
    canvas.drawLine(startC, endC, paint);

    final wallAngle = math.atan2(endC.dy - startC.dy, endC.dx - startC.dx);
    final wdx = endC.dx - startC.dx, wdy = endC.dy - startC.dy;
    final ldx = leafTip.dx - startC.dx, ldy = leafTip.dy - startC.dy;
    final cross = wdx * ldy - wdy * ldx;
    final sweep = cross > 0 ? math.pi / 2 : -math.pi / 2;

    canvas.drawArc(
      Rect.fromCircle(center: startC, radius: radiusPx),
      wallAngle + sweep, -sweep, false,
      Paint()
        ..color = const Color(0xFFFF6644)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawWindowPreview(Canvas canvas, Offset startC, Offset endC,
      Offset inWorld) {
    // Fixed 4 px spacing — readable at all zoom levels
    for (final t in [-4.0, 0.0, 4.0]) {
      final off = inWorld * t;
      canvas.drawLine(
        startC + off, endC + off,
        Paint()
          ..color = const Color(0xFF44DDEE)
          ..strokeWidth = t == 0 ? 1.5 : 0.8
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawFurnitureItem(Canvas canvas, FurnitureItem item,
      Offset Function(Offset) toC, double sc) {
    final rad = item.rotationDeg * math.pi / 180;
    final hw = item.widthMm / mmPerUnit / 2;
    final hd = item.depthMm / mmPerUnit / 2;
    final ux = math.cos(rad), uy = math.sin(rad);
    final vx = -math.sin(rad), vy = math.cos(rad);

    final cx = item.position.dx, cy = item.position.dy;
    final corners = [
      toC(Offset(cx + ux*hw + vx*hd, cy + uy*hw + vy*hd)),
      toC(Offset(cx - ux*hw + vx*hd, cy - uy*hw + vy*hd)),
      toC(Offset(cx - ux*hw - vx*hd, cy - uy*hw - vy*hd)),
      toC(Offset(cx + ux*hw - vx*hd, cy + uy*hw - vy*hd)),
    ];

    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(path, Paint()..color = const Color(0xFF001A08)..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()
      ..color = const Color(0xFF44CC77)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke);

    final crossPaint = Paint()..color = const Color(0xFF226644)..strokeWidth = 0.7..style = PaintingStyle.stroke;
    canvas.drawLine(corners[0], corners[2], crossPaint);
    canvas.drawLine(corners[1], corners[3], crossPaint);

    final center = toC(item.position);
    final maxLabelW = (item.widthMm / mmPerUnit * sc).clamp(28.0, 110.0);
    final tp = TextPainter(
      text: TextSpan(
        text: item.type.displayName,
        style: const TextStyle(
          color: Color(0xFF44CC77),
          fontSize: 7.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxLabelW);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawPlaceholder(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'No room drawn yet',
        style: TextStyle(color: Color(0xFF1A3A4A), fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2));
  }

  static String _fmtMm(double mm) {
    if (mm >= 1000) return '${(mm / 1000).toStringAsFixed(2)} m';
    return '${mm.toStringAsFixed(0)} mm';
  }

  @override
  bool shouldRepaint(_BlueprintPainter old) => old.shapes != shapes;
}

// ── File info card ─────────────────────────────────────────────────────────

class _FileInfoCard extends StatelessWidget {
  final bool isMock;
  final String projectName;
  final int roomCount;
  final int wallCount;
  final int doorCount;
  final int windowCount;
  final int furnitureCount;

  const _FileInfoCard({
    required this.isMock,
    required this.projectName,
    required this.roomCount,
    required this.wallCount,
    required this.doorCount,
    required this.windowCount,
    required this.furnitureCount,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final safeName = isMock
        ? 'sample_room.dxf'
        : '${projectName.replaceAll(RegExp(r'[^\w\-]'), '_')}.dxf';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0A1520),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF1A3A4A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 15, color: Color(0xFF00CCFF)),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    safeName,
                    style: const TextStyle(
                      color: Color(0xFF00CCFF),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMock)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A1800),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFFFFAA00)),
                    ),
                    child: const Text(
                      'SAMPLE',
                      style: TextStyle(
                          color: Color(0xFFFFAA00),
                          fontSize: 9,
                          letterSpacing: 1,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: Color(0xFF1A3A4A), height: 1),
            const SizedBox(height: 10),
            _row('Format', 'AutoCAD DXF  (AC1009 / R12)'),
            _row('Units', 'Millimetres  (INSUNITS = 4)'),
            _row('Scale', '1 world unit = 5 mm'),
            _row('Layers', 'WALLS · DOORS · WINDOWS · FURNITURE'),
            _row('Rooms', '$roomCount'),
            _row('Walls', '$wallCount total'),
            if (doorCount > 0) _row('Doors', '$doorCount'),
            if (windowCount > 0) _row('Windows', '$windowCount'),
            if (furnitureCount > 0) _row('Furniture', '$furnitureCount items'),
            _row('Date', dateStr),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 78,
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF335566),
                  fontSize: 11,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(color: Color(0xFFAABBCC), fontSize: 11),
              ),
            ),
          ],
        ),
      );
}

// ── Wall measurements table ────────────────────────────────────────────────

class _WallTable extends StatelessWidget {
  final List<SketchShape> shapes;

  const _WallTable({required this.shapes});

  @override
  Widget build(BuildContext context) {
    final displayShapes = shapes.where((s) => s.points.length >= 2).toList();
    if (displayShapes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WALL MEASUREMENTS',
            style: TextStyle(
              color: Color(0xFF335566),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 7),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF1A3A4A)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.1),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2.2),
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: Color(0xFF0C1A24)),
                  children: [
                    _TCell('WALL', header: true),
                    _TCell('DRAWN', header: true),
                    _TCell('CALIBRATED', header: true),
                  ],
                ),
                ..._buildRows(displayShapes),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<TableRow> _buildRows(List<SketchShape> shapes) {
    final rows = <TableRow>[];
    for (int si = 0; si < shapes.length; si++) {
      final s = shapes[si];
      final n = s.points.length;
      final wallCount = s.isClosed ? n : n - 1;

      // Room separator row when there are multiple shapes
      if (shapes.length > 1) {
        final roomLabel = s.label.isNotEmpty ? s.label : 'Room ${si + 1}';
        rows.add(TableRow(
          decoration: const BoxDecoration(color: Color(0xFF071018)),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              child: Text(
                roomLabel,
                style: const TextStyle(
                  color: Color(0xFF00CCFF),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
          ],
        ));
      }

      for (int i = 0; i < wallCount; i++) {
        final a = s.points[i];
        final b = s.points[(i + 1) % n];
        final drawn = (b - a).distance;
        final drawnStr = formatLength(drawn);
        final hasCal = s.wallRealMm.containsKey(i);
        final calStr = hasCal ? '${s.wallRealMm[i]!.toStringAsFixed(0)} mm' : '—';
        final rowIndex = rows.length;
        rows.add(TableRow(
          decoration: BoxDecoration(
            color: rowIndex.isEven
                ? const Color(0xFF070E16)
                : const Color(0xFF090F18),
          ),
          children: [
            _TCell('W${i + 1}', accent: true),
            _TCell(drawnStr),
            _TCell(calStr, calibrated: hasCal),
          ],
        ));
      }
    }
    return rows;
  }
}

class _TCell extends StatelessWidget {
  final String text;
  final bool header;
  final bool accent;
  final bool calibrated;

  const _TCell(
    this.text, {
    this.header = false,
    this.accent = false,
    this.calibrated = false,
  });

  @override
  Widget build(BuildContext context) {
    Color color = const Color(0xFF7799AA);
    if (header) color = const Color(0xFF335566);
    if (accent) color = const Color(0xFF00BBEE);
    if (calibrated) color = const Color(0xFF00EE88);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: header ? 9 : 11,
          fontWeight: header ? FontWeight.bold : FontWeight.normal,
          letterSpacing: header ? 1.0 : 0,
          fontFamily: accent || !header ? 'monospace' : null,
        ),
      ),
    );
  }
}
