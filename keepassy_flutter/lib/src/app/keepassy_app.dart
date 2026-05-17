import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/unlock/unlock_page.dart';
import '../repositories/ffi_vault_repository.dart';
import '../repositories/vault_repository.dart';
import '../settings/settings_service.dart';
import 'theme.dart';

class KeepassYApp extends StatefulWidget {
  const KeepassYApp({
    super.key,
    VaultRepository? repository,
    SettingsService? settingsService,
  }) : _repository = repository,
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
  VaultRepository? _repository;
  BackendInfo? _backendInfo;
  String? _startupError;
  String? _startupWarning;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _settingsService = widget._settingsService ?? SettingsService();
    _initializeRepository();
    _settingsService.addListener(() => setState(() {}));
    _settingsService
        .load()
        .then((_) {
          if (mounted) setState(() => _loadGeneration++);
        })
        .catchError((_) {
          if (mounted) setState(() => _loadGeneration++);
        });
  }

  void _initializeRepository() {
    if (widget._repository != null) {
      _repository = widget._repository;
      return;
    }

    try {
      final repository = FfiVaultRepository();
      _repository = repository;
      _backendInfo = repository.backendInfo();
    } catch (e) {
      final message =
          'KeePassY could not start the native backend.\n\n'
          '$e';
      if (kDebugMode) {
        debugPrint(
          'WARNING: FFI library not available, using mock data.\n'
          '  Build it: cd keepass-rs && cargo build -p keepass_ffi --release\n'
          '  Error: $e',
        );
        _repository = MockVaultRepository();
        _startupWarning = message;
      } else {
        _startupError = message;
      }
    }
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
    final repository = _repository;
    final isMock = repository is MockVaultRepository;
    final settings = _settingsService.settings;

    return MaterialApp(
      title: 'KeePassY',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildKeepassYTheme(
        brightness: Brightness.light,
        accentId: settings.themeAccent,
      ),
      darkTheme: buildKeepassYTheme(
        brightness: Brightness.dark,
        accentId: settings.themeAccent,
      ),
      home: _startupError != null
          ? _StartupFailurePage(message: _startupError!)
          : Stack(
              children: [
                if (repository != null)
                  UnlockPage(
                    key: ValueKey('unlock-$_loadGeneration'),
                    repository: repository,
                    settingsService: _settingsService,
                    backendInfo: _backendInfo,
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
                            ScaffoldMessenger.of(
                              context,
                            ).hideCurrentMaterialBanner();
                          },
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ),
                if (_startupWarning != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _startupWarning!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _StartupFailurePage extends StatelessWidget {
  const _StartupFailurePage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 18),
                Text(
                  'Native backend unavailable',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(message),
                const SizedBox(height: 18),
                const Text(
                  'Build the release backend and make sure libkeepass_ffi is bundled next to the app.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
