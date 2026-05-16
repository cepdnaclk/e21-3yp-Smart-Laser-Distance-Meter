import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'furniture_item.dart';
import 'sketch_constants.dart';

// ── Rotation handle ───────────────────────────────────────────────────────────
// Returns the screen-space position of the rotation handle for a furniture item.
// Call this from both the painter (to draw it) and the gesture handler (to hit-test it).
Offset furnitureRotationHandlePos({
  required FurnitureItem item,
  required Offset Function(Offset) worldToScreen,
  required double scale,
}) {
  final center = worldToScreen(item.position);
  final halfPx = math.max(item.widthMm, item.depthMm) / mmPerUnit * scale / 2;
  return center - Offset(0, halfPx + 30);
}

// ── Public entry point ────────────────────────────────────────────────────────
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

  // Rotation handle (drawn in screen space, not rotated)
  if (isSelected) {
    final handle = furnitureRotationHandlePos(
        item: item, worldToScreen: worldToScreen, scale: scale);
    // Stem line
    canvas.drawLine(
      center,
      handle,
      Paint()
        ..color = const Color(0xFF1976D2).withOpacity(0.6)
        ..strokeWidth = 1.2,
    );
    // Handle circle
    canvas.drawCircle(handle, 9,
        Paint()..color = const Color(0xFF1976D2)..style = PaintingStyle.fill);
    canvas.drawCircle(handle, 9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    // Rotation arrow icon (simplified arc with arrowhead)
    final rect = Rect.fromCenter(center: handle, width: 12, height: 12);
    canvas.drawArc(rect, -math.pi * 0.8, math.pi * 1.4, false,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);
  }
}

// ── Architectural style helpers ───────────────────────────────────────────────
Paint _fill(bool sel) => Paint()
  ..color = sel ? const Color(0xFFE3F2FD) : const Color(0xFFF7F7F7)
  ..style = PaintingStyle.fill;

Paint _stroke(bool sel, [double sw = 1.5]) => Paint()
  ..color = sel ? const Color(0xFF1565C0) : const Color(0xFF222222)
  ..style = PaintingStyle.stroke
  ..strokeWidth = sw;

Paint _detail() => Paint()
  ..color = const Color(0xFF444444)
  ..style = PaintingStyle.stroke
  ..strokeWidth = 0.8
  ..strokeCap = StrokeCap.round;

// ── Selection overlay ─────────────────────────────────────────────────────────
void _drawSelectionOverlay(Canvas canvas, double w, double d) {
  final rect = Rect.fromCenter(center: Offset.zero, width: w + 4, height: d + 4);
  _drawDashedRect(canvas, rect,
      Paint()
        ..color = const Color(0xFF1976D2)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke);

  // Corner resize handles
  for (final corner in [
    Offset(-w / 2 - 2, -d / 2 - 2),
    Offset( w / 2 + 2, -d / 2 - 2),
    Offset( w / 2 + 2,  d / 2 + 2),
    Offset(-w / 2 - 2,  d / 2 + 2),
  ]) {
    canvas.drawRect(
        Rect.fromCenter(center: corner, width: 8, height: 8),
        Paint()..color = const Color(0xFF1976D2)..style = PaintingStyle.fill);
    canvas.drawRect(
        Rect.fromCenter(center: corner, width: 8, height: 8),
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }
}

void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
  const double dashLen = 6.0, gapLen = 4.0;
  final path = Path()..addRect(rect);
  for (final metric in path.computeMetrics()) {
    double dist = 0;
    bool drawing = true;
    while (dist < metric.length) {
      final seg = math.min(dist + (drawing ? dashLen : gapLen), metric.length);
      if (drawing) canvas.drawPath(metric.extractPath(dist, seg), paint);
      dist = seg;
      drawing = !drawing;
    }
  }
}

