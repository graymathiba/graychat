import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import { initializeApp, cert } from 'firebase-admin/app';
import type { App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { createClient } from '@supabase/supabase-js';
import nodemailer from 'nodemailer';
import 'dotenv/config';

let firebaseApp: App | null = null;
if (!firebaseApp) {
  const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (serviceAccount) {
    try {
      firebaseApp = initializeApp({
        credential: cert(JSON.parse(serviceAccount)),
      });
    } catch (err: any) {
      console.error('Firebase init failed:', err.message);
      process.exit(1);
    }
  } else {
    if (process.env.NODE_ENV === 'production') {
      console.error('FIREBASE_SERVICE_ACCOUNT missing in production');
      process.exit(1);
    }
    firebaseApp = initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID ?? 'dev-project',
    });
  }
}

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;
let supabase: ReturnType<typeof createClient> | null = null;

if (supabaseUrl && supabaseKey) {
  supabase = createClient(supabaseUrl, supabaseKey);
}

function generateShortCodeFromHash(userId: string, salt = ''): string {
  const input = salt ? `${userId}:${salt}` : userId;
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  hash ^= hash >>> 16;
  hash = Math.imul(hash, 0x85ebca6b);
  hash ^= hash >>> 13;
  hash = Math.imul(hash, 0xc2b2ae35);
  hash ^= hash >>> 16;
  const code = ((hash >>> 0) % 1679616).toString(36).toUpperCase().padStart(4, '0');
  return `GRY-${code}`;
}

async function getOrCreatePermanentShortCode(userId: string): Promise<string> {
  if (!supabase) return generateShortCodeFromHash(userId);
  const db = supabase as any;

  const { data: existing } = await db
    .from('user_profiles')
    .select('short_code')
    .eq('user_id', userId)
    .single();

  if (existing?.short_code) return existing.short_code;

  let code = generateShortCodeFromHash(userId);
  for (let attempt = 1; attempt <= 10; attempt++) {
    const { data: taken } = await db
      .from('user_profiles')
      .select('user_id')
      .eq('short_code', code)
      .maybeSingle();
    if (!taken || taken.user_id === userId) break;
    code = generateShortCodeFromHash(userId, String(attempt));
  }
  const { error } = await db
    .from('user_profiles')
    .upsert({ user_id: userId, short_code: code }, { onConflict: 'user_id' });

  if (error) {
    console.error('Failed to persist short code:', error.message);
    return code;
  }
  return code;
}

async function upsertUserProfile(userId: string, shortCode: string, displayName: string, email: string, profilePicBase64: string, username?: string): Promise<void> {
  if (!supabase) return;
  const db = supabase as any;
  try {
    const record: any = {
      user_id: userId,
      short_code: shortCode,
      display_name: displayName,
      email: email,
      profile_pic_base64: profilePicBase64,
    };
    if (username) record.username = username;
    await db
      .from('user_profiles')
      .upsert(record, { onConflict: 'user_id' });
  } catch (err: any) {
    console.error('Failed to upsert user profile:', err.message);
  }
}

async function searchUsers(query: string, currentUserId: string): Promise<any[]> {
  if (!supabase) return [];
  const db = supabase as any;
  const normalizedQuery = query.trim().toLowerCase();

  const { data: byUsername } = await db
    .from('user_profiles')
    .select('user_id, display_name, username, short_code, profile_pic_base64')
    .ilike('username', `%${normalizedQuery}%`)
    .neq('user_id', currentUserId)
    .limit(20);

  const { data: byDisplayName } = await db
    .from('user_profiles')
    .select('user_id, display_name, username, short_code, profile_pic_base64')
    .ilike('display_name', `%${normalizedQuery}%`)
    .neq('user_id', currentUserId)
    .limit(20);

  const seen = new Set<string>();
  const results: any[] = [];
  for (const u of [...(byUsername || []), ...(byDisplayName || [])]) {
    if (!seen.has(u.user_id)) {
      seen.add(u.user_id);
      results.push(u);
    }
  }
  return results;
}

async function persistMessage(message: any): Promise<void> {
  if (!supabase) return;
  
  try {
    const { error } = await supabase
      .from('messages')
      .insert({
        id: message.id,
        room_id: message.roomId,
        sender_id: message.senderId,
        receiver_id: message.receiverId,
        group_id: message.groupId || null,
        content: message.content,
        message_type: message.messageType,
        file_name: message.fileName,
        mime_type: message.mimeType,
        attachment_size: message.attachmentSize,
        reply_to_message_id: message.replyToMessageId || null,
        reply_to_content: message.replyToContent || null,
        reply_to_sender_id: message.replyToSenderId || null,
        status: message.status,
        timestamp: message.timestamp,
        server_timestamp: message.serverTimestamp,
      } as any);
    
    if (error) {
      console.error('Failed to persist message:', error.message);
    }
  } catch (err) {
    console.error('persistMessage error:', err);
  }
}

async function persistGroup(group: any): Promise<void> {
  if (!supabase) return;
  
  try {
    const { error: groupError } = await supabase
      .from('groups')
      .upsert({
        id: group.id,
        name: group.name,
        creator_id: group.creatorId,
        created_at: group.createdAt,
      } as any);
    
    if (groupError) {
      console.error('Failed to persist group:', groupError.message);
      return;
    }

    const members = group.memberIds.map((userId: string) => ({
      group_id: group.id,
      user_id: userId,
    }));
    
    const { error: membersError } = await supabase
      .from('group_members')
      .upsert(members, { onConflict: 'group_id,user_id' });
    
    if (membersError) {
      console.error('Failed to persist group members:', membersError.message);
    }
  } catch (err) {
    console.error('persistGroup error:', err);
  }
}

