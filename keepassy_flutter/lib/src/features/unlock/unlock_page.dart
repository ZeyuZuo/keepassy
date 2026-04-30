import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/vault_models.dart';
import '../../repositories/vault_repository.dart';
import '../../settings/settings_service.dart';
import '../settings/settings_dialog.dart';
import '../vault/vault_page.dart';

double _pwStrength(String pw) {
  if (pw.isEmpty) return 0;
  double score = 0;
  if (pw.length >= 8) score += 1;
  if (pw.length >= 12) score += 1;
  if (pw.length >= 16) score += 1;
  if (RegExp(r'[a-z]').hasMatch(pw)) score += 0.5;
  if (RegExp(r'[A-Z]').hasMatch(pw)) score += 0.5;
  if (RegExp(r'[0-9]').hasMatch(pw)) score += 0.5;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pw)) score += 0.5;
  return (score / 4).clamp(0.0, 1.0);
}

Color _pwColor(double v) {
  if (v < 0.3) return Colors.red;
  if (v < 0.6) return Colors.orange;
  return Colors.green;
}

String _withKdbxExtension(String path) {
  final trimmed = path.trim();
  if (trimmed.toLowerCase().endsWith('.kdbx')) {
    return trimmed;
  }
  return '$trimmed.kdbx';
}

class _CreateVaultResult {
  const _CreateVaultResult({
    required this.vault,
    required this.path,
    this.keyfilePath,
  });

  final OpenedVault vault;
  final String path;
  final String? keyfilePath;
}

class _CreateVaultDialog extends StatefulWidget {
  const _CreateVaultDialog({required this.repository});

  final VaultRepository repository;

  @override
  State<_CreateVaultDialog> createState() => _CreateVaultDialogState();
}

