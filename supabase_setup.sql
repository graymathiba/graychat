-- Run this in Supabase SQL Editor (https://supabase.com/dashboard → SQL Editor)

-- 1. Profiles table (stores username + display info)
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE NOT NULL,
  display_name TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Messages table (persists chat messages)
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  room_id TEXT NOT NULL,
  sender_id UUID NOT NULL REFERENCES auth.users(id),
  receiver_id UUID NOT NULL,
  group_id UUID,
  content TEXT NOT NULL,
  message_type TEXT DEFAULT 'text',
  file_name TEXT,
  mime_type TEXT,
  attachment_size INTEGER,
  status TEXT DEFAULT 'sent',
  timestamp TIMESTAMPTZ DEFAULT now(),
  server_timestamp TIMESTAMPTZ DEFAULT now()
);

-- 3. Groups table (persists group definitions)
CREATE TABLE IF NOT EXISTS groups (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  creator_id UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Group members table (persists group membership)
CREATE TABLE IF NOT EXISTS group_members (
  group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  joined_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

-- 5. Auto-create profile row when a user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, username, display_name)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    COALESCE(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1))
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Trigger: fire on signup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 7. Row-level security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_members ENABLE ROW LEVEL SECURITY;

-- ─── Profiles ───────────────────────────────────────────────────────

-- Anyone authenticated can read profiles (needed for chat user lookup)
CREATE POLICY "Authenticated users can read profiles"
  ON profiles FOR SELECT
  USING (auth.role() = 'authenticated');

-- Users can insert their own profile (backup for trigger)
CREATE POLICY "Users can insert own profile"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);

-- ─── Messages ───────────────────────────────────────────────────────

-- Users can read messages they sent, received, or in groups they belong to
CREATE POLICY "Users can read own messages"
  ON messages FOR SELECT
  USING (
    auth.uid() = sender_id OR 
    auth.uid() = receiver_id OR
    group_id IN (SELECT group_id FROM group_members WHERE user_id = auth.uid())
  );

-- Users can insert messages they send
CREATE POLICY "Users can insert own messages"
  ON messages FOR INSERT
  WITH CHECK (auth.uid() = sender_id);

-- Users can update status of messages they sent (delivered, read)
CREATE POLICY "Users can update own message status"
  ON messages FOR UPDATE
  USING (auth.uid() = sender_id);

-- Users can delete messages they sent
CREATE POLICY "Users can delete own messages"
  ON messages FOR DELETE
  USING (auth.uid() = sender_id);

-- ─── Groups ─────────────────────────────────────────────────────────

-- Only authenticated users can see groups
CREATE POLICY "Authenticated users can read groups"
  ON groups FOR SELECT
  USING (auth.role() = 'authenticated');

-- Authenticated users can create groups
CREATE POLICY "Authenticated users can create groups"
  ON groups FOR INSERT
  WITH CHECK (auth.uid() = creator_id);

-- Only group creator can update group info
CREATE POLICY "Group creator can update group"
  ON groups FOR UPDATE
  USING (auth.uid() = creator_id);

-- Only group creator can delete group
CREATE POLICY "Group creator can delete group"
  ON groups FOR DELETE
  USING (auth.uid() = creator_id);

-- ─── Group Members ──────────────────────────────────────────────────

-- Only group members can see membership list
CREATE POLICY "Group members can view membership"
  ON group_members FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM group_members gm
      WHERE gm.group_id = group_members.group_id AND gm.user_id = auth.uid()
    )
  );

-- Group creator can add members
CREATE POLICY "Group creator can add members"
  ON group_members FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM groups 
      WHERE id = group_id AND creator_id = auth.uid()
    )
  );

-- Group creator can remove members
CREATE POLICY "Group creator can remove members"
  ON group_members FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM groups 
      WHERE id = group_id AND creator_id = auth.uid()
    )
  );

-- Users can remove themselves from a group (leave group)
CREATE POLICY "Users can leave groups"
  ON group_members FOR DELETE
  USING (auth.uid() = user_id);

-- 8. Indexes for performance
CREATE INDEX IF NOT EXISTS idx_messages_room_id ON messages(room_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver_id ON messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_group_id ON messages(group_id);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
CREATE INDEX IF NOT EXISTS idx_group_members_user_id ON group_members(user_id);