const RATE_LIMIT_WINDOW_MS = 60 * 1000;
const RATE_LIMIT_MAX_CONNECTIONS = 10;
const RATE_LIMIT_MAX_MESSAGES = 60;
const MAX_MESSAGE_SIZE = 1 * 1024 * 1024;
const MAX_DISPLAY_NAME_LENGTH = 50;
const MAX_GROUP_MEMBERS = 100;

const connectionCounts = new Map<string, { count: number; resetTime: number }>();
const messageCounts = new Map<string, { count: number; resetTime: number }>();

function checkRateLimit(identifier: string, type: 'connection' | 'message'): boolean {
  const now = Date.now();
  const max = type === 'connection' ? RATE_LIMIT_MAX_CONNECTIONS : RATE_LIMIT_MAX_MESSAGES;
  const counts = type === 'connection' ? connectionCounts : messageCounts;

  const existing = counts.get(identifier);
  if (existing && now < existing.resetTime) {
    if (existing.count >= max) return false;
    existing.count++;
    return true;
  }

  counts.set(identifier, { count: 1, resetTime: now + RATE_LIMIT_WINDOW_MS });
  return true;
}

const ALLOWED_ORIGINS = process.env.ALLOWED_ORIGINS?.split(',') || [
  'https://grychat.com',
];

const app = express();
const server = http.createServer(app);

app.use(express.json({ limit: '1mb' }));

const io = new Server(server, {
  cors: { 
    origin: ALLOWED_ORIGINS,
    methods: ['GET', 'POST'],
  },
  maxHttpBufferSize: MAX_MESSAGE_SIZE,
});

const onlineUsers = new Map<string, {
  socketId: string;
  shortCode: string;
  displayName: string;
  profilePicBase64: string;
}>();

const shortCodeToUserId = new Map<string, string>();

const groups = new Map<string, {
  id: string;
  name: string;
  creatorId: string;
  memberIds: string[];
  createdAt: string;
}>();

function deriveRoomId(userA: string, userB: string): string {
  return [userA, userB].sort().join('_');
}

function generateUsernameSuggestions(username: string): string[] {
  const suggestions: string[] = [];
  const suffixes = ['_', '1', '2', '3', 'x', 'dev'];
  for (const suffix of suffixes) {
    suggestions.push(`${username}${suffix}`);
    if (suggestions.length >= 5) break;
  }
  return suggestions;
}

function getOnlineUsers() {
  return Array.from(onlineUsers.entries()).map(([id, info]) => ({
    userId: id,
    shortCode: info.shortCode,
    displayName: info.displayName,
    profilePicBase64: info.profilePicBase64,
    status: 'online',
  }));
}

io.use(async (socket, next) => {
  try {
    const token = socket.handshake.auth.token;

    if (!token) {
      if (process.env.NODE_ENV !== 'production') {
        console.warn('DEV MODE: Accepting unauthenticated connection');
        // Dev-only: honor a per-socket dev identity so multiple local
        // peers can be tested independently. Never honored in production.
        const rawDevUid =
          typeof socket.handshake.auth?.devUid === 'string'
            ? socket.handshake.auth.devUid.trim().slice(0, 64)
            : '';
        const devUid = rawDevUid ? `dev-${rawDevUid}` : 'dev-user';
        socket.data.user = { uid: devUid, email: `${devUid}@localhost` } as any;
        return next();
      }
      return next(new Error('Authentication required'));
    }

    try {
      const app = firebaseApp;
      if (!app) return next(new Error('Firebase not initialized'));
      const decodedToken = await getAuth(app).verifyIdToken(token);
      socket.data.user = decodedToken;
      next();
    } catch (error: any) {
      return next(new Error('Invalid authentication token'));
    }
  } catch (error) {
    next(new Error('Authentication error'));
  }
});

