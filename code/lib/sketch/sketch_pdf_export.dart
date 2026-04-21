import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'sketch_constants.dart';
import 'sketch_shape.dart';

Future<void> exportSketchPdf({
  required BuildContext context,
  required List<SketchShape> shapes,
}) async {
  // Filter to shapes that have enough points to draw
  final drawable = shapes.where((s) => s.points.length >= 2).toList();

  if (drawable.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draw at least one room first'),
        backgroundColor: Color(0xFF333333),
      ),
    );
    return;
  }

  final pdf = pw.Document();

  // ── Compute a single bounding box across ALL rooms ──────────────────────
  double minX = double.infinity, maxX = double.negativeInfinity;
  double minY = double.infinity, maxY = double.negativeInfinity;
  for (final s in drawable) {
    for (final p in s.points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
  }

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

  // ── Build per-room wall rows for the table ───────────────────────────────
  final List<List<Map<String, String>>> allWallRows = drawable.map((s) {
    final pts = s.points;
    final int n = pts.length;
    final int wallCount = s.isClosed ? n : n - 1;
    return List.generate(wallCount, (i) {
      final Offset a = pts[i];
      final Offset b = pts[(i + 1) % n];
      final double wl = (b - a).distance;
      return {
        'room': s.label ?? 'Room ${drawable.indexOf(s) + 1}',
        'wall': 'Wall ${i + 1}',
        'drawn': formatLength(wl),
        'real': s.wallRealMm.containsKey(i)
            ? '${s.wallRealMm[i]!.toStringAsFixed(0)} mm'
            : '—',
      };
    });
  }).toList();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Floor Plan',
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey800)),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'SmartMeasure Pro  •  ${_formattedDate()}  •  ${drawable.length} room${drawable.length == 1 ? '' : 's'}',
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

            // ── Canvas with all rooms ────────────────────────────────────
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
                    // Grid
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

                    // Rooms — each in a distinct tint, drawn back to front
                    final roomTints = [
                      const PdfColor(0.91, 0.96, 1.0),   // blue
                      const PdfColor(0.91, 1.0, 0.93),   // green
                      const PdfColor(1.0, 0.97, 0.88),   // amber
                      const PdfColor(0.97, 0.91, 1.0),   // purple
                      const PdfColor(1.0, 0.91, 0.91),   // red
                    ];

                    for (int ri = 0; ri < drawable.length; ri++) {
                      final s = drawable[ri];
                      final pts = s.points;
                      final int n = pts.length;
                      final tint = roomTints[ri % roomTints.length];

                      // Fill closed rooms
                      if (s.isClosed && n >= 3) {
                        g.setFillColor(tint);
                        final first = toPdf(pts[0]);
                        g.moveTo(first.x, first.y);
                        for (int i = 1; i < n; i++) {
                          final p = toPdf(pts[i]);
                          g.lineTo(p.x, p.y);
                        }
                        g.closePath();
                        g.fillPath();
                      }

                      // Walls
                      g.setStrokeColor(PdfColors.blueGrey800);
                      g.setLineWidth(1.8);
                      final int wallCount = s.isClosed ? n : n - 1;
                      for (int i = 0; i < wallCount; i++) {
                        final PdfPoint a = toPdf(pts[i]);
                        final PdfPoint b = toPdf(pts[(i + 1) % n]);
                        g.moveTo(a.x, a.y);
                        g.lineTo(b.x, b.y);
                        g.strokePath();
                      }

                      // Corner dots
                      for (int i = 0; i < n; i++) {
                        final PdfPoint p = toPdf(pts[i]);
                        g.setFillColor(
                            i == 0 ? PdfColors.green700 : PdfColors.blue700);
                        g.drawEllipse(p.x, p.y, 3.5, 3.5);
                        g.fillPath();
                      }
                    }
                  },
                ),
              ),
            ),
            pw.SizedBox(height: 16),

            // ── Per-room summary boxes ───────────────────────────────────
            ...drawable.asMap().entries.map((entry) {
              final ri = entry.key;
              final s = entry.value;
              if (!s.isClosed || s.points.length < 3) return pw.SizedBox();
              final n = s.points.length;
              double perimeter = 0;
              for (int i = 0; i < n; i++) {
                perimeter += (s.points[(i + 1) % n] - s.points[i]).distance;
              }
              double area = 0;
              for (int i = 0; i < n; i++) {
                final j = (i + 1) % n;
                area += s.points[i].dx * s.points[j].dy;
                area -= s.points[j].dx * s.points[i].dy;
              }
              area = area.abs() / 2.0;

              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(s.label ?? 'Room ${ri + 1}',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blueGrey700)),
                  pw.SizedBox(height: 4),
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
                        _pdfSummaryItem('POINTS', '${n}'),
                        _pdfDivider(),
                        _pdfSummaryItem('PERIMETER', formatLength(perimeter)),
                        _pdfDivider(),
                        _pdfSummaryItem('AREA', formatArea(area)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                ],
              );
            }),

            // ── Wall measurements table ──────────────────────────────────
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
                0: const pw.FlexColumnWidth(1.5),
                1: const pw.FlexColumnWidth(1.0),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.blueGrey100),
                  children: ['Room', 'Wall', 'Drawn Length', 'Real Measurement']
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
                ...allWallRows.expand((roomRows) => roomRows).map(
                      (row) => pw.TableRow(
                        children: [
                          row['room']!,
                          row['wall']!,
                          row['drawn']!,
                          row['real']!
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
                      ),
                    ),
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
    name: 'floor_plan',
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