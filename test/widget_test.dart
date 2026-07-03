import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:emergency_mobile/providers/emergency_provider.dart';
import 'package:emergency_mobile/providers/session_provider.dart';
import 'package:emergency_mobile/screens/login_screen.dart';
import 'package:emergency_mobile/services/api_service.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('muestra la pantalla de login móvil', (WidgetTester tester) async {
    final apiService = ApiService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: apiService),
          ChangeNotifierProvider(create: (_) => SessionProvider(apiService)),
          ChangeNotifierProvider(create: (_) => EmergencyProvider(apiService)),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    expect(find.text('Asistencia Vehicular'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
  });
}
