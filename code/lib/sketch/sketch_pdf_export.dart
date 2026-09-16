// lib/sketch/sketch_pdf_export.dart

import 'dart:math' as math;
import 'package:flutter/material.dart'
    show BuildContext, Color, Offset, ScaffoldMessenger, SnackBar, Text;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'sketch_constants.dart';
import 'sketch_model.dart';
import 'room_object.dart';
import 'furniture_item.dart';

// ── Canvas layout constants ──────────────────────────────────────────────────
const double _cs = 296.0; // canvas square size (PDF points)
const double _cm = 18.0;  // canvas inner margin
const double _da = _cs - _cm * 2; // drawable area
const double _csOv = 480.0; // overview canvas square size (PDF points)
const double _daOv = _csOv - _cm * 2; // overview drawable area
// Extra breathing room for dimension lines; the plan keeps its existing scale.
const double _dimMargin = 30.0;
const double _csOvDim = _daOv + _dimMargin * 2;
const double _roomDimMargin = 22.0;
const double _csRoomDim = _da + _roomDimMargin * 2;

// ── Coordinate transformer ───────────────────────────────────────────────────
class _Tx {
  final double minX, minY, scale, canvasSize, margin;
  const _Tx(this.minX, this.minY, this.scale, this.canvasSize,
      [this.margin = _cm]);

  PdfPoint call(Offset w) => PdfPoint(
        margin + (w.dx - minX) * scale,
        canvasSize - margin - (w.dy - minY) * scale,
      );
}

_Tx _txFor(List<Offset> pts, [double da = _da]) {
  double minX = pts.map((p) => p.dx).reduce(math.min);
  double maxX = pts.map((p) => p.dx).reduce(math.max);
  double minY = pts.map((p) => p.dy).reduce(math.min);
  double maxY = pts.map((p) => p.dy).reduce(math.max);
  final s = da / math.max((maxX - minX).clamp(1.0, double.infinity),
                          (maxY - minY).clamp(1.0, double.infinity));
  final canvasSize = da == _da ? _cs : _csOv;
  return _Tx(minX, minY, s, canvasSize);
}

_Tx _txAll(List<SketchShape> shapes, [double da = _da]) {
  final pts = [for (final s in shapes) ...s.points];
  return _txFor(pts, da);
}

// ── Public entry point ───────────────────────────────────────────────────────
Future<void> exportSketchPdf({
  required BuildContext context,
  required List<SketchShape> shapes,
  required String projectName,
}) async {
  final valid = shapes.where((s) => s.points.length >= 2).toList();
  if (valid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Draw a room first'),
          backgroundColor: Color(0xFF333333)),
    );
    return;
  }

  final totalPages = 2 + valid.length;
  final pdf = pw.Document();
  final referenceScale = _txAll(valid, _daOv).scale;

  pdf.addPage(_coverPage(valid, projectName, totalPages));
  pdf.addPage(_overviewPage(valid, projectName, 2, totalPages));
  for (int i = 0; i < valid.length; i++) {
    pdf.addPage(_roomPage(valid[i], i, 3 + i, totalPages, referenceScale));
  }

  await Printing.layoutPdf(
    onLayout: (_) async => pdf.save(),
    name: 'floor_plan_guide',
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE BUILDERS
// ═══════════════════════════════════════════════════════════════════════════

// ── Cover / Index page ───────────────────────────────────────────────────────
pw.Page _coverPage(
    List<SketchShape> valid, String projectName, int totalPages) {
  final closedCount = valid.where((s) => s.isClosed).length;
  final totalArea = valid.fold(0.0, (d, s) => d + _shapeArea(s));

  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.zero,
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Dark header
        pw.Container(
          color: const PdfColor(0.13, 0.20, 0.30),
          padding: const pw.EdgeInsets.fromLTRB(44, 52, 44, 36),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('FLOOR PLAN GUIDE',
                  style: pw.TextStyle(
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 2)),
              pw.SizedBox(height: 8),
              pw.Text(
                projectName.isNotEmpty ? projectName : 'SmartMeasure Project',
                style: const pw.TextStyle(
                    fontSize: 13, color: PdfColors.blueGrey100),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Generated  ${_date()}   •   SmartMeasure Pro',
                style: const pw.TextStyle(
                    fontSize: 8.5, color: PdfColors.blueGrey300),
              ),
            ],
          ),
        ),

        // Accent stats bar
        pw.Container(
          color: const PdfColor(0.19, 0.29, 0.41),
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 44, vertical: 14),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _coverStat('ROOMS', '$closedCount'),
              _coverStat('TOTAL AREA', formatArea(totalArea)),
              _coverStat('TOTAL PAGES', '$totalPages'),
            ],
          ),
        ),

        pw.SizedBox(height: 32),

        // Table of contents
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 44),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('TABLE OF CONTENTS',
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor(0.13, 0.20, 0.30),
                      letterSpacing: 1.8)),
              pw.SizedBox(height: 10),
              pw.Divider(
                  color: const PdfColor(0.13, 0.20, 0.30), thickness: 1.5),
              pw.SizedBox(height: 2),
              _tocRow('Full Floor Plan Overview', 2, bold: true),
              pw.Divider(color: PdfColors.blueGrey200, thickness: 0.5),
              for (int i = 0; i < valid.length; i++) ...[
                _tocRow(
                  _roomName(valid[i], i),
                  3 + i,
                  sub: _roomSub(valid[i]),
                ),
                if (i < valid.length - 1)
                  pw.Divider(color: PdfColors.blueGrey100, thickness: 0.5),
              ],
              pw.Divider(color: PdfColors.blueGrey200, thickness: 0.5),
            ],
          ),
        ),

        pw.Spacer(),

        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(44, 0, 44, 28),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('SmartMeasure Pro — Floor Plan Guide',
                  style: const pw.TextStyle(
                      fontSize: 7.5, color: PdfColors.grey500)),
              pw.Text('Page 1 of $totalPages',
                  style: const pw.TextStyle(
                      fontSize: 7.5, color: PdfColors.grey500)),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Full overview page ───────────────────────────────────────────────────────
