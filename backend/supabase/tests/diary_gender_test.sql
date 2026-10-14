-- 0004_diary：shared_babies.gender 与 push_baby(p_gender) 验证（本地临时库，见 run_local_rls_test.sh）
\set ON_ERROR_STOP 1
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u, false); end $$;
set role authenticated;
select pg_temp.as_user('aaaaaaaa-0000-0000-0000-000000000011');
select public.create_family('bbbbbbbb-0000-0000-0000-000000000011', '小糖', '2026-07-01', '妈妈', 'mom') is not null as created;
do $$ begin
  assert (select gender from public.shared_babies) is null, '老数据/新建宝宝 gender 应为 null';
end $$;
-- 新客户端带性别
select public.push_baby('bbbbbbbb-0000-0000-0000-000000000011', '小糖', '2026-07-01', '2026-10-14T10:00:00Z', 'girl');
do $$ begin assert (select gender from public.shared_babies) = 'girl', '应写入 girl'; end $$;
-- 老客户端按 4 个命名参数调用：仍可用，且不清空性别
select public.push_baby(p_id => 'bbbbbbbb-0000-0000-0000-000000000011', p_nickname => '糖糖',
                        p_birth_date => '2026-07-01', p_updated_at => '2026-10-14T11:00:00Z');
do $$ begin
  assert (select nickname from public.shared_babies) = '糖糖', '老客户端应能改昵称';
  assert (select gender from public.shared_babies) = 'girl', '老客户端不应清空性别';
end $$;
-- 非法值被拒
do $$ begin
  perform public.push_baby('bbbbbbbb-0000-0000-0000-000000000011', '糖糖', '2026-07-01', '2026-10-14T12:00:00Z', 'x');
  raise exception '非法性别竟然写入';
exception when check_violation then null; end $$;
-- 旧时间戳不覆盖
select public.push_baby('bbbbbbbb-0000-0000-0000-000000000011', '旧', '2026-07-01', '2026-10-14T09:00:00Z', 'boy');
do $$ begin assert (select gender from public.shared_babies) = 'girl', '旧数据不应覆盖'; end $$;
-- 已设性别可改成另一个性别（产品决定：不能清回未填，但必须能改）
select public.push_baby('bbbbbbbb-0000-0000-0000-000000000011', '糖糖', '2026-07-01', '2026-10-14T13:00:00Z', 'boy');
do $$ begin assert (select gender from public.shared_babies) = 'boy', '应能从 girl 改成 boy'; end $$;
select public.push_baby('bbbbbbbb-0000-0000-0000-000000000011', '糖糖', '2026-07-01', '2026-10-14T14:00:00Z', 'girl');
do $$ begin assert (select gender from public.shared_babies) = 'girl', '应能再改回 girl'; end $$;
select public.leave_family();
reset role;
select 'ALL DIARY SQL CHECKS PASSED' as result;
