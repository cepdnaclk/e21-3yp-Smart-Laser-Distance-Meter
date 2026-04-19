// lib/sketch/sketch_pdf_export.dart

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'sketch_constants.dart';
import 'room_object.dart';
import 'room_object_utils.dart';

Future<void> exportSketchPdf({
  required BuildContext context,
  required List<Offset> points,
  required bool isClosed,
  required Map<int, double> wallRealMm,
  required double totalPerimeter,
  required double totalArea,
  required List<RoomObject> roomObjects,
}) async {
  if (points.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draw a room first'),
        backgroundColor: Color(0xFF333333),
      ),
    );
    return;
  }

  final pdf = pw.Document();

  double minX = points.map((p) => p.dx).reduce(math.min);
  double maxX = points.map((p) => p.dx).reduce(math.max);
  double minY = points.map((p) => p.dy).reduce(math.min);
  double maxY = points.map((p) => p.dy).reduce(math.max);

  const double canvasSize = 440.0;
  const double canvasMargin = 30.0;
  const double drawArea = canvasSize - canvasMargin * 2;

  final double worldW = (maxX - minX).clamp(1.0, double.infinity);
  final double worldH = (maxY - minY).clamp(1.0, double.infinity);
  final double pdfScale = drawArea / math.max(worldW, worldH);

  PdfPoint toPdf(Offset world) {
    return PdfPoint(
      canvasMargin + (world.dx - minX) * pdfScale,
      canvasSize - canvasMargin - (world.dy - minY) * pdfScale,
    );
  }

  final int n = points.length;
  final int wallCount = isClosed ? n : n - 1;

  final List<Map<String, String>> wallRows = List.generate(wallCount, (i) {
    final Offset a = points[i];
    final Offset b = points[(i + 1) % n];
    final double wl = (b - a).distance;
    return {
      'wall': 'Wall ${i + 1}',
      'drawn': formatLength(wl),
      'real': wallRealMm.containsKey(i)
          ? '${wallRealMm[i]!.toStringAsFixed(0)} mm'
          : '—',
    };
  });

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Room Floor Plan',
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey800)),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'SmartMeasure Pro  •  ${_formattedDate()}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey600),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blueGrey50,
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: PdfColors.blueGrey200),
                  ),
                  child: pw.Text('1 grid div = 100 mm',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.blueGrey600)),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(color: PdfColors.blueGrey200),
            pw.SizedBox(height: 12),
            pw.Center(
              child: pw.Container(
                width: canvasSize,
                height: canvasSize,
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: PdfColors.blueGrey300),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.CustomPaint(
                  painter: (PdfGraphics g, PdfPoint size) {
                    g.setStrokeColor(PdfColors.grey200);
                    g.setLineWidth(0.4);
                    const double gridStep = 20.0;
                    for (double x = 0; x <= size.x; x += gridStep) {
                      g.moveTo(x, 0);
                      g.lineTo(x, size.y);
                      g.strokePath();
                    }
                    for (double y = 0; y <= size.y; y += gridStep) {
                      g.moveTo(0, y);
                      g.lineTo(size.x, y);
                      g.strokePath();
                    }
                    if (isClosed && n >= 3) {
                      g.setFillColor(const PdfColor(0.91, 0.96, 1.0));
                      final first = toPdf(points[0]);
                      g.moveTo(first.x, first.y);
                      for (int i = 1; i < n; i++) {
                        final p = toPdf(points[i]);
                        g.lineTo(p.x, p.y);
                      }
                      g.closePath();
                      g.fillPath();
                    }
                    g.setStrokeColor(PdfColors.blueGrey800);
                    g.setLineWidth(1.8);
                    for (int i = 0; i < wallCount; i++) {
                      final PdfPoint a = toPdf(points[i]);
                      final PdfPoint b = toPdf(points[(i + 1) % n]);
                      g.moveTo(a.x, a.y);
                      g.lineTo(b.x, b.y);
                      g.strokePath();
                    }
                    for (int i = 0; i < n; i++) {
                      final PdfPoint p = toPdf(points[i]);
                      g.setFillColor(
                          i == 0 ? PdfColors.green700 : PdfColors.blue700);
                      g.drawEllipse(p.x, p.y, 3.5, 3.5);
                      g.fillPath();
                    }

                    // ── Draw doors and windows ──────────────────────
                    for (final obj in roomObjects) {
                      if (obj.wallIndex >= wallCount) continue;

                      final Offset aWorld = points[obj.wallIndex];
                      final Offset bWorld = points[(obj.wallIndex + 1) % n];

                      // Centre point in world coords
                      final Offset centreWorld = Offset(
                        aWorld.dx + obj.positionAlong * (bWorld.dx - aWorld.dx),
                        aWorld.dy + obj.positionAlong * (bWorld.dy - aWorld.dy),
                      );

                      // Wall direction unit vector (world)
                      final double wallDx = bWorld.dx - aWorld.dx;
                      final double wallDy = bWorld.dy - aWorld.dy;
                      final double wallLen =
                          math.sqrt(wallDx * wallDx + wallDy * wallDy);
                      if (wallLen < 1) continue;
                      final double dirX = wallDx / wallLen;
                      final double dirY = wallDy / wallLen;

                      // Half-width in world units (fixed symbol size)
                      const double halfW = 12.0;
                      // Perpendicular (inward)
                      final double perpX = -dirY;
                      final double perpY = dirX;

                      final PdfPoint c = toPdf(centreWorld);

                      // Convert direction offsets to PDF scale
                      final double dxPdf = dirX * halfW * pdfScale;
                      final double dyPdf = dirY * halfW * pdfScale;
                      final double pxPdf = perpX * halfW * 1.5 * pdfScale;
                      final double pyPdf = perpY * halfW * 1.5 * pdfScale;

                      if (obj.isDoor) {
                        // White gap on wall
                        g.setStrokeColor(PdfColors.white);
                        g.setLineWidth(4);
                        g.moveTo(c.x - dxPdf, c.y + dyPdf);
                        g.lineTo(c.x + dxPdf, c.y - dyPdf);
                        g.strokePath();

                        // Door leaf (filled rectangle)
                        g.setFillColor(
                            const PdfColor(0.55, 0.27, 0.07, 0.3)); // brown tint
                        g.setStrokeColor(const PdfColor(0.55, 0.27, 0.07));
                        g.setLineWidth(1.2);

                        final double p1x = c.x - dxPdf;
                        final double p1y = c.y + dyPdf;
                        final double p2x = c.x + dxPdf;
                        final double p2y = c.y - dyPdf;
                        final double p3x = p2x + pxPdf;
                        final double p3y = p2y - pyPdf;
                        final double p4x = p1x + pxPdf;
                        final double p4y = p1y - pyPdf;

                        g.moveTo(p1x, p1y);
                        g.lineTo(p2x, p2y);
                        g.lineTo(p3x, p3y);
                        g.lineTo(p4x, p4y);
                        g.closePath();
                        g.fillAndStrokePath();

                        // Swing arc (drawn as polyline approximation)
                        g.setStrokeColor(
                            const PdfColor(0.55, 0.27, 0.07, 0.5));
                        g.setLineWidth(0.8);
                        final double radius = halfW * pdfScale;
                        final double startAngle = math.atan2(p1y - c.y, p1x - c.x);
                        const int arcSteps = 12;
                        const double arcSpan = math.pi / 2;
                        bool arcFirst = true;
                        for (int s = 0; s <= arcSteps; s++) {
                          final double angle =
                              startAngle + (s / arcSteps) * arcSpan;
                          final double ax = p1x + math.cos(angle) * radius;
                          final double ay = p1y + math.sin(angle) * radius;
                          if (arcFirst) {
                            g.moveTo(ax, ay);
                            arcFirst = false;
                          } else {
                            g.lineTo(ax, ay);
                          }
                        }
                        g.strokePath();

                        // Label
                        g.setFillColor(const PdfColor(0.55, 0.27, 0.07));
                        // (PDF text drawing omitted — label shown in table below)

                      } else {
                        // Window — white gap
                        g.setStrokeColor(PdfColors.white);
                        g.setLineWidth(4);
                        g.moveTo(c.x - dxPdf, c.y + dyPdf);
                        g.lineTo(c.x + dxPdf, c.y - dyPdf);
                        g.strokePath();

                        // Three parallel lines (window symbol)
                        g.setStrokeColor(const PdfColor(0.0, 0.6, 0.8));
                        for (final off in [-0.4, 0.0, 0.4]) {
                          final double ox = perpX * off * 6 * pdfScale;
                          final double oy = perpY * off * 6 * pdfScale;
                          g.setLineWidth(off == 0 ? 1.5 : 0.8);
                          g.moveTo(c.x - dxPdf + ox, c.y + dyPdf - oy);
                          g.lineTo(c.x + dxPdf + ox, c.y - dyPdf - oy);
                          g.strokePath();
                        }
                      }
                    }
                  },
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            if (isClosed)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blueGrey50,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(4)),
                  border: pw.Border.all(color: PdfColors.blueGrey200),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    _pdfSummaryItem('POINTS', '${points.length}'),
                    _pdfDivider(),
                    _pdfSummaryItem('PERIMETER', formatLength(totalPerimeter)),
                    _pdfDivider(),
                    _pdfSummaryItem('AREA', formatArea(totalArea)),
                  ],
                ),
              ),
            pw.SizedBox(height: 14),

            if (roomObjects.isNotEmpty) ...[
              pw.Text('Doors & Windows',
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey700)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(
                    color: PdfColors.blueGrey200, width: 0.6),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                        color: PdfColors.blueGrey100),
                    children: ['#', 'Type', 'Width', 'Height']
                        .map((h) => pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 5),
                              child: pw.Text(h,
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.blueGrey700)),
                            ))
                        .toList(),
                  ),
                  ...roomObjects.asMap().entries.map((e) {
                    final i = e.key;
                    final obj = e.value;
                    final wStr = obj.widthMm >= 1000
                        ? '${(obj.widthMm / 1000).toStringAsFixed(3)} m'
                        : '${obj.widthMm.toStringAsFixed(0)} mm';
                    final hStr = obj.heightMm >= 1000
                        ? '${(obj.heightMm / 1000).toStringAsFixed(3)} m'
                        : '${obj.heightMm.toStringAsFixed(0)} mm';
                    return pw.TableRow(
                      children: [
                        '${i + 1}',
                        obj.isDoor ? 'Door' : 'Window',
                        wStr,
                        hStr,
                      ]
                          .map((c) => pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                child: pw.Text(c,
                                    style: const pw.TextStyle(
                                        fontSize: 9,
                                        color: PdfColors.blueGrey800)),
                              ))
                          .toList(),
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 14),
            ],


            pw.Text('Wall Measurements',
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey700)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColors.blueGrey200, width: 0.6),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.blueGrey100),
                  children: ['Wall', 'Drawn Length', 'Real Measurement']
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            child: pw.Text(h,
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.blueGrey700)),
                          ))
                      .toList(),
                ),
                ...wallRows.map((row) => pw.TableRow(
                      children: [row['wall']!, row['drawn']!, row['real']!]
                          .map((c) => pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                child: pw.Text(c,
                                    style: const pw.TextStyle(
                                        fontSize: 9,
                                        color: PdfColors.blueGrey800)),
                              ))
                          .toList(),
                    )),
              ],
            ),
            pw.Spacer(),
            pw.Divider(color: PdfColors.blueGrey200),
            pw.Text(
              'SmartMeasure Pro — generated floor plan  •  '
              '1 world unit = ${mmPerUnit.toStringAsFixed(0)} mm',
              style:
                  const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
            ),
          ],
        );
      },
    ),
  );

  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => pdf.save(),
    name: 'room_floor_plan',
  );
}

// ── Private helpers ──────────────────────────────────────────────────────

String _formattedDate() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}  '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
}

pw.Widget _pdfSummaryItem(String label, String value) {
  return pw.Column(children: [
    pw.Text(label,
        style:
            const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey500)),
    pw.SizedBox(height: 2),
    pw.Text(value,
        style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey800)),
  ]);
}

pw.Widget _pdfDivider() {
  return pw.Container(width: 1, height: 30, color: PdfColors.blueGrey200);
}