pw.Page _overviewPage(
    List<SketchShape> valid, String projectName, int pageNum, int totalPages) {
  final baseTx = _txAll(valid, _daOv);
  final tx = _Tx(baseTx.minX, baseTx.minY, baseTx.scale, _csOvDim, _dimMargin);

  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pageHeader('Full Floor Plan', projectName, pageNum, totalPages),
        pw.SizedBox(height: 10),
        pw.Center(
          child: _canvasBox(
            pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    painter: (g, size) {
                    _paintGrid(g, size);

                    // Pass 1: room fills (white)
                    for (final s in valid) {
                      final n = s.points.length;
                      if (n < 3 || !s.isClosed) continue;
                      g.setFillColor(PdfColors.white);
                      final f = tx(s.points[0]);
                      g.moveTo(f.x, f.y);
                      for (int i = 1; i < n; i++) {
                        final p = tx(s.points[i]);
                        g.lineTo(p.x, p.y);
                      }
                      g.closePath();
                      g.fillPath();
                    }

                    // Pass 2: every wall for every room, filled black.
                    for (final s in valid) {
                      final n = s.points.length;
                      if (n < 2) continue;
                      final wc = s.isClosed ? n : n - 1;
                      g.setFillColor(PdfColors.black);
                      for (int i = 0; i < wc; i++) {
                        final corners = thickWallRect(s.points[i],
                            s.points[(i + 1) % n], wallThickness);
                        if (corners.isEmpty) continue;
                        final c0 = tx(corners[0]);
                        final c1 = tx(corners[1]);
                        final c2 = tx(corners[2]);
                        final c3 = tx(corners[3]);
                        g.moveTo(c0.x, c0.y);
                        g.lineTo(c1.x, c1.y);
                        g.lineTo(c2.x, c2.y);
                        g.lineTo(c3.x, c3.y);
                        g.closePath();
                        g.fillPath();
                      }
                    }

                    // Pass 3: furniture, then door/window cuts and symbols.
                    for (final s in valid) {
                      final n = s.points.length;
                      if (n < 2) continue;
                      final wc = s.isClosed ? n : n - 1;

                      for (final item in s.furnitureItems) {
                        _paintFurniture(g, item, tx);
                      }

                      if (s.isClosed && s.roomObjects.isNotEmpty) {
                        Offset centroid = Offset.zero;
                        for (final p in s.points) {
                          centroid =
                              Offset(centroid.dx + p.dx, centroid.dy + p.dy);
                        }
                        centroid = Offset(centroid.dx / n, centroid.dy / n);
                        _paintRoomObjects(g, s.points, n, wc, s.roomObjects,
                            tx, centroid, wallThickness);
                      }
                    }
                    _paintFullPlanDimensions(g, valid, tx);
                    },
                  ),
                ),
                for (int si = 0; si < valid.length; si++)
                  if (valid[si].isClosed && valid[si].points.length >= 3)
                    _roomLabelOverlay(valid[si], si, tx),
                ..._fullPlanDimensionLabels(valid, tx),
              ],
            ),
            size: _csOvDim,
          ),
        ),
        pw.SizedBox(height: 14),

        // Room index table
        _sectionLabel('Room Index'),
        pw.SizedBox(height: 5),
        pw.Table(
          border:
              pw.TableBorder.all(color: PdfColors.blueGrey200, width: 0.5),
          columnWidths: {
            0: const pw.FixedColumnWidth(22),
            1: const pw.FlexColumnWidth(2.2),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FixedColumnWidth(30),
          },
          children: [
            pw.TableRow(
              decoration:
                  const pw.BoxDecoration(color: PdfColors.blueGrey100),
              children:
                  ['#', 'Room Name', 'Perimeter', 'Area', 'Pg']
                      .map(_thCell)
                      .toList(),
            ),
            for (int i = 0; i < valid.length; i++)
              pw.TableRow(children: [
                _tdCell('${i + 1}'),
                _tdCell(_roomName(valid[i], i)),
                _tdCell(_perimStr(valid[i])),
                _tdCell(_areaStr(valid[i])),
                _tdCell('${3 + i}'),
              ]),
          ],
        ),

        pw.Spacer(),
        _pageFooter('SmartMeasure Pro — Floor Plan Guide', pageNum, totalPages),
      ],
    ),
  );
}

