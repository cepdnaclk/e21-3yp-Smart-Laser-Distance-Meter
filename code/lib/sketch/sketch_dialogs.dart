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
// ── Object Measurement Dialog ──────────────────────────────────────────────
class ObjectMeasurementDialog extends StatefulWidget {
  final RoomObject roomObject;
  final ValueChanged<RoomObject> onSave;
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

class _ObjectMeasurementDialogState extends State<ObjectMeasurementDialog> {
  late TextEditingController _widthCtrl;
  late TextEditingController _heightCtrl;
  late TextEditingController _elevationCtrl;

  @override
  void initState() {
    super.initState();
    _widthCtrl = TextEditingController(
        text: widget.roomObject.widthMm.toStringAsFixed(0));
    _heightCtrl = TextEditingController(
        text: widget.roomObject.heightMm.toStringAsFixed(0));
    _elevationCtrl = TextEditingController(
        text: widget.roomObject.elevationMm.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _elevationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDoor = widget.roomObject.isDoor;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E2A3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(isDoor ? Icons.door_front_door : Icons.window,
              color: const Color(0xFF00AAFF), size: 20),
          const SizedBox(width: 8),
          Text(isDoor ? 'Edit Door' : 'Edit Window',
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
          const Text('Width (mm)',
              style: TextStyle(
                  color: Color(0xFF778899),
                  fontFamily: 'monospace',
                  fontSize: 11)),
          const SizedBox(height: 4),
          TextField(
            controller: _widthCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Color(0xFF00DDFF), fontFamily: 'monospace'),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xFF0D1A27),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF334466))),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00AAFF))),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Height (mm)',
              style: TextStyle(
                  color: Color(0xFF778899),
                  fontFamily: 'monospace',
                  fontSize: 11)),
          const SizedBox(height: 4),
          TextField(
            controller: _heightCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Color(0xFF00DDFF), fontFamily: 'monospace'),
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xFF0D1A27),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF334466))),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00AAFF))),
            ),
          ),
          if (!isDoor) ...[
            const SizedBox(height: 12),
            const Text('Elevation from floor (mm)',
                style: TextStyle(
                    color: Color(0xFF778899),
                    fontFamily: 'monospace',
                    fontSize: 11)),
            const SizedBox(height: 4),
            TextField(
              controller: _elevationCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Color(0xFF00DDFF), fontFamily: 'monospace'),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF0D1A27),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF334466))),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00AAFF))),
              ),
            ),
          ]
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onDelete();
          },
          child: const Text('DELETE',
              style: TextStyle(color: Color(0xFFFF4444), fontFamily: 'monospace')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL',
              style: TextStyle(color: Color(0xFF556677), fontFamily: 'monospace')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00AAFF),
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final w = double.tryParse(_widthCtrl.text) ?? widget.roomObject.widthMm;
            final h = double.tryParse(_heightCtrl.text) ?? widget.roomObject.heightMm;
            final e = isDoor
                ? 0.0
                : (double.tryParse(_elevationCtrl.text) ??
                    widget.roomObject.elevationMm);

            widget.onSave(widget.roomObject
                .copyWith(widthMm: w, heightMm: h, elevationMm: e));
            Navigator.pop(context);
          },
          child: const Text('SAVE', style: TextStyle(fontFamily: 'monospace')),
        ),
      ],
    );
  }
}
