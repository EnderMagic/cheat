import 'package:demo_ai_even/ble_manager.dart';
import 'package:demo_ai_even/controllers/evenai_model_controller.dart';
import 'package:demo_ai_even/views/home_page.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // ✅ 建议加上

  final bm = BleManager.get();
  bm.setMethodCallHandler();       // ✅ 接收原生回调（连接/断开/发现设备）
  bm.startListening();             // ✅ 监听BLE数据
  bm.enableAutoConnect(channel: 57); // ✅ 自动扫描并连接（不固定就删掉channel参数）

  Get.put(EvenaiModelController());

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Even AI Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}
