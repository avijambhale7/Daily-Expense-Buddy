// Security rules tests for firestore.rules (run against the Firestore emulator).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let env;

before(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({
    projectId: 'demo-daily-expense-buddy',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
      host,
      port: Number(port),
    },
  });
});

after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const alice = () => env.authenticatedContext('alice', { email_verified: true }).firestore();
const bob = () => env.authenticatedContext('bob', { email_verified: true }).firestore();
const unverified = () => env.authenticatedContext('alice', { email_verified: false }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

const expense = (overrides = {}) => ({
  amountMinor: 12050,
  currency: 'INR',
  categoryId: 'food',
  date: '2025-10-14',
  note: 'Lunch',
  merchant: null,
  paymentMethod: 'cash',
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  version: 1,
  ...overrides,
});

async function seedExpense(id = 'e1', data = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/alice/expenses/${id}`), {
      ...expense(),
      createdAt: new Date('2025-10-14T10:00:00Z'),
      updatedAt: new Date('2025-10-14T10:00:00Z'),
      ...data,
    });
  });
}

describe('expenses', () => {
  test('owner with verified email can create and read', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/expenses/e1'), expense()));
    await assertSucceeds(getDoc(doc(alice(), 'users/alice/expenses/e1')));
    await assertSucceeds(
      getDocs(query(collection(alice(), 'users/alice/expenses'), where('date', '>=', '2025-10-01'))),
    );
  });

  test('other users, unverified users and anonymous users are denied', async () => {
    await seedExpense();
    await assertFails(getDoc(doc(bob(), 'users/alice/expenses/e1')));
    await assertFails(getDocs(collection(bob(), 'users/alice/expenses')));
    await assertFails(setDoc(doc(bob(), 'users/alice/expenses/e2'), expense()));
    await assertFails(deleteDoc(doc(bob(), 'users/alice/expenses/e1')));
    await assertFails(getDoc(doc(unverified(), 'users/alice/expenses/e1')));
    await assertFails(setDoc(doc(unverified(), 'users/alice/expenses/e3'), expense()));
    await assertFails(getDoc(doc(anon(), 'users/alice/expenses/e1')));
  });

  test('invalid amounts are rejected', async () => {
    for (const amountMinor of [0, -100, 12.5, '100', null, 1e16]) {
      await assertFails(
        setDoc(doc(alice(), 'users/alice/expenses/bad'), expense({ amountMinor })),
        `amountMinor=${amountMinor}`,
      );
    }
  });

  test('invalid fields are rejected', async () => {
    const bad = [
      { date: '2025-13-01' },
      { date: '14/10/2025' },
      { date: '1999-12-31' },
      { currency: 'rupees' },
      { categoryId: '' },
      { note: 'x'.repeat(201) },
      { paymentMethod: 'bitcoin' },
      { uid: 'bob' },
      { version: 2 },
      { createdAt: new Date('2020-01-01') },
    ];
    for (const b of bad) {
      await assertFails(setDoc(doc(alice(), 'users/alice/expenses/bad'), expense(b)), JSON.stringify(b));
    }
    const { categoryId, ...missing } = expense();
    await assertFails(setDoc(doc(alice(), 'users/alice/expenses/bad'), missing));
  });

  test('dates must exist on the calendar', async () => {
    for (const date of ['2025-02-31', '2025-02-29', '2025-04-31', '2100-02-29']) {
      await assertFails(setDoc(doc(alice(), `users/alice/expenses/d${date}`), expense({ date })), date);
    }
    for (const date of ['2024-02-29', '2000-02-29', '2025-01-31', '2025-04-30', '2025-12-31']) {
      await assertSucceeds(setDoc(doc(alice(), `users/alice/expenses/d${date}`), expense({ date })), date);
    }
  });

  test('updates must increment the version (stale edits are rejected)', async () => {
    await seedExpense('e1', { version: 3 });
    const ref = doc(alice(), 'users/alice/expenses/e1');
    await assertSucceeds(updateDoc(ref, { amountMinor: 9900, updatedAt: serverTimestamp(), version: 4 }));
    // A second device that still had version 3 tries to write version 4.
    await assertFails(updateDoc(ref, { amountMinor: 1, updatedAt: serverTimestamp(), version: 4 }));
    await assertFails(updateDoc(ref, { amountMinor: 1, updatedAt: serverTimestamp(), version: 9 }));
  });

  test('createdAt is immutable and updatedAt must be server time', async () => {
    await seedExpense('e1');
    const ref = doc(alice(), 'users/alice/expenses/e1');
    await assertFails(updateDoc(ref, { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), version: 2 }));
    await assertFails(updateDoc(ref, { amountMinor: 5, updatedAt: new Date(), version: 2 }));
  });

  test('owner can delete', async () => {
    await seedExpense('e1');
    await assertSucceeds(deleteDoc(doc(alice(), 'users/alice/expenses/e1')));
  });
});

describe('other collections', () => {
  test('user profile', async () => {
    const ref = doc(alice(), 'users/alice');
    await assertSucceeds(setDoc(ref, { displayName: 'Alice', createdAt: serverTimestamp(), schemaVersion: 1 }));
    await assertSucceeds(updateDoc(ref, { displayName: 'Al' }));
    await assertFails(updateDoc(ref, { createdAt: serverTimestamp() }));
    await assertFails(getDoc(doc(bob(), 'users/alice')));
    await assertFails(getDocs(collection(alice(), 'users')));
  });

  test('daily status id must match its date', async () => {
    const ok = { date: '2025-10-13', status: 'no_expenses', updatedAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/daily_status/2025-10-13'), ok));
    await assertFails(setDoc(doc(alice(), 'users/alice/daily_status/2025-10-12'), ok));
    await assertFails(
      setDoc(doc(alice(), 'users/alice/daily_status/2025-10-13'), { ...ok, status: 'maybe' }),
    );
    await assertFails(setDoc(doc(bob(), 'users/alice/daily_status/2025-10-13'), ok));
  });

  test('categories are validated', async () => {
    const cat = { name: 'Pets', iconKey: 'pets', colorIndex: 3, archived: false, sortOrder: 200, updatedAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/categories/c1'), cat));
    await assertFails(setDoc(doc(alice(), 'users/alice/categories/c2'), { ...cat, colorIndex: 12 }));
    await assertFails(setDoc(doc(alice(), 'users/alice/categories/c3'), { ...cat, name: '' }));
  });

  test('budget ids match their scope', async () => {
    const b = { amountMinor: 100000, currency: 'INR', categoryId: null, updatedAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/budgets/overall'), b));
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/budgets/cat_food'), { ...b, categoryId: 'food' }));
    await assertFails(setDoc(doc(alice(), 'users/alice/budgets/cat_food'), { ...b, categoryId: 'travel' }));
    await assertFails(setDoc(doc(alice(), 'users/alice/budgets/overall'), { ...b, amountMinor: -1 }));
  });

  test('budget alerts can only escalate', async () => {
    const ref = doc(alice(), 'users/alice/budget_alerts/2025-10_overall');
    const a = { monthKey: '2025-10', budgetId: 'overall', threshold: 80, updatedAt: serverTimestamp() };
    await assertSucceeds(setDoc(ref, a));
    await assertFails(setDoc(ref, a));
    await assertSucceeds(setDoc(ref, { ...a, threshold: 100 }));
    await assertFails(setDoc(doc(alice(), 'users/alice/budget_alerts/2025-10_other'), a));
  });

  test('loans are private and validated', async () => {
    const loan = {
      direction: 'lent',
      personName: 'Rahul',
      amountMinor: 500000,
      repaidMinor: 0,
      currency: 'INR',
      date: '2025-10-14',
      dueDate: null,
      note: null,
      settled: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };
    const ref = doc(alice(), 'users/alice/loans/l1');
    await assertSucceeds(setDoc(ref, loan));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(updateDoc(ref, { repaidMinor: 200000, updatedAt: serverTimestamp() }));
    // Cannot repay more than the amount, or use an unknown direction.
    await assertFails(updateDoc(ref, { repaidMinor: 600000, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(alice(), 'users/alice/loans/l2'), { ...loan, direction: 'gift' }));
    await assertFails(setDoc(doc(alice(), 'users/alice/loans/l3'), { ...loan, personName: '' }));
    await assertFails(setDoc(doc(alice(), 'users/alice/loans/l4'), { ...loan, extra: 1 }));
    // Other users and unverified accounts cannot touch it.
    await assertFails(getDoc(doc(bob(), 'users/alice/loans/l1')));
    await assertFails(setDoc(doc(bob(), 'users/alice/loans/l5'), loan));
    await assertFails(setDoc(doc(unverified(), 'users/alice/loans/l6'), loan));
    await assertSucceeds(deleteDoc(ref));
  });

  test('repayments must move the loan total by exactly their amount', async () => {
    const loanRef = (db) => doc(db, 'users/alice/loans/l1');
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(loanRef(ctx.firestore()), {
        direction: 'lent',
        personName: 'Rahul',
        amountMinor: 500000,
        repaidMinor: 100000,
        currency: 'INR',
        date: '2025-10-14',
        settled: false,
        createdAt: new Date('2025-10-14T10:00:00Z'),
        updatedAt: new Date('2025-10-14T10:00:00Z'),
      });
    });
    const repayment = (amountMinor, extra = {}) => ({
      amountMinor,
      date: '2025-10-20',
      note: null,
      createdAt: serverTimestamp(),
      ...extra,
    });
    const pay = (db, id, amount, newTotal, extra = {}, settled = false) => {
      const b = writeBatch(db);
      b.set(doc(db, `users/alice/loans/l1/repayments/${id}`), repayment(amount, extra));
      b.update(loanRef(db), { repaidMinor: newTotal, settled, updatedAt: serverTimestamp() });
      return b.commit();
    };

    await assertSucceeds(pay(alice(), 'r1', 200000, 300000));
    await assertSucceeds(getDocs(collection(alice(), 'users/alice/loans/l1/repayments')));
    // The total must rise by exactly the repayment.
    await assertFails(pay(alice(), 'r2', 50000, 400000));
    // A repayment on its own (loan total unchanged) is rejected.
    await assertFails(setDoc(doc(alice(), 'users/alice/loans/l1/repayments/r3'), repayment(1000)));
    // Overpaying is rejected (repaidMinor would exceed the amount).
    await assertFails(pay(alice(), 'r4', 300000, 600000, {}, true));
    // Invalid fields.
    await assertFails(pay(alice(), 'r5', 0, 300000));
    await assertFails(pay(alice(), 'r6', 1000, 301000, { date: '2025-02-30' }));
    await assertFails(pay(alice(), 'r7', 1000, 301000, { extra: true }));
    // History is immutable and private.
    await assertFails(
      updateDoc(doc(alice(), 'users/alice/loans/l1/repayments/r1'), { amountMinor: 1 }),
    );
    await assertFails(getDoc(doc(bob(), 'users/alice/loans/l1/repayments/r1')));
    await assertFails(pay(bob(), 'r8', 1000, 301000));
    // Paying the rest settles the loan.
    await assertSucceeds(pay(alice(), 'r9', 200000, 500000, {}, true));
    await assertSucceeds(deleteDoc(doc(alice(), 'users/alice/loans/l1/repayments/r1')));
  });

  test('preferences are validated', async () => {
    const p = {
      currencyCode: 'INR',
      weekStart: 7,
      formatLocale: null,
      reminders: {
        enabled: true,
        timeMinutes: 1320,
        followUpsEnabled: true,
        followUpMinutes: [1365, 1410],
        quietHoursEnabled: false,
        quietStartMinutes: 1380,
        quietEndMinutes: 420,
      },
      budgetAlertThresholds: [80, 100],
      updatedAt: serverTimestamp(),
    };
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/settings/preferences'), p));
    await assertFails(setDoc(doc(alice(), 'users/alice/settings/preferences'), { ...p, weekStart: 8 }));
    await assertFails(
      setDoc(doc(alice(), 'users/alice/settings/preferences'), { ...p, reminders: { ...p.reminders, timeMinutes: 5000 } }),
    );
    await assertFails(setDoc(doc(alice(), 'users/alice/settings/other'), p));
  });

  test('clients cannot grant themselves premium', async () => {
    const ref = doc(alice(), 'users/alice/entitlements/premium');
    await assertFails(setDoc(ref, { active: true }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/alice/entitlements/premium'), { active: true, source: 'manual' });
    });
    await assertSucceeds(getDoc(ref));
    await assertFails(updateDoc(ref, { active: false, source: 'x' }));
    await assertFails(getDoc(doc(bob(), 'users/alice/entitlements/premium')));
  });

  test('unknown collections are denied', async () => {
    await assertFails(setDoc(doc(alice(), 'users/alice/secrets/x'), { a: 1 }));
    await assertFails(setDoc(doc(alice(), 'public/x'), { a: 1 }));
  });
});
