import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'sketch_constants.dart';
import 'sketch_shape.dart';

class SketchPainter extends CustomPainter {
  final Offset panOffset;
  final double scale;
  final double minorGrid;
  final double majorGrid;
  final List<Offset> points;
  final bool isClosed;
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
  final Map<int, double> wallRealMm;
  /// All rooms that are NOT the active one — drawn greyed-out behind the active room.
  final List<SketchShape> inactiveShapes;

  const SketchPainter({
    required this.panOffset,
    required this.scale,
    required this.minorGrid,
    required this.majorGrid,
    required this.points,
    required this.isClosed,
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
    required this.wallRealMm,
    this.inactiveShapes = const [],
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
    // Draw inactive rooms first (behind everything)
    for (final shape in inactiveShapes) {
      _drawInactiveShape(canvas, shape);
    }
    if (points.isNotEmpty) {
      _drawSnapGuides(canvas, size);
      _drawRoom(canvas);
      _drawPoints(canvas);
      _drawAngleIndicator(canvas);
      _drawNearestSnapLine(canvas, size);
      _drawMiddlePointAngles(canvas);
    }
    _drawSnapCursor(canvas);
  }

  // ── Draw an inactive (completed or in-progress) room greyed out ───────────
  void _drawInactiveShape(Canvas canvas, SketchShape shape) {
    if (shape.points.length < 2) return;

    final pts = shape.points;
    final sp = pts.map<Offset>(worldToScreen).toList();
    final int n = pts.length;
    final bool closed = shape.isClosed;

    // Fill
    if (closed && n >= 3) {
      final path = Path()..addPolygon(sp, true);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF4488CC).withOpacity(0.10)
          ..style = PaintingStyle.fill,
      );
    }

    // Walls — solid dark, same weight as active room
    final wallPaint = Paint()
      ..color = const Color(0xFF444444).withOpacity(0.75)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final int wallCount = closed ? n : n - 1;
    for (int i = 0; i < wallCount; i++) {
      canvas.drawLine(sp[i], sp[(i + 1) % n], wallPaint);
    }

