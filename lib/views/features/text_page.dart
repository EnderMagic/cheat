import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/services/text_service.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // ✅ 新增
import '../../services/openrouter_service.dart';
import 'package:demo_ai_even/views/otg_camera_page.dart';

class TextPage extends StatefulWidget {
  const TextPage({super.key});

  @override
  _TextPageState createState() => _TextPageState();
}

class _TextPageState extends State<TextPage> {
  late TextEditingController tfController;
  final ImagePicker _picker = ImagePicker(); // ✅ 新增

  String testContent = '''Welcome to G1.''';

  @override
  void initState() {
    tfController = TextEditingController(text: testContent);
    super.initState();
  }

  bool get _canSendText =>
      BleManager.get().isConnected && tfController.text.trim().isNotEmpty;

  bool get _canUseCamera =>
      BleManager.get().isConnected; // 拍照不需要输入框有内容

  Future<void> _sendTextToGlasses() async {
    final prompt = tfController.text.trim();
    if (prompt.isEmpty) return;

    TextService.get.clear();
    TextService.get.startSendText("思考中…");

    try {
      final answer = await OpenRouterService().ask(
        "请用中文回答，尽量短，适合眼镜显示（最多5行）。不要自我介绍：\n$prompt",
      );
      TextService.get.clear();
      TextService.get.startSendText(answer);
    } catch (e) {
      TextService.get.clear();
      TextService.get.startSendText("请求失败");
    }
  }

  Future<void> _takePhotoAndSendToGlasses() async {
    // 1) 拍照（压缩一下，不然 base64 太大又慢又贵）
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1024,
    );
    if (photo == null) return;

    TextService.get.clear();
    TextService.get.startSendText("识别中…");

    try {
      final bytes = await photo.readAsBytes();

      final answer = await OpenRouterService().askWithImageBytes(
        prompt: '不要自我介绍，不要复述题干，不要解释推理过程，只输出最终答案。 - 如果图片信息不足无法确定：只输出"缺信息：……"并列出最少需要的1-3项关键信息。 选择题：只输出选项字母（如：C）。 - 填空/计算：只输出最终结果（含单位/保留位数按题目要求）。 - 多问：按(1)(2)(3)逐行输出答案。 - 如果题目要求"写步骤/过程"，也仍然只给最终答案。 若为作文/写作题： - 直接输出一篇英语作文/短文，总字数≤500字（含标点）。 - 不要标题（除非题目明确要求）。 - 结构清晰：开头点题，中间展开（2-3段），结尾收束。 - 紧扣题意与材料，不要复述题干。 - 如可能超长，优先保证结尾完整，必要时压缩中间段落。',
        imageBytes: bytes,
        // mimeType: 'image/jpeg', // 默认就是 jpeg
      );

      TextService.get.clear();
      TextService.get.startSendText(answer);
    } catch (e) {
      TextService.get.clear();
      TextService.get.startSendText("识别失败");
    }
  }

  // ✅ 打开OTG相机页面
  void _openOtgCamera() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OtgCameraPage()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Text Transfer'),
    ),
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
            ),
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: const InputDecoration.collapsed(hintText: ""),
              controller: tfController,
              onChanged: (_) => setState(() {}),
              maxLines: null,
            ),
          ),

          // ✅ 原来的发送文字按钮
          GestureDetector(
            onTap: _canSendText ? _sendTextToGlasses : null,
            child: Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: Text(
                "Send Text to Glasses",
                style: TextStyle(
                  color: _canSendText ? Colors.black : Colors.grey,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          // ✅ 新增：拍照并发送到眼镜（系统相机）
          GestureDetector(
            onTap: _canUseCamera ? _takePhotoAndSendToGlasses : null,
            child: Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: Text(
                "Take Photo & Send to Glasses",
                style: TextStyle(
                  color: _canUseCamera ? Colors.black : Colors.grey,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          // ✅ 新增：OTG相机拍照按钮
          GestureDetector(
            onTap: _canUseCamera ? _openOtgCamera : null,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: Text(
                "OTG相机拍照",
                style: TextStyle(
                  color: _canUseCamera ? Colors.black : Colors.grey,
                  fontSize: 16,
                ),
              ),
            ),
          ),

        ],
      ),
    ),
  );
}
