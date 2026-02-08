import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';

class OpenRouterService {
  // ✅ 写死在这里（自己填）
  static const String _apiKey = "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";

  // 文字模型（你现在用的）
  static const String _textModel = "openai/gpt-5-mini";

  // ⚠️ 图片模型：这里必须换成“支持 images 的多模态模型”
  // 在 OpenRouter 模型页确认支持 Images 后，把模型 id 填到这里
  static const String _visionModel = "openai/gpt-5-mini";

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://openrouter.ai/api/v1',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 75),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    },
  ));

  Map<String, dynamic> get _providerPref => {
    // ✅ OpenRouter 供应商路由策略：Azure 优先，OpenAI 兜底，按延迟选
    // (order/allow_fallbacks/sort 是 OpenRouter 支持的 provider 配置)
    'order': ['azure', 'openai'],
    'allow_fallbacks': true,
    'sort': 'latency',
  };

  String _parseContent(dynamic data) {
    final content = (data is Map &&
        data['choices'] is List &&
        (data['choices'] as List).isNotEmpty)
        ? ((data['choices'][0] as Map)['message']?['content'] as String?)
        ?.trim()
        : null;

    if (content == null || content.isEmpty) {
      throw Exception('OpenRouter 返回空内容');
    }
    return content;
  }

  /// 文字问答
  Future<String> ask(String prompt, {int maxTokens = 120}) async {
    final resp = await _dio.post('/chat/completions', data: {
      'model': _textModel,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'provider': _providerPref,
    });

    return _parseContent(resp.data);
  }

  /// 图片问答：传入图片 bytes（相机拍照后 readAsBytes() 得到）
  /// mimeType 默认 jpeg；你也可以传 image/png
  Future<String> askWithImageBytes({
    required String prompt,
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    final b64 = base64Encode(imageBytes);
    final dataUrl = 'data:$mimeType;base64,$b64'; // OpenRouter 支持 base64 data url :contentReference[oaicite:3]{index=3}

    final resp = await _dio.post('/chat/completions', data: {
      'model': _visionModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        },
      ],
      'provider': _providerPref,
    });

    return _parseContent(resp.data);
  }
}
