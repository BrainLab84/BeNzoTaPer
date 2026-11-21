import 'dart:async';

import 'package:tapering_buddy/app_state.dart';

/// Alle bestehenden Tests laufen auf Deutsch und überspringen die Sprachwahl.
/// (Tests zur Sprachwahl setzen `AppState.spracheStandard = null`.)
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppState.spracheStandard = 'de';
  await testMain();
}
