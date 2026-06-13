// lib/screens/dxf_preview_screen.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../sketch/sketch_model.dart';
import '../sketch/sketch_constants.dart';
import '../sketch/room_object.dart';
import 'dxf_exporter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DXF Preview & Export Screen
// Shows a CAD-style blueprint preview and triggers DXF download via share sheet.
// Falls back to a 4×3 m sample room when no closed room is available.
// ─────────────────────────────────────────────────────────────────────────────

class DxfPreviewScreen extends StatefulWidget {
  final List<SketchShape> shapes;
  final double totalPerimeter;
  final double totalArea;
  final List<RoomObject> roomObjects;
  final String projectName;

  const DxfPreviewScreen({
    super.key,
    required this.shapes,
    required this.totalPerimeter,
    required this.totalArea,
    required this.roomObjects,
    this.projectName = 'SmartMeasure_Room',
  });

  @override
  State<DxfPreviewScreen> createState() => _DxfPreviewScreenState();
}

class _DxfPreviewScreenState extends State<DxfPreviewScreen> {
  bool _isExporting = false;

  // 4 m × 3 m sample room in world units (1 unit = 5 mm → 4000/5=800, 3000/5=600)
  static const List<Offset> _mockPoints = [
    Offset(0, 0),
    Offset(800, 0),
    Offset(800, 600),
    Offset(0, 600),
  ];
  static const Map<int, double> _mockWallMm = {
    0: 4000,
    1: 3000,
    2: 4000,
    3: 3000,
  };

  SketchShape get _shape => widget.shapes.firstWhere(
        (s) => s.isClosed && s.points.length >= 3,
        orElse: () => widget.shapes.first,
      );

  bool get _hasRealRoom =>
      widget.shapes.any((s) => s.isClosed && s.points.length >= 3);

  List<Offset> get _pts => _hasRealRoom ? _shape.points : _mockPoints;
  Map<int, double> get _wallMm =>
      _hasRealRoom ? _shape.wallRealMm : _mockWallMm;

