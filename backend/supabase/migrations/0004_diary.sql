-- 哄哄 妈咪日记（P1）：shared_babies 增加性别。
-- 日记输入/卡片/小结本期只存本地、不同步，云端不建表（架构 §3.3）。
-- shared_care_logs 本期不加 source（去重靠 SSOT，不依赖该列）。
-- 注意：新版 App 调 push_baby 会带 p_gender，发版前必须先在服务器执行本迁移。

alter table public.shared_babies
  add column if not exists gender text null check (gender in ('boy', 'girl'));

-- 旧版 4 参数签名替换为带 p_gender 的版本（默认 null）。
-- 老版本客户端不传 p_gender → 保留已有性别，不会被清空。
drop function if exists public.push_baby(uuid, text, date, timestamptz);
create or replace function public.push_baby(p_id uuid, p_nickname text, p_birth_date date, p_updated_at timestamptz,
                                            p_gender text default null)
returns void language sql security invoker set search_path = public as $$
  update shared_babies set nickname = p_nickname, birth_date = p_birth_date, updated_at = p_updated_at,
         gender = coalesce(p_gender, gender)
  where id = p_id and updated_at <= p_updated_at;
$$;
revoke execute on function public.push_baby(uuid, text, date, timestamptz, text) from public, anon;
grant execute on function public.push_baby(uuid, text, date, timestamptz, text) to authenticated;
