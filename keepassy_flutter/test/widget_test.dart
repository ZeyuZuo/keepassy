import 'package:flutter_test/flutter_test.dart';
import 'package:keepassy_flutter/src/app/keepassy_app.dart';
import 'package:keepassy_flutter/src/repositories/vault_repository.dart';

void main() {
  testWidgets('starts on the unlock surface', (tester) async {
    final repo = MockVaultRepository();
    await tester.pumpWidget(KeepassYApp(repository: repo));

    expect(find.text('KeePassY'), findsOneWidget);
    expect(find.text('Open vault'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
