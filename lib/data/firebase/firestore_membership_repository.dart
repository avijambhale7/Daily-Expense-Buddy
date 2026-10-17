import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/models/membership.dart';
import '../../domain/models/premium_entitlement.dart';
import '../../domain/repositories/repositories.dart';
import 'firebase_error_mapper.dart';
import 'firestore_serializers.dart';

/// Shared Firestore paths for membership data. Top-level (not under
/// `users/{uid}`) so admins can query across users; the security rules
/// limit each user to their own documents.
abstract final class MembershipPaths {
  static const requests = 'premium_requests';
  static const bans = 'bans';
  static const config = 'app_config/premium';

  /// Readable only by admins: a successful read proves admin rights.
  static const adminProbe = 'admin/probe';

  static String entitlement(String uid) => 'users/$uid/entitlements/premium';
}

PremiumRequest? _requestFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
  final d = doc.data();
  if (d == null) return null;
  final type = PremiumRequestType.fromKey(d['type']);
  final uid = d['uid'];
  if (type == null || uid is! String) return null;
  DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
  String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
  return PremiumRequest(
    id: doc.id,
    uid: uid,
    email: str(d['email']) ?? '',
    displayName: str(d['displayName']) ?? '',
    type: type,
    status: PremiumRequestStatus.fromKey(d['status']),
    message: str(d['message']),
    upiRef: str(d['upiRef']),
    amountPaise: d['amountPaise'] is int ? d['amountPaise'] as int : null,
    createdAt: ts(d['createdAt']),
    decidedAt: ts(d['decidedAt']),
    decidedBy: str(d['decidedBy']),
    adminNote: str(d['adminNote']),
  );
}

List<PremiumRequest> _requests(QuerySnapshot<Map<String, dynamic>> snap) => [
  for (final doc in snap.docs) ?_requestFromDoc(doc),
];

PremiumConfig _configFrom(Map<String, dynamic>? d) {
  if (d == null) return const PremiumConfig();
  int intOr(Object? v, int fallback) => v is int && v > 0 ? v : fallback;
  return PremiumConfig(
    pricePaise: intOr(d['pricePaise'], PremiumConfig.defaultPricePaise),
    upiId: d['upiId'] is String ? d['upiId'] as String : '',
    payeeName: d['payeeName'] is String && (d['payeeName'] as String).isNotEmpty
        ? d['payeeName'] as String
        : 'Daily Expense Buddy',
    trialDays: intOr(d['trialDays'], PremiumConfig.defaultTrialDays),
  );
}

BanInfo _banFrom(Map<String, dynamic> d) => BanInfo(
  reason: d['reason'] is String ? d['reason'] as String : null,
  bannedAt: d['bannedAt'] is Timestamp
      ? (d['bannedAt'] as Timestamp).toDate()
      : null,
  bannedBy: d['bannedBy'] is String ? d['bannedBy'] as String : null,
);

Never _fail(String op, Object e) {
  AppLogger.warn('Membership', '$op failed', e);
  throw FirebaseErrorMapper.firestore(e);
}

class FirestoreMembershipRepository implements MembershipRepository {
  FirestoreMembershipRepository(
    this._db, {
    required this.uid,
    required this.email,
    required this.displayName,
    this.checkAdmin = true,
  });

  final FirebaseFirestore _db;

  /// Off in tests: the in-memory database has no rules, so the probe would
  /// succeed for everyone.
  final bool checkAdmin;
  final String uid;
  final String email;
  final String displayName;

  @override
  Future<bool> isAdmin() async {
    if (!checkAdmin) return false;
    try {
      await _db
          .doc(MembershipPaths.adminProbe)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      // permission-denied for everyone who is not an admin (and offline).
      return false;
    }
  }

  @override
  Stream<BanInfo?> watchBan() => _db
      .collection(MembershipPaths.bans)
      .doc(uid)
      .snapshots()
      .map((s) => s.exists ? _banFrom(s.data() ?? const {}) : null)
      .handleError((Object e) => AppLogger.warn('Membership', 'Ban', e));

  @override
  Stream<PremiumConfig> watchConfig() => _db
      .doc(MembershipPaths.config)
      .snapshots()
      .map((s) => _configFrom(s.data()))
      .handleError((Object e) => AppLogger.warn('Membership', 'Config', e));

  @override
  Stream<List<PremiumRequest>> watchMyRequests() => _db
      .collection(MembershipPaths.requests)
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(_requests)
      .handleError((Object e) => _fail('My requests', e));

  Future<void> _create(Map<String, Object?> fields) async {
    try {
      await _db.collection(MembershipPaths.requests).add({
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'status': PremiumRequestStatus.pending.key,
        'createdAt': FieldValue.serverTimestamp(),
        ...fields,
      });
    } catch (e) {
      _fail('Create request', e);
    }
  }

  @override
  Future<void> requestTrial({String? message}) => _create({
    'type': PremiumRequestType.trial.key,
    if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
  });

  @override
  Future<void> requestActivation({
    required String upiRef,
    required int amountPaise,
    String? message,
  }) => _create({
    'type': PremiumRequestType.payment.key,
    'upiRef': upiRef.trim(),
    'amountPaise': amountPaise,
    if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
  });
}

class FirestoreAdminRepository implements AdminRepository {
  FirestoreAdminRepository(this._db, {required this.adminEmail});

  final FirebaseFirestore _db;
  final String adminEmail;