// ── Room detail page ─────────────────────────────────────────────────────────
pw.Page _roomPage(
    SketchShape shape, int roomIdx, int pageNum, int totalPages,
    double referenceScale) {
  final n = shape.points.length;
  final wallCount = shape.isClosed ? n : n - 1;
  final baseTx = _txFor(shape.points);
  final tx = _Tx(
      baseTx.minX, baseTx.minY, baseTx.scale, _csRoomDim, _roomDimMargin);
  final effectiveWallThickness = (wallThickness * referenceScale) / tx.scale;

  // Centroid for door/window inward direction
  Offset centroid = Offset.zero;
  for (final p in shape.points) {
    centroid = Offset(centroid.dx + p.dx, centroid.dy + p.dy);
  }
  centroid = Offset(centroid.dx / n, centroid.dy / n);

  final hasDW = shape.roomObjects.isNotEmpty;
  final hasFurn = shape.furnitureItems.isNotEmpty;

  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pageHeader(_roomName(shape, roomIdx), null, pageNum, totalPages,
            accent: true),
        pw.SizedBox(height: 10),

        // Canvas
        pw.Center(
          child: _canvasBox(
            pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    painter: (g, size) {
                _paintGrid(g, size);

                // Room fill
                if (shape.isClosed && n >= 3) {
                  g.setFillColor(const PdfColor(0.90, 0.95, 1.00));
                  final f = tx(shape.points[0]);
                  g.moveTo(f.x, f.y);
                  for (int i = 1; i < n; i++) {
                    final p = tx(shape.points[i]);
                    g.lineTo(p.x, p.y);
                  }
                  g.closePath();
                  g.fillPath();
                }

                // Walls
                g.setFillColor(PdfColors.blueGrey800);
                for (int i = 0; i < wallCount; i++) {
                  final corners = thickWallRect(shape.points[i],
                      shape.points[(i + 1) % n], effectiveWallThickness);
                  if (corners.isEmpty) continue;
                  final c0 = tx(corners[0]);
                  final c1 = tx(corners[1]);
                  final c2 = tx(corners[2]);
                  final c3 = tx(corners[3]);
                  g.moveTo(c0.x, c0.y);
                  g.lineTo(c1.x, c1.y);
                  g.lineTo(c2.x, c2.y);
                  g.lineTo(c3.x, c3.y);
                  g.closePath();
                  g.fillPath();
                }

                // Corner dots
                for (int i = 0; i < n; i++) {
                  final p = tx(shape.points[i]);
                  g.setFillColor(
                      i == 0 ? PdfColors.green700 : PdfColors.blue700);
                  g.drawEllipse(p.x, p.y, 3.0, 3.0);
                  g.fillPath();
                }

                // Furniture (drawn before doors/windows so walls overlay them)
                for (final item in shape.furnitureItems) {
                  _paintFurniture(g, item, tx);
                }

                // Doors & windows
                if (shape.isClosed) {
                  _paintRoomObjects(
                      g, shape.points, n, wallCount,
                      shape.roomObjects, tx, centroid, effectiveWallThickness);
                }
                        _paintRoomWallDimensions(g, shape, tx, wallCount);
                    },
                  ),
                ),
                ..._roomWallDimensionLabels(shape, tx, wallCount),
              ],
            ),
            size: _csRoomDim,
          ),
        ),
        pw.SizedBox(height: 10),

        // Stats row
        if (shape.isClosed)
          _statsRow(shape, wallCount),
        pw.SizedBox(height: 10),

        // Doors/windows + furniture side-by-side
        if (hasDW || hasFurn)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (hasDW)
                pw.Expanded(child: _dwTable(shape.roomObjects)),
              if (hasDW && hasFurn) pw.SizedBox(width: 10),
              if (hasFurn)
                pw.Expanded(child: _furnitureTable(shape.furnitureItems)),
            ],
          ),
        if (hasDW || hasFurn) pw.SizedBox(height: 10),

        // Wall measurements
        _wallsTable(shape, wallCount),

        pw.Spacer(),
        _pageFooter(
            'SmartMeasure Pro — Floor Plan Guide', pageNum, totalPages),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// CANVAS PAINTERS
// ═══════════════════════════════════════════════════════════════════════════

void _paintGrid(PdfGraphics g, PdfPoint size) {
  g.setStrokeColor(PdfColors.grey200);
  g.setLineWidth(0.3);
  const step = 20.0;
  for (double x = 0; x <= size.x; x += step) {
    g.moveTo(x, 0);
    g.lineTo(x, size.y);
    g.strokePath();
  }
  for (double y = 0; y <= size.y; y += step) {
    g.moveTo(0, y);
    g.lineTo(size.x, y);
    g.strokePath();
  }
}

void _paintRoomObjects(
  PdfGraphics g,
  List<Offset> pts,
  int n,
  int wallCount,
  List<RoomObject> objects,
  _Tx tx,
  Offset centroid,
  double wallThicknessWorld,
) {
  for (final obj in objects) {
    if (obj.wallIndex >= wallCount) continue;
    final wA = pts[obj.wallIndex];
    final wB = pts[(obj.wallIndex + 1) % n];
    final wallVec = wB - wA;
    final wallLen = wallVec.distance;
    if (wallLen < 1) continue;

    final wallDir =
        Offset(wallVec.dx / wallLen, wallVec.dy / wallLen);
    final halfObjW = obj.widthMm / mmPerUnit / 2; // world units
    final tCenter = obj.positionAlong * wallLen;

    // Opening endpoints in world space
    final startW = wA +
        Offset(wallDir.dx * (tCenter - halfObjW),
            wallDir.dy * (tCenter - halfObjW));
    final endW = wA +
        Offset(wallDir.dx * (tCenter + halfObjW),
            wallDir.dy * (tCenter + halfObjW));

    // Inward normal (pointing into room)
    Offset inW = Offset(-wallDir.dy, wallDir.dx);
    final wallMid =
        Offset((wA.dx + wB.dx) / 2, (wA.dy + wB.dy) / 2);
    if ((centroid.dx - wallMid.dx) * inW.dx +
            (centroid.dy - wallMid.dy) * inW.dy <
        0) {
      inW = Offset(-inW.dx, -inW.dy);
    }
    if (obj.swingFlipped) inW = Offset(-inW.dx, -inW.dy);

    final sP = tx(startW);
    final eP = tx(endW);
    // PDF space direction vectors (Y flipped relative to world)
    final wdPdf = Offset(wallDir.dx, -wallDir.dy);
    final inPdf = Offset(inW.dx, -inW.dy);
    final widPdf = obj.widthMm / mmPerUnit * tx.scale;
    final wallGapPdf = wallThicknessWorld * tx.scale + 1.0;

    if (obj.isDoor) {
      _paintDoor(g, sP, eP, wdPdf, inPdf, widPdf, wallGapPdf);
    } else {
      _paintWindow(g, sP, eP, inPdf, widPdf, wallGapPdf);
    }
  }
}

