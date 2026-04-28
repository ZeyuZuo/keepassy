import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/unlock/unlock_page.dart';
import '../repositories/ffi_vault_repository.dart';
import '../repositories/vault_repository.dart';
import 'theme.dart';

class KeepassYApp extends StatelessWidget {
  const KeepassYApp({super.key, VaultRepository? repository})
    : _repository = repository;

  final VaultRepository? _repository;

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
  Widget build(BuildContext context) {
    final repository = _repository ?? defaultRepository();
    final isMock = repository is MockVaultRepository;

    return MaterialApp(
      title: 'KeePassY',
      debugShowCheckedModeBanner: false,
      theme: buildKeepassYTheme(),
      home: Stack(
        children: [
          UnlockPage(repository: repository),
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
