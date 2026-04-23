import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'sketch_constants.dart';
import 'sketch_model.dart';
import 'room_object.dart';
import 'room_object_utils.dart';

class SketchPainter extends CustomPainter {
  final Offset panOffset;
  final double scale;
  final double minorGrid;
  final double majorGrid;
  
  // New shape variables replacing the old single-room variables
  final List<SketchShape> shapes;
  final int activeIndex;

  final Offset? cursorWorld;
  final double snapRadiusWorld;
  final bool isDraggingLastPoint;
  final double lastPointGlowRadius;
  final double lastPointRingRadius;
  final double? snappedAngle;
  final bool isAngleSnapped;
  final double? currentAngleDeg;
  final double? nearestSnapAngleDeg;
  final double? snapDiffDeg;
  final Offset? angleRefWorld;
  final Offset? angleTargetWorld;
  final List<double> snapAngles;
  final int activePointIndex;
  final int? snapTargetIndex;
  final double? prevWallAngle;
  final double? nextWallAngle;
  final bool prevWallSnapped;
  final bool nextWallSnapped;
  final int selectedWallIndex;
  final int snapCandidateShape;
  final int snapCandidateWall;
  final List<({Rect rect, int wallIndex, int shapeIndex})> labelHitRects;

  const SketchPainter({
    required this.panOffset,
    required this.scale,
    required this.minorGrid,
    required this.majorGrid,
    required this.shapes,
    required this.activeIndex,
    required this.cursorWorld,
    required this.snapRadiusWorld,
    required this.isDraggingLastPoint,
    required this.lastPointGlowRadius,
    required this.lastPointRingRadius,
    required this.snappedAngle,
    required this.isAngleSnapped,
    required this.currentAngleDeg,
    required this.nearestSnapAngleDeg,
    required this.snapDiffDeg,
    required this.angleRefWorld,
    required this.angleTargetWorld,
    required this.snapAngles,
    required this.activePointIndex,
    required this.snapTargetIndex,
    required this.prevWallAngle,
    required this.nextWallAngle,
    required this.prevWallSnapped,
    required this.nextWallSnapped,
    required this.selectedWallIndex,
    required this.snapCandidateShape,
    required this.snapCandidateWall,
    required this.labelHitRects,
    
  });

  Offset worldToScreen(Offset world) => world * scale + panOffset;