void _paintDoor(
  PdfGraphics g,
  PdfPoint start,
  PdfPoint end,
  Offset wallDirPdf,
  Offset inWPdf,
  double widthPdf,
  double gapWidthPdf,
) {
  final hx = start.x, hy = start.y; // hinge
  final tx = end.x, ty = end.y;     // tip (far jamb)

  // White wall gap
  g.setStrokeColor(PdfColors.white);
  g.setLineWidth(gapWidthPdf);
  g.moveTo(hx, hy);
  g.lineTo(tx, ty);
  g.strokePath();

  // Leaf tip (door leaf end, fully open = 90° into room)
  final ltx = hx + inWPdf.dx * widthPdf;
  final lty = hy + inWPdf.dy * widthPdf;

  g.setStrokeColor(PdfColors.blueGrey800);
  g.setLineWidth(1.5);

  // Door leaf line: hinge → leaf tip
  g.moveTo(hx, hy);
  g.lineTo(ltx, lty);
  g.strokePath();

  // Door frame line: hinge → tip
  g.moveTo(hx, hy);
  g.lineTo(tx, ty);
  g.strokePath();

  // Arc from leaf tip to tip, centred on hinge
  // Cross product determines CW vs CCW sweep
  final cross =
      wallDirPdf.dx * inWPdf.dy - wallDirPdf.dy * inWPdf.dx;
  final sweepSign = cross > 0 ? -1.0 : 1.0;
  final arcStart = math.atan2(inWPdf.dy, inWPdf.dx);

  g.setLineWidth(0.8);
  bool first = true;
  for (int s = 0; s <= 24; s++) {
    final ang = arcStart + sweepSign * (s / 24) * (math.pi / 2);
    final ax = hx + math.cos(ang) * widthPdf;
    final ay = hy + math.sin(ang) * widthPdf;
    if (first) {
      g.moveTo(ax, ay);
      first = false;
    } else {
      g.lineTo(ax, ay);
    }
  }
  g.strokePath();
}

void _paintWindow(
  PdfGraphics g,
  PdfPoint start,
  PdfPoint end,
  Offset inWPdf,
  double widthPdf,
  double gapWidthPdf,
) {
  // White wall gap
  g.setStrokeColor(PdfColors.white);
  g.setLineWidth(gapWidthPdf);
  g.moveTo(start.x, start.y);
  g.lineTo(end.x, end.y);
  g.strokePath();

  // Three parallel lines across the opening
  g.setStrokeColor(const PdfColor(0.00, 0.49, 0.76));
  const offsets = [-0.38, 0.0, 0.38];
  for (final t in offsets) {
    final ox = inWPdf.dx * t * 7;
    final oy = inWPdf.dy * t * 7;
    g.setLineWidth(t == 0.0 ? 1.5 : 0.8);
    g.moveTo(start.x + ox, start.y + oy);
    g.lineTo(end.x + ox, end.y + oy);
    g.strokePath();
  }
}

void _paintFurniture(PdfGraphics g, FurnitureItem item, _Tx tx) {
  final hw = item.widthMm / mmPerUnit / 2;
  final hd = item.depthMm / mmPerUnit / 2;
  final rad = item.rotationDeg * math.pi / 180;
  final cosR = math.cos(rad);
  final sinR = math.sin(rad);

  // Rotate a local corner into world space
  Offset rotW(double lx, double ly) => Offset(
        item.position.dx + lx * cosR - ly * sinR,
        item.position.dy + lx * sinR + ly * cosR,
      );

  final c1 = tx(rotW(-hw, -hd));
  final c2 = tx(rotW(hw, -hd));
  final c3 = tx(rotW(hw, hd));
  final c4 = tx(rotW(-hw, hd));

  // Muted fill derived from the furniture's theme colour
  final col = item.type.color;
  final r = col.r;
  final gr = col.g;
  final b = col.b;
  // Lighten for fill
  g.setFillColor(PdfColor(
    0.65 + r * 0.35,
    0.65 + gr * 0.35,
    0.65 + b * 0.35,
  ));
  g.moveTo(c1.x, c1.y);
  g.lineTo(c2.x, c2.y);
  g.lineTo(c3.x, c3.y);
  g.lineTo(c4.x, c4.y);
  g.closePath();
  g.fillPath();

  // Border
  g.setStrokeColor(PdfColor(r * 0.7, gr * 0.7, b * 0.7));
  g.setLineWidth(0.8);
  g.moveTo(c1.x, c1.y);
  g.lineTo(c2.x, c2.y);
  g.lineTo(c3.x, c3.y);
  g.lineTo(c4.x, c4.y);
  g.closePath();
  g.strokePath();

  // Diagonal cross (standard floor-plan furniture indicator)
  g.setStrokeColor(PdfColor(r * 0.5, gr * 0.5, b * 0.5));
  g.setLineWidth(0.4);
  g.moveTo(c1.x, c1.y);
  g.lineTo(c3.x, c3.y);
  g.strokePath();
  g.moveTo(c2.x, c2.y);
  g.lineTo(c4.x, c4.y);
  g.strokePath();
}

// ═══════════════════════════════════════════════════════════════════════════
// DIMENSION LINES (extension lines + arrows + text, architectural style)
// ═══════════════════════════════════════════════════════════════════════════

const PdfColor _dimColor = PdfColor(0.30, 0.30, 0.30);
const double _dimArrowSize = 3.0;
const double _dimSegOffset = 7.0;
const double _dimTotalOffset = 16.0;

pw.TextStyle get _dimTextStyle => pw.TextStyle(
      fontSize: 6.5,
      fontWeight: pw.FontWeight.normal,
      color: _dimColor,
    );

void _drawLine(PdfGraphics g, double x1, double y1, double x2, double y2,
    {double width = 0.4}) {
  g.setStrokeColor(_dimColor);
  g.setLineWidth(width);
  g.moveTo(x1, y1);
  g.lineTo(x2, y2);
  g.strokePath();
}

void _drawArrowHead(PdfGraphics g, double tipX, double tipY, double angleRad) {
  const spread = 2.6;
  final a1 = angleRad + spread;
  final a2 = angleRad - spread;
  g.setFillColor(_dimColor);
  g.moveTo(tipX, tipY);
  g.lineTo(tipX + math.cos(a1) * _dimArrowSize,
      tipY + math.sin(a1) * _dimArrowSize);
  g.lineTo(tipX + math.cos(a2) * _dimArrowSize,
      tipY + math.sin(a2) * _dimArrowSize);
  g.closePath();
  g.fillPath();
}

