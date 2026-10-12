import 'dart:async';

import '../../core/errors/app_failure.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/repositories/repositories.dart';
import 'firebase_error_mapper.dart';

/// Broadcasts failures of writes that were already reported to the user as
/// "saved on this device" but were later rejected by the server (e.g. an
/// offline edit that conflicts with a newer change from another device).
class SyncIssueReporter {
  final _controller = StreamController<AppFailure>.broadcast();

  Stream<AppFailure> get issues => _controller.stream;

  void report(AppFailure failure) {
    if (!_controller.isClosed) _controller.add(failure);
  }

  Future<void> dispose() => _controller.close();
}

/// Waits briefly for a Firestore write to be acknowledged.
///
/// Firestore applies writes to the local cache immediately and queues them
/// while offline; the returned future completes only when the server
/// acknowledges. If that takes longer than [ackTimeout] the change is
/// reported as [SaveOutcome.pendingSync]. A later server rejection is routed
/// to [SyncIssueReporter] so it is never silently lost.
class WriteTracker {
  WriteTracker(this.reporter, {this.ackTimeout = const Duration(seconds: 4)});

  final SyncIssueReporter reporter;
  final Duration ackTimeout;

  Future<SaveOutcome> track(
    Future<void> write, {
    bool isUpdate = false,
    String operation = 'write',
  }) async {
    var timedOut = false;
    // Observe the original future so late failures are reported.
    unawaited(
      write.then<void>(
        (_) {},
        onError: (Object e, StackTrace st) {
          if (timedOut) {
            AppLogger.warn('Sync', 'Deferred $operation rejected', e);
            reporter.report(
              FirebaseErrorMapper.firestore(e, isUpdate: isUpdate),
            );
          }
        },
      ),
    );
    try {
      await write.timeout(ackTimeout);
      return SaveOutcome.synced;
    } on TimeoutException {
      timedOut = true;
      return SaveOutcome.pendingSync;
    } catch (e, st) {
      AppLogger.error('Sync', '$operation failed', e, st);
      throw FirebaseErrorMapper.firestore(e, isUpdate: isUpdate);
    }
  }
}