io.on('connection', (socket) => {
  const userId = socket.data.user?.uid || socket.id;

  socket.on('register', (data: any) => {
    try {
      if (!data || typeof data !== 'object') {
        socket.emit('error', { message: 'Invalid registration data' });
        return;
      }

      // Identity comes ONLY from the verified JWT — client-supplied
      // userId is ignored so one user cannot impersonate another.
      const uid = userId;
      socket.data.registeredUserId = uid;
      
      const displayName = typeof data.deviceName === 'string' 
        ? data.deviceName.slice(0, MAX_DISPLAY_NAME_LENGTH) 
        : `User ${uid.substring(0, 8)}`;
      
      const profilePicBase64 = typeof data.profilePicBase64 === 'string' && data.profilePicBase64.length < 1000000
        ? data.profilePicBase64 
        : '';

      const email = socket.data.user?.email || '';
      const username = typeof data.username === 'string' ? data.username.trim() : '';

      getOrCreatePermanentShortCode(uid).then((shortCode) => {
        onlineUsers.set(uid, { socketId: socket.id, shortCode, displayName, profilePicBase64 });
        shortCodeToUserId.set(shortCode, uid);

        upsertUserProfile(uid, shortCode, displayName, email, profilePicBase64, username);

        socket.emit('myShortCode', { shortCode });

        socket.broadcast.emit('userPresence', {
          userId: uid,
          shortCode,
          displayName,
          profilePicBase64,
          status: 'online',
          lastSeen: new Date().toISOString(),
        });

        io.emit('onlineUsersList', getOnlineUsers());
      }).catch(() => {
        const shortCode = generateShortCodeFromHash(uid);
        onlineUsers.set(uid, { socketId: socket.id, shortCode, displayName, profilePicBase64 });
        shortCodeToUserId.set(shortCode, uid);
        socket.emit('myShortCode', { shortCode });
      });

      io.emit('onlineUsersList', getOnlineUsers());
    } catch (error) {
      socket.emit('error', { message: 'Failed to register user' });
    }
  });

  socket.on('resolveShortCode', (data: any) => {
    if (!data || typeof data !== 'object') {
      socket.emit('resolveShortCodeResult', { found: false, shortCode: '' });
      return;
    }
    const code = (data.shortCode as string || '').toUpperCase().trim();
    if (!code) {
      socket.emit('resolveShortCodeResult', { found: false, shortCode: '' });
      return;
    }
    const targetUserId = shortCodeToUserId.get(code);
    if (targetUserId) {
      const info = onlineUsers.get(targetUserId);
      socket.emit('resolveShortCodeResult', {
        found: true,
        shortCode: code,
        userId: targetUserId,
        displayName: info?.displayName || '',
        profilePicBase64: info?.profilePicBase64 || '',
      });
    } else if (supabase) {
      const db = supabase as any;
      db
        .from('user_profiles')
        .select('user_id, display_name, profile_pic_base64, email')
        .ilike('short_code', code)
        .single()
        .then(({ data: profile }: any) => {
          if (profile) {
            socket.emit('resolveShortCodeResult', {
              found: true,
              shortCode: code,
              userId: profile.user_id,
              displayName: profile.display_name || profile.email || 'User',
              profilePicBase64: profile.profile_pic_base64 || '',
            });
          } else {
            socket.emit('resolveShortCodeResult', { found: false, shortCode: code });
          }
        })
        .catch(() => {
          socket.emit('resolveShortCodeResult', { found: false, shortCode: code });
        });
    } else {
      socket.emit('resolveShortCodeResult', { found: false, shortCode: code });
    }
  });

  socket.on('searchUsers', (data: any) => {
    if (!data || typeof data !== 'object') {
      socket.emit('searchUsersResult', { results: [] });
      return;
    }
    const query = typeof data.query === 'string' ? data.query.trim() : '';
    if (!query || query.length < 2) {
      socket.emit('searchUsersResult', { results: [] });
      return;
    }
    searchUsers(query, userId).then((results) => {
      socket.emit('searchUsersResult', { results });
    }).catch(() => {
      socket.emit('searchUsersResult', { results: [] });
    });
  });

  socket.on('checkUsername', (data: any) => {
    if (!data || typeof data !== 'object' || !supabase) {
      socket.emit('checkUsernameResult', { available: false, suggestions: [] });
      return;
    }
    const username = typeof data.username === 'string' ? data.username.trim().toLowerCase() : '';
    if (username.length < 3) {
      socket.emit('checkUsernameResult', { available: false, suggestions: [] });
      return;
    }
    if (!/^[a-z0-9_]+$/.test(username)) {
      socket.emit('checkUsernameResult', { available: false, suggestions: [] });
      return;
    }

    const db = supabase as any;
    db
      .from('user_profiles')
      .select('user_id')
      .ilike('username', username)
      .limit(1)
      .then(({ data: existing }: any) => {
        if (existing && existing.length > 0) {
          const suggestions = generateUsernameSuggestions(username);
          socket.emit('checkUsernameResult', { available: false, suggestions });
        } else {
          socket.emit('checkUsernameResult', { available: true, suggestions: [] });
        }
      })
      .catch(() => {
        socket.emit('checkUsernameResult', { available: false, suggestions: [] });
      });
  });

  socket.on('getMessages', async (data: any) => {
    if (!data || typeof data !== 'object' || !supabase) {
      socket.emit('messagesHistory', { roomId: data?.roomId || '', messages: [] });
      return;
    }
    const roomId = typeof data.roomId === 'string' ? data.roomId : '';
    const limit = typeof data.limit === 'number' ? Math.min(data.limit, 100) : 50;
    if (!roomId) {
      socket.emit('messagesHistory', { roomId: '', messages: [] });
      return;
    }

    const db = supabase as any;

    const verifiedUid = (socket.data.user?.uid || '') as string;
    if (!verifiedUid) {
      socket.emit('messagesHistory', { roomId, messages: [] });
      return;
    }

    let query;
    if (roomId.startsWith('group_')) {
      const groupId = roomId.slice('group_'.length);
      let isMember = groups.get(groupId)?.memberIds.includes(verifiedUid) ?? false;
      if (!isMember) {
        try {
          const { data: membership } = await db
            .from('group_members')
            .select('user_id')
            .eq('group_id', groupId)
            .eq('user_id', verifiedUid)
            .maybeSingle();
          isMember = !!membership;
        } catch {
          isMember = false;
        }
      }
      if (!isMember) {
        socket.emit('messagesHistory', { roomId, messages: [] });
        return;
      }
      query = db.from('messages').select(
        'id, room_id, sender_id, receiver_id, content, message_type, file_name, mime_type, attachment_size, status, timestamp, server_timestamp, reply_to_message_id, reply_to_content, reply_to_sender_id, group_id, forwarded_from, reactions'
      ).eq('group_id', groupId);
    } else {
      // 1:1 room — only actual participants may read it.
      query = db.from('messages').select(
        'id, room_id, sender_id, receiver_id, content, message_type, file_name, mime_type, attachment_size, status, timestamp, server_timestamp, reply_to_message_id, reply_to_content, reply_to_sender_id, group_id, forwarded_from, reactions'
      ).eq('room_id', roomId).or(`sender_id.eq.${verifiedUid},receiver_id.eq.${verifiedUid}`);
    }

    query
      .order('timestamp', { ascending: false })
      .limit(limit)
      .then(({ data: rows, error }: any) => {
        if (error) {
          socket.emit('messagesHistory', { roomId, messages: [] });
          return;
        }
        const messages = (rows || []).map((row: any) => ({
          id: row.id,
          roomId: row.room_id,
          senderId: row.sender_id,
          receiverId: row.receiver_id,
          content: row.content,
          messageType: row.message_type || 'text',
          fileName: row.file_name,
          mimeType: row.mime_type,
          attachmentSize: row.attachment_size,
          status: row.status || 'sent',
          timestamp: row.timestamp,
          serverTimestamp: row.server_timestamp,
          replyToMessageId: row.reply_to_message_id,
          replyToContent: row.reply_to_content,
          replyToSenderId: row.reply_to_sender_id,
          reactions: row.reactions && typeof row.reactions === 'object' ? row.reactions : {},
          groupId: row.group_id,
          forwardedFrom: row.forwarded_from,
        })).reverse();
        socket.emit('messagesHistory', { roomId, messages });
      })
      .catch(() => {
        socket.emit('messagesHistory', { roomId, messages: [] });
      });
  });

  socket.on('join-room', (roomId: string) => {
    const participantIds = roomId.split('_');
    const registeredId = socket.data.registeredUserId || userId;
    if (participantIds.length !== 2 || !participantIds.includes(registeredId)) {
      return;
    }
    socket.join(roomId);
  });

  for (const signalType of ['call:offer', 'call:answer', 'call:ice_candidate', 'call:reject', 'call:hangup']) {
    socket.on(signalType, (data: any) => {
      const senderId = socket.data.registeredUserId || userId;
      const targetId = data?.targetId as string;
      if (!targetId) return;

      let delivered = false;
      for (const recipientSocket of io.sockets.sockets.values()) {
        const registeredId = recipientSocket.data.registeredUserId;
        if (registeredId === targetId) {
          recipientSocket.emit(signalType, {
            senderId,
            targetId,
            data: data.data,
          });
          delivered = true;
        }
      }
    });
  }

  socket.on('sendMessage', async (data: any) => {
    try {
      const rateLimitId = (socket.data.registeredUserId || userId) as string;
      if (!checkRateLimit(rateLimitId, 'message')) {
        socket.emit('messageError', {
          id: data?.id,
          error: 'Rate limit exceeded. Please slow down.',
        });
        return;
      }

      if (!data || typeof data !== 'object') {
        socket.emit('messageError', { id: null, error: 'Invalid message format' });
        return;
      }

      const serverTimestamp = new Date().toISOString();
      
      const senderId = (socket.data.registeredUserId || userId) as string;
      const receiverId = data.receiverId as string;
      if (!senderId || !receiverId) {
        throw new Error('Invalid message participants');
      }

      const content = data.content as string;
      if (!content || typeof content !== 'string' || content.length > MAX_MESSAGE_SIZE) {
        socket.emit('messageError', {
          id: data?.id,
          error: 'Invalid message content',
        });
        return;
      }

      const validMessageTypes = ['text', 'image', 'audio', 'video', 'file', 'application/pdf'];
      const messageType = validMessageTypes.includes(data.messageType) ? data.messageType : 'text';

      // Reply metadata (optional, sanitized)
      const replyToMessageId = typeof data.replyToMessageId === 'string' && data.replyToMessageId
        ? data.replyToMessageId.slice(0, 128) : null;
      const replyToContent = typeof data.replyToContent === 'string' && data.replyToContent
        ? data.replyToContent.slice(0, 200) : null;
      const replyToSenderId = typeof data.replyToSenderId === 'string' && data.replyToSenderId
        ? data.replyToSenderId.slice(0, 128) : null;

      // Group vs 1:1 routing
      const groupId = typeof data.groupId === 'string' && data.groupId ? data.groupId : null;
      let correctRoomId: string;
      if (groupId) {
        const group = groups.get(groupId);
        let isMember = group?.memberIds.includes(senderId) ?? false;
        if (!isMember && supabase) {
          try {
            const { data: membership } = await (supabase as any).from('group_members')
              .select('user_id').eq('group_id', groupId).eq('user_id', senderId).maybeSingle();
            isMember = !!membership;
          } catch { /* treat as non-member */ }
        }
        if (!isMember) {
          socket.emit('messageError', { id: data?.id, error: 'Not a group member' });
          return;
        }
        correctRoomId = `group_${groupId}`;
      } else {
        if (!receiverId) throw new Error('Invalid message participants');
        correctRoomId = deriveRoomId(senderId, receiverId);
      }

      const message = {
        id: data.id,
        roomId: correctRoomId,
        senderId: senderId,
        receiverId: receiverId,
        content: content,
        messageType: messageType,
        fileName: data.fileName,
        mimeType: data.mimeType,
        attachmentBase64: data.attachmentBase64,
        attachmentSize: data.attachmentSize,
        status: 'sent',
        timestamp: data.timestamp,
        serverTimestamp,
        replyToMessageId,
        replyToContent,
        replyToSenderId,
        ...(groupId ? { groupId } : {}),
      };

      persistMessage(message);

      if (senderId === receiverId) {
        for (const recipientSocket of io.sockets.sockets.values()) {
          const registeredId =
            recipientSocket.data.registeredUserId || recipientSocket.data.user?.uid;
          if (registeredId !== senderId) continue;
          if (!recipientSocket.rooms.has(correctRoomId)) {
            recipientSocket.join(correctRoomId);
          }
          if (recipientSocket.id !== socket.id) {
            recipientSocket.emit('newMessage', message);
          }
        }
        socket.emit('messageAck', {
          id: data.id,
          status: 'sent',
          serverTimestamp,
        });
        return;
      }

      socket.to(correctRoomId).emit('newMessage', message);

      for (const recipientSocket of io.sockets.sockets.values()) {
        const registeredId = recipientSocket.data.registeredUserId || recipientSocket.data.user?.uid;
        if (registeredId !== receiverId || recipientSocket.id === socket.id) continue;
        if (!recipientSocket.rooms.has(correctRoomId)) {
          recipientSocket.join(correctRoomId);
          recipientSocket.emit('newMessage', message);
        }
      }

      socket.emit('messageAck', {
        id: data.id,
        status: 'sent',
        serverTimestamp,
      });
    } catch (error) {
      socket.emit('messageError', {
        id: data?.id,
        error: 'Failed to send message',
      });
    }
  });

  socket.on('typingStatus', (data: any) => {
    if (!data || typeof data !== 'object') return;
    const roomId = data.roomId as string;
    if (!roomId) return;

    if (data.groupId) {
      const groupId = data.groupId as string;
      const senderId = socket.data.registeredUserId || userId;
      const groupMembers = groups.get(groupId)?.memberIds || [];
      for (const recipientSocket of io.sockets.sockets.values()) {
        const rid = recipientSocket.data.registeredUserId;
        if (rid && groupMembers.includes(rid) && rid !== senderId) {
          recipientSocket.emit('typingStatus', {
            roomId,
            groupId,
            userId: senderId,
            isTyping: data.isTyping,
          });
        }
      }
      return;
    }

    if (!socket.rooms.has(roomId)) return;
    socket.to(roomId).emit('typingStatus', {
      roomId,
      userId: socket.data.registeredUserId || userId,
      isTyping: data.isTyping,
    });
  });

  socket.on('readReceipt', (data: any) => {
    if (!data || typeof data !== 'object') return;
    const roomId = data.roomId as string;
    if (!roomId) return;

    if (data.groupId) {
      const groupId = data.groupId as string;
      const senderId = socket.data.registeredUserId || userId;
      const groupMembers = groups.get(groupId)?.memberIds || [];
      for (const recipientSocket of io.sockets.sockets.values()) {
        const rid = recipientSocket.data.registeredUserId;
        if (rid && groupMembers.includes(rid) && rid !== senderId) {
          recipientSocket.emit('readReceipt', {
            roomId,
            groupId,
            userId: senderId,
            messageId: data.messageId,
          });
        }
      }
      return;
    }

    if (!socket.rooms.has(roomId)) return;
    socket.to(roomId).emit('readReceipt', {
      roomId,
      userId: socket.data.registeredUserId || userId,
      messageId: data.messageId,
    });
  });

  socket.on('reaction', async (data: any) => {
    if (!data || typeof data !== 'object') return;
    const senderId = socket.data.registeredUserId || userId;
    const targetId = data.targetId as string;
    const messageId = data.messageId as string;
    const emoji = typeof data.emoji === 'string' ? data.emoji.slice(0, 16) : '';
    const action = data.action === 'remove' ? 'remove' : 'add';
    if (!targetId || !messageId || !emoji) return;

    // Persist the toggle so reactions survive reloads.
    if (supabase && messageId.length <= 128) {
      try {
        const db = supabase as any;
        const { data: row } = await db.from('messages')
          .select('sender_id, receiver_id, group_id, reactions')
          .eq('id', messageId)
          .maybeSingle();
        if (row) {
          let allowed = false;
          const rowGroupId = row.group_id as string | null;
          if (rowGroupId) {
            allowed = groups.get(rowGroupId)?.memberIds.includes(senderId) ?? false;
            if (!allowed) {
              const { data: membership } = await db.from('group_members')
                .select('user_id').eq('group_id', rowGroupId).eq('user_id', senderId).maybeSingle();
              allowed = !!membership;
            }
          } else {
            allowed = row.sender_id === senderId || row.receiver_id === senderId;
          }

          if (allowed) {
            const current = (row.reactions && typeof row.reactions === 'object')
              ? { ...row.reactions } : {};
            const users = Array.isArray(current[emoji]) ? [...current[emoji]] : [];
            if (action === 'add') {
              if (!users.includes(senderId)) users.push(senderId);
            } else {
              const idx = users.indexOf(senderId);
              if (idx >= 0) users.splice(idx, 1);
            }
            if (users.length > 0) {
              current[emoji] = users;
            } else {
              delete current[emoji];
            }
            await db.from('messages').update({ reactions: current }).eq('id', messageId);
          }
        }
      } catch (err) {
        console.error('reaction persist error:', err);
      }
    }

    if (data.groupId) {
      const groupId = data.groupId as string;
      const groupMembers = groups.get(groupId)?.memberIds || [];
      for (const recipientSocket of io.sockets.sockets.values()) {
        const rid = recipientSocket.data.registeredUserId;
        if (rid && groupMembers.includes(rid) && rid !== senderId) {
          recipientSocket.emit('reaction', {
            senderId,
            messageId,
            emoji,
            groupId,
            action,
          });
        }
      }
    } else {
      for (const recipientSocket of io.sockets.sockets.values()) {
        if (recipientSocket.data.registeredUserId === targetId) {
          recipientSocket.emit('reaction', {
            senderId,
            messageId,
            emoji,
            action,
          });
        }
      }
    }
  });

  socket.on('updateProfile', (data: any) => {
    if (!data || typeof data !== 'object') return;
    const senderId = socket.data.registeredUserId || userId;
    const displayName = data.displayName as string;
    const profilePicBase64 = data.profilePicBase64 as string;

    const existing = onlineUsers.get(senderId);
    if (existing) {
      onlineUsers.set(senderId, {
        ...existing,
        displayName: displayName || existing.displayName,
        profilePicBase64: profilePicBase64 ?? existing.profilePicBase64,
      });
    }

    io.emit('userPresence', {
      userId: senderId,
      shortCode: existing?.shortCode || '',
      displayName: displayName || existing?.displayName || '',
      profilePicBase64: profilePicBase64 ?? (existing?.profilePicBase64 || ''),
      status: 'online',
      lastSeen: new Date().toISOString(),
    });
  });

  socket.on('createGroup', (data: any) => {
    if (!data || typeof data !== 'object') {
      socket.emit('error', { message: 'Invalid group data' });
      return;
    }

    const senderId = socket.data.registeredUserId || userId;
    const groupId = data.groupId as string;
    const groupName = typeof data.groupName === 'string'
      ? data.groupName.slice(0, MAX_DISPLAY_NAME_LENGTH)
      : '';
    const memberIds = Array.isArray(data.memberIds)
      ? (data.memberIds as string[]).slice(0, MAX_GROUP_MEMBERS)
      : [];

    if (!groupId || !groupName || memberIds.length === 0) return;
    if (!/^[A-Za-z0-9_-]{6,64}$/.test(groupId)) {
      socket.emit('error', { message: 'Invalid group id' });
      return;
    }
    if (groups.has(groupId)) {
      socket.emit('error', { message: 'Group already exists' });
      return;
    }

    const group = {
      id: groupId,
      name: groupName,
      creatorId: senderId,
      memberIds: [senderId, ...memberIds.filter((id: string) => id !== senderId)],
      createdAt: new Date().toISOString(),
    };
    groups.set(groupId, group);

    persistGroup(group);

    for (const memberId of group.memberIds) {
      for (const recipientSocket of io.sockets.sockets.values()) {
        if (recipientSocket.data.registeredUserId === memberId) {
          recipientSocket.emit('groupCreated', group);
          recipientSocket.join(`group_${groupId}`);
        }
      }
    }
  });

  socket.on('joinGroup', (data: any) => {
    if (!data || typeof data !== 'object') return;
    const senderId = socket.data.registeredUserId || userId;
    const groupId = data.groupId as string;
    if (!groupId) return;
    const group = groups.get(groupId);
    if (!group) return;
    if (!group.memberIds.includes(senderId)) {
      socket.emit('error', { message: 'Not a member of this group' });
      return;
    }

    socket.join(`group_${groupId}`);
    socket.emit('groupInfo', group);
  });

  socket.on('leaveGroup', (data: any) => {
    if (!data || typeof data !== 'object') return;
    const senderId = socket.data.registeredUserId || userId;
    const groupId = data.groupId as string;
    if (!groupId) return;
    const group = groups.get(groupId);
    if (!group) return;
    if (!group.memberIds.includes(senderId)) return;

    group.memberIds = group.memberIds.filter((id: string) => id !== senderId);
    if (group.memberIds.length === 0) {
      groups.delete(groupId);
    } else {
      groups.set(groupId, group);
    }
    socket.leave(`group_${groupId}`);
    socket.to(`group_${groupId}`).emit('groupMemberLeft', {
      groupId,
      userId: senderId,
    });
  });

  socket.on('disconnect', () => {
    for (const [uid, info] of onlineUsers.entries()) {
      if (info.socketId === socket.id) {
        const replacement = Array.from(io.sockets.sockets.values()).find(
          (activeSocket) =>
            activeSocket.data.registeredUserId === uid && activeSocket.id !== socket.id,
        );
        if (replacement) {
          onlineUsers.set(uid, { ...info, socketId: replacement.id });
          continue;
        }
        onlineUsers.delete(uid);
        shortCodeToUserId.delete(info.shortCode);
        io.emit('userPresence', {
          userId: uid,
          shortCode: info.shortCode,
          displayName: info.displayName,
          profilePicBase64: info.profilePicBase64,
          status: 'offline',
          lastSeen: new Date().toISOString(),
        });
        break;
      }
    }
  });
});

