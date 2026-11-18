import 'package:client/features/onboarding/pages/onboarding_page.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('English onboarding renders setup and validation copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: S.localizationsDelegates,
          supportedLocales: S.supportedLocales,
          home: OnboardingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trustworthy RAG knowledge workbench'), findsOneWidget);
    final serverMode = find.text('Connect to a server');
    await tester.ensureVisible(serverMode);
    await tester.tap(serverMode);
    await tester.pumpAndSettle();

    final testConnection = find.text('Test connection');
    await tester.ensureVisible(testConnection);
    await tester.tap(testConnection);
    await tester.pumpAndSettle();

    expect(find.text('Enter the server address'), findsOneWidget);
  });
}
