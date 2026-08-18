import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import { initializeApp, cert } from 'firebase-admin/app';
import type { App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { createClient } from '@supabase/supabase-js';
import 'dotenv/config';

// Initialize Firebase Admin SDK
let firebaseApp: App | null = null;
if (!firebaseApp) {
  const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (serviceAccount) {
    try {
      firebaseApp = initializeApp({
        credential: cert(JSON.parse(serviceAccount)),
      });
      console.log('[Firebase] Admin SDK initialized with service account');
    } catch (err) {
      console.error('[Firebase] Failed to parse FIREBASE_SERVICE_ACCOUNT JSON:', err);
      process.exit(1);
    }
  } else {
    // In production, fail hard without service account
    if (process.env.NODE_ENV === 'production') {
      console.error('[Firebase] FIREBASE_SERVICE_ACCOUNT is required in production');
      process.exit(1);
    }
    firebaseApp = initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID ?? 'dev-project',
    });
    console.log('[Firebase] Admin SDK initialized with project ID only (dev mode)');
  }
}

// Initialize Supabase client for database persistence
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;
let supabase: ReturnType<typeof createClient> | null = null;

if (supabaseUrl && supabaseKey) {
  supabase = createClient(supabaseUrl, supabaseKey);
  console.log('[Supabase] Client initialized for database persistence');
} else {
  console.warn('[Supabase] URL or key not provided, running without persistence');
}

// ─── Database Persistence Functions ──────────────────────────────────
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
        status: message.status,
        timestamp: message.timestamp,
        server_timestamp: message.serverTimestamp,
      } as any);
    
    if (error) {
      console.error('[DB] Failed to persist message:', error.message);
    }
  } catch (err) {
    console.error('[DB] Message persistence error:', err);
  }
}

async function persistGroup(group: any): Promise<void> {
  if (!supabase) return;
  
  try {
    // Insert group
    const { error: groupError } = await supabase
      .from('groups')
      .upsert({
        id: group.id,
        name: group.name,
        creator_id: group.creatorId,
        created_at: group.createdAt,
      } as any);
    
    if (groupError) {
      console.error('[DB] Failed to persist group:', groupError.message);
      return;
    }

    // Insert group members
    const members = group.memberIds.map((userId: string) => ({
      group_id: group.id,
      user_id: userId,
    }));
    
    const { error: membersError } = await supabase
      .from('group_members')
      .upsert(members, { onConflict: 'group_id,user_id' });
    
    if (membersError) {
      console.error('[DB] Failed to persist group members:', membersError.message);
    }
  } catch (err) {
    console.error('[DB] Group persistence error:', err);
  }
}

// ─── Rate Limiting ──────────────────────────────────────────────────
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX_CONNECTIONS = 10;
const RATE_LIMIT_MAX_MESSAGES = 60; // per minute
const MAX_MESSAGE_SIZE = 1 * 1024 * 1024; // 1 MB
const MAX_DISPLAY_NAME_LENGTH = 50;
const MAX_GROUP_MEMBERS = 100;

const connectionCounts = new Map<string, number>();
const messageCounts = new Map<string, number>();

function checkRateLimit(identifier: string, type: 'connection' | 'message'): boolean {
  const now = Date.now();
  
  if (type === 'connection') {
    const count = connectionCounts.get(identifier) || 0;
    if (count >= RATE_LIMIT_MAX_CONNECTIONS) return false;
    connectionCounts.set(identifier, count + 1);
    setTimeout(() => connectionCounts.delete(identifier), RATE_LIMIT_WINDOW_MS);
  }
  
  if (type === 'message') {
    const count = messageCounts.get(identifier) || 0;
    if (count >= RATE_LIMIT_MAX_MESSAGES) return false;
    messageCounts.set(identifier, count + 1);
    setTimeout(() => messageCounts.delete(identifier), RATE_LIMIT_WINDOW_MS);
  }
  
  return true;
}

// ─── CORS Configuration ────────────────────────────────────────────
const ALLOWED_ORIGINS = process.env.ALLOWED_ORIGINS?.split(',') || [
  'https://grychat.com',
];

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { 
    origin: ALLOWED_ORIGINS,
    methods: ['GET', 'POST'],
  },
  // Limit buffer size to 1 MB for security
  maxHttpBufferSize: MAX_MESSAGE_SIZE,
});

// ─── In-memory presence tracking ────────────────────────────────────
// Maps userId → { socketId, shortCode, displayName, profilePicBase64 }
const onlineUsers = new Map<string, {
  socketId: string;
  shortCode: string;
  displayName: string;
  profilePicBase64: string;
}>();

