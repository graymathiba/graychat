import { io } from 'socket.io-client';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { readFileSync } from 'fs';
import dotenv from 'dotenv';

const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, '.env') });

const URL = process.env.LIVE_URL || 'https://graychat.onrender.com';
const API_KEY = 'REDACTED_GOOGLE_API_KEY';
const PROJECT_ID = 'graychat-db6a0';

const ts = Date.now();
const EMAIL_A = `live-test-a-${ts}@grychat-test.local`;
const EMAIL_B = `live-test-b-${ts}@grychat-test.local`;
const PASSWORD = 'LiveTest!2026zz';

let passed = 0;
let failed = 0;
function check(name, cond, extra = '') {
  if (cond) {
    passed++;
    console.log(`  PASS  ${name}`);
  } else {
    failed++;
    console.log(`  FAIL  ${name}${extra ? ` :: ${extra}` : ''}`);
  }
}

async function mintUser(email, displayName) {
  const signup = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email,
        password: PASSWORD,
        returnSecureToken: true,
        displayName,
      }),
    },
  );
  const data = await signup.json();
  if (!data.idToken) throw new Error(`signUp failed: ${JSON.stringify(data)}`);
  return { idToken: data.idToken, refreshToken: data.refreshToken, uid: data.localId };
}

function connect(auth, timeoutMs = 20000) {
  return new Promise((resolve, reject) => {
    const s = io(URL, { transports: ['websocket'], reconnection: false, auth });
    const timer = setTimeout(() => reject(new Error('connect timeout')), timeoutMs);
    s.on('connect', () => { clearTimeout(timer); resolve(s); });
    s.on('connect_error', (err) => { clearTimeout(timer); reject(new Error(`connect_error: ${err.message}`)); });
  });
}

function waitFor(socket, event, predicate = null, timeoutMs = 15000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off(event, handler);
      reject(new Error(`timeout waiting for "${event}"`));
    }, timeoutMs);
    const handler = (data) => {
      try { if (predicate && !predicate(data)) return; } catch { return; }
      clearTimeout(timer);
      socket.off(event, handler);
      resolve(data);
    };
    socket.on(event, handler);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const roomIdFor = (a, b) => [a, b].sort().join('_');

let users = [];
let sockets = [];

async function cleanup() {
  console.log('\n--- cleanup ---');
  for (const s of sockets) { try { s.disconnect(); } catch {} }
  try {
    const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT;
    if (!serviceAccountJson) {
      console.log('  no FIREBASE_SERVICE_ACCOUNT for cleanup');
      return;
    }
    const { initializeApp, applicationDefault } = await import('firebase-admin/app');
    const { getAuth } = await import('firebase-admin/auth');
    let app;
    try {
      app = initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
    } catch {
      app = process.env.FIREBASE_ADMIN_APP;
    }
    const auth = getAuth(app);
    for (const u of users) {
      try {
        await auth.deleteUser(u.uid);
        console.log(`  deleted test user ${u.uid}`);
      } catch (e) {
        console.log(`  cleanup failed for ${u.uid}: ${e.message}`);
      }
    }
  } catch (e) {
    console.log(`  cleanup error: ${e.message}`);
  }
}

async function main() {
  console.log(`\n=== Live routing test against ${URL} ===\n`);

  // 1. Mint two real users
  let ua, ub;
  try {
    ua = await mintUser(EMAIL_A, 'Live Test A');
    ub = await mintUser(EMAIL_B, 'Live Test B');
  } catch (e) {
    console.log(`mint failed: ${e.message}`);
    process.exit(1);
  }
  users = [ua, ub];
  console.log(`minted users \n  A uid=${ua.uid}\n  B uid=${ub.uid}`);

  // 2. Connect both sockets to the live server
  let pa, pb;
  try {
    pa = await connect({ token: ua.idToken });
    check('socket A connects with real Firebase token', pa.connected);
    pb = await connect({ token: ub.idToken });
    check('socket B connects with real Firebase token', pb.connected);
  } catch (e) {
    check(`socket connect`, false, e.message);
    await cleanup();
    process.exit(1);
  }
  sockets = [pa, pb];
  console.log(`socket A id=${pa.id}`);
  console.log(`socket B id=${pb.id}`);

  // 3. Register both
  const codeA = waitFor(pa, 'myShortCode').catch(() => null);
  const codeB = waitFor(pb, 'myShortCode').catch(() => null);
  pa.emit('register', { deviceName: 'Live Test A' });
  pb.emit('register', { deviceName: 'Live Test B' });
  const [c1, c2] = await Promise.all([codeA, codeB]);
  check('B receives myShortCode', !!c2?.shortCode);
  check('A receives myShortCode', !!c1?.shortCode);

  // 4. Presence: does each socket see the other online (this is the green-dot path)?
  const bothPresent = (list) =>
    Array.isArray(list) &&
    list.some((u) => u.userId === ua.uid) &&
    list.some((u) => u.userId === ub.uid);
  const listA = waitFor(pa, 'onlineUsersList', bothPresent, 20000).catch(() => null);
  const listB = waitFor(pb, 'onlineUsersList', bothPresent, 20000).catch(() => null);
  const [la, lb] = await Promise.all([listA, listB]);
  check('A sees B online in onlineUsersList', !!la);
  check('B sees A online in onlineUsersList', !!lb);

  // 5. Message: A joins room, B does NOT. A sends -> B should receive via direct fallback.
  const room = roomIdFor(ua.uid, ub.uid);
  pa.emit('join-room', room);

  const msgB = waitFor(pb, 'newMessage', (m) => m.id === 'live-msg-1').catch(() => null);
  const ackA = waitFor(pa, 'messageAck', (a) => a.id === 'live-msg-1').catch(() => null);
  pa.emit('sendMessage', {
    id: 'live-msg-1',
    receiverId: ub.uid,
    content: 'hello from A (B not in room)',
    messageType: 'text',
    timestamp: new Date().toISOString(),
  });
  const [m1, a1] = await Promise.all([msgB, ackA]);
  check('A got messageAck for live-msg-1', a1?.status === 'sent', JSON.stringify(a1));
  check('B received live-msg-1 (no room join)', m1?.content?.includes('hello from A'), JSON.stringify(m1));

  // 6. Message: B joins room, A sends. B should get it via room broadcast.
  pb.emit('join-room', room);
  await sleep(500);
  const msgB2 = waitFor(pb, 'newMessage', (m) => m.id === 'live-msg-2').catch(() => null);
  pa.emit('sendMessage', {
    id: 'live-msg-2',
    receiverId: ub.uid,
    content: 'hello from A (B in room)',
    messageType: 'text',
    timestamp: new Date().toISOString(),
  });
  const m2 = await msgB2;
  check('B received live-msg-2 (room broadcast)', m2?.content?.includes('hello from A'), JSON.stringify(m2));

  // 7. Reverse direction while both in room
  const msgA = waitFor(pa, 'newMessage', (m) => m.id === 'live-msg-3').catch(() => null);
  pb.emit('sendMessage', {
    id: 'live-msg-3',
    receiverId: ua.uid,
    content: 'hello from B (reverse)',
    messageType: 'text',
    timestamp: new Date().toISOString(),
  });
  const m3 = await msgA;
  check('A received live-msg-3 (reverse direction)', m3?.content?.includes('hello from B'), JSON.stringify(m3));

  console.log(`\n=== RESULT: ${passed} passed, ${failed} failed ===`);
  await cleanup();
  process.exit(failed === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.log(`SCRIPT ERROR: ${e.message}`);
  await cleanup();
  process.exit(1);
});