create table if not exists public.login_pins (
  pin text primary key,
  is_active boolean not null default true,
  target_role text not null default 'user',
  expires_at timestamptz null,
  note text null,
  created_at timestamptz not null default now()
);

alter table public.login_pins
  add column if not exists target_role text;

update public.login_pins
set target_role = 'user'
where target_role is null;

alter table public.login_pins
  alter column target_role set default 'user';

alter table public.login_pins
  alter column target_role set not null;

alter table public.login_pins
  drop constraint if exists login_pins_target_role_check;

alter table public.login_pins
  add constraint login_pins_target_role_check
  check (target_role in ('user', 'admin'));

alter table public.login_pins enable row level security;

create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.app_admins enable row level security;

create table if not exists public.app_locked_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text null,
  created_at timestamptz not null default now()
);

alter table public.app_locked_users enable row level security;

drop policy if exists "app_admins_no_direct_select" on public.app_admins;
create policy "app_admins_no_direct_select"
on public.app_admins
for select
to anon, authenticated
using (false);

drop policy if exists "app_admins_no_direct_insert" on public.app_admins;
create policy "app_admins_no_direct_insert"
on public.app_admins
for insert
to anon, authenticated
with check (false);

drop policy if exists "app_admins_no_direct_update" on public.app_admins;
create policy "app_admins_no_direct_update"
on public.app_admins
for update
to anon, authenticated
using (false)
with check (false);

drop policy if exists "app_admins_no_direct_delete" on public.app_admins;
create policy "app_admins_no_direct_delete"
on public.app_admins
for delete
to anon, authenticated
using (false);

drop policy if exists "app_locked_users_no_direct_select" on public.app_locked_users;
create policy "app_locked_users_no_direct_select"
on public.app_locked_users
for select
to anon, authenticated
using (false);

drop policy if exists "app_locked_users_no_direct_insert" on public.app_locked_users;
create policy "app_locked_users_no_direct_insert"
on public.app_locked_users
for insert
to anon, authenticated
with check (false);

drop policy if exists "app_locked_users_no_direct_update" on public.app_locked_users;
create policy "app_locked_users_no_direct_update"
on public.app_locked_users
for update
to anon, authenticated
using (false)
with check (false);

drop policy if exists "app_locked_users_no_direct_delete" on public.app_locked_users;
create policy "app_locked_users_no_direct_delete"
on public.app_locked_users
for delete
to anon, authenticated
using (false);

drop policy if exists "login_pins_no_direct_select" on public.login_pins;
create policy "login_pins_no_direct_select"
on public.login_pins
for select
to anon, authenticated
using (false);

drop policy if exists "login_pins_no_direct_insert" on public.login_pins;
create policy "login_pins_no_direct_insert"
on public.login_pins
for insert
to anon, authenticated
with check (false);

drop policy if exists "login_pins_no_direct_update" on public.login_pins;
create policy "login_pins_no_direct_update"
on public.login_pins
for update
to anon, authenticated
using (false)
with check (false);

drop policy if exists "login_pins_no_direct_delete" on public.login_pins;
create policy "login_pins_no_direct_delete"
on public.login_pins
for delete
to anon, authenticated
using (false);

create or replace function public.check_login_pin(p_pin text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_pin text := nullif(trim(p_pin), '');
begin
  if normalized_pin is null then
    return false;
  end if;

  return exists (
    select 1
    from public.login_pins lp
    where lp.pin = normalized_pin
      and lp.is_active = true
      and (lp.expires_at is null or lp.expires_at > now())
  );
end;
$$;

revoke all on function public.check_login_pin(text) from public;
grant execute on function public.check_login_pin(text) to anon, authenticated;

create or replace function public.get_login_pin_role(p_pin text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_pin text := nullif(trim(p_pin), '');
  role_value text;
begin
  if normalized_pin is null then
    return 'user';
  end if;

  select lp.target_role
    into role_value
  from public.login_pins lp
  where lp.pin = normalized_pin
    and lp.is_active = true
    and (lp.expires_at is null or lp.expires_at > now())
  limit 1;

  return coalesce(role_value, 'user');
end;
$$;

revoke all on function public.get_login_pin_role(text) from public;
grant execute on function public.get_login_pin_role(text) to anon, authenticated;

create or replace function public.is_current_user_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_admins a
    where a.user_id = auth.uid()
  );
$$;

revoke all on function public.is_current_user_admin() from public;
grant execute on function public.is_current_user_admin() to authenticated;

create or replace function public.is_current_user_locked()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.app_locked_users l
    where l.user_id = auth.uid()
  );
$$;

revoke all on function public.is_current_user_locked() from public;
grant execute on function public.is_current_user_locked() to authenticated;

drop function if exists public.create_login_pin(text, integer);

