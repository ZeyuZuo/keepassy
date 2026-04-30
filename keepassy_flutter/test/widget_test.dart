import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepassy_flutter/src/app/keepassy_app.dart';
import 'package:keepassy_flutter/src/models/vault_models.dart';
import 'package:keepassy_flutter/src/repositories/vault_repository.dart';

void main() {
  test('group entry count only includes direct entries', () {
    final group = GroupNode(
      id: 'root',
      name: 'Database',
      entries: [EntrySummary(id: 'root-entry')],
      groups: [
        GroupNode(
          id: 'child',
          name: 'Entertainment',
          entries: [
            EntrySummary(id: 'child-1'),
            EntrySummary(id: 'child-2'),
          ],
          groups: [],
        ),
      ],
    );

    expect(group.entryCount, 1);
    expect(group.totalEntryCount, 3);
  });

  test('WebDAV URL validation requires http or https URL', () {
    expect(
      () => validateWebDavUrl(''),
      throwsA(isA<VaultRepositoryException>()),
    );
    expect(
      () => validateWebDavUrl('ftp://example.com/vault.kdbx'),
      throwsA(isA<VaultRepositoryException>()),
    );
    expect(
      () => validateWebDavUrl('https://example.com/vault.kdbx'),
      returnsNormally,
    );
  });

  // --- Header ---

  testWidgets('shows operational header', (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    expect(find.text('KeePassY'), findsOneWidget);
    expect(find.text('Open your vault'), findsOneWidget);
    expect(find.text('Unlock vault'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    // No marketing copy
    expect(
      find.text('A desktop vault surface for the Rust KeePass backend.'),
      findsNothing,
    );
    // No capability badges
    expect(find.text('Local KDBX'), findsNothing);
    expect(find.text('Keyfile ready'), findsNothing);
    expect(find.text('JSON FFI boundary'), findsNothing);
  });

  // --- Form structure ---

  testWidgets('section labels and divider are present', (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Database credentials'), findsOneWidget);
    expect(find.byType(Divider), findsAtLeastNWidgets(1));
  });

  // --- Source switching ---

  testWidgets('local source shows file path and hides server fields',
      (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    // Default is local source
    expect(find.text('File path'), findsOneWidget);
    expect(find.text('Server URL'), findsNothing);
    expect(find.text('Username'), findsNothing);
    expect(find.text('Server password'), findsNothing);
  });

  testWidgets('WebDAV source shows server fields and hides file path',
      (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();

    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Server password'), findsOneWidget);
    expect(find.text('File path'), findsNothing);
  });

  testWidgets('master password and keyfile visible regardless of source',
      (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    // Local source
    expect(find.text('Master password'), findsOneWidget);
    expect(find.text('Use keyfile'), findsOneWidget);

    // Switch to WebDAV
    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();

    expect(find.text('Master password'), findsOneWidget);
    expect(find.text('Use keyfile'), findsOneWidget);
  });

  // --- Validation ---

  Future<void> tapUnlock(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows validation error for empty master password',
      (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    // Path is pre-filled with a default value, master password is empty
    await tapUnlock(tester);

    expect(find.text('Master password is required.'), findsOneWidget);
  });

  testWidgets('shows validation error for empty WebDAV URL', (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    // Switch to WebDAV — URL is empty
    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();

    // Fill in master password but leave URL empty
    await tester.enterText(
      find.widgetWithText(TextField, 'Master password'),
      'masterpass',
    );

    await tapUnlock(tester);

    expect(find.text('Server URL is required.'), findsOneWidget);
  });

  testWidgets('clears validation error on source switch', (tester) async {
    final repo = MockVaultRepository();
    // Use a wide viewport so the non-compact layout is used and the
    // MaterialBanner does not overlap the form controls.
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 2.0;
    });
    await tester.pumpWidget(KeepassYApp(repository: repo));

    // Switch to WebDAV, leave fields empty, trigger error
    await tester.tap(find.text('WebDAV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Server URL is required.'), findsOneWidget);

    // Switch back to local — error should clear
    await tester.tap(find.text('Local file'));
    await tester.pumpAndSettle();
    expect(find.text('Server URL is required.'), findsNothing);
  });

  testWidgets('clears validation error when typing in master password',
      (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    // Path is pre-filled, master password is empty — tap Unlock
    await tapUnlock(tester);
    expect(find.text('Master password is required.'), findsOneWidget);

    // Type in master password — error should clear via onChanged
    await tester.ensureVisible(
      find.widgetWithText(TextField, 'Master password'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Master password'),
      'p',
    );
    await tester.pumpAndSettle();

    expect(find.text('Master password is required.'), findsNothing);
  });
}
