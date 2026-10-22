import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:esp32_ble_app/ble_man.dart';
import 'package:google_fonts/google_fonts.dart';

// NOTE: This file used to have its own main()/MyApp here, but main.dart
// already defines MyApp and is the app's real entry point. Having two
// classes named MyApp in the same package fails to compile, so this
// screen now only exposes BleHomePage for main.dart to push onto the nav stack.

class BleHomePage extends StatefulWidget {
  const BleHomePage({super.key});

  @override
  State<BleHomePage> createState() => _BleHomePageState();
}

class _BleHomePageState extends State<BleHomePage> {
  final List<ScanResult> _scanResults = [];
  final List<String> _log = [];

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanningSub;
  bool _scanning = false;
  bool _connecting = false;
  bool _disposed = false;

  // ================= PERMISSIONS =================
  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;

    await Permission.locationWhenInUse.request();

    try {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
    } catch (_) {}
  }

  // ================= SCAN =================
  Future<void> _startScan() async {
    if (!mounted || _disposed) return;

    await _scanSub?.cancel();
    _scanSub = null;
    await _scanningSub?.cancel();
    _scanningSub = null;
    if (!mounted || _disposed) return;

    setState(() {
      _scanResults.clear();
      _scanning = true;
    });

    await _ensurePermissions();
    if (!mounted || _disposed) return;

    await FlutterBluePlus.stopScan();
    if (!mounted || _disposed) return;

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted || _disposed) return;
      setState(() {
        _scanResults
          ..clear()
          ..addAll(results);
      });
    });

    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (!mounted || _disposed) return;
      setState(() => _scanning = s);
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
  }

  // ================= CONNECT =================
  Future<void> _connect(ScanResult r) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    _addLog("Connecting → ${r.device.name}");
    try {
      await BLEManager.instance.connect(r.device);
      if (!mounted) return;
      _addLog("Connected ✔ ${r.device.name}");

      // Report the connected device back to whoever pushed this screen
      // (main.dart awaits this to know when to update ble_status).
      Navigator.pop(context, r.device);
    } catch (e) {
      _addLog("Failed ❌ $e");
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() => _log.insert(0, msg));
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_scanSub?.cancel());
    unawaited(_scanningSub?.cancel());
    unawaited(FlutterBluePlus.stopScan());
    super.dispose();
  }

  // ================= DEVICE CARD =================
  Widget _deviceCard(ScanResult r) {
    final name = r.device.name.isNotEmpty ? r.device.name : "Unknown Device";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B48),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.cyanAccent.withOpacity(0.15),
            child: const Icon(Icons.bluetooth, color: Colors.cyanAccent),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  r.device.id.toString(),
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),

          ElevatedButton(
            onPressed: _connecting ? null : () => _connect(r),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("Connect"),
          ),
        ],
      ),
    );
  }

  // ================= EMPTY STATE =================
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _scanning ? Icons.radar : Icons.bluetooth_disabled,
            size: 90,
            color: Colors.cyanAccent.withOpacity(0.4),
          ),
          const SizedBox(height: 12),

          Text(
            _scanning ? "Scanning nearby devices..." : "No BLE devices found",
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            "Tap scan button to start",
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ================= LOG PANEL =================
  Widget _logPanel() {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B48),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.terminal, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Text(
                "Logs",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          SizedBox(
            height: 110,
            child: _log.isEmpty
                ? const Center(
                    child: Text(
                      "No activity yet",
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _log[i],
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0B2E),

        iconTheme: const IconThemeData(color: Colors.white),

        title: Text(
          "BLE Scanner",
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: Column(
        children: [
          // STATUS BAR
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: const Color(0xFF1E1B48),
            child: Row(
              children: [
                Icon(
                  _scanning ? Icons.radar : Icons.wifi_off,
                  color: Colors.cyanAccent,
                ),
                const SizedBox(width: 10),

                Text(
                  _scanning ? "Scanning..." : "Idle",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _scanResults.isEmpty
                ? _emptyState()
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (_, i) => _deviceCard(_scanResults[i]),
                  ),
          ),

          _logPanel(),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blueAccent,
        onPressed: _scanning ? () => FlutterBluePlus.stopScan() : _startScan,
        icon: Icon(_scanning ? Icons.stop : Icons.search),
        label: Text(_scanning ? "Stop" : "Scan"),
      ),
    );
  }
}
