import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../repositories/vault_repository.dart';
import '../vault/vault_page.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key, required this.repository});

  final VaultRepository repository;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _pathController = TextEditingController(
    text: '/home/zzy/Desktop/code/KeepassY/keepass-rs/Database.kdbx',
  );
  final _passwordController = TextEditingController();
  final _keyfileController = TextEditingController();
  bool _useKeyfile = false;
  bool _obscurePassword = true;
  bool _opening = false;
  String? _error;

  @override
  void dispose() {
    _pathController.dispose();
    _passwordController.dispose();
    _keyfileController.dispose();
    super.dispose();
  }

  Future<void> _openVault() async {
    setState(() {
      _opening = true;
      _error = null;
    });

    try {
      final vault = await widget.repository.openLocal(
        path: _pathController.text.trim(),
        masterPassword: _passwordController.text,
        keyfilePath: _useKeyfile ? _keyfileController.text.trim() : null,
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => VaultPage(
            repository: widget.repository,
            initialVault: vault,
            keyfilePath: _useKeyfile ? _keyfileController.text.trim() : null,
          ),
        ),
      );
    } on Object catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = err.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 840;
                  final form = _UnlockForm(
                    pathController: _pathController,
                    passwordController: _passwordController,
                    keyfileController: _keyfileController,
                    useKeyfile: _useKeyfile,
                    obscurePassword: _obscurePassword,
                    opening: _opening,
                    error: _error,
                    onUseKeyfileChanged: (value) {
                      setState(() => _useKeyfile = value);
                    },
                    onObscurePasswordChanged: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    onOpen: _opening ? null : _openVault,
                  );

                  if (compact) {
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _ProductHeader(),
                          const SizedBox(height: 24),
                          form,
                        ],
                      ),
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(child: _ProductHeader()),
                      const SizedBox(width: 56),
                      SizedBox(width: 440, child: form),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, size: 48, color: colorScheme.primary),
        const SizedBox(height: 28),
        Text(
          'KeePassY',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'A desktop vault surface for the Rust KeePass backend.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Capability(label: 'Local KDBX'),
            _Capability(label: 'Keyfile ready'),
            _Capability(label: 'JSON FFI boundary'),
          ],
        ),
      ],
    );
  }
}

class _UnlockForm extends StatelessWidget {
  const _UnlockForm({
    required this.pathController,
    required this.passwordController,
    required this.keyfileController,
    required this.useKeyfile,
    required this.obscurePassword,
    required this.opening,
    required this.onUseKeyfileChanged,
    required this.onObscurePasswordChanged,
    required this.onOpen,
    this.error,
  });

  final TextEditingController pathController;
  final TextEditingController passwordController;
  final TextEditingController keyfileController;
  final bool useKeyfile;
  final bool obscurePassword;
  final bool opening;
  final ValueChanged<bool> onUseKeyfileChanged;
  final VoidCallback onObscurePasswordChanged;
  final VoidCallback? onOpen;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Open vault',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pathController,
                    decoration: const InputDecoration(
                      labelText: 'KDBX file path',
                      prefixIcon: Icon(Icons.folder_open_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Browse for KDBX file',
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      dialogTitle: 'Open KDBX vault',
                    );
                    if (result != null && result.files.single.path != null) {
                      pathController.text = result.files.single.path!;
                    }
                  },
                  icon: const Icon(Icons.folder_open),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passwordController,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                labelText: 'Master password',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  tooltip: obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: onObscurePasswordChanged,
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onSubmitted: (_) => onOpen?.call(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use keyfile'),
              value: useKeyfile,
              onChanged: onUseKeyfileChanged,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: useKeyfile
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        key: const ValueKey('keyfile-path'),
                        children: [
                          Expanded(
                            child: TextField(
                              controller: keyfileController,
                              decoration: const InputDecoration(
                                labelText: 'Keyfile path',
                                prefixIcon: Icon(
                                  Icons.insert_drive_file_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Browse for keyfile',
                            onPressed: () async {
                              final result = await FilePicker.platform
                                  .pickFiles(dialogTitle: 'Select keyfile');
                              if (result != null &&
                                  result.files.single.path != null) {
                                keyfileController.text =
                                    result.files.single.path!;
                              }
                            },
                            icon: const Icon(Icons.folder_open),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (error != null) ...[
              const SizedBox(height: 4),
              Text(error!, style: TextStyle(color: colorScheme.error)),
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpen,
              icon: opening
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_open_outlined),
              label: Text(opening ? 'Opening' : 'Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label),
      ),
    );
  }
}
