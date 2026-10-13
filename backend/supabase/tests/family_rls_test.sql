-- 家庭共享 RLS 验证：A 创建家庭，B 用邀请码加入能看到共享数据，C（外人）看不到也写不进。
-- 用法（本地）：见 run_local_rls_test.sh
\set ON_ERROR_STOP 1
create temp table ctx (k text primary key, v text);
grant all on ctx to authenticated;
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u, false); end $$;

set role authenticated;
-- A 创建家庭
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
insert into ctx values ('fid', public.create_family('bbbbbbbb-0000-0000-0000-000000000001', '测试', '2026-09-01', '爸爸', 'dad')::text);
insert into ctx select 'code', code from public.family_invites;
select public.push_care_logs(jsonb_build_array(jsonb_build_object(
  'id','cccccccc-0000-0000-0000-000000000001','family_id',(select v from ctx where k='fid'),
  'baby_id','bbbbbbbb-0000-0000-0000-000000000001','type','feed',
  'started_at','2026-10-13T10:00:00Z','updated_at','2026-10-13T10:20:00Z','deleted',false))) as a_push;

-- C 外人：什么都看不到
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000003');
do $$ begin
  assert (select count(*) from public.shared_care_logs) = 0, 'C 不应看到记录';
  assert (select count(*) from public.family_members) = 0, 'C 不应看到成员';
  assert (select count(*) from public.family_invites) = 0, 'C 不应看到邀请码';
  assert (select count(*) from public.shared_babies) = 0, 'C 不应看到宝宝';
  begin
    insert into public.shared_care_logs (id, family_id, baby_id, type, started_at, updated_at)
      values (gen_random_uuid(), (select v::uuid from ctx where k='fid'), 'bbbbbbbb-0000-0000-0000-000000000001', 'feed', now(), now());
    raise exception 'C 直接写入竟然成功';
  exception when insufficient_privilege then null; end;
  begin
    perform public.join_family('ZZZZZZ');
    raise exception '错误邀请码竟然能加入';
  exception when sqlstate 'P0002' then null; end;
end $$;

-- B 用邀请码加入后能看到
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000002');
select public.join_family((select v from ctx where k='code'), '妈妈', 'mom') is not null as b_joined;
do $$ begin
  assert (select count(*) from public.shared_care_logs) = 1, 'B 应看到 1 条记录';
  assert (select count(*) from public.family_members) = 2, 'B 应看到 2 个成员';
  assert (select nickname from public.shared_babies) = '测试', 'B 应看到宝宝';
  -- 旧版本不覆盖、新版本覆盖（最后写入者胜出），软删除
  assert public.push_care_logs(('[{"id":"cccccccc-0000-0000-0000-000000000001","family_id":"' || (select v from ctx where k='fid') ||
    '","baby_id":"bbbbbbbb-0000-0000-0000-000000000001","type":"sleep","started_at":"2026-10-13T10:00:00Z","updated_at":"2026-10-13T09:00:00Z","deleted":false}]')::jsonb) = 0, '旧版本不应覆盖';
  assert public.push_care_logs(('[{"id":"cccccccc-0000-0000-0000-000000000001","family_id":"' || (select v from ctx where k='fid') ||
    '","baby_id":"bbbbbbbb-0000-0000-0000-000000000001","type":"feed","started_at":"2026-10-13T10:00:00Z","updated_at":"2026-10-13T11:00:00Z","deleted":true}]')::jsonb) = 1, '新版本应覆盖';
  assert (select deleted from public.shared_care_logs), '应为软删除';
  begin
    perform public.remove_member('aaaaaaaa-0000-0000-0000-000000000001');
    raise exception '成员竟然能移除别人';
  exception when sqlstate 'P0003' then null; end;
  begin
    update public.family_members set role = 'owner' where user_id = auth.uid();
    raise exception '成员竟然能改自己的角色';
  exception when insufficient_privilege then null; end;
end $$;

-- C 通过 RPC 推送也被 RLS 拦下
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000003');
do $$ begin
  perform public.push_care_logs(('[{"id":"cccccccc-0000-0000-0000-000000000009","family_id":"' || (select v from ctx where k='fid') ||
    '","baby_id":"bbbbbbbb-0000-0000-0000-000000000001","type":"feed","started_at":"2026-10-13T10:00:00Z","updated_at":"2026-10-14T11:00:00Z","deleted":false}]')::jsonb);
  raise exception 'C 通过 RPC 推送竟然成功';
exception when insufficient_privilege then null; end $$;

-- A（owner）退出 → B 成为 owner；A 看不到了；B 再退出 → 家庭解散
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000001');
select public.leave_family();
do $$ begin assert (select count(*) from public.shared_care_logs) = 0, 'A 退出后不应再看到'; end $$;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000002');
do $$ begin assert (select role from public.family_members where user_id = auth.uid()) = 'owner', 'B 应接任 owner'; end $$;
select public.leave_family();
reset role;
do $$ begin assert (select count(*) from public.families) = 0, '最后一人退出后家庭应解散'; end $$;
select 'ALL RLS CHECKS PASSED' as result;