class _CreateVaultDialogState extends State<_CreateVaultDialog> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _keyfileCtrl = TextEditingController();

  String? _vaultPath;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _useKeyfile = false;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _keyfileCtrl.dispose();
    super.dispose();
  }

  Future<void> _chooseVaultPath() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Create KDBX vault',
      fileName: 'NewVault.kdbx',
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _vaultPath = _withKdbxExtension(result);
      _error = null;
    });
  }

  Future<void> _chooseExistingKeyfile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select keyfile',
    );
    if (result == null || result.files.single.path == null || !mounted) {
      return;
    }
    setState(() {
      _useKeyfile = true;
      _keyfileCtrl.text = result.files.single.path!;
      _error = null;
    });
  }

  Future<void> _createKeyfile() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Create keyfile',
      fileName: 'keepassy.key',
    );
    if (result == null || !mounted) {
      return;
    }

    final path = result.trim();
    if (path.isEmpty) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      setState(() => _error = 'Keyfile already exists. Choose a new file.');
      return;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(256));
    try {
      await file.writeAsBytes(bytes, flush: true);
    } on Object catch (err) {
      if (!mounted) return;
      setState(() => _error = 'Failed to create keyfile: $err');
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _useKeyfile = true;
      _keyfileCtrl.text = path;
      _error = null;
    });
  }

  String? _validate() {
    final path = _vaultPath;
    if (path == null || path.trim().isEmpty) {
      return 'Choose where to save the KDBX file.';
    }
    if (File(path.trim()).existsSync()) {
      return 'A vault already exists at this path.';
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      return 'Passwords do not match.';
    }
    if (_passwordCtrl.text.isEmpty && !_useKeyfile) {
      return 'Set a master password or use a keyfile.';
    }
    if (_useKeyfile) {
      final keyfilePath = _keyfileCtrl.text.trim();
      if (keyfilePath.isEmpty) {
        return 'Choose or create a keyfile.';
      }
      if (!File(keyfilePath).existsSync()) {
        return 'Keyfile does not exist.';
      }
    }
    return null;
  }

  Future<void> _createVault() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    final path = _vaultPath!.trim();
    final keyfilePath = _useKeyfile ? _keyfileCtrl.text.trim() : null;

    try {
      final vault = await widget.repository.createLocal(
        path: path,
        masterPassword: _passwordCtrl.text,
        keyfilePath: keyfilePath,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        _CreateVaultResult(vault: vault, path: path, keyfilePath: keyfilePath),
      );
    } on Object catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _error = err.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strength = _pwStrength(_passwordCtrl.text);

    return AlertDialog(
      title: const Text('Create local KDBX'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel('Vault file'),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _creating ? null : _chooseVaultPath,
                icon: const Icon(Icons.folder_open),
                label: Text(
                  _vaultPath == null
                      ? 'Choose save location'
                      : 'Change location',
                ),
              ),
              if (_vaultPath != null) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _vaultPath!,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const _SectionLabel('Master credentials'),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: _useKeyfile
                      ? 'Master password (optional)'
                      : 'Master password',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                onChanged: (_) => setState(() => _error = null),
                textInputAction: TextInputAction.next,
              ),
              if (strength > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: strength,
                          minHeight: 4,
                          color: _pwColor(strength),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ['Weak', 'Fair', 'Good', 'Strong'][(strength * 3.99)
                          .toInt()],
                      style: TextStyle(fontSize: 11, color: _pwColor(strength)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.check_circle_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirm
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _creating ? null : _createVault(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Use keyfile'),
                subtitle: const Text(
                  'A vault can use password, keyfile, or both.',
                ),
                value: _useKeyfile,
                onChanged: _creating
                    ? null
                    : (value) {
                        setState(() {
                          _useKeyfile = value;
                          if (!value) {
                            _keyfileCtrl.clear();
                          }
                          _error = null;
                        });
                      },
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: _useKeyfile
                    ? Padding(
                        key: const ValueKey('create-keyfile-section'),
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _keyfileCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Keyfile',
                                      prefixIcon: Icon(
                                        Icons.insert_drive_file_outlined,
                                      ),
                                    ),
                                    onChanged: (_) =>
                                        setState(() => _error = null),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Select existing keyfile',
                                  onPressed: _creating
                                      ? null
                                      : _chooseExistingKeyfile,
                                  icon: const Icon(Icons.folder_open),
                                ),
                                IconButton(
                                  tooltip: 'Create keyfile',
                                  onPressed: _creating ? null : _createKeyfile,
                                  icon: const Icon(Icons.note_add_outlined),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _creating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _creating ? null : _createVault,
          icon: _creating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(_creating ? 'Creating' : 'Create vault'),
        ),
      ],
    );
  }
}

enum _VaultSource { local, webDav }

