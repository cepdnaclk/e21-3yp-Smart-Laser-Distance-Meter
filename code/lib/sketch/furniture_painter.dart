import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'furniture_item.dart';
import 'sketch_constants.dart';

/// Public entry point — call this from SketchPainter.paint()
void drawFurnitureItem({
  required Canvas canvas,
  required FurnitureItem item,
  required Offset Function(Offset) worldToScreen,
  required double scale,
  required bool isSelected,
}) {
  final center = worldToScreen(item.position);
  final w = item.widthMm / mmPerUnit * scale;
  final d = item.depthMm / mmPerUnit * scale;

  if (w < 4 || d < 4) return;

  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(item.rotationDeg * math.pi / 180);

  _drawSymbol(canvas, item.type, w, d, isSelected);

  if (isSelected) {
    _drawSelectionOverlay(canvas, w, d);
  }

  canvas.restore();
}

// ── Selection overlay ───────────────────────────────────────────────────
void _drawSelectionOverlay(Canvas canvas, double w, double d) {
  final rect = Rect.fromCenter(center: Offset.zero, width: w, height: d);

  // Dashed blue border
  final paint = Paint()
    ..color = const Color(0xFF0099FF)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  _drawDashedRect(canvas, rect, paint);

  // Corner handles
  final handlePaint = Paint()
    ..color = const Color(0xFF0099FF)
    ..style = PaintingStyle.fill;

  for (final corner in [
    Offset(-w / 2, -d / 2),
    Offset(w / 2, -d / 2),
    Offset(w / 2, d / 2),
    Offset(-w / 2, d / 2),
  ]) {
    canvas.drawCircle(corner, 4.5, handlePaint);
    canvas.drawCircle(
      corner,
      4.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}

void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
  const double dashLen = 5.0, gapLen = 4.0;
  final path = Path()..addRect(rect);
  final metrics = path.computeMetrics();
  for (final metric in metrics) {
    double dist = 0;
    bool drawing = true;
    while (dist < metric.length) {
      final seg = math.min(dist + (drawing ? dashLen : gapLen), metric.length);
      if (drawing) {
        canvas.drawPath(metric.extractPath(dist, seg), paint);
      }
      dist = seg;
      drawing = !drawing;
    }
  }
}

// ── Symbol dispatcher ───────────────────────────────────────────────────
void _drawSymbol(Canvas canvas, FurnitureType type, double w, double d, bool sel) {
  switch (type) {
    case FurnitureType.sofa:
      _drawSofa(canvas, w, d, sel); break;
    case FurnitureType.armchair:
      _drawArmchair(canvas, w, d, sel); break;
    case FurnitureType.coffeeTable:
      _drawCoffeeTable(canvas, w, d, sel); break;
    case FurnitureType.floorLamp:
      _drawFloorLamp(canvas, w, d, sel); break;
    case FurnitureType.bookshelf:
      _drawBookshelf(canvas, w, d, sel); break;
    case FurnitureType.tvUnit:
      _drawTvUnit(canvas, w, d, sel); break;
    case FurnitureType.singleBed:
      _drawBed(canvas, w, d, sel, single: true); break;
    case FurnitureType.doubleBed:
      _drawBed(canvas, w, d, sel, single: false); break;
    case FurnitureType.queenBed:
      _drawBed(canvas, w, d, sel, single: false); break;
    case FurnitureType.kingBed:
      _drawBed(canvas, w, d, sel, single: false); break;
    case FurnitureType.dresser:
      _drawDresser(canvas, w, d, sel); break;
    case FurnitureType.nightstand:
      _drawNightstand(canvas, w, d, sel); break;
    case FurnitureType.wardrobe:
      _drawWardrobe(canvas, w, d, sel); break;
    case FurnitureType.diningTable:
      _drawDiningTable(canvas, w, d, sel); break;
    case FurnitureType.roundDiningTable:
      _drawRoundDiningTable(canvas, w, d, sel); break;
    case FurnitureType.barStool:
      _drawChair(canvas, w, d, sel); break;
    case FurnitureType.chair:
      _drawChair(canvas, w, d, sel); break;
    case FurnitureType.kitchenCounter:
      _drawKitchenCounter(canvas, w, d, sel); break;
    case FurnitureType.islandCounter:
      _drawIslandCounter(canvas, w, d, sel); break;
    case FurnitureType.refrigerator:
      _drawRefrigerator(canvas, w, d, sel); break;
    case FurnitureType.stove:
      _drawStove(canvas, w, d, sel); break;
    case FurnitureType.sink:
      _drawSink(canvas, w, d, sel); break;
    case FurnitureType.bathtub:
      _drawBathtub(canvas, w, d, sel); break;
    case FurnitureType.shower:
      _drawShower(canvas, w, d, sel); break;
    case FurnitureType.toilet:
      _drawToilet(canvas, w, d, sel); break;
    case FurnitureType.basinSink:
      _drawBasinSink(canvas, w, d, sel); break;
    case FurnitureType.vanity:
      _drawDesk(canvas, w, d, sel); break;
    case FurnitureType.desk:
      _drawDesk(canvas, w, d, sel); break;
    case FurnitureType.officeChair:
      _drawChair(canvas, w, d, sel); break;
    case FurnitureType.filingCabinet:
      _drawFilingCabinet(canvas, w, d, sel); break;
    case FurnitureType.washingMachine:
      _drawWashingMachine(canvas, w, d, sel); break;
  }
}

// ── Helper paints ───────────────────────────────────────────────────────
Paint _fill(Color c) => Paint()..color = c..style = PaintingStyle.fill;
Paint _stroke(Color c, double sw) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = sw;

// ── Sofa ─────────────────────────────────────────────────────────────────
void _drawSofa(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32);
  final fillColor = sel ? const Color(0xFF81C784) : const Color(0xFFA5D6A7);
  final backH = d * 0.30;
  final armW = w * 0.12;

  // Outer rect
  final outer = Rect.fromLTWH(-w / 2, -d / 2, w, d);
  canvas.drawRect(outer, _fill(fillColor));
  canvas.drawRect(outer, _stroke(outlineColor, 1.5));

  // Backrest (top 30%)
  final back = Rect.fromLTWH(-w / 2, -d / 2, w, backH);
  canvas.drawRect(back, _fill(outlineColor.withOpacity(0.35)));
  canvas.drawRect(back, _stroke(outlineColor, 1.0));

  // Armrests left & right
  final armL = Rect.fromLTWH(-w / 2, -d / 2 + backH, armW, d - backH);
  final armR = Rect.fromLTWH(w / 2 - armW, -d / 2 + backH, armW, d - backH);
  canvas.drawRect(armL, _fill(outlineColor.withOpacity(0.25)));
  canvas.drawRect(armL, _stroke(outlineColor, 1.0));
  canvas.drawRect(armR, _fill(outlineColor.withOpacity(0.25)));
  canvas.drawRect(armR, _stroke(outlineColor, 1.0));

  // Center seat divider
  canvas.drawLine(
    Offset(0, -d / 2 + backH),
    Offset(0, d / 2),
    _stroke(outlineColor, 1.0),
  );
}

