import 'package:equatable/equatable.dart';

/// Premium entitlement for the signed-in user.
///
/// Stored at `users/{uid}/entitlements/premium` and **writable only by a
/// trusted backend** (Firestore rules deny client writes). The app never
/// grants itself premium; a client-side flag is not proof of purchase.
class PremiumEntitlement extends Equatable {
  const PremiumEntitlement({
    this.active = false,
    this.expiresAt,
    this.source,
    this.developerPreview = false,
  });

  static const none = PremiumEntitlement();

  final bool active;
  final DateTime? expiresAt;

  /// e.g. `play`, `app_store`, `manual`.
  final String? source;

  /// True only in debug builds started with
  /// `--dart-define=PREMIUM_PREVIEW=true`, so developers can test premium UI.
  /// Never enabled in release builds.
  final bool developerPreview;

  bool isPremium(DateTime now) {
    if (developerPreview) return true;
    if (!active) return false;
    final exp = expiresAt;
    return exp == null || exp.isAfter(now);
  }

  @override
  List<Object?> get props => [active, expiresAt, source, developerPreview];
}
