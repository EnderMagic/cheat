import 'dart:async';
import 'package:demo_ai_even/app.dart';
import 'package:demo_ai_even/services/ble.dart';
import 'package:demo_ai_even/services/evenai.dart';
import 'package:demo_ai_even/services/proto.dart';
import 'package:flutter/services.dart';

typedef SendResultParse = bool Function(Uint8List value);

class BleManager {
  Function()? onStatusChanged;
  BleManager._() {}

  static BleManager? _instance;
  static BleManager get() {
    _instance ??= BleManager._();
    _instance!._init();
    return _instance!;
  }

  static const methodSend = "send";
  static const _eventBleReceive = "eventBleReceive";
  static const _channel = MethodChannel('method.bluetooth');

  final eventBleReceive = const EventChannel(_eventBleReceive)
      .receiveBroadcastStream(_eventBleReceive)
      .map((ret) => BleReceive.fromMap(ret));

  Timer? beatHeartTimer;

  final List<Map<String, String>> pairedGlasses = [];
  bool isConnected = false;
  String connectionStatus = 'Not connected';

  // ===================== 自动连接（新增/修正） =====================
  bool _autoConnectEnabled = false;
  bool _userDisconnected = false; // 用户手动断开后，不自动重连
  bool _autoBusy = false; // 防止并发扫描/连接
  bool _scanning = false;
  int? _preferredChannel; // 固定连接某个 channel（例如 57）
  Timer? _autoTimer;
  DateTime _lastAutoAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  // ===============================================================

  void _init() {}

  void startListening() {
    eventBleReceive.listen((res) {
      _handleReceivedData(res);
    });
  }

  Future<void> startScan() async {
    if (_scanning) return;
    try {
      _scanning = true;
      await _channel.invokeMethod('startScan');
    } catch (e) {
      _scanning = false;
      print('Error starting scan: $e');
    }
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    try {
      await _channel.invokeMethod('stopScan');
    } catch (e) {
      print('Error stopping scan: $e');
    } finally {
      _scanning = false;
    }
  }

  /// ⚠️ 注意：原生那边参数 key 叫 deviceName，但你传 "57"（channel）也能正常连
  Future<void> connectToGlasses(String channelOrName) async {
    try {
      await _channel.invokeMethod('connectToGlasses', {
        'deviceName': channelOrName, // ✅ 这里我们传 channelNumber 的字符串，比如 "57"
      });
      connectionStatus = 'Connecting...';
      onStatusChanged?.call();
    } catch (e) {
      print('Error connecting to device: $e');
    }
  }

