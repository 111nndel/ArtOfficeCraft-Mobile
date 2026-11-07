import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Let real disk/isolate work finish while still draining widget fake microtasks.
Future<void> waitDraftIO(
  WidgetTester tester,
  Future<void> Function() operation,
) async {
  var done = false;
  Object? failure;
  StackTrace? trace;
  unawaited(
    operation().then(
      (_) {
        done = true;
      },
      onError: (Object error, StackTrace stack) {
        failure = error;
        trace = stack;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 400 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  if (!done) throw TimeoutException('Draft disk operation did not complete');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}
