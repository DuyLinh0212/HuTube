import 'package:flutter/material.dart';

/// Keeps sheet content reachable with the keyboard open and in landscape.
class ScrollableSheet extends StatelessWidget {
  const ScrollableSheet({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              .9,
        ),
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

class HuTubeScrollable extends StatelessWidget {
  const HuTubeScrollable({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.hasBoundedHeight
        ? SingleChildScrollView(child: child)
        : child,
  );
}
