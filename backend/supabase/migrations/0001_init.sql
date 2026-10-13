-- 哄哄 第二阶段：自建 Supabase 初始化
-- 设备以匿名登录（auth.signInAnonymously）获得 auth.uid()，不收集个人信息

create table public.devices (
  id uuid primary key default auth.uid(),
  created_at timestamptz not null default now(),
  app_version text,
  consent_at timestamptz not null            -- 用户开启"参与改进"的时间
);

create table public.babies (
  id uuid primary key,                         -- 与本地 id 相同
  device_id uuid not null references public.devices(id) on delete cascade,
  age_months_at_upload numeric(4,1),          -- 只存月龄，不存生日
  created_at timestamptz not null default now()
);

create table public.cry_events (
  id uuid primary key,
  device_id uuid not null references public.devices(id) on delete cascade,
  baby_id uuid not null references public.babies(id) on delete cascade,
  started_at timestamptz not null,
  duration_ms int not null,
  clip_path text,                              -- storage: cry-clips/{device_id}/{id}.wav
  cry_confidence real,
  context jsonb not null,
  prediction jsonb not null,
  predictor_version text not null,
  created_at timestamptz not null default now()
);
create index on public.cry_events (baby_id, started_at);

create table public.feedbacks (
  id uuid primary key,
  cry_event_id uuid not null references public.cry_events(id) on delete cascade,
  device_id uuid not null references public.devices(id) on delete cascade,
  resolved_cause text not null check (resolved_cause in ('hungry','sleepy','gas','diaper','holdMe','unknown')),
  minutes_to_soothe int,
  created_at timestamptz not null default now()
);

create table public.model_versions (
  version text primary key,
  kind text not null check (kind in ('detector','classifier')),
  storage_path text not null,                  -- storage: models/{version}.tflite
  sha256 text not null,
  min_app_version text,
  rollout_percent int not null default 0 check (rollout_percent between 0 and 100),
  released_at timestamptz not null default now()
);

-- RLS：设备只能读写自己的数据；模型表所有登录设备可读，只有 service_role 可写
alter table public.devices enable row level security;
alter table public.babies enable row level security;
alter table public.cry_events enable row level security;
alter table public.feedbacks enable row level security;
alter table public.model_versions enable row level security;

create policy own_device on public.devices for all using (id = auth.uid()) with check (id = auth.uid());
create policy own_babies on public.babies for all using (device_id = auth.uid()) with check (device_id = auth.uid());
create policy own_events on public.cry_events for all using (device_id = auth.uid()) with check (device_id = auth.uid());
create policy own_feedbacks on public.feedbacks for all using (device_id = auth.uid()) with check (device_id = auth.uid());
create policy read_models on public.model_versions for select to authenticated using (true);

-- Storage
insert into storage.buckets (id, name, public) values ('cry-clips','cry-clips',false), ('models','models',false)
  on conflict do nothing;
create policy clips_own on storage.objects for all to authenticated
  using (bucket_id = 'cry-clips' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'cry-clips' and (storage.foldername(name))[1] = auth.uid()::text);
create policy models_read on storage.objects for select to authenticated using (bucket_id = 'models');

-- 灰度：按设备 id 哈希落桶
create or replace function public.eligible_model(p_kind text)
returns setof public.model_versions language sql stable as $$
  select * from public.model_versions
  where kind = p_kind
    and (abs(hashtext(auth.uid()::text)) % 100) < rollout_percent
  order by released_at desc limit 1;
$$;
