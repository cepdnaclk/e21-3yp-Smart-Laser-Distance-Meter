// lib/sketch/sketch_pdf_export.dart

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'sketch_constants.dart';
import 'sketch_model.dart';

Future<void> exportSketchPdf({
  required BuildContext context,
  required List<SketchShape> shapes,
  required double totalPerimeter,
  required double totalArea,
}) async {
  final SketchShape shape = shapes.firstWhere(
    (s) => s.isClosed,
    orElse: () => shapes.first,
  );
  final List<Offset> points = shape.points;
  final bool isClosed = shape.isClosed;
  final Map<int, double> wallRealMm = shape.wallRealMm;

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