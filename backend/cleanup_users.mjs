import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { readFileSync } from 'fs';
import dotenv from 'dotenv';
const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, '.env') });

const { initializeApp, cert } = await import('firebase-admin/app');
const { getAuth } = await import('firebase-admin/auth');

const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
let app;
try {
  app = initializeApp({ credential: cert(serviceAccount) });
} catch (e) {
  app = process.env.FIREBASE_ADMIN_APP;
}
const auth = getAuth(app);

const uids = process.argv.slice(2);
for (const uid of uids) {
  try {
    await auth.deleteUser(uid);
    console.log(`deleted ${uid}`);
  } catch (e) {
    console.log(`FAILED ${uid}: ${e.message}`);
  }
}