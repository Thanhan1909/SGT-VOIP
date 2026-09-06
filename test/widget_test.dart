import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_sip_softphone/core/services/sip_manager.dart';
import 'package:flutter_sip_softphone/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('SGTSoftphoneApp UI smoke test', (WidgetTester tester) async {
    final sipManager = SipManager();

    await tester.pumpWidget(
      ChangeNotifierProvider<SipManager>.value(
        value: sipManager,
        child: const SGTSoftphoneApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify SGT Softphone App bar title is present
    expect(find.text('SGT Softphone'), findsOneWidget);
    // Verify dialpad numbers exist
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.phone), findsOneWidget);
  });
}
