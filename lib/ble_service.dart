import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// Import UI yang salah letak sudah dihapus dari sini

class BleService {
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String wifiCharUuid = "4fafc204-1fb5-459e-8fcc-c5c9c331914b"; 
  
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? wifiCharacteristic;

  Future<void> connectToEsp32() async {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        if (r.device.platformName.startsWith("ESP32-NAV")) {
          FlutterBluePlus.stopScan();
          connectedDevice = r.device;
          
          await connectedDevice!.connect(license: License.nonprofit);
          await _discoverServices();
          break;
        }
      }
    });
  }

  Future<void> _discoverServices() async {
    if (connectedDevice == null) return;
    
    List<BluetoothService> services = await connectedDevice!.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid.toString() == serviceUuid) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == wifiCharUuid) {
            wifiCharacteristic = characteristic;
          }
        }
      }
    }
  }

  Future<void> sendWifiCredentials(String ssid, String password) async {
    if (wifiCharacteristic == null) {
      print("Karakteristik Wi-Fi belum ditemukan!");
      return;
    }

    String payload = "$ssid|$password";
    List<int> bytes = utf8.encode(payload);
    
    await wifiCharacteristic!.write(bytes, withoutResponse: true);
    print("Kredensial Wi-Fi terkirim: $payload");
  }
}

// Inisialisasi global ini wajib ada agar UI bisa memanggil kelas di atas
final bleService = BleService();