import 'package:flutter/material.dart';

/// Theme-aware outline shared by detail tabs and custom tab rows.
class BrandTabIndicator extends BoxDecoration {
  BrandTabIndicator({required Color color})
    : super(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(6),
      );
}