create or replace function public.create_login_pin(
  p_note text default null,
  p_expires_minutes integer default 1440,
  p_role text default 'user'
)
returns table(pin text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  candidate text;
  try_count integer := 0;
  normalized_role text := case when lower(coalesce(trim(p_role), 'user')) = 'admin' then 'admin' else 'user' end;
  expires_value timestamptz := case
    when p_expires_minutes is null or p_expires_minutes <= 0 then null
    else now() + make_interval(mins => p_expires_minutes)
  end;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;

  if not public.is_current_user_admin() then
    raise exception 'Forbidden';
  end if;

  loop
    try_count := try_count + 1;
    if try_count > 100 then
      raise exception 'Could not generate unique PIN';
    end if;

    candidate := lpad((floor(random() * 10000))::int::text, 4, '0');

    insert into public.login_pins (pin, is_active, target_role, expires_at, note)
    values (candidate, true, normalized_role, expires_value, p_note)
    on conflict on constraint login_pins_pkey do nothing;

    if found then
      return query select candidate, expires_value;
      return;
    end if;
  end loop;
end;
$$;

revoke all on function public.create_login_pin(text, integer, text) from public;
grant execute on function public.create_login_pin(text, integer, text) to authenticated;

create or replace function public.consume_login_pin(
  p_pin text,
  p_user_id uuid default auth.uid()
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_pin text := nullif(trim(p_pin), '');
  target_role_value text;
begin
  if normalized_pin is null then
    raise exception 'PIN required';
  end if;
  if p_user_id is null then
    raise exception 'User required';
  end if;

  update public.login_pins lp
  set is_active = false
  where lp.pin = normalized_pin
    and lp.is_active = true
    and (lp.expires_at is null or lp.expires_at > now())
  returning lp.target_role into target_role_value;

  if target_role_value is null then
    raise exception 'Invalid or expired PIN';
  end if;

  if target_role_value = 'admin' then
    insert into public.app_admins (user_id)
    values (p_user_id)
    on conflict (user_id) do nothing;
  end if;

  return target_role_value;
end;
$$;

revoke all on function public.consume_login_pin(text, uuid) from public;
grant execute on function public.consume_login_pin(text, uuid) to anon, authenticated;

create or replace function public.admin_list_users()
returns table(user_id uuid, email text, display_name text, avatar_url text, is_admin boolean, is_locked boolean, is_verified boolean)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if not public.is_current_user_admin() then
    raise exception 'Forbidden';
  end if;

  return query
  select
    u.id as user_id,
    u.email::text as email,
    coalesce(up.display_name, u.raw_user_meta_data ->> 'display_name', split_part(coalesce(u.email::text, ''), '@', 1), 'User')::text as display_name,
    coalesce(up.avatar_url, u.raw_user_meta_data ->> 'avatar_url', '')::text as avatar_url,
    exists (select 1 from public.app_admins a where a.user_id = u.id) as is_admin,
    exists (select 1 from public.app_locked_users l where l.user_id = u.id) as is_locked,
    (u.email_confirmed_at is not null) as is_verified
  from auth.users u
  left join public.users_public up on up.id = u.id
  order by lower(coalesce(up.display_name, u.raw_user_meta_data ->> 'display_name', u.email::text, ''));
end;
$$;

revoke all on function public.admin_list_users() from public;
grant execute on function public.admin_list_users() to authenticated;

create or replace function public.admin_rename_user(p_user_id uuid, p_display_name text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  next_name text := nullif(trim(p_display_name), '');
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if not public.is_current_user_admin() then
    raise exception 'Forbidden';
  end if;
  if p_user_id is null then
    raise exception 'User required';
  end if;
  if next_name is null then
    raise exception 'Display name required';
  end if;

  update public.users_public
  set display_name = next_name
  where id = p_user_id;

  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('display_name', next_name)
  where id = p_user_id;
end;
$$;

revoke all on function public.admin_rename_user(uuid, text) from public;
grant execute on function public.admin_rename_user(uuid, text) to authenticated;

create or replace function public.admin_set_user_role(p_user_id uuid, p_role text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_role text := case when lower(coalesce(trim(p_role), 'user')) = 'admin' then 'admin' else 'user' end;
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if not public.is_current_user_admin() then
    raise exception 'Forbidden';
  end if;
  if p_user_id is null then
    raise exception 'User required';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Cannot change own role here';
  end if;

  if normalized_role = 'admin' then
    insert into public.app_admins (user_id) values (p_user_id)
    on conflict (user_id) do nothing;
  else
    delete from public.app_admins where user_id = p_user_id;
  end if;

  update auth.users
  set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('app_role', normalized_role)
  where id = p_user_id;

  return normalized_role;
end;
$$;

revoke all on function public.admin_set_user_role(uuid, text) from public;
grant execute on function public.admin_set_user_role(uuid, text) to authenticated;

create or replace function public.admin_set_user_lock(p_user_id uuid, p_locked boolean)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  next_locked boolean := coalesce(p_locked, false);
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if not public.is_current_user_admin() then
    raise exception 'Forbidden';
  end if;
  if p_user_id is null then
    raise exception 'User required';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Cannot lock own account here';
  end if;

  if next_locked then
    insert into public.app_locked_users (user_id)
    values (p_user_id)
    on conflict (user_id) do nothing;
  else
    delete from public.app_locked_users where user_id = p_user_id;
  end if;

  return next_locked;
end;
$$;

revoke all on function public.admin_set_user_lock(uuid, boolean) from public;
grant execute on function public.admin_set_user_lock(uuid, boolean) to authenticated;

create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Unauthorized';
  end if;
  if not public.is_current_user_admin() then
    raise exception 'Forbidden';
  end if;
  if p_user_id is null then
    raise exception 'User required';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Cannot delete own account here';
  end if;

  delete from public.app_admins where user_id = p_user_id;
  delete from public.app_locked_users where user_id = p_user_id;
  delete from auth.users where id = p_user_id;
end;
$$;

revoke all on function public.admin_delete_user(uuid) from public;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- Beispiele:
-- Ersten Admin manuell setzen:
-- insert into public.app_admins (user_id) values ('<DEINE_USER_UUID>');
-- Beispiel-PINs:
-- insert into public.login_pins (pin, target_role, note) values ('1234', 'user', 'Test-PIN');
-- insert into public.login_pins (pin, target_role, expires_at) values ('9876', 'admin', now() + interval '7 days');