  (double, double) _nearestSnapAnglePure(double angleDeg) {
    double nearestAngle = snapAngles.first;
    double minDiff = double.infinity;
    for (final a in snapAngles) {
      double diff = (angleDeg - a).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff < minDiff) {
        minDiff = diff;
        nearestAngle = a;
      }
    }
    return (nearestAngle, minDiff);
  }

  double _worldDist(Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawAxes(canvas, size);

    // Loop through every room we have created
    for (int s = 0; s < shapes.length; s++) {
      final shape = shapes[s];
      final isActive = s == activeIndex;

      if (shape.points.isNotEmpty) {
        _drawSnapGuides(canvas, size, shape, isActive);
        _drawRoom(canvas, shape, isActive, s);
        if (shape.isClosed) {
          _drawRoomObjects(canvas, shape);
          _drawRoomLabel(canvas, shape);
        }
        _drawPoints(canvas, shape, isActive);
        _drawAngleIndicator(canvas, shape, isActive);
        _drawNearestSnapLine(canvas, size, shape, isActive);
        _drawMiddlePointAngles(canvas, shape, isActive);
      }
    }

    if (shapes.isNotEmpty) {
      _drawSnapCursor(canvas, shapes[activeIndex]);
    }
  }

  void _drawWallLengthLabel(Canvas canvas, Offset fromWorld, Offset toWorld,
      {Offset? centroid,
      double? overrideMm,
      bool isSelected = false,
      int wallIndex = -1,
      int shapeIndex = -1}) {
    final fromScreen = worldToScreen(fromWorld);
    final toScreen = worldToScreen(toWorld);

    final worldUnits = _worldDist(fromWorld, toWorld);
    if (worldUnits < 5) return;
    final screenLen = _worldDist(fromScreen, toScreen);
    if (screenLen < 28) return;

    final dx = toScreen.dx - fromScreen.dx;
    final dy = toScreen.dy - fromScreen.dy;
    final wallLen = math.sqrt(dx * dx + dy * dy);
    final ux = dx / wallLen; // unit along wall
    final uy = dy / wallLen;
    double nx = -uy; // unit perpendicular
    double ny = ux;

    // Flip perpendicular so dimension line sits OUTSIDE the room
    if (centroid != null) {
      final cScreen = worldToScreen(centroid);
      final wallMidX = (fromScreen.dx + toScreen.dx) / 2;
      final wallMidY = (fromScreen.dy + toScreen.dy) / 2;
      if ((cScreen.dx - wallMidX) * nx + (cScreen.dy - wallMidY) * ny > 0) {
        nx = -nx;
        ny = -ny;
      }
    }

    const double dimOffset = 26.0; // distance from wall face to dim line
    const double extGap = 3.0; // gap between wall and start of extension line
    const double extOverrun = 5.0; // how far extension line goes past dim line
    const double arrowSize = 6.0; // arrowhead length

    final Color dimColor = overrideMm != null
        ? const Color(0xFF00AA44)
        : isSelected
            ? const Color(0xFFFF8800)
            : const Color(0xFF2255CC);

    // --- Extension lines (dashed) ---
    final dashPaint = Paint()
      ..color = dimColor.withOpacity(0.7)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    void drawDashedLine(Offset a, Offset b) {
      const double dashLen = 4.0, gapLen = 3.0;
      final lx = b.dx - a.dx, ly = b.dy - a.dy;
      final total = math.sqrt(lx * lx + ly * ly);
      final sx = lx / total, sy = ly / total;
      double dist = 0;
      bool drawing = true;
      while (dist < total) {
        final segEnd = math.min(dist + (drawing ? dashLen : gapLen), total);
        if (drawing) {
          canvas.drawLine(
            Offset(a.dx + sx * dist, a.dy + sy * dist),
            Offset(a.dx + sx * segEnd, a.dy + sy * segEnd),
            dashPaint,
          );
        }
        dist = segEnd;
        drawing = !drawing;
      }
    }

    // Extension line from wall endpoint outward past dim line
    drawDashedLine(
      Offset(fromScreen.dx + nx * extGap, fromScreen.dy + ny * extGap),
      Offset(fromScreen.dx + nx * (dimOffset + extOverrun),
          fromScreen.dy + ny * (dimOffset + extOverrun)),
    );
    drawDashedLine(
      Offset(toScreen.dx + nx * extGap, toScreen.dy + ny * extGap),
      Offset(toScreen.dx + nx * (dimOffset + extOverrun),
          toScreen.dy + ny * (dimOffset + extOverrun)),
    );

    // Dim line endpoints
    final dFrom =
        Offset(fromScreen.dx + nx * dimOffset, fromScreen.dy + ny * dimOffset);
    final dTo = Offset(toScreen.dx + nx * dimOffset, toScreen.dy + ny * dimOffset);

    // --- Main dimension line (thin solid) ---
    canvas.drawLine(
        dFrom,
        dTo,
        Paint()
          ..color = dimColor
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke);

    // --- Arrowheads (filled triangles) ---
    void drawArrow(Offset tip, double dirX, double dirY) {
      final perpX = -dirY, perpY = dirX;
      final base = Offset(tip.dx - dirX * arrowSize, tip.dy - dirY * arrowSize);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(base.dx + perpX * arrowSize * 0.35,
            base.dy + perpY * arrowSize * 0.35)
        ..lineTo(base.dx - perpX * arrowSize * 0.35,
            base.dy - perpY * arrowSize * 0.35)
        ..close();
      canvas.drawPath(
          path,
          Paint()
            ..color = dimColor
            ..style = PaintingStyle.fill);
    }

    drawArrow(dFrom, -ux, -uy); // pointing toward dTo
    drawArrow(dTo, ux, uy); // pointing toward dFrom

    // --- Length text ---
    final mid = Offset((dFrom.dx + dTo.dx) / 2, (dFrom.dy + dTo.dy) / 2);
    final text = overrideMm != null
        ? formatLength(overrideMm / mmPerUnit)
        : formatLength(worldUnits);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isSelected ? const Color(0xFFFF8800) : dimColor,
          fontSize: 9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    double angle = math.atan2(uy, ux);
    if (angle > math.pi / 2 || angle < -math.pi / 2) angle += math.pi;
    canvas.rotate(angle);

    final halfW = tp.width / 2 + 4;
    final halfH = tp.height / 2 + 2;
    // White background so text is readable over dim line
    canvas.drawRect(
        Rect.fromLTRB(-halfW, -halfH, halfW, halfH),
        Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.92));
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();

    if (wallIndex >= 0) {
      // Store unrotated screen rect centred on mid for tap detection
      labelHitRects.add((
        rect: Rect.fromCenter(center: mid, width: halfW * 2 + 10, height: 24),
        wallIndex: wallIndex,
        shapeIndex: shapeIndex,
      ));
    }
  }

  void _drawSegmentedWallDimension(
    Canvas canvas,
    SketchShape shape,
    int wallIndex,
    Offset centroid,
  ) {
    final pts = shape.points;
    final n = pts.length;
    final wA = pts[wallIndex];
    final wB = pts[(wallIndex + 1) % n];

    final wallLenWorld = (wB - wA).distance;
    if (wallLenWorld < 5) return;

    // Collect all objects on this wall, sorted by positionAlong
    final objs = shape.roomObjects
        .where((o) => o.wallIndex == wallIndex)
        .toList()
      ..sort((a, b) => a.positionAlong.compareTo(b.positionAlong));

    if (objs.isEmpty) return; // no objects → no segmented dim needed

    // Build segments: [wallStart, obj1Start, obj1End, obj2Start, obj2End, ..., wallEnd]
    // Each segment: (worldStart, worldEnd, label, isObject, isLocked)
    final List<(Offset, Offset, String, bool, bool)> segments = [];

    final wallDir = (wB - wA) / wallLenWorld;

    double prevT = 0.0;
    for (final obj in objs) {
      final objWidthWorld = obj.widthMm / mmPerUnit;
      final halfT = (objWidthWorld / 2) / wallLenWorld;
      final objStartT = (obj.positionAlong - halfT).clamp(0.0, 1.0);
      final objEndT   = (obj.positionAlong + halfT).clamp(0.0, 1.0);

      // Gap before object
      if (objStartT - prevT > 0.001) {
        final gapStart = wA + (wB - wA) * prevT;
        final gapEnd   = wA + (wB - wA) * objStartT;
        final gapMm = (gapEnd - gapStart).distance * mmPerUnit;
        segments.add((gapStart, gapEnd, formatLength((gapEnd - gapStart).distance), false, false));
      }

      // Object itself
      final objStart = wA + (wB - wA) * objStartT;
      final objEnd   = wA + (wB - wA) * objEndT;
      final hasRealMm = obj.widthMm > 0;
      segments.add((objStart, objEnd,
        formatLength(objWidthWorld),
        true, hasRealMm));

      prevT = objEndT;
    }

    // Gap after last object
    if (1.0 - prevT > 0.001) {
      final gapStart = wA + (wB - wA) * prevT;
      segments.add((gapStart, wB,
        formatLength((wB - gapStart).distance), false, false));
    }

    // Total wall dim (drawn further out)
    _drawWallLengthLabel(canvas, wA, wB,
      centroid: centroid,
      overrideMm: shape.wallRealMm[wallIndex],
      isSelected: false,
      wallIndex: -1,   // -1 = don't register hit rect for total
      shapeIndex: -1,
    );

    // Now draw each segment dim closer to the wall
    const double segDimOffset = 14.0; // closer than the 26px total dim

    // Perpendicular direction outward from centroid
    final fromScreen = worldToScreen(wA);
    final toScreen   = worldToScreen(wB);
    final dx = toScreen.dx - fromScreen.dx;
    final dy = toScreen.dy - fromScreen.dy;
    final wallLen = math.sqrt(dx * dx + dy * dy);
    if (wallLen < 1) return;
    double nx = -dy / wallLen;
    double ny =  dx / wallLen;
    final cScreen = worldToScreen(centroid);
    final wallMidX = (fromScreen.dx + toScreen.dx) / 2;
    final wallMidY = (fromScreen.dy + toScreen.dy) / 2;
    if ((cScreen.dx - wallMidX) * nx + (cScreen.dy - wallMidY) * ny > 0) {
      nx = -nx; ny = -ny;
    }

    for (final seg in segments) {
      final (sWorld, eWorld, label, isObj, isLocked) = seg;
      final sScreen = worldToScreen(sWorld);
      final eScreen = worldToScreen(eWorld);
      final segScreenLen = (eScreen - sScreen).distance;
      if (segScreenLen < 8) continue;

      final Color segColor = isObj
          ? const Color(0xFF0066CC)
          : const Color(0xFF2255CC);

      final midScreen = Offset(
        (sScreen.dx + eScreen.dx) / 2 + nx * segDimOffset,
        (sScreen.dy + eScreen.dy) / 2 + ny * segDimOffset,
      );

      // Short tick marks at segment ends
      final tickPaint = Paint()
        ..color = segColor
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(sScreen.dx + nx * (segDimOffset - 4), sScreen.dy + ny * (segDimOffset - 4)),
        Offset(sScreen.dx + nx * (segDimOffset + 4), sScreen.dy + ny * (segDimOffset + 4)),
        tickPaint,
      );
      canvas.drawLine(
        Offset(eScreen.dx + nx * (segDimOffset - 4), eScreen.dy + ny * (segDimOffset - 4)),
        Offset(eScreen.dx + nx * (segDimOffset + 4), eScreen.dy + ny * (segDimOffset + 4)),
        tickPaint,
      );

      // Dim line between ticks
      canvas.drawLine(
        Offset(sScreen.dx + nx * segDimOffset, sScreen.dy + ny * segDimOffset),
        Offset(eScreen.dx + nx * segDimOffset, eScreen.dy + ny * segDimOffset),
        Paint()
          ..color = segColor
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke,
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: segColor,
            fontSize: 8,
            fontFamily: 'monospace',
            fontWeight: isObj ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Arrowheads on the dim line
      void drawSegArrow(Offset tip, double dirX, double dirY) {
        const double arrowSize = 5.0;
        final perpX = -dirY, perpY = dirX;
        final base = Offset(tip.dx - dirX * arrowSize, tip.dy - dirY * arrowSize);
        final path = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(base.dx + perpX * arrowSize * 0.35,
                  base.dy + perpY * arrowSize * 0.35)
          ..lineTo(base.dx - perpX * arrowSize * 0.35,
                  base.dy - perpY * arrowSize * 0.35)
          ..close();
        canvas.drawPath(path,
          Paint()..color = segColor..style = PaintingStyle.fill);
      }

      final ux = (eScreen.dx - sScreen.dx) / segScreenLen;
      final uy = (eScreen.dy - sScreen.dy) / segScreenLen;
      final sOnLine = Offset(
        sScreen.dx + nx * segDimOffset,
        sScreen.dy + ny * segDimOffset,
      );
      final eOnLine = Offset(
        eScreen.dx + nx * segDimOffset,
        eScreen.dy + ny * segDimOffset,
      );
      drawSegArrow(sOnLine,  -ux, -uy); // pointing inward from start
      drawSegArrow(eOnLine,   ux,  uy); // pointing inward from end

      if (segScreenLen > tp.width + 10) {
        canvas.drawRect(
          Rect.fromCenter(
            center: midScreen,
            width: tp.width + 4,
            height: tp.height + 2,
          ),
          Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.92),
        );
        tp.paint(canvas,
          Offset(midScreen.dx - tp.width / 2, midScreen.dy - tp.height / 2));
      }
    }
  }

  void _drawRoomLabel(Canvas canvas, SketchShape shape) {
    if (!shape.isClosed || shape.points.length < 3) return;

    // Compute centroid
    double cx = 0, cy = 0;
    for (final p in shape.points) {
      cx += p.dx;
      cy += p.dy;
    }
    final centroid = Offset(cx / shape.points.length, cy / shape.points.length);
    final centre = worldToScreen(centroid);

    // Compute area (shoelace)
    double area = 0;
    final n = shape.points.length;
    for (int i = 0; i < n; i++) {
      final a = shape.points[i];
      final b = shape.points[(i + 1) % n];
      area += a.dx * b.dy - b.dx * a.dy;
    }
    final areaMm2 = (area.abs() / 2) * mmPerUnit * mmPerUnit;
    final areaM2 = areaMm2 / 1e6;
    final areaStr = '${areaM2.toStringAsFixed(2)} m²';

    final name = shape.label.isEmpty ? 'Room' : shape.label;

    // Draw name
    final nameTp = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Color(0xFF333333),
          fontSize: 13,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Draw area below name
    final areaTp = TextPainter(
      text: TextSpan(
        text: areaStr,
        style: const TextStyle(
          color: Color(0xFF666666),
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final totalH = nameTp.height + 3 + areaTp.height;
    final namePos = Offset(centre.dx - nameTp.width / 2, centre.dy - totalH / 2);
    final areaPos = Offset(centre.dx - areaTp.width / 2, namePos.dy + nameTp.height + 3);

    nameTp.paint(canvas, namePos);
    areaTp.paint(canvas, areaPos);
  }

  void _drawNearestSnapLine(Canvas canvas, Size size, SketchShape shape, bool isActive) {
    if (!isActive || activePointIndex >= 0) return;
    if (shape.isClosed) return;
    if (angleRefWorld == null || currentAngleDeg == null) return;
    if (nearestSnapAngleDeg == null) return;
    final diff = snapDiffDeg ?? 99;
    if (diff > 6) return;

    final refScreen = worldToScreen(angleRefWorld!);
    final opacity = (1.0 - (diff / 20.0)).clamp(0.0, 1.0);
    final rad = nearestSnapAngleDeg! * math.pi / 180;
    final end = Offset(
      refScreen.dx + 2000 * math.cos(rad),
      refScreen.dy - 2000 * math.sin(rad),
    );
    canvas.drawLine(
      refScreen,
      end,
      Paint()
        ..color = isAngleSnapped
            ? const Color(0xFF00CC44).withOpacity(0.5 * opacity)
            : const Color(0xFFFFAA33).withOpacity(0.45 * opacity)
        ..strokeWidth = isAngleSnapped ? 2.0 : 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final labelPos = Offset(
      refScreen.dx + 120 * math.cos(rad),
      refScreen.dy - 120 * math.sin(rad),
    );
    final labelText = '${nearestSnapAngleDeg!.toStringAsFixed(0)}°';
    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          color: isAngleSnapped
              ? const Color(0xFF00CC44).withOpacity(opacity)
              : const Color(0xFFFFAA33).withOpacity(opacity),
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bgRect = Rect.fromCenter(
      center: labelPos,
      width: tp.width + 8,
      height: tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()..color = const Color(0xFFFAFAFA).withOpacity(0.85 * opacity),
    );
    tp.paint(
      canvas,
      Offset(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2),
    );
  }

  void _drawWallAngleLabel(Canvas canvas, Offset fromScreen, Offset toScreen,
      double angleDeg, bool isSnapped) {
    final mid = Offset(
      (fromScreen.dx + toScreen.dx) / 2,
      (fromScreen.dy + toScreen.dy) / 2,
    );
    final wallDx = toScreen.dx - fromScreen.dx;
    final wallDy = toScreen.dy - fromScreen.dy;
    final wallLen = math.sqrt(wallDx * wallDx + wallDy * wallDy);
    Offset labelPos = mid;
    if (wallLen > 0) {
      final nx = -wallDy / wallLen;
      final ny = wallDx / wallLen;
      labelPos = Offset(mid.dx + nx * 20, mid.dy + ny * 20);
    }

    final (nearestA, diff) = _nearestSnapAnglePure(angleDeg);
    final bool snappedDisplay = isSnapped || diff <= 3.0;
    final labelText = snappedDisplay
        ? '${nearestA.toStringAsFixed(0)}°'
        : '${angleDeg.toStringAsFixed(1)}°';
    final labelColor =
        snappedDisplay ? const Color(0xFF00CC44) : const Color(0xFF888888);

    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          color: labelColor,
          fontSize: 12,
          fontFamily: 'monospace',
          fontWeight: snappedDisplay ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromCenter(
      center: labelPos,
      width: tp.width + 10,
      height: tp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFFFAFAFA).withOpacity(0.95),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      Paint()
        ..color =
            snappedDisplay ? const Color(0xFF00CC44) : const Color(0xFFCCCCCC)
        ..strokeWidth = snappedDisplay ? 1.5 : 1.0
        ..style = PaintingStyle.stroke,
    );
    tp.paint(
      canvas,
      Offset(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2),
    );
    if (snappedDisplay) {
      canvas.drawCircle(
        Offset(bgRect.right - 5, bgRect.top + 5),
        3,
        Paint()..color = const Color(0xFF00CC44),
      );
    }
  }

  void _drawMiddlePointAngles(Canvas canvas, SketchShape shape, bool isActive) {
    if (!isActive || activePointIndex < 0) return;
    if (activePointIndex >= shape.points.length) return;
    
    final activePoint = shape.points[activePointIndex];
    final activeScreen = worldToScreen(activePoint);
    final n = shape.points.length;

    Offset? prevPoint;
    Offset? nextPoint;
    if (activePointIndex > 0) {
      prevPoint = shape.points[activePointIndex - 1];
    } else if (shape.isClosed && n > 1) {
      prevPoint = shape.points[n - 1];
    }
    if (activePointIndex < n - 1) {
      nextPoint = shape.points[activePointIndex + 1];
    } else if (shape.isClosed && n > 1) {
      nextPoint = shape.points[0];
    }

    if (prevPoint != null && prevWallAngle != null) {
      final prevScreen = worldToScreen(prevPoint);
      _drawWallAngleLabel(
          canvas, prevScreen, activeScreen, prevWallAngle!, prevWallSnapped);
    }
    if (nextPoint != null && nextWallAngle != null) {
      final nextScreen = worldToScreen(nextPoint);
      _drawWallAngleLabel(
          canvas, activeScreen, nextScreen, nextWallAngle!, nextWallSnapped);
    }
  }

  void _drawSnapGuides(Canvas canvas, Size size, SketchShape shape, bool isActive) {
    if (!isActive) return;

    if (activePointIndex >= 0 && shape.points.isNotEmpty) {
      final refScreen = worldToScreen(shape.points[activePointIndex]);
      final faintPaint = Paint()
        ..color = const Color(0xFFFFAA00).withOpacity(0.07)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      for (final a in snapAngles) {
        final rad = a * math.pi / 180;
        final end = Offset(
          refScreen.dx + 2000 * math.cos(rad),
          refScreen.dy - 2000 * math.sin(rad),
        );
        canvas.drawLine(refScreen, end, faintPaint);
      }
      return;
    }
    if (shape.isClosed) return;
    if (angleRefWorld == null || angleTargetWorld == null) return;
    if (currentAngleDeg == null) return;

    final refScreen = worldToScreen(angleRefWorld!);
    final faintPaint = Paint()
      ..color = const Color(0xFF00AAFF).withOpacity(0.06)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (final a in snapAngles) {
      final rad = a * math.pi / 180;
      final end = Offset(
        refScreen.dx + 2000 * math.cos(rad),
        refScreen.dy - 2000 * math.sin(rad),
      );
      canvas.drawLine(refScreen, end, faintPaint);
    }
    if (snappedAngle != null) {
      final rad = snappedAngle! * math.pi / 180;
      final end = Offset(
        refScreen.dx + 2000 * math.cos(rad),
        refScreen.dy - 2000 * math.sin(rad),
      );
      canvas.drawLine(
        refScreen,
        end,
        Paint()
          ..color = isAngleSnapped
              ? const Color(0xFF00CC44).withOpacity(0.35)
              : const Color(0xFF00AAFF).withOpacity(0.20)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawAngleIndicator(Canvas canvas, SketchShape shape, bool isActive) {
    if (!isActive || activePointIndex >= 0) return;
    if (angleRefWorld == null || angleTargetWorld == null) return;
    if (currentAngleDeg == null) return;

    final refScreen = worldToScreen(angleRefWorld!);
    final targetScreen = worldToScreen(angleTargetWorld!);
    final dx = targetScreen.dx - refScreen.dx;
    final dy = targetScreen.dy - refScreen.dy;
    final screenDist = math.sqrt(dx * dx + dy * dy);
    if (screenDist < 5) return;

    final screenAngleRad = math.atan2(dy, dx);
    const double arcRadius = 22.0;
    canvas.drawArc(
      Rect.fromCircle(center: refScreen, radius: arcRadius),
      0,
      screenAngleRad,
      false,
      Paint()
        ..color =
            isAngleSnapped ? const Color(0xFF00CC44) : const Color(0xFF888888)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      Offset(refScreen.dx + arcRadius - 4, refScreen.dy),
      Offset(refScreen.dx + arcRadius + 6, refScreen.dy),
      Paint()
        ..color = const Color(0xFF888888).withOpacity(0.5)
        ..strokeWidth = 1.0,
    );

    final labelAngleRad = screenAngleRad / 2;
    const double labelRadius = 38.0;
    final labelPos = Offset(
      refScreen.dx + labelRadius * math.cos(labelAngleRad),
      refScreen.dy + labelRadius * math.sin(labelAngleRad),
    );
    final labelText = isAngleSnapped
        ? '${snappedAngle!.toStringAsFixed(0)}°'
        : '${currentAngleDeg!.toStringAsFixed(1)}°';
    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: TextStyle(
          color: isAngleSnapped
              ? const Color(0xFF00CC44)
              : const Color(0xFF666666),
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: isAngleSnapped ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromCenter(
      center: labelPos,
      width: tp.width + 8,
      height: tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()..color = const Color(0xFFFAFAFA).withOpacity(0.92),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
      Paint()
        ..color = isAngleSnapped
            ? const Color(0xFF00CC44).withOpacity(0.4)
            : const Color(0xFFCCCCCC)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );
    tp.paint(
      canvas,
      Offset(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2),
    );
    if (isAngleSnapped) {
      canvas.drawCircle(
        refScreen,
        arcRadius + 4,
        Paint()
          ..color = const Color(0xFF00CC44).withOpacity(0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final minorPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 0.5;
    final majorPaint = Paint()
      ..color = const Color(0xFFBBBBBB)
      ..strokeWidth = 1.0;
    final double minorSpacing = minorGrid * scale;
    final double majorSpacing = majorGrid * scale;
    if (minorSpacing > 4) _drawGridLines(canvas, size, minorSpacing, minorPaint);
    if (majorSpacing > 4) _drawGridLines(canvas, size, majorSpacing, majorPaint);
    if (minorSpacing > 12) {
      final dotPaint = Paint()
        ..color = const Color(0xFFAAAAAA)
        ..style = PaintingStyle.fill;
      final double startX = panOffset.dx % minorSpacing;
      final double startY = panOffset.dy % minorSpacing;
      for (double x = startX; x <= size.width; x += minorSpacing) {
        for (double y = startY; y <= size.height; y += minorSpacing) {
          canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
        }
      }
    }
  }

  void _drawGridLines(Canvas canvas, Size size, double spacing, Paint paint) {
    final double startX = panOffset.dx % spacing;
    for (double x = startX; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    final double startY = panOffset.dy % spacing;
    for (double y = startY; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawAxes(Canvas canvas, Size size) {
    final axisPaint = Paint()
      ..color = const Color(0xFFAAAAAA)
      ..strokeWidth = 1.5;
    final o = panOffset;
    if (o.dy >= 0 && o.dy <= size.height) {
      canvas.drawLine(Offset(0, o.dy), Offset(size.width, o.dy), axisPaint);
    }
    if (o.dx >= 0 && o.dx <= size.width) {
      canvas.drawLine(Offset(o.dx, 0), Offset(o.dx, size.height), axisPaint);
    }
  }

  void _drawSnapCursor(Canvas canvas, SketchShape activeShape) {
    if (cursorWorld == null || activeShape.isClosed) return;
    if (activePointIndex >= 0) return;
    final s = worldToScreen(cursorWorld!);
    final p = Paint()
      ..color =
          isAngleSnapped ? const Color(0xFF00CC44) : const Color(0xFF00AAFF)
      ..strokeWidth = isAngleSnapped ? 1.5 : 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(s.dx - 8, s.dy), Offset(s.dx + 8, s.dy), p);
    canvas.drawLine(Offset(s.dx, s.dy - 8), Offset(s.dx, s.dy + 8), p);
    if (isAngleSnapped) {
      final path = Path()
        ..moveTo(s.dx, s.dy - 10)
        ..lineTo(s.dx + 10, s.dy)
        ..lineTo(s.dx, s.dy + 10)
        ..lineTo(s.dx - 10, s.dy)
        ..close();
      canvas.drawPath(path, p);
    } else {
      canvas.drawRect(Rect.fromCenter(center: s, width: 10, height: 10), p);
    }
  }

  void _drawRoom(Canvas canvas, SketchShape shape, bool isActive, int s) {
    final rubberPaint = Paint()
      ..color = isAngleSnapped ? const Color(0xFF00CC44) : const Color(0xFF00AAFF)
      ..strokeWidth = isAngleSnapped ? 2.0 : 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = const Color(0xFF00AAFF).withOpacity(isActive ? 0.07 : 0.03)
      ..style = PaintingStyle.fill;

    final wallFillPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;

    final selectedWallFillPaint = Paint()
      ..color = const Color(0xFFFF8800)
      ..style = PaintingStyle.fill;

    final snapWallFillPaint = Paint()
      ..color = const Color(0xFF00CC44)
      ..style = PaintingStyle.fill;

    final List<Offset> sp =
        shape.points.map<Offset>((p) => worldToScreen(p)).toList();

    Offset? centroid;
    if (shape.points.length >= 2) {
      double cx = 0, cy = 0;
      final allPts = shape.isClosed
          ? shape.points
          : [...shape.points, if (cursorWorld != null && isActive) cursorWorld!];
      for (final p in allPts) {
        cx += p.dx;
        cy += p.dy;
      }
      centroid = Offset(cx / allPts.length, cy / allPts.length);
    }

    // 1. Draw room fill first (so walls paint over it)
    if (shape.isClosed && sp.length >= 3) {
      final path = Path()..addPolygon(sp, true);
      canvas.drawPath(path, fillPaint);
    }

    // Draw active shape outline highlight
    if (isActive && shape.isClosed && sp.length >= 3) {
      final path = Path()..addPolygon(sp, true);
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFF00AAFF).withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0);
    }

    if (shape.isClosed && shape.points.length >= 2) {
      final int n = shape.points.length;

      // Build offset lines for each wall
      // Each entry: (outerA, outerB, innerA, innerB)
      List<(Offset, Offset, Offset, Offset)> wallLines = [];
      for (int i = 0; i < n; i++) {
        final a = shape.points[i];
        final b = shape.points[(i + 1) % n];
        final corners = thickWallRect(a, b, wallThickness);
        // thickWallRect returns [outerA, outerB, innerB, innerA]
        wallLines.add((corners[0], corners[1], corners[3], corners[2]));
      }

      // Compute mitre corners
      List<Offset> outerCorners = [];
      List<Offset> innerCorners = [];
      for (int i = 0; i < n; i++) {
        final next = (i + 1) % n;
        final (oA, oB, iA, iB) = wallLines[i];
        final (oC, oD, iC, iD) = wallLines[next];

        final oDir1 = oB - oA;
        final oDir2 = oD - oC;
        final iDir1 = iB - iA;
        final iDir2 = iD - iC;

        final outerMitre = lineIntersect(oA, oDir1, oC, oDir2) ?? oB;
        final innerMitre = lineIntersect(iA, iDir1, iC, iDir2) ?? iB;

        outerCorners.add(worldToScreen(outerMitre));
        innerCorners.add(worldToScreen(innerMitre));
      }

      // Draw single filled wall path
      final wallPath = Path();
      wallPath.moveTo(outerCorners[0].dx, outerCorners[0].dy);
      for (int i = 1; i < n; i++) {
        wallPath.lineTo(outerCorners[i].dx, outerCorners[i].dy);
      }
      wallPath.close();

      // Cut out interior
      wallPath.moveTo(innerCorners[0].dx, innerCorners[0].dy);
      for (int i = 1; i < n; i++) {
        wallPath.lineTo(innerCorners[i].dx, innerCorners[i].dy);
      }
      wallPath.close();

      wallPath.fillType = PathFillType.evenOdd;
      canvas.drawPath(
        wallPath,
        Paint()
          ..color = const Color(0xFF1A1A1A)
          ..style = PaintingStyle.fill,
      );

      // Draw ONLY the shared sub-segment thin — the rest of the wall stays full thickness
      for (final sw in shape.sharedWalls) {
        if (sw.myWallIndex >= n) continue;
        final Offset wallA = shape.points[sw.myWallIndex];
        final Offset wallB = shape.points[(sw.myWallIndex + 1) % n];
        // Recompute from t-values — always follows the room's current position
        final Offset a = wallA + (wallB - wallA) * sw.tStart;
        final Offset b = wallA + (wallB - wallA) * sw.tEnd;
        if ((a - b).distance < 2.0) continue;

        final corners = thickWallRect(a, b, wallThickness * 0.28);
        if (corners.isEmpty) continue;
        final sc = corners.map((c) => worldToScreen(c)).toList();
        final thinPath = Path()
          ..moveTo(sc[0].dx, sc[0].dy)
          ..lineTo(sc[1].dx, sc[1].dy)
          ..lineTo(sc[2].dx, sc[2].dy)
          ..lineTo(sc[3].dx, sc[3].dy)
          ..close();
        // First erase that strip (paint over with background) then draw thin
        canvas.drawPath(
            thinPath,
            Paint()
              ..color = const Color(0xFFF5F5F0) // match your floor/background color
              ..style = PaintingStyle.fill);
        canvas.drawPath(
            thinPath,
            Paint()
              ..color = const Color(0xFF1A1A1A)
              ..style = PaintingStyle.fill);
      }

      // Highlight snap candidate wall during drag (green glow)
      if (s == snapCandidateShape && snapCandidateWall >= 0) {
        final int i = snapCandidateWall;
        if (i < shape.points.length) {
          final aS = worldToScreen(shape.points[i]);
          final bS = worldToScreen(shape.points[(i + 1) % shape.points.length]);
          canvas.drawLine(
              aS,
              bS,
              Paint()
                ..color = const Color(0xFF00CC44)
                ..strokeWidth = 4.0
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round);
        }
      }

      // Draw dimension labels
      if (isActive) {
        for (int i = 0; i < n; i++) {
          final a = shape.points[i];
          final b = shape.points[(i + 1) % n];
          // Only draw simple label if no objects on this wall
          final hasObjects = shape.roomObjects.any((o) => o.wallIndex == i);
          if (!hasObjects) {
            _drawWallLengthLabel(canvas, a, b,
                centroid: centroid,
                overrideMm: shape.wallRealMm[i],
                isSelected: i == selectedWallIndex,
                wallIndex: i,
                shapeIndex: s);
          } else {
            // Draw segmented dims: gap + door/window + gap + total
            _drawSegmentedWallDimension(canvas, shape, i, centroid!);
          }
        }
      }
    } else {
      // Shape not closed yet — draw individual thick walls while drawing
      for (int i = 0; i < shape.points.length - 1; i++) {
        final corners = thickWallRect(shape.points[i], shape.points[i + 1], wallThickness);
        if (corners.isEmpty) continue;
        final sc = corners.map((c) => worldToScreen(c)).toList();
        final path = Path()
          ..moveTo(sc[0].dx, sc[0].dy)
          ..lineTo(sc[1].dx, sc[1].dy)
          ..lineTo(sc[2].dx, sc[2].dy)
          ..lineTo(sc[3].dx, sc[3].dy)
          ..close();
        canvas.drawPath(path, wallFillPaint);
        if (isActive) {
          _drawWallLengthLabel(canvas, shape.points[i], shape.points[i + 1],
              centroid: centroid,
              overrideMm: shape.wallRealMm[i],
              isSelected: i == selectedWallIndex,
              wallIndex: i,
              shapeIndex: s);
        }
      }
    } 

    // 5. Rubber band line while drawing
    if (isActive &&
        !shape.isClosed &&
        cursorWorld != null &&
        sp.isNotEmpty &&
        activePointIndex < 0) {
      canvas.drawLine(sp.last, worldToScreen(cursorWorld!), rubberPaint);
      _drawWallLengthLabel(canvas, shape.points.last, cursorWorld!,
          centroid: centroid);
      if (shape.points.length >= 3) {
        final distToFirst = (cursorWorld! - shape.points.first).distance;
        if (distToFirst < snapRadiusWorld) {
          canvas.drawCircle(
            sp.first,
            14,
            Paint()
              ..color = const Color(0xFF00CC44)
              ..strokeWidth = 2.0
              ..style = PaintingStyle.stroke,
          );
        }
      }
    }
  }

  void _drawPoints(Canvas canvas, SketchShape shape, bool isActive) {
    for (int i = 0; i < shape.points.length; i++) {
      final s = worldToScreen(shape.points[i]);
      final isFirst = i == 0;
      final isLast = i == shape.points.length - 1 && !shape.isClosed;
      final isThisActivePoint = isActive && i == activePointIndex;
      final isSnapTarget = isActive && i == snapTargetIndex;

      if (isSnapTarget) {
        canvas.drawCircle(
            s,
            20,
            Paint()
              ..color = const Color(0xFF00CC44).withOpacity(0.25)
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            s,
            20,
            Paint()
              ..color = const Color(0xFF00CC44)
              ..strokeWidth = 2.0
              ..style = PaintingStyle.stroke);
      }

      if (isThisActivePoint) {
        canvas.drawCircle(
            s,
            lastPointGlowRadius,
            Paint()
              ..color = const Color(0xFFFF6600).withOpacity(0.10)
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            s,
            lastPointRingRadius,
            Paint()
              ..color = const Color(0xFFFF6600).withOpacity(0.30)
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            s,
            lastPointRingRadius,
            Paint()
              ..color = const Color(0xFFFF6600)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke);
      } else if (isActive && isLast) {
        canvas.drawCircle(
            s,
            lastPointGlowRadius,
            Paint()
              ..color = isAngleSnapped
                  ? const Color(0xFF00CC44).withOpacity(0.10)
                  : const Color(0xFFFF6600).withOpacity(0.08)
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            s,
            lastPointRingRadius,
            Paint()
              ..color = isAngleSnapped
                  ? const Color(0xFF00CC44).withOpacity(0.25)
                  : isDraggingLastPoint
                      ? const Color(0xFFFF6600).withOpacity(0.35)
                      : const Color(0xFFFF6600).withOpacity(0.15)
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            s,
            lastPointRingRadius,
            Paint()
              ..color = isAngleSnapped
                  ? const Color(0xFF00CC44)
                  : const Color(0xFFFF6600)
              ..strokeWidth = 1.5
              ..style = PaintingStyle.stroke);
      }

      Color dotColor;
      Color borderColor;
      final double dotRadius = (isActive && (isLast || isThisActivePoint)) ? 7 : (isFirst ? 6 : 4);

      if (isThisActivePoint) {
        dotColor = const Color(0xFFFF6600);
        borderColor = const Color(0xFFFF6600);
      } else if (isActive && isLast) {
        dotColor =
            isAngleSnapped ? const Color(0xFF00CC44) : const Color(0xFFFF6600);
        borderColor =
            isAngleSnapped ? const Color(0xFF00CC44) : const Color(0xFFFF6600);
      } else if (isFirst) {
        dotColor = const Color(0xFF00CC44);
        borderColor = const Color(0xFF00CC44);
      } else {
        dotColor = const Color(0xFFFFFFFF);
        borderColor = const Color(0xFF1A1A1A);
      }

      canvas.drawCircle(s, dotRadius,
          Paint()
            ..color = dotColor
            ..style = PaintingStyle.fill);
      canvas.drawCircle(s, dotRadius,
          Paint()
            ..color = borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0);
    }
  }

  @override
  @override
  bool shouldRepaint(SketchPainter oldDelegate) => true;

  void _drawRoomObjects(Canvas canvas, SketchShape shape) {
    final pts = shape.points;
    final isClosed = shape.isClosed;
    final wallCount = isClosed ? pts.length : pts.length - 1;

    for (final obj in shape.roomObjects) {
      if (obj.wallIndex >= wallCount) continue;

      // Wall segment in world coords
      final wA = pts[obj.wallIndex];
      final wB = pts[(obj.wallIndex + 1) % pts.length];
      final wallLenWorld = (wB - wA).distance;
      if (wallLenWorld < 1) continue;

      // Convert door width from mm -> world units
      final objWidthWorld = obj.widthMm / mmPerUnit;
      // Half-width in screen pixels
      final scaleRatio =
          (worldToScreen(wB) - worldToScreen(wA)).distance / wallLenWorld;
      final halfWScreen = (objWidthWorld / 2) * scaleRatio;

      final centre = objectCentreWorld(
        obj: obj,
        points: pts,
        wallCount: wallCount,
      );
      final centreScreen = worldToScreen(centre);

      final dir = wallDirectionScreen(
        wallIndex: obj.wallIndex,
        points: pts,
        worldToScreen: worldToScreen,
      );
      final perp = obj.swingFlipped
          ? Offset(dir.dy, -dir.dx) // flipped side
          : Offset(-dir.dy, dir.dx); // default inward

      const bool isSelected = false;
      if (obj.isDoor) {
        _drawDoor(canvas, centreScreen, dir, perp, halfWScreen, isSelected);
      } else {
        _drawWindow(canvas, centreScreen, dir, halfWScreen, isSelected);
      }
    }
  }

  void _drawDoor(Canvas canvas, Offset centre, Offset dir, Offset perp,
      double halfW, bool isSelected) {
    final Color color = isSelected
        ? const Color(0xFFFF8800)
        : const Color(0xFF1A1A1A);

    final Offset hingePoint = Offset(
      centre.dx - dir.dx * halfW,
      centre.dy - dir.dy * halfW,
    );
    final Offset tipPoint = Offset(
      centre.dx + dir.dx * halfW,
      centre.dy + dir.dy * halfW,
    );

    // 1. Colour-less gap - fill with canvas background colour
    canvas.drawLine(
      hingePoint,
      tipPoint,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = wallThickness * 1.1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt,
    );

    final double radius = halfW * 2;

    final double leafAngle = math.atan2(
      tipPoint.dy - hingePoint.dy,
      tipPoint.dx - hingePoint.dx,
    );
    final double perpAngle = math.atan2(perp.dy, perp.dx);
    final double cwEnd  = leafAngle - math.pi / 2;
    final double ccwEnd = leafAngle + math.pi / 2;
    final double cwDiff  = ((cwEnd  - perpAngle + math.pi) % (2 * math.pi) - math.pi).abs();
    final double ccwDiff = ((ccwEnd - perpAngle + math.pi) % (2 * math.pi) - math.pi).abs();
    final double sweepAngle = cwDiff < ccwDiff ? -math.pi / 2 : math.pi / 2;

    final Offset leafTip = Offset(
      hingePoint.dx + perp.dx * radius,
      hingePoint.dy + perp.dy * radius,
    );

    final paint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 2.0 : 1.5
      ..style = PaintingStyle.stroke;

    // 2. Door leaf line: hinge -> inward
    canvas.drawLine(hingePoint, leafTip, paint);

    // 3. Door opening line: hinge -> tip along wall
    canvas.drawLine(hingePoint, tipPoint, paint);

    // 4. Arc: quarter circle sweep
    canvas.drawArc(
      Rect.fromCenter(
        center: hingePoint,
        width:  radius * 2,
        height: radius * 2,
      ),
      leafAngle + sweepAngle, 
      -sweepAngle,            
      false,
      Paint()
        ..color = color
        ..strokeWidth = isSelected ? 1.5 : 1.0
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawWindow(Canvas canvas, Offset centre, Offset dir,
      double halfW, bool isSelected) {
    final Color color = isSelected
        ? const Color(0xFFFF8800)
        : const Color(0xFF0099CC);

    // Gap in wall
    canvas.drawLine(
      Offset(centre.dx - dir.dx * halfW, centre.dy - dir.dy * halfW),
      Offset(centre.dx + dir.dx * halfW, centre.dy + dir.dy * halfW),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = wallThickness * 1.1
        ..style = PaintingStyle.stroke,
    );

    // Three lines (classic window symbol)
    for (final offset in [-0.5, 0.0, 0.5]) {
      canvas.drawLine(
        Offset(centre.dx - dir.dx * halfW + dir.dy * offset * 6,
              centre.dy - dir.dy * halfW - dir.dx * offset * 6),
        Offset(centre.dx + dir.dx * halfW + dir.dy * offset * 6,
              centre.dy + dir.dy * halfW - dir.dx * offset * 6),
        Paint()
          ..color = color
          ..strokeWidth = offset == 0 ? 2.0 : 1.0
          ..style = PaintingStyle.stroke,
      );
    }
  }
}