// Maps shortCode → userId (for finding users by short code)
const shortCodeToUserId = new Map<string, string>();

// Maps groupId → group info (in-memory group management)
const groups = new Map<string, {
  id: string;
  name: string;
  creatorId: string;
  memberIds: string[];
  createdAt: string;
}>();

// ─── Short Code Generator ────────────────────────────────────────────
function generateShortCode(userId: string): string {
  // Deterministic 6-char code from userId (GRY-XXXX)
  let hash = 0;
  for (let i = 0; i < userId.length; i++) {
    const char = userId.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  const code = Math.abs(hash).toString(36).toUpperCase().padStart(4, '0').slice(0, 4);
  return `GRY-${code}`;
}

function deriveRoomId(userA: string, userB: string): string {
  return [userA, userB].sort().join('_');
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

// ─── JWT Authentication Middleware ──────────────────────────────────
io.use(async (socket, next) => {
  try {
    const token = socket.handshake.auth.token;

    if (!token) {
      console.warn(`[Auth] No token for socket ${socket.id}, rejecting connection.`);
      return next(new Error('Authentication required'));
    }

    try {
      const decodedToken = await getAuth(firebaseApp!).verifyIdToken(token);
      socket.data.user = decodedToken;
      console.log(`[Auth] Authenticated socket ${socket.id} as user ${decodedToken.uid}`);
      next();
    } catch (error: any) {
      console.warn(`[Auth] Invalid token for socket ${socket.id}: ${error.message}`);
      return next(new Error('Invalid authentication token'));
    }
  } catch (error) {
    console.error('[Auth] Unexpected error in authentication middleware:', error);
    next(new Error('Authentication error'));
  }
});

// ─── Connection Handler ──────────────────────────────────────────────
io.on('connection', (socket) => {
  const userId = socket.data.user?.uid || socket.id;
  console.log(`✅ User connected: ${userId} (socket: ${socket.id})`);

  // ── Register Presence ─────────────────────────────────────────
  socket.on('register', (data: any) => {
    try {
      // Input validation
      if (!data || typeof data !== 'object') {
        socket.emit('error', { message: 'Invalid registration data' });
        return;
      }

      const uid = data.userId || userId;
      socket.data.registeredUserId = uid;
      const shortCode = generateShortCode(uid);
      
      // Validate and sanitize displayName
      const displayName = typeof data.deviceName === 'string' 
        ? data.deviceName.slice(0, MAX_DISPLAY_NAME_LENGTH) 
        : `User ${uid.substring(0, 8)}`;
      
      // Validate profilePicBase64 size
      const profilePicBase64 = typeof data.profilePicBase64 === 'string' && data.profilePicBase64.length < 1000000
        ? data.profilePicBase64 
        : '';

      onlineUsers.set(uid, { socketId: socket.id, shortCode, displayName, profilePicBase64 });
      shortCodeToUserId.set(shortCode, uid);

      console.log(`👤 Registered: ${uid} → ${shortCode} | Online: ${onlineUsers.size}`);

      // Send this user's own short code back to them
      socket.emit('myShortCode', { shortCode });

      // Broadcast this user's online status to all other connected clients
      socket.broadcast.emit('userPresence', {
        userId: uid,
        shortCode,
        displayName,
        profilePicBase64,
        status: 'online',
        lastSeen: new Date().toISOString(),
      });

      // Send a complete snapshot to every client so presence does not depend
      // on registration event order.
      io.emit('onlineUsersList', getOnlineUsers());
    } catch (error) {
      console.error('[Register] Error:', error);
      socket.emit('error', { message: 'Failed to register user' });
    }
  });

  // ── Resolve Short Code → UserId ───────────────────────────────
  socket.on('resolveShortCode', (data: any) => {
    const code = (data.shortCode as string || '').toUpperCase().trim();
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
    } else {
      socket.emit('resolveShortCodeResult', { found: false, shortCode: code });
    }
  });

  // ── Join Room (conversation) ──────────────────────────────────
  socket.on('join-room', (roomId: string) => {
    const participantIds = roomId.split('_');
    const registeredId = socket.data.registeredUserId || userId;
    console.log(`[Room] join-room request from ${registeredId} for ${roomId} | participants=${JSON.stringify(participantIds)} | registered=${registeredId}`);
    if (participantIds.length !== 2 || !participantIds.includes(registeredId)) {
      console.warn(`[Room] Rejected unauthorized room join by ${registeredId}: ${roomId}`);
      return;
    }
    socket.join(roomId);
    console.log(`🏠 User ${registeredId} joined room: ${roomId} | rooms now: ${JSON.stringify(Array.from(socket.rooms))}`);
  });

  // ── WebRTC Call Signaling ────────────────────────────────────
  // Audio/video call signaling (prefixed to avoid collision with P2P data channel signaling)
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
      console.log(`[Signal] ${signalType} from ${senderId} → ${targetId} (delivered: ${delivered})`);
    });
  }

  // ── Send Message ──────────────────────────────────────────────
  socket.on('sendMessage', (data: any) => {
    try {
      // Rate limiting (per-user, not per-socket)
      const rateLimitId = (socket.data.registeredUserId || userId) as string;
      if (!checkRateLimit(rateLimitId, 'message')) {
        socket.emit('messageError', {
          id: data?.id,
          error: 'Rate limit exceeded. Please slow down.',
        });
        return;
      }

      // Input validation
      if (!data || typeof data !== 'object') {
        socket.emit('messageError', { id: null, error: 'Invalid message format' });
        return;
      }

      const serverTimestamp = new Date().toISOString();
      
      // Derive correct roomId from sorted user IDs (data isolation)
      const senderId = (socket.data.registeredUserId || data.senderId) as string;
      const receiverId = data.receiverId as string;
      if (!senderId || !receiverId) {
        throw new Error('Invalid message participants');
      }

      // Validate content
      const content = data.content as string;
      if (!content || typeof content !== 'string' || content.length > MAX_MESSAGE_SIZE) {
        socket.emit('messageError', {
          id: data?.id,
          error: 'Invalid message content',
        });
        return;
      }

      // Validate message type
      const validMessageTypes = ['text', 'image', 'audio', 'video', 'file', 'application/pdf'];
      const messageType = validMessageTypes.includes(data.messageType) ? data.messageType : 'text';

      const correctRoomId = deriveRoomId(senderId, receiverId);
      
      // Warn if client sent wrong roomId (security/debugging)
      if (data.roomId !== correctRoomId) {
        console.warn(
          `[SendMessage] RoomId mismatch for message ${data.id}: ` +
          `client sent "${data.roomId}", using correct "${correctRoomId}"`
        );
      }
      
      const message = {
        id: data.id,
        roomId: correctRoomId, // Use derived roomId, not client-provided
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
      };

      // Persist message to database (fire and forget)
      persistMessage(message);

      // Self-chat (Saved Messages): deliver back to the sender's own sockets
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

      // Route to the conversation room. The recipient is auto-added below
      // only when they are not already in the room, preventing duplicates.
      socket.to(correctRoomId).emit('newMessage', message);

      // Also deliver to every active socket for the recipient. A user can
      // have multiple app windows or a reconnecting socket at the same time.
      for (const recipientSocket of io.sockets.sockets.values()) {
        const registeredId = recipientSocket.data.registeredUserId || recipientSocket.data.user?.uid;
        if (registeredId !== receiverId || recipientSocket.id === socket.id) continue;
        if (!recipientSocket.rooms.has(correctRoomId)) {
          recipientSocket.join(correctRoomId);
          recipientSocket.emit('newMessage', message);
        }
      }

      // Acknowledge back to the sender
      socket.emit('messageAck', {
        id: data.id,
        status: 'sent',
        serverTimestamp,
      });

      console.log(`💬 Message ${data.id} routed in room ${correctRoomId} → ${receiverId}`);
    } catch (error) {
      console.error('[SendMessage] Error:', error);
      socket.emit('messageError', {
        id: data?.id,
        error: 'Failed to send message',
      });
    }
  });

  // ── Typing Status ─────────────────────────────────────────────
  socket.on('typingStatus', (data: any) => {
    const roomId = data.roomId as string;
    if (!roomId) return;

    // For group chats, forward to all members except sender
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

    // 1:1 chat — use room-based forwarding
    if (!socket.rooms.has(roomId)) return;
    socket.to(roomId).emit('typingStatus', {
      roomId,
      userId: socket.data.registeredUserId || userId,
      isTyping: data.isTyping,
    });
  });

  // ── Read Receipt ──────────────────────────────────────────────
  socket.on('readReceipt', (data: any) => {
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

  // ── Reaction (add/remove emoji on a message) ─────────────────
  socket.on('reaction', (data: any) => {
    const senderId = socket.data.registeredUserId || userId;
    const targetId = data.targetId as string;
    const messageId = data.messageId as string;
    const emoji = data.emoji as string;
    if (!targetId || !messageId || !emoji) return;

    // Route to target user (1:1) or group members
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
            action: data.action, // 'add' or 'remove'
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
            action: data.action,
          });
        }
      }
    }
    console.log(`[Reaction] ${data.action} ${emoji} on ${messageId} from ${senderId}`);
  });

  // ── Profile Update ───────────────────────────────────────────
  socket.on('updateProfile', (data: any) => {
    const senderId = socket.data.registeredUserId || userId;
    const displayName = data.displayName as string;
    const profilePicBase64 = data.profilePicBase64 as string;

    // Update in online users map
    const existing = onlineUsers.get(senderId);
    if (existing) {
      onlineUsers.set(senderId, {
        ...existing,
        displayName: displayName || existing.displayName,
        profilePicBase64: profilePicBase64 ?? existing.profilePicBase64,
      });
    }

    // Broadcast updated presence to all
    io.emit('userPresence', {
      userId: senderId,
      shortCode: existing?.shortCode || '',
      displayName: displayName || existing?.displayName || '',
      profilePicBase64: profilePicBase64 ?? (existing?.profilePicBase64 || ''),
      status: 'online',
      lastSeen: new Date().toISOString(),
    });

    console.log(`[Profile] Updated: ${senderId} → ${displayName}`);
  });

  // ── Group Management ─────────────────────────────────────────
  socket.on('createGroup', (data: any) => {
    // Input validation
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

    const group = {
      id: groupId,
      name: groupName,
      creatorId: senderId,
      memberIds: [senderId, ...memberIds.filter((id: string) => id !== senderId)],
      createdAt: new Date().toISOString(),
    };
    groups.set(groupId, group);

    // Persist group to database (fire and forget)
    persistGroup(group);

    // Notify all members
    for (const memberId of group.memberIds) {
      for (const recipientSocket of io.sockets.sockets.values()) {
        if (recipientSocket.data.registeredUserId === memberId) {
          recipientSocket.emit('groupCreated', group);
          recipientSocket.join(`group_${groupId}`);
        }
      }
    }
    console.log(`[Group] Created: ${groupName} (${groupId}) by ${senderId} with ${group.memberIds.length} members`);
  });

  socket.on('joinGroup', (data: any) => {
    const groupId = data.groupId as string;
    const group = groups.get(groupId);
    if (!group) return;

    socket.join(`group_${groupId}`);
    socket.emit('groupInfo', group);
    console.log(`[Group] User joined: ${socket.data.registeredUserId} → ${group.name}`);
  });

  socket.on('leaveGroup', (data: any) => {
    const senderId = socket.data.registeredUserId || userId;
    const groupId = data.groupId as string;
    const group = groups.get(groupId);
    if (!group) return;

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
    console.log(`[Group] User left: ${senderId} ← ${group.name}`);
  });

  // ── Disconnect ────────────────────────────────────────────────
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
        console.log(`❌ Disconnected: ${uid} | Online: ${onlineUsers.size}`);
        break;
      }
    }
  });
});

