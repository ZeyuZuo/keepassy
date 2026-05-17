import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../settings/settings.dart';
import '../../settings/settings_service.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.settingsService});

  final SettingsService settingsService;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late Settings _draft;

  @override
  void initState() {
    super.initState();
    _draft = Settings()
      ..themeMode = widget.settingsService.settings.themeMode
      ..themeAccent = widget.settingsService.settings.themeAccent
      ..defaultSource = widget.settingsService.settings.defaultSource
      ..rememberPaths = widget.settingsService.settings.rememberPaths
      ..autoLockMinutes = widget.settingsService.settings.autoLockMinutes
      ..clipboardClearSeconds =
          widget.settingsService.settings.clipboardClearSeconds
      ..lastLocalPath = widget.settingsService.settings.lastLocalPath
      ..lastWebDavUrl = widget.settingsService.settings.lastWebDavUrl;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Settings'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(title: 'App', icon: Icons.settings_outlined),
              const SizedBox(height: 12),
              DropdownButtonFormField<ThemeMode>(
                initialValue: _draft.themeMode,
                decoration: const InputDecoration(labelText: 'Theme'),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('System'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _draft.themeMode = v);
                  widget.settingsService.update((s) {
                    s.themeMode = v;
                  });
                },
              ),
              const SizedBox(height: 16),
              _SectionHeader(
                title: 'Theme color',
                icon: Icons.palette_outlined,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final accent in KeepassYAccent.values)
                    _AccentSwatch(
                      accent: accent,
                      selected: _draft.themeAccent == accent.id,
                      onSelected: () {
                        setState(() => _draft.themeAccent = accent.id);
                        widget.settingsService.update(
                          (s) => s.themeAccent = accent.id,
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _draft.defaultSource,
                decoration: const InputDecoration(
                  labelText: 'Default unlock source',
                ),
                items: const [
                  DropdownMenuItem(value: 'local', child: Text('Local file')),
                  DropdownMenuItem(value: 'webdav', child: Text('WebDAV')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _draft.defaultSource = v);
                  widget.settingsService.update((s) => s.defaultSource = v);
                },
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                title: const Text('Remember last vault path'),
                subtitle: Text(
                  'Does not store master password, keyfile, or WebDAV password.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _draft.rememberPaths,
                onChanged: (v) {
                  setState(() => _draft.rememberPaths = v);
                  widget.settingsService.update((s) => s.rememberPaths = v);
                },
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 24),
              _SectionHeader(title: 'Security', icon: Icons.security_outlined),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _draft.autoLockMinutes,
                decoration: const InputDecoration(
                  labelText: 'Auto-lock after inactivity',
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 minute')),
                  DropdownMenuItem(value: 5, child: Text('5 minutes')),
                  DropdownMenuItem(value: 15, child: Text('15 minutes')),
                  DropdownMenuItem(value: 30, child: Text('30 minutes')),
                  DropdownMenuItem(value: 0, child: Text('Never')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _draft.autoLockMinutes = v);
                  widget.settingsService.update((s) => s.autoLockMinutes = v);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _draft.clipboardClearSeconds,
                decoration: const InputDecoration(
                  labelText: 'Clear clipboard after',
                ),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15 seconds')),
                  DropdownMenuItem(value: 30, child: Text('30 seconds')),
                  DropdownMenuItem(value: 60, child: Text('1 minute')),
                  DropdownMenuItem(value: 120, child: Text('2 minutes')),
                  DropdownMenuItem(value: 0, child: Text('Never')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _draft.clipboardClearSeconds = v);
                  widget.settingsService.update(
                    (s) => s.clipboardClearSeconds = v,
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onSelected,
  });

  final KeepassYAccent accent;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: accent.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(KeepassYRadius.control),
        onTap: onSelected,
        child: AnimatedContainer(
          duration: KeepassYMotion.fast,
          curve: KeepassYMotion.curve,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.seed,
            borderRadius: BorderRadius.circular(KeepassYRadius.control),
            border: Border.all(
              color: selected ? colorScheme.onSurface : colorScheme.outline,
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.seed.withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
