# ml：哭声原因模型（第三阶段）

流程：导出数据 → 预处理（16kHz 单声道、裁剪哭声段）→ YAMNet embedding + 上下文特征 → 小分类器 → TFLite。

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python src/data_prep.py --input data/raw --out data/clean
python src/features.py --input data/clean --out data/features.npz
python src/train.py --features data/features.npz --out outputs/model.keras
python src/export_tflite.py --model outputs/model.keras --out outputs/cry_cause.tflite
```

评估指标：top-1 与家长反馈一致率。`data/`、`outputs/` 不入库。
