import 'package:equatable/equatable.dart';

import 'premium_entitlement.dart';

/// Price in rupees for display, e.g. ₹99 or ₹99.50.
String rupees(int paise) => paise % 100 == 0
    ? '₹${paise ~/ 100}'
    : '₹${(paise / 100).toStringAsFixed(2)}';

/// Price and payment details for premium, set by an admin in the admin
/// console (`app_config/premium`). Kept in the database so the price can
/// change without an app update.
class PremiumConfig extends Equatable {
  const PremiumConfig({
    this.pricePaise = defaultPricePaise,
    this.upiId = '',
    this.payeeName = 'Daily Expense Buddy',
    this.trialDays = defaultTrialDays,
  });

  static const defaultPricePaise = 9900;
  static const defaultTrialDays = 3;
  static const premiumDays = 365;

  /// Yearly price in paise (₹99 = 9900).
  final int pricePaise;

  /// Where users send the UPI payment; empty until the admin sets it.
  final String upiId;
  final String payeeName;

  /// Length of an approved free trial.
  final int trialDays;

  bool get canPay => upiId.isNotEmpty;

  /// `upi://pay` link that opens the user's UPI app with the amount filled.
  Uri upiPayUri({required String note}) => Uri(
    scheme: 'upi',
    host: 'pay',
    queryParameters: {
      'pa': upiId,
      'pn': payeeName,
      'am': (pricePaise / 100).toStringAsFixed(2),
      'cu': 'INR',
      'tn': note,
    },
  );

  PremiumConfig copyWith({
    int? pricePaise,
    String? upiId,
    String? payeeName,
    int? trialDays,
  }) => PremiumConfig(
    pricePaise: pricePaise ?? this.pricePaise,
    upiId: upiId ?? this.upiId,
    payeeName: payeeName ?? this.payeeName,
    trialDays: trialDays ?? this.trialDays,
  );

  @override
  List<Object?> get props => [pricePaise, upiId, payeeName, trialDays];
}

enum PremiumRequestType {
  trial('trial', 'Free trial'),
  payment('payment', 'Payment');

  const PremiumRequestType(this.key, this.label);
  final String key;
  final String label;

  static PremiumRequestType? fromKey(Object? key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

enum PremiumRequestStatus {
  pending('pending', 'Pending'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Rejected');

  const PremiumRequestStatus(this.key, this.label);
  final String key;
  final String label;

  static PremiumRequestStatus fromKey(Object? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return pending;
  }
}

/// A user's request for a free trial or for activation after paying by UPI.
/// Stored at `premium_requests/{id}`; users create and read their own,
/// only admins decide them.
class PremiumRequest extends Equatable {
  const PremiumRequest({
    required this.id,
    required this.uid,
    required this.email,
    required this.displayName,
    required this.type,
    required this.status,
    this.message,
    this.upiRef,
    this.amountPaise,
    this.createdAt,
    this.decidedAt,
    this.decidedBy,
    this.adminNote,
  });

  final String id;
  final String uid;
  final String email;
  final String displayName;
  final PremiumRequestType type;
  final PremiumRequestStatus status;
  final String? message;

  /// UPI transaction / UTR reference the user entered (payments only).
  final String? upiRef;
  final int? amountPaise;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;
  final String? adminNote;

  bool get isPending => status == PremiumRequestStatus.pending;

  @override
  List<Object?> get props => [
    id,
    uid,
    email,
    displayName,
    type,
    status,
    message,
    upiRef,
    amountPaise,
    createdAt,
    decidedAt,
    decidedBy,
    adminNote,
  ];
}

/// A banned account (`bans/{uid}`). While it exists the security rules
/// deny all access to that user's data.
class BanInfo extends Equatable {
  const BanInfo({this.reason, this.bannedAt, this.bannedBy});

  final String? reason;
  final DateTime? bannedAt;
  final String? bannedBy;

  @override
  List<Object?> get props => [reason, bannedAt, bannedBy];
}

/// One row of the admin's user list.
class AdminUser extends Equatable {
  const AdminUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.createdAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final DateTime? createdAt;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        email.toLowerCase().contains(q) ||
        displayName.toLowerCase().contains(q);
  }

  @override
  List<Object?> get props => [uid, email, displayName, createdAt];
}

/// Everything the admin sees about one user.
class AdminUserDetail extends Equatable {
  const AdminUserDetail({
    required this.entitlement,
    required this.ban,
    required this.requests,
  });

  final PremiumEntitlement entitlement;
  final BanInfo? ban;

  /// Newest first.
  final List<PremiumRequest> requests;

  int get trialsApproved => requests
      .where(
        (r) =>
            r.type == PremiumRequestType.trial &&
            r.status == PremiumRequestStatus.approved,
      )
      .length;

  @override
  List<Object?> get props => [entitlement, ban, requests];
}

/// Pure rules for how long premium lasts after an admin decision, so they
/// can be tested without Firestore.
abstract final class PremiumGrant {
  /// A trial never shortens premium the user already has.
  static DateTime trialExpiry({
    required DateTime now,
    required DateTime? currentExpiry,
    required int trialDays,
  }) {
    final trialEnd = now.add(Duration(days: trialDays));
    return currentExpiry != null && currentExpiry.isAfter(trialEnd)
        ? currentExpiry
        : trialEnd;
  }

  /// A year is added on top of any premium time still left.
  static DateTime paidExpiry({
    required DateTime now,
    required DateTime? currentExpiry,
    int days = PremiumConfig.premiumDays,
  }) {
    final from = currentExpiry != null && currentExpiry.isAfter(now)
        ? currentExpiry
        : now;
    return from.add(Duration(days: days));
  }

  /// "Request #n from this user", counting from their oldest request.
  static Map<String, int> requestNumbers(Iterable<PremiumRequest> requests) {
    final byUser = <String, List<PremiumRequest>>{};
    for (final r in requests) {
      byUser.putIfAbsent(r.uid, () => []).add(r);
    }
    final numbers = <String, int>{};
    for (final list in byUser.values) {
      list.sort((a, b) {
        final at = a.createdAt, bt = b.createdAt;
        if (at == null && bt == null) return a.id.compareTo(b.id);
        if (at == null) return 1; // not yet synced: newest
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
      for (var i = 0; i < list.length; i++) {
        numbers[list[i].id] = i + 1;
      }
    }
    return numbers;
  }
}
