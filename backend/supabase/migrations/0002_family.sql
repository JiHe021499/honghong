-- 哄哄 第二阶段：家庭共享
-- 一个家庭对应一个宝宝；成员都是匿名登录的设备（auth.uid()），角色 owner / member。
-- 加入方式：6 位邀请码（去掉易混字符，24 小时有效，可多次使用，owner 可刷新）。
-- 同步：本地优先，App 按 updated_at 推送（最后写入者胜出），按 server_updated_at 增量拉取；删除为软删除。

create table public.families (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create table public.family_members (
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null,
  role text not null check (role in ('owner','member')),
  display_name text not null default '家人' check (char_length(display_name) <= 12),
  avatar text not null default 'dad' check (avatar in ('mom','dad','grandma','baby')),
  joined_at timestamptz not null default now(),
  primary key (family_id, user_id),
  unique (user_id)                              -- 一台设备同时只在一个家庭
);

create table public.family_invites (
  code text primary key check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  family_id uuid not null references public.families(id) on delete cascade,
  created_by uuid not null,
  expires_at timestamptz not null default now() + interval '24 hours'
);
create index on public.family_invites (family_id);

-- 共享数据：主键用本地 uuid，重复推送幂等
create table public.shared_babies (
  id uuid primary key,
  family_id uuid not null unique references public.families(id) on delete cascade,
  nickname text not null,
  birth_date date not null,
  updated_at timestamptz not null,
  updated_by uuid not null default auth.uid(),
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp()
);

create table public.shared_care_logs (
  id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  baby_id uuid not null references public.shared_babies(id) on delete cascade,
  type text not null check (type in ('feed','sleep','diaper','burp')),
  started_at timestamptz not null,
  ended_at timestamptz,
  detail text,
  updated_at timestamptz not null,
  updated_by uuid not null default auth.uid(),
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index on public.shared_care_logs (family_id, server_updated_at);

-- 哭声记录：只共享判断结果和反馈，不共享录音
create table public.shared_cry_events (
  id uuid primary key,
  family_id uuid not null references public.families(id) on delete cascade,
  baby_id uuid not null references public.shared_babies(id) on delete cascade,
  started_at timestamptz not null,
  duration_ms int not null,
  cry_confidence real not null default 0,
  context_json text not null,
  prediction_json text not null,
  predictor_version text not null,
  auto_triggered boolean not null default false,
  resolved_cause text,
  minutes_to_soothe int,
  updated_at timestamptz not null,
  updated_by uuid not null default auth.uid(),
  deleted boolean not null default false,
  server_updated_at timestamptz not null default clock_timestamp()
);
create index on public.shared_cry_events (family_id, server_updated_at);

-- 每次写入刷新 server_updated_at（拉取游标）
create or replace function public.touch_server_updated_at() returns trigger language plpgsql as $$
begin new.server_updated_at := clock_timestamp(); new.updated_by := coalesce(auth.uid(), new.updated_by); return new; end $$;
create trigger t_touch before insert or update on public.shared_babies for each row execute function public.touch_server_updated_at();
create trigger t_touch before insert or update on public.shared_care_logs for each row execute function public.touch_server_updated_at();
create trigger t_touch before insert or update on public.shared_cry_events for each row execute function public.touch_server_updated_at();

-- 成员判断（security definer，避免 RLS 递归）
create or replace function public.my_family_id() returns uuid
language sql stable security definer set search_path = public as $$
  select family_id from public.family_members where user_id = auth.uid()
$$;
create or replace function public.is_family_member(fid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.family_members where family_id = fid and user_id = auth.uid())
$$;

alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invites enable row level security;
alter table public.shared_babies enable row level security;
alter table public.shared_care_logs enable row level security;
alter table public.shared_cry_events enable row level security;

-- 家庭、成员、邀请码：成员只读；增删改走下面的 RPC
create policy fam_read on public.families for select to authenticated using (public.is_family_member(id));
create policy mem_read on public.family_members for select to authenticated using (public.is_family_member(family_id));
create policy inv_read on public.family_invites for select to authenticated using (public.is_family_member(family_id));
-- 只能改自己的称呼和头像
create policy mem_update_self on public.family_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke update on public.family_members from authenticated;
grant update (display_name, avatar) on public.family_members to authenticated;

-- 共享数据：同一家庭的成员可读写（不允许硬删除，用 deleted 软删）
create policy baby_rw on public.shared_babies for select to authenticated using (public.is_family_member(family_id));
create policy baby_ins on public.shared_babies for insert to authenticated with check (public.is_family_member(family_id));
create policy baby_upd on public.shared_babies for update to authenticated using (public.is_family_member(family_id)) with check (public.is_family_member(family_id));
create policy log_sel on public.shared_care_logs for select to authenticated using (public.is_family_member(family_id));
create policy log_ins on public.shared_care_logs for insert to authenticated with check (public.is_family_member(family_id));
create policy log_upd on public.shared_care_logs for update to authenticated using (public.is_family_member(family_id)) with check (public.is_family_member(family_id));
create policy cry_sel on public.shared_cry_events for select to authenticated using (public.is_family_member(family_id));
create policy cry_ins on public.shared_cry_events for insert to authenticated with check (public.is_family_member(family_id));
create policy cry_upd on public.shared_cry_events for update to authenticated using (public.is_family_member(family_id)) with check (public.is_family_member(family_id));

-- 邀请码生成
create or replace function public._new_invite(fid uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  c text;
begin
  delete from family_invites where family_id = fid or expires_at < now();
  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    begin
      insert into family_invites (code, family_id, created_by) values (c, fid, auth.uid());
      return c;
    exception when unique_violation then -- 重试
    end;
  end loop;
end $$;

-- 创建家庭：同时登记宝宝（id 用本地宝宝 id），返回 family_id
create or replace function public.create_family(p_baby_id uuid, p_nickname text, p_birth_date date,
    p_display_name text default '爸爸', p_avatar text default 'dad')
returns uuid language plpgsql security definer set search_path = public as $$
declare fid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if exists (select 1 from family_members where user_id = auth.uid()) then
    raise exception 'already in a family' using errcode = 'P0001';
  end if;
  insert into families default values returning id into fid;
  insert into family_members (family_id, user_id, role, display_name, avatar)
    values (fid, auth.uid(), 'owner', p_display_name, p_avatar);
  insert into shared_babies (id, family_id, nickname, birth_date, updated_at)
    values (p_baby_id, fid, p_nickname, p_birth_date, now());
  perform _new_invite(fid);
  return fid;
end $$;

-- 用邀请码加入，返回 family_id
create or replace function public.join_family(p_code text, p_display_name text default '家人', p_avatar text default 'mom')
returns uuid language plpgsql security definer set search_path = public as $$
declare fid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select family_id into fid from family_invites where code = upper(trim(p_code)) and expires_at > now();
  if fid is null then raise exception 'invalid or expired code' using errcode = 'P0002'; end if;
  if exists (select 1 from family_members where user_id = auth.uid() and family_id <> fid) then
    raise exception 'already in a family' using errcode = 'P0001';
  end if;
  insert into family_members (family_id, user_id, role, display_name, avatar)
    values (fid, auth.uid(), 'member', p_display_name, p_avatar)
    on conflict (family_id, user_id) do nothing;
  return fid;
end $$;

-- 刷新邀请码（任何成员都能邀请，方便老人也能拉人）
create or replace function public.refresh_invite() returns text
language plpgsql security definer set search_path = public as $$
declare fid uuid := my_family_id();
begin
  if fid is null then raise exception 'not in a family'; end if;
  return _new_invite(fid);
end $$;

-- 退出家庭：owner 退出时把 owner 交给最早加入的成员；没人了就解散（数据一起删除）
create or replace function public.leave_family() returns void
language plpgsql security definer set search_path = public as $$
declare fid uuid := my_family_id(); was_owner boolean; nxt uuid;
begin
  if fid is null then return; end if;
  delete from family_members where family_id = fid and user_id = auth.uid() returning role = 'owner' into was_owner;
  select user_id into nxt from family_members where family_id = fid order by joined_at limit 1;
  if nxt is null then
    delete from families where id = fid;
  elsif was_owner then
    update family_members set role = 'owner' where family_id = fid and user_id = nxt;
  end if;
end $$;

-- owner 移除成员
create or replace function public.remove_member(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare fid uuid := my_family_id();
begin
  if not exists (select 1 from family_members where family_id = fid and user_id = auth.uid() and role = 'owner') then
    raise exception 'only owner can remove members' using errcode = 'P0003';
  end if;
  if p_user_id = auth.uid() then raise exception 'use leave_family'; end if;
  delete from family_members where family_id = fid and user_id = p_user_id;
end $$;

-- 推送：最后写入者胜出（updated_at 更新的才覆盖），RLS 照常生效（security invoker）
create or replace function public.push_care_logs(rows jsonb) returns int
language plpgsql security invoker set search_path = public as $$
declare n int;
begin
  insert into shared_care_logs as t (id, family_id, baby_id, type, started_at, ended_at, detail, updated_at, deleted)
  select r.id, r.family_id, r.baby_id, r.type, r.started_at, r.ended_at, r.detail, r.updated_at, r.deleted
  from jsonb_to_recordset(rows) as r(id uuid, family_id uuid, baby_id uuid, type text, started_at timestamptz,
       ended_at timestamptz, detail text, updated_at timestamptz, deleted boolean)
  on conflict (id) do update set baby_id = excluded.baby_id, type = excluded.type, started_at = excluded.started_at,
       ended_at = excluded.ended_at, detail = excluded.detail, updated_at = excluded.updated_at, deleted = excluded.deleted
    where t.updated_at <= excluded.updated_at and t.family_id = excluded.family_id;
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.push_cry_events(rows jsonb) returns int
language plpgsql security invoker set search_path = public as $$
declare n int;
begin
  insert into shared_cry_events as t (id, family_id, baby_id, started_at, duration_ms, cry_confidence, context_json,
       prediction_json, predictor_version, auto_triggered, resolved_cause, minutes_to_soothe, updated_at, deleted)
  select r.id, r.family_id, r.baby_id, r.started_at, r.duration_ms, coalesce(r.cry_confidence, 0), r.context_json,
       r.prediction_json, r.predictor_version, coalesce(r.auto_triggered, false), r.resolved_cause, r.minutes_to_soothe,
       r.updated_at, r.deleted
  from jsonb_to_recordset(rows) as r(id uuid, family_id uuid, baby_id uuid, started_at timestamptz, duration_ms int,
       cry_confidence real, context_json text, prediction_json text, predictor_version text, auto_triggered boolean,
       resolved_cause text, minutes_to_soothe int, updated_at timestamptz, deleted boolean)
  on conflict (id) do update set started_at = excluded.started_at, duration_ms = excluded.duration_ms,
       resolved_cause = excluded.resolved_cause, minutes_to_soothe = excluded.minutes_to_soothe,
       prediction_json = excluded.prediction_json, updated_at = excluded.updated_at, deleted = excluded.deleted
    where t.updated_at <= excluded.updated_at and t.family_id = excluded.family_id;
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.push_baby(p_id uuid, p_nickname text, p_birth_date date, p_updated_at timestamptz)
returns void language sql security invoker set search_path = public as $$
  update shared_babies set nickname = p_nickname, birth_date = p_birth_date, updated_at = p_updated_at
  where id = p_id and updated_at <= p_updated_at;
$$;

-- 删除我上传的研究数据（"参与改进"）；录音文件由 App 通过 Storage API 删除
create or replace function public.delete_my_research_data() returns void
language sql security invoker set search_path = public as $$
  delete from devices where id = auth.uid();
$$;

revoke execute on function public._new_invite(uuid) from public, anon, authenticated;
revoke execute on function public.create_family(uuid, text, date, text, text) from public, anon;
revoke execute on function public.join_family(text, text, text) from public, anon;
revoke execute on function public.refresh_invite() from public, anon;
revoke execute on function public.leave_family() from public, anon;
revoke execute on function public.remove_member(uuid) from public, anon;
grant execute on function public.create_family(uuid, text, date, text, text), public.join_family(text, text, text),
  public.refresh_invite(), public.leave_family(), public.remove_member(uuid),
  public.push_care_logs(jsonb), public.push_cry_events(jsonb), public.push_baby(uuid, text, date, timestamptz),
  public.delete_my_research_data() to authenticated;
