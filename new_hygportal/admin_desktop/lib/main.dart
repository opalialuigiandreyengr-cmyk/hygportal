import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'src/app.dart';
part 'src/shell.dart';
part 'src/assist_screen.dart';
part 'src/employees_screen.dart';
part 'src/companies_screen.dart';
part 'src/departments_screen.dart';
part 'src/stores_screen.dart';
part 'src/clusters_screen.dart';
part 'src/admin_workflow_screen.dart';
part 'src/positions_screen.dart';
part 'src/users_screen.dart';
part 'src/requests_screen.dart';
part 'src/shared_widgets.dart';
part 'src/models.dart';
part 'src/services.dart';
part 'src/design_system.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _ignoreWindowsHotRestartAltKeyAssertion();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  await LocalSyncService.initialize();
  unawaited(LocalSyncService.syncNow());

  runApp(const HygAdminApp());
}

void _ignoreWindowsHotRestartAltKeyAssertion() {
  final defaultOnError = FlutterError.onError;

  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    final isHotRestartKeyStateAssertion =
        Platform.isWindows &&
        message.contains(
          'Attempted to send a key down event when no keys are in keysPressed',
        ) &&
        message.contains('RawKeyDownEvent');

    if (isHotRestartKeyStateAssertion) {
      return;
    }

    if (defaultOnError != null) {
      defaultOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
}
