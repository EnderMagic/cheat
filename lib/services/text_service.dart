import 'dart:async';
import 'dart:math';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/proto.dart';

class TextService {
  static TextService? _instance;
  static TextService get get => _instance ??= TextService._();

  static bool isRunning = false;
  static int maxRetry = 5;

  static int _currentLine = 0;
  static Timer? _timer;

  // ✅ 1分钟无新内容自动清屏
  static Timer? _autoClearTimer;
  static DateTime _lastSendAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ✅ 防止 Timer.periodic async 重入
  static bool _pagingBusy = false;

  static List<String> list = [];
  static List<String> sendReplys = [];

  TextService._();

  // 触摸“空闲清屏”计时器：每次成功发送新内容就重置 1 分钟倒计时
  static void _touchAutoClearTimer() {
    _lastSendAt = DateTime.now();
    _autoClearTimer?.cancel();
    _autoClearTimer = Timer(const Duration(minutes: 1), () async {
      // 仍然1分钟没新内容 -> 清屏并清状态
      if (DateTime.now().difference(_lastSendAt) >= const Duration(minutes: 1)) {
        await _clearGlassScreen();
        get.clear();
      }
    });
  }

  // 清空眼镜显示（发 5 行空行）
  static Future<void> _clearGlassScreen() async {
    try {
      await Proto.sendEvenAIData(
        "\n\n\n\n\n",
        newScreen: EvenAIDataMethod.transferToNewScreen(0x01, 0x70),
        pos: 0,
        current_page_num: 1,
        max_page_num: 1,
      );
    } catch (_) {
      // 忽略清屏失败
    }
  }

  Future startSendText(String text) async {
    // 每次开始新内容，先停掉旧的分页计时器（但不强制清屏）
    _timer?.cancel();
    _timer = null;

    isRunning = true;
    _currentLine = 0;
    sendReplys = [];
    retryCount = 0;

    list = EvenAIDataMethod.measureStringList(text);

    // --- 单页情况：直接发一次就结束（等待 1 分钟无新内容自动清屏） ---
    if (list.length < 4) {
      String startScreenWords =
      list.sublist(0, min(3, list.length)).map((str) => '$str\n').join();
      String headString = '\n\n';
      startScreenWords = headString + startScreenWords;

      await doSendText(startScreenWords, 0x01, 0x70, 0);
      return;
    }

    if (list.length == 4) {
      String startScreenWords = list.sublist(0, 4).map((str) => '$str\n').join();
      String headString = '\n';
      startScreenWords = headString + startScreenWords;
      await doSendText(startScreenWords, 0x01, 0x70, 0);
      return;
    }

    if (list.length == 5) {
      String startScreenWords = list.sublist(0, 5).map((str) => '$str\n').join();
      await doSendText(startScreenWords, 0x01, 0x70, 0);
      return;
    }

    // --- 多页情况：先发第一页，然后启动分页定时器 ---
    String startScreenWords = list.sublist(0, 5).map((str) => '$str\n').join();
    bool isSuccess = await doSendText(startScreenWords, 0x01, 0x70, 0);

    if (isSuccess) {
      _currentLine = 0;
      await updateReplyToOSByTimer();
    } else {
      clear();
    }
  }

  int retryCount = 0;

  Future<bool> doSendText(String text, int type, int status, int pos) async {
    print(
        '${DateTime.now()} doSendText--currentPage---${getCurrentPage()}-----text----$text-----type---$type---status---$status----pos---$pos-');

    if (!isRunning) return false;

    final bool isSuccess = await Proto.sendEvenAIData(
      text,
      newScreen: EvenAIDataMethod.transferToNewScreen(type, status),
      pos: pos,
      current_page_num: getCurrentPage(),
      max_page_num: getTotalPages(),
    );

    if (!isSuccess) {
      if (retryCount < maxRetry) {
        retryCount++;
        return await doSendText(text, type, status, pos);
      } else {
        retryCount = 0;
        return false;
      }
    }

    retryCount = 0;

    // ✅ 成功发送新内容 -> 1分钟清屏倒计时重置
    TextService._touchAutoClearTimer();

    return true;
  }

  Future updateReplyToOSByTimer() async {
    if (!isRunning) return;

    const int interval = 8; // 每页间隔秒数（可自定义）

    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: interval), (timer) async {
      if (!isRunning) return;
      if (_pagingBusy) return;

      _pagingBusy = true;
      try {
        // ✅ 如果没有下一页了，就停止分页（不再重复发送最后一页）
        final int nextLine = _currentLine + 5;
        if (nextLine >= list.length) {
          _timer?.cancel();
          _timer = null;
          // 不 clear()，保留最后一页显示；1分钟无新内容会自动清屏
          return;
        }

        _currentLine = nextLine;
        sendReplys = list.sublist(_currentLine);

        final mergedStr = sendReplys
            .sublist(0, min(5, sendReplys.length))
            .map((str) => '$str\n')
            .join();

        await doSendText(mergedStr, 0x01, 0x70, 0);

        // ✅ 如果这次发完就是最后一页了，立刻停止定时器（不等下一次 tick）
        if (_currentLine + 5 >= list.length) {
          _timer?.cancel();
          _timer = null;
        }
      } finally {
        _pagingBusy = false;
      }
    });
  }

  int getTotalPages() {
    if (list.isEmpty) return 0;
    if (list.length < 6) return 1;

    int div = list.length ~/ 5;
    int rest = list.length % 5;
    int pages = div + (rest == 0 ? 0 : 1);
    return pages;
  }

  int getCurrentPage() {
    if (_currentLine == 0) return 1;

    int div = _currentLine ~/ 5;
    int rest = _currentLine % 5;

    int currentPage = 1 + div;
    if (rest != 0) currentPage++;
    return currentPage;
  }

  Future stopTextSendingByOS() async {
    print("stopTextSendingByOS---------------");
    isRunning = false;
    clear();
  }

  void clear() {
    isRunning = false;
    _currentLine = 0;

    _timer?.cancel();
    _timer = null;

    _autoClearTimer?.cancel();
    _autoClearTimer = null;

    list = [];
    sendReplys = [];
    retryCount = 0;
    _pagingBusy = false;
  }
}