// ── Bed ──────────────────────────────────────────────────────────────────
void _drawBed(Canvas canvas, double w, double d, bool sel, {required bool single}) {
  final outlineColor = sel ? const Color(0xFF1565C0) : const Color(0xFF1976D2);
  final fillColor = sel ? const Color(0xFF90CAF9) : const Color(0xFFBBDEFB);
  final headH = d * 0.13;
  final foldY = d / 2 - d * 0.28; // fold line from bottom

  // Outer rect
  final outer = Rect.fromLTWH(-w / 2, -d / 2, w, d);
  canvas.drawRect(outer, _fill(fillColor));
  canvas.drawRect(outer, _stroke(outlineColor, 1.5));

  // Headboard (top)
  final head = Rect.fromLTWH(-w / 2, -d / 2, w, headH);
  canvas.drawRect(head, _fill(outlineColor.withOpacity(0.45)));
  canvas.drawRect(head, _stroke(outlineColor, 1.0));

  // Pillow(s)
  final pillowH = d * 0.18;
  final pillowY = -d / 2 + headH + 4;
  if (single) {
    final pRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-w / 2 + 6, pillowY, w - 12, pillowH),
      const Radius.circular(4),
    );
    canvas.drawRRect(pRect, _fill(Colors.white.withOpacity(0.7)));
    canvas.drawRRect(pRect, _stroke(outlineColor, 1.0));
  } else {
    final pw = (w - 18) / 2;
    for (final px in [-w / 2 + 6, 6.0]) {
      final pRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(px, pillowY, pw, pillowH),
        const Radius.circular(4),
      );
      canvas.drawRRect(pRect, _fill(Colors.white.withOpacity(0.7)));
      canvas.drawRRect(pRect, _stroke(outlineColor, 1.0));
    }
  }

  // Cover fold line
  canvas.drawLine(
    Offset(-w / 2, foldY),
    Offset(w / 2, foldY),
    _stroke(outlineColor, 1.0),
  );
}

