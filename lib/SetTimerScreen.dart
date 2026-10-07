import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ble_man.dart';
import 'dart:async';

class SetTimerScreen extends StatefulWidget {
  const SetTimerScreen({super.key});

  @override
  State<SetTimerScreen> createState() => _SetTimerScreenState();
}

class _SetTimerScreenState extends State<SetTimerScreen> {
  double selectedLevel = 0.5;
  double heatLevel = 50.0;
  bool isLocked = false;

  static const List<double> _heatLevels = [0.0, 25.0, 50.0, 75.0, 100.0];

  double _snapHeatLevel(double value) {
    double closest = _heatLevels.first;

    for (final level in _heatLevels.skip(1)) {
      if ((value - level).abs() < (value - closest).abs()) {
        closest = level;
      }
    }

    return closest;
  }

  int remainingSeconds = 0;
  Timer? countdownTimer;
  Timer? autoFinishTimer; // cancellable replacement for the old Future.delayed
  String? currentLogId;
  DateTime? sessionStartTime;
  int originalDuration = 0;

  @override
  void dispose() {
    countdownTimer?.cancel();
    autoFinishTimer?.cancel();
    super.dispose();
  }

  // ================= TIMER FUNCTION =================
  Future<void> sendTimer(int seconds) async {
    if (!BLEManager.instance.connected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Device not connected")));
      return;
    }

    setState(() {
      isLocked = true;
      remainingSeconds = seconds;
      originalDuration = seconds;
    });

    sessionStartTime = DateTime.now();

    final levelPercent = (selectedLevel * 100).round();

    final startTime = DateTime.now();
    final endTime = startTime.add(Duration(seconds: seconds));

    final docRef = await FirebaseFirestore.instance
        .collection("vibrator_logs")
        .add({
          "type": "timer",
          "status": "running",
          "set_time": Timestamp.fromDate(startTime),
          "end_time": Timestamp.fromDate(endTime),
          "duration": seconds,
          "vibration_level": levelPercent,
          "heat_level": heatLevel.round(),
          "timestamp": FieldValue.serverTimestamp(),
        });
    currentLogId = docRef.id;

    // 🔥 DEBUG (check if sending)
    print("BLE SEND: VIB,$seconds,$levelPercent");

    // 🔥 FIXED FORMAT (common Arduino/ESP32 readable format)
    await BLEManager.instance.send("ON");
    await Future.delayed(const Duration(milliseconds: 200));
    await BLEManager.instance.send("VIB:${levelPercent}");
    await BLEManager.instance.send("HEAT:${heatLevel.round()}");
    countdownTimer?.cancel();

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (remainingSeconds > 0) {
        setState(() {
          remainingSeconds--;
        });
      } else {
        timer.cancel();
      }
    });

    // 🔥 Auto-finish when the timer naturally reaches zero.
    // Uses a cancellable Timer (not Future.delayed) so STOP TIMER can
    // actually prevent this from firing later and clobbering the
    // "cancelled" status / resetting a newer session's UI state.
    autoFinishTimer?.cancel();
    autoFinishTimer = Timer(Duration(seconds: seconds), () async {
      await BLEManager.instance.send("OFF");

      await FirebaseFirestore.instance
          .collection("vibrator_logs")
          .doc(docRef.id)
          .update({"status": "ended"});

      countdownTimer?.cancel();

      if (mounted) {
        setState(() {
          isLocked = false;
          remainingSeconds = 0;
        });
      }
    });
  }

  // ================= CUSTOM TIMER =================
  void showCustomTimeDialog() {
    int selectedHours = 0;
    int selectedMinutes = 0;
    int selectedSeconds = 0;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1B48),
              title: const Text(
                "Custom Timer",
                style: TextStyle(color: Colors.white),
              ),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Hours
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Hours",
                        style: TextStyle(color: Colors.white),
                      ),
                      DropdownButton<int>(
                        dropdownColor: const Color(0xFF1E1B48),
                        value: selectedHours,
                        items: List.generate(
                          24,
                          (index) => DropdownMenuItem(
                            value: index,
                            child: Text(
                              "$index",
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedHours = value!;
                          });
                        },
                      ),
                    ],
                  ),

                  // Minutes
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Minutes",
                        style: TextStyle(color: Colors.white),
                      ),
                      DropdownButton<int>(
                        dropdownColor: const Color(0xFF1E1B48),
                        value: selectedMinutes,
                        items: List.generate(
                          60,
                          (index) => DropdownMenuItem(
                            value: index,
                            child: Text(
                              "$index",
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedMinutes = value!;
                          });
                        },
                      ),
                    ],
                  ),

                  // Seconds
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Seconds",
                        style: TextStyle(color: Colors.white),
                      ),
                      DropdownButton<int>(
                        dropdownColor: const Color(0xFF1E1B48),
                        value: selectedSeconds,
                        items: List.generate(
                          60,
                          (index) => DropdownMenuItem(
                            value: index,
                            child: Text(
                              "$index",
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedSeconds = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    int totalSeconds =
                        (selectedHours * 3600) +
                        (selectedMinutes * 60) +
                        selectedSeconds;

                    if (totalSeconds <= 0) return;

                    Navigator.pop(context);
                    sendTimer(totalSeconds);
                  },
                  child: const Text("Start"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ================= SLIDER UI =================
  Widget buildLevelSlider() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B48),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Vibration Level",
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(Icons.vibration, color: Colors.blue),

              Expanded(
                child: Slider(
                  value: selectedLevel,
                  min: 0,
                  max: 1,
                  activeColor: Colors.blue,
                  inactiveColor: Colors.blue.withValues(alpha: 0.4),

                  onChanged: isLocked
                      ? null
                      : (val) async {
                          setState(() {
                            selectedLevel = val;
                          });

                          if (BLEManager.instance.connected) {
                            await BLEManager.instance.send(
                              "VIB:${(val * 100).round()}",
                            );
                          }
                        },
                ),
              ),

              Text(
                "${(selectedLevel * 100).round()}%",
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= HEAT SLIDER UI =================
  Widget buildHeatSlider() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B48),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Heat Level",
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(Icons.thermostat, color: Colors.orange),

              Expanded(
                child: Slider(
                  value: heatLevel,
                  min: 0,
                  max: 100,
                  divisions: 4,
                  activeColor: Colors.orange,
                  inactiveColor: Colors.orange.withValues(alpha: 0.4),
                  onChanged: isLocked
                      ? null
                      : (val) async {
                          final selectedHeat = _snapHeatLevel(val);
                          setState(() {
                            heatLevel = selectedHeat;
                          });

                          if (BLEManager.instance.connected) {
                            await BLEManager.instance.send(
                              "HEAT:${selectedHeat.round()}",
                            );
                          }
                        },
                ),
              ),

              Text(
                "${heatLevel.round()}",
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text("0", style: TextStyle(color: Colors.white70)),
              Text("25", style: TextStyle(color: Colors.white70)),
              Text("50", style: TextStyle(color: Colors.white70)),
              Text("75", style: TextStyle(color: Colors.white70)),
              Text("100", style: TextStyle(color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  // ================= PRESET BUTTON =================
  Widget buildButton(String text, int sec) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E1B48),
          minimumSize: const Size(double.infinity, 50),
        ),
        onPressed: isLocked ? null : () => sendTimer(sec),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0731),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 10),

              Text(
                "Set Timer",
                style: GoogleFonts.poppins(fontSize: 26, color: Colors.white),
              ),

              const SizedBox(height: 30),

              buildLevelSlider(),

              const SizedBox(height: 16),

              buildHeatSlider(),

              const SizedBox(height: 30),

              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.5,
                children: [
                  buildButton("1 min", 60),
                  buildButton("5 min", 300),
                  buildButton("15 min", 900),
                  buildButton("30 min", 1800),
                  buildButton("1 hour", 3600),
                  buildButton("1 hr 30 min", 5400),
                ],
              ), // bagong button

              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: isLocked ? null : showCustomTimeDialog,
                  child: const Text("Custom Timer"),
                ),
              ),

              const SizedBox(height: 20),

              if (isLocked)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B48),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "Timer Running",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Duration(
                          seconds: remainingSeconds,
                        ).toString().split('.').first,
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

              if (isLocked)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () async {
                        countdownTimer?.cancel();
                        autoFinishTimer?.cancel();

                        await BLEManager.instance.send("OFF");

                        final actualDuration =
                            originalDuration - remainingSeconds;

                        if (currentLogId != null) {
                          await FirebaseFirestore.instance
                              .collection("vibrator_logs")
                              .doc(currentLogId)
                              .update({
                                "status": "cancelled",
                                "duration": actualDuration,
                                "actual_duration": actualDuration,
                                "actual_end_time": Timestamp.now(),
                              });
                        }

                        setState(() {
                          isLocked = false;
                          remainingSeconds = 0;
                        });
                      },
                      child: const Text(
                        "STOP TIMER",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              Text(
                "Selected: ${(selectedLevel * 100).round()}% • ${heatLevel.round()}°C",
                style: const TextStyle(color: Colors.white),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