  // ===================== 自动连接 API =====================
  void enableAutoConnect({int? channel}) {
    _preferredChannel = channel;
    _autoConnectEnabled = true;
    _userDisconnected = false;

    // 先跑一次
    _tryAutoConnect();

    // 周期兜底（断连/回调丢失也能拉回来）
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _tryAutoConnect();
    });
  }

  void disableAutoConnect() {
    _autoConnectEnabled = false;
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  /// 如果你有“断开按钮”，点断开前先调用它，避免自动连回去
  void markUserDisconnected() {
    _userDisconnected = true;
    disableAutoConnect();
  }

  Future<void> _tryAutoConnect() async {
    if (!_autoConnectEnabled) return;
    if (_userDisconnected) return;
    if (isConnected) return;
    if (connectionStatus == 'Connecting...') return;
    if (_autoBusy) return;

    // 节流：避免疯狂重试导致系统 scan fail
    final now = DateTime.now();
    if (now.difference(_lastAutoAttempt).inSeconds < 4) return;
    _lastAutoAttempt = now;

    _autoBusy = true;
    try {
      // 1) 先扫一小段时间
      await stopScan();
      await startScan();
      await Future.delayed(const Duration(seconds: 2));
      await stopScan();

      // 2) 选一个 channel 连接（关键修复：不要传 Even G1_57_L_xxx）
      final channelStr = _pickChannelToConnect();
      if (channelStr == null) return;

      await connectToGlasses(channelStr);
    } finally {
      _autoBusy = false;
    }
  }

  String? _pickChannelToConnect() {
    if (pairedGlasses.isEmpty) return null;

    // 优先连指定 channel
    if (_preferredChannel != null) {
      final ch = _preferredChannel!.toString();
      final hit = pairedGlasses.firstWhere(
            (g) => g['channelNumber'] == ch,
        orElse: () => {},
      );
      if (hit.isNotEmpty) return ch;
    }

    // 否则连第一个 paired 的 channel
    return pairedGlasses.first['channelNumber'];
  }
  // =======================================================

  void setMethodCallHandler() {
    _channel.setMethodCallHandler(_methodCallHandler);
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    switch (call.method) {
      case 'glassesConnected':
        _onGlassesConnected(call.arguments);
        break;
      case 'glassesConnecting':
        _onGlassesConnecting();
        break;
      case 'glassesDisconnected':
        _onGlassesDisconnected();
        break;
      case 'foundPairedGlasses':
        _onPairedGlassesFound(Map<String, String>.from(call.arguments));
        break;
      default:
        print('Unknown method: ${call.method}');
    }
  }

  void _onGlassesConnected(dynamic arguments) async {
    print("_onGlassesConnected----arguments----$arguments------");
    connectionStatus =
    'Connected: \n${arguments['leftDeviceName']} \n${arguments['rightDeviceName']}';
    isConnected = true;

    // ✅ 连上就停扫描（省电 + 防止系统报 scan fail）
    await stopScan();

    onStatusChanged?.call();
    startSendBeatHeart();
  }

  int tryTime = 0;
  void startSendBeatHeart() async {
    beatHeartTimer?.cancel();
    beatHeartTimer = null;

    beatHeartTimer = Timer.periodic(const Duration(seconds: 8), (timer) async {
      bool isSuccess = await Proto.sendHeartBeat();
      if (!isSuccess && tryTime < 2) {
        tryTime++;
        await Proto.sendHeartBeat();
      } else {
        tryTime = 0;
      }
    });
  }

  void _onGlassesConnecting() {
    connectionStatus = 'Connecting...';
    onStatusChanged?.call();
  }

  void _onGlassesDisconnected() {
    connectionStatus = 'Not connected';
    isConnected = false;

    // ✅ 断开就停心跳
    beatHeartTimer?.cancel();
    beatHeartTimer = null;

    onStatusChanged?.call();

    // ✅ 不是用户手动断开 => 自动重连
    if (_autoConnectEnabled && !_userDisconnected) {
      _tryAutoConnect();
    }
  }

  void _onPairedGlassesFound(Map<String, String> deviceInfo) {
    final channelNumber = deviceInfo['channelNumber'];
    if (channelNumber == null || channelNumber.isEmpty) return;

    final isAlreadyPaired =
    pairedGlasses.any((g) => g['channelNumber'] == channelNumber);

    if (!isAlreadyPaired) {
      pairedGlasses.add(deviceInfo);
    }

    onStatusChanged?.call();

    // ✅ 扫到 paired 就尝试连（按 channelNumber）
    if (_autoConnectEnabled && !_userDisconnected && !isConnected) {
      _tryAutoConnect();
    }
  }

  void _handleReceivedData(BleReceive res) {
    if (res.type == "VoiceChunk") return;

    String cmd = "${res.lr}${res.getCmd().toRadixString(16).padLeft(2, '0')}";
    if (res.getCmd() != 0xf1) {
      print(
        "${DateTime.now()} BleManager receive cmd: $cmd, len: ${res.data.length}, data = ${res.data.hexString}",
      );
    }

    if (res.data[0].toInt() == 0xF5) {
      final notifyIndex = res.data[1].toInt();

      switch (notifyIndex) {
        case 0:
          App.get.exitAll();
          break;
        case 1:
          if (res.lr == 'L') {
            EvenAI.get.lastPageByTouchpad();
          } else {
            EvenAI.get.nextPageByTouchpad();
          }
          break;
        case 23:
          EvenAI.get.toStartEvenAIByOS();
          break;
        case 24:
          EvenAI.get.recordOverByOS();
          break;
        default:
          print("Unknown Ble Event: $notifyIndex");
      }
      return;
    }

    _reqListen.remove(cmd)?.complete(res);
    _reqTimeout.remove(cmd)?.cancel();
    if (_nextReceive != null) {
      _nextReceive?.complete(res);
      _nextReceive = null;
    }
  }

  String getConnectionStatus() => connectionStatus;
  List<Map<String, String>> getPairedGlasses() => pairedGlasses;

  static final _reqListen = <String, Completer<BleReceive>>{};
  static final _reqTimeout = <String, Timer>{};
  static Completer<BleReceive>? _nextReceive;

  static _checkTimeout(String cmd, int timeoutMs, Uint8List data, String lr) {
    _reqTimeout.remove(cmd);
    var cb = _reqListen.remove(cmd);
    print(
        '${DateTime.now()} _checkTimeout-----timeoutMs----$timeoutMs-----cb----$cb-----');
    if (cb != null) {
      var res = BleReceive();
      res.isTimeout = true;
      print("send Timeout $cmd of $timeoutMs");
      cb.complete(res);
    }

    _reqTimeout[cmd]?.cancel();
    _reqTimeout.remove(cmd);
  }

  static Future<T?> invokeMethod<T>(String method, [dynamic params]) {
    return _channel.invokeMethod(method, params);
  }

  static Future<BleReceive> requestRetry(
      Uint8List data, {
        String? lr,
        Map<String, dynamic>? other,
        int timeoutMs = 200,
        bool useNext = false,
        int retry = 3,
      }) async {
    BleReceive ret;
    for (var i = 0; i <= retry; i++) {
      ret = await request(data,
          lr: lr, other: other, timeoutMs: timeoutMs, useNext: useNext);
      if (!ret.isTimeout) return ret;
      if (!BleManager.isBothConnected()) break;
    }
    ret = BleReceive();
    ret.isTimeout = true;
    print("requestRetry $lr timeout of $timeoutMs");
    return ret;
  }

  static Future<bool> sendBoth(
      data, {
        int timeoutMs = 250,
        SendResultParse? isSuccess,
        int? retry,
      }) async {
    var ret = await BleManager.requestRetry(data,
        lr: "L", timeoutMs: timeoutMs, retry: retry ?? 0);
    if (ret.isTimeout) {
      print("sendBoth L timeout");
      return false;
    } else if (isSuccess != null) {
      final success = isSuccess.call(ret.data);
      if (!success) return false;
      var retR = await BleManager.requestRetry(data,
          lr: "R", timeoutMs: timeoutMs, retry: retry ?? 0);
      if (retR.isTimeout) return false;
      return isSuccess.call(retR.data);
    } else if (ret.data[1].toInt() == 0xc9) {
      var ret = await BleManager.requestRetry(data,
          lr: "R", timeoutMs: timeoutMs, retry: retry ?? 0);
      if (ret.isTimeout) return false;
    }
    return true;
  }

  static Future sendData(Uint8List data,
      {String? lr, Map<String, dynamic>? other, int secondDelay = 100}) async {
    var params = <String, dynamic>{'data': data};
    if (other != null) params.addAll(other);

    if (lr != null) {
      params["lr"] = lr;
      return BleManager.invokeMethod(methodSend, params);
    } else {
      params["lr"] = "L";
      var ret = await _channel.invokeMethod(methodSend, params);
      if (ret == true) {
        params["lr"] = "R";
        return BleManager.invokeMethod(methodSend, params);
      }
      if (secondDelay > 0) {
        await Future.delayed(Duration(milliseconds: secondDelay));
      }
      params["lr"] = "R";
      return BleManager.invokeMethod(methodSend, params);
    }
  }

  static Future<BleReceive> request(
      Uint8List data, {
        String? lr,
        Map<String, dynamic>? other,
        int timeoutMs = 1000,
        bool useNext = false,
      }) async {
    var lr0 = lr ?? Proto.lR();
    var completer = Completer<BleReceive>();
    String cmd = "$lr0${data[0].toRadixString(16).padLeft(2, '0')}";

    if (useNext) {
      _nextReceive = completer;
    } else {
      if (_reqListen.containsKey(cmd)) {
        var res = BleReceive();
        res.isTimeout = true;
        _reqListen[cmd]?.complete(res);
        print("already exist key: $cmd");
        _reqTimeout[cmd]?.cancel();
      }
      _reqListen[cmd] = completer;
    }
    print("request key: $cmd, ");

    if (timeoutMs > 0) {
      _reqTimeout[cmd] = Timer(Duration(milliseconds: timeoutMs), () {
        _checkTimeout(cmd, timeoutMs, data, lr0);
      });
    }

    completer.future.then((_) {
      _reqTimeout.remove(cmd)?.cancel();
    });

    await sendData(data, lr: lr, other: other).timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _reqTimeout.remove(cmd)?.cancel();
        var ret = BleReceive();
        ret.isTimeout = true;
        _reqListen.remove(cmd)?.complete(ret);
      },
    );

    return completer.future;
  }

  static bool isBothConnected() {
    // 原版就是 true
    return true;
  }

  static Future<bool> requestList(
      List<Uint8List> sendList, {
        String? lr,
        int? timeoutMs,
      }) async {
    print(
        "requestList---sendList---${sendList.first}----lr---$lr----timeoutMs----$timeoutMs-");

    if (lr != null) {
      return await _requestList(sendList, lr, timeoutMs: timeoutMs);
    } else {
      var rets = await Future.wait([
        _requestList(sendList, "L", keepLast: true, timeoutMs: timeoutMs),
        _requestList(sendList, "R", keepLast: true, timeoutMs: timeoutMs),
      ]);
      if (rets.length == 2 && rets[0] && rets[1]) {
        var lastPack = sendList[sendList.length - 1];
        return await sendBoth(lastPack, timeoutMs: timeoutMs ?? 250);
      } else {
        print("error request lr leg");
      }
    }
    return false;
  }

  static Future<bool> _requestList(
      List sendList,
      String lr, {
        bool keepLast = false,
        int? timeoutMs,
      }) async {
    int len = sendList.length;
    if (keepLast) len = sendList.length - 1;
    for (var i = 0; i < len; i++) {
      var pack = sendList[i];
      var resp = await request(pack, lr: lr, timeoutMs: timeoutMs ?? 350);
      if (resp.isTimeout) return false;
      final b = resp.data[1].toInt();
      if (b != 0xc9 && b != 0xcB) return false;
    }
    return true;
  }
}

extension Uint8ListEx on Uint8List {
  String get hexString {
    return map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
  }
}
