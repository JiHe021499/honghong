/// 基于 YAMNet（tflite_flutter）的端上哭声检测。
/// 输入 16kHz 单声道 0.975s 帧，取 "Baby cry, infant cry" 类别（索引 20）得分。
/// 连续 N 帧超过阈值即触发自动录音。
class CryDetector {
  static const int sampleRate = 16000;
  static const int frameSamples = 15600;
  static const int babyCryClassIndex = 20;
  static const double threshold = 0.5;

  // TODO: 加载 assets/models/yamnet.tflite，实现 score(Float32List frame)
}
