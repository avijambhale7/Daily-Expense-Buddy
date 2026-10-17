import 'package:daily/domain/models/membership.dart';
import 'package:flutter_test/flutter_test.dart';

PremiumRequest _req(String id, String uid, DateTime? at) => PremiumRequest(
  id: id,
  uid: uid,
  email: '$uid@x.com',
  displayName: uid,
  type: PremiumRequestType.trial,
  status: PremiumRequestStatus.pending,
  createdAt: at,
);

void main() {
  final now = DateTime(2026, 10, 17, 12);

  group('PremiumGrant', () {
    test('a trial lasts the configured number of days', () {
      expect(
        PremiumGrant.trialExpiry(now: now, currentExpiry: null, trialDays: 3),
        DateTime(2026, 10, 20, 12),
      );
    });

    test('a trial never shortens premium the user already has', () {
      final later = DateTime(2027, 1, 1);
      expect(
        PremiumGrant.trialExpiry(now: now, currentExpiry: later, trialDays: 3),
        later,
      );
    });

    test('a payment adds a year, on top of time still left', () {
      expect(
        PremiumGrant.paidExpiry(now: now, currentExpiry: null),
        now.add(const Duration(days: 365)),
      );
      final trialEnd = DateTime(2026, 10, 19);
      expect(
        PremiumGrant.paidExpiry(now: now, currentExpiry: trialEnd),
        trialEnd.add(const Duration(days: 365)),
      );
      // Expired premium starts again from today.
      expect(
        PremiumGrant.paidExpiry(now: now, currentExpiry: DateTime(2026, 1, 1)),
        now.add(const Duration(days: 365)),
      );
    });

    test('requests are numbered per user, oldest first', () {
      final numbers = PremiumGrant.requestNumbers([
        _req('c', 'ann', DateTime(2026, 10, 3)),
        _req('a', 'ann', DateTime(2026, 10, 1)),
        _req('x', 'bob', DateTime(2026, 10, 2)),
        _req('b', 'ann', DateTime(2026, 10, 2)),
        _req('new', 'ann', null),
      ]);
      expect(numbers['a'], 1);
      expect(numbers['b'], 2);
      expect(numbers['c'], 3);
      expect(numbers['new'], 4, reason: 'not yet synced counts as newest');
      expect(numbers['x'], 1);
    });
  });

  group('PremiumConfig', () {
    test('defaults to ₹99 a year and a 3-day trial', () {
      const c = PremiumConfig();
      expect(rupees(c.pricePaise), '₹99');
      expect(c.trialDays, 3);
      expect(c.canPay, isFalse);
    });

    test('builds a UPI payment link with the amount filled in', () {
      const c = PremiumConfig(upiId: 'buddy@okaxis', payeeName: 'Buddy');
      final uri = c.upiPayUri(note: 'Premium');
      expect(uri.scheme, 'upi');
      expect(uri.queryParameters['pa'], 'buddy@okaxis');
      expect(uri.queryParameters['am'], '99.00');
      expect(uri.queryParameters['cu'], 'INR');
    });

    test('rupees formats whole and fractional prices', () {
      expect(rupees(14900), '₹149');
      expect(rupees(9950), '₹99.50');
    });
  });
}
