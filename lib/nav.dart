import 'package:flutter/material.dart';

final navKey = GlobalKey<NavigatorState>();

// Set by main() so other files can go home without importing main.dart
Widget Function()? homeBuilder;

void goHome(BuildContext c) {
  Navigator.of(c).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => homeBuilder!()), (r) => false);
}