  CollectionReference<Map<String, dynamic>> get _requestsCol =>
      _db.collection(MembershipPaths.requests);

  @override
  Stream<List<PremiumRequest>> watchRequests({bool pendingOnly = false}) {
    Query<Map<String, dynamic>> q = _requestsCol;
    if (pendingOnly) {
      q = q.where('status', isEqualTo: PremiumRequestStatus.pending.key);
    }
    return q
        .orderBy('createdAt', descending: true)
        .limit(500)
        .snapshots()
        .map(_requests)
        .handleError((Object e) => _fail('Requests', e));
  }

  @override
  Stream<List<AdminUser>> watchUsers() => _db
      .collection('users')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map(
        (snap) => [
          for (final doc in snap.docs)
            AdminUser(
              uid: doc.id,
              email: doc.data()['email'] is String
                  ? doc.data()['email'] as String
                  : '',
              displayName: doc.data()['displayName'] is String
                  ? doc.data()['displayName'] as String
                  : '',
              createdAt: doc.data()['createdAt'] is Timestamp
                  ? (doc.data()['createdAt'] as Timestamp).toDate()
                  : null,
            ),
        ],
      )
      .handleError((Object e) => _fail('Users', e));

  @override
  Stream<Set<String>> watchBannedUids() => _db
      .collection(MembershipPaths.bans)
      .snapshots()
      .map((snap) => {for (final d in snap.docs) d.id})
      .handleError((Object e) => _fail('Bans', e));

  Future<PremiumEntitlement> _entitlement(String uid) async {
    final snap = await _db.doc(MembershipPaths.entitlement(uid)).get();
    return FirestoreSerializers.entitlementFromMap(snap.data());
  }

  @override
  Future<AdminUserDetail> userDetail(String uid) async {
    try {
      final results = await Future.wait([
        _entitlement(uid),
        _db.collection(MembershipPaths.bans).doc(uid).get(),
        _requestsCol
            .where('uid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get(),
      ]);
      final ban = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      return AdminUserDetail(
        entitlement: results[0] as PremiumEntitlement,
        ban: ban.exists ? _banFrom(ban.data() ?? const {}) : null,
        requests: _requests(results[2] as QuerySnapshot<Map<String, dynamic>>),
      );
    } catch (e) {
      _fail('User detail', e);
    }
  }

  Map<String, Object?> _entitlementFields({
    required DateTime until,
    required String source,
    int? pricePaise,
  }) => {
    'active': true,
    'expiresAt': Timestamp.fromDate(until),
    'source': source,
    'grantedBy': adminEmail,
    'pricePaise': ?pricePaise,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  @override
  Future<void> approve(
    PremiumRequest request, {
    required PremiumConfig config,
  }) async {
    try {
      final now = DateTime.now();
      final current = await _entitlement(request.uid);
      final currentExpiry = current.isPremium(now) ? current.expiresAt : null;
      final until = request.type == PremiumRequestType.trial
          ? PremiumGrant.trialExpiry(
              now: now,
              currentExpiry: currentExpiry,
              trialDays: config.trialDays,
            )
          : PremiumGrant.paidExpiry(now: now, currentExpiry: currentExpiry);
      final batch = _db.batch()
        ..update(_requestsCol.doc(request.id), {
          'status': PremiumRequestStatus.approved.key,
          'decidedAt': FieldValue.serverTimestamp(),
          'decidedBy': adminEmail,
        })
        ..set(
          _db.doc(MembershipPaths.entitlement(request.uid)),
          _entitlementFields(
            until: until,
            source: request.type == PremiumRequestType.trial ? 'trial' : 'upi',
            pricePaise: request.type == PremiumRequestType.payment
                ? request.amountPaise
                : null,
          ),
        );
      await batch.commit();
    } catch (e) {
      _fail('Approve', e);
    }
  }

  @override
  Future<void> reject(PremiumRequest request, {String? note}) async {
    try {
      await _requestsCol.doc(request.id).update({
        'status': PremiumRequestStatus.rejected.key,
        'decidedAt': FieldValue.serverTimestamp(),
        'decidedBy': adminEmail,
        if (note != null && note.trim().isNotEmpty) 'adminNote': note.trim(),
      });
    } catch (e) {
      _fail('Reject', e);
    }
  }

  @override
  Future<void> setPremium(String uid, DateTime? until) async {
    try {
      final ref = _db.doc(MembershipPaths.entitlement(uid));
      if (until == null) {
        await ref.delete();
      } else {
        await ref.set(_entitlementFields(until: until, source: 'manual'));
      }
    } catch (e) {
      _fail('Set premium', e);
    }
  }

  @override
  Future<void> ban(String uid, {String? reason}) async {
    try {
      await _db.collection(MembershipPaths.bans).doc(uid).set({
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        'bannedAt': FieldValue.serverTimestamp(),
        'bannedBy': adminEmail,
      });
    } catch (e) {
      _fail('Ban', e);
    }
  }

  @override
  Future<void> unban(String uid) async {
    try {
      await _db.collection(MembershipPaths.bans).doc(uid).delete();
    } catch (e) {
      _fail('Unban', e);
    }
  }

  @override
  Future<void> saveConfig(PremiumConfig config) async {
    try {
      await _db.doc(MembershipPaths.config).set({
        'pricePaise': config.pricePaise,
        'upiId': config.upiId.trim(),
        'payeeName': config.payeeName.trim(),
        'trialDays': config.trialDays,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _fail('Save settings', e);
    }
  }
}
