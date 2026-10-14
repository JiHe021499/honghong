# 哄哄 · 第三阶段模型管线（ml/）

YAMNet embedding（+ 上下文特征）→ 小分类头 → TFLite → Supabase `models` bucket 下发 → App 端 `ModelPredictor` 和上下文规则融合 + 端上个性化。

## 目录

| 文件 | 作用 |
|---|---|
| `src/export_yamnet.py` | TF Hub YAMNet → `yamnet_embed.tflite`（一帧 15600 采样 → 521 类得分 + 1024 维 embedding，动态范围量化，3.9MB）。App 内置的就是这个文件，训练也用它提特征，保证一致 |
| `src/features.py` | 特征规格：16kHz → 63 阶 FIR 低通 3.8kHz → 帧长 15600 / 步长 7800 → embedding → 只对哭声得分 ≥0.2 的帧取均值；上下文 8 维（距上次喂奶/醒来/换尿布/拍嗝小时数、是否在睡、时刻 sin/cos、月龄）。Dart 端 `lib/services/audio/cry_embedder.dart`、`lib/domain/predictor/model_predictor.dart` 逐项对应，有单测对齐数值 |
| `src/data_prep.py` | 公开数据 + App 导出数据 → `data/features.npz` |
| `src/supabase_export.py` | 用 service_role key（只从本机 env 文件读）导出 App 上传的片段 + 家长反馈 + 上下文 → `data/app/manifest.csv` |
| `src/train.py` | 分组交叉验证评估 + 训练 + 导出 `build/cry_head_{version}.tflite` 和元数据 json |
| `src/publish_model.py` | 上传到 `models/classifier/{version}.tflite/.json`，upsert `model_versions`（含 meta、rollout_percent） |
| `reports/` | 每个发布版本的元数据和评估结果 |

```bash
uv venv -p 3.12 .venv && . .venv/bin/activate && uv pip install -r requirements.txt
git clone --depth 1 https://github.com/gveres/donateacry-corpus.git /workspace/donateacry-corpus
cd ml
python src/export_yamnet.py --quant dynamic --out ../app/assets/models/yamnet_embed.tflite   # 只在换 YAMNet 时
# 有 App 数据时：python src/supabase_export.py --env <secrets>/supabase-nc_am.env
python src/data_prep.py
cd src && python train.py --features ../data/features.npz --out ../build --version cls-2 [--context]
python publish_model.py --env <secrets>/supabase-nc_am.env --build ../build --version cls-2 --rollout 10
```

密钥只放在 `/cursor/stores/.../secrets/`，`data/`、`build/`、`*.tflite`（除 App 内置的两个）都不入库。

## 数据集与许可

**donateacry-corpus**（https://github.com/gveres/donateacry-corpus），使用其中 KTH 学生整理的 `donateacry_corpus_cleaned_and_updated_data` 子集（人工去掉非哭声，统一转成 8kHz WAV）。

- 许可：数据库 **Open Database License (ODbL 1.0)**，单条内容 **Database Contents License (DbCL 1.0)**。可商用；对外公开衍生数据库时需同样以 ODbL 共享并署名。训练出的模型属于 "Produced Work"，按 ODbL 第 4.3 条需附带来源说明：本文件和模型元数据 `training.license` 字段即该说明。作者要求使用者告知 hello@newparentsapps.com（尚未发送，需要的话由用户决定）。
- 标签映射到 App 原因：hungry→饿(382)，tired→困(24)，burping + belly_pain→胀气(8+16)，discomfort(含 cold/hot)→不舒服/尿布(27)。**"要抱"没有对应数据**（原始语料 lonely 只有 23 条且未清洗），模型不输出这一类，App 里这一类完全由规则给出。
- 偏差和局限（请直接看待）：
  - 标签是 2015 年家长在 App 里**自己猜**的原因，不是经过验证的真值；
  - 极度不平衡：84% 是"饿"；
  - 8kHz 电话音质（Android 为 AMR-NB），App 录音是 16kHz —— 所以两端都做 3.8kHz 低通；
  - 221 个 App 安装（≈ 宝宝/家庭），每个只有 1–几条，以欧美用户为主；月龄多在 0–6 个月。

