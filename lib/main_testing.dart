import 'main.dart' as application;

/// Dedicated test build entrypoint. Missing defines can never select production.
Future<void> main() => application.startApplication(testingEntrypoint: true);
