import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../ble/ble_manager.dart';
import '../ble/ble_packet.dart';

// ─────────────────────────────────────────────
// Scale: 1 grid unit (20px) = 100mm = 0.1m
// So 1 world unit = 5mm
// ─────────────────────────────────────────────
const double _mmPerUnit = 5.0;
const double _unitsPerMeter = 200.0;

String _formatLength(double worldUnits) {
  final double mm = worldUnits * _mmPerUnit;
  if (mm >= 1000) {
    final double m = mm / 1000.0;
    return '${m.toStringAsFixed(2)} m';
  } else {
    return '${mm.toStringAsFixed(0)} mm';
  }
}

class SketchScreen extends StatefulWidget {
  final BleManager? bleManager;
  const SketchScreen({super.key, this.bleManager});


  @override
  State<SketchScreen> createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen> {
  Offset _panOffset = Offset.zero;
  double _scale = 1.0;
  double _scaleStart = 1.0;
  List<Offset> _points = [];
  bool _isClosed = false;
  Offset? _cursorWorld;
  bool _isDraggingLastPoint = false;
  bool _dragOccurred = false;
  bool _isMultiTouch = false;
  int _activePointIndex = -1;
  bool _isDraggingActivePoint = false;
  int? _snapTargetIndex;
  final List<List<Offset>> _undoStack = [];
  final List<List<Offset>> _redoStack = [];
  final List<bool> _undoClosedStack = [];
  final List<bool> _redoClosedStack = [];
  TapDownDetails? _pendingTap;
  bool _tapCancelled = false;
  double? _snappedAngle;
  bool _isAngleSnapped = false;
  double? _currentAngleDeg;
  double? _prevWallAngle;
  double? _nextWallAngle;
  bool _prevWallSnapped = false;
  bool _nextWallSnapped = false;
  Offset? _panStartPosition;
  bool _panConfirmed = false;
  double? _nearestSnapAngleDeg;
  double? _snapDiffDeg;

  int _selectedWallIndex = -1;
  final Map<int, double> _wallRealMm = {};
  // ── BLE ──────────────────────────────────────────
  double? _pendingBleMm;
  bool _waitingForBle = false;

  static const double _panThreshold = 6.0;
  static const double _minorGrid = 20.0;
  static const double _majorGrid = 100.0;
  static const double _snapRadiusWorld = 15.0;
  static const double _minPointDistance = 8.0;
  static const double _lastPointGlowRadius = 28.0;
  static const double _lastPointRingRadius = 14.0;
  static const double _pointSnapRadiusScreen = 30.0;
  static const double _pointSelectRadiusScreen = 22.0;
  static const List<double> _snapAngles = [
    0, 30, 45, 60, 75, 90, 105, 120, 135, 150,
    180, 210, 225, 240, 255, 270, 285, 300, 315, 330,
  ];
  static const double _snapThresholdDeg = 3.0;
  static const double _minAngleDistance = 10.0;

  @override
  void initState() {
    super.initState();
    widget.bleManager?.packetStream.listen((BlePacket packet) {
      // Only apply if user has selected a wall and is waiting
      if (_waitingForBle && _selectedWallIndex >= 0) {
        setState(() {
          _waitingForBle = false;
          _pendingBleMm = packet.distanceMm;
        });
        _applyRealMeasurement(_selectedWallIndex, packet.distanceMm);
      }
    });
  }

  @override
  void dispose() {
    widget.bleManager?.disconnect();
    super.dispose();
  }


  Offset worldToScreen(Offset world) => world * _scale + _panOffset;
  Offset screenToWorld(Offset screen) => (screen - _panOffset) / _scale;

  Offset snapToGrid(Offset worldPos) {
    final double snappedX = (worldPos.dx / _minorGrid).round() * _minorGrid;
    final double snappedY = (worldPos.dy / _minorGrid).round() * _minorGrid;
    return Offset(snappedX, snappedY);
  }

  bool _isNearLastPoint(Offset screenPos) {
    if (_points.isEmpty || _isClosed) return false;
    if (_activePointIndex >= 0) return false;
    final lastScreen = worldToScreen(_points.last);
    return (screenPos - lastScreen).distance < _lastPointGlowRadius;
  }

  int _findNearPoint(Offset screenPos,
      {int excludeIndex = -1, double radius = _pointSelectRadiusScreen}) {
    for (int i = 0; i < _points.length; i++) {
      if (i == excludeIndex) continue;
      final s = worldToScreen(_points[i]);
      if ((screenPos - s).distance < radius) return i;
    }
    return -1;
  }

  void _saveUndo() {
    _undoStack.add(List<Offset>.of(_points));
    _undoClosedStack.add(_isClosed);
    _redoStack.clear();
    _redoClosedStack.clear();
  }

  double _computeAngleDeg(Offset from, Offset to) {
    final dx = to.dx - from.dx;
    final dy = -(to.dy - from.dy);
    double angleDeg = math.atan2(dy, dx) * 180 / math.pi;
    if (angleDeg < 0) angleDeg += 360;
    return angleDeg;
  }

  (double, double) _nearestSnapAngle(double angleDeg) {
    double nearestAngle = _snapAngles.first;
    double minDiff = double.infinity;
    for (final a in _snapAngles) {
      double diff = (angleDeg - a).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff < minDiff) {
        minDiff = diff;
        nearestAngle = a;
      }
    }
    return (nearestAngle, minDiff);
  }