// ── Symbol dispatcher ─────────────────────────────────────────────────────────
void _drawSymbol(Canvas canvas, FurnitureType type, double w, double d, bool sel) {
  switch (type) {
    case FurnitureType.sofa:            _drawSofa(canvas, w, d, sel); break;
    case FurnitureType.armchair:        _drawArmchair(canvas, w, d, sel); break;
    case FurnitureType.coffeeTable:     _drawCoffeeTable(canvas, w, d, sel); break;
    case FurnitureType.floorLamp:       _drawFloorLamp(canvas, w, d, sel); break;
    case FurnitureType.bookshelf:       _drawBookshelf(canvas, w, d, sel); break;
    case FurnitureType.tvUnit:          _drawTvUnit(canvas, w, d, sel); break;
    case FurnitureType.singleBed:       _drawBed(canvas, w, d, sel, single: true); break;
    case FurnitureType.doubleBed:       _drawBed(canvas, w, d, sel, single: false); break;
    case FurnitureType.queenBed:        _drawBed(canvas, w, d, sel, single: false); break;
    case FurnitureType.kingBed:         _drawBed(canvas, w, d, sel, single: false); break;
    case FurnitureType.dresser:         _drawDresser(canvas, w, d, sel); break;
    case FurnitureType.nightstand:      _drawNightstand(canvas, w, d, sel); break;
    case FurnitureType.wardrobe:        _drawWardrobe(canvas, w, d, sel); break;
    case FurnitureType.diningTable:     _drawDiningTable(canvas, w, d, sel); break;
    case FurnitureType.roundDiningTable:_drawRoundDiningTable(canvas, w, d, sel); break;
    case FurnitureType.barStool:        _drawChair(canvas, w, d, sel); break;
    case FurnitureType.chair:           _drawChair(canvas, w, d, sel); break;
    case FurnitureType.kitchenCounter:  _drawKitchenCounter(canvas, w, d, sel); break;
    case FurnitureType.islandCounter:   _drawIslandCounter(canvas, w, d, sel); break;
    case FurnitureType.refrigerator:    _drawRefrigerator(canvas, w, d, sel); break;
    case FurnitureType.stove:           _drawStove(canvas, w, d, sel); break;
    case FurnitureType.sink:            _drawSink(canvas, w, d, sel); break;
    case FurnitureType.bathtub:         _drawBathtub(canvas, w, d, sel); break;
    case FurnitureType.shower:          _drawShower(canvas, w, d, sel); break;
    case FurnitureType.toilet:          _drawToilet(canvas, w, d, sel); break;
    case FurnitureType.basinSink:       _drawBasinSink(canvas, w, d, sel); break;
    case FurnitureType.vanity:          _drawVanity(canvas, w, d, sel); break;
    case FurnitureType.desk:            _drawDesk(canvas, w, d, sel); break;
    case FurnitureType.officeChair:     _drawOfficeChair(canvas, w, d, sel); break;
    case FurnitureType.filingCabinet:   _drawFilingCabinet(canvas, w, d, sel); break;
    case FurnitureType.washingMachine:  _drawWashingMachine(canvas, w, d, sel); break;
  }
}

// ── Sofa ──────────────────────────────────────────────────────────────────────
void _drawSofa(Canvas canvas, double w, double d, bool sel) {
  final backH = d * 0.28;
  final armW  = w * 0.12;

  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));

  // Back (top strip)
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, backH),
      Paint()..color = (sel ? const Color(0xFF90CAF9) : const Color(0xFFDDDDDD))
        ..style = PaintingStyle.fill);

  // Armrests
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2 + backH, armW, d - backH),
      Paint()..color = (sel ? const Color(0xFF90CAF9) : const Color(0xFFDDDDDD))
        ..style = PaintingStyle.fill);
  canvas.drawRect(Rect.fromLTWH(w/2 - armW, -d/2 + backH, armW, d - backH),
      Paint()..color = (sel ? const Color(0xFF90CAF9) : const Color(0xFFDDDDDD))
        ..style = PaintingStyle.fill);

  // Seat cushion lines
  final seatX = -w/2 + armW;
  final seatW = w - 2 * armW;
  final seatY = -d/2 + backH;
  final seatH = d - backH;
  canvas.drawLine(Offset(seatX + seatW/3, seatY), Offset(seatX + seatW/3, seatY + seatH), _detail());
  canvas.drawLine(Offset(seatX + 2*seatW/3, seatY), Offset(seatX + 2*seatW/3, seatY + seatH), _detail());

  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Armchair ──────────────────────────────────────────────────────────────────
