import 'package:flutter_test/flutter_test.dart';
import 'package:keepassy_flutter/src/app/keepassy_app.dart';
import 'package:keepassy_flutter/src/models/vault_models.dart';
import 'package:keepassy_flutter/src/repositories/vault_repository.dart';

void main() {
  test('group entry count only includes direct entries', () {
    const group = GroupNode(
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

  testWidgets('starts on the unlock surface', (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    expect(find.text('KeePassY'), findsOneWidget);
    expect(find.text('Open vault'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
