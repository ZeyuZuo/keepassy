import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'src/app/keepassy_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final view = PlatformDispatcher.instance.views.first;
    if (view.physicalSize.width / view.devicePixelRatio < 720 ||
        view.physicalSize.height / view.devicePixelRatio < 480) {
      // Flutter desktop doesn't expose a direct minimum window size API.
      // This is handled by the platform embedder configuration:
      // Linux:  CMakeLists.txt / GTK window properties
      // macOS:  Runner.xcodeproj / MainFlutterWindow.swift
      // Windows: runner/Runner.rc or Win32 window creation
    }
  }

  runApp(const KeepassYApp());
}
