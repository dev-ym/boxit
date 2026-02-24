import 'package:flutter/material.dart';

const kRectColors = <Color>[
  Color(0xFF4CAF50),
  Color(0xFF2196F3),
  Color(0xFFF44336),
  Color(0xFFFF9800),
  Color(0xFF9C27B0),
  Color(0xFF00BCD4),
  Color(0xFFFFEB3B),
  Color(0xFFE91E63),
  Color(0xFF795548),
  Color(0xFF607D8B),
];

class RectType {
  final double width, height;
  final int count;
  final Color color;

  const RectType({
    required this.width,
    required this.height,
    required this.count,
    required this.color,
  });

  RectType copyWith({double? width, double? height, int? count, Color? color}) =>
      RectType(
        width: width ?? this.width,
        height: height ?? this.height,
        count: count ?? this.count,
        color: color ?? this.color,
      );
}

class PlacedRect {
  final double x, y, w, h;
  final int typeIndex;
  final bool rotated;

  const PlacedRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.typeIndex,
    required this.rotated,
  });
}

class PackResult {
  final double squareSize;
  final List<PlacedRect> placed;

  const PackResult({required this.squareSize, required this.placed});
}
