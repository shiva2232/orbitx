import 'dart:ui';
import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 20,
          sigmaY: 20,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: .2),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}