// ── Dining Table ─────────────────────────────────────────────────────────
void _drawDiningTable(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFFE65100) : const Color(0xFFEF6C00);
  final fillColor = sel ? const Color(0xFFFFCC80) : const Color(0xFFFFE0B2);
  final chairW = w * 0.18;
  final chairD = d * 0.22;
  final tableW = w * 0.72;
  final tableD = d * 0.72;

  // Draw 4 chairs outside the oval
  void drawChairRect(Rect r) {
    canvas.drawRect(r, _fill(outlineColor.withOpacity(0.20)));
    canvas.drawRect(r, _stroke(outlineColor, 1.0));
  }

  // Top
  drawChairRect(
    Rect.fromCenter(
      center: Offset(0, -d / 2 - chairD / 2 + 2),
      width: chairW * 1.8,
      height: chairD,
    ),
  );
  // Bottom
  drawChairRect(
    Rect.fromCenter(
      center: Offset(0, d / 2 + chairD / 2 - 2),
      width: chairW * 1.8,
      height: chairD,
    ),
  );
  // Left
  drawChairRect(
    Rect.fromCenter(
      center: Offset(-w / 2 - chairW / 2 + 2, 0),
      width: chairW,
      height: chairD * 1.8,
    ),
  );
  // Right
  drawChairRect(
    Rect.fromCenter(
      center: Offset(w / 2 + chairW / 2 - 2, 0),
      width: chairW,
      height: chairD * 1.8,
    ),
  );

  // Oval table
  final tableRect =
      Rect.fromCenter(center: Offset.zero, width: tableW, height: tableD);
  canvas.drawOval(tableRect, _fill(fillColor));
  canvas.drawOval(tableRect, _stroke(outlineColor, 1.5));
}

// ── Bathtub ─────────────────────────────────────────────────────────────
void _drawBathtub(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF00838F) : const Color(0xFF0097A7);
  final fillColor = sel ? const Color(0xFF80DEEA) : const Color(0xFFB2EBF2);

  // Outer rounded rect
  final outer = RRect.fromRectAndRadius(
    Rect.fromLTWH(-w / 2, -d / 2, w, d),
    const Radius.circular(10),
  );
  canvas.drawRRect(outer, _fill(fillColor));
  canvas.drawRRect(outer, _stroke(outlineColor, 1.5));

  // Inner oval (tub area)
  final inner = Rect.fromLTWH(-w / 2 + 8, -d / 2 + 8, w - 16, d - 26);
  canvas.drawOval(inner, _fill(Colors.white.withOpacity(0.5)));
  canvas.drawOval(inner, _stroke(outlineColor, 1.0));

  // Drain circle (bottom centre)
  canvas.drawCircle(
    Offset(0, d / 2 - 10),
    4,
    _fill(outlineColor.withOpacity(0.5)),
  );
  canvas.drawCircle(
    Offset(0, d / 2 - 10),
    4,
    _stroke(outlineColor, 1.0),
  );

  // Tap circles (top)
  for (final tx in [-8.0, 8.0]) {
    canvas.drawCircle(
      Offset(tx, -d / 2 + 9),
      3.5,
      _fill(outlineColor.withOpacity(0.7)),
    );
  }
}