void _drawArmchair(Canvas canvas, double w, double d, bool sel) {
  final backH = d * 0.30;
  final armW  = w * 0.20;

  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, backH),
      Paint()..color = (sel ? const Color(0xFF90CAF9) : const Color(0xFFDDDDDD))
        ..style = PaintingStyle.fill);
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2 + backH, armW, d - backH),
      Paint()..color = (sel ? const Color(0xFF90CAF9) : const Color(0xFFDDDDDD))
        ..style = PaintingStyle.fill);
  canvas.drawRect(Rect.fromLTWH(w/2 - armW, -d/2 + backH, armW, d - backH),
      Paint()..color = (sel ? const Color(0xFF90CAF9) : const Color(0xFFDDDDDD))
        ..style = PaintingStyle.fill);
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Bed ───────────────────────────────────────────────────────────────────────
void _drawBed(Canvas canvas, double w, double d, bool sel, {required bool single}) {
  final headH = d * 0.15;
  final foldY = d * 0.30;

  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));

  // Headboard (darker strip at top)
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, headH),
      Paint()..color = (sel ? const Color(0xFF90CAF9) : const Color(0xFFCCCCCC))
        ..style = PaintingStyle.fill);

  // Pillows
  final pY = -d/2 + headH + 3;
  final pH = d * 0.18;
  if (single) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-w/2+6, pY, w-12, pH), const Radius.circular(4)),
        Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-w/2+6, pY, w-12, pH), const Radius.circular(4)),
        _detail());
  } else {
    final pw = (w - 20) / 2;
    for (final px in [-w/2 + 6.0, 8.0]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(px, pY, pw, pH), const Radius.circular(4)),
          Paint()..color = Colors.white..style = PaintingStyle.fill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(px, pY, pw, pH), const Radius.circular(4)),
          _detail());
    }
  }

  // Cover fold line
  canvas.drawLine(Offset(-w/2 + 4, -d/2 + foldY), Offset(w/2 - 4, -d/2 + foldY), _detail());
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Chair (side chair) ────────────────────────────────────────────────────────
void _drawChair(Canvas canvas, double w, double d, bool sel) {
  final backH = d * 0.20;
  final seatH = d * 0.65;

  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));

  // Back arc
  final backRect = Rect.fromLTWH(-w/2, -d/2, w, backH * 2);
  canvas.drawArc(backRect, math.pi, math.pi, false, _stroke(sel, 1.8));

  // Seat
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2+3, -d/2+backH, w-6, seatH),
          const Radius.circular(4)),
      Paint()..color = (sel ? const Color(0xFFBBDEFB) : const Color(0xFFEEEEEE))
        ..style = PaintingStyle.fill);
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2+3, -d/2+backH, w-6, seatH),
          const Radius.circular(4)),
      _stroke(sel));
}

// ── Dining Table ──────────────────────────────────────────────────────────────
void _drawDiningTable(Canvas canvas, double w, double d, bool sel) {
  final tableW = w * 0.72, tableD = d * 0.72;
  final chairW = w * 0.18, chairD = d * 0.22;

  void drawChair(Rect r) {
    canvas.drawRect(r, Paint()..color = const Color(0xFFEEEEEE)..style = PaintingStyle.fill);
    canvas.drawRect(r, _detail());
  }

  drawChair(Rect.fromCenter(center: Offset(0, -d/2 - chairD/2 + 2), width: chairW*1.8, height: chairD));
  drawChair(Rect.fromCenter(center: Offset(0,  d/2 + chairD/2 - 2), width: chairW*1.8, height: chairD));
  drawChair(Rect.fromCenter(center: Offset(-w/2 - chairW/2 + 2, 0), width: chairW, height: chairD*1.8));
  drawChair(Rect.fromCenter(center: Offset( w/2 + chairW/2 - 2, 0), width: chairW, height: chairD*1.8));

  // Table oval
  final tRect = Rect.fromCenter(center: Offset.zero, width: tableW, height: tableD);
  canvas.drawOval(tRect, _fill(sel));
  canvas.drawOval(tRect, _stroke(sel));

  // Cross grain lines
  canvas.drawLine(Offset(-tableW/2 + 6, 0), Offset(tableW/2 - 6, 0), _detail());
}

