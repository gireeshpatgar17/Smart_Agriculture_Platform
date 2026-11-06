import 'package:flutter_test/flutter_test.dart';
import 'package:smart_agriculture/app/app.dart';

void main() {
  testWidgets('Smart Agriculture App navigation tabs smoke test', (WidgetTester tester) async {
    // Build the app and pump initial frame
    await tester.pumpWidget(const SmartAgricultureApp());
    await tester.pump();

    // Verify all core navigation tabs are present
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Irrigation'), findsWidgets);
    expect(find.text('AI Doctor'), findsWidgets);
    expect(find.text('Farm'), findsWidgets);
  });
}