// ─── Health Check Endpoint ───────────────────────────────────────────
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

// ─── TURN Credentials Endpoint ──────────────────────────────────────
// Requires authentication to prevent credential harvesting
app.get('/turn-credentials', async (req, res) => {
  // Verify Firebase token from query param or header
  const authHeader = req.headers.authorization;
  const token = authHeader?.startsWith('Bearer ') 
    ? authHeader.slice(7) 
    : (req.query.token as string);

  if (!token) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    await getAuth(firebaseApp!).verifyIdToken(token);
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

const PORT = process.env.PORT || 3000;

// ─── Server Startup with Error Handling ──────────────────────────────
server.listen(PORT, () => {
  console.log(`🚀 Chat Server running on port ${PORT}`);
});

server.on('error', (error: NodeJS.ErrnoException) => {
  if (error.code === 'EADDRINUSE') {
    console.error(`❌ Port ${PORT} is already in use`);
  } else {
    console.error(`❌ Server error: ${error.message}`);
  }
  process.exit(1);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('📋 SIGTERM received, shutting down gracefully...');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
  // Force shutdown after 10 seconds
  setTimeout(() => {
    console.error('❌ Forcing shutdown after timeout');
    process.exit(1);
  }, 10000);
});

process.on('SIGINT', () => {
  console.log('⏹️  SIGINT received, shutting down gracefully...');
  server.close(() => {
    console.log('✅ Server closed');
    process.exit(0);
  });
  setTimeout(() => {
    console.error('❌ Forcing shutdown after timeout');
    process.exit(1);
  }, 10000);
});
