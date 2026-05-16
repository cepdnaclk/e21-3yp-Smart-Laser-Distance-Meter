import 'package:flutter/material.dart';

enum FurnitureType {
  // Living
  sofa,
  armchair,
  coffeeTable,
  floorLamp,
  bookshelf,
  tvUnit,
  // Bedroom
  singleBed,
  doubleBed,
  queenBed,
  kingBed,
  dresser,
  nightstand,
  wardrobe,
  // Dining
  diningTable,
  roundDiningTable,
  barStool,
  chair,
  // Kitchen
  kitchenCounter,
  islandCounter,
  refrigerator,
  stove,
  sink,
  // Bathroom
  bathtub,
  shower,
  toilet,
  basinSink,
  vanity,
  // Office / Utility
  desk,
  officeChair,
  filingCabinet,
  washingMachine,
}

extension FurnitureTypeExtension on FurnitureType {
  String get displayName {
    switch (this) {
      case FurnitureType.sofa:            return 'Sofa';
      case FurnitureType.armchair:        return 'Armchair';
      case FurnitureType.coffeeTable:     return 'Coffee Table';
      case FurnitureType.floorLamp:       return 'Floor Lamp';
      case FurnitureType.bookshelf:       return 'Bookshelf';
      case FurnitureType.tvUnit:          return 'TV Unit';
      case FurnitureType.singleBed:       return 'Single Bed';
      case FurnitureType.doubleBed:       return 'Double Bed';
      case FurnitureType.queenBed:        return 'Queen Bed';
      case FurnitureType.kingBed:         return 'King Bed';
      case FurnitureType.dresser:         return 'Dresser';
      case FurnitureType.nightstand:      return 'Nightstand';
      case FurnitureType.wardrobe:        return 'Wardrobe';
      case FurnitureType.diningTable:     return 'Dining Table';
      case FurnitureType.roundDiningTable:return 'Round Table';
      case FurnitureType.barStool:        return 'Bar Stool';
      case FurnitureType.chair:           return 'Chair';
      case FurnitureType.kitchenCounter:  return 'Kitchen Counter';
      case FurnitureType.islandCounter:   return 'Island Counter';
      case FurnitureType.refrigerator:    return 'Refrigerator';
      case FurnitureType.stove:           return 'Stove';
      case FurnitureType.sink:            return 'Kitchen Sink';
      case FurnitureType.bathtub:         return 'Bathtub';
      case FurnitureType.shower:          return 'Shower';
      case FurnitureType.toilet:          return 'Toilet';
      case FurnitureType.basinSink:       return 'Basin Sink';
      case FurnitureType.vanity:          return 'Vanity';
      case FurnitureType.desk:            return 'Desk';
      case FurnitureType.officeChair:     return 'Office Chair';
      case FurnitureType.filingCabinet:   return 'Filing Cabinet';
      case FurnitureType.washingMachine:  return 'Washing Machine';
    }
  }

  // (widthMm, depthMm)
  (double, double) get defaultSizeMm {
    switch (this) {
      case FurnitureType.sofa:            return (2200, 900);
      case FurnitureType.armchair:        return (800, 800);
      case FurnitureType.coffeeTable:     return (1100, 600);
      case FurnitureType.floorLamp:       return (300, 300);
      case FurnitureType.bookshelf:       return (900, 300);
      case FurnitureType.tvUnit:          return (1600, 450);
      case FurnitureType.singleBed:       return (900, 2000);
      case FurnitureType.doubleBed:       return (1400, 2000);
      case FurnitureType.queenBed:        return (1600, 2000);
      case FurnitureType.kingBed:         return (1800, 2000);
      case FurnitureType.dresser:         return (1000, 500);
      case FurnitureType.nightstand:      return (500, 400);
      case FurnitureType.wardrobe:        return (1200, 600);
      case FurnitureType.diningTable:     return (1200, 900);
      case FurnitureType.roundDiningTable:return (1200, 1200);
      case FurnitureType.barStool:        return (400, 400);
      case FurnitureType.chair:           return (500, 500);
      case FurnitureType.kitchenCounter:  return (1800, 600);
      case FurnitureType.islandCounter:   return (1500, 900);
      case FurnitureType.refrigerator:    return (700, 700);
      case FurnitureType.stove:           return (600, 600);
      case FurnitureType.sink:            return (600, 500);
      case FurnitureType.bathtub:         return (1700, 800);
      case FurnitureType.shower:          return (900, 900);
      case FurnitureType.toilet:          return (450, 650);
      case FurnitureType.basinSink:       return (600, 500);
      case FurnitureType.vanity:          return (1200, 500);
      case FurnitureType.desk:            return (1200, 600);
      case FurnitureType.officeChair:     return (600, 600);
      case FurnitureType.filingCabinet:   return (450, 600);
      case FurnitureType.washingMachine:  return (600, 600);
    }
  }

