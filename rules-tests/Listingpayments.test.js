const { assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { getTestEnv, seed } = require('./setup');

describe('listingPayments/{paymentId}', () => {
  afterEach(async () => (await getTestEnv()).clearFirestore());

  it('CRITICAL: blocks a client from creating a listingPayments doc directly (write: false)', async () => {
    await seed((db) => db.doc('users/me').set({ uid: 'me', role: 'user', banned: false }));
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('listingPayments/pay1').set({ userId: 'me', amount: 100 })
    );
  });

  it('lets the owner read their own listing-payment record', async () => {
    await seed((db) => db.doc('listingPayments/pay1').set({ userId: 'me', amount: 100 }));
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertSucceeds(me.doc('listingPayments/pay1').get());
  });

  it('CRITICAL: blocks a non-owner from reading someone else\'s listing-payment record', async () => {
    await seed(async (db) => {
      await db.doc('users/attacker').set({ uid: 'attacker', role: 'user', banned: false });
      await db.doc('listingPayments/pay1').set({ userId: 'victim', amount: 100 });
    });
    const attacker = (await getTestEnv()).authenticatedContext('attacker').firestore();
    await assertFails(attacker.doc('listingPayments/pay1').get());
  });

  it('allows an admin to read any listing-payment record', async () => {
    await seed(async (db) => {
      await db.doc('users/admin1').set({ uid: 'admin1', role: 'admin', banned: false });
      await db.doc('listingPayments/pay1').set({ userId: 'victim', amount: 100 });
    });
    const admin = (await getTestEnv()).authenticatedContext('admin1').firestore();
    await assertSucceeds(admin.doc('listingPayments/pay1').get());
  });

  it('CRITICAL: blocks any client update, even by the owner', async () => {
    await seed((db) => db.doc('listingPayments/pay1').set({ userId: 'me', amount: 100 }));
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('listingPayments/pay1').set({ amount: 1 }, { merge: true })
    );
  });

  it('CRITICAL: blocks any client delete, even by an admin', async () => {
    await seed(async (db) => {
      await db.doc('users/admin1').set({ uid: 'admin1', role: 'admin', banned: false });
      await db.doc('listingPayments/pay1').set({ userId: 'victim', amount: 100 });
    });
    const admin = (await getTestEnv()).authenticatedContext('admin1').firestore();
    await assertFails(admin.doc('listingPayments/pay1').delete());
  });
});