// ── Round Dining Table ────────────────────────────────────────────────────────
void _drawRoundDiningTable(Canvas canvas, double w, double d, bool sel) {
  final r = math.min(w, d) / 2;
  final chairD = r * 0.35;
  for (int i = 0; i < 4; i++) {
    final angle = i * math.pi / 2;
    final cx = (r + chairD/2) * math.cos(angle);
    final cy = (r + chairD/2) * math.sin(angle);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: chairD * 1.6, height: chairD),
        Paint()..color = const Color(0xFFEEEEEE)..style = PaintingStyle.fill);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: chairD * 1.6, height: chairD),
        _detail());
  }
  canvas.drawCircle(Offset.zero, r, _fill(sel));
  canvas.drawCircle(Offset.zero, r, _stroke(sel));
  canvas.drawLine(Offset(-r + 6, 0), Offset(r - 6, 0), _detail());
  canvas.drawLine(Offset(0, -r + 6), Offset(0, r - 6), _detail());
}

// ── Coffee Table ──────────────────────────────────────────────────────────────
void _drawCoffeeTable(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, d), const Radius.circular(6)),
      _fill(sel));
  // Inset line showing glass top
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2+6, -d/2+6, w-12, d-12), const Radius.circular(4)),
      Paint()..color = const Color(0xFFE0E0E0)..style = PaintingStyle.fill);
  // Leg marks at corners
  final inset = 8.0;
  for (final c in [
    Offset(-w/2 + inset, -d/2 + inset), Offset(w/2 - inset, -d/2 + inset),
    Offset(-w/2 + inset,  d/2 - inset), Offset(w/2 - inset,  d/2 - inset),
  ]) {
    canvas.drawCircle(c, 3, Paint()..color = const Color(0xFFBBBBBB)..style = PaintingStyle.fill);
  }
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, d), const Radius.circular(6)),
      _stroke(sel));
}

