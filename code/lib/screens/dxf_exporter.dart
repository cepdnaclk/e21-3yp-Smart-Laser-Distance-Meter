import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ─────────────────────────────────────────────────────────────────
// DXF Exporter — AutoCAD R12 compatible (AC1009)
// AC1009 requires no subclass markers, no handles, no OBJECTS section,
// no owner references — works in every CAD tool without exception.
// Units: millimeters | Y axis flipped | 1 world unit = 5mm
// ─────────────────────────────────────────────────────────────────

class DxfExporter {
  static const double _mmPerUnit = 5.0;

  static Future<void> export({
    required List<Offset> points,
    required bool isClosed,
    required Map<int, double> wallRealMm,
    String projectName = 'SmartMeasure_Room',
  }) async {
    if (points.length < 2) throw Exception('Need at least 2 points');
    if (!isClosed) throw Exception('Close the room before exporting');

    final String content = _buildDxf(points: points, wallRealMm: wallRealMm);

    final Directory tmp = await getTemporaryDirectory();
    final String safe = projectName.replaceAll(RegExp(r'[^\w\-]'), '_');
    final File file = File('${tmp.path}/$safe.dxf');
    await file.writeAsString(content);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/dxf')],
      subject: '$projectName — Floor Plan',
    );
  }

  static double _dx(Offset p) => p.dx * _mmPerUnit;
  static double _dy(Offset p) => -(p.dy * _mmPerUnit);

  static double _dist(Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  static String _f(double v) => v.toStringAsFixed(6);

  static String _buildDxf({
    required List<Offset> points,
    required Map<int, double> wallRealMm,
  }) {
    final buf = StringBuffer();
    final int n = points.length;

    // Bounding box in DXF coordinates
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in points) {
      final x = _dx(p), y = _dy(p);
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    final double padX = (maxX - minX) * 0.15 + 200;
    final double padY = (maxY - minY) * 0.15 + 200;
    minX -= padX; minY -= padY;
    maxX += padX; maxY += padY;

    // ── HEADER ───────────────────────────────────────────────────
    _w(buf, 0, 'SECTION');
    _w(buf, 2, 'HEADER');
    _w(buf, 9, r'$ACADVER');     _w(buf, 1, 'AC1009');
    _w(buf, 9, r'$INSUNITS');    _w(buf, 70, '4');   // mm
    _w(buf, 9, r'$MEASUREMENT'); _w(buf, 70, '1');   // metric
    _w(buf, 9, r'$EXTMIN');
    _w(buf, 10, _f(minX)); _w(buf, 20, _f(minY));
    _w(buf, 9, r'$EXTMAX');
    _w(buf, 10, _f(maxX)); _w(buf, 20, _f(maxY));
    _w(buf, 9, r'$LIMMIN');
    _w(buf, 10, _f(minX)); _w(buf, 20, _f(minY));
    _w(buf, 9, r'$LIMMAX');
    _w(buf, 10, _f(maxX)); _w(buf, 20, _f(maxY));
    _w(buf, 0, 'ENDSEC');

    // ── TABLES ───────────────────────────────────────────────────
    _w(buf, 0, 'SECTION');
    _w(buf, 2, 'TABLES');

    // LTYPE table
    _w(buf, 0, 'TABLE');
    _w(buf, 2, 'LTYPE');
    _w(buf, 70, '1');
    _w(buf, 0, 'LTYPE');
    _w(buf, 2, 'CONTINUOUS');
    _w(buf, 70, '0');
    _w(buf, 3, 'Solid line');
    _w(buf, 72, '65');
    _w(buf, 73, '0');
    _w(buf, 40, '0.0');
    _w(buf, 0, 'ENDTAB');

    // LAYER table — two layers: 0 and WALLS
    _w(buf, 0, 'TABLE');
    _w(buf, 2, 'LAYER');
    _w(buf, 70, '2');
    _w(buf, 0, 'LAYER');
    _w(buf, 2, '0');
    _w(buf, 70, '0');
    _w(buf, 62, '7');
    _w(buf, 6, 'CONTINUOUS');
    _w(buf, 0, 'LAYER');
    _w(buf, 2, 'WALLS');
    _w(buf, 70, '0');
    _w(buf, 62, '5');
    _w(buf, 6, 'CONTINUOUS');
    _w(buf, 0, 'ENDTAB');

    // STYLE table
    _w(buf, 0, 'TABLE');
    _w(buf, 2, 'STYLE');
    _w(buf, 70, '1');
    _w(buf, 0, 'STYLE');
    _w(buf, 2, 'STANDARD');
    _w(buf, 70, '0');
    _w(buf, 40, '0.0');
    _w(buf, 41, '1.0');
    _w(buf, 50, '0.0');
    _w(buf, 71, '0');
    _w(buf, 42, '2.5');
    _w(buf, 3, 'txt');
    _w(buf, 4, '');
    _w(buf, 0, 'ENDTAB');

    _w(buf, 0, 'ENDSEC');

    // ── ENTITIES ─────────────────────────────────────────────────
    // In AC1009, all geometry goes directly in ENTITIES (no BLOCKS needed)
    _w(buf, 0, 'SECTION');
    _w(buf, 2, 'ENTITIES');

    // Room outline — closed 2D POLYLINE
    _w(buf, 0, 'POLYLINE');
    _w(buf, 8, 'WALLS');
    _w(buf, 62, '5');   // color: blue
    _w(buf, 66, '1');   // vertices follow
    _w(buf, 70, '1');   // closed polyline flag
    _w(buf, 10, '0.0');
    _w(buf, 20, '0.0');
    _w(buf, 30, '0.0');

    for (final p in points) {
      _w(buf, 0, 'VERTEX');
      _w(buf, 8, 'WALLS');
      _w(buf, 10, _f(_dx(p)));
      _w(buf, 20, _f(_dy(p)));
      _w(buf, 30, '0.0');
    }

    _w(buf, 0, 'SEQEND');
    _w(buf, 8, 'WALLS');

    // Wall labels and dimension lines
    double cx = 0, cy = 0;
    for (final p in points) { cx += _dx(p); cy += _dy(p); }
    cx /= n; cy /= n;

    for (int i = 0; i < n; i++) {
      final int j = (i + 1) % n;
      final Offset pA = points[i];
      final Offset pB = points[j];
      final double ax = _dx(pA), ay = _dy(pA);
      final double bx = _dx(pB), by = _dy(pB);
      final double wallLen = _dist(pA, pB);
      if (wallLen < 5) continue;

      final double wdx = bx - ax, wdy = by - ay;
      final double wLen = math.sqrt(wdx * wdx + wdy * wdy);
      if (wLen < 1) continue;

      // Normal pointing away from room centroid
      double nx = -wdy / wLen;
      double ny =  wdx / wLen;
      final double midX = (ax + bx) / 2;
      final double midY = (ay + by) / 2;
      if ((cx - midX) * nx + (cy - midY) * ny > 0) {
        nx = -nx; ny = -ny;
      }

      const double dimOffset = 80.0;
      final double tx = midX + nx * dimOffset;
      final double ty = midY + ny * dimOffset;

      double angleDeg = math.atan2(wdy, wdx) * 180 / math.pi;
      if (angleDeg > 90 || angleDeg < -90) angleDeg += 180;

      final double drawnMm = wallLen * _mmPerUnit;
      final double displayMm = wallRealMm.containsKey(i) ? wallRealMm[i]! : drawnMm;
      final String label = _formatMm(displayMm);
      final int textColor = wallRealMm.containsKey(i) ? 3 : 2; // green=calibrated, yellow=drawn

      // TEXT entity — AC1009 center/middle justification
      _w(buf, 0, 'TEXT');
      _w(buf, 8, 'WALLS');
      _w(buf, 62, '$textColor');
      _w(buf, 10, _f(tx));    // first text point
      _w(buf, 20, _f(ty));
      _w(buf, 30, '0.0');
      _w(buf, 40, '50.0');    // text height in mm
      _w(buf, 1, label);
      _w(buf, 50, _f(angleDeg));
      _w(buf, 7, 'STANDARD');
      _w(buf, 72, '1');       // horizontal center
      _w(buf, 73, '2');       // vertical middle
      _w(buf, 11, _f(tx));    // alignment point
      _w(buf, 21, _f(ty));
      _w(buf, 31, '0.0');

      // Dimension extension and main lines
      _writeDimLines(buf, ax: ax, ay: ay, bx: bx, by: by,
          nx: nx, ny: ny, offset: dimOffset);
    }

    _w(buf, 0, 'ENDSEC');
    _w(buf, 0, 'EOF');

    return buf.toString();
  }

  static void _writeDimLines(StringBuffer buf, {
    required double ax, required double ay,
    required double bx, required double by,
    required double nx, required double ny,
    required double offset,
  }) {
    const double gap = 8.0;
    const double overrun = 20.0;

    // Extension line from A
    _w(buf, 0, 'LINE');
    _w(buf, 8, 'WALLS');
    _w(buf, 62, '8');
    _w(buf, 10, _f(ax + nx * gap));
    _w(buf, 20, _f(ay + ny * gap));
    _w(buf, 30, '0.0');
    _w(buf, 11, _f(ax + nx * (offset + overrun)));
    _w(buf, 21, _f(ay + ny * (offset + overrun)));
    _w(buf, 31, '0.0');

    // Extension line from B
    _w(buf, 0, 'LINE');
    _w(buf, 8, 'WALLS');
    _w(buf, 62, '8');
    _w(buf, 10, _f(bx + nx * gap));
    _w(buf, 20, _f(by + ny * gap));
    _w(buf, 30, '0.0');
    _w(buf, 11, _f(bx + nx * (offset + overrun)));
    _w(buf, 21, _f(by + ny * (offset + overrun)));
    _w(buf, 31, '0.0');

    // Main dimension line
    _w(buf, 0, 'LINE');
    _w(buf, 8, 'WALLS');
    _w(buf, 62, '8');
    _w(buf, 10, _f(ax + nx * offset));
    _w(buf, 20, _f(ay + ny * offset));
    _w(buf, 30, '0.0');
    _w(buf, 11, _f(bx + nx * offset));
    _w(buf, 21, _f(by + ny * offset));
    _w(buf, 31, '0.0');
  }

  // Group code + value, CRLF line endings (standard for DXF)
  static void _w(StringBuffer buf, int code, String value) {
    buf.write(code.toString().padLeft(3));
    buf.write('\r\n');
    buf.write(value);
    buf.write('\r\n');
  }

  static String _formatMm(double mm) {
    if (mm >= 1000) return '${(mm / 1000).toStringAsFixed(2)} m';
    return '${mm.toStringAsFixed(0)} mm';
  }
}
