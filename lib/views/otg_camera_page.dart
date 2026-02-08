import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/openrouter_service.dart';
import '../services/text_service.dart';

class OtgCameraPage extends StatefulWidget {
  const OtgCameraPage({super.key});

  @override
  State<OtgCameraPage> createState() => _OtgCameraPageState();
}

class _OtgCameraPageState extends State<OtgCameraPage> {
  static const MethodChannel _channel = MethodChannel('com.example.demo_ai_even/uvc_camera');
  bool _isInitialized = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // 请求相机权限
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要相机权限')),
          );
        }
        return;
      }

      // 初始化UVC相机
      print('调用原生方法: initialize');
      final result = await _channel.invokeMethod('initialize');
      print('原生方法返回: $result');
      if (result is Map) {
        final hasCamera = result['hasCamera'] as bool? ?? true; // 默认允许使用
        final isUsbCamera = result['isUsbCamera'] as bool? ?? false;
        
        if (mounted) {
          setState(() {
            _isInitialized = hasCamera;
          });
          
          // 显示提示信息
          if (!isUsbCamera) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('未检测到USB相机设备，将使用系统相机'),
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已检测到USB相机设备'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('初始化相机异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('初始化相机失败: $e')),
        );
        // 即使初始化失败，也允许尝试拍照（使用系统相机）
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }

  Future<void> _takePhoto() async {
    if (!_isInitialized || _isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      // 拍照
      final result = await _channel.invokeMethod('capture');
      
      if (result is Map && result['imageBytes'] != null) {
        // 从原生返回的可能是List<int>，需要转换为Uint8List
        final imageData = result['imageBytes'];
        Uint8List imageBytes;
        
        if (imageData is List) {
          imageBytes = Uint8List.fromList(imageData.cast<int>());
        } else if (imageData is Uint8List) {
          imageBytes = imageData;
        } else {
          throw Exception('不支持的图片数据格式');
        }
        
        if (imageBytes.isNotEmpty) {
          // 发送到眼镜
          await _sendPhotoToGlasses(imageBytes);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('拍照失败：图片为空')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('拍照失败：未获取到图片数据')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照错误: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _sendPhotoToGlasses(Uint8List imageBytes) async {
    TextService.get.clear();
    TextService.get.startSendText("识别中…");

    try {
      final answer = await OpenRouterService().askWithImageBytes(
        prompt: '不要自我介绍，不要复述题干，不要解释推理过程，只输出最终答案。 - 如果图片信息不足无法确定：只输出"缺信息：……"并列出最少需要的1-3项关键信息。 选择题：只输出选项字母（如：C）。 - 填空/计算：只输出最终结果（含单位/保留位数按题目要求）。 - 多问：按(1)(2)(3)逐行输出答案。 - 如果题目要求"写步骤/过程"，也仍然只给最终答案。 若为作文/写作题： - 直接输出一篇英语作文/短文，总字数≤500字（含标点）。 - 不要标题（除非题目明确要求）。 - 结构清晰：开头点题，中间展开（2-3段），结尾收束。 - 紧扣题意与材料，不要复述题干。 - 如可能超长，优先保证结尾完整，必要时压缩中间段落。',
        imageBytes: imageBytes,
      );

      TextService.get.clear();
      TextService.get.startSendText(answer);
      
      // 返回上一页
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      TextService.get.clear();
      TextService.get.startSendText("识别失败");
    }
  }

  @override
  void dispose() {
    _channel.invokeMethod('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OTG相机'),
      ),
      body: Column(
        children: [
          // 相机预览区域（简化版本，实际UVC相机需要预览功能）
          Expanded(
            child: _isInitialized
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, size: 64, color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            '点击下方按钮拍照',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在初始化OTG相机...'),
                      ],
                    ),
                  ),
          ),
          // 拍照按钮
          Container(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: !_isCapturing ? _takePhoto : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.blue,
              ),
              child: _isCapturing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      '拍照',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