    // Corner dots
    for (int i = 0; i < n; i++) {
      canvas.drawCircle(
        sp[i],
        4,
        Paint()
          ..color = const Color(0xFF555555).withOpacity(0.85)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        sp[i],
        4,
        Paint()
          ..color = const Color(0xFF333333).withOpacity(0.85)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    // Room label if present
    if (shape.label != null && closed) {
      double cx = 0, cy = 0;
      for (final p in pts) { cx += p.dx; cy += p.dy; }
      final centroidScreen = worldToScreen(Offset(cx / n, cy / n));
      final tp = TextPainter(
        text: TextSpan(
          text: shape.label,
          style: const TextStyle(
            color: Color(0xFFAAAAAA),
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(centroidScreen.dx - tp.width / 2,
              centroidScreen.dy - tp.height / 2));
    }
  }

  void _drawWallLengthLabel(Canvas canvas, Offset fromWorld, Offset toWorld,
      {Offset? centroid, double? overrideMm, bool isSelected = false}) {
    final fromScreen = worldToScreen(fromWorld);
    final toScreen = worldToScreen(toWorld);

    final worldUnits = _worldDist(fromWorld, toWorld);
    if (worldUnits < 5) return;

    final screenLen = _worldDist(fromScreen, toScreen);
    if (screenLen < 28) return;

    final dx = toScreen.dx - fromScreen.dx;
    final dy = toScreen.dy - fromScreen.dy;
    final wallLen = math.sqrt(dx * dx + dy * dy);
    final ux = dx / wallLen;
    final uy = dy / wallLen;
    double nx = -uy;
    double ny = ux;

    final wallMidX = (fromScreen.dx + toScreen.dx) / 2;
    final wallMidY = (fromScreen.dy + toScreen.dy) / 2;

    if (centroid != null) {
      final cScreen = worldToScreen(centroid);
      final toCx = cScreen.dx - wallMidX;
      final toCy = cScreen.dy - wallMidY;
      if (toCx * nx + toCy * ny > 0) {
        nx = -nx;
        ny = -ny;
      }
    }

    const double dimOffset = 22.0;
    const double extOverrun = 5.0;
    const double tickLen = 7.0;

    final dFrom = Offset(
        fromScreen.dx + nx * dimOffset, fromScreen.dy + ny * dimOffset);
    final dTo =
        Offset(toScreen.dx + nx * dimOffset, toScreen.dy + ny * dimOffset);

    final Color dimColor = overrideMm != null
        ? const Color(0xFF00AA44)
        : isSelected
            ? const Color(0xFFFF8800)
            : const Color(0xFF0055AA);

    final dimPaint = Paint()
      ..color = dimColor
      ..strokeWidth = isSelected ? 1.4 : 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final extPaint = Paint()
      ..color = dimColor.withOpacity(0.5)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(fromScreen.dx + nx * 3, fromScreen.dy + ny * 3),
      Offset(dFrom.dx + nx * extOverrun, dFrom.dy + ny * extOverrun),
      extPaint,
    );
    canvas.drawLine(
      Offset(toScreen.dx + nx * 3, toScreen.dy + ny * 3),
      Offset(dTo.dx + nx * extOverrun, dTo.dy + ny * extOverrun),
      extPaint,
    );

    canvas.drawLine(dFrom, dTo, dimPaint);

    void drawTick(Offset centre) {
      final tx = (ux + nx) / math.sqrt(2);
      final ty = (uy + ny) / math.sqrt(2);
      canvas.drawLine(
        Offset(centre.dx - tx * tickLen / 2, centre.dy - ty * tickLen / 2),
        Offset(centre.dx + tx * tickLen / 2, centre.dy + ty * tickLen / 2),
        Paint()
          ..color = dimColor
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    drawTick(dFrom);
    drawTick(dTo);

    final mid = Offset((dFrom.dx + dTo.dx) / 2, (dFrom.dy + dTo.dy) / 2);

    final text = formatLength(worldUnits);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF003399),
          fontSize: 10,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(mid.dx, mid.dy);

    double angle = math.atan2(uy, ux);
    if (angle > math.pi / 2 || angle < -math.pi / 2) angle += math.pi;
    canvas.rotate(angle);

    final halfW = tp.width / 2 + 3;
    final halfH = tp.height / 2 + 1;
    canvas.drawRect(
      Rect.fromLTRB(-halfW, -halfH, halfW, halfH),
      Paint()..color = const Color(0xFFFFFFFF).withOpacity(0.93),
    );

    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2 - 1));
    canvas.restore();
  }

  void _drawNearestSnapLine(Canvas canvas, Size size) {
    if (activePointIndex >= 0) return;
    if (isClosed) return;
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

  void _drawMiddlePointAngles(Canvas canvas) {
    if (activePointIndex < 0) return;
    if (activePointIndex >= points.length) return;
    final activePoint = points[activePointIndex];
    final activeScreen = worldToScreen(activePoint);
    final n = points.length;

    Offset? prevPoint;
    Offset? nextPoint;
    if (activePointIndex > 0) {
      prevPoint = points[activePointIndex - 1];
    } else if (isClosed && n > 1) {
      prevPoint = points[n - 1];
    }
    if (activePointIndex < n - 1) {
      nextPoint = points[activePointIndex + 1];
    } else if (isClosed && n > 1) {
      nextPoint = points[0];
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

  void _drawSnapGuides(Canvas canvas, Size size) {
    if (activePointIndex >= 0) {
      final refScreen = worldToScreen(points[activePointIndex]);
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
    if (isClosed) return;
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

  void _drawAngleIndicator(Canvas canvas) {
    if (activePointIndex >= 0) return;
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

  void _drawSnapCursor(Canvas canvas) {
    if (cursorWorld == null || isClosed) return;
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

  void _drawRoom(Canvas canvas) {
    final wallPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final snapWallPaint = Paint()
      ..color = const Color(0xFF00CC44)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final rubberPaint = Paint()
      ..color =
          isAngleSnapped ? const Color(0xFF00CC44) : const Color(0xFF00AAFF)
      ..strokeWidth = isAngleSnapped ? 2.0 : 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = const Color(0xFF00AAFF).withOpacity(0.07)
      ..style = PaintingStyle.fill;

    final List<Offset> sp =
        points.map<Offset>((p) => worldToScreen(p)).toList();

    Offset? centroid;
    if (points.length >= 2) {
      double cx = 0, cy = 0;
      final allPts = isClosed
          ? points
          : [...points, if (cursorWorld != null) cursorWorld!];
      for (final p in allPts) {
        cx += p.dx;
        cy += p.dy;
      }
      centroid = Offset(cx / allPts.length, cy / allPts.length);
    }

    if (isClosed && sp.length >= 3) {
      final path = Path()..addPolygon(sp, true);
      canvas.drawPath(path, fillPaint);
    }

    final selectedWallPaint = Paint()
      ..color = const Color(0xFFFF8800)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < sp.length - 1; i++) {
      final isPrevWall = activePointIndex >= 0 && i == activePointIndex - 1;
      final isNextWall = activePointIndex >= 0 && i == activePointIndex;
      final isPrevWallWrapped = activePointIndex == 0 && i == sp.length - 1;
      final isNextWallWrapped =
          activePointIndex == sp.length - 1 && i == 0;

      Paint paint = wallPaint;
      if (i == selectedWallIndex) {
        paint = selectedWallPaint;
      } else if ((isPrevWall || isPrevWallWrapped) && prevWallSnapped) {
        paint = snapWallPaint;
      } else if ((isNextWall || isNextWallWrapped) && nextWallSnapped) {
        paint = snapWallPaint;
      }
      canvas.drawLine(sp[i], sp[i + 1], paint);
      _drawWallLengthLabel(canvas, points[i], points[i + 1],
          centroid: centroid,
          overrideMm: wallRealMm[i],
          isSelected: i == selectedWallIndex);
    }

    if (isClosed && sp.length >= 2) {
      final int closingWallIdx = sp.length - 1;
      Paint paint = wallPaint;
      if (closingWallIdx == selectedWallIndex) {
        paint = selectedWallPaint;
      } else if (activePointIndex == 0 && prevWallSnapped) {
        paint = snapWallPaint;
      } else if (activePointIndex == sp.length - 1 && nextWallSnapped) {
        paint = snapWallPaint;
      }
      canvas.drawLine(sp.last, sp.first, paint);
      _drawWallLengthLabel(canvas, points.last, points.first,
          centroid: centroid,
          overrideMm: wallRealMm[closingWallIdx],
          isSelected: closingWallIdx == selectedWallIndex);
    }

    if (!isClosed &&
        cursorWorld != null &&
        sp.isNotEmpty &&
        activePointIndex < 0) {
      canvas.drawLine(sp.last, worldToScreen(cursorWorld!), rubberPaint);
      _drawWallLengthLabel(canvas, points.last, cursorWorld!,
          centroid: centroid);
      if (points.length >= 3) {
        final distToFirst = (cursorWorld! - points.first).distance;
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

  void _drawPoints(Canvas canvas) {
    for (int i = 0; i < points.length; i++) {
      final s = worldToScreen(points[i]);
      final isFirst = i == 0;
      final isLast = i == points.length - 1 && !isClosed;
      final isActive = i == activePointIndex;
      final isSnapTarget = i == snapTargetIndex;

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

      if (isActive) {
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
      } else if (isLast) {
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
      final double dotRadius = (isLast || isActive) ? 7 : (isFirst ? 6 : 4);

      if (isActive) {
        dotColor = const Color(0xFFFF6600);
        borderColor = const Color(0xFFFF6600);
      } else if (isLast) {
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
  bool shouldRepaint(SketchPainter old) => true;
}