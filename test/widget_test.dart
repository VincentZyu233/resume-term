import 'package:flutter_test/flutter_test.dart';

import 'package:resume_term/main.dart';

void main() {
  testWidgets('app renders title', (WidgetTester tester) async {
    await tester.pumpWidget(const ResumeTermApp());

    expect(find.text('Resume-Term'), findsOneWidget);
  });
}
