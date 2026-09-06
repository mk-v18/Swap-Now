const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

let testEnv;

async function getTestEnv() {
  if (testEnv) return testEnv;
  testEnv = await initializeTestEnvironment({
    projectId: 'swapnow-rules-test',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
  return testEnv;
}

// Seeds documents using the Admin SDK context, which bypasses rules
// entirely — this is how we set up "existing state" before an attacker
// tries to read/write it, exactly like Cloud Functions do in production.
async function seed(fn) {
  const env = await getTestEnv();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await fn(ctx.firestore());
  });
}

// Closes the connection to the emulator so Jest can exit cleanly instead
// of hanging on an open gRPC stream. Registered here (rather than in each
// test file) so every test file that requires ./setup gets cleanup for
// free without needing its own afterAll boilerplate.
afterAll(async () => {
  if (testEnv) {
    await testEnv.cleanup();
    testEnv = null;
  }
});

module.exports = { getTestEnv, seed };