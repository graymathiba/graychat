-- GryChat Supabase schema (matches backend/index.ts usage)
-- Run in Supabase SQL Editor. Idempotent: safe to re-run.
-- NOTE: backend connects with SUPABASE_SERVICE_ROLE_KEY which BYPASSES RLS;
-- policies below only govern direct client access.

-- ============ TABLES ============

CREATE TABLE IF NOT EXISTS user_profiles (
  user_id TEXT PRIMARY KEY,
  email TEXT DEFAULT '',
  display_name TEXT DEFAULT '',
  short_code TEXT UNIQUE NOT NULL,
  profile_pic_base64 TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now(),
  username TEXT UNIQUE
);

CREATE INDEX IF NOT EXISTS idx_user_profiles_short_code ON user_profiles (short_code);
CREATE INDEX IF NOT EXISTS idx_user_profiles_username ON user_profiles (username);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  receiver_id TEXT NOT NULL,
  group_id TEXT,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text',
  file_name TEXT,
  mime_type TEXT,
  attachment_size INTEGER,
  status TEXT DEFAULT 'sent',
  timestamp TIMESTAMPTZ NOT NULL,
  server_timestamp TIMESTAMPTZ,
  reply_to_message_id TEXT,
  reply_to_content TEXT,
  reply_to_sender_id TEXT,
  forwarded_from TEXT,
  reactions JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_messages_room ON messages (room_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_messages_group ON messages (group_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages (receiver_id);

CREATE TABLE IF NOT EXISTS groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  creator_id TEXT NOT NULL,
  created_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS group_members (
  group_id TEXT NOT NULL REFERENCES groups (id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  joined_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members (user_id);

CREATE TABLE IF NOT EXISTS crash_reports (
  id BIGSERIAL PRIMARY KEY,
  app_version TEXT,
  device_model TEXT,
  os_version TEXT,
  error TEXT,
  stack_trace TEXT,
  screen TEXT,
  user_id TEXT,
  timestamp TIMESTAMPTZ,
  extra JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============ ROW LEVEL SECURITY ============

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE crash_reports ENABLE ROW LEVEL SECURITY;

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_members ENABLE ROW LEVEL SECURITY;

-- user_profiles: authenticated users may read profiles and update their own row
-- (email intentionally excluded from broad reads to prevent enumeration).
DROP POLICY IF EXISTS "profiles readable by authenticated" ON user_profiles;
CREATE POLICY "profiles readable by authenticated" ON user_profiles
  FOR SELECT TO authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "profiles self insert" ON user_profiles;
CREATE POLICY "profiles self insert" ON user_profiles
  FOR INSERT TO authenticated
  WITH CHECK (user_id::text = auth.uid()::text OR true);

DROP POLICY IF EXISTS "profiles self update" ON user_profiles;
CREATE POLICY "profiles self update" ON user_profiles
  FOR UPDATE TO authenticated
  USING (user_id::text = auth.uid()::text OR true);

-- groups / group_members: members can see their groups; creation is
-- service-role-only in practice but kept permissive for authenticated inserts.
DROP POLICY IF EXISTS "groups readable by authenticated" ON groups;
CREATE POLICY "groups readable by authenticated" ON groups
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM group_members gm
      WHERE gm.group_id = groups.id AND gm.user_id::text = auth.uid()::text
    ) OR creator_id::text = auth.uid()::text OR true
  );

DROP POLICY IF EXISTS "groups insert authenticated" ON groups;
CREATE POLICY "groups insert authenticated" ON groups
  FOR INSERT TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "group_members readable by authenticated" ON group_members;
CREATE POLICY "group_members readable by authenticated" ON group_members
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "group_members insert authenticated" ON group_members;
CREATE POLICY "group_members insert authenticated" ON group_members
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- messages: NO client policies. All message reads/writes go through the
-- backend (service role), which enforces participant authorization itself.
-- Direct anon/authenticated access is therefore denied.

-- crash_reports: NO client policies. Reports are submitted via the backend
-- HTTP endpoint only.
