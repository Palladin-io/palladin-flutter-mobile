import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Visual order of the tapped navbar item, carried only with that navigation.
/// Deep links and auth redirects have no direction and appear immediately.
enum ShellTabDirection {
  none(0),
  fromLeft(-1),
  fromRight(1);

  const ShellTabDirection(this.horizontalOffset);
  final double horizontalOffset;

  static ShellTabDirection between(int currentIndex, int nextIndex) =>
      nextIndex == currentIndex
      ? none
      : nextIndex > currentIndex
      ? fromRight
      : fromLeft;
}

/// Only the page content slides; the shell's navbar and drawer stay mounted.
class ShellTabPage extends CustomTransitionPage<void> {
  ShellTabPage({
    required LocalKey pageKey,
    required super.child,
    required ShellTabDirection direction,
    required bool disableAnimations,
  }) : super(
         key: pageKey,
         transitionDuration:
             disableAnimations || direction == ShellTabDirection.none
             ? Duration.zero
             : const Duration(milliseconds: 260),
         reverseTransitionDuration: Duration.zero,
         transitionsBuilder: (context, animation, secondaryAnimation, child) {
           if (disableAnimations || direction == ShellTabDirection.none) {
             return child;
           }
           return ClipRect(
             child: SlideTransition(
               position:
                   Tween<Offset>(
                     begin: Offset(direction.horizontalOffset, 0),
                     end: Offset.zero,
                   ).animate(
                     animation.drive(CurveTween(curve: Curves.easeOutCubic)),
                   ),
               child: child,
             ),
           );
         },
       );
}