## v1 结果（cls-1，真实数字）

评估：`StratifiedGroupKFold(5)` 按安装 id 分组（同一宝宝不会同时出现在训练和验证），重复 10 次换随机种子；C 在同一套 CV 上挑选（略乐观）。

| 指标（均值 ± 标准差） | cls-1（LR, C=0.3） | 全猜"饿" | 按先验随机猜 |
|---|---|---|---|
| 宏平均 F1 | **0.231 ± 0.010** | 0.228 | 0.249 |
| 平衡准确率 | **0.229 ± 0.011** | 0.250 | 0.250 |
| 准确率 | 0.652 ± 0.008 | 0.836 | — |

每类（10 次重复平均）：

| 类别 | n | precision | recall | F1 |
|---|---|---|---|---|
| 饿 | 382 | 0.827 | 0.770 | 0.797 |
| 困 | 24 | 0.015 | 0.025 | 0.019 |
| 胀气 | 24 | 0.018 | 0.021 | 0.019 |
| 不舒服/尿布 | 27 | 0.079 | 0.100 | 0.088 |

混淆矩阵（行=真实，列=预测，10 次重复累加）：

| | 饿 | 困 | 胀气 | 不舒服 |
|---|---|---|---|---|
| 饿 | 2940 | 348 | 246 | 286 |
| 困 | 212 | 6 | 11 | 11 |
| 胀气 | 188 | 21 | 5 | 26 |
| 不舒服 | 216 | 15 | 12 | 27 |

另外试过 PCA+LR、RBF-SVM、随机森林，分组 CV 平衡准确率 0.19–0.25，都不超过随机。若**不按宝宝分组**随机切分，平衡准确率会升到 0.28–0.30 —— 这是同一宝宝的声音泄漏，不是真本事；很多公开报告的高准确率就是这么来的。

**结论：在这份公开数据上，音频本身学不到可用的"原因"信号。** 所以 cls-1 的 `blend.weight = 0`（影子运行）：App 会跑模型、把模型输出记进每次预测（`prediction.components.model`），但给家长看的排序仍然是上下文规则；等有了本 App 的真实反馈，端上个性化和下一版训练会用这些记录判断模型到底有没有用。

## App 端怎么用

- `CryEmbedder`（内置 `yamnet_embed.tflite`）：录音结束后算 embedding 和哭声得分。
- `ModelPredictor`：`p ∝ p_rule^(1-w) · p_model^w`（只在模型覆盖的 4 类上；"要抱"保留规则的概率）；无音频、哭声得分 < 0.1、模型最高概率 < 0.4 或推理出错时只用规则。`w` = 元数据里的 `blend.weight`，或端上个性化的权重。
- 端上个性化（`Personalization`，只用本机数据）：至少 8 条带反馈且模型参与过的哭声后，比较模型第一名和规则第一名各猜中几次，模型更准才加权（最多 0.6），更差就设为 0；并按"模型常猜成 A 实际是 B"调整各类偏置（0.5–2 倍）。规则自身的先验仍按反馈频率调整。
- `ModelManager`：内置 cls-1 作为基线；启动/回前台（最多 6 小时一次）调 `eligible_model('classifier')`，有新版本就下载 → 校验 sha256（服务器行、元数据、文件三者一致）→ 加载并跑元数据里的自检样本 → 设为当前（热切换，不用重启）；失败的版本拉黑不再下载；推理出错或文件损坏时回滚到上一版本 → 内置 → 纯规则。保留当前 + 上一个版本。

## 下一步需要的数据

真正能让模型有用的是**本 App 的家长反馈 + 当时的上下文 + 片段**（"参与改进"上传）：
- 每类至少 ~100 条、来自 ≥30 个宝宝才值得训练带上下文的版本（`train.py --context`），评估同样按宝宝分组；
- 特别缺"困""胀气""要抱"；
- 训练集以 App 数据为主、donateacry 只做辅助；发布先 `--rollout 10`，用 top-1 一致率和规则版对比，再放量。
