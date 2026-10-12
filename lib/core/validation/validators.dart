/// Form validators shared by authentication and settings screens.
abstract final class Validators {
  static final _email = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$",
  );

  static const int minPasswordLength = 8;

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email address';
    if (v.length > 254 || !_email.hasMatch(v)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Sign-up password policy: at least 8 characters with a letter and a
  /// number.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Choose a password';
    if (v.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    if (v.length > 128) return 'Password is too long';
    if (!RegExp('[A-Za-z]').hasMatch(v) || !RegExp('[0-9]').hasMatch(v)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  /// Login only checks presence; the server decides validity.
  static String? existingPassword(String? value) =>
      (value == null || value.isEmpty) ? 'Enter your password' : null;

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your name';
    if (v.length > 50) return 'Name must be 50 characters or fewer';
    return null;
  }

  static String? confirmPassword(String? value, String password) =>
      value != password ? 'Passwords do not match' : null;
}
