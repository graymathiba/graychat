# AI Session Context

**Last Updated**: 2026-08-22

## Current Task
- Security audit + UX polish pass complete (session 7). All work UNCOMMITTED on main.

## Previous Sessions
- 2026-08-17: Initial context setup, discovered auth inconsistency between Firebase/Supabase
- 2026-08-17: Fixed auth - rewrote AuthService to use Firebase Auth, updated backend to use Firebase Admin SDK
- 2026-08-17: Enforced backend JWT auth, built Group Chat UI
- 2026-08-17: Production readiness - security hardening, database persistence, Docker deployment
- 2026-08-17: Production security audit and fixes - 12 issues resolved
- 2026-08-18: Completed all remaining priority items (WebRTC cleanup, RLS, security, offline queue, FCM, tests, CI/CD, legal docs)
- 2026-08-22: GryCode collision fix + deep security audit (backend authz gaps) + Android hardening + client socket auth + dark-mode/UX fixes

## Important Notes
- This file tracks what I was working on so I can resume in future sessions
- **Firebase** = Authentication + Crashlytics + Cloud Messaging
- **Supabase** = Storage + Database (PostgreSQL)
- **Docker** runs on Node 22-alpine (required for Supabase SDK WebSocket support)
- Backend prefers SUPABASE_SERVICE_ROLE_KEY → RLS bypassed server-side; backend code IS the security boundary
- CI runs `flutter analyze --no-fatal-infos` (any info fails) + `flutter test` + backend `npm ci` (package-lock.json EXISTS ✓)
- NEVER edit files via PowerShell Set-Content/-replace (corrupts UTF-8); use the Edit tool only
- GryCode = FNV-1a + murmur3 fmix32, `(h>>>0)%1679616` base36 upper padded 4 → GRY-XXXX; mirrors in backend/index.ts, backend/test.ts, chat_provider.dart MUST stay in sync. Ref values: user_a→GRY-VXRU, user_b→GRY-VZAS, test-user-id-123→GRY-H412, user123→GRY-MANC
- file_picker is now ^12.0.0 STABLE — API changed: pickFiles() returns List<PlatformFile> directly (no FilePickerResult), PlatformFile has no `.extension` getter (derive from name)

## Changes Made (2026-08-22 - Session 7)

### GryCode Collision Fix
1. Fixed FNV-1a implementation in all 3 mirrors (backend/index.ts generateShortCodeFromHash(userId, salt=''), backend/test.ts mirror, chat_provider.dart _deriveShortCode with web-safe _mul32 using 16-bit decomposition)
2. Web-safe masking for Flutter Web JS int32: ((hash>>16)&0xFFFF), ((hash>>13)&0x1FFFFF)
3. Added collision retry loop in getOrCreatePermanentShortCode (10 salt attempts)
4. Added deriveShortCodeForTest (@visibleForTesting) + test/short_code_test.dart parity contract (meta ^1.15.0 added to pubspec)

### Backend Security Fixes (index.ts)
5. CRITICAL register handler: `data.userId || userId` → JWT uid only (identity spoofing)
6. CRITICAL getMessages: added participant authorization (1:1 via user_profiles query, group via group_members/membership map); non-members get empty history
7. sendMessage: senderId no longer trusts data.senderId fallback
8. createGroup: rejects existing groupId (takeover) + validates /^[A-Za-z0-9_-]{6,64}$/
9. express.json({limit:'1mb'}) moved BEFORE routes (was after → /api/update-username & /api/update-email had undefined req.body = broken)
10. Crash report email HTML injection fixed via escapeHtml() on all fields
11. searchUsers no longer returns email addresses

