import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/membership.dart';
import '../../domain/repositories/repositories.dart';

class MembershipState extends Equatable {
  const MembershipState({
    this.adminChecked = false,
    this.isAdmin = false,
    this.ban,
    this.config = const PremiumConfig(),
    this.requests = const [],
  });

  /// False until the admin check has answered (the app waits for it so an
  /// admin never sees the normal app flash first).
  final bool adminChecked;
  final bool isAdmin;

  /// Non-null while this account is banned.
  final BanInfo? ban;
  final PremiumConfig config;

  /// This user's premium requests, newest first.
  final List<PremiumRequest> requests;

  bool get hasPendingTrial =>
      requests.any((r) => r.isPending && r.type == PremiumRequestType.trial);
  bool get hasPendingPayment =>
      requests.any((r) => r.isPending && r.type == PremiumRequestType.payment);

  MembershipState copyWith({
    bool? adminChecked,
    bool? isAdmin,
    BanInfo? Function()? ban,
    PremiumConfig? config,
    List<PremiumRequest>? requests,
  }) => MembershipState(
    adminChecked: adminChecked ?? this.adminChecked,
    isAdmin: isAdmin ?? this.isAdmin,
    ban: ban != null ? ban() : this.ban,
    config: config ?? this.config,
    requests: requests ?? this.requests,
  );

  @override
  List<Object?> get props => [adminChecked, isAdmin, ban, config, requests];
}

/// Admin status, ban status, premium settings and the user's own requests.
class MembershipCubit extends Cubit<MembershipState> {
  MembershipCubit(this._repo) : super(const MembershipState()) {
    _subs = [
      _repo.watchBan().listen((b) => emit(state.copyWith(ban: () => b))),
      _repo.watchConfig().listen((c) => emit(state.copyWith(config: c))),
      _repo.watchMyRequests().listen(
        (r) => emit(state.copyWith(requests: r)),
        onError: (Object _) {},
      ),
    ];
    unawaited(_checkAdmin());
  }

  final MembershipRepository _repo;
  late final List<StreamSubscription<Object?>> _subs;

  Future<void> _checkAdmin() async {
    final admin = await _repo.isAdmin();
    if (!isClosed) emit(state.copyWith(adminChecked: true, isAdmin: admin));
  }

  /// Sends a free-trial request. Throws [AppFailure] on failure.
  Future<void> requestTrial({String? message}) =>
      _repo.requestTrial(message: message);

  /// Sends a "I've paid, please activate" request with the UPI reference.
  Future<void> requestActivation({
    required String upiRef,
    String? message,
  }) async {
    final ref = upiRef.trim();
    if (ref.length < 6 || ref.length > 40) {
      throw const AppFailure(
        FailureKind.unknown,
        'Enter the UPI transaction ID (UTR) shown in your UPI app.',
      );
    }
    return _repo.requestActivation(
      upiRef: ref,
      amountPaise: state.config.pricePaise,
      message: message,
    );
  }

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    return super.close();
  }
}