void _drawHDimLine(PdfGraphics g, double x1, double x2, double lineY) {
  _drawLine(g, x1, lineY, x2, lineY, width: 0.5);
  _drawArrowHead(g, x1, lineY, math.pi);
  _drawArrowHead(g, x2, lineY, 0);
}

void _drawVDimLine(PdfGraphics g, double y1, double y2, double lineX) {
  _drawLine(g, lineX, y1, lineX, y2, width: 0.5);
  _drawArrowHead(g, lineX, y1, -math.pi / 2);
  _drawArrowHead(g, lineX, y2, math.pi / 2);
}

pw.Widget _dimLabel(double x, double y, String text, double canvasSize,
  {bool vertical = false, double rotation = -math.pi / 2}) {
  final width = vertical ? 14.0 : 32.0;
  final height = vertical ? 32.0 : 14.0;
  return pw.Positioned(
    left: x - width / 2,
    top: canvasSize - y - height / 2,
    child: pw.SizedBox(
      width: width,
      height: height,
      child: pw.Center(
        child: vertical
            ? pw.Transform.rotate(
              angle: rotation,
                child: pw.SizedBox(
                  width: 32,
                  height: 14,
                  child: pw.Center(
                    child: pw.Text(text,
                        maxLines: 1,
                        style: _dimTextStyle,
                        textAlign: pw.TextAlign.center),
                  ),
                ),
              )
            : pw.Text(text,
                style: _dimTextStyle, textAlign: pw.TextAlign.center),
      ),
    ),
  );
}

Offset _centroidOf(SketchShape s) {
  Offset c = Offset.zero;
  for (final p in s.points) {
    c = Offset(c.dx + p.dx, c.dy + p.dy);
  }
  return Offset(c.dx / s.points.length, c.dy / s.points.length);
}

List<double> _xBreakpointsAtY(
    List<SketchShape> shapes, double y, double minX, double maxX,
    {double tol = 3.0}) {
  final vals = <double>{minX, maxX};
  for (final s in shapes) {
    for (final p in s.points) {
      if ((p.dy - y).abs() < tol) vals.add(p.dx);
    }
  }
  final list = vals.toList()..sort();
  final merged = <double>[];
  for (final v in list) {
    if (merged.isEmpty || (v - merged.last).abs() > tol) merged.add(v);
  }
  return merged;
}

List<double> _yBreakpointsAtX(
    List<SketchShape> shapes, double x, double minY, double maxY,
    {double tol = 3.0}) {
  final vals = <double>{minY, maxY};
  for (final s in shapes) {
    for (final p in s.points) {
      if ((p.dx - x).abs() < tol) vals.add(p.dy);
    }
  }
  final list = vals.toList()..sort();
  final merged = <double>[];
  for (final v in list) {
    if (merged.isEmpty || (v - merged.last).abs() > tol) merged.add(v);
  }
  return merged;
}

void _paintFullPlanDimensions(PdfGraphics g, List<SketchShape> shapes, _Tx tx) {
  final allPts = [for (final s in shapes) ...s.points];
  if (allPts.isEmpty) return;
  final minX = allPts.map((p) => p.dx).reduce(math.min);
  final maxX = allPts.map((p) => p.dx).reduce(math.max);
  final minY = allPts.map((p) => p.dy).reduce(math.min);
  final maxY = allPts.map((p) => p.dy).reduce(math.max);

  final topBp = _xBreakpointsAtY(shapes, minY, minX, maxX);
  final topY = tx(Offset(minX, minY)).y;
  final topSegY = topY + _dimSegOffset;
  final topTotY = topY + _dimTotalOffset;
  for (final bx in topBp) {
    final px = tx(Offset(bx, minY)).x;
    _drawLine(g, px, topY, px, topTotY + 3, width: 0.3);
  }
  for (int i = 0; i < topBp.length - 1; i++) {
    _drawHDimLine(g, tx(Offset(topBp[i], minY)).x,
        tx(Offset(topBp[i + 1], minY)).x, topSegY);
  }
  _drawHDimLine(g, tx(Offset(minX, minY)).x, tx(Offset(maxX, minY)).x, topTotY);

  final botBp = _xBreakpointsAtY(shapes, maxY, minX, maxX);
  final botY = tx(Offset(minX, maxY)).y;
  final botSegY = botY - _dimSegOffset;
  final botTotY = botY - _dimTotalOffset;
  for (final bx in botBp) {
    final px = tx(Offset(bx, maxY)).x;
    _drawLine(g, px, botY, px, botTotY - 3, width: 0.3);
  }
  for (int i = 0; i < botBp.length - 1; i++) {
    _drawHDimLine(g, tx(Offset(botBp[i], maxY)).x,
        tx(Offset(botBp[i + 1], maxY)).x, botSegY);
  }
  _drawHDimLine(g, tx(Offset(minX, maxY)).x, tx(Offset(maxX, maxY)).x, botTotY);

  final leftBp = _yBreakpointsAtX(shapes, minX, minY, maxY);
  final leftX = tx(Offset(minX, minY)).x;
  final leftSegX = leftX - _dimSegOffset;
  final leftTotX = leftX - _dimTotalOffset;
  for (final by in leftBp) {
    final py = tx(Offset(minX, by)).y;
    _drawLine(g, leftX, py, leftTotX - 3, py, width: 0.3);
  }
  for (int i = 0; i < leftBp.length - 1; i++) {
    final y1 = tx(Offset(minX, leftBp[i])).y;
    final y2 = tx(Offset(minX, leftBp[i + 1])).y;
    _drawVDimLine(g, math.min(y1, y2), math.max(y1, y2), leftSegX);
  }
  final ly1 = tx(Offset(minX, minY)).y;
  final ly2 = tx(Offset(minX, maxY)).y;
  _drawVDimLine(g, math.min(ly1, ly2), math.max(ly1, ly2), leftTotX);

  final rightBp = _yBreakpointsAtX(shapes, maxX, minY, maxY);
  final rightX = tx(Offset(maxX, minY)).x;
  final rightSegX = rightX + _dimSegOffset;
  final rightTotX = rightX + _dimTotalOffset;
  for (final by in rightBp) {
    final py = tx(Offset(maxX, by)).y;
    _drawLine(g, rightX, py, rightTotX + 3, py, width: 0.3);
  }
  for (int i = 0; i < rightBp.length - 1; i++) {
    final y1 = tx(Offset(maxX, rightBp[i])).y;
    final y2 = tx(Offset(maxX, rightBp[i + 1])).y;
    _drawVDimLine(g, math.min(y1, y2), math.max(y1, y2), rightSegX);
  }
  final ry1 = tx(Offset(maxX, minY)).y;
  final ry2 = tx(Offset(maxX, maxY)).y;
  _drawVDimLine(g, math.min(ry1, ry2), math.max(ry1, ry2), rightTotX);
}

