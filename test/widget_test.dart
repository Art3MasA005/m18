import 'package:flutter_test/flutter_test.dart';
import 'package:real_time_location_tracker/main.dart';

void main() {
  testWidgets('App initializes smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const RealTimeLocationTrackerApp());
    expect(find.text('Real-Time Location Tracker'), findsOneWidget);
  });
}