// ── Wardrobe ──────────────────────────────────────────────────────────────────
void _drawWardrobe(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  canvas.drawLine(Offset(0, -d/2), Offset(0, d/2), _detail());
  // Diagonal X marks on each half
  for (final xOff in [-w/4, w/4]) {
    final l = w/2 - 5;
    final h = d - 8;
    canvas.drawLine(Offset(xOff - l/2, -h/2), Offset(xOff + l/2, h/2), _detail());
    canvas.drawLine(Offset(xOff + l/2, -h/2), Offset(xOff - l/2, h/2), _detail());
  }
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Bookshelf ─────────────────────────────────────────────────────────────────
void _drawBookshelf(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  for (int i = 1; i <= 3; i++) {
    final y = -d/2 + d * i / 4;
    canvas.drawLine(Offset(-w/2 + 3, y), Offset(w/2 - 3, y), _detail());
  }
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Dresser ───────────────────────────────────────────────────────────────────
void _drawDresser(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  const rows = 3;
  for (int i = 0; i < rows; i++) {
    final y = -d/2 + d * (i + 1) / rows;
    if (i < rows - 1) canvas.drawLine(Offset(-w/2+3, y), Offset(w/2-3, y), _detail());
    // Handle
    canvas.drawLine(Offset(-8, y - d/rows/2), Offset(8, y - d/rows/2),
        Paint()..color = const Color(0xFF666666)..style = PaintingStyle.stroke
          ..strokeWidth = 1.5..strokeCap = StrokeCap.round);
  }
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Nightstand ────────────────────────────────────────────────────────────────
void _drawNightstand(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  canvas.drawLine(Offset(-w/2+3, 0), Offset(w/2-3, 0), _detail());
  canvas.drawLine(Offset(-7, d/4), Offset(7, d/4),
      Paint()..color = const Color(0xFF666666)..style = PaintingStyle.stroke
        ..strokeWidth = 1.5..strokeCap = StrokeCap.round);
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Desk ──────────────────────────────────────────────────────────────────────
void _drawDesk(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  // Drawer row at bottom
  final dY = d/2 - d * 0.32;
  canvas.drawLine(Offset(-w/2+3, dY), Offset(w/2-3, dY), _detail());
  for (final hx in [-w/4, w/4]) {
    canvas.drawLine(Offset(hx-8, dY + d*0.16), Offset(hx+8, dY + d*0.16),
        Paint()..color = const Color(0xFF666666)..style = PaintingStyle.stroke
          ..strokeWidth = 1.5..strokeCap = StrokeCap.round);
  }
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Vanity ────────────────────────────────────────────────────────────────────
void _drawVanity(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  canvas.drawLine(Offset(-w/2+3, 0), Offset(w/2-3, 0), _detail());
  // Mirror oval on top half
  canvas.drawOval(Rect.fromLTWH(-w/4, -d/2+4, w/2, d*0.35), _detail());
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Office Chair ──────────────────────────────────────────────────────────────
void _drawOfficeChair(Canvas canvas, double w, double d, bool sel) {
  final r = math.min(w, d) / 2;
  canvas.drawCircle(Offset.zero, r, _fill(sel));
  canvas.drawCircle(Offset.zero, r, _stroke(sel));
  // Star base pattern
  for (int i = 0; i < 5; i++) {
    final a = i * 2 * math.pi / 5;
    canvas.drawLine(Offset.zero, Offset(r * 0.65 * math.cos(a), r * 0.65 * math.sin(a)), _detail());
  }
  // Backrest arc (top)
  canvas.drawArc(Rect.fromCenter(center: Offset(0, -r * 0.1), width: r * 1.5, height: r * 1.5),
      math.pi + 0.3, math.pi - 0.6, false, _stroke(sel, 1.8));
}

// ── TV Unit ───────────────────────────────────────────────────────────────────
void _drawTvUnit(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  // Screen area (inset rect showing the TV)
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2+6, -d/2+4, w-12, d-8), const Radius.circular(2)),
      Paint()..color = const Color(0xFFDDDDDD)..style = PaintingStyle.fill);
  // Diagonal cross on screen
  canvas.drawLine(Offset(-w/2+8, -d/2+6), Offset(w/2-8, d/2-6), _detail());
  canvas.drawLine(Offset(w/2-8, -d/2+6), Offset(-w/2+8, d/2-6), _detail());
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Floor Lamp ────────────────────────────────────────────────────────────────
void _drawFloorLamp(Canvas canvas, double w, double d, bool sel) {
  final r = math.min(w, d) / 2;
  canvas.drawCircle(Offset.zero, r, _fill(sel));
  canvas.drawCircle(Offset.zero, r, _stroke(sel));
  canvas.drawCircle(Offset.zero, r * 0.25,
      Paint()..color = const Color(0xFFFFEE88)..style = PaintingStyle.fill);
  canvas.drawCircle(Offset.zero, r * 0.25, _detail());
}

// ── Kitchen Counter ───────────────────────────────────────────────────────────
void _drawKitchenCounter(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  // Front edge line
  canvas.drawLine(Offset(-w/2+3, d/2-5), Offset(w/2-3, d/2-5), _detail());
  // Counter depth shadow line
  canvas.drawLine(Offset(-w/2+3, -d/2+6), Offset(w/2-3, -d/2+6), _detail());
  // Sink basin
  final sinkR = math.min(w * 0.14, d * 0.3);
  canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.25, 0), width: sinkR*2.4, height: sinkR*1.8),
      Paint()..color = const Color(0xFFE0E0E0)..style = PaintingStyle.fill);
  canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.25, 0), width: sinkR*2.4, height: sinkR*1.8),
      _detail());
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Island Counter ────────────────────────────────────────────────────────────
void _drawIslandCounter(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, d), const Radius.circular(4)),
      _fill(sel));
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2+8, -d/2+8, w-16, d-16), const Radius.circular(3)),
      Paint()..color = const Color(0xFFE8E8E8)..style = PaintingStyle.fill);
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, d), const Radius.circular(4)),
      _stroke(sel));
}