  // Height in mm for 3D rendering
  double get heightMm {
    switch (this) {
      case FurnitureType.sofa:            return 850;
      case FurnitureType.armchair:        return 900;
      case FurnitureType.coffeeTable:     return 450;
      case FurnitureType.floorLamp:       return 1600;
      case FurnitureType.bookshelf:       return 1800;
      case FurnitureType.tvUnit:          return 450;
      case FurnitureType.singleBed:       return 600;
      case FurnitureType.doubleBed:       return 600;
      case FurnitureType.queenBed:        return 600;
      case FurnitureType.kingBed:         return 600;
      case FurnitureType.dresser:         return 1300;
      case FurnitureType.nightstand:      return 600;
      case FurnitureType.wardrobe:        return 2100;
      case FurnitureType.diningTable:     return 750;
      case FurnitureType.roundDiningTable:return 750;
      case FurnitureType.barStool:        return 750;
      case FurnitureType.chair:           return 900;
      case FurnitureType.kitchenCounter:  return 900;
      case FurnitureType.islandCounter:   return 900;
      case FurnitureType.refrigerator:    return 1700;
      case FurnitureType.stove:           return 900;
      case FurnitureType.sink:            return 900;
      case FurnitureType.bathtub:         return 550;
      case FurnitureType.shower:          return 2100;
      case FurnitureType.toilet:          return 800;
      case FurnitureType.basinSink:       return 850;
      case FurnitureType.vanity:          return 900;
      case FurnitureType.desk:            return 750;
      case FurnitureType.officeChair:     return 900;
      case FurnitureType.filingCabinet:   return 1200;
      case FurnitureType.washingMachine:  return 850;
    }
  }

  Color get color {
    switch (this) {
      case FurnitureType.sofa:            return const Color(0xFF4CAF50);
      case FurnitureType.armchair:        return const Color(0xFF66BB6A);
      case FurnitureType.coffeeTable:     return const Color(0xFF8D6E63);
      case FurnitureType.floorLamp:       return const Color(0xFFFFD54F);
      case FurnitureType.bookshelf:       return const Color(0xFF795548);
      case FurnitureType.tvUnit:          return const Color(0xFF9C27B0);
      case FurnitureType.singleBed:       return const Color(0xFF2196F3);
      case FurnitureType.doubleBed:       return const Color(0xFF3F51B5);
      case FurnitureType.queenBed:        return const Color(0xFF5C6BC0);
      case FurnitureType.kingBed:         return const Color(0xFF3949AB);
      case FurnitureType.dresser:         return const Color(0xFFA1887F);
      case FurnitureType.nightstand:      return const Color(0xFFBCAAA4);
      case FurnitureType.wardrobe:        return const Color(0xFF6D4C41);
      case FurnitureType.diningTable:     return const Color(0xFFFF9800);
      case FurnitureType.roundDiningTable:return const Color(0xFFFFA726);
      case FurnitureType.barStool:        return const Color(0xFFFFB74D);
      case FurnitureType.chair:           return const Color(0xFF8BC34A);
      case FurnitureType.kitchenCounter:  return const Color(0xFFFF5722);
      case FurnitureType.islandCounter:   return const Color(0xFFFF7043);
      case FurnitureType.refrigerator:    return const Color(0xFF90A4AE);
      case FurnitureType.stove:           return const Color(0xFF78909C);
      case FurnitureType.sink:            return const Color(0xFF80DEEA);
      case FurnitureType.bathtub:         return const Color(0xFF00BCD4);
      case FurnitureType.shower:          return const Color(0xFF00ACC1);
      case FurnitureType.toilet:          return const Color(0xFF9E9E9E);
      case FurnitureType.basinSink:       return const Color(0xFF80CBC4);
      case FurnitureType.vanity:          return const Color(0xFF4DB6AC);
      case FurnitureType.desk:            return const Color(0xFF607D8B);
      case FurnitureType.officeChair:     return const Color(0xFF546E7A);
      case FurnitureType.filingCabinet:   return const Color(0xFF78909C);
      case FurnitureType.washingMachine:  return const Color(0xFF42A5F5);
    }
  }

  IconData get icon {
    switch (this) {
      case FurnitureType.sofa:            return Icons.weekend;
      case FurnitureType.armchair:        return Icons.chair;
      case FurnitureType.coffeeTable:     return Icons.table_bar;
      case FurnitureType.floorLamp:       return Icons.light;
      case FurnitureType.bookshelf:       return Icons.menu_book;
      case FurnitureType.tvUnit:          return Icons.tv;
      case FurnitureType.singleBed:       return Icons.single_bed;
      case FurnitureType.doubleBed:       return Icons.bed;
      case FurnitureType.queenBed:        return Icons.bed;
      case FurnitureType.kingBed:         return Icons.bed;
      case FurnitureType.dresser:         return Icons.door_sliding;
      case FurnitureType.nightstand:      return Icons.nightlight;
      case FurnitureType.wardrobe:        return Icons.door_sliding;
      case FurnitureType.diningTable:     return Icons.table_restaurant;
      case FurnitureType.roundDiningTable:return Icons.table_restaurant;
      case FurnitureType.barStool:        return Icons.chair_alt;
      case FurnitureType.chair:           return Icons.chair_alt;
      case FurnitureType.kitchenCounter:  return Icons.countertops;
      case FurnitureType.islandCounter:   return Icons.countertops;
      case FurnitureType.refrigerator:    return Icons.kitchen;
      case FurnitureType.stove:           return Icons.microwave;
      case FurnitureType.sink:            return Icons.water;
      case FurnitureType.bathtub:         return Icons.bathtub;
      case FurnitureType.shower:          return Icons.shower;
      case FurnitureType.toilet:          return Icons.wc;
      case FurnitureType.basinSink:       return Icons.water_drop;
      case FurnitureType.vanity:          return Icons.face;
      case FurnitureType.desk:            return Icons.desk;
      case FurnitureType.officeChair:     return Icons.chair_alt;
      case FurnitureType.filingCabinet:   return Icons.folder;
      case FurnitureType.washingMachine:  return Icons.local_laundry_service;
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
