const { assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { getTestEnv, seed } = require('./setup');

describe('UserProductList/{productId}', () => {
  afterEach(async () => (await getTestEnv()).clearFirestore());

  it('lets any signed-in user read a listing', async () => {
    await seed((db) => db.doc('UserProductList/prod1').set({ userId: 'seller', price: 100 }));
    const someone = (await getTestEnv()).authenticatedContext('someone').firestore();
    await assertSucceeds(someone.doc('UserProductList/prod1').get());
  });

  it('lets a non-banned user create their own listing with a positive price', async () => {
    await seed((db) => db.doc('users/me').set({ uid: 'me', role: 'user', banned: false }));
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertSucceeds(
      me.doc('UserProductList/prod1').set({ userId: 'me', price: 500 })
    );
  });

  it('CRITICAL: blocks creating a listing with someone else\'s userId', async () => {
    await seed((db) => db.doc('users/me').set({ uid: 'me', role: 'user', banned: false }));
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('UserProductList/prod1').set({ userId: 'someone-else', price: 500 })
    );
  });

  it('CRITICAL: blocks a banned user from creating a listing', async () => {
    await seed((db) => db.doc('users/banned1').set({ uid: 'banned1', role: 'user', banned: true }));
    const banned = (await getTestEnv()).authenticatedContext('banned1').firestore();
    await assertFails(
      banned.doc('UserProductList/prod1').set({ userId: 'banned1', price: 500 })
    );
  });

  it('blocks creating a listing with price <= 0 for a normal user', async () => {
    await seed((db) => db.doc('users/me').set({ uid: 'me', role: 'user', banned: false }));
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('UserProductList/prod1').set({ userId: 'me', price: 0 })
    );
  });

  it('lets a user with hasLifetimeListingAccess create a listing with price = 0', async () => {
    await seed((db) =>
      db.doc('users/lifetime1').set({ uid: 'lifetime1', role: 'user', banned: false, hasLifetimeListingAccess: true })
    );
    const lifetime = (await getTestEnv()).authenticatedContext('lifetime1').firestore();
    await assertSucceeds(
      lifetime.doc('UserProductList/prod1').set({ userId: 'lifetime1', price: 0 })
    );
  });

  it('CRITICAL: blocks a non-lifetime user from claiming hasLifetimeListingAccess just by writing price 0', async () => {
    await seed((db) =>
      db.doc('users/me').set({ uid: 'me', role: 'user', banned: false, hasLifetimeListingAccess: false })
    );
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('UserProductList/prod1').set({ userId: 'me', price: 0 })
    );
  });

  it('CRITICAL: blocks a banned user from updating their own existing listing', async () => {
    await seed(async (db) => {
      await db.doc('users/banned1').set({ uid: 'banned1', role: 'user', banned: true });
      await db.doc('UserProductList/prod1').set({ userId: 'banned1', price: 500 });
    });
    const banned = (await getTestEnv()).authenticatedContext('banned1').firestore();
    await assertFails(
      banned.doc('UserProductList/prod1').set({ price: 400 }, { merge: true })
    );
  });

  it('CRITICAL: blocks a banned user from deleting their own existing listing', async () => {
    await seed(async (db) => {
      await db.doc('users/banned1').set({ uid: 'banned1', role: 'user', banned: true });
      await db.doc('UserProductList/prod1').set({ userId: 'banned1', price: 500 });
    });
    const banned = (await getTestEnv()).authenticatedContext('banned1').firestore();
    await assertFails(banned.doc('UserProductList/prod1').delete());
  });

  it('CRITICAL: blocks a non-owner from updating someone else\'s listing', async () => {
    await seed(async (db) => {
      await db.doc('users/attacker').set({ uid: 'attacker', role: 'user', banned: false });
      await db.doc('UserProductList/prod1').set({ userId: 'victim', price: 500 });
    });
    const attacker = (await getTestEnv()).authenticatedContext('attacker').firestore();
    await assertFails(
      attacker.doc('UserProductList/prod1').set({ price: 1 }, { merge: true })
    );
  });

  it('CRITICAL: blocks a non-owner from deleting someone else\'s listing', async () => {
    await seed(async (db) => {
      await db.doc('users/attacker').set({ uid: 'attacker', role: 'user', banned: false });
      await db.doc('UserProductList/prod1').set({ userId: 'victim', price: 500 });
    });
    const attacker = (await getTestEnv()).authenticatedContext('attacker').firestore();
    await assertFails(attacker.doc('UserProductList/prod1').delete());
  });

  it('allows an admin to update/delete any listing, banned owner or not', async () => {
    await seed(async (db) => {
      await db.doc('users/admin1').set({ uid: 'admin1', role: 'admin', banned: false });
      await db.doc('users/banned1').set({ uid: 'banned1', role: 'user', banned: true });
      await db.doc('UserProductList/prod1').set({ userId: 'banned1', price: 500 });
    });
    const admin = (await getTestEnv()).authenticatedContext('admin1').firestore();
    await assertSucceeds(
      admin.doc('UserProductList/prod1').set({ price: 1 }, { merge: true })
    );
    await assertSucceeds(admin.doc('UserProductList/prod1').delete());
  });
});