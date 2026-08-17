# Grychat Current Project Summary

## Current State

Grychat is a Flutter chat client with a Node.js, Express, and Socket.io backend.
The current Windows build supports text messaging, emojis, image attachments, audio attachments, video attachments, and generic files.

The tested local setup is:

- Flutter Windows client: `grychat/`
- TypeScript signaling and chat backend: `backend/`
- Backend URL: `http://127.0.0.1:3000`
- Local database: Hive
- Authentication and application configuration: Supabase
- Media playback: Flutter audio and video plugins

## Completed Work

### Backend

- Express health endpoint at `/health`.
- Socket.io connections with reconnect support on the Flutter client.
- Presence registration and online-user discovery.
- Stable `GRY-XXXX` short codes for online users.
- Short-code resolution before opening a conversation.
- Conversation room IDs derived consistently from sorted user IDs using `_`.
- Room membership checks so a socket can only join a room containing its registered user.
- Message routing to the intended recipient and conversation room.
- Duplicate room-plus-direct delivery prevention.
- Typing status and read receipts routed through the authorized conversation room.
- Attachment payload forwarding with a 25 MB Socket.io buffer limit.
- Health monitoring through `/health`.

The backend currently accepts connections without a token as guest sockets. Supabase JWTs are accepted and stored when present, but strict authentication is still a hardening task.

### Flutter Client

- Supabase initialization.
- Hive persistence for profiles, peers, messages, and chat attachments.
- Optimistic message sending with `sending` and `sent` states.
- Incoming-message filtering so messages for unrelated users are ignored.
- Message ID deduplication during reconnects and room/direct delivery overlap.
- Conversation list filtering by the active local user.
- Emoji picker and Unicode emoji text support.
- File picker support for images, audio, video, and other files.
- Attachment metadata including filename, MIME type, size, and encoded bytes.
- Inline image previews with tap-to-zoom viewing.
- Inline audio playback with play/pause and seeking.
- Inline video playback with play/pause and scrubbing.
- Generic document attachment opening through the operating system.

## Attachment Behavior

Supported media is transferred inside the chat message and remains associated with the same validated conversation room.

| Type | Current behavior |
|---|---|
| Text | Rendered directly in the chat bubble |
| Emoji | Rendered as normal Unicode text or inserted with the emoji picker |
| Image | Inline preview and zoomable viewer |
| Audio | Inline player with play/pause and seek controls |
| Video | Inline player with play/pause and scrub controls |
| PDF, ZIP, and other documents | Stored in the message and opened with the system application |

The client limits selected attachments to 18 MB before sending. The backend Socket.io payload limit is 25 MB.

## Security and Isolation Fixes

The original message problems were caused by inconsistent room formats and untrusted routing data.

These issues are now addressed by:

1. Using the same room format in Flutter and the backend: `sortedUserA_sortedUserB`.
2. Deriving the server routing room from the sender and recipient instead of trusting the submitted room ID.
3. Deriving the sender from the registered socket user when available.
4. Rejecting unauthorized room joins.
5. Filtering incoming messages against the local user ID.
6. Deduplicating messages by message ID in the chat provider.

## Verification Completed

The following checks have passed during development:

```powershell
cd backend
npx tsc --noEmit
```

```powershell
cd grychat
flutter pub get
flutter build windows
```

The Windows build has been successfully generated at:

`grychat/build/windows/x64/runner/Release/grychat.exe`

Two Windows instances have been launched successfully using separate profiles:

```powershell
$env:APP_PROFILE = "peer1"
Start-Process grychat/build/windows/x64/runner/Release/grychat.exe

$env:APP_PROFILE = "peer2"
Start-Process grychat/build/windows/x64/runner/Release/grychat.exe

Remove-Item Env:APP_PROFILE -ErrorAction SilentlyContinue
```

Text-message routing and conversation isolation were verified between the two instances. The backend health endpoint also responded successfully during testing.

Flutter analysis still reports seven existing warnings and informational findings unrelated to the attachment transport:

- Deprecated Supabase `anonKey` parameter.
- Missing type annotation for the chat service field.
- Dangling library documentation comment.
- Unused error-boundary import and members.

## Current Provider Note

The project currently contains signaling providers for both chat and WebRTC. This can create more than one Socket.io connection per app instance. The extra connections are visible in `/health` as anonymous or duplicate socket identities.