// ── Toilet ──────────────────────────────────────────────────────────────
void _drawToilet(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF616161) : const Color(0xFF757575);
  final fillColor = const Color(0xFFF5F5F5);
  final tankH = d * 0.30;

  // Tank (top rect)
  final tank = RRect.fromRectAndRadius(
    Rect.fromLTWH(-w / 2, -d / 2, w, tankH),
    const Radius.circular(4),
  );
  canvas.drawRRect(tank, _fill(fillColor));
  canvas.drawRRect(tank, _stroke(outlineColor, 1.5));

  // Bowl (oval, remaining 70%)
  final bowlRect = Rect.fromLTWH(-w / 2, -d / 2 + tankH + 2, w, d - tankH - 2);
  canvas.drawOval(bowlRect, _fill(fillColor));
  canvas.drawOval(bowlRect, _stroke(outlineColor, 1.5));

  // Inner seat oval
  final seatRect = Rect.fromLTWH(
    -w / 2 + 5,
    -d / 2 + tankH + 7,
    w - 10,
    d - tankH - 14,
  );
  canvas.drawOval(seatRect, _stroke(outlineColor, 1.0));
}

// ── Kitchen Counter ─────────────────────────────────────────────────────
void _drawKitchenCounter(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFFBF360C) : const Color(0xFFD84315);
  final fillColor = sel ? const Color(0xFFFF8A65) : const Color(0xFFFFCCBC);

  // Outer rect
  final outer = Rect.fromLTWH(-w / 2, -d / 2, w, d);
  canvas.drawRect(outer, _fill(fillColor));
  canvas.drawRect(outer, _stroke(outlineColor, 1.5));

  // Inner edge line (countertop depth)
  canvas.drawLine(
    Offset(-w / 2 + 6, -d / 2 + 6),
    Offset(w / 2 - 6, -d / 2 + 6),
    _stroke(outlineColor, 1.0),
  );

  // 2 sink circles
  final sinkR = d * 0.25;
  for (final sx in [-w / 4, w / 4]) {
    canvas.drawCircle(
      Offset(sx, 0),
      sinkR,
      _fill(Colors.white.withOpacity(0.6)),
    );
    canvas.drawCircle(Offset(sx, 0), sinkR, _stroke(outlineColor, 1.0));
  }

  // Tap bridge between sinks
  canvas.drawLine(
    Offset(-w / 4, -sinkR),
    Offset(w / 4, -sinkR),
    _stroke(outlineColor, 1.5),
  );
}

// ── Wardrobe ────────────────────────────────────────────────────────────
void _drawWardrobe(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF4E342E) : const Color(0xFF5D4037);
  final fillColor = sel ? const Color(0xFFBCAAA4) : const Color(0xFFD7CCC8);

  // Outer rect
  final outer = Rect.fromLTWH(-w / 2, -d / 2, w, d);
  canvas.drawRect(outer, _fill(fillColor));
  canvas.drawRect(outer, _stroke(outlineColor, 1.5));

  // Center divider
  canvas.drawLine(Offset(0, -d / 2), Offset(0, d / 2), _stroke(outlineColor, 1.0));

  // X diagonals on each half
  for (final xOffset in [-w / 4, w / 4]) {
    final l = w / 2 - 4;
    final h = d - 8;
    canvas.drawLine(
      Offset(xOffset - l / 2, -h / 2),
      Offset(xOffset + l / 2, h / 2),
      _stroke(outlineColor.withOpacity(0.5), 0.8),
    );
    canvas.drawLine(
      Offset(xOffset + l / 2, -h / 2),
      Offset(xOffset - l / 2, h / 2),
      _stroke(outlineColor.withOpacity(0.5), 0.8),
    );
  }
}

