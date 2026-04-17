// lib/sketch/sketch_widgets.dart

import 'package:flutter/material.dart';

// ── mm / m unit toggle used inside wall-edit dialog ──────────────────────
class UnitSelector extends StatefulWidget {
  final void Function(String unit) onUnitChanged;
  const UnitSelector({super.key, required this.onUnitChanged});

  @override
  State<UnitSelector> createState() => _UnitSelectorState();
}

class _UnitSelectorState extends State<UnitSelector> {
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
                color: active ? const Color(0xFF00AAFF) : const Color(0xFF334466),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              u,
              style: TextStyle(
                color: active ? Colors.white : const Color(0xFF556677),
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Label + value pair shown in the bottom status bar ────────────────────
class StatusItem extends StatelessWidget {
  final String label;
  final String value;
  const StatusItem({super.key, required this.label, required this.value});

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