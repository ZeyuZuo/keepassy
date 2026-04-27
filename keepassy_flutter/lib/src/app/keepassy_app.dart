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
    } catch (_) {
      return MockVaultRepository();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeePassY',
      debugShowCheckedModeBanner: false,
      theme: buildKeepassYTheme(),
      home: UnlockPage(repository: _repository ?? defaultRepository()),
    );
  }
}
