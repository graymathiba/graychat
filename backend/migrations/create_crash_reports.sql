-- Run this in Supabase SQL Editor: https://supabase.com/dashboard/project/rztznpwhsfqrzavzluik/sql

create table if not exists crash_reports (
  id uuid default gen_random_uuid() primary key,
  app_version text,
  device_model text,
  os_version text,
  error text,
  stack_trace text,
  screen text,
  user_id text,
  timestamp timestamptz,
  extra jsonb,
  created_at timestamptz default now()
);

alter table crash_reports enable row level security;

create policy "allow_anon_insert_crash_reports"
  on crash_reports for insert
  with check (true);

create policy "allow_service_role_all_crash_reports"
  on crash_reports for all
  using (auth.role() = 'service_role');