List<pw.Widget> _fullPlanDimensionLabels(List<SketchShape> shapes, _Tx tx) {
  final widgets = <pw.Widget>[];
  final allPts = [for (final s in shapes) ...s.points];
  if (allPts.isEmpty) return widgets;
  final minX = allPts.map((p) => p.dx).reduce(math.min);
  final maxX = allPts.map((p) => p.dx).reduce(math.max);
  final minY = allPts.map((p) => p.dy).reduce(math.min);
  final maxY = allPts.map((p) => p.dy).reduce(math.max);
  final cs = tx.canvasSize;

  final topBp = _xBreakpointsAtY(shapes, minY, minX, maxX);
  final topY = tx(Offset(minX, minY)).y;
  for (int i = 0; i < topBp.length - 1; i++) {
    final x1 = tx(Offset(topBp[i], minY)).x;
    final x2 = tx(Offset(topBp[i + 1], minY)).x;
    widgets.add(_dimLabel((x1 + x2) / 2, topY + _dimSegOffset + 4,
        formatLength(topBp[i + 1] - topBp[i]), cs));
  }
  widgets.add(_dimLabel(
      (tx(Offset(minX, minY)).x + tx(Offset(maxX, minY)).x) / 2,
      topY + _dimTotalOffset + 4,
      formatLength(maxX - minX),
      cs));

  final botBp = _xBreakpointsAtY(shapes, maxY, minX, maxX);
  final botY = tx(Offset(minX, maxY)).y;
  for (int i = 0; i < botBp.length - 1; i++) {
    final x1 = tx(Offset(botBp[i], maxY)).x;
    final x2 = tx(Offset(botBp[i + 1], maxY)).x;
    widgets.add(_dimLabel((x1 + x2) / 2, botY - _dimSegOffset - 4,
        formatLength(botBp[i + 1] - botBp[i]), cs));
  }
  widgets.add(_dimLabel(
      (tx(Offset(minX, maxY)).x + tx(Offset(maxX, maxY)).x) / 2,
      botY - _dimTotalOffset - 4,
      formatLength(maxX - minX),
      cs));

  final leftBp = _yBreakpointsAtX(shapes, minX, minY, maxY);
  final leftX = tx(Offset(minX, minY)).x;
  for (int i = 0; i < leftBp.length - 1; i++) {
    final y1 = tx(Offset(minX, leftBp[i])).y;
    final y2 = tx(Offset(minX, leftBp[i + 1])).y;
    widgets.add(_dimLabel(leftX - _dimSegOffset - 4, (y1 + y2) / 2,
        _formatVerticalMeters((leftBp[i + 1] - leftBp[i]).abs()), cs,
      vertical: true, rotation: math.pi / 2));
  }
  widgets.add(_dimLabel(leftX - _dimTotalOffset - 4,
      (tx(Offset(minX, minY)).y + tx(Offset(minX, maxY)).y) / 2,
      _formatVerticalMeters(maxY - minY), cs,
      vertical: true,
      rotation: math.pi / 2));

  final rightBp = _yBreakpointsAtX(shapes, maxX, minY, maxY);
  final rightX = tx(Offset(maxX, minY)).x;
  for (int i = 0; i < rightBp.length - 1; i++) {
    final y1 = tx(Offset(maxX, rightBp[i])).y;
    final y2 = tx(Offset(maxX, rightBp[i + 1])).y;
    widgets.add(_dimLabel(rightX + _dimSegOffset + 3, (y1 + y2) / 2,
        _formatVerticalMeters((rightBp[i + 1] - rightBp[i]).abs()), cs,
        vertical: true));
  }
  widgets.add(_dimLabel(rightX + _dimTotalOffset + 3,
      (tx(Offset(maxX, minY)).y + tx(Offset(maxX, maxY)).y) / 2,
      _formatVerticalMeters(maxY - minY), cs,
      vertical: true));

  return widgets;
}

void _paintRoomWallDimensions(
    PdfGraphics g, SketchShape shape, _Tx tx, int wallCount) {
  final n = shape.points.length;
  if (wallCount == 0) return;
  final centroid = _centroidOf(shape);

  for (int i = 0; i < wallCount; i++) {
    final a = shape.points[i];
    final b = shape.points[(i + 1) % n];
    final wallVec = b - a;
    final wallLen = wallVec.distance;
    if (wallLen < 1) continue;

    Offset normal = Offset(-wallVec.dy / wallLen, wallVec.dx / wallLen);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    if ((mid.dx - centroid.dx) * normal.dx +
            (mid.dy - centroid.dy) * normal.dy <
        0) {
      normal = Offset(-normal.dx, -normal.dy);
    }
    final pdfNormal = Offset(normal.dx, -normal.dy);
    final pa = tx(a);
    final pb = tx(b);
    final x1 = pa.x + pdfNormal.dx * _dimSegOffset;
    final y1 = pa.y + pdfNormal.dy * _dimSegOffset;
    final x2 = pb.x + pdfNormal.dx * _dimSegOffset;
    final y2 = pb.y + pdfNormal.dy * _dimSegOffset;

    _drawLine(g, pa.x, pa.y, x1 + pdfNormal.dx * 3,
        y1 + pdfNormal.dy * 3, width: 0.3);
    _drawLine(g, pb.x, pb.y, x2 + pdfNormal.dx * 3,
        y2 + pdfNormal.dy * 3, width: 0.3);
    _drawLine(g, x1, y1, x2, y2, width: 0.5);
    final angle = math.atan2(y2 - y1, x2 - x1);
    _drawArrowHead(g, x1, y1, angle + math.pi);
    _drawArrowHead(g, x2, y2, angle);
  }
}