// ── Desk ────────────────────────────────────────────────────────────────
void _drawDesk(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF37474F) : const Color(0xFF455A64);
  final fillColor = sel ? const Color(0xFF90A4AE) : const Color(0xFFB0BEC5);
  final drawerH = d * 0.32;

  // Outer rect
  final outer = Rect.fromLTWH(-w / 2, -d / 2, w, d);
  canvas.drawRect(outer, _fill(fillColor));
  canvas.drawRect(outer, _stroke(outlineColor, 1.5));

  // Drawer line
  final drawerY = d / 2 - drawerH;
  canvas.drawLine(
    Offset(-w / 2, drawerY),
    Offset(w / 2, drawerY),
    _stroke(outlineColor, 1.0),
  );

  // Drawer handles
  for (final hx in [-w / 4, w / 4]) {
    canvas.drawLine(
      Offset(hx - 8, drawerY + drawerH / 2),
      Offset(hx + 8, drawerY + drawerH / 2),
      _stroke(outlineColor, 1.5),
    );
  }
}

// ── Chair ───────────────────────────────────────────────────────────────
void _drawChair(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF33691E) : const Color(0xFF558B2F);
  final fillColor = sel ? const Color(0xFFAED581) : const Color(0xFFDCEDC8);
  final backH = d * 0.22;
  final seatH = d * 0.60;

  // Backrest arc (top 22%)
  final backRect = Rect.fromLTWH(-w / 2, -d / 2, w, backH * 2);
  canvas.drawArc(backRect, math.pi, math.pi, false, _stroke(outlineColor, 2.0));

  // Seat (rounded rect, middle 60%)
  final seat = RRect.fromRectAndRadius(
    Rect.fromLTWH(-w / 2 + 3, -d / 2 + backH, w - 6, seatH),
    const Radius.circular(6),
  );
  canvas.drawRRect(seat, _fill(fillColor));
  canvas.drawRRect(seat, _stroke(outlineColor, 1.5));
}

// ── Armchair ─────────────────────────────────────────────────────────────
void _drawArmchair(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF388E3C) : const Color(0xFF43A047);
  final fillColor    = sel ? const Color(0xFF81C784) : const Color(0xFFA5D6A7);
  final backH = d * 0.28;
  final armW  = w * 0.18;

  final outer = Rect.fromLTWH(-w / 2, -d / 2, w, d);
  canvas.drawRect(outer, _fill(fillColor));
  canvas.drawRect(outer, _stroke(outlineColor, 1.5));

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, backH),
      _fill(outlineColor.withOpacity(0.35)));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2 + backH, armW, d - backH),
      _fill(outlineColor.withOpacity(0.25)));
  canvas.drawRect(Rect.fromLTWH(w / 2 - armW, -d / 2 + backH, armW, d - backH),
      _fill(outlineColor.withOpacity(0.25)));
}

// ── Coffee Table ─────────────────────────────────────────────────────────
void _drawCoffeeTable(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF5D4037) : const Color(0xFF6D4C41);
  final fillColor    = sel ? const Color(0xFFBCAAA4) : const Color(0xFFD7CCC8);

  final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(-w / 2, -d / 2, w, d), const Radius.circular(6));
  canvas.drawRRect(outer, _fill(fillColor));
  canvas.drawRRect(outer, _stroke(outlineColor, 1.5));

  // Cross legs
  final inset = math.min(w, d) * 0.15;
  canvas.drawLine(Offset(-w / 2 + inset, -d / 2 + inset),
      Offset(w / 2 - inset, d / 2 - inset), _stroke(outlineColor, 1.0));
  canvas.drawLine(Offset(w / 2 - inset, -d / 2 + inset),
      Offset(-w / 2 + inset, d / 2 - inset), _stroke(outlineColor, 1.0));
}