Before production, consolidate the signaling ownership so chat signaling and WebRTC signaling do not create unnecessary connections.

## Remaining Work

### Priority 1: Calls

- Consolidate the duplicate signaling providers.
- Add an incoming-call state and call invitation events.
- Build an incoming-call screen with accept, decline, and cancel actions.
- Add audio-call controls: mute, speaker, end call.
- Add video-call controls: camera toggle, mute, camera switch, end call.
- Add call connection, failure, and timeout states.
- Verify WebRTC offer, answer, and ICE exchange between two Windows instances.

### Priority 2: Security Hardening

- Require valid Supabase JWTs in production.
- Derive the registered user only from verified token claims.
- Add payload validation for messages and signaling events.
- Add rate limiting and attachment abuse limits.
- Remove any exposed API keys from Continue configuration and rotate them.

### Priority 3: Reliability and Operations

- Add automated backend tests for room isolation and message routing.
- Add Flutter tests for message filtering and attachment rendering.
- Add a clean production TypeScript build and `dist/` output configuration.
- Add CI validation for TypeScript and Flutter builds.
- Replace base64 message transport with object storage for larger media files.

## Running Locally

Start the backend from its own directory:

```powershell
cd backend
npm run dev
```

Build and run the Flutter Windows client:

```powershell
cd grychat
flutter build windows
```

For two isolated local instances, set `APP_PROFILE` to different values before launching each process, or simply use the provided `Launch_Grychats.bat` which automatically does this and launches the debug build.

## Recent Fixes (Agent Logs)

- **Multiple Instances Support (Launch_Grychats.bat):** Fixed issues with instances failing to launch from PowerShell by creating a batch file that properly sets the working directory, injects isolated `APP_PROFILE` environment variables, and launches the debug builds natively to ensure windows appear interactively.
- **Video Player Fallback (Windows):** Resolved an issue where unsupported videos (or audio files sent with video extensions like `.mpeg`) would cause an endless loading spinner because `video_player_win` swallowed the codec initialization error. The UI now gracefully catches this state and renders a "Play in System Player" fallback button, allowing the user to open unsupported media natively in VLC/Windows Media Player.
- **WhatsApp Audio Detection:** Improved the attachment rendering logic to check for 'WhatsApp Audio' in both `fileName` and `content`. If matched, it correctly routes the file to the more robust `_AudioAttachmentPlayer` rather than attempting to initialize it as a video.
- **Backend `groups` variable fix:** Added missing `groups` Map declaration in `backend/index.ts` that caused 8 TypeScript compilation errors. Group chat operations now work at runtime.
- **Deleted `signaling_server/` duplicate:** Removed the legacy standalone signaling server that conflicted on port 3000 with the main backend.
- **Firebase credentials configured:** Replaced placeholder Firebase config in `main.dart` with real project credentials (`graychat-db6a0`).
- **Supabase defaults set:** Updated `app_config.dart` with real Supabase URL and anon key from the backend `.env`.
- **JWT_SECRET generated:** Backend `.env` now uses a randomly generated 64-char hex JWT secret.
- **All 9 Dart warnings eliminated:** Removed dead code (`authUser` null check), unused fields (`_isSendingVoice`, `_stackTrace`), unused imports/methods (`_showCreateGroupDialog`, `_handleError`, `_showErrorDialog`, `showErrorDialog`), and fixed `catchError` return type.
- **Firebase init failure handled:** Wrapped Firebase.initializeApp and Supabase.initialize in try-catch so the app falls back to guest mode if credentials are missing.
- **Git committed:** Full project state saved across 3 commits (56 files changed) with `.env` properly excluded from version control.
- **Dockerized backend:** Docker Desktop 29.7.2 installed (WSL2 engine verified). Built `grychat-backend` image from `backend/Dockerfile` (multi-stage: `npm ci` + `tsc` build, then `node dist/index.js` on port 3000). Running as container `grychat-backend` with `--restart unless-stopped`, port 3000 published, and `backend/.env` mounted read-only at `/app/.env`.
- **Docker launch verified:** `/health` responds from the container (`{"status":"ok","onlineUsers":2}`) and both Flutter peer instances (`peer1`/`peer2`) registered successfully. Backend no longer needs `npm run dev`; start it with `docker start grychat-backend`.