### Client Security Fixes
12. chat_service.dart connect(): fresh Firebase token per connection attempt passed via 'auth' option; aborts when no token; reconnection:false (app's own backoff loop handles reconnects with fresh tokens — removed fragile (s.io as dynamic).opts['auth'] mutation that sent stale tokens)
13. login_screen.dart + forgot_password_screen.dart: anti-enumeration generic errors ('user-not-found'/'wrong-password' → 'Invalid email or password'; forgot-password shows success even when user-not-found)
14. main.dart ErrorWidget.builder no longer leaks raw exception text to users (Crashlytics still gets it)
15. AndroidManifest: allowBackup=false + fullBackupContent=false, removed READ/WRITE_EXTERNAL_STORAGE + RECEIVE_BOOT_COMPLETED permissions
16. build.gradle.kts release signing now THROWS if key.properties missing (was silently falling back to debug key)
17. network_security_config.xml: REMOVED fabricated certificate pin-set (pins were placeholders that would self-DoS api.grychat.com once real); kept dev-only cleartext hosts

### Dependencies
18. file_picker: ^12.0.0-beta.7 → ^12.0.0 stable (+ API migration in home_screen.dart/chat_screen.dart: pickFiles returns list directly, .extension getter removed)
19. device_info_plus: exact pin 13.2.0 → ^13.2.0

### UX/UI Polish
20. complete_profile_screen: removed 'Jhone' prefill bug, saving spinner + button disable, dark-mode-safe inputs/avatar/hints
21. Dark-mode fixes across welcome_screen (phone input), home_screen (action tiles, search dialog input+result card, list dividers, timestamps/subtitle colors), chat_screen (composer fill), forgot_password_screen (scaffold bg)
22. App-wide page transitions: FadeUpwards (Android/Windows/Linux), Zoom (iOS/macOS) via PageTransitionsTheme in _buildTheme

### Verification (all green)
- flutter analyze: No issues found
- flutter test: 18/18 pass
- backend npm run test (build + node --test): 11/11 pass

## Changes Made (2026-08-18 - Session 6: Complete Remaining Items)

### Dead Code Removal
1. **Deleted 5 dead WebRTC files** - webrtc_service.dart, webrtc_provider.dart, signaling_service.dart, signaling_provider.dart, incoming_call_overlay.dart (~800 lines)
2. **Removed dead P2P signaling relay** from backend (offer/answer/ice_candidate without call: prefix)
3. **Removed dead getTurnCredentials() method** from app_config.dart
4. **Removed signaling provider references** from main.dart

### Security Hardening
5. **Tightened Supabase RLS policies** - groups and group_members no longer world-readable
6. **Added profiles INSERT policy** for backup profile creation
7. **Added messages UPDATE/DELETE policies** for sender-only operations
8. **Added group_members DELETE policies** for creator and self-leave
9. **Created Android network_security_config.xml** with certificate pinning for api.grychat.com
10. **Added POST_NOTIFICATIONS permission** for Android push notifications

### New Features
11. **Implemented offline message queue** - messages retry on reconnect
12. **Added FCM push notifications** - firebase_messaging integration with background handler
13. **Added retry button for failed messages** - tappable error icon in chat UI
14. **Upgraded Docker to Node 22** - required for Supabase SDK WebSocket support

### Testing & CI/CD
15. **Added Flutter unit tests** - ChatMessage, Group, AppConfig tests
16. **Added backend tests** - roomId derivation, short code generation, message validation
17. **Set up GitHub Actions CI/CD** - backend test, flutter analyze, docker build

### Legal & Documentation
18. **Wrote Privacy Policy** - GDPR-compliant, covers data collection and user rights
19. **Wrote Terms of Service** - acceptable use, liability limitations, dispute resolution

## Changes Made (2026-08-17 - Session 5: Production Security Fixes)
### Critical Fixes
1. **Deleted stale `backend/index.js` files** - had auth bypass, open CORS (`origin: "*"`), 75MB buffer, no rate limiting
2. **Fixed `.gitignore`** - now covers all `.env.*` variants (was missing `.env.production`)
3. **Fixed nginx.conf** - changed `proxy_pass` from `127.0.0.1:3000` to `backend:3000` (Docker DNS)
4. **Migrated Firebase Admin SDK to v14 modular API** - fixed TypeScript compilation errors

### Security Fixes
5. **TURN endpoint now requires authentication** - was returning credentials to unauthenticated callers
6. **Rate limiting changed from per-socket to per-user** - users can no longer bypass limits with multiple connections
7. **Health endpoint sanitized in production** - now returns only `{ status: 'ok' }` (was leaking user counts, memory usage)
8. **CORS fallback restricted** - removed localhost origins from default (production-only)
9. **Firebase service account validation** - now fails hard in production if missing, with try/catch for JSON parse

### Infrastructure Fixes
10. **Disabled source maps, declarations, declaration maps** in tsconfig.json (smaller production builds)
11. **Removed deprecated `version: '3.8'`** from docker-compose.yml
12. **docker-compose.yml now uses `env_file: .env.production`** instead of individual `${VAR}` expansions
13. **Fixed `maxHttpBufferSize` mismatch** - Flutter client was 100MB, backend was 1MB; now both 1MB
14. **Fixed nginx `ssl_prefer_server_ciphers`** - changed from `off` to `on`
15. **Removed free TURN server fallback** (`free.expressturn.com`) - now requires proper TURN config

## Project Status Summary
- **Tech Stack**: Flutter, Node.js/Express, Firebase Auth (v14 modular), Supabase (Auth + Storage + DB)
- **Core Features**: Chat (1:1), Group Chat, Profile, Settings, Contacts
- **Security**: Firebase Auth JWT, rate limiting (per-user), input validation, CORS, authenticated TURN endpoint
- **Persistence**: Supabase PostgreSQL for messages and groups
- **Deployment**: Docker ready with docker-compose.yml, nginx reverse proxy, TLS
- **Monitoring**: Firebase Crashlytics
- **TypeScript**: Clean compilation, no errors

## Priority Items (in order)
1. ~~**CRITICAL**: Fix auth inconsistency~~ ✓ DONE
2. ~~**CRITICAL**: Enforce backend JWT auth~~ ✓ DONE
3. ~~**HIGH**: Build Group Chat UI~~ ✓ DONE
4. ~~**HIGH**: Fix CORS, add rate limiting~~ ✓ DONE
5. ~~**HIGH**: Add database persistence~~ ✓ DONE
6. ~~**HIGH**: Set up Docker deployment~~ ✓ DONE
7. ~~**HIGH**: Add Firebase Crashlytics~~ ✓ DONE
8. ~~**CRITICAL**: Production security audit & fixes~~ ✓ DONE (12 issues)
9. ~~**MEDIUM**: Remove dead WebRTC code~~ ✓ DONE (5 files, ~800 lines removed)
10. ~~**MEDIUM**: Add automated tests~~ ✓ DONE (Flutter + backend tests)
11. ~~**MEDIUM**: Set up CI/CD pipeline~~ ✓ DONE (GitHub Actions)
12. ~~**MEDIUM**: Tighten Supabase RLS policies~~ ✓ DONE (world-readable → authenticated-only)
13. ~~**MEDIUM**: Add Android network security config~~ ✓ DONE (cert pinning)
14. ~~**MEDIUM**: Implement offline message queue~~ ✓ DONE (retry on reconnect)
15. ~~**MEDIUM**: Add push notifications~~ ✓ DONE (FCM integration)
16. ~~**LOW**: Write Privacy Policy & Terms of Service~~ ✓ DONE

## Remaining Items
- COMMIT session 7 work (all changes uncommitted on main)
- Populate `.env.production` with real production values before deploying
- Generate initial TLS certificate (`certbot certonly --webroot ...`)
- Rotate all exposed secrets (Firebase key, JWT secret - may be in git history)
- Add iOS push notification setup (APNs certificate)
- Run Supabase RLS migration (updated supabase_setup.sql)
- supabase_setup.sql is STALE: defines `profiles` table but backend uses `user_profiles`; messages insert omits reply/attachment columns — rewrite to match backend usage before running migration
- update-email endpoint updates only Supabase profile, not Firebase Auth email (decide desired behavior)
- Static TURN credentials still come from env; consider ephemeral credential endpoint if TURN provider supports it
- 192.168.0.0/16 cleartext allowed in network_security_config for LAN dev testing — tighten before store release if unused
- Optional deeper UX: remaining hardcoded colors exist across screens (grep `Color(0xFF` in lib/ui) — priority hotspots fixed, full sweep not done

## Deployment Checklist
Before deploying to production:
1. [ ] Rotate JWT_SECRET, SUPABASE_JWT_SECRET, SUPABASE_ANON_KEY
2. [ ] Populate `.env.production` with all required values
3. [ ] Run updated `supabase_setup.sql` in Supabase SQL Editor
4. [ ] Generate initial TLS cert: `docker-compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d api.grychat.com`
5. [ ] Build Flutter: `flutter build apk --release --dart-define=BACKEND_URL=https://api.grychat.com`
6. [ ] Deploy: `docker-compose up -d --build`