// ── Floor Lamp ───────────────────────────────────────────────────────────
void _drawFloorLamp(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFFF9A825) : const Color(0xFFFBC02D);
  final r = math.min(w, d) / 2;

  canvas.drawCircle(Offset.zero, r, _fill(outlineColor.withOpacity(0.3)));
  canvas.drawCircle(Offset.zero, r, _stroke(outlineColor, 1.5));
  canvas.drawCircle(Offset.zero, r * 0.3, _fill(outlineColor));
}

// ── Bookshelf ────────────────────────────────────────────────────────────
void _drawBookshelf(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF4E342E) : const Color(0xFF5D4037);
  final fillColor    = sel ? const Color(0xFFBCAAA4) : const Color(0xFFD7CCC8);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // Shelf lines (3 shelves)
  final int shelves = 3;
  for (int i = 1; i <= shelves; i++) {
    final y = -d / 2 + d * i / (shelves + 1);
    canvas.drawLine(Offset(-w / 2 + 3, y), Offset(w / 2 - 3, y),
        _stroke(outlineColor, 0.8));
  }
}

// ── Dresser ─────────────────────────────────────────────────────────────
void _drawDresser(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF78909C) : const Color(0xFF90A4AE);
  final fillColor    = sel ? const Color(0xFFB0BEC5) : const Color(0xFFCFD8DC);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // 3 drawer rows
  final int rows = 3;
  for (int i = 0; i < rows; i++) {
    final y = -d / 2 + d * i / rows;
    canvas.drawLine(Offset(-w / 2 + 3, y + d / rows),
        Offset(w / 2 - 3, y + d / rows), _stroke(outlineColor, 0.8));
    canvas.drawLine(Offset(0, y + 3), Offset(0, y + d / rows - 3),
        _stroke(outlineColor, 0.8));
    // Handles
    for (final hx in [-w / 4, w / 4]) {
      canvas.drawLine(Offset(hx - 5, y + d / rows / 2),
          Offset(hx + 5, y + d / rows / 2), _stroke(outlineColor, 1.5));
    }
  }
}

// ── Nightstand ───────────────────────────────────────────────────────────
void _drawNightstand(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF546E7A) : const Color(0xFF607D8B);
  final fillColor    = sel ? const Color(0xFF90A4AE) : const Color(0xFFB0BEC5);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // One drawer
  canvas.drawLine(
      Offset(-w / 2 + 3, 0), Offset(w / 2 - 3, 0), _stroke(outlineColor, 0.8));
  canvas.drawLine(Offset(-6, d / 4), Offset(6, d / 4), _stroke(outlineColor, 1.5));
}

// ── Round Dining Table ───────────────────────────────────────────────────
void _drawRoundDiningTable(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFFE65100) : const Color(0xFFEF6C00);
  final fillColor    = sel ? const Color(0xFFFFCC80) : const Color(0xFFFFE0B2);
  final r = math.min(w, d) / 2;

  // 4 chairs around the circle
  final chairD = r * 0.35;
  for (int i = 0; i < 4; i++) {
    final angle = i * math.pi / 2;
    final cx = (r + chairD / 2) * math.cos(angle);
    final cy = (r + chairD / 2) * math.sin(angle);
    canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy), width: chairD * 1.5, height: chairD),
        _fill(outlineColor.withOpacity(0.20)));
    canvas.drawRect(
        Rect.fromCenter(center: Offset(cx, cy), width: chairD * 1.5, height: chairD),
        _stroke(outlineColor, 1.0));
  }

  canvas.drawCircle(Offset.zero, r, _fill(fillColor));
  canvas.drawCircle(Offset.zero, r, _stroke(outlineColor, 1.5));
}

