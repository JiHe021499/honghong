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
```bash
cd app
flutter create . --platforms=android,ios   # 首次生成平台工程
flutter pub get
dart run build_runner build                # 生成 drift 代码
flutter run
```