  Offset _computeAngle(Offset fromWorld, Offset toWorld) {
    final dx = toWorld.dx - fromWorld.dx;
    final dy = toWorld.dy - fromWorld.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < _minAngleDistance) {
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
      return toWorld;
    }
    final angleDeg = _computeAngleDeg(fromWorld, toWorld);
    _currentAngleDeg = angleDeg;
    final (nearestAngle, minDiff) = _nearestSnapAngle(angleDeg);
    _nearestSnapAngleDeg = nearestAngle;
    _snapDiffDeg = minDiff;
    _snappedAngle = nearestAngle;
    if (minDiff <= _snapThresholdDeg) {
      _isAngleSnapped = true;
      final rad = nearestAngle * math.pi / 180;
      return Offset(
        fromWorld.dx + distance * math.cos(rad),
        fromWorld.dy - distance * math.sin(rad),
      );
    }
    _isAngleSnapped = false;
    return toWorld;
  }

  Offset? _rayIntersection(
      Offset originA, double angleDegA, Offset originB, double angleDegB) {
    final radA = angleDegA * math.pi / 180;
    final radB = angleDegB * math.pi / 180;
    final dAx = math.cos(radA);
    final dAy = -math.sin(radA);
    final dBx = math.cos(radB);
    final dBy = -math.sin(radB);
    final det = dAx * (-dBy) - dAy * (-dBx);
    if (det.abs() < 1e-10) return null;
    final dx = originB.dx - originA.dx;
    final dy = originB.dy - originA.dy;
    final t = (dx * (-dBy) - dy * (-dBx)) / det;
    return Offset(originA.dx + t * dAx, originA.dy + t * dAy);
  }

  (double?, bool) _trySnap(double angleDeg) {
    final (nearest, diff) = _nearestSnapAngle(angleDeg);
    if (diff <= _snapThresholdDeg) return (nearest, true);
    return (nearest, false);
  }

  Offset _updateMiddlePointAngles(int idx, Offset rawPos) {
    _prevWallAngle = null;
    _nextWallAngle = null;
    _prevWallSnapped = false;
    _nextWallSnapped = false;

    Offset? prevPoint;
    Offset? nextPoint;
    if (idx > 0) {
      prevPoint = _points[idx - 1];
    } else if (_isClosed && _points.length > 1) {
      prevPoint = _points[_points.length - 1];
    }
    if (idx < _points.length - 1) {
      nextPoint = _points[idx + 1];
    } else if (_isClosed && _points.length > 1) {
      nextPoint = _points[0];
    }

    double? prevSnapAngle;
    Offset? prevSnappedPos;
    if (prevPoint != null) {
      final dx = rawPos.dx - prevPoint.dx;
      final dy = rawPos.dy - prevPoint.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist >= _minAngleDistance) {
        final rawAngle = _computeAngleDeg(prevPoint, rawPos);
        _prevWallAngle = rawAngle;
        final (nearest, snapped) = _trySnap(rawAngle);
        if (snapped) {
          _prevWallSnapped = true;
          prevSnapAngle = nearest;
          _prevWallAngle = nearest;
          final rad = nearest! * math.pi / 180;
          prevSnappedPos = Offset(
            prevPoint.dx + dist * math.cos(rad),
            prevPoint.dy - dist * math.sin(rad),
          );
        }
      }
    }

    double? nextSnapAngle;
    Offset? nextSnappedPos;
    if (nextPoint != null) {
      final dx = nextPoint.dx - rawPos.dx;
      final dy = nextPoint.dy - rawPos.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist >= _minAngleDistance) {
        final rawAngle = _computeAngleDeg(rawPos, nextPoint);
        _nextWallAngle = rawAngle;
        final (nearest, snapped) = _trySnap(rawAngle);
        if (snapped) {
          _nextWallSnapped = true;
          nextSnapAngle = nearest;
          _nextWallAngle = nearest;
          final reverseAngle = (nearest! + 180) % 360;
          final rad = reverseAngle * math.pi / 180;
          nextSnappedPos = Offset(
            nextPoint.dx + dist * math.cos(rad),
            nextPoint.dy - dist * math.sin(rad),
          );
        }
      }
    }

    if (_prevWallSnapped &&
        _nextWallSnapped &&
        prevPoint != null &&
        nextPoint != null &&
        prevSnapAngle != null &&
        nextSnapAngle != null) {
      final reverseNextAngle = (nextSnapAngle + 180) % 360;
      final intersection = _rayIntersection(
          prevPoint, prevSnapAngle, nextPoint, reverseNextAngle);
      if (intersection != null) {
        _prevWallAngle = prevSnapAngle;
        _nextWallAngle = nextSnapAngle;
        return intersection;
      }
      return prevSnappedPos ?? rawPos;
    }

    if (_prevWallSnapped) return prevSnappedPos ?? rawPos;
    if (_nextWallSnapped) return nextSnappedPos ?? rawPos;
    return rawPos;
  }

  void _showAngleEditor() {
    if (_points.isEmpty || _currentAngleDeg == null) return;
    if (_points.length < 2) return;
    final controller =
        TextEditingController(text: _currentAngleDeg!.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Edit Wall Angle',
            style: TextStyle(
                color: Color(0xFFCCCCCC),
                fontFamily: 'monospace',
                fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Adjust angle of last wall (counterclockwise from east)',
                style: TextStyle(
                    color: Color(0xFF888888),
                    fontFamily: 'monospace',
                    fontSize: 11)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  color: Color(0xFF00CC44),
                  fontFamily: 'monospace',
                  fontSize: 20),
              decoration: const InputDecoration(
                suffixText: '°',
                suffixStyle: TextStyle(color: Color(0xFF00CC44), fontSize: 20),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF555555))),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00CC44), width: 2)),
                filled: true,
                fillColor: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [0, 30, 45, 60, 75, 90, 135, 180, 270].map((a) {
                return GestureDetector(
                  onTap: () => controller.text = a.toString(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3A),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF555555)),
                    ),
                    child: Text('$a°',
                        style: const TextStyle(
                            color: Color(0xFFAAAAAA),
                            fontFamily: 'monospace',
                            fontSize: 11)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL',
                style: TextStyle(
                    color: Color(0xFF888888), fontFamily: 'monospace')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00CC44),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && _points.length >= 2) {
                final refPoint = _points[_points.length - 2];
                final lastPoint = _points.last;
                final dx = lastPoint.dx - refPoint.dx;
                final dy = lastPoint.dy - refPoint.dy;
                final wallLength = math.sqrt(dx * dx + dy * dy);
                final rad = val * math.pi / 180;
                final updatedLastPoint = Offset(
                  refPoint.dx + wallLength * math.cos(rad),
                  refPoint.dy - wallLength * math.sin(rad),
                );
                Navigator.pop(ctx);
                _saveUndo();
                setState(() {
                  _points[_points.length - 1] = updatedLastPoint;
                  _cursorWorld = null;
                  _currentAngleDeg = val % 360;
                  _snappedAngle = val % 360;
                  _isAngleSnapped = false;
                });
              } else {
                Navigator.pop(ctx);
              }
            },
            child:
                const Text('APPLY', style: TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _dragOccurred = false;
    _panStartPosition = event.localPosition;
    _panConfirmed = false;
    _snapTargetIndex = null;
    _prevWallAngle = null;
    _nextWallAngle = null;

    if (_isClosed) {
      final idx = _findNearPoint(event.localPosition,
          radius: _pointSelectRadiusScreen);
      if (idx >= 0) {
        setState(() {
          _activePointIndex = idx;
          _isDraggingActivePoint = true;
        });
      } else {
        setState(() {
          _activePointIndex = -1;
          _isDraggingActivePoint = false;
        });
      }
      return;
    }

    if (_activePointIndex >= 0) {
      final activeScreen = worldToScreen(_points[_activePointIndex]);
      final distToActive = (event.localPosition - activeScreen).distance;
      if (distToActive < _lastPointGlowRadius) {
        _isDraggingActivePoint = true;
        return;
      } else {
        final idx = _findNearPoint(event.localPosition,
            excludeIndex: _activePointIndex,
            radius: _pointSelectRadiusScreen);
        if (idx >= 0) {
          setState(() {
            _activePointIndex = idx;
            _isDraggingActivePoint = true;
          });
          return;
        }
        setState(() {
          _activePointIndex = -1;
          _isDraggingActivePoint = false;
        });
      }
    }

    if (_points.isNotEmpty && _isNearLastPoint(event.localPosition)) {
      _isDraggingLastPoint = true;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isClosed) {
      if (_isDraggingActivePoint && _activePointIndex >= 0) {
        _dragOccurred = true;
        final rawWorld = screenToWorld(event.localPosition);
        final snapIdx = _findNearPoint(event.localPosition,
            excludeIndex: _activePointIndex,
            radius: _pointSnapRadiusScreen);
        final Offset finalPos;
        if (snapIdx >= 0) {
          finalPos = _points[snapIdx];
          _prevWallAngle = null;
          _nextWallAngle = null;
          _prevWallSnapped = false;
          _nextWallSnapped = false;
        } else {
          finalPos = _updateMiddlePointAngles(_activePointIndex, rawWorld);
        }
        setState(() {
          _snapTargetIndex = snapIdx >= 0 ? snapIdx : null;
          _points[_activePointIndex] = finalPos;
        });
      }
      return;
    }

    if (_isDraggingActivePoint && _activePointIndex >= 0) {
      _dragOccurred = true;
      final rawWorld = screenToWorld(event.localPosition);
      final snapIdx = _findNearPoint(event.localPosition,
          excludeIndex: _activePointIndex,
          radius: _pointSnapRadiusScreen);
      final Offset finalPos;
      if (snapIdx >= 0) {
        finalPos = _points[snapIdx];
        _prevWallAngle = null;
        _nextWallAngle = null;
        _prevWallSnapped = false;
        _nextWallSnapped = false;
      } else {
        finalPos = _updateMiddlePointAngles(_activePointIndex, rawWorld);
      }
      setState(() {
        _snapTargetIndex = snapIdx >= 0 ? snapIdx : null;
        _points[_activePointIndex] = finalPos;
        _cursorWorld = null;
      });
      return;
    }

    if (_isDraggingLastPoint && _points.isNotEmpty) {
      _dragOccurred = true;
      final rawWorld = screenToWorld(event.localPosition);
      final snapIdx = _findNearPoint(event.localPosition,
          excludeIndex: _points.length - 1,
          radius: _pointSnapRadiusScreen);
      Offset newPos;
      if (snapIdx >= 0) {
        newPos = _points[snapIdx];
        _currentAngleDeg = null;
        _nearestSnapAngleDeg = null;
        _snapDiffDeg = null;
        _snappedAngle = null;
        _isAngleSnapped = false;
      } else if (_points.length >= 2) {
        newPos = _computeAngle(_points[_points.length - 2], rawWorld);
      } else {
        newPos = rawWorld;
        _currentAngleDeg = null;
        _nearestSnapAngleDeg = null;
        _snapDiffDeg = null;
        _snappedAngle = null;
        _isAngleSnapped = false;
      }
      setState(() {
        _snapTargetIndex = snapIdx >= 0 ? snapIdx : null;
        _points[_points.length - 1] = newPos;
        _cursorWorld = null;
      });
      return;
    }

    if (_points.isNotEmpty && _activePointIndex < 0) {
      final rawWorld = snapToGrid(screenToWorld(event.localPosition));
      final snapped = _computeAngle(_points.last, rawWorld);
      setState(() {
        _cursorWorld = snapped;
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isDraggingLastPoint &&
        _snapTargetIndex == 0 &&
        _points.length >= 3) {
      _saveUndo();
      setState(() {
        _isClosed = true;
        _cursorWorld = null;
        _currentAngleDeg = null;
        _nearestSnapAngleDeg = null;
        _snapDiffDeg = null;
        _snappedAngle = null;
        _isAngleSnapped = false;
        _snapTargetIndex = null;
        _prevWallAngle = null;
        _nextWallAngle = null;
      });
    } else {
      if (_isDraggingActivePoint && _dragOccurred) {
        _saveUndo();
      }
      setState(() {
        _snapTargetIndex = null;
        _prevWallAngle = null;
        _nextWallAngle = null;
      });
    }
    _isDraggingLastPoint = false;
    _isDraggingActivePoint = false;
    _panStartPosition = null;
    _panConfirmed = false;
  }

  void _onPointerHover(PointerHoverEvent event) {
    if (_isClosed || _points.isEmpty) return;
    if (_activePointIndex >= 0) return;
    final rawWorld = snapToGrid(screenToWorld(event.localPosition));
    final snapped = _computeAngle(_points.last, rawWorld);
    setState(() {
      _cursorWorld = snapped;
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      setState(() {
        final zoomFactor = event.scrollDelta.dy > 0 ? 0.92 : 1.08;
        final focalWorld = screenToWorld(event.position);
        _scale = (_scale * zoomFactor).clamp(0.05, 50.0);
        _panOffset = event.position - focalWorld * _scale;
      });
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _scaleStart = _scale;
    _panConfirmed = false;
    if (details.pointerCount >= 2) {
      _isMultiTouch = true;
      _tapCancelled = true;
      _pendingTap = null;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_isDraggingLastPoint || _isDraggingActivePoint) return;
    if (details.pointerCount >= 2) {
      _isMultiTouch = true;
      _tapCancelled = true;
      _pendingTap = null;
      _panConfirmed = true;
      setState(() {
        final focalWorld = screenToWorld(details.focalPoint);
        _scale = (_scaleStart * details.scale).clamp(0.05, 50.0);
        _panOffset = details.focalPoint - focalWorld * _scale;
      });
      return;
    }
    if (!_panConfirmed && _panStartPosition != null) {
      final totalMoved = (details.focalPoint - _panStartPosition!).distance;
      if (totalMoved > _panThreshold) _panConfirmed = true;
    }
    if (_panConfirmed) {
      setState(() {
        _panOffset += details.focalPointDelta;
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _panConfirmed = false;
    Future.delayed(const Duration(milliseconds: 150), () {
      _isMultiTouch = false;
      _tapCancelled = false;
    });
  }

  void _onTapDown(TapDownDetails details) {
    if (_isMultiTouch) return;
    if (_dragOccurred) {
      _dragOccurred = false;
      return;
    }
    if (_isClosed) {
      final wallIdx = _findNearWall(details.localPosition);
      if (wallIdx >= 0) {
        setState(() {
          _activePointIndex = -1;
          _selectedWallIndex = wallIdx;
        });
        _showWallEditDialog(wallIdx);
        return;
      }
      final idx = _findNearPoint(details.localPosition,
          radius: _pointSelectRadiusScreen);
      setState(() {
        _activePointIndex = idx;
        _selectedWallIndex = -1;
      });
      return;
    }

    if (_points.length >= 3) {
      final firstScreen = worldToScreen(_points.first);
      final distToFirst = (details.localPosition - firstScreen).distance;
      if (distToFirst < _pointSelectRadiusScreen) {
        _saveUndo();
        setState(() {
          _isClosed = true;
          _cursorWorld = null;
          _currentAngleDeg = null;
          _nearestSnapAngleDeg = null;
          _snapDiffDeg = null;
          _snappedAngle = null;
          _isAngleSnapped = false;
          _activePointIndex = -1;
        });
        return;
      }
    }

    final existingIdx = _findNearPoint(
      details.localPosition,
      excludeIndex: _points.isEmpty ? -1 : _points.length - 1,
      radius: _pointSelectRadiusScreen,
    );
    if (existingIdx >= 0 && _points.length > 1) {
      setState(() {
        _activePointIndex = existingIdx;
      });
      return;
    }

    if (_activePointIndex >= 0) {
      final activeScreen = worldToScreen(_points[_activePointIndex]);
      final distToActive = (details.localPosition - activeScreen).distance;
      if (distToActive > _pointSelectRadiusScreen) {
        setState(() => _activePointIndex = -1);
      }
      return;
    }

    if (_points.isNotEmpty && _isNearLastPoint(details.localPosition)) return;

    _pendingTap = details;
    _tapCancelled = false;
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_tapCancelled) return;
      if (_pendingTap == null) return;
      _commitTap(_pendingTap!);
      _pendingTap = null;
    });
  }

  void _commitTap(TapDownDetails details) {
    if (_isClosed) return;
    if (_isMultiTouch) return;
    final rawWorld = snapToGrid(screenToWorld(details.localPosition));
    final worldPos =
        _points.isNotEmpty ? _computeAngle(_points.last, rawWorld) : rawWorld;
    if (_points.isNotEmpty) {
      final distToLast = (worldPos - _points.last).distance;
      if (distToLast < _minPointDistance) return;
    }
    _saveUndo();
    setState(() {
      _points.add(worldPos);
      _cursorWorld = null;
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List<Offset>.of(_points));
    _redoClosedStack.add(_isClosed);
    setState(() {
      _points = _undoStack.removeLast();
      _isClosed = _undoClosedStack.removeLast();
      _activePointIndex = -1;
      _cursorWorld = null;
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List<Offset>.of(_points));
    _undoClosedStack.add(_isClosed);
    setState(() {
      _points = _redoStack.removeLast();
      _isClosed = _redoClosedStack.removeLast();
      _activePointIndex = -1;
      _cursorWorld = null;
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
    });
  }

  void _clear() {
    _saveUndo();
    setState(() {
      _points.clear();
      _isClosed = false;
      _cursorWorld = null;
      _isDraggingLastPoint = false;
      _dragOccurred = false;
      _isMultiTouch = false;
      _pendingTap = null;
      _tapCancelled = false;
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
      _activePointIndex = -1;
      _isDraggingActivePoint = false;
      _snapTargetIndex = null;
      _prevWallAngle = null;
      _nextWallAngle = null;
    });
  }

  String _angleLabel() {
    if (_currentAngleDeg == null) return '';
    if (_isAngleSnapped && _snappedAngle != null) {
      return '${_snappedAngle!.toStringAsFixed(0)}°';
    }
    return '${_currentAngleDeg!.toStringAsFixed(1)}°';
  }

  double _totalPerimeter() {
    if (_points.length < 2) return 0;
    double total = 0;
    for (int i = 0; i < _points.length - 1; i++) {
      final dx = _points[i + 1].dx - _points[i].dx;
      final dy = _points[i + 1].dy - _points[i].dy;
      total += math.sqrt(dx * dx + dy * dy);
    }
    if (_isClosed) {
      final dx = _points.first.dx - _points.last.dx;
      final dy = _points.first.dy - _points.last.dy;
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
  }

  double _totalArea() {
    if (!_isClosed || _points.length < 3) return 0;
    double area = 0;
    final n = _points.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += _points[i].dx * _points[j].dy;
      area -= _points[j].dx * _points[i].dy;
    }
    return area.abs() / 2.0;
  }

  String _formatArea(double worldUnitsSquared) {
    final double mm2 = worldUnitsSquared * _mmPerUnit * _mmPerUnit;
    final double m2 = mm2 / 1000000.0;
    if (m2 >= 0.01) {
      return '${m2.toStringAsFixed(2)} m²';
    }
    return '${mm2.toStringAsFixed(0)} mm²';
  }

  int _findNearWall(Offset screenPos) {
    if (_points.length < 2) return -1;
    const double hitThresh = 18.0;
    final List<Offset> sp = _points.map(worldToScreen).toList();
    final int n = sp.length;
    final int wallCount = _isClosed ? n : n - 1;
    for (int i = 0; i < wallCount; i++) {
      final Offset a = sp[i];
      final Offset b = sp[(i + 1) % n];
      final double dist = _pointToSegmentDist(screenPos, a, b);
      if (dist < hitThresh) return i;
    }
    return -1;
  }

  double _pointToSegmentDist(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    final clamped = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + clamped * dx, a.dy + clamped * dy);
    return (p - proj).distance;
  }

  double _wallLengthWorld(int wallIndex) {
    final int n = _points.length;
    final Offset a = _points[wallIndex];
    final Offset b = _points[(wallIndex + 1) % n];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _applyRealMeasurement(int wallIndex, double realMm) {
    final double pixelLen = _wallLengthWorld(wallIndex);
    if (pixelLen < 1e-6) return;
    final double realUnits = realMm / _mmPerUnit;
    final double ratio = realUnits / pixelLen;
    if (ratio <= 0) return;

    _saveUndo();

    final Offset anchor = _points[wallIndex];
    final List<Offset> newPoints = _points.map((pt) {
      final dx = pt.dx - anchor.dx;
      final dy = pt.dy - anchor.dy;
      return Offset(anchor.dx + dx * ratio, anchor.dy + dy * ratio);
    }).toList();

    setState(() {
      _points = newPoints;
      _wallRealMm[wallIndex] = realMm;
      _selectedWallIndex = -1;
      _activePointIndex = -1;
    });
  }

  void _showWallEditDialog(int wallIndex) {
    // If BLE connected — offer a choice instead of jumping straight to BLE
    if (widget.bleManager != null && widget.bleManager!.isConnected) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E2A3A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Wall ${wallIndex + 1}  —  ${_formatLength(_wallLengthWorld(wallIndex))} drawn',
                style: const TextStyle(
                  color: Color(0xFF778899),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              // ── Use Device button ──────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth),
                  label: const Text(
                    'Use Device  —  press BOOT button on ESP32',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00AAFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedWallIndex = wallIndex;
                      _waitingForBle = true;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              // ── Enter manually button ──────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text(
                    'Enter manually',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFAABBCC),
                    side: const BorderSide(color: Color(0xFF334466)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showManualEntryDialog(wallIndex);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      return;
    }

    // No BLE — go straight to manual entry
    _showManualEntryDialog(wallIndex);
  }

  void _showManualEntryDialog(int wallIndex) {
    final String existingReal = _wallRealMm.containsKey(wallIndex)
        ? _wallRealMm[wallIndex]!.toStringAsFixed(0)
        : '';

    final controller = TextEditingController(text: existingReal);

    final int n = _points.length;
    final bool isClosing = _isClosed && wallIndex == n - 1;
    final String wallLabel =
        isClosing ? 'Wall ${wallIndex + 1} (closing)' : 'Wall ${wallIndex + 1}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A3A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.straighten, color: Color(0xFF00AAFF), size: 20),
            const SizedBox(width: 8),
            Text(wallLabel,
                style: const TextStyle(
                    color: Color(0xFFCCDDEE),
                    fontFamily: 'monospace',
                    fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1A27),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334455)),
              ),
              child: Row(
                children: [
                  const Text('Drawn length: ',
                      style: TextStyle(
                          color: Color(0xFF778899),
                          fontFamily: 'monospace',
                          fontSize: 11)),
                  Text(
                    _formatLength(_wallLengthWorld(wallIndex)),
                    style: const TextStyle(
                        color: Color(0xFFAABBCC),
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text('Enter real measurement:',
                style: TextStyle(
                    color: Color(0xFF778899),
                    fontFamily: 'monospace',
                    fontSize: 11)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        color: Color(0xFF00DDFF),
                        fontFamily: 'monospace',
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(color: Color(0xFF334455)),
                      enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF334466))),
                      focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Color(0xFF00AAFF), width: 2)),
                      filled: true,
                      fillColor: Color(0xFF0D1A27),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _UnitSelector(
                  onUnitChanged: (unit) {
                    final v = double.tryParse(controller.text);
                    if (v == null) return;
                    if (unit == 'm') {
                      controller.text = (v / 1000).toStringAsFixed(3);
                    } else {
                      controller.text = (v * 1000).toStringAsFixed(0);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                '1000 mm',
                '1500 mm',
                '2000 mm',
                '2400 mm',
                '3000 mm',
                '4000 mm',
                '5000 mm',
              ].map((label) {
                final mm = double.parse(label.split(' ')[0]);
                return GestureDetector(
                  onTap: () => controller.text = mm.toStringAsFixed(0),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1A27),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF334466)),
                    ),
                    child: Text(label,
                        style: const TextStyle(
                            color: Color(0xFF5588AA),
                            fontFamily: 'monospace',
                            fontSize: 10)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _selectedWallIndex = -1);
              Navigator.pop(ctx);
            },
            child: const Text('CANCEL',
                style: TextStyle(
                    color: Color(0xFF556677), fontFamily: 'monospace')),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: const Text('APPLY & RESCALE',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00AAFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) {
                Navigator.pop(ctx);
                _applyRealMeasurement(wallIndex, val);
              }
            },
          ),
        ],
      ),
    );
  }

  // ── PDF Export — paste inside _SketchScreenState ───────────────────────────────────

  Future<void> _exportPdf() async {
    if (_points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draw a room first'),
          backgroundColor: Color(0xFF333333),
        ),
      );
      return;
    }

    final pdf = pw.Document();

    // ── Bounding box of the world points ──────────────────────────────────
    double minX = _points.map((p) => p.dx).reduce(math.min);
    double maxX = _points.map((p) => p.dx).reduce(math.max);
    double minY = _points.map((p) => p.dy).reduce(math.min);
    double maxY = _points.map((p) => p.dy).reduce(math.max);

    // ── Fit drawing into a square canvas (in PDF points) ──────────────────
    const double canvasSize   = 440.0;   // pts — drawing square
    const double canvasMargin = 30.0;    // padding inside the square
    const double drawArea     = canvasSize - canvasMargin * 2;

    final double worldW = (maxX - minX).clamp(1.0, double.infinity);
    final double worldH = (maxY - minY).clamp(1.0, double.infinity);
    final double pdfScale = drawArea / math.max(worldW, worldH);

    // World → PDF canvas coords  (PDF origin = bottom-left, Y flipped)
    PdfPoint toPdf(Offset world) {
      return PdfPoint(
        canvasMargin + (world.dx - minX) * pdfScale,
        canvasSize - canvasMargin - (world.dy - minY) * pdfScale,
      );
    }

    // ── Wall count ─────────────────────────────────────────────────────────
    final int n = _points.length;
    final int wallCount = _isClosed ? n : n - 1;

    // ── Prepare wall data for the table ────────────────────────────────────
    final List<Map<String, String>> wallRows = List.generate(wallCount, (i) {
      final Offset a = _points[i];
      final Offset b = _points[(i + 1) % n];
      final double wl = (b - a).distance;
      return {
        'wall': 'Wall ${i + 1}',
        'drawn': _formatLength(wl),
        'real': _wallRealMm.containsKey(i)
            ? '${_wallRealMm[i]!.toStringAsFixed(0)} mm'
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

              // ── Header ─────────────────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Room Floor Plan',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blueGrey800,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'SmartMeasure Pro  •  ${_formattedDate()}',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                  // Scale note
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blueGrey50,
                      borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4)),
                      border: pw.Border.all(color: PdfColors.blueGrey200),
                    ),
                    child: pw.Text(
                      '1 grid div = 100 mm',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.blueGrey600),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 4),
              pw.Divider(color: PdfColors.blueGrey200),
              pw.SizedBox(height: 12),

              // ── Drawing canvas ──────────────────────────────────────────
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
                      // ── Light grid ──────────────────────────────────
                      g.setStrokeColor(PdfColors.grey200);
                      g.setLineWidth(0.4);
                      const double gridStep = 20.0; // pts between grid lines
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

                      // ── Filled room polygon (if closed) ─────────────
                      if (_isClosed && n >= 3) {
                        g.setFillColor(const PdfColor(0.91, 0.96, 1.0));  // ← NEW line
                        final first = toPdf(_points[0]);
                        g.moveTo(first.x, first.y);
                        for (int i = 1; i < n; i++) {
                          final p = toPdf(_points[i]);
                          g.lineTo(p.x, p.y);
                        }
                        g.closePath();
                        g.fillPath();
                      }

                      // ── Walls ────────────────────────────────────────
                      g.setStrokeColor(PdfColors.blueGrey800);
                      g.setLineWidth(1.8);
                      for (int i = 0; i < wallCount; i++) {
                        final PdfPoint a = toPdf(_points[i]);
                        final PdfPoint b = toPdf(_points[(i + 1) % n]);
                        g.moveTo(a.x, a.y);
                        g.lineTo(b.x, b.y);
                        g.strokePath();
                      }

                      // ── Corner points ────────────────────────────────
                      for (int i = 0; i < n; i++) {
                        final PdfPoint p = toPdf(_points[i]);
                        final bool isFirst = i == 0;
                        g.setFillColor(
                            isFirst ? PdfColors.green700 : PdfColors.blue700);
                        g.drawEllipse(p.x, p.y, 3.5, 3.5);
                        g.fillPath();
                      }
                    },
                  ),
                ),
              ),

              pw.SizedBox(height: 16),

              // ── Summary row ─────────────────────────────────────────────
              if (_isClosed)
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
                    mainAxisAlignment:
                        pw.MainAxisAlignment.spaceAround,
                    children: [
                      _pdfSummaryItem('POINTS', '${_points.length}'),
                      _pdfDivider(),
                      _pdfSummaryItem(
                          'PERIMETER', _formatLength(_totalPerimeter())),
                      _pdfDivider(),
                      _pdfSummaryItem('AREA', _formatArea(_totalArea())),
                    ],
                  ),
                ),

              pw.SizedBox(height: 14),

              // ── Wall measurements table ──────────────────────────────────
              pw.Text(
                'Wall Measurements',
                style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey700),
              ),
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
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                        color: PdfColors.blueGrey100),
                    children: ['Wall', 'Drawn Length', 'Real Measurement']
                        .map(
                          (h) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            child: pw.Text(
                              h,
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blueGrey700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  // Data rows
                  ...wallRows.map((row) => pw.TableRow(
                        children: [
                          row['wall']!,
                          row['drawn']!,
                          row['real']!,
                        ]
                            .map(
                              (c) => pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                child: pw.Text(
                                  c,
                                  style: const pw.TextStyle(
                                      fontSize: 9,
                                      color: PdfColors.blueGrey800),
                                ),
                              ),
                            )
                            .toList(),
                      )),
                ],
              ),

              pw.Spacer(),

              // ── Footer ──────────────────────────────────────────────────
              pw.Divider(color: PdfColors.blueGrey200),
              pw.Text(
                'SmartMeasure Pro — generated floor plan  •  1 world unit = ${_mmPerUnit.toStringAsFixed(0)} mm',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey500),
              ),
            ],
          );
        },
      ),
    );

    // ── Show print/share preview ──────────────────────────────────────────
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'room_floor_plan',
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _formattedDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}  '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  pw.Widget _pdfSummaryItem(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(label,
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColors.blueGrey500)),
        pw.SizedBox(height: 2),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey800)),
      ],
    );
  }

  pw.Widget _pdfDivider() {
    return pw.Container(
        width: 1, height: 30, color: PdfColors.blueGrey200);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    Offset? angleRefWorld;
    Offset? angleTargetWorld;
    if (_isDraggingLastPoint && _points.length >= 2) {
      angleRefWorld = _points[_points.length - 2];
      angleTargetWorld = _points.last;
    } else if (!_isDraggingLastPoint &&
        _activePointIndex < 0 &&
        _points.isNotEmpty &&
        _cursorWorld != null) {
      angleRefWorld = _points.last;
      angleTargetWorld = _cursorWorld;
    }

    double? liveDistance;
    if (!_isClosed && _points.isNotEmpty && _activePointIndex < 0) {
      final target = _cursorWorld;
      if (target != null) {
        final dx = target.dx - _points.last.dx;
        final dy = target.dy - _points.last.dy;
        liveDistance = math.sqrt(dx * dx + dy * dy);
      }
    }

    // Show angle strip only while actively drawing (not closed, angle is live)
    final bool showAngleStrip = _currentAngleDeg != null &&
        _activePointIndex < 0 &&
        _points.length >= 2 &&
        !_isClosed;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Stack(
        children: [
          // ── Canvas ───────────────────────────────────────────────────
          Listener(
            onPointerSignal: _onPointerSignal,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerHover: _onPointerHover,
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapDown: _onTapDown,
              child: CustomPaint(
                painter: _SketchPainter(
                  panOffset: _panOffset,
                  scale: _scale,
                  minorGrid: _minorGrid,
                  majorGrid: _majorGrid,
                  points: _points,
                  isClosed: _isClosed,
                  cursorWorld: _cursorWorld,
                  snapRadiusWorld: _snapRadiusWorld,
                  isDraggingLastPoint: _isDraggingLastPoint,
                  lastPointGlowRadius: _lastPointGlowRadius,
                  lastPointRingRadius: _lastPointRingRadius,
                  snappedAngle: _snappedAngle,
                  isAngleSnapped: _isAngleSnapped,
                  currentAngleDeg: _currentAngleDeg,
                  nearestSnapAngleDeg: _nearestSnapAngleDeg,
                  snapDiffDeg: _snapDiffDeg,
                  angleRefWorld: angleRefWorld,
                  angleTargetWorld: angleTargetWorld,
                  snapAngles: _snapAngles,
                  activePointIndex: _activePointIndex,
                  snapTargetIndex: _snapTargetIndex,
                  prevWallAngle: _prevWallAngle,
                  nextWallAngle: _nextWallAngle,
                  prevWallSnapped: _prevWallSnapped,
                  nextWallSnapped: _nextWallSnapped,
                  selectedWallIndex: _selectedWallIndex,
                  wallRealMm: _wallRealMm,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),

          // ── Top toolbar ──────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(top: topPadding),
              color: const Color(0xFF2D2D2D),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Icon(Icons.straighten,
                        color: Color(0xFF00AAFF), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isClosed
                            ? _selectedWallIndex >= 0
                                ? 'Wall ${_selectedWallIndex + 1} selected — enter real measurement'
                                : _activePointIndex >= 0
                                    ? 'Drag point ${_activePointIndex + 1} to reposition'
                                    : _waitingForBle
                                        ? 'Point device at wall → press BOOT button'
                                        : 'Tap a wall to edit its length'
                            : _points.isEmpty
                                ? 'Tap to place first corner'
                                : _isDraggingLastPoint
                                    ? 'Drag | ${_angleLabel()}'
                                    : _activePointIndex >= 0
                                        ? 'Drag point ${_activePointIndex + 1} to reposition'
                                        : _isAngleSnapped
                                            ? 'Snapped: ${_angleLabel()}'
                                            : 'Tap next corner | Drag orange to adjust',
                        style: TextStyle(
                          color: _activePointIndex >= 0
                              ? const Color(0xFFFFAA00)
                              : _isAngleSnapped
                                  ? const Color(0xFF00CC44)
                                  : const Color(0xFFCCCCCC),
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF555555)),
                      ),
                      child: const Text(
                        '1div=100mm',
                        style: TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 10,
                            fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${(_scale * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: Color(0xFFAAAAAA), size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Polar tracking HUD (floating above bottom bar) ───────────
          if (_currentAngleDeg != null &&
              _activePointIndex < 0 &&
              !_isClosed &&
              _points.length >= 1 &&
              _cursorWorld != null)
            Positioned(
              bottom: showAngleStrip ? 86 : 60,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isAngleSnapped
                        ? const Color(0xFF003311).withOpacity(0.95)
                        : const Color(0xFF1A1A2E).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isAngleSnapped
                          ? const Color(0xFF00CC44)
                          : const Color(0xFF334466),
                      width: _isAngleSnapped ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('ANGLE',
                              style: TextStyle(
                                  color: Color(0xFF556677),
                                  fontSize: 9,
                                  fontFamily: 'monospace')),
                          Text(
                            '${_currentAngleDeg!.toStringAsFixed(1)}°',
                            style: TextStyle(
                              color: _isAngleSnapped
                                  ? const Color(0xFF00CC44)
                                  : const Color(0xFF88AACC),
                              fontSize: 18,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (liveDistance != null) ...[
                        const SizedBox(width: 16),
                        Container(
                            width: 1,
                            height: 36,
                            color: const Color(0xFF334466)),
                        const SizedBox(width: 16),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('LENGTH',
                                style: TextStyle(
                                    color: Color(0xFF556677),
                                    fontSize: 9,
                                    fontFamily: 'monospace')),
                            Text(
                              _formatLength(liveDistance),
                              style: const TextStyle(
                                color: Color(0xFF0099FF),
                                fontSize: 18,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_nearestSnapAngleDeg != null) ...[
                        const SizedBox(width: 16),
                        Container(
                            width: 1,
                            height: 36,
                            color: const Color(0xFF334466)),
                        const SizedBox(width: 16),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isAngleSnapped ? 'SNAPPED' : 'NEAREST',
                              style: TextStyle(
                                color: _isAngleSnapped
                                    ? const Color(0xFF00CC44)
                                    : const Color(0xFF556677),
                                fontSize: 9,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              '${_nearestSnapAngleDeg!.toStringAsFixed(0)}°',
                              style: TextStyle(
                                color: _isAngleSnapped
                                    ? const Color(0xFF00FF55)
                                    : const Color(0xFFFFAA33),
                                fontSize: 18,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (!_isAngleSnapped) ...[
                          const SizedBox(width: 12),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('delta',
                                  style: TextStyle(
                                      color: Color(0xFF556677),
                                      fontSize: 9,
                                      fontFamily: 'monospace')),
                              Text(
                                '${(_snapDiffDeg ?? 0).toStringAsFixed(1)}°',
                                style: TextStyle(
                                  color: (_snapDiffDeg ?? 99) < 1.5
                                      ? const Color(0xFFFFCC44)
                                      : const Color(0xFF556677),
                                  fontSize: 14,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                      if (_isAngleSnapped) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.lock,
                            color: Color(0xFF00CC44), size: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // ── Bottom toolbar (angle strip + main bar stacked) ──────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Angle edit strip — full width, shown while drawing ─
                if (showAngleStrip)
                  GestureDetector(
                    onTap: _showAngleEditor,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isAngleSnapped
                            ? const Color(0xFF003A1A)
                            : const Color(0xFF363636),
                        border: Border(
                          top: BorderSide(
                            color: _isAngleSnapped
                                ? const Color(0xFF00CC44)
                                : const Color(0xFF555555),
                            width: _isAngleSnapped ? 1.5 : 1.0,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Left: icon + label
                          if (_isAngleSnapped)
                            const Icon(Icons.lock,
                                size: 13, color: Color(0xFF00CC44))
                          else
                            const Icon(Icons.rotate_90_degrees_ccw,
                                size: 13, color: Color(0xFF888888)),
                          const SizedBox(width: 6),
                          Text(
                            'ANGLE',
                            style: TextStyle(
                              color: _isAngleSnapped
                                  ? const Color(0xFF00CC44)
                                  : const Color(0xFF888888),
                              fontSize: 10,
                              fontFamily: 'monospace',
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Angle value — large and prominent
                          Text(
                            _angleLabel(),
                            style: TextStyle(
                              color: _isAngleSnapped
                                  ? const Color(0xFF00FF66)
                                  : const Color(0xFFEEEEEE),
                              fontSize: 20,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          // Right: tap-to-edit chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isAngleSnapped
                                  ? const Color(0xFF005522)
                                  : const Color(0xFF4A4A4A),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _isAngleSnapped
                                    ? const Color(0xFF00CC44)
                                    : const Color(0xFF666666),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.edit,
                                    size: 11, color: Color(0xFFAAAAAA)),
                                SizedBox(width: 4),
                                Text(
                                  'EDIT',
                                  style: TextStyle(
                                    color: Color(0xFFCCCCCC),
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Main bottom bar ────────────────────────────────────
                Container(
                  height: 52,
                  color: const Color(0xFF2D2D2D),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      // ── Left: status items ───────────────────────────
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _StatusItem(
                                label: 'MODE',
                                value: _isClosed
                                    ? _activePointIndex >= 0
                                        ? 'EDIT'
                                        : 'DONE'
                                    : _isDraggingLastPoint
                                        ? 'DRAG'
                                        : _activePointIndex >= 0
                                            ? 'EDIT'
                                            : 'DRAW',
                              ),
                              const SizedBox(width: 8),
                              _StatusItem(
                                  label: 'PTS',
                                  value: '${_points.length}'),

                              // ── PERIM: only when shape is closed ──────
                              if (_isClosed && _points.length >= 2) ...[
                                const SizedBox(width: 8),
                                _StatusItem(
                                  label: 'PERIM',
                                  value: _formatLength(_totalPerimeter()),
                                ),
                              ],

                              // ── AREA: only when shape is closed ───────
                              if (_isClosed && _points.length >= 3) ...[
                                const SizedBox(width: 8),
                                _StatusItem(
                                  label: 'AREA',
                                  value: _formatArea(_totalArea()),
                                ),
                              ],

                              if (_activePointIndex >= 0 &&
                                  _activePointIndex < _points.length) ...[
                                const SizedBox(width: 8),
                                _StatusItem(
                                  label: 'PT',
                                  value: '${_activePointIndex + 1}',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // ── Right: action buttons ────────────────────────
                      IconButton(
                        icon: const Icon(Icons.undo, size: 18),
                        onPressed: _undoStack.isEmpty ? null : _undo,
                        color: const Color(0xFFFFAA00),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Undo',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo, size: 18),
                        onPressed: _redoStack.isEmpty ? null : _redo,
                        color: const Color(0xFFFFAA00),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Redo',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: _points.isEmpty ? null : _clear,
                        color: const Color(0xFFFF4444),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Clear',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        onPressed: _points.length >= 2 ? _exportPdf : null,
                        color: const Color(0xFFFF4488),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Export PDF',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Sketch Painter
// ─────────────────────────────────────────────
class _SketchPainter extends CustomPainter {
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

  const _SketchPainter({
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

    final text = _formatLength(worldUnits);
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
  bool shouldRepaint(_SketchPainter old) => true;
}

// ── Simple mm/m toggle ───────────────────────────────────────────────────
class _UnitSelector extends StatefulWidget {
  final void Function(String unit) onUnitChanged;
  const _UnitSelector({required this.onUnitChanged});

  @override
  State<_UnitSelector> createState() => _UnitSelectorState();
}

class _UnitSelectorState extends State<_UnitSelector> {
  String _unit = 'mm';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: ['mm', 'm'].map((u) {
        final bool active = _unit == u;
        return GestureDetector(
          onTap: () {
            if (_unit == u) return;
            setState(() => _unit = u);
            widget.onUnitChanged(u);
          },
          child: Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 6),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF00AAFF) : const Color(0xFF0D1A27),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: active
                    ? const Color(0xFF00AAFF)
                    : const Color(0xFF334466),
              ),
            ),
            alignment: Alignment.center,
            child: Text(u,
                style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF556677),
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight:
                        active ? FontWeight.bold : FontWeight.normal)),
          ),
        );
      }).toList(),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatusItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF555555),
                fontSize: 11,
                fontFamily: 'monospace')),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
                fontFamily: 'monospace')),
      ],
    );
  }
}