// ── Island Counter ───────────────────────────────────────────────────────
void _drawIslandCounter(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFFBF360C) : const Color(0xFFD84315);
  final fillColor    = sel ? const Color(0xFFFF8A65) : const Color(0xFFFFCCBC);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // Surface marking
  canvas.drawRect(
      Rect.fromLTWH(-w / 2 + 6, -d / 2 + 6, w - 12, d - 12),
      _stroke(outlineColor.withOpacity(0.5), 0.8));
}

// ── Refrigerator ─────────────────────────────────────────────────────────
void _drawRefrigerator(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF546E7A) : const Color(0xFF607D8B);
  final fillColor    = sel ? const Color(0xFFB0BEC5) : const Color(0xFFCFD8DC);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // Divider (fridge on top ~65%, freezer below)
  final divY = -d / 2 + d * 0.65;
  canvas.drawLine(Offset(-w / 2 + 3, divY), Offset(w / 2 - 3, divY),
      _stroke(outlineColor, 1.0));

  // Handles
  canvas.drawLine(Offset(w / 2 - 6, -d / 2 + d * 0.2),
      Offset(w / 2 - 6, -d / 2 + d * 0.45), _stroke(outlineColor, 2.0));
  canvas.drawLine(Offset(w / 2 - 6, divY + d * 0.07),
      Offset(w / 2 - 6, divY + d * 0.2), _stroke(outlineColor, 2.0));
}

// ── Stove ────────────────────────────────────────────────────────────────
void _drawStove(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF455A64) : const Color(0xFF546E7A);
  final fillColor    = sel ? const Color(0xFF78909C) : const Color(0xFF90A4AE);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // 4 burner circles
  final bR = math.min(w, d) * 0.18;
  for (final pos in [
    Offset(-w / 4, -d / 4),
    Offset( w / 4, -d / 4),
    Offset(-w / 4,  d / 4),
    Offset( w / 4,  d / 4),
  ]) {
    canvas.drawCircle(pos, bR, _fill(outlineColor.withOpacity(0.5)));
    canvas.drawCircle(pos, bR, _stroke(outlineColor, 1.0));
    canvas.drawCircle(pos, bR * 0.4, _fill(outlineColor.withOpacity(0.7)));
  }
}

// ── Kitchen Sink ─────────────────────────────────────────────────────────
void _drawSink(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF00838F) : const Color(0xFF0097A7);
  final fillColor    = sel ? const Color(0xFF80DEEA) : const Color(0xFFB2EBF2);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // Basin oval
  final basin = Rect.fromLTWH(-w / 2 + 8, -d / 2 + 8, w - 16, d - 16);
  canvas.drawOval(basin, _fill(Colors.white.withOpacity(0.55)));
  canvas.drawOval(basin, _stroke(outlineColor, 1.0));
  canvas.drawCircle(Offset(0, d / 2 - 10), 3, _fill(outlineColor.withOpacity(0.6)));
}

// ── Shower ───────────────────────────────────────────────────────────────
void _drawShower(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF00838F) : const Color(0xFF0097A7);
  final fillColor    = sel ? const Color(0xFF80DEEA) : const Color(0xFFB2EBF2);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // Drain circle
  canvas.drawCircle(Offset.zero, math.min(w, d) * 0.15,
      _fill(outlineColor.withOpacity(0.4)));
  canvas.drawCircle(Offset.zero, math.min(w, d) * 0.15, _stroke(outlineColor, 1.0));

  // Showerhead dot (corner)
  canvas.drawCircle(Offset(-w / 2 + 8, -d / 2 + 8), 5, _fill(outlineColor));
}

// ── Basin Sink ───────────────────────────────────────────────────────────
void _drawBasinSink(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF00695C) : const Color(0xFF00796B);
  final fillColor    = sel ? const Color(0xFF80CBC4) : const Color(0xFFB2DFDB);

  final outer = RRect.fromRectAndRadius(
      Rect.fromLTWH(-w / 2, -d / 2, w, d), const Radius.circular(8));
  canvas.drawRRect(outer, _fill(fillColor));
  canvas.drawRRect(outer, _stroke(outlineColor, 1.5));

  final basin = Rect.fromLTWH(-w / 2 + 8, -d / 2 + 8, w - 16, d - 16);
  canvas.drawOval(basin, _fill(Colors.white.withOpacity(0.55)));
  canvas.drawOval(basin, _stroke(outlineColor, 1.0));
  canvas.drawCircle(Offset(0, 0), 3, _fill(outlineColor.withOpacity(0.6)));
}

