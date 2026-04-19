// lib/sketch/sketch_dialogs.dart

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'sketch_constants.dart';
import 'sketch_widgets.dart';
import 'room_object.dart';

mixin SketchDialogsMixin<T extends StatefulWidget> on State<T> {

  // ── Abstract interface — the state class provides these ──────────────────
  List<Offset> get sketchPoints;
  bool get sketchIsClosed;
  double? get sketchCurrentAngleDeg;
  double? get sketchSnappedAngle;
  Map<int, double> get sketchWallRealMm;
  bool get sketchWaitingForBle;
  dynamic get sketchBleManager; // BleManager? — avoids importing ble here

  void sketchSetSnappedAngle(double? v);
  void sketchSetCursorWorld(Offset? v);
  void sketchSetCurrentAngleDeg(double? v);
  void sketchSetIsAngleSnapped(bool v);
  void sketchSetSelectedWallIndex(int v);
  void sketchSetWaitingForBle(bool v);
  void sketchSaveUndo();
  void sketchApplyRealMeasurement(int wallIndex, double realMm);
  double sketchWallLengthWorld(int wallIndex);

  // ── Angle editor dialog ──────────────────────────────────────────────────
  void showSketchAngleEditor() {
    final pts = sketchPoints;
    final angleDeg = sketchCurrentAngleDeg;
    if (pts.isEmpty || angleDeg == null || pts.length < 2) return;

    final controller = TextEditingController(text: angleDeg.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text(
          'Edit Wall Angle',
          style: TextStyle(
              color: Color(0xFFCCCCCC), fontFamily: 'monospace', fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adjust angle of last wall (counterclockwise from east)',
              style: TextStyle(
                  color: Color(0xFF888888), fontFamily: 'monospace', fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  color: Color(0xFF00CC44), fontFamily: 'monospace', fontSize: 20),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                style:
                    TextStyle(color: Color(0xFF888888), fontFamily: 'monospace')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00CC44),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final val = double.tryParse(controller.text);
              final pts = sketchPoints;
              if (val != null && pts.length >= 2) {
                final refPoint = pts[pts.length - 2];
                final lastPoint = pts.last;
                final dx = lastPoint.dx - refPoint.dx;
                final dy = lastPoint.dy - refPoint.dy;
                final wallLength = math.sqrt(dx * dx + dy * dy);
                final rad = val * math.pi / 180;
                final updatedLast = Offset(
                  refPoint.dx + wallLength * math.cos(rad),
                  refPoint.dy - wallLength * math.sin(rad),
                );
                Navigator.pop(ctx);
                sketchSaveUndo();
                setState(() {
                  pts[pts.length - 1] = updatedLast;
                  sketchSetCursorWorld(null);
                  sketchSetCurrentAngleDeg(val % 360);
                  sketchSetSnappedAngle(val % 360);
                  sketchSetIsAngleSnapped(false);
                });
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('APPLY', style: TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  // ── Wall edit dialog (BLE choice or manual entry) ────────────────────────
  void showSketchWallEditDialog(int wallIndex) {
    final ble = sketchBleManager;
    final bool bleConnected =
        ble != null && (ble.isConnected as bool? ?? false);

    if (bleConnected) {
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
                'Wall ${wallIndex + 1}  —  '
                '${formatLength(sketchWallLengthWorld(wallIndex))} drawn',
                style: const TextStyle(
                    color: Color(0xFF778899),
                    fontFamily: 'monospace',
                    fontSize: 12),
              ),
              const SizedBox(height: 16),
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
                      sketchSetSelectedWallIndex(wallIndex);
                      sketchSetWaitingForBle(true);
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
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
                    showSketchManualEntryDialog(wallIndex);
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

    showSketchManualEntryDialog(wallIndex);
  }

  // ── Manual measurement entry dialog ─────────────────────────────────────
  void showSketchManualEntryDialog(int wallIndex) {
    final realMmMap = sketchWallRealMm;
    final existingReal = realMmMap.containsKey(wallIndex)
        ? realMmMap[wallIndex]!.toStringAsFixed(0)
        : '';
    final controller = TextEditingController(text: existingReal);

    final int n = sketchPoints.length;
    final bool isClosing = sketchIsClosed && wallIndex == n - 1;
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    formatLength(sketchWallLengthWorld(wallIndex)),
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
                UnitSelector(
                  onUnitChanged: (unit) {
                    final v = double.tryParse(controller.text);
                    if (v == null) return;
                    controller.text = unit == 'm'
                        ? (v / 1000).toStringAsFixed(3)
                        : (v * 1000).toStringAsFixed(0);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                '1000 mm', '1500 mm', '2000 mm',
                '2400 mm', '3000 mm', '4000 mm', '5000 mm',
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
              setState(() => sketchSetSelectedWallIndex(-1));
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
                sketchApplyRealMeasurement(wallIndex, val);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── Object Measurement Dialog ─────────────────────────────────────────────
class ObjectMeasurementDialog extends StatefulWidget {
  final RoomObject roomObject;
  final void Function(RoomObject updated) onSave;
  final VoidCallback onDelete;

  const ObjectMeasurementDialog({
    super.key,
    required this.roomObject,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<ObjectMeasurementDialog> createState() =>
      _ObjectMeasurementDialogState();
}

class _ObjectMeasurementDialogState
    extends State<ObjectMeasurementDialog> {
  late double? _width;   // in metres
  late double? _height;  // in metres
  late double? _top;     // window only
  late double? _bottom;  // window only

  @override
  void initState() {
    super.initState();
    _width  = widget.roomObject.widthMm / 1000.0;
    _height = widget.roomObject.heightMm / 1000.0;
    _top    = widget.roomObject.heightMm / 1000.0;   // default same as height
    _bottom = widget.roomObject.elevationMm / 1000.0;
  }

  bool get _isDoor => widget.roomObject.isDoor;

  // Ask user to type a measurement for the given side label
  Future<void> _editSide(String sideLabel, double? current,
      void Function(double) onConfirmed) async {
    final ctrl = TextEditingController(
      text: current != null ? current.toStringAsFixed(3) : '',
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A3A),
        title: Text(
          '$sideLabel measurement',
          style: const TextStyle(
              color: Color(0xFFCCDDEE),
              fontFamily: 'monospace',
              fontSize: 14),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
              color: Colors.white, fontFamily: 'monospace'),
          decoration: InputDecoration(
            suffixText: 'm',
            suffixStyle: const TextStyle(color: Color(0xFF00AAFF)),
            hintText: 'e.g. 0.900',
            hintStyle:
                const TextStyle(color: Color(0xFF445566)),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF334466))),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF00AAFF))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL',
                style: TextStyle(
                    color: Color(0xFF778899),
                    fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v != null && v > 0) {
                onConfirmed(v);
              }
              Navigator.pop(ctx);
            },
            child: const Text('OK',
                style: TextStyle(
                    color: Color(0xFF00AAFF),
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  String _fmt(double? v) =>
      v != null ? '${v.toStringAsFixed(3)} m' : 'tap to set';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E2A3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title ─────────────────────────────────────────────────
            Text(
              _isDoor ? '🚪  Door Measurements' : '🪟  Window Measurements',
              style: const TextStyle(
                  color: Color(0xFFCCDDEE),
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap any side to enter its measurement',
              style: TextStyle(
                  color: Color(0xFF556677),
                  fontFamily: 'monospace',
                  fontSize: 11),
            ),
            const SizedBox(height: 20),

            // ── Interactive shape ──────────────────────────────────────
            _isDoor
                ? _DoorMeasureWidget(
                    width: _width,
                    height: _height,
                    onTapWidth: () => _editSide('Width', _width, (v) {
                      setState(() => _width = v);
                    }),
                    onTapHeight: () => _editSide('Height', _height, (v) {
                      setState(() => _height = v);
                    }),
                  )
                : _WindowMeasureWidget(
                    width: _width,
                    height: _height,
                    top: _top,
                    bottom: _bottom,
                    onTapWidth: () => _editSide('Width', _width, (v) {
                      setState(() => _width = v);
                    }),
                    onTapHeight: () => _editSide('Height (right)', _height, (v) {
                      setState(() => _height = v);
                    }),
                    onTapTop: () => _editSide('Top', _top, (v) {
                      setState(() => _top = v);
                    }),
                    onTapBottom: () => _editSide('Bottom', _bottom, (v) {
                      setState(() => _bottom = v);
                    }),
                  ),

            const SizedBox(height: 20),

            // ── Action buttons ─────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () {
                    widget.onDelete();
                    Navigator.pop(context);
                  },
                  child: const Text('DELETE',
                      style: TextStyle(
                          color: Color(0xFFFF4444),
                          fontFamily: 'monospace',
                          fontSize: 12)),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL',
                          style: TextStyle(
                              color: Color(0xFF778899),
                              fontFamily: 'monospace',
                              fontSize: 12)),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00AAFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                      onPressed: () {
                        final updated = widget.roomObject.copyWith(
                          widthMm: (_width ?? widget.roomObject.widthMm / 1000.0) * 1000,
                          heightMm: (_height ?? widget.roomObject.heightMm / 1000.0) * 1000,
                          elevationMm: _isDoor
                              ? 0
                              : (_bottom ?? widget.roomObject.elevationMm / 1000.0) * 1000,
                        );
                        widget.onSave(updated);
                        Navigator.pop(context);
                      },
                      child: const Text('SAVE',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Door shape widget ──────────────────────────────────────────────────────
class _DoorMeasureWidget extends StatelessWidget {
  final double? width;
  final double? height;
  final VoidCallback onTapWidth;
  final VoidCallback onTapHeight;

  const _DoorMeasureWidget({
    required this.width,
    required this.height,
    required this.onTapWidth,
    required this.onTapHeight,
  });

  String _fmt(double? v) => v != null ? '${v.toStringAsFixed(3)} m' : 'tap to set';

  @override
  Widget build(BuildContext context) {
    const double w = 140.0;
    const double h = 190.0;
    const Color doorColor = Color(0xFF8B4513); // saddle brown
    const Color doorDark  = Color(0xFF5C2E00);
    const Color labelColor = Color(0xFFCCDDEE);

    return SizedBox(
      width: w + 100,
      height: h + 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Door body ────────────────────────────────────────────────
          Positioned(
            left: 50, top: 20,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: doorColor,
                border: Border.all(color: doorDark, width: 3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(4, 4),
                  )
                ],
              ),
              child: Stack(
                children: [
                  // Inner panel lines
                  Positioned(
                    left: 10, right: 10, top: 10, bottom: 10,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: doorDark.withOpacity(0.5), width: 1.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Door knob
                  Positioned(
                    right: 16,
                    top: h / 2 - 6,
                    child: Container(
                      width: 10, height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFD700),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Width label (bottom, tappable) ───────────────────────────
          Positioned(
            bottom: 0,
            left: 50,
            child: GestureDetector(
              onTap: onTapWidth,
              child: Container(
                width: w,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1A27),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF00AAFF)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.swap_horiz, color: Color(0xFF00AAFF), size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(width),
                      style: const TextStyle(
                          color: labelColor,
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Height label (right side, tappable) ──────────────────────
          Positioned(
            right: 0,
            top: 20,
            child: GestureDetector(
              onTap: onTapHeight,
              child: RotatedBox(
                quarterTurns: 1,
                child: Container(
                  width: h,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1A27),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF00AA66)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.swap_vert, color: Color(0xFF00AA66), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _fmt(height),
                        style: const TextStyle(
                            color: labelColor,
                            fontSize: 11,
                            fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Window shape widget ────────────────────────────────────────────────────
class _WindowMeasureWidget extends StatelessWidget {
  final double? width;
  final double? height;
  final double? top;
  final double? bottom;
  final VoidCallback onTapWidth;
  final VoidCallback onTapHeight;
  final VoidCallback onTapTop;
  final VoidCallback onTapBottom;

  const _WindowMeasureWidget({
    required this.width,
    required this.height,
    required this.top,
    required this.bottom,
    required this.onTapWidth,
    required this.onTapHeight,
    required this.onTapTop,
    required this.onTapBottom,
  });

  String _fmt(double? v) => v != null ? '${v.toStringAsFixed(3)} m' : 'tap';

  @override
  Widget build(BuildContext context) {
    const double w = 130.0;
    const double h = 130.0;
    const Color frameColor = Color(0xFF90A4AE);  // blue-grey window frame
    const Color glassColor = Color(0xFFB3E5FC);  // light blue glass
    const Color labelColor = Color(0xFFCCDDEE);

    return SizedBox(
      width: w + 110,
      height: h + 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Window frame and glass panes ─────────────────────────────
          Positioned(
            left: 45, top: 35,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: glassColor.withOpacity(0.3),
                border: Border.all(color: frameColor, width: 4),
              ),
              child: Stack(
                children: [
                  // Horizontal divider
                  Positioned(
                    top: h / 2 - 2,
                    left: 0, right: 0,
                    child: Container(height: 4, color: frameColor),
                  ),
                  // Vertical divider
                  Positioned(
                    left: w / 2 - 2,
                    top: 0, bottom: 0,
                    child: Container(width: 4, color: frameColor),
                  ),
                  // Glass tint panes
                  Positioned(
                    left: 6, top: 6,
                    right: w / 2 + 2, bottom: h / 2 + 2,
                    child: Container(color: glassColor.withOpacity(0.25)),
                  ),
                  Positioned(
                    left: w / 2 + 6, top: 6,
                    right: 6, bottom: h / 2 + 2,
                    child: Container(color: glassColor.withOpacity(0.15)),
                  ),
                ],
              ),
            ),
          ),

          // ── TOP label ────────────────────────────────────────────────
          Positioned(
            top: 0, left: 45,
            child: GestureDetector(
              onTap: onTapTop,
              child: Container(
                width: w,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1A27),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFFFAA00)),
                ),
                child: Text(
                  _fmt(top),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: labelColor, fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),

          // ── BOTTOM label ─────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 45,
            child: GestureDetector(
              onTap: onTapBottom,
              child: Container(
                width: w,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1A27),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF00AAFF)),
                ),
                child: Text(
                  _fmt(bottom),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: labelColor, fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),

          // ── LEFT label (Height, rotated) ─────────────────────────────
          Positioned(
            left: 0, top: 35,
            child: GestureDetector(
              onTap: onTapHeight,
              child: RotatedBox(
                quarterTurns: 3,
                child: Container(
                  width: h,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1A27),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF00AA66)),
                  ),
                  child: Text(
                    _fmt(height),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: labelColor, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ),

          // ── RIGHT label (Width, rotated) ─────────────────────────────
          Positioned(
            right: 0, top: 35,
            child: GestureDetector(
              onTap: onTapWidth,
              child: RotatedBox(
                quarterTurns: 1,
                child: Container(
                  width: h,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1A27),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF00AAFF)),
                  ),
                  child: Text(
                    _fmt(width),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: labelColor, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}