List<pw.Widget> _roomWallDimensionLabels(
    SketchShape shape, _Tx tx, int wallCount) {
  final n = shape.points.length;
  if (wallCount == 0) return [];
  final centroid = _centroidOf(shape);
  final widgets = <pw.Widget>[];

  for (int i = 0; i < wallCount; i++) {
    final a = shape.points[i];
    final b = shape.points[(i + 1) % n];
    final wallVec = b - a;
    final wallLen = wallVec.distance;
    if (wallLen < 1) continue;

    Offset normal = Offset(-wallVec.dy / wallLen, wallVec.dx / wallLen);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    if ((mid.dx - centroid.dx) * normal.dx +
            (mid.dy - centroid.dy) * normal.dy <
        0) {
      normal = Offset(-normal.dx, -normal.dy);
    }
    final pdfNormal = Offset(normal.dx, -normal.dy);
    final pa = tx(a);
    final pb = tx(b);
    final midX = (pa.x + pb.x) / 2 + pdfNormal.dx * (_dimSegOffset + 7);
    final midY = (pa.y + pb.y) / 2 + pdfNormal.dy * (_dimSegOffset + 7);
    final isVertical = (pb.x - pa.x).abs() < (pb.y - pa.y).abs();
    widgets.add(_dimLabel(
      midX, midY, _wallLenMeters(shape, i, n), tx.canvasSize,
      vertical: isVertical));
  }
  return widgets;
}

// ═══════════════════════════════════════════════════════════════════════════
// TABLE BUILDERS
// ═══════════════════════════════════════════════════════════════════════════

pw.Widget _dwTable(List<RoomObject> objects) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel('Doors & Windows'),
      pw.SizedBox(height: 4),
      pw.Table(
        border:
            pw.TableBorder.all(color: PdfColors.blueGrey200, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(18),
          1: const pw.FlexColumnWidth(1.5),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(1.4),
          4: const pw.FlexColumnWidth(1.3),
        },
        children: [
          pw.TableRow(
            decoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey100),
            children: ['#', 'Type', 'Width', 'Height', 'Elev.']
                .map(_thCell)
                .toList(),
          ),
          ...objects.asMap().entries.map((e) {
            final obj = e.value;
            return pw.TableRow(children: [
              _tdCell('${e.key + 1}'),
              _tdCell(obj.isDoor ? 'Door' : 'Window'),
              _tdCell(_fmtMm(obj.widthMm)),
              _tdCell(_fmtMm(obj.heightMm)),
              _tdCell(obj.elevationMm > 0 ? _fmtMm(obj.elevationMm) : '—'),
            ]);
          }),
        ],
      ),
    ],
  );
}

pw.Widget _furnitureTable(List<FurnitureItem> items) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel('Furniture'),
      pw.SizedBox(height: 4),
      pw.Table(
        border:
            pw.TableBorder.all(color: PdfColors.blueGrey200, width: 0.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(18),
          1: const pw.FlexColumnWidth(2.2),
          2: const pw.FlexColumnWidth(1.3),
          3: const pw.FlexColumnWidth(1.3),
        },
        children: [
          pw.TableRow(
            decoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey100),
            children: ['#', 'Item', 'W', 'D'].map(_thCell).toList(),
          ),
          ...items.asMap().entries.map((e) {
            final item = e.value;
            return pw.TableRow(children: [
              _tdCell('${e.key + 1}'),
              _tdCell(item.type.displayName),
              _tdCell(_fmtMm(item.widthMm)),
              _tdCell(_fmtMm(item.depthMm)),
            ]);
          }),
        ],
      ),
    ],
  );
}

pw.Widget _wallsTable(SketchShape shape, int wallCount) {
  if (wallCount == 0) return pw.SizedBox();
  final n = shape.points.length;
  final half = (wallCount + 1) ~/ 2;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel('Wall Measurements'),
      pw.SizedBox(height: 4),
      pw.Table(
        border:
            pw.TableBorder.all(color: PdfColors.blueGrey200, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(0.8),
          1: const pw.FlexColumnWidth(1.6),
          2: const pw.FixedColumnWidth(12),
          3: const pw.FlexColumnWidth(0.8),
          4: const pw.FlexColumnWidth(1.6),
        },
        children: [
          pw.TableRow(
            decoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey100),
            children: ['Wall', 'Length', '', 'Wall', 'Length']
                .map(_thCell)
                .toList(),
          ),
          for (int i = 0; i < half; i++)
            pw.TableRow(children: [
              _tdCell('W ${i + 1}'),
              _tdCell(_wallLen(shape, i, n)),
              _tdCell(''),
              if (i + half < wallCount) ...[
                _tdCell('W ${i + half + 1}'),
                _tdCell(_wallLen(shape, i + half, n)),
              ] else ...[
                _tdCell(''),
                _tdCell(''),
              ],
            ]),
        ],
      ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET HELPERS
// ═══════════════════════════════════════════════════════════════════════════

pw.Widget _roomLabelOverlay(SketchShape s, int idx, _Tx tx) {
  Offset centroid = Offset.zero;
  for (final p in s.points) {
    centroid = Offset(centroid.dx + p.dx, centroid.dy + p.dy);
  }
  centroid = Offset(
      centroid.dx / s.points.length, centroid.dy / s.points.length);

  final point = tx(centroid);
  return pw.Positioned(
    left: point.x - 24,
    top: tx.canvasSize - point.y - 6,
    child: pw.SizedBox(
      width: 48,
      child: pw.Center(
        child: pw.Text(
          _roomName(s, idx),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 7,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey900,
          ),
        ),
      ),
    ),
  );
}