// ── Filing Cabinet ───────────────────────────────────────────────────────
void _drawFilingCabinet(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF455A64) : const Color(0xFF546E7A);
  final fillColor    = sel ? const Color(0xFF78909C) : const Color(0xFF90A4AE);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // 4 drawer lines
  for (int i = 1; i <= 3; i++) {
    final y = -d / 2 + d * i / 4;
    canvas.drawLine(Offset(-w / 2 + 3, y), Offset(w / 2 - 3, y),
        _stroke(outlineColor, 0.8));
    canvas.drawLine(Offset(-6, y - d / 8), Offset(6, y - d / 8),
        _stroke(outlineColor, 1.5));
  }
  canvas.drawLine(Offset(-6, d / 2 - d / 8), Offset(6, d / 2 - d / 8),
      _stroke(outlineColor, 1.5));
}

// ── Washing Machine ──────────────────────────────────────────────────────
void _drawWashingMachine(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF1565C0) : const Color(0xFF1976D2);
  final fillColor    = sel ? const Color(0xFF90CAF9) : const Color(0xFFBBDEFB);

  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _fill(fillColor));
  canvas.drawRect(Rect.fromLTWH(-w / 2, -d / 2, w, d), _stroke(outlineColor, 1.5));

  // Door circle
  final r = math.min(w, d) * 0.33;
  canvas.drawCircle(Offset.zero, r, _fill(Colors.white.withOpacity(0.55)));
  canvas.drawCircle(Offset.zero, r, _stroke(outlineColor, 1.5));
  canvas.drawCircle(Offset.zero, r * 0.55,
      _fill(outlineColor.withOpacity(0.2)));
  canvas.drawCircle(Offset.zero, r * 0.55, _stroke(outlineColor, 1.0));

  // Control panel (top strip)
  canvas.drawLine(Offset(-w / 2 + 4, -d / 2 + 5), Offset(w / 2 - 4, -d / 2 + 5),
      _stroke(outlineColor, 1.0));
}

// ── TV Unit ─────────────────────────────────────────────────────────────
void _drawTvUnit(Canvas canvas, double w, double d, bool sel) {
  final outlineColor = sel ? const Color(0xFF6A1B9A) : const Color(0xFF7B1FA2);
  final fillColor = sel ? const Color(0xFFCE93D8) : const Color(0xFFE1BEE7);

  // Outer rect
  final outer = Rect.fromLTWH(-w / 2, -d / 2, w, d);
  canvas.drawRect(outer, _fill(fillColor));
  canvas.drawRect(outer, _stroke(outlineColor, 1.5));

  // Inset screen RRect
  final screen = RRect.fromRectAndRadius(
    Rect.fromLTWH(-w / 2 + 8, -d / 2 + 5, w - 16, d - 10),
    const Radius.circular(3),
  );
  canvas.drawRRect(screen, _fill(const Color(0xFF1A1A2E)));
  canvas.drawRRect(screen, _stroke(outlineColor, 1.0));

  // X diagonals on screen
  final sx = -w / 2 + 8, sy = -d / 2 + 5;
  final sw = w - 16, sh = d - 10;
  canvas.drawLine(
    Offset(sx, sy),
    Offset(sx + sw, sy + sh),
    _stroke(outlineColor.withOpacity(0.4), 0.8),
  );
  canvas.drawLine(
    Offset(sx + sw, sy),
    Offset(sx, sy + sh),
    _stroke(outlineColor.withOpacity(0.4), 0.8),
  );
}
