// lib/ar/ar_result_screen.dart
//
// Phase AR-5: Shows the AR-derived room polygon with draggable corner handles,
// a scale-correction slider, wall dimension labels, and an "Import to Sketch"
// button that creates a SketchShape and opens SketchScreen.

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../sketch/sketch_constants.dart';
import '../sketch/sketch_model.dart';
import '../sketch/sketch_screen.dart';

class ARResultScreen extends StatefulWidget {
  /// Ordered room corners in millimetres, derived from AR wall planes.
  final List<Offset> polygonMm;

  const ARResultScreen({super.key, required this.polygonMm});

  @override
  State<ARResultScreen> createState() => _ARResultScreenState();
}

class _ARResultScreenState extends State<ARResultScreen> {
  late List<Offset> _corners; // mutable: user can drag corners
  double _scaleCorrection = 1.0;
  int? _draggingIndex;

  // View transform — recalculated in LayoutBuilder each frame.
  Offset _viewOrigin = Offset.zero;
  double _viewScale = 1.0;

  @override
  void initState() {
    super.initState();
    _corners = List.of(widget.polygonMm);
  }

  // ── Derived helpers ────────────────────────────────────────────────────────

  List<Offset> get _displayed =>
      _corners.map((c) => c * _scaleCorrection).toList();

  Offset _toScreen(Offset mm) =>
      Offset(mm.dx * _viewScale + _viewOrigin.dx,
             mm.dy * _viewScale + _viewOrigin.dy);

  Offset _toMm(Offset screen) =>
      Offset((screen.dx - _viewOrigin.dx) / _viewScale,
             (screen.dy - _viewOrigin.dy) / _viewScale);

  void _recomputeView(Size size) {
    final pts = _displayed;
    if (pts.isEmpty) return;
    final minX = pts.fold(double.infinity, (m, c) => math.min(m, c.dx));
    final maxX = pts.fold(double.negativeInfinity, (m, c) => math.max(m, c.dx));
    final minY = pts.fold(double.infinity, (m, c) => math.min(m, c.dy));
    final maxY = pts.fold(double.negativeInfinity, (m, c) => math.max(m, c.dy));
    final w = maxX - minX;
    final h = maxY - minY;
    if (w < 1 || h < 1) return;
    _viewScale = math.min(
      (size.width - 80) / w,
      (size.height - 80) / h,
    );
    _viewOrigin = Offset(
      size.width / 2 - (minX + w / 2) * _viewScale,
      size.height / 2 - (minY + h / 2) * _viewScale,
    );
  }

  // ── Drag interaction ───────────────────────────────────────────────────────

  void _onPanStart(Offset pos) {
    final pts = _displayed;
    for (int i = 0; i < pts.length; i++) {
      if ((_toScreen(pts[i]) - pos).distance < 26) {
        setState(() => _draggingIndex = i);
        return;
      }
    }
  }

  void _onPanUpdate(Offset pos) {
    if (_draggingIndex == null) return;
    // Convert screen → mm, then undo scale correction to store in _corners.
    final raw = _toMm(pos) / _scaleCorrection;
    setState(() => _corners[_draggingIndex!] = raw);
  }

  void _onPanEnd() => setState(() => _draggingIndex = null);

  // ── Import ─────────────────────────────────────────────────────────────────

