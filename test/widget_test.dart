import 'package:flutter_test/flutter_test.dart';

import 'package:diandi_notes/main.dart';

void main() {
  testWidgets('renders notes home', (WidgetTester tester) async {
    await tester.pumpWidget(const DiandiNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('Diandi Notes'), findsOneWidget);
    expect(find.text('Nouvelle note'), findsOneWidget);
  });
}