// ── Refrigerator ──────────────────────────────────────────────────────────────
void _drawRefrigerator(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  final divY = -d/2 + d * 0.62;
  canvas.drawLine(Offset(-w/2+3, divY), Offset(w/2-3, divY), _detail());
  // Handles
  final hx = w/2 - 7;
  canvas.drawLine(Offset(hx, -d/2 + d*0.15), Offset(hx, -d/2 + d*0.45),
      Paint()..color = const Color(0xFF888888)..style = PaintingStyle.stroke
        ..strokeWidth = 2.5..strokeCap = StrokeCap.round);
  canvas.drawLine(Offset(hx, divY + d*0.06), Offset(hx, divY + d*0.22),
      Paint()..color = const Color(0xFF888888)..style = PaintingStyle.stroke
        ..strokeWidth = 2.5..strokeCap = StrokeCap.round);
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Stove ─────────────────────────────────────────────────────────────────────
void _drawStove(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  final bR = math.min(w, d) * 0.16;
  for (final pos in [
    Offset(-w/4, -d/4), Offset(w/4, -d/4),
    Offset(-w/4,  d/4), Offset(w/4,  d/4),
  ]) {
    canvas.drawCircle(pos, bR,
        Paint()..color = const Color(0xFFE8E8E8)..style = PaintingStyle.fill);
    canvas.drawCircle(pos, bR, _detail());
    canvas.drawCircle(pos, bR * 0.35,
        Paint()..color = const Color(0xFFCCCCCC)..style = PaintingStyle.fill);
  }
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Kitchen Sink ──────────────────────────────────────────────────────────────
void _drawSink(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  canvas.drawOval(Rect.fromLTWH(-w/2+8, -d/2+8, w-16, d-16),
      Paint()..color = const Color(0xFFE0E0E0)..style = PaintingStyle.fill);
  canvas.drawOval(Rect.fromLTWH(-w/2+8, -d/2+8, w-16, d-16), _detail());
  canvas.drawCircle(const Offset(0, 6), 3,
      Paint()..color = const Color(0xFF888888)..style = PaintingStyle.fill);
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Bathtub ───────────────────────────────────────────────────────────────────
void _drawBathtub(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, d), const Radius.circular(10)),
      _fill(sel));
  // Inner tub area
  canvas.drawOval(Rect.fromLTWH(-w/2+8, -d/2+10, w-16, d-28),
      Paint()..color = const Color(0xFFE8E8E8)..style = PaintingStyle.fill);
  canvas.drawOval(Rect.fromLTWH(-w/2+8, -d/2+10, w-16, d-28), _detail());
  // Tap end (top)
  for (final tx in [-9.0, 9.0]) {
    canvas.drawCircle(Offset(tx, -d/2+7), 3.5,
        Paint()..color = const Color(0xFFAAAAAA)..style = PaintingStyle.fill);
  }
  // Drain (bottom)
  canvas.drawCircle(Offset(0, d/2-10), 4,
      Paint()..color = const Color(0xFFBBBBBB)..style = PaintingStyle.fill);
  canvas.drawCircle(Offset(0, d/2-10), 4, _detail());
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, d), const Radius.circular(10)),
      _stroke(sel));
}