  void _importToSketch() {
    final pts = _displayed; // mm after scale correction

    // mm → canvas world units (1 unit = mmPerUnit = 5 mm).
    final unitPts = pts.map((p) => Offset(p.dx / mmPerUnit, p.dy / mmPerUnit)).toList();

    // Centre the polygon on canvas position (200, 200).
    final cx = unitPts.fold(0.0, (s, p) => s + p.dx) / unitPts.length;
    final cy = unitPts.fold(0.0, (s, p) => s + p.dy) / unitPts.length;
    const anchor = Offset(200, 200);
    final centred = unitPts
        .map((p) => Offset(p.dx - cx + anchor.dx, p.dy - cy + anchor.dy))
        .toList();

    // Build wallRealMm: actual length of each wall segment in mm.
    final wallRealMm = <int, double>{};
    for (int i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      wallRealMm[i] = math.sqrt(dx * dx + dy * dy);
    }

    final shape = SketchShape(
      points: centred,
      isClosed: true,
      label: 'AR Scan',
      wallRealMm: wallRealMm,
      heightMm: 2400,
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => SketchScreen(initialShapes: [shape]),
      ),
      (route) => route.isFirst, // pop back to HomeScreen
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Result'),
        actions: [
          TextButton.icon(
            onPressed: _importToSketch,
            icon: const Icon(Icons.check),
            label: const Text('Import to Sketch'),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildScaleSlider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'Drag corner handles to fine-tune. Tap "Import to Sketch" when ready.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(child: _buildPolygonView()),
          _buildDimensionChips(),
        ],
      ),
    );
  }

  Widget _buildScaleSlider() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Text('Scale:', style: TextStyle(fontSize: 13)),
          Expanded(
            child: Slider(
              value: _scaleCorrection,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              label: '${_scaleCorrection.toStringAsFixed(2)}×',
              onChanged: (v) => setState(() => _scaleCorrection = v),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${_scaleCorrection.toStringAsFixed(2)}×',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolygonView() {
    return LayoutBuilder(builder: (_, box) {
      _recomputeView(box.biggest);
      return GestureDetector(
        onPanStart: (d) => _onPanStart(d.localPosition),
        onPanUpdate: (d) => _onPanUpdate(d.localPosition),
        onPanEnd: (_) => _onPanEnd(),
        child: CustomPaint(
          painter: _PolygonPainter(
            corners: _displayed,
            viewOrigin: _viewOrigin,
            viewScale: _viewScale,
            draggingIndex: _draggingIndex,
          ),
          size: box.biggest,
        ),
      );
    });
  }

  Widget _buildDimensionChips() {
    final pts = _displayed;
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (int i = 0; i < pts.length; i++)
            Builder(builder: (_) {
              final a = pts[i];
              final b = pts[(i + 1) % pts.length];
              final len = math.sqrt(
                  math.pow(b.dx - a.dx, 2) + math.pow(b.dy - a.dy, 2));
              final label = len >= 1000
                  ? '${(len / 1000).toStringAsFixed(2)} m'
                  : '${len.toStringAsFixed(0)} mm';
              return Chip(
                label: Text('W${i + 1}: $label',
                    style: const TextStyle(fontSize: 11)),
                backgroundColor: Colors.blue.shade50,
                visualDensity: VisualDensity.compact,
              );
            }),
        ],
      ),
    );
  }
}

// ── Polygon painter ───────────────────────────────────────────────────────────

class _PolygonPainter extends CustomPainter {
  final List<Offset> corners; // in mm
  final Offset viewOrigin;
  final double viewScale;
  final int? draggingIndex;

  const _PolygonPainter({
    required this.corners,
    required this.viewOrigin,
    required this.viewScale,
    this.draggingIndex,
  });

  Offset _s(Offset mm) =>
      Offset(mm.dx * viewScale + viewOrigin.dx,
             mm.dy * viewScale + viewOrigin.dy);

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 3) return;

    final sc = corners.map(_s).toList();
    final path = Path()..addPolygon(sc, true);

    // Room fill
    canvas.drawPath(path, Paint()..color = Colors.blue.withValues(alpha: 0.10));

    // Wall outlines
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blue.shade700
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    // Wall dimension labels
    for (int i = 0; i < corners.length; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % corners.length];
      final len = math.sqrt(
          math.pow(b.dx - a.dx, 2) + math.pow(b.dy - a.dy, 2));
      final label = len >= 1000
          ? '${(len / 1000).toStringAsFixed(2)} m'
          : '${len.toStringAsFixed(0)} mm';

      final sa = sc[i];
      final sb = sc[(i + 1) % sc.length];
      final mid = Offset((sa.dx + sb.dx) / 2, (sa.dy + sb.dy) / 2);

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: Colors.blue.shade900, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2 + 12));
    }

    // Corner handles
    for (int i = 0; i < sc.length; i++) {
      final isDragging = i == draggingIndex;
      final r = isDragging ? 15.0 : 9.0;
      final colour = isDragging ? Colors.orange : Colors.blue;

      canvas.drawCircle(sc[i], r, Paint()..color = colour);
      canvas.drawCircle(
        sc[i],
        r,
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );

      // Corner number
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, sc[i] - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PolygonPainter old) =>
      old.corners != corners ||
      old.viewOrigin != viewOrigin ||
      old.viewScale != viewScale ||
      old.draggingIndex != draggingIndex;
}
