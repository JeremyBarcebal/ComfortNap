import 'package:esp32_ble_app/ble.dart';
import 'package:esp32_ble_app/ble_man.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:esp32_ble_app/SetTimerScreen.dart';
import 'package:esp32_ble_app/sound.dart';
import 'package:esp32_ble_app/data.dart';
import 'dart:async';
// ===== FIREBASE =====
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ====================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ComfortNap',
      theme: ThemeData(
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
      ),
      home: const ComfortNapScreen(),
    );
  }
}

class ComfortNapScreen extends StatefulWidget {
  const ComfortNapScreen({super.key});

  @override
  State<ComfortNapScreen> createState() => _ComfortNapScreenState();
}

class _ComfortNapScreenState extends State<ComfortNapScreen> {
  double vibrationLevel = 0.6;
  double heatLevel = 38.0;
  double musicVolume = 0.6;

  bool bleConnected = false;

  // ===== SESSION TIMER =====
  DateTime? sessionStartTime;
  String? sessionDocId;
  String? activeSessionDocId;
  double currentSessionLevel = 0.5;
  bool isSessionRunning = false;
  Timer? sessionTimer;

  // ===== AUDIO =====
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? selectedSoundLabel;
  String? selectedSoundFile;

  // ===== FIREBASE =====
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref("ble_status");

