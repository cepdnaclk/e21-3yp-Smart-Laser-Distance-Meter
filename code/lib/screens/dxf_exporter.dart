import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../sketch/room_object.dart';
import '../sketch/furniture_item.dart';

// ─────────────────────────────────────────────────────────────────
// DXF Exporter — AutoCAD R12 (AC1009)
// Layers: WALLS (blue-5), DOORS (red-1), WINDOWS (cyan-4), FURNITURE (green-3)
// Units: millimetres | 1 world unit = 5 mm | Y axis flipped for DXF
// ─────────────────────────────────────────────────────────────────

class DxfExporter {
  static const double _mm = 5.0; // world units → mm

  static Future<void> export({
    required List<Offset> points,
    required bool isClosed,
    required Map<int, double> wallRealMm,
    List<RoomObject> roomObjects = const [],
    List<FurnitureItem> furnitureItems = const [],
    String projectName = 'SmartMeasure_Room',
  }) async {
    if (points.length < 2) throw Exception('Need at least 2 points');
    if (!isClosed) throw Exception('Close the room before exporting');

    final content = _buildDxf(
      points: points,
      wallRealMm: wallRealMm,
      roomObjects: roomObjects,
      furnitureItems: furnitureItems,
    );

    final tmp = await getTemporaryDirectory();
    final safe = projectName.replaceAll(RegExp(r'[^\w\-]'), '_');
    final file = File('${tmp.path}/$safe.dxf');
    await file.writeAsString(content);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/dxf')],
      subject: '$projectName — Floor Plan',
    );
  }

  // ── Coordinate helpers ────────────────────────────────────────
  static double _wx(double worldX) => worldX * _mm;
  static double _wy(double worldY) => -(worldY * _mm); // Y flip for DXF
  static String _f(double v) => v.toStringAsFixed(4);

  // ── DXF builder ───────────────────────────────────────────────
  static String _buildDxf({
    required List<Offset> points,
    required Map<int, double> wallRealMm,
    required List<RoomObject> roomObjects,
    required List<FurnitureItem> furnitureItems,
  }) {
    final buf = StringBuffer();
    final int n = points.length;

    // Bounding box from walls + furniture
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    void expandBounds(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    for (final p in points) { expandBounds(_wx(p.dx), _wy(p.dy)); }
    for (final f in furnitureItems) { expandBounds(_wx(f.position.dx), _wy(f.position.dy)); }
    final px = (maxX - minX) * 0.15 + 300;
    final py = (maxY - minY) * 0.15 + 300;
    minX -= px; minY -= py; maxX += px; maxY += py;

    // ── HEADER ─────────────────────────────────────────────────
    _w(buf, 0, 'SECTION');
    _w(buf, 2, 'HEADER');
    _w(buf, 9, r'$ACADVER');     _w(buf, 1, 'AC1009');
    _w(buf, 9, r'$INSUNITS');    _w(buf, 70, '4');
    _w(buf, 9, r'$MEASUREMENT'); _w(buf, 70, '1');
    _w(buf, 9, r'$EXTMIN'); _w(buf, 10, _f(minX)); _w(buf, 20, _f(minY));
    _w(buf, 9, r'$EXTMAX'); _w(buf, 10, _f(maxX)); _w(buf, 20, _f(maxY));
    _w(buf, 9, r'$LIMMIN'); _w(buf, 10, _f(minX)); _w(buf, 20, _f(minY));
    _w(buf, 9, r'$LIMMAX'); _w(buf, 10, _f(maxX)); _w(buf, 20, _f(maxY));
    _w(buf, 0, 'ENDSEC');

    // ── TABLES ─────────────────────────────────────────────────
    _w(buf, 0, 'SECTION');
    _w(buf, 2, 'TABLES');

    // LTYPE
    _w(buf, 0, 'TABLE'); _w(buf, 2, 'LTYPE'); _w(buf, 70, '1');
    _w(buf, 0, 'LTYPE'); _w(buf, 2, 'CONTINUOUS');
    _w(buf, 70, '0'); _w(buf, 3, 'Solid line');
    _w(buf, 72, '65'); _w(buf, 73, '0'); _w(buf, 40, '0.0');
    _w(buf, 0, 'ENDTAB');

    // LAYER: 0 / WALLS / DOORS / WINDOWS / FURNITURE
    _w(buf, 0, 'TABLE'); _w(buf, 2, 'LAYER'); _w(buf, 70, '5');
    for (final r in [
      ('0', '7'), ('WALLS', '5'), ('DOORS', '1'),
      ('WINDOWS', '4'), ('FURNITURE', '3'),
    ]) {
      _w(buf, 0, 'LAYER'); _w(buf, 2, r.$1);
      _w(buf, 70, '0'); _w(buf, 62, r.$2); _w(buf, 6, 'CONTINUOUS');
    }
    _w(buf, 0, 'ENDTAB');

    // STYLE
    _w(buf, 0, 'TABLE'); _w(buf, 2, 'STYLE'); _w(buf, 70, '1');
    _w(buf, 0, 'STYLE'); _w(buf, 2, 'STANDARD');
    _w(buf, 70, '0'); _w(buf, 40, '0.0'); _w(buf, 41, '1.0');
    _w(buf, 50, '0.0'); _w(buf, 71, '0'); _w(buf, 42, '2.5');
    _w(buf, 3, 'txt'); _w(buf, 4, '');
    _w(buf, 0, 'ENDTAB');

    _w(buf, 0, 'ENDSEC');

    // ── ENTITIES ───────────────────────────────────────────────
    _w(buf, 0, 'SECTION');
    _w(buf, 2, 'ENTITIES');

    _writeWalls(buf, points, n);
    _writeWallDims(buf, points, wallRealMm, n);
    _writeRoomObjects(buf, points, n, roomObjects);
    _writeFurniture(buf, furnitureItems);

    _w(buf, 0, 'ENDSEC');
    _w(buf, 0, 'EOF');

    return buf.toString();
  }

  // ── Walls ─────────────────────────────────────────────────────
  static void _writeWalls(StringBuffer buf, List<Offset> points, int n) {
    _w(buf, 0, 'POLYLINE');
    _w(buf, 8, 'WALLS'); _w(buf, 62, '5');
    _w(buf, 66, '1'); _w(buf, 70, '1');
    _w(buf, 10, '0.0'); _w(buf, 20, '0.0'); _w(buf, 30, '0.0');
    for (final p in points) {
      _w(buf, 0, 'VERTEX'); _w(buf, 8, 'WALLS');
      _w(buf, 10, _f(_wx(p.dx))); _w(buf, 20, _f(_wy(p.dy))); _w(buf, 30, '0.0');
    }
    _w(buf, 0, 'SEQEND'); _w(buf, 8, 'WALLS');
  }

  // ── Wall dimension labels ─────────────────────────────────────
  static void _writeWallDims(StringBuffer buf, List<Offset> points,
      Map<int, double> wallRealMm, int n) {
    // Centroid in DXF space (for normal direction)
    double cx = 0, cy = 0;
    for (final p in points) { cx += _wx(p.dx); cy += _wy(p.dy); }
    cx /= n; cy /= n;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final ax = _wx(points[i].dx), ay = _wy(points[i].dy);
      final bx = _wx(points[j].dx), by = _wy(points[j].dy);
      final wdx = bx - ax, wdy = by - ay;
      final wLen = math.sqrt(wdx * wdx + wdy * wdy);
      if (wLen < 25) continue;

      final ux = wdx / wLen, uy = wdy / wLen;
      double nx = -uy, ny = ux;
      final midX = (ax + bx) / 2, midY = (ay + by) / 2;
      if ((cx - midX) * nx + (cy - midY) * ny > 0) { nx = -nx; ny = -ny; }

      const double off = 80.0;
      final tx = midX + nx * off, ty = midY + ny * off;
      double ang = math.atan2(uy, ux) * 180 / math.pi;
      if (ang > 90 || ang < -90) ang += 180;

      final worldLen = (points[j] - points[i]).distance;
      final dispMm = wallRealMm.containsKey(i) ? wallRealMm[i]! : worldLen * _mm;
      _writeText(buf, 'WALLS', wallRealMm.containsKey(i) ? 3 : 2,
          tx, ty, ang, 50.0, _fmtMm(dispMm));

      const double gap = 8.0, ovr = 20.0;
      _line(buf, 'WALLS', 8, ax+nx*gap, ay+ny*gap, ax+nx*(off+ovr), ay+ny*(off+ovr));
      _line(buf, 'WALLS', 8, bx+nx*gap, by+ny*gap, bx+nx*(off+ovr), by+ny*(off+ovr));
      _line(buf, 'WALLS', 8, ax+nx*off, ay+ny*off, bx+nx*off, by+ny*off);
    }
  }

  // ── Doors & Windows ───────────────────────────────────────────
  static void _writeRoomObjects(StringBuffer buf, List<Offset> points,
      int n, List<RoomObject> roomObjects) {
    if (roomObjects.isEmpty) return;

    // Room centroid in world units (to determine inward direction)
    Offset cent = points.fold(Offset.zero, (s, p) => s + p);
    cent = Offset(cent.dx / n, cent.dy / n);

    for (final obj in roomObjects) {
      if (obj.wallIndex >= n) continue;
      final wA = points[obj.wallIndex];
      final wB = points[(obj.wallIndex + 1) % n];
      final wallVec = wB - wA;
      final wallLen = wallVec.distance;
      if (wallLen < 1) continue;

      // Wall unit direction (world)
      final wallDir = Offset(wallVec.dx / wallLen, wallVec.dy / wallLen);
      final halfW = (obj.widthMm / _mm) / 2;

      // Door/window endpoints along wall (world)
      final tCenter = obj.positionAlong * wallLen;
      final startW = wA + Offset(wallDir.dx * (tCenter - halfW), wallDir.dy * (tCenter - halfW));
      final endW   = wA + Offset(wallDir.dx * (tCenter + halfW), wallDir.dy * (tCenter + halfW));

      // Inward normal (world) — points toward centroid
      Offset inW = Offset(-wallDir.dy, wallDir.dx);
      final wallMid = Offset((wA.dx + wB.dx) / 2, (wA.dy + wB.dy) / 2);
      if ((cent.dx - wallMid.dx) * inW.dx + (cent.dy - wallMid.dy) * inW.dy < 0) {
        inW = Offset(-inW.dx, -inW.dy);
      }
      if (obj.swingFlipped) inW = Offset(-inW.dx, -inW.dy);

      // Convert to DXF mm
      final sx = _wx(startW.dx), sy = _wy(startW.dy);
      final ex = _wx(endW.dx),   ey = _wy(endW.dy);
      // Unit direction in DXF (Y flipped)
      final wux = wallDir.dx, wuy = -wallDir.dy;
      final iux = inW.dx,     iuy = -inW.dy;

      if (obj.isDoor) {
        _writeDoor(buf, sx, sy, ex, ey, obj.widthMm, wux, wuy, iux, iuy);
      } else {
        _writeWindow(buf, sx, sy, ex, ey, obj.widthMm, wux, wuy, iux, iuy);
      }
    }
  }

  static void _writeDoor(StringBuffer buf,
      double sx, double sy, double ex, double ey, double widthMm,
      double wux, double wuy, double iux, double iuy) {
    // Hinge = start point; door leaf swings inward
    final ltx = sx + iux * widthMm;
    final lty = sy + iuy * widthMm;

    _line(buf, 'DOORS', 1, sx, sy, ltx, lty);  // door leaf
    _line(buf, 'DOORS', 1, sx, sy, ex, ey);     // door stop along wall

    // Arc (quarter-circle swing)
    final wallAng   = math.atan2(wuy, wux) * 180 / math.pi;
    final inwardAng = math.atan2(iuy, iux) * 180 / math.pi;
    final cross = wux * iuy - wuy * iux;
    final arcStart = cross > 0 ? wallAng   : inwardAng;
    final arcEnd   = cross > 0 ? inwardAng : wallAng;
    _arc(buf, 'DOORS', 1, sx, sy, widthMm, arcStart, arcEnd);

    // Dimension annotation — outside room (outward = -inward), same style as walls
    const double dimOff = 50.0, gap = 5.0, ovr = 15.0;
    final ox = -iux, oy = -iuy;
    final midX = (sx + ex) / 2, midY = (sy + ey) / 2;
    final tx = midX + ox * dimOff, ty = midY + oy * dimOff;
    double ang = math.atan2(wuy, wux) * 180 / math.pi;
    if (ang > 90 || ang < -90) ang += 180;
    _line(buf, 'DOORS', 1, sx+ox*gap, sy+oy*gap, sx+ox*(dimOff+ovr), sy+oy*(dimOff+ovr));
    _line(buf, 'DOORS', 1, ex+ox*gap, ey+oy*gap, ex+ox*(dimOff+ovr), ey+oy*(dimOff+ovr));
    _line(buf, 'DOORS', 1, sx+ox*dimOff, sy+oy*dimOff, ex+ox*dimOff, ey+oy*dimOff);
    _writeText(buf, 'DOORS', 1, tx, ty, ang, 40.0, _fmtMm(widthMm));
  }

  static void _writeWindow(StringBuffer buf,
      double sx, double sy, double ex, double ey, double widthMm,
      double wux, double wuy, double iux, double iuy) {
    const double sp = 55.0;   // glazing line spacing (mm)
    const double jl = 130.0;  // jamb line half-length (mm)

    // Three glazing lines parallel to wall
    for (final t in [-sp, 0.0, sp]) {
      _line(buf, 'WINDOWS', 4,
          sx + iux * t, sy + iuy * t,
          ex + iux * t, ey + iuy * t);
    }
    // Jamb lines perpendicular at each end
    _line(buf, 'WINDOWS', 4, sx - iux*jl, sy - iuy*jl, sx + iux*jl, sy + iuy*jl);
    _line(buf, 'WINDOWS', 4, ex - iux*jl, ey - iuy*jl, ex + iux*jl, ey + iuy*jl);

    // Dimension annotation — outside room, same style as walls
    const double dimOff = 50.0, gap = 5.0, ovr = 15.0;
    final ox = -iux, oy = -iuy;
    final midX = (sx + ex) / 2, midY = (sy + ey) / 2;
    final tx = midX + ox * dimOff, ty = midY + oy * dimOff;
    double ang = math.atan2(wuy, wux) * 180 / math.pi;
    if (ang > 90 || ang < -90) ang += 180;
    _line(buf, 'WINDOWS', 4, sx+ox*gap, sy+oy*gap, sx+ox*(dimOff+ovr), sy+oy*(dimOff+ovr));
    _line(buf, 'WINDOWS', 4, ex+ox*gap, ey+oy*gap, ex+ox*(dimOff+ovr), ey+oy*(dimOff+ovr));
    _line(buf, 'WINDOWS', 4, sx+ox*dimOff, sy+oy*dimOff, ex+ox*dimOff, ey+oy*dimOff);
    _writeText(buf, 'WINDOWS', 4, tx, ty, ang, 40.0, _fmtMm(widthMm));
  }

  // ── Furniture ─────────────────────────────────────────────────
  static void _writeFurniture(StringBuffer buf, List<FurnitureItem> items) {
    for (final item in items) {
      final cx = _wx(item.position.dx);
      final cy = _wy(item.position.dy);
      final rad = item.rotationDeg * math.pi / 180;

      // Width and depth unit vectors in DXF space (Y-flipped)
      final ux = math.cos(rad),  uy = -math.sin(rad); // width direction
      final vx = math.sin(rad),  vy =  math.cos(rad); // depth direction

      final hw = item.widthMm / 2;
      final hd = item.depthMm / 2;

      // 4 corners
      final c = [
        (cx + ux*hw + vx*hd, cy + uy*hw + vy*hd),
        (cx - ux*hw + vx*hd, cy - uy*hw + vy*hd),
        (cx - ux*hw - vx*hd, cy - uy*hw - vy*hd),
        (cx + ux*hw - vx*hd, cy + uy*hw - vy*hd),
      ];

      // 4 sides
      for (int k = 0; k < 4; k++) {
        final a = c[k], b = c[(k + 1) % 4];
        _line(buf, 'FURNITURE', 3, a.$1, a.$2, b.$1, b.$2);
      }

      // Diagonal cross (makes furniture easy to identify)
      _line(buf, 'FURNITURE', 8, c[0].$1, c[0].$2, c[2].$1, c[2].$2);
      _line(buf, 'FURNITURE', 8, c[1].$1, c[1].$2, c[3].$1, c[3].$2);

      // Label at center
      _writeText(buf, 'FURNITURE', 3, cx, cy, 0, 40.0, item.type.displayName);
    }
  }

  // ── Primitive writers ─────────────────────────────────────────
  static void _line(StringBuffer buf, String layer, int color,
      double x1, double y1, double x2, double y2) {
    _w(buf, 0, 'LINE');
    _w(buf, 8, layer); _w(buf, 62, '$color');
    _w(buf, 10, _f(x1)); _w(buf, 20, _f(y1)); _w(buf, 30, '0.0');
    _w(buf, 11, _f(x2)); _w(buf, 21, _f(y2)); _w(buf, 31, '0.0');
  }

  static void _arc(StringBuffer buf, String layer, int color,
      double cx, double cy, double radius,
      double startAngle, double endAngle) {
    _w(buf, 0, 'ARC');
    _w(buf, 8, layer); _w(buf, 62, '$color');
    _w(buf, 10, _f(cx)); _w(buf, 20, _f(cy)); _w(buf, 30, '0.0');
    _w(buf, 40, _f(radius));
    _w(buf, 50, _f(startAngle));
    _w(buf, 51, _f(endAngle));
  }

  static void _writeText(StringBuffer buf, String layer, int color,
      double tx, double ty, double angleDeg, double height, String text) {
    _w(buf, 0, 'TEXT');
    _w(buf, 8, layer); _w(buf, 62, '$color');
    _w(buf, 10, _f(tx)); _w(buf, 20, _f(ty)); _w(buf, 30, '0.0');
    _w(buf, 40, _f(height));
    _w(buf, 1, text);
    _w(buf, 50, _f(angleDeg));
    _w(buf, 7, 'STANDARD');
    _w(buf, 72, '1'); _w(buf, 73, '2');
    _w(buf, 11, _f(tx)); _w(buf, 21, _f(ty)); _w(buf, 31, '0.0');
  }

  static void _w(StringBuffer buf, int code, String value) {
    buf.write(code.toString().padLeft(3));
    buf.write('\r\n');
    buf.write(value);
    buf.write('\r\n');
  }

  static String _fmtMm(double mm) {
    if (mm >= 1000) return '${(mm / 1000).toStringAsFixed(2)} m';
    return '${mm.toStringAsFixed(0)} mm';
  }
}
