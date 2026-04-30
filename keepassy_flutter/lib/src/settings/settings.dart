import 'package:flutter/material.dart';

class Settings {
  Settings({
    this.themeMode = ThemeMode.system,
    this.defaultSource = 'local',
    this.lastLocalPath,
    this.lastWebDavUrl,
    this.rememberPaths = true,
    this.autoLockMinutes = 5,
    this.clipboardClearSeconds = 30,
  });

  ThemeMode themeMode;
  String defaultSource;
  String? lastLocalPath;
  String? lastWebDavUrl;
  bool rememberPaths;
  int autoLockMinutes;
  int clipboardClearSeconds;

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.index,
        'defaultSource': defaultSource,
        'lastLocalPath': lastLocalPath,
        'lastWebDavUrl': lastWebDavUrl,
        'rememberPaths': rememberPaths,
        'autoLockMinutes': autoLockMinutes,
        'clipboardClearSeconds': clipboardClearSeconds,
      };

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      themeMode: ThemeMode.values[json['themeMode'] as int? ?? 0],
      defaultSource: json['defaultSource'] as String? ?? 'local',
      lastLocalPath: json['lastLocalPath'] as String?,
      lastWebDavUrl: json['lastWebDavUrl'] as String?,
      rememberPaths: json['rememberPaths'] as bool? ?? true,
      autoLockMinutes: json['autoLockMinutes'] as int? ?? 5,
      clipboardClearSeconds: json['clipboardClearSeconds'] as int? ?? 30,
    );
  }
}