  @override
  void initState() {
    super.initState();

    // ================= BLE STATUS =================
    BLEManager.instance.connectionStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          bleConnected = isConnected;
        });
      }
    });

    // ================= SLEEP STREAM =================
    BLEManager.instance.sleepStream.listen((msg) {
      try {
        final data = msg.replaceFirst("SLEEP:", "").split(",");

        final start = int.parse(data[0]);
        final end = int.parse(data[1]);
        final duration = int.parse(data[2]);

        // ✅ CONVERT HERE (THIS IS WHERE YOU PUT IT)
        final startDate = DateTime.fromMillisecondsSinceEpoch(start);
        final endDate = DateTime.fromMillisecondsSinceEpoch(end);

        FirebaseFirestore.instance.collection("vibrator_logs").add({
          "type": "sleep",
          "sleep_start": Timestamp.fromDate(startDate),
          "sleep_end": Timestamp.fromDate(endDate),
          "sleep_duration_minutes": duration,
          "status": "completed",
          "timestamp": FieldValue.serverTimestamp(),
        });

        print("SLEEP SAVED");
      } catch (e) {
        print("SLEEP ERROR: $e");
      }
    });
  }

  Future<void> saveSleepSession() async {
    if (sessionStartTime == null) return;

    final endTime = DateTime.now();

    final durationSeconds = endTime.difference(sessionStartTime!).inSeconds;
    final durationMinutes = (durationSeconds / 60).round();

    await FirebaseFirestore.instance.collection("vibrator_logs").add({
      "type": "sleep",
      "sleep_start": Timestamp.fromDate(sessionStartTime!),
      "sleep_end": Timestamp.fromDate(endTime),

      // Must match "sleep_duration_minutes" — that's the field every
      // reader (MonthlySleepScreen, data.dart's buildSleepCard) looks for.
      "sleep_duration_minutes": durationMinutes,

      "status": "completed",
      "timestamp": FieldValue.serverTimestamp(),
    });
  }

  Future<void> endCurrentSession() async {
    if (activeSessionDocId == null || sessionStartTime == null) {
      return;
    }

    final endTime = DateTime.now();

    final duration = endTime.difference(sessionStartTime!).inSeconds;

    await FirebaseFirestore.instance
        .collection("vibrator_logs")
        .doc(activeSessionDocId)
        .update({
          "status": "ended",
          "end_time": Timestamp.fromDate(endTime),
          "duration": duration,
          "final_vibration_level": (currentSessionLevel * 100).round(),
          "final_heat_level": heatLevel.round(),
        });

    activeSessionDocId = null;
  }

  Future<void> _playSelectedSound() async {
    try {
      await _audioPlayer.stop();

      if (selectedSoundFile != null) {
        await _audioPlayer.play(AssetSource('sounds/$selectedSoundFile'));

        await _audioPlayer.setVolume(musicVolume);
      }
    } catch (e) {
      print("ERROR PLAYING SOUND: $e");
    }
  }

  void startOneHourCheck() {
    sessionTimer?.cancel();

    sessionTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !isSessionRunning) return;

      _showExtendSessionDialog();
    });
  }

  void _showExtendSessionDialog() {
    bool handled = false;

    Timer(const Duration(seconds: 10), () async {
      if (handled) return;

      handled = true;

      Navigator.of(context, rootNavigator: true).pop();

      await BLEManager.instance.send("OFF");

      setState(() {
        isSessionRunning = false;
      });

      await endCurrentSession();
      await saveSleepSession();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Session Complete"),
          content: const Text("Extend session?\n\nAuto NO in 10 seconds."),
          actions: [
            TextButton(
              onPressed: () {
                if (handled) return;

                handled = true;

                Navigator.pop(context);

                startOneHourCheck();

                // ❌ DO NOT save sleep here (still session continues)
              },
              child: const Text("YES"),
            ),

            TextButton(
              onPressed: () async {
                if (handled) return;

                handled = true;

                Navigator.pop(context);

                await BLEManager.instance.send("OFF");

                setState(() {
                  isSessionRunning = false;
                });

                // ✅ USER ENDS SESSION → SAVE SLEEP
                await endCurrentSession();
                await saveSleepSession();
              },
              child: const Text("NO"),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ================= HEADER =================
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "ComfortNap",
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    IconButton(
                      icon: const Icon(
                        Icons.history_rounded,
                        color: Colors.cyanAccent,
                        size: 28,
                      ),
                      tooltip: "Sleep Record History",
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SleepSessionScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 25),

                // ================= VIBRATION =================
                Container(
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
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: [
                          const Icon(Icons.vibration, color: Colors.blue),

                          Expanded(
                            child: Slider(
                              value: vibrationLevel,
                              min: 0,
                              max: 1,
                              activeColor: Colors.blue,
                              inactiveColor: Colors.blue.withValues(alpha: 0.4),

                              onChanged: (val) async {
                                setState(() {
                                  vibrationLevel = val;
                                  currentSessionLevel = val; // 🔥 store latest
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
                            "${(vibrationLevel * 100).round()}%",
                            style: GoogleFonts.poppins(color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ================= HEAT =================
                _buildSliderTile(
                  title: "Heat Level",
                  icon: Icons.thermostat,
                  color: Colors.orange,
                  value: heatLevel,
                  min: 20,
                  max: 50,
                  label: "${heatLevel.round()}°C",
                  onChanged: (val) {
                    setState(() {
                      heatLevel = val;
                    });
                  },
                ),

                const SizedBox(height: 16),

                // ================= MUSIC =================
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E1B48), Color(0xFF2A2760)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Music Sounds",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              color: Colors.purpleAccent,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(12),
                            child: const Icon(
                              Icons.music_note,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              selectedSoundLabel ?? "None",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),

                          CircleAvatar(
                            backgroundColor: Colors.purple,
                            child: IconButton(
                              icon: Icon(
                                _audioPlayer.state == PlayerState.playing
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                if (selectedSoundFile == null) {
                                  return;
                                }

                                if (_audioPlayer.state == PlayerState.playing) {
                                  await _audioPlayer.pause();
                                } else {
                                  await _playSelectedSound();
                                }

                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),

                      Slider(
                        value: musicVolume,
                        min: 0,
                        max: 1,
                        onChanged: (val) async {
                          setState(() {
                            musicVolume = val;
                          });

                          await _audioPlayer.setVolume(val);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ================= TIMER =================
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SetTimerScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1B48),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.hourglass_bottom,
                          color: Colors.yellow,
                        ),

                        const SizedBox(width: 8),

                        Text(
                          "Set Timer",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),

                        const Spacer(),

                        const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.yellow,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ================= START BUTTON =================
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),

                    onPressed: () async {
                      if (!bleConnected) return;

                      sessionStartTime = DateTime.now();

                      await BLEManager.instance.send("ON");

                      final docRef = await FirebaseFirestore.instance
                          .collection("vibrator_logs")
                          .add({
                            "type": "session",
                            "status": "running",
                            "start_time": Timestamp.fromDate(sessionStartTime!),
                            "vibration_level": (currentSessionLevel * 100)
                                .round(),
                            "heat_level": heatLevel.round(),
                            "timestamp": FieldValue.serverTimestamp(),
                          });

                      activeSessionDocId = docRef.id;

                      setState(() {
                        isSessionRunning = true;
                      });

                      startOneHourCheck();

                      print("ACTIVE SESSION: $activeSessionDocId");
                    },

                    child: Text(
                      "Start Session",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ================= STOP BUTTON =================
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),

                    onPressed: () async {
                      sessionTimer?.cancel();

                      // ALWAYS STOP MOTOR FIRST
                      await BLEManager.instance.send("OFF");

                      if (activeSessionDocId == null) {
                        print("No active session");
                        return;
                      }

                      final endTime = DateTime.now();

                      final duration = endTime
                          .difference(sessionStartTime!)
                          .inSeconds;

                      await FirebaseFirestore.instance
                          .collection("vibrator_logs")
                          .doc(activeSessionDocId)
                          .update({
                            "status": "ended",
                            "end_time": Timestamp.fromDate(endTime),
                            "duration": duration,

                            // 🔥 final vibration level — must be 0-100 to match
                            // "vibration_level" saved at start (was previously
                            // saved as a raw 0-1 double, which displayed wrong)
                            "final_vibration_level": (currentSessionLevel * 100)
                                .round(),
                            "final_heat_level": heatLevel.round(),
                          });

                      print("SESSION UPDATED");

                      activeSessionDocId = null;

                      setState(() {
                        isSessionRunning = false;
                      });
                    },
                    child: Text(
                      "Stop Session",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ================= SOUND SCREEN =================
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SoundScreen(),
                      ),
                    );

                    if (result != null && mounted) {
                      setState(() {
                        selectedSoundLabel = result['label'];

                        selectedSoundFile = result['file'];
                      });

                      _playSelectedSound();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1B48),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(
                          "Sleep Sounds",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),

                        const Spacer(),

                        Text(
                          selectedSoundLabel ?? "",
                          style: GoogleFonts.poppins(
                            color: Colors.cyanAccent,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(width: 8),

                        const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ================= BLE BUTTON =================
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: bleConnected
                          ? Colors.redAccent
                          : Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),

                    icon: const Icon(Icons.bluetooth, color: Colors.white),

                    label: Text(
                      bleConnected ? "Disconnect" : "Connect",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),

                    onPressed: () async {
                      if (bleConnected) {
                        await BLEManager.instance.disconnect();

                        await _dbRef.set({
                          "status": "Disconnected",
                          "timestamp": ServerValue.timestamp,
                        });
                      } else {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BleHomePage(),
                          ),
                        );

                        if (result != null) {
                          await BLEManager.instance.connect(result);

                          await _dbRef.set({
                            "status": "Connected",
                            "timestamp": ServerValue.timestamp,
                          });
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required IconData icon,
    required Color color,
    required double value,
    required double min,
    required double max,
    required String label,
    required Function(double) onChanged,
  }) {
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
            title,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 18),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Icon(icon, color: color),

              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  activeColor: color,
                  inactiveColor: color.withValues(alpha: 0.4),
                  onChanged: onChanged,
                ),
              ),

              Text(label, style: GoogleFonts.poppins(color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }
}