class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key, required this.repository, this.settingsService});

  final VaultRepository repository;
  final SettingsService? settingsService;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  late final _pathController = TextEditingController(text: _initialPath());
  late final _webDavUrlController = TextEditingController(
    text: _initialWebDavUrl(),
  );
  final _webDavUsernameController = TextEditingController();
  final _webDavPasswordController = TextEditingController();
  final _passwordController = TextEditingController();
  final _keyfileController = TextEditingController();
  late _VaultSource _source = _initialSource();

  String _initialPath() {
    final svc = widget.settingsService;
    if (svc != null) {
      final s = svc.settings;
      if (s.rememberPaths && s.lastLocalPath != null) return s.lastLocalPath!;
    }
    return '/home/zzy/Desktop/code/KeepassY/keepass-rs/Database.kdbx';
  }

  String _initialWebDavUrl() {
    final svc = widget.settingsService;
    if (svc != null) {
      final s = svc.settings;
      if (s.rememberPaths && s.lastWebDavUrl != null) return s.lastWebDavUrl!;
    }
    return '';
  }

  _VaultSource _initialSource() {
    final svc = widget.settingsService;
    if (svc != null && svc.settings.defaultSource == 'webdav') {
      return _VaultSource.webDav;
    }
    return _VaultSource.local;
  }

  bool _useKeyfile = false;
  bool _obscurePassword = true;
  bool _obscureWebDavPassword = true;
  bool _opening = false;
  String? _error;

  @override
  void dispose() {
    _pathController.dispose();
    _webDavUrlController.dispose();
    _webDavUsernameController.dispose();
    _webDavPasswordController.dispose();
    _passwordController.dispose();
    _keyfileController.dispose();
    super.dispose();
  }

  Future<void> _showCreateVaultDialog() async {
    final result = await showDialog<_CreateVaultResult>(
      context: context,
      builder: (_) => _CreateVaultDialog(repository: widget.repository),
    );
    if (result == null || !mounted) {
      return;
    }

    final svc = widget.settingsService;
    if (svc != null && svc.settings.rememberPaths) {
      svc.update((s) {
        s.defaultSource = 'local';
        s.lastLocalPath = result.path;
      });
    }
    setState(() {
      _source = _VaultSource.local;
      _pathController.text = result.path;
    });

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => VaultPage(
          repository: widget.repository,
          initialVault: result.vault,
          keyfilePath: result.keyfilePath,
          settingsService: svc,
        ),
      ),
    );
  }

  String? _validateForm() {
    if (_source == _VaultSource.local) {
      if (_pathController.text.trim().isEmpty) {
        return 'File path is required.';
      }
    } else {
      final url = _webDavUrlController.text.trim();
      if (url.isEmpty) {
        return 'Server URL is required.';
      }
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        return 'Server URL must start with http:// or https:// and include a host.';
      }
      if (_webDavUsernameController.text.trim().isEmpty) {
        return 'Server username is required.';
      }
      if (_webDavPasswordController.text.isEmpty) {
        return 'Server password is required.';
      }
    }

    if (_passwordController.text.isEmpty && !_useKeyfile) {
      return 'Master password or keyfile is required.';
    }

    if (_useKeyfile && _keyfileController.text.trim().isEmpty) {
      return 'Keyfile path is required when keyfile is enabled.';
    }

    return null;
  }

  Future<void> _openVault() async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _opening = true;
      _error = null;
    });

    try {
      final keyfilePath = _useKeyfile ? _keyfileController.text.trim() : null;
      final vault = _source == _VaultSource.local
          ? await widget.repository.openLocal(
              path: _pathController.text.trim(),
              masterPassword: _passwordController.text,
              keyfilePath: keyfilePath,
            )
          : await widget.repository.openWebDav(
              url: _webDavUrlController.text.trim(),
              masterPassword: _passwordController.text,
              username: _webDavUsernameController.text.trim(),
              webDavPassword: _webDavPasswordController.text,
              keyfilePath: keyfilePath,
            );
      if (!mounted) {
        return;
      }
      final svc = widget.settingsService;
      if (svc != null && svc.settings.rememberPaths) {
        if (_source == _VaultSource.local) {
          svc.update((s) {
            s.lastLocalPath = _pathController.text.trim();
          });
        } else {
          svc.update((s) => s.lastWebDavUrl = _webDavUrlController.text.trim());
          // Also set default source
        }
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => VaultPage(
            repository: widget.repository,
            initialVault: vault,
            keyfilePath: keyfilePath,
            settingsService: svc,
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
                    source: _source,
                    pathController: _pathController,
                    webDavUrlController: _webDavUrlController,
                    webDavUsernameController: _webDavUsernameController,
                    webDavPasswordController: _webDavPasswordController,
                    passwordController: _passwordController,
                    keyfileController: _keyfileController,
                    useKeyfile: _useKeyfile,
                    obscurePassword: _obscurePassword,
                    obscureWebDavPassword: _obscureWebDavPassword,
                    opening: _opening,
                    error: _error,
                    onSourceChanged: (value) {
                      setState(() {
                        _source = value;
                        _error = null;
                      });
                    },
                    onUseKeyfileChanged: (value) {
                      setState(() => _useKeyfile = value);
                    },
                    onObscurePasswordChanged: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    onObscureWebDavPasswordChanged: () {
                      setState(
                        () => _obscureWebDavPassword = !_obscureWebDavPassword,
                      );
                    },
                    onClearError: () => setState(() => _error = null),
                    onOpen: _opening ? null : _openVault,
                    settingsService: widget.settingsService,
                    onCreateVault: _showCreateVaultDialog,
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
                      SizedBox(
                        width: 440,
                        child: SingleChildScrollView(child: form),
                      ),
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
        Icon(Icons.lock_outline, size: 40, color: colorScheme.primary),
        const SizedBox(height: 24),
        Text(
          'KeePassY',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Open your vault',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _UnlockForm extends StatelessWidget {
  const _UnlockForm({
    required this.source,
    required this.pathController,
    required this.webDavUrlController,
    required this.webDavUsernameController,
    required this.webDavPasswordController,
    required this.passwordController,
    required this.keyfileController,
    required this.useKeyfile,
    required this.obscurePassword,
    required this.obscureWebDavPassword,
    required this.opening,
    required this.onSourceChanged,
    required this.onUseKeyfileChanged,
    required this.onObscurePasswordChanged,
    required this.onObscureWebDavPasswordChanged,
    required this.onOpen,
    required this.onClearError,
    this.error,
    this.settingsService,
    this.onCreateVault,
  });

  final _VaultSource source;
  final TextEditingController pathController;
  final TextEditingController webDavUrlController;
  final TextEditingController webDavUsernameController;
  final TextEditingController webDavPasswordController;
  final TextEditingController passwordController;
  final TextEditingController keyfileController;
  final bool useKeyfile;
  final bool obscurePassword;
  final bool obscureWebDavPassword;
  final bool opening;
  final ValueChanged<_VaultSource> onSourceChanged;
  final ValueChanged<bool> onUseKeyfileChanged;
  final VoidCallback onObscurePasswordChanged;
  final VoidCallback onObscureWebDavPasswordChanged;
  final VoidCallback? onOpen;
  final VoidCallback onClearError;
  final String? error;
  final SettingsService? settingsService;
  final VoidCallback? onCreateVault;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Unlock vault',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (settingsService != null)
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          SettingsDialog(settingsService: settingsService!),
                    ),
                    icon: const Icon(Icons.settings_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SegmentedButton<_VaultSource>(
              segments: const [
                ButtonSegment<_VaultSource>(
                  value: _VaultSource.local,
                  icon: Icon(Icons.folder_open_outlined),
                  label: Text('Local file'),
                ),
                ButtonSegment<_VaultSource>(
                  value: _VaultSource.webDav,
                  icon: Icon(Icons.cloud_outlined),
                  label: Text('WebDAV'),
                ),
              ],
              selected: {source},
              onSelectionChanged: opening
                  ? null
                  : (values) => onSourceChanged(values.single),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Source'),
            const SizedBox(height: 10),
            if (source == _VaultSource.local)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pathController,
                      decoration: const InputDecoration(
                        labelText: 'File path',
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
              )
            else ...[
              TextField(
                controller: webDavUrlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  prefixIcon: Icon(Icons.cloud_outlined),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: webDavUsernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: webDavPasswordController,
                obscureText: obscureWebDavPassword,
                decoration: InputDecoration(
                  labelText: 'Server password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: obscureWebDavPassword
                        ? 'Show server password'
                        : 'Hide server password',
                    onPressed: onObscureWebDavPasswordChanged,
                    icon: Icon(
                      obscureWebDavPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
            const _SectionLabel('Database credentials'),
            const SizedBox(height: 10),
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
              onChanged: (_) => onClearError(),
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
              const SizedBox(height: 8),
            ] else
              const SizedBox(height: 8),
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
            if (onCreateVault != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton(
                  onPressed: opening ? null : onCreateVault,
                  child: const Text('Create new vault'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
