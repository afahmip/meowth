import 'package:flutter_test/flutter_test.dart';
import 'package:meowth/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MeowtApp());
    expect(find.text('Meowth'), findsWidgets);
  });
}