app.get('/health', (req, res) => {
  if (process.env.NODE_ENV === 'production') {
    res.json({ status: 'ok' });
  } else {
    res.json({ 
      status: 'ok', 
      onlineUsers: onlineUsers.size, 
      groups: groups.size,
      uptime: process.uptime(),
      memoryUsage: process.memoryUsage().heapUsed,
    });
  }
});

app.get('/api/check-username/:username', async (req, res) => {
  const username = (req.params.username || '').trim().toLowerCase();
  if (username.length < 3 || !/^[a-z0-9_]+$/.test(username)) {
    return res.json({ available: false, suggestions: [] });
  }
  if (!supabase) {
    return res.json({ available: true, suggestions: [] });
  }
  try {
    const db = supabase as any;
    const { data } = await db
      .from('user_profiles')
      .select('user_id')
      .ilike('username', username)
      .limit(1);
    if (data && data.length > 0) {
      const suggestions = generateUsernameSuggestions(username);
      return res.json({ available: false, suggestions });
    }
    return res.json({ available: true, suggestions: [] });
  } catch {
    return res.json({ available: false, suggestions: [] });
  }
});

app.post('/api/update-username', async (req, res) => {
  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Authentication required' });

  let userId: string;
  try {
    const app = firebaseApp;
    if (!app) return res.status(500).json({ error: 'Firebase not initialized' });
    const decoded = await getAuth(app).verifyIdToken(token);
    userId = decoded.uid;
  } catch {
    return res.status(401).json({ error: 'Invalid token' });
  }

  const { username } = req.body || {};
  const normalized = (username || '').trim().toLowerCase();
  if (normalized.length < 3 || !/^[a-z0-9_]+$/.test(normalized)) {
    return res.status(400).json({ error: 'Invalid username format' });
  }

  if (!supabase) {
    return res.status(500).json({ error: 'Database not available' });
  }

  try {
    const db = supabase as any;

    // Check if username is taken by another user
    const { data: existing } = await db
      .from('user_profiles')
      .select('user_id')
      .ilike('username', normalized)
      .neq('user_id', userId)
      .limit(1);

    if (existing && existing.length > 0) {
      const suggestions = generateUsernameSuggestions(normalized);
      return res.status(409).json({ error: 'Username already taken', suggestions });
    }

    // The live schema requires short_code (NOT NULL), so resolve the
    // permanent code first — otherwise first-time profile inserts violate
    // the constraint and the update fails.
    let shortCode: string;
    try {
      shortCode = await getOrCreatePermanentShortCode(userId);
    } catch (err: any) {
      console.error('update-username short-code resolution failed:', err?.message || err);
      shortCode = generateShortCodeFromHash(userId);
    }

    // Update username
    const { error } = await db
      .from('user_profiles')
      .upsert(
        {
          user_id: userId,
          short_code: shortCode,
          username: normalized,
        },
        { onConflict: 'user_id' },
      );

    if (error) {
      console.error('update-username upsert failed:', error.message);
      return res.status(500).json({ error: 'Failed to update username' });
    }

    return res.json({ success: true, username: normalized });
  } catch {
    return res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/api/update-email', async (req, res) => {
  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Authentication required' });

  let userId: string;
  let oldEmail: string;
  try {
    const app = firebaseApp;
    if (!app) return res.status(500).json({ error: 'Firebase not initialized' });
    const decoded = await getAuth(app).verifyIdToken(token);
    userId = decoded.uid;
    oldEmail = decoded.email || '';
  } catch {
    return res.status(401).json({ error: 'Invalid token' });
  }

  const { newEmail } = req.body || {};
  if (!newEmail || typeof newEmail !== 'string' || !newEmail.includes('@')) {
    return res.status(400).json({ error: 'Invalid email address' });
  }

  if (newEmail.toLowerCase() === oldEmail.toLowerCase()) {
    return res.status(400).json({ error: 'New email is the same as current email' });
  }

  if (!supabase) {
    return res.status(500).json({ error: 'Database not available' });
  }

  try {
    const db = supabase as any;

    // Check if email is already in use
    const { data: existing } = await db
      .from('user_profiles')
      .select('user_id')
      .ilike('email', newEmail)
      .neq('user_id', userId)
      .limit(1);

    if (existing && existing.length > 0) {
      return res.status(409).json({ error: 'Email is already in use by another account' });
    }

  // Same NOT NULL short_code requirement as update-username.
  let profileShortCode: string;
  try {
    profileShortCode = await getOrCreatePermanentShortCode(userId);
  } catch (err: any) {
    console.error('update-email short-code resolution failed:', err?.message || err);
    profileShortCode = generateShortCodeFromHash(userId);
  }

  // Update email in Supabase
  const { error } = await db
    .from('user_profiles')
    .upsert(
      {
        user_id: userId,
        short_code: profileShortCode,
        email: newEmail,
      },
      { onConflict: 'user_id' },
    );

  if (error) {
    console.error('update-email upsert failed:', error.message);
    return res.status(500).json({ error: 'Failed to update email in database' });
  }

    return res.json({ success: true, email: newEmail });
  } catch {
    return res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/turn-credentials', async (req, res) => {
  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith('Bearer ') 
    ? authHeader.slice(7) 
    : (req.query.token as string);

  if (!token) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    const app = firebaseApp;
    if (!app) return res.status(500).json({ error: 'Firebase not initialized' });
    await getAuth(app).verifyIdToken(token);
  } catch {
    return res.status(401).json({ error: 'Invalid authentication token' });
  }

  const turnUsername = process.env.TURN_USERNAME || '';
  const turnCredential = process.env.TURN_CREDENTIAL || '';
  const turnUrls = process.env.TURN_URLS?.split(',') || [];

  if (!turnUsername || !turnCredential || turnUrls.length === 0) {
    return res.status(503).json({ error: 'TURN credentials not configured' });
  }

  res.json({
    iceServers: [
      {
        urls: [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
      {
        urls: turnUrls,
        username: turnUsername,
        credential: turnCredential,
      },
    ],
  });
});

const CRASH_REPORT_EMAIL = process.env.CRASH_REPORT_EMAIL || 'denzelmathiba2@gmail.com';

const emailTransporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.SMTP_USER || '',
    pass: process.env.SMTP_APP_PASSWORD || '',
  },
});

