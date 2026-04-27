import 'package:flutter_test/flutter_test.dart';
import 'package:keepassy_flutter/src/app/keepassy_app.dart';

void main() {
  testWidgets('starts on the unlock surface', (tester) async {
    await tester.pumpWidget(const KeepassYApp());

    expect(find.text('KeePassY'), findsOneWidget);
    expect(find.text('Open vault'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
