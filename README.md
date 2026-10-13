# 哄哄（暂定名）

帮新手爸妈判断宝宝为什么哭的 App。所有判断仅供参考，不能替代医生。

## 文档
- [整体架构](docs/architecture.md)
- [三阶段技术方案](docs/tech-plan.md)
- [设计稿](docs/design/design.html)

## 目录结构
```
docs/      产品与技术文档，docs/design/ 为设计稿
app/       Flutter 客户端（Riverpod + drift + tflite_flutter）
  lib/core       主题等公共代码
  lib/domain     领域模型与 CryPredictor（规则版已实现）
  lib/data       drift 数据库
  lib/services   录音与哭声检测
  lib/features   按页面划分：home / cry / feedback / logs / insights / settings
ml/        哭声原因模型训练（Python，第三阶段）
backend/   自建 Supabase 配置与迁移（第二阶段）
```

## 开发

环境：Flutter 3.47.7 stable（Dart 3.13.5）。本机（box）已安装在 `/opt/flutter`。

```bash
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 drift 代码（*.g.dart 不入库）
flutter analyze
flutter test
flutter run                                                # 需连接 iOS/Android 设备或模拟器
```

代码结构：
- `lib/core/`：路由（go_router）、主题（日/夜）、Riverpod providers
- `lib/data/`：drift 数据库与仓库（Baby / CareLog / CryEvent / Feedback）
- `lib/domain/`：CryPredictor 接口、规则版实现、上下文生成
- `lib/features/`：首页、录音、结果、反馈、记录、规律、设置
- `test/`：规则预测和内存数据库测试

ML（第三阶段）：
```bash
cd ml && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
```
