-- 哄哄 第三阶段：模型下发
-- model_versions 增加元数据（类别、特征规格、融合参数、自检样本、评估结果），App 用它校验和解释模型。
-- 文件放在私有 bucket models/classifier/{version}.tflite（+ {version}.json 备份同一份元数据）。
-- 只有 service_role（训练端）能写；登录设备（含匿名）只读。灰度仍按 eligible_model 的哈希分桶。

alter table public.model_versions
  add column if not exists meta jsonb,
  add column if not exists size_bytes int,
  add column if not exists notes text;

alter table public.model_versions drop constraint if exists model_versions_meta_sha;
alter table public.model_versions add constraint model_versions_meta_sha
  check (meta is null or (meta->>'sha256' = sha256 and meta->>'version' = version));

create or replace function public.eligible_model(p_kind text)
returns setof public.model_versions language sql stable as $$
  select * from public.model_versions
  where kind = p_kind
    and (abs(hashtext(coalesce(auth.uid()::text, ''))) % 100) < rollout_percent
  order by released_at desc limit 1;
$$;
grant execute on function public.eligible_model(text) to authenticated;
