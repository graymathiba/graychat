import { io } from 'socket.io-client';
import assert from 'node:assert';

const URL = process.env.TEST_URL || 'http://127.0.0.1:3000';

let passed = 0;
let failed = 0;
const results = [];

function check(name, cond, extra = '') {
  if (cond) {
    passed++;
    results.push(`  PASS  ${name}`);
  } else {
    failed++;
    results.push(`  FAIL  ${name}${extra ? ` :: ${extra}` : ''}`);
  }
}

function connect(auth = {}, timeoutMs = 15000) {
  return new Promise((resolve, reject) => {
    const s = io(URL, {
      transports: ['websocket'],
      reconnection: false,
      auth,
    });
    const timer = setTimeout(
      () => reject(new Error('connect timeout')),
      timeoutMs,
    );
    s.on('connect', () => {
      clearTimeout(timer);
      resolve(s);
    });
    s.on('connect_error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

function waitFor(socket, event, predicate = null, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.off(event, handler);
      reject(new Error(`timeout waiting for "${event}"`));
    }, timeoutMs);
    const handler = (data) => {
      try {
        if (predicate && !predicate(data)) return;
      } catch {
        /* keep waiting on predicate errors */
      }
      clearTimeout(timer);
      socket.off(event, handler);
      resolve(data);
    };
    socket.on(event, handler);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function roomIdFor(a, b) {
  return [a, b].sort().join('_');
}

async function main() {
  console.log(`\n=== GryChat integration tests against ${URL} ===\n`);

  let p1, p2;

  // --- 1. Both peers connect over websocket (same options the app uses) ---
  try {
    p1 = await connect({ devUid: 'peer1' });
    check('peer1 websocket connect', p1.connected);
    p2 = await connect({ devUid: 'peer2' });
    check('peer2 websocket connect', p2.connected);
  } catch (e) {
    check('peers connect', false, e.message);
    finish();
  }

  // --- 2. Register both, expect short codes ---
  p1.emit('register', { userId: 'ignored', deviceName: 'Test Peer One' });
  p2.emit('register', { userId: 'ignored', deviceName: 'Test Peer Two' });

  const code1Ev = waitFor(p1, 'myShortCode').catch(() => null);
  const code2Ev = waitFor(p2, 'myShortCode').catch(() => null);
  const [c1, c2] = await Promise.all([code1Ev, code2Ev]);
  check('peer1 received myShortCode', !!c1?.shortCode, JSON.stringify(c1));
  check('peer2 received myShortCode', !!c2?.shortCode, JSON.stringify(c2));
  check('short codes have GRY- prefix', c1?.shortCode?.startsWith('GRY-') && c2?.shortCode?.startsWith('GRY-'));
  check('short codes differ between users', c1?.shortCode !== c2?.shortCode);

  // --- 3. Presence list contains both users on both peers ---
  const bothPresent = (list) =>
    Array.isArray(list) &&
    list.some((u) => u.userId === 'dev-peer1') &&
    list.some((u) => u.userId === 'dev-peer2');
  const listP1 = waitFor(p1, 'onlineUsersList', bothPresent).catch(() => null);
  const listP2 = waitFor(p2, 'onlineUsersList', bothPresent).catch(() => null);
  const [l1, l2] = await Promise.all([listP1, listP2]);
  check('peer1 sees both users in onlineUsersList', !!l1);
  check('peer2 sees both users in onlineUsersList', !!l2);

  // --- 4. Short-code resolution ---
  p2.emit('resolveShortCode', { shortCode: c1.shortCode });
  const resolved = await waitFor(p2, 'resolveShortCodeResult').catch(() => null);
  check(
    'resolveShortCode finds peer1',
    resolved?.found === true && resolved?.userId === 'dev-peer1',
    JSON.stringify(resolved),
  );

  // --- 5. Room join + 1:1 message flow ---
  const room = roomIdFor('dev-peer1', 'dev-peer2');
  p1.emit('join-room', room);
  p2.emit('join-room', room);

  const newMsgAtPeer2 = waitFor(
    p2,
    'newMessage',
    (m) => m.id === 'int-msg-1',
  ).catch(() => null);
  const ackAtPeer1 = waitFor(
    p1,
    'messageAck',
    (a) => a.id === 'int-msg-1',
  ).catch(() => null);

  p1.emit('sendMessage', {
    id: 'int-msg-1',
    receiverId: 'dev-peer2',
    content: 'hello from peer1',
    messageType: 'text',
    timestamp: new Date().toISOString(),
  });

  const [msg, ack] = await Promise.all([newMsgAtPeer2, ackAtPeer1]);
  check('sender got messageAck (status sent)', ack?.status === 'sent', JSON.stringify(ack));
  check('ack has serverTimestamp', typeof ack?.serverTimestamp === 'string' && ack.serverTimestamp.length > 0);
  check('receiver got newMessage', msg?.content === 'hello from peer1', JSON.stringify(msg));
  check('message roomId derived correctly', msg?.roomId === room, `got ${msg?.roomId}`);
  check('message senderId is verified identity', msg?.senderId === 'dev-peer1');

  // Reply path
  const replyAtPeer1 = waitFor(
    p1,
    'newMessage',
    (m) => m.id === 'int-msg-2',
  ).catch(() => null);
  p2.emit('sendMessage', {
    id: 'int-msg-2',
    receiverId: 'dev-peer1',
    content: 'hello from peer2',
    messageType: 'text',
    timestamp: new Date().toISOString(),
  });
  const reply = await replyAtPeer1;
  check('bidirectional delivery works', reply?.content === 'hello from peer2');

  // --- 6. Typing status ---
  const typingEv = waitFor(
    p1,
    'typingStatus',
    (t) => t.userId === 'dev-peer2',
  ).catch(() => null);
  p2.emit('typingStatus', { roomId: room, userId: 'x', isTyping: true });
  const typing = await typingEv;
  check('typingStatus relayed to peer', typing?.isTyping === true);

  // --- 7. Read receipt ---
  const receiptEv = waitFor(
    p1,
    'readReceipt',
    (r) => r.messageId === 'int-msg-1',
  ).catch(() => null);
  p2.emit('readReceipt', { roomId: room, userId: 'x', messageId: 'int-msg-1' });
  const receipt = await receiptEv;
  check('readReceipt relayed to peer', receipt?.userId === 'dev-peer2');

  // --- 8. Reactions ---
  const reactionEv = waitFor(p1, 'reaction').catch(() => null);
  p2.emit('reaction', {
    targetId: 'dev-peer1',
    messageId: 'int-msg-1',
    emoji: '\u2764',
    action: 'add',
  });
  const reaction = await reactionEv;
  check(
    'reaction relayed',
    reaction?.messageId === 'int-msg-1' && reaction?.emoji === '\u2764',
    JSON.stringify(reaction),
  );

  // --- 9. Self-chat does not echo to other sockets ---
  let peer2SawSelfMsg = false;
  const spy = (m) => {
    if (m.id === 'self-1') peer2SawSelfMsg = true;
  };
  p2.on('newMessage', spy);
  const selfAck = waitFor(p1, 'messageAck', (a) => a.id === 'self-1').catch(() => null);
  p1.emit('sendMessage', {
    id: 'self-1',
    receiverId: 'dev-peer1',
    content: 'note to self',
    messageType: 'text',
    timestamp: new Date().toISOString(),
  });
  await selfAck;
  await sleep(400);
  check('self-chat acked without leaking to other peers', !peer2SawSelfMsg);
  p2.off('newMessage', spy);

  // --- 10. Invalid token is rejected even in dev mode ---
  let rejected = false;
  try {
    await connect({ token: 'garbage.token.value' }, 12000);
  } catch {
    rejected = true;
  }
  check('invalid Firebase token rejected', rejected);

  // --- 11. Invalid message payload produces messageError ---
  const errEv = waitFor(p1, 'messageError').catch(() => null);
  p1.emit('sendMessage', { id: 'bad-1', receiverId: 'dev-peer2', content: '' });
  const errMsg = await errEv;
  check('empty content rejected with messageError', !!errMsg, JSON.stringify(errMsg));

  // --- 12. Disconnect propagates presence offline, reconnect recovers ---
  const offlineEv = waitFor(
    p1,
    'userPresence',
    (u) => u.userId === 'dev-peer2' && u.status === 'offline',
    12000,
  ).catch(() => null);
  p2.disconnect();
  const offline = await offlineEv;
  check('offline presence broadcast on disconnect', !!offline);

  p2 = await connect({ devUid: 'peer2' }).catch(() => null);
  check('reconnect after disconnect succeeds', !!p2?.connected);
  if (p2) {
    const rejoinList = waitFor(p2, 'myShortCode', null, 8000).catch(() => null);
    p2.emit('register', { userId: 'ignored', deviceName: 'Test Peer Two' });
    check('re-register after reconnect works', !!(await rejoinList));
  }

  // --- 13. Rate limiting kicks in after 60 msgs/min ---
  const p3 = await connect({ devUid: 'peer3' }).catch(() => null);
  if (p3) {
    let rateLimited = false;
    p3.on('messageError', (e) => {
      if (String(e?.error || '').includes('Rate limit')) rateLimited = true;
    });
    for (let i = 0; i < 70; i++) {
      p3.emit('sendMessage', {
        id: `rl-${i}`,
        receiverId: 'dev-peer1',
        content: 'spam',
        messageType: 'text',
        timestamp: new Date().toISOString(),
      });
      if (i % 10 === 0) await sleep(30);
    }
    await sleep(1500);
    check('rate limit enforced (>60 msgs/min)', rateLimited);
    p3.disconnect();
  } else {
    check('rate limit client connected', false);
  }

  finish();
}

function finish() {
  console.log(results.join('\n'));
  console.log(`\n=== Results: ${passed} passed, ${failed} failed ===\n`);
  try {
    p1?.disconnect();
    p2?.disconnect();
  } catch {}
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error('Fatal test error:', e);
  process.exit(1);
});
