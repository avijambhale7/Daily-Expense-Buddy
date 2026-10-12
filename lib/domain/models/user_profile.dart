import 'package:equatable/equatable.dart';

/// The signed-in user as exposed to the app. Never contains credentials or
/// tokens; session handling stays inside Firebase Authentication.
class UserProfile extends Equatable {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.emailVerified,
    this.displayName,
    this.createdAt,
  });

  final String uid;
  final String email;
  final bool emailVerified;
  final String? displayName;

  /// When the account was created; used so new users are not shown
  /// "incomplete days" from before they signed up.
  final DateTime? createdAt;

  String get firstName {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return '';
    return name.split(RegExp(r'\s+')).first;
  }

  String get initials {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+'));
      return parts.take(2).map((p) => p[0].toUpperCase()).join();
    }
    return email.isNotEmpty ? email[0].toUpperCase() : '?';
  }

  @override
  List<Object?> get props => [
    uid,
    email,
    emailVerified,
    displayName,
    createdAt,
  ];
}
