import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/unlock/unlock_page.dart';
import '../repositories/ffi_vault_repository.dart';
import '../repositories/vault_repository.dart';
import '../settings/settings_service.dart';
import 'theme.dart';

class KeepassYApp extends StatefulWidget {
  const KeepassYApp({super.key, VaultRepository? repository, SettingsService? settingsService})
    : _repository = repository,
      _settingsService = settingsService;

  final VaultRepository? _repository;
  final SettingsService? _settingsService;

  static VaultRepository defaultRepository() {
    try {
      return FfiVaultRepository();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'WARNING: FFI library not available, using mock data.\n'
          '  Build it: cd keepass-rs && cargo build -p keepass_ffi\n'
          '  Error: $e',
        );
        return MockVaultRepository();
      }
      rethrow;
    }
  }

  @override
  State<KeepassYApp> createState() => _KeepassYAppState();
}

class _KeepassYAppState extends State<KeepassYApp> {
  late final SettingsService _settingsService;

  @override
  void initState() {
    super.initState();
    _settingsService = widget._settingsService ?? SettingsService();
    _settingsService.addListener(() => setState(() {}));
    _settingsService.load();
  }

  @override
  void dispose() {
    if (widget._settingsService == null) {
      _settingsService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget._repository ?? KeepassYApp.defaultRepository();
    final isMock = repository is MockVaultRepository;
    final settings = _settingsService.settings;

    return MaterialApp(
      title: 'KeePassY',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildKeepassYTheme(brightness: Brightness.light),
      darkTheme: buildKeepassYTheme(brightness: Brightness.dark),
      home: Stack(
        children: [
          UnlockPage(
            repository: repository,
            settingsService: _settingsService,
          ),
          if (isMock)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: MaterialBanner(
                content: const Text(
                  'Mock data — FFI library not loaded. '
                  'Build keepass_ffi to use real vaults.',
                ),
                backgroundColor: Colors.orange.withValues(alpha: 0.12),
                actions: [
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                    },
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