const crashReportCounts = new Map<string, { count: number; resetTime: number }>();

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

app.post('/api/crash-report', async (req, res) => {
  try {
    const report = req.body;
    if (!report || !report.error) {
      return res.status(400).json({ error: 'Invalid crash report' });
    }

    const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown';
    const rateKey = clientIp as string;
    const now = Date.now();
    const existing = crashReportCounts.get(rateKey);
    if (existing && now < existing.resetTime) {
      if (existing.count >= 10) {
        return res.status(429).json({ error: 'Too many reports' });
      }
      existing.count++;
    } else {
      crashReportCounts.set(rateKey, { count: 1, resetTime: now + 60000 });
    }

    if (supabase) {
      try {
        await supabase.from('crash_reports').insert({
          app_version: report.appVersion || 'unknown',
          device_model: report.deviceModel || 'unknown',
          os_version: report.osVersion || 'unknown',
          error: report.error,
          stack_trace: report.stackTrace || '',
          screen: report.screen || '',
          user_id: report.userId || '',
          timestamp: report.timestamp || new Date().toISOString(),
          extra: report.extra || {},
        } as any);
      } catch (dbErr) {
        console.error('Failed to store crash report in Supabase:', dbErr);
      }
    }

    if (process.env.SMTP_USER && process.env.SMTP_APP_PASSWORD) {
      try {
        const html = `
          <div style="font-family: monospace; background: #1a1a2e; color: #e0e0e0; padding: 20px; border-radius: 8px;">
            <h2 style="color: #ff6b6b; margin: 0 0 16px 0;">GryChat Crash Report</h2>
            <table style="width: 100%; border-collapse: collapse;">
              <tr><td style="padding: 6px 12px; color: #888;">Timestamp</td><td style="padding: 6px 12px;">${escapeHtml(report.timestamp || new Date().toISOString())}</td></tr>
              <tr><td style="padding: 6px 12px; color: #888;">App Version</td><td style="padding: 6px 12px;">${escapeHtml(report.appVersion || 'unknown')}</td></tr>
              <tr><td style="padding: 6px 12px; color: #888;">Device</td><td style="padding: 6px 12px;">${escapeHtml(report.deviceModel || 'unknown')}</td></tr>
              <tr><td style="padding: 6px 12px; color: #888;">OS Version</td><td style="padding: 6px 12px;">${escapeHtml(report.osVersion || 'unknown')}</td></tr>
              <tr><td style="padding: 6px 12px; color: #888;">Screen</td><td style="padding: 6px 12px;">${escapeHtml(report.screen || 'N/A')}</td></tr>
              <tr><td style="padding: 6px 12px; color: #888;">User ID</td><td style="padding: 6px 12px;">${escapeHtml(report.userId || 'anonymous')}</td></tr>
            </table>
            <hr style="border-color: #333; margin: 16px 0;">
            <h3 style="color: #ff6b6b; margin: 0 0 8px 0;">Error</h3>
            <pre style="background: #0d1117; padding: 12px; border-radius: 6px; overflow-x: auto; color: #ff9a9a; font-size: 13px;">${escapeHtml(report.error)}</pre>
            ${report.stackTrace ? `
            <h3 style="color: #ff6b6b; margin: 16px 0 8px 0;">Stack Trace</h3>
            <pre style="background: #0d1117; padding: 12px; border-radius: 6px; overflow-x: auto; color: #8b949e; font-size: 12px; max-height: 400px; overflow-y: auto;">${escapeHtml(report.stackTrace)}</pre>
            ` : ''}
            ${report.extra && Object.keys(report.extra).length > 0 ? `
            <h3 style="color: #ff6b6b; margin: 16px 0 8px 0;">Extra Info</h3>
            <pre style="background: #0d1117; padding: 12px; border-radius: 6px; overflow-x: auto; color: #8b949e; font-size: 12px;">${escapeHtml(JSON.stringify(report.extra, null, 2))}</pre>
            ` : ''}
          </div>
        `;

        await emailTransporter.sendMail({
          from: `"GryChat Crash Reporter" <${process.env.SMTP_USER}>`,
          to: CRASH_REPORT_EMAIL,
          subject: `[Crash] GryChat ${escapeHtml((report.appVersion || '?').toString())} — ${escapeHtml(report.error.substring(0, 80))}`,
          html,
        });
        console.log(`Crash report email sent to ${CRASH_REPORT_EMAIL}`);
      } catch (emailErr) {
        console.error('Failed to send crash report email:', emailErr);
      }
    }

    res.json({ status: 'ok' });
  } catch (err) {
    console.error('crash-report error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

const PORT = process.env.PORT || 3000;

server.listen(PORT, () => {
  console.log(`GryChat server running on port ${PORT}`);
});

server.on('error', (error: NodeJS.ErrnoException) => {
  if (error.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is already in use`);
  } else {
    console.error('Server error:', error.message);
  }
  process.exit(1);
});

process.on('SIGTERM', () => {
  server.close(() => {
    process.exit(0);
  });
  setTimeout(() => {
    process.exit(1);
  }, 10000);
});

process.on('SIGINT', () => {
  server.close(() => {
    process.exit(0);
  });
  setTimeout(() => {
    process.exit(1);
  }, 10000);
});
