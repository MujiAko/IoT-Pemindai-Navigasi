import 'package:flutter_test/flutter_test.dart';
import 'package:iot_pemindai_navigasi/main.dart';

void main() {
  testWidgets('App launches and shows Home', (tester) async {
    await tester.pumpWidget(const NavApp());
    expect(find.text('ESP32 Maps'), findsOneWidget);
  });
}