pw.Widget _canvasBox(pw.Widget child, {double size = _cs}) => pw.Container(
  width: size,
  height: size,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.blueGrey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: child,
    );

pw.Widget _pageHeader(
  String title,
  String? subtitle,
  int pageNum,
  int totalPages, {
  bool accent = false,
}) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: accent
                        ? const PdfColor(0.09, 0.40, 0.71)
                        : PdfColors.blueGrey800)),
            if (subtitle != null && subtitle.isNotEmpty)
              pw.Text(subtitle,
                  style: const pw.TextStyle(
                      fontSize: 8.5, color: PdfColors.grey500)),
          ],
        ),
      ),
      pw.Container(
        padding:
            const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: pw.BoxDecoration(
          color: PdfColors.blueGrey50,
          borderRadius:
              const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: PdfColors.blueGrey200),
        ),
        child: pw.Text('Page $pageNum of $totalPages',
            style: const pw.TextStyle(
                fontSize: 7.5, color: PdfColors.blueGrey600)),
      ),
    ],
  );
}

pw.Widget _pageFooter(String label, int pageNum, int totalPages) =>
    pw.Column(children: [
      pw.Divider(color: PdfColors.blueGrey200),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 7, color: PdfColors.grey500)),
          pw.Text('Page $pageNum of $totalPages',
              style: const pw.TextStyle(
                  fontSize: 7, color: PdfColors.grey500)),
        ],
      ),
    ]);

pw.Widget _statsRow(SketchShape shape, int wallCount) => pw.Container(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        borderRadius:
            const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: PdfColors.blueGrey200),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _statItem('WALLS', '$wallCount'),
          _vDiv(),
          _statItem('PERIMETER', _perimStr(shape)),
          _vDiv(),
          _statItem('AREA', _areaStr(shape)),
          _vDiv(),
          _statItem('HEIGHT', '${shape.heightMm.toStringAsFixed(0)} mm'),
        ],
      ),
    );

pw.Widget _statItem(String label, String value) => pw.Column(children: [
      pw.Text(label,
          style: const pw.TextStyle(
              fontSize: 7, color: PdfColors.blueGrey500)),
      pw.SizedBox(height: 2),
      pw.Text(value,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800)),
    ]);

pw.Widget _vDiv() =>
    pw.Container(width: 0.5, height: 26, color: PdfColors.blueGrey200);

pw.Widget _sectionLabel(String text) => pw.Text(text,
    style: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.blueGrey700));

pw.Widget _thCell(String text) => pw.Padding(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey700)),
    );

pw.Widget _tdCell(String text) => pw.Padding(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: pw.Text(text,
          style: const pw.TextStyle(
              fontSize: 7.5, color: PdfColors.blueGrey800)),
    );

pw.Widget _coverStat(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label,
            style: const pw.TextStyle(
                fontSize: 7.5, color: PdfColors.blueGrey200)),
        pw.SizedBox(height: 3),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white)),
      ],
    );

pw.Widget _tocRow(String name, int page,
    {String? sub, bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    child: pw.Row(children: [
      pw.SizedBox(width: bold ? 0 : 14),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(name,
                style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight:
                        bold ? pw.FontWeight.bold : null,
                    color: PdfColors.blueGrey800)),
            if (sub != null && sub.isNotEmpty)
              pw.Text(sub,
                  style: const pw.TextStyle(
                      fontSize: 7.5, color: PdfColors.grey500)),
          ],
        ),
      ),
      pw.Container(
        width: 20,
        alignment: pw.Alignment.centerRight,
        child: pw.Text('$page',
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor(0.09, 0.40, 0.71))),
      ),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA HELPERS
// ═══════════════════════════════════════════════════════════════════════════

double _shapeArea(SketchShape s) {
  if (!s.isClosed || s.points.length < 3) return 0;
  double area = 0;
  final n = s.points.length;
  for (int i = 0; i < n; i++) {
    final j = (i + 1) % n;
    area += s.points[i].dx * s.points[j].dy;
    area -= s.points[j].dx * s.points[i].dy;
  }
  return area.abs() / 2;
}

double _shapePerimeter(SketchShape s) {
  if (s.points.length < 2) return 0;
  final n = s.points.length;
  final wc = s.isClosed ? n : n - 1;
  double total = 0;
  for (int i = 0; i < wc; i++) {
    total += (s.points[(i + 1) % n] - s.points[i]).distance;
  }
  return total;
}

String _perimStr(SketchShape s) {
  final p = _shapePerimeter(s);
  return p > 0 ? formatLength(p) : '—';
}

String _areaStr(SketchShape s) {
  final a = _shapeArea(s);
  return a > 0 ? formatArea(a) : '—';
}

String _wallLen(SketchShape s, int i, int n) {
  final worldLen = (s.points[(i + 1) % n] - s.points[i]).distance;
  return s.wallRealMm.containsKey(i)
      ? _fmtMm(s.wallRealMm[i]!)
      : formatLength(worldLen);
}

String _wallLenMeters(SketchShape s, int i, int n) {
  final millimeters = s.wallRealMm[i] ??
      (s.points[(i + 1) % n] - s.points[i]).distance * mmPerUnit;
  return '${(millimeters / 1000).toStringAsFixed(2)} m';
}

String _formatVerticalMeters(double worldUnits) =>
    '${(worldUnits * mmPerUnit / 1000).toStringAsFixed(2)} m';

String _roomName(SketchShape s, int idx) =>
    s.label.isNotEmpty ? s.label : 'Room ${idx + 1}';

String _roomSub(SketchShape s) {
  final a = _areaStr(s);
  return a != '—' ? 'Area: $a' : '';
}

String _fmtMm(double mm) =>
    mm >= 1000 ? '${(mm / 1000).toStringAsFixed(3)} m' : '${mm.toStringAsFixed(0)} mm';

String _date() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