  Future<void> _exportDxf() async {
    setState(() => _isExporting = true);
    try {
      if (_hasRealRoom) {
        await DxfExporter.export(
          points: _shape.points,
          isClosed: _shape.isClosed,
          wallRealMm: _shape.wallRealMm,
          projectName: widget.projectName,
        );
      } else {
        await DxfExporter.export(
          points: List<Offset>.from(_mockPoints),
          isClosed: true,
          wallRealMm: Map<int, double>.from(_mockWallMm),
          projectName: 'Sample_Room',
        );
      }
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
                    painter: _BlueprintPainter(
                      points: _pts,
                      wallRealMm: _wallMm,
                    ),
                  ),
                ),
              ),
            ),

            // ── File info ──────────────────────────────────────────────
            _FileInfoCard(
              isMock: !_hasRealRoom,
              projectName: widget.projectName,
              perimeter: _hasRealRoom ? widget.totalPerimeter : null,
              area: _hasRealRoom ? widget.totalArea : null,
              pointCount: _pts.length,
            ),

            const SizedBox(height: 10),

            // ── Wall table ─────────────────────────────────────────────
            _WallTable(points: _pts, wallRealMm: _wallMm),

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
                                ? 'EXPORT DXF'
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
  final List<Offset> points;
  final Map<int, double> wallRealMm;

  const _BlueprintPainter({required this.points, required this.wallRealMm});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF040A12),
    );

    if (points.length < 2) {
      _drawPlaceholder(canvas, size);
      return;
    }

    final margin = size.width * 0.14;
    final minX = points.map((p) => p.dx).reduce(math.min);
    final maxX = points.map((p) => p.dx).reduce(math.max);
    final minY = points.map((p) => p.dy).reduce(math.min);
    final maxY = points.map((p) => p.dy).reduce(math.max);
    final worldW = (maxX - minX).clamp(1.0, double.infinity);
    final worldH = (maxY - minY).clamp(1.0, double.infinity);
    final drawW = size.width - margin * 2;
    final drawH = size.height - margin * 2;
    final sc = math.min(drawW / worldW, drawH / worldH) * 0.78;

    Offset toC(Offset p) => Offset(
          margin + (drawW - worldW * sc) / 2 + (p.dx - minX) * sc,
          margin + (drawH - worldH * sc) / 2 + (p.dy - minY) * sc,
        );

    // Grid
    final gridPaint = Paint()
      ..color = const Color(0xFF091820)
      ..strokeWidth = 0.6;
    const double step = 36.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final n = points.length;

    // Room fill
    if (n >= 3) {
      final path = Path();
      path.moveTo(toC(points[0]).dx, toC(points[0]).dy);
      for (int i = 1; i < n; i++) {
        path.lineTo(toC(points[i]).dx, toC(points[i]).dy);
      }
      path.close();
      canvas.drawPath(
          path, Paint()..color = const Color(0xFF061020));
    }

    // Walls
    final wallPaint = Paint()
      ..color = const Color(0xFF00CCFF)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < n; i++) {
      final a = toC(points[i]);
      final b = toC(points[(i + 1) % n]);
      // Skip closing wall if polygon open (< 3 pts)
      if (i == n - 1 && n < 3) continue;
      canvas.drawLine(a, b, wallPaint);
    }

    // Corner dots
    for (int i = 0; i < n; i++) {
      final c = toC(points[i]);
      canvas.drawCircle(
        c,
        i == 0 ? 4.0 : 2.8,
        Paint()..color = const Color(0xFF00FF99),
      );
    }

    // Centroid for normal direction
    double cx = 0, cy = 0;
    for (final p in points) {
      cx += toC(p).dx;
      cy += toC(p).dy;
    }
    cx /= n;
    cy /= n;

    // Dimension lines + labels
    for (int i = 0; i < n; i++) {
      if (i == n - 1 && n < 3) continue;
      final pA = points[i];
      final pB = points[(i + 1) % n];
      final a = toC(pA);
      final b = toC(pB);

      final midX = (a.dx + b.dx) / 2;
      final midY = (a.dy + b.dy) / 2;
      final wdx = b.dx - a.dx;
      final wdy = b.dy - a.dy;
      final wLen = math.sqrt(wdx * wdx + wdy * wdy);
      if (wLen < 24) continue;

      double nx = -wdy / wLen;
      double ny = wdx / wLen;
      if ((cx - midX) * nx + (cy - midY) * ny > 0) {
        nx = -nx;
        ny = -ny;
      }

      const double dimOffset = 20.0;
      const double tickGap = 5.0;
      const double tickLen = 16.0;

      // Extension ticks
      final tickPaint = Paint()
        ..color = const Color(0xFF005577)
        ..strokeWidth = 0.8;
      canvas.drawLine(
          Offset(a.dx + nx * tickGap, a.dy + ny * tickGap),
          Offset(a.dx + nx * (tickGap + tickLen), a.dy + ny * (tickGap + tickLen)),
          tickPaint);
      canvas.drawLine(
          Offset(b.dx + nx * tickGap, b.dy + ny * tickGap),
          Offset(b.dx + nx * (tickGap + tickLen), b.dy + ny * (tickGap + tickLen)),
          tickPaint);
      // Dimension line
      canvas.drawLine(
          Offset(a.dx + nx * dimOffset, a.dy + ny * dimOffset),
          Offset(b.dx + nx * dimOffset, b.dy + ny * dimOffset),
          tickPaint);

      // Label
      final drawnMm = (pB - pA).distance * mmPerUnit;
      final dispMm =
          wallRealMm.containsKey(i) ? wallRealMm[i]! : drawnMm;
      final label = _fmtMm(dispMm);

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: wallRealMm.containsKey(i)
                ? const Color(0xFF00FF88)
                : const Color(0xFFCCEE88),
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(
            midX + nx * (dimOffset + 3) - tp.width / 2,
            midY + ny * (dimOffset + 3) - tp.height / 2,
          ));

      // Wall index label at corner
      final idxTp = TextPainter(
        text: TextSpan(
          text: 'W${i + 1}',
          style: const TextStyle(color: Color(0xFF336688), fontSize: 8),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      idxTp.paint(canvas, Offset(a.dx + 5, a.dy - 13));
    }

    // Watermark
    final wm = TextPainter(
      text: const TextSpan(
        text: 'SMARTMEASURE  ·  DXF AC1015',
        style: TextStyle(
          color: Color(0xFF0A1E2A),
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    wm.paint(
        canvas, Offset(size.width / 2 - wm.width / 2, size.height - 18));
  }

  void _drawPlaceholder(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'No room drawn yet',
        style: TextStyle(color: Color(0xFF1A3A4A), fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas,
        Offset(size.width / 2 - tp.width / 2,
            size.height / 2 - tp.height / 2));
  }

  static String _fmtMm(double mm) {
    if (mm >= 1000) return '${(mm / 1000).toStringAsFixed(2)} m';
    return '${mm.toStringAsFixed(0)} mm';
  }

  @override
  bool shouldRepaint(_BlueprintPainter old) =>
      old.points != points || old.wallRealMm != wallRealMm;
}

// ── File info card ─────────────────────────────────────────────────────────

class _FileInfoCard extends StatelessWidget {
  final bool isMock;
  final String projectName;
  final double? perimeter;
  final double? area;
  final int pointCount;

  const _FileInfoCard({
    required this.isMock,
    required this.projectName,
    required this.pointCount,
    this.perimeter,
    this.area,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
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
            // File name row
            Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 15, color: Color(0xFF00CCFF)),
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
            _row('Format', 'AutoCAD DXF  (AC1015 / R2000)'),
            _row('Units', 'Millimetres  (INSUNITS = 4)'),
            _row('Scale', '1 world unit = 5 mm'),
            _row('Layers', 'WALLS  (colour 5 = blue)'),
            _row('Corners', '$pointCount points'),
            if (perimeter != null)
              _row('Perimeter', formatLength(perimeter!)),
            if (area != null)
              _row('Area', formatArea(area!)),
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
                style: const TextStyle(
                  color: Color(0xFFAABBCC),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      );
}

// ── Wall measurements table ────────────────────────────────────────────────

class _WallTable extends StatelessWidget {
  final List<Offset> points;
  final Map<int, double> wallRealMm;

  const _WallTable({required this.points, required this.wallRealMm});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    final n = points.length;

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
                0: FlexColumnWidth(0.9),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2.2),
              },
              children: [
                // Header
                const TableRow(
                  decoration: BoxDecoration(color: Color(0xFF0C1A24)),
                  children: [
                    _TCell('WALL', header: true),
                    _TCell('DRAWN', header: true),
                    _TCell('CALIBRATED', header: true),
                  ],
                ),
                ...List.generate(n, (i) {
                  final a = points[i];
                  final b = points[(i + 1) % n];
                  final drawn = (b - a).distance;
                  final drawnStr = formatLength(drawn);
                  final hasCal = wallRealMm.containsKey(i);
                  final calStr = hasCal
                      ? '${wallRealMm[i]!.toStringAsFixed(0)} mm'
                      : '—';
                  return TableRow(
                    decoration: BoxDecoration(
                      color: i.isEven
                          ? const Color(0xFF070E16)
                          : const Color(0xFF090F18),
                    ),
                    children: [
                      _TCell('W${i + 1}', accent: true),
                      _TCell(drawnStr),
                      _TCell(calStr, calibrated: hasCal),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
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
