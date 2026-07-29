import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import jwt from 'jsonwebtoken';
import 'dotenv/config';

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" },
  // Attachments are base64 encoded by the Flutter client before transport.
  // Leave headroom for that encoding and the surrounding Socket.IO payload.
  maxHttpBufferSize: 75 * 1024 * 1024,
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
io.use((socket, next) => {
  try {
    const token = socket.handshake.auth.token;
    const secret = process.env.JWT_SECRET;

    if (!token) {
      console.log(`[Auth] No token for socket ${socket.id}, proceeding as guest.`);
      return next();
    }

    if (!secret || secret === 'change-me-to-a-random-secret') {
      console.warn('[Auth] WARNING: JWT_SECRET not configured properly, skipping verification');
      return next();
    }

    jwt.verify(token, secret, (err: any, decoded: any) => {
      if (err) {
        console.warn(`[Auth] Invalid token for socket ${socket.id}: ${err.message}`);
        return next(new Error('Authentication failed'));
      }
      socket.data.user = decoded;
      console.log(`[Auth] Authenticated socket ${socket.id} as user ${decoded.sub}`);
      next();
    });
  } catch (error) {
    console.error('[Auth] Unexpected error in authentication middleware:', error);
    next();
  }
});

// ─── Connection Handler ──────────────────────────────────────────────
io.on('connection', (socket) => {
  const userId = socket.data.user?.sub || socket.id;
  console.log(`✅ User connected: ${userId} (socket: ${socket.id})`);

  // ── Register Presence ─────────────────────────────────────────
  socket.on('register', (data: any) => {
    try {
      const uid = data.userId || userId;
      socket.data.registeredUserId = uid;
      const shortCode = generateShortCode(uid);
      const displayName = data.deviceName || `User ${uid.substring(0, 8)}`;
      const profilePicBase64 = data.profilePicBase64 || '';

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

  // ── WebRTC Signaling (direct socket routing) ──────────────────
  for (const signalType of ['offer', 'answer', 'ice_candidate', 'reject', 'hangup']) {
    socket.on(signalType, (data: any) => {
      const senderId = socket.data.registeredUserId || userId;
      const targetId = data?.targetId as string;
      if (!targetId) return;

      // Find target user's socket(s) and forward directly
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
      const serverTimestamp = new Date().toISOString();
      
      // Derive correct roomId from sorted user IDs (data isolation)
      const senderId = (socket.data.registeredUserId || data.senderId) as string;
      const receiverId = data.receiverId as string;
      if (!senderId || !receiverId || senderId === receiverId) {
        throw new Error('Invalid message participants');
      }
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
        content: data.content,
        messageType: data.messageType || 'text',
        fileName: data.fileName,
        mimeType: data.mimeType,
        attachmentBase64: data.attachmentBase64,
        attachmentSize: data.attachmentSize,
        status: 'sent',
        timestamp: data.timestamp,
        serverTimestamp,
      };

      // Route to the conversation room. The recipient is auto-added below
      // only when they are not already in the room, preventing duplicates.
      socket.to(correctRoomId).emit('newMessage', message);

      // Also deliver to every active socket for the recipient. A user can
      // have multiple app windows or a reconnecting socket at the same time.
      for (const recipientSocket of io.sockets.sockets.values()) {
        const registeredId = recipientSocket.data.registeredUserId || recipientSocket.data.user?.sub;
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
    const senderId = socket.data.registeredUserId || userId;
    const groupId = data.groupId as string;
    const groupName = data.groupName as string;
    const memberIds = (data.memberIds as string[]) || [];
    if (!groupId || !groupName || memberIds.length === 0) return;

    const group = {
      id: groupId,
      name: groupName,
      creatorId: senderId,
      memberIds: [senderId, ...memberIds.filter((id: string) => id !== senderId)],
      createdAt: new Date().toISOString(),
    };
    groups.set(groupId, group);

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
  const users = Array.from(onlineUsers.entries()).map(([id, info]) => ({
    userId: id,
    shortCode: info.shortCode,
    displayName: info.displayName,
  }));
  res.json({ status: 'ok', onlineUsers: onlineUsers.size, users, uptime: process.uptime() });
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
