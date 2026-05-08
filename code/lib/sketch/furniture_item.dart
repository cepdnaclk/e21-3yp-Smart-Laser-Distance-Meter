import 'package:flutter/material.dart';

enum FurnitureType {
  sofa,
  singleBed,
  doubleBed,
  diningTable,
  bathtub,
  toilet,
  kitchenCounter,
  wardrobe,
  desk,
  chair,
  tvUnit,
}

extension FurnitureTypeExtension on FurnitureType {
  String get displayName {
    switch (this) {
      case FurnitureType.sofa:
        return 'Sofa';
      case FurnitureType.singleBed:
        return 'Single Bed';
      case FurnitureType.doubleBed:
        return 'Double Bed';
      case FurnitureType.diningTable:
        return 'Dining Table';
      case FurnitureType.bathtub:
        return 'Bathtub';
      case FurnitureType.toilet:
        return 'Toilet';
      case FurnitureType.kitchenCounter:
        return 'Kitchen';
      case FurnitureType.wardrobe:
        return 'Wardrobe';
      case FurnitureType.desk:
        return 'Desk';
      case FurnitureType.chair:
        return 'Chair';
      case FurnitureType.tvUnit:
        return 'TV Unit';
    }
  }

  // Default size: (widthMm, depthMm)
  (double, double) get defaultSizeMm {
    switch (this) {
      case FurnitureType.sofa:
        return (2200, 900);
      case FurnitureType.singleBed:
        return (900, 2000);
      case FurnitureType.doubleBed:
        return (1600, 2000);
      case FurnitureType.diningTable:
        return (1200, 900);
      case FurnitureType.bathtub:
        return (1700, 800);
      case FurnitureType.toilet:
        return (450, 650);
      case FurnitureType.kitchenCounter:
        return (1800, 600);
      case FurnitureType.wardrobe:
        return (1200, 600);
      case FurnitureType.desk:
        return (1200, 600);
      case FurnitureType.chair:
        return (500, 500);
      case FurnitureType.tvUnit:
        return (1600, 450);
    }
  }

  Color get color {
    switch (this) {
      case FurnitureType.sofa:
        return const Color(0xFF4CAF50);
      case FurnitureType.singleBed:
        return const Color(0xFF2196F3);
      case FurnitureType.doubleBed:
        return const Color(0xFF3F51B5);
      case FurnitureType.diningTable:
        return const Color(0xFFFF9800);
      case FurnitureType.bathtub:
        return const Color(0xFF00BCD4);
      case FurnitureType.toilet:
        return const Color(0xFF9E9E9E);
      case FurnitureType.kitchenCounter:
        return const Color(0xFFFF5722);
      case FurnitureType.wardrobe:
        return const Color(0xFF795548);
      case FurnitureType.desk:
        return const Color(0xFF607D8B);
      case FurnitureType.chair:
        return const Color(0xFF8BC34A);
      case FurnitureType.tvUnit:
        return const Color(0xFF9C27B0);
    }
  }

  IconData get icon {
    switch (this) {
      case FurnitureType.sofa:
        return Icons.weekend;
      case FurnitureType.singleBed:
        return Icons.single_bed;
      case FurnitureType.doubleBed:
        return Icons.bed;
      case FurnitureType.diningTable:
        return Icons.table_restaurant;
      case FurnitureType.bathtub:
        return Icons.bathtub;
      case FurnitureType.toilet:
        return Icons.wc;
      case FurnitureType.kitchenCounter:
        return Icons.countertops;
      case FurnitureType.wardrobe:
        return Icons.door_sliding;
      case FurnitureType.desk:
        return Icons.desk;
      case FurnitureType.chair:
        return Icons.chair_alt;
      case FurnitureType.tvUnit:
        return Icons.tv;
    }
  }
}

class FurnitureItem {
  final String id;
  final FurnitureType type;
  Offset position; // world-coordinate centre (free-floating, NOT wall-anchored)
  double rotationDeg; // clockwise, 0 = facing right
  double widthMm;
  double depthMm;

  FurnitureItem({
    required this.id,
    required this.type,
    required this.position,
    this.rotationDeg = 0.0,
    double? widthMm,
    double? depthMm,
  })  : widthMm = widthMm ?? type.defaultSizeMm.$1,
        depthMm = depthMm ?? type.defaultSizeMm.$2;

  FurnitureItem copyWith({
    Offset? position,
    double? rotationDeg,
    double? widthMm,
    double? depthMm,
  }) {
    return FurnitureItem(
      id: id,
      type: type,
      position: position ?? this.position,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      widthMm: widthMm ?? this.widthMm,
      depthMm: depthMm ?? this.depthMm,
    );
  }
}
