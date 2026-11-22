import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final deps = await AppDependencies.create();
  runApp(HedoneApp(deps: deps));
}