// ── Shower ────────────────────────────────────────────────────────────────────
void _drawShower(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  // Drain
  canvas.drawCircle(Offset.zero, math.min(w, d) * 0.14,
      Paint()..color = const Color(0xFFDDDDDD)..style = PaintingStyle.fill);
  canvas.drawCircle(Offset.zero, math.min(w, d) * 0.14, _detail());
  // Showerhead corner dot
  canvas.drawCircle(Offset(-w/2 + 10, -d/2 + 10), 5,
      Paint()..color = const Color(0xFFCCCCCC)..style = PaintingStyle.fill);
  canvas.drawCircle(Offset(-w/2 + 10, -d/2 + 10), 5, _detail());
  // Water drop lines radiating from showerhead
  for (int i = 0; i < 4; i++) {
    final a = math.pi/4 + i * math.pi / 2;
    canvas.drawLine(
        Offset(-w/2 + 10 + 8*math.cos(a), -d/2 + 10 + 8*math.sin(a)),
        Offset(-w/2 + 10 + 14*math.cos(a), -d/2 + 10 + 14*math.sin(a)),
        _detail());
  }
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Toilet ────────────────────────────────────────────────────────────────────
void _drawToilet(Canvas canvas, double w, double d, bool sel) {
  final tankH = d * 0.30;
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, tankH), const Radius.circular(4)),
      _fill(sel));
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, tankH), const Radius.circular(4)),
      _stroke(sel));
  // Bowl
  canvas.drawOval(Rect.fromLTWH(-w/2, -d/2 + tankH + 2, w, d - tankH - 2), _fill(sel));
  canvas.drawOval(Rect.fromLTWH(-w/2+6, -d/2 + tankH + 8, w-12, d-tankH-16), _detail());
  canvas.drawOval(Rect.fromLTWH(-w/2, -d/2 + tankH + 2, w, d - tankH - 2), _stroke(sel));
}

// ── Basin Sink ────────────────────────────────────────────────────────────────
void _drawBasinSink(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, d), const Radius.circular(8)),
      _fill(sel));
  canvas.drawOval(Rect.fromLTWH(-w/2+8, -d/2+8, w-16, d-16),
      Paint()..color = const Color(0xFFE0E0E0)..style = PaintingStyle.fill);
  canvas.drawOval(Rect.fromLTWH(-w/2+8, -d/2+8, w-16, d-16), _detail());
  canvas.drawCircle(const Offset(0, 0), 3,
      Paint()..color = const Color(0xFF888888)..style = PaintingStyle.fill);
  canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w/2, -d/2, w, d), const Radius.circular(8)),
      _stroke(sel));
}

// ── Filing Cabinet ────────────────────────────────────────────────────────────
void _drawFilingCabinet(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  for (int i = 1; i <= 3; i++) {
    final y = -d/2 + d * i / 4;
    if (i < 4) canvas.drawLine(Offset(-w/2+3, y), Offset(w/2-3, y), _detail());
    canvas.drawLine(Offset(-7, y - d/8), Offset(7, y - d/8),
        Paint()..color = const Color(0xFF666666)..style = PaintingStyle.stroke
          ..strokeWidth = 1.5..strokeCap = StrokeCap.round);
  }
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}

// ── Washing Machine ───────────────────────────────────────────────────────────
void _drawWashingMachine(Canvas canvas, double w, double d, bool sel) {
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _fill(sel));
  final r = math.min(w, d) * 0.33;
  canvas.drawCircle(Offset(0, d * 0.06), r,
      Paint()..color = const Color(0xFFE0E0E0)..style = PaintingStyle.fill);
  canvas.drawCircle(Offset(0, d * 0.06), r, _stroke(sel));
  canvas.drawCircle(Offset(0, d * 0.06), r * 0.5, _detail());
  // Control strip (top)
  canvas.drawLine(Offset(-w/2+4, -d/2+6), Offset(w/2-4, -d/2+6), _detail());
  canvas.drawRect(Rect.fromLTWH(-w/2, -d/2, w, d), _stroke(sel));
}
