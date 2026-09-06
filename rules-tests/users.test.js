const { assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { getTestEnv, seed } = require('./setup');

describe('users/{uid}', () => {
  afterEach(async () => (await getTestEnv()).clearFirestore());

  it('lets any signed-in user read any profile', async () => {
    await seed((db) => db.doc('users/victim').set({ uid: 'victim', role: 'user', banned: false }));
    const attacker = (await getTestEnv()).authenticatedContext('attacker').firestore();
    await assertSucceeds(attacker.doc('users/victim').get());
  });

  it('lets a user create their own profile as role=user, banned=false', async () => {
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertSucceeds(
      me.doc('users/me').set({ uid: 'me', role: 'user', banned: false })
    );
  });

  it('blocks creating your own profile as an admin', async () => {
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('users/me').set({ uid: 'me', role: 'admin', banned: false })
    );
  });

  it('CRITICAL: blocks a user from promoting themselves to admin via update', async () => {
    await seed((db) => db.doc('users/me').set({ uid: 'me', role: 'user', banned: false }));
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('users/me').set({ uid: 'me', role: 'admin', banned: false }, { merge: true })
    );
  });

  it('CRITICAL: blocks a user from un-banning themselves', async () => {
    await seed((db) => db.doc('users/me').set({ uid: 'me', role: 'user', banned: true }));
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('users/me').set({ banned: false }, { merge: true })
    );
  });

  it('CRITICAL: blocks a user from setting hasPaid=true on themselves', async () => {
    await seed((db) => db.doc('users/me').set({ uid: 'me', role: 'user', banned: false, hasPaid: false }));
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('users/me').set({ hasPaid: true }, { merge: true })
    );
  });

  it('CRITICAL: blocks a user from setting hasLifetimeListingAccess=true on themselves', async () => {
    await seed((db) =>
      db.doc('users/me').set({ uid: 'me', role: 'user', banned: false, hasLifetimeListingAccess: false })
    );
    const me = (await getTestEnv()).authenticatedContext('me').firestore();
    await assertFails(
      me.doc('users/me').set({ hasLifetimeListingAccess: true }, { merge: true })
    );
  });

  it('allows an admin to change another user\'s role/banned status', async () => {
    await seed(async (db) => {
      await db.doc('users/admin1').set({ uid: 'admin1', role: 'admin', banned: false });
      await db.doc('users/victim').set({ uid: 'victim', role: 'user', banned: false });
    });
    const admin = (await getTestEnv()).authenticatedContext('admin1').firestore();
    await assertSucceeds(admin.doc('users/victim').set({ banned: true }, { merge: true }));
  });

  it('CRITICAL: blocks a non-admin from deleting another user\'s profile', async () => {
    await seed((db) => db.doc('users/victim').set({ uid: 'victim', role: 'user', banned: false }));
    const attacker = (await getTestEnv()).authenticatedContext('attacker').firestore();
    await assertFails(attacker.doc('users/victim').delete());
  });

  describe('users/{uid}/wishlist', () => {
    it('CRITICAL: blocks reading another user\'s wishlist', async () => {
      await seed((db) => db.doc('users/victim/wishlist/prod1').set({ productId: 'prod1' }));
      const attacker = (await getTestEnv()).authenticatedContext('attacker').firestore();
      await assertFails(attacker.doc('users/victim/wishlist/prod1').get());
    });

    it('lets the owner read/write their own wishlist', async () => {
      const me = (await getTestEnv()).authenticatedContext('me').firestore();
      await assertSucceeds(me.doc('users/me/wishlist/prod1').set({ productId: 'prod1' }));
    });
  });

  describe('users/{uid}/notifications', () => {
    it('CRITICAL: blocks reading another user\'s notifications', async () => {
      await seed((db) =>
        db.doc('users/victim/notifications/n1').set({ read: false, data: { type: 'swap_request' } })
      );
      const attacker = (await getTestEnv()).authenticatedContext('attacker').firestore();
      await assertFails(attacker.doc('users/victim/notifications/n1').get());
    });

    it('CRITICAL: blocks marking someone else\'s notification as read', async () => {
      await seed((db) =>
        db.doc('users/victim/notifications/n1').set({ read: false, data: { type: 'swap_request' } })
      );
      const attacker = (await getTestEnv()).authenticatedContext('attacker').firestore();
      await assertFails(
        attacker.doc('users/victim/notifications/n1').set({ read: true }, { merge: true })
      );
    });

    it('blocks a client from directly creating a notification for themselves', async () => {
      const me = (await getTestEnv()).authenticatedContext('me').firestore();
      await assertFails(
        me.doc('users/me/notifications/fake1').set({ read: false, data: { type: 'swap_request' } })
      );
    });

    it('lets the owner mark their own notification as read, but only the `read` field', async () => {
      await seed((db) =>
        db.doc('users/me/notifications/n1').set({ read: false, data: { type: 'swap_request' }, title: 'x' })
      );
      const me = (await getTestEnv()).authenticatedContext('me').firestore();
      await assertSucceeds(
        me.doc('users/me/notifications/n1').set({ read: true }, { merge: true })
      );
    });

    it('CRITICAL: blocks the owner from rewriting other fields while marking read (e.g. forging `type`)', async () => {
      await seed((db) =>
        db.doc('users/me/notifications/n1').set({ read: false, data: { type: 'swap_request' }, title: 'x' })
      );
      const me = (await getTestEnv()).authenticatedContext('me').firestore();
      await assertFails(
        me.doc('users/me/notifications/n1').set(
          { read: true, title: 'tampered' },
          { merge: true }
        )
      );
    });

    it('lets the owner delete their own notification', async () => {
      await seed((db) =>
        db.doc('users/me/notifications/n1').set({ read: false, data: { type: 'swap_request' } })
      );
      const me = (await getTestEnv()).authenticatedContext('me').firestore();
      await assertSucceeds(me.doc('users/me/notifications/n1').delete());
    });
  });
});