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
  double heatLevel = 50.0;
  double pillowTemperature = 0.0;
  bool hasPillowTemperature = false;
  double musicVolume = 0.6;

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

  bool bleConnected = false;

  // ===== SESSION TIMER =====
  DateTime? sessionStartTime;
  String? sessionDocId;
  String? activeSessionDocId;
  double currentSessionLevel = 0.5;
  bool isSessionRunning = false;
  bool _heaterSafetyFaultActive = false;
  int? selectedSessionDurationSeconds;
  int? _remainingSessionSeconds;
  Timer? sessionCountdownTimer;
  bool _isStoppingSession = false;
  OverlayEntry? _sessionNoticeEntry;

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

    // ================= PILLOW TEMP STREAM =================
    BLEManager.instance.temperatureStream.listen((temp) {
      if (mounted) {
        setState(() {
          pillowTemperature = temp;
          hasPillowTemperature = true;
        });
      }
    });

    BLEManager.instance.heaterSafetyStream.listen((fault) {
      if (!mounted) return;

      if (fault == "CLEARED") {
        setState(() {
          _heaterSafetyFaultActive = false;
        });
        _showSessionMessageSnackBar(
          "Heat pad is cool and the temperature sensor is working. Start a new session to use heat.",
        );
        return;
      }

      setState(() {
        _heaterSafetyFaultActive = true;
      });

      final message = switch (fault) {
        "OVER_TEMPERATURE" =>
          "Heat pad overheated. Heating is off until it cools below 45°C.",
        "SENSOR_ERROR" =>
          "Heat pad temperature sensor error. Heating is off until safe readings return.",
        _ => "Heat pad safety fault. Heating is off while the fault is active.",
      };
      _showSessionMessageSnackBar(message);

      if (activeSessionDocId != null) {
        unawaited(_stopSession());
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
          if (hasPillowTemperature)
            "final_pillow_temperature": pillowTemperature,
        });

    activeSessionDocId = null;
  }

  void _showSessionMessageSnackBar(String message) {
    _showCenterSessionNotice(message: message);
  }

  void _showStopSessionConfirmation() {
    _showCenterSessionNotice(
      message: "Stopping session?",
      onOkay: _stopSession,
      showCancel: true,
    );
  }

  void _showCenterSessionNotice({
    required String message,
    Future<void> Function()? onOkay,
    bool showCancel = false,
  }) {
    _dismissSessionNotice();

    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Material(
        color: Colors.black38,
        child: Center(
          child: Container(
            width: (MediaQuery.sizeOf(context).width - 48)
                .clamp(0, 360)
                .toDouble(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B48),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  showCancel ? Icons.help_outline : Icons.check_circle_outline,
                  color: Colors.cyanAccent,
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (showCancel)
                      TextButton(
                        onPressed: _dismissSessionNotice,
                        child: const Text(
                          "Cancel",
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    TextButton(
                      onPressed: () async {
                        _dismissSessionNotice();
                        await onOkay?.call();
                      },
                      child: const Text(
                        "Okay",
                        style: TextStyle(color: Colors.cyanAccent),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    _sessionNoticeEntry = entry;
    overlay.insert(entry);
  }

  void _dismissSessionNotice() {
    final entry = _sessionNoticeEntry;
    _sessionNoticeEntry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }

  Future<void> _stopSession() async {
    if (activeSessionDocId == null ||
        sessionStartTime == null ||
        _isStoppingSession) {
      return;
    }

    _isStoppingSession = true;
    sessionCountdownTimer?.cancel();
    try {
      await BLEManager.instance.send("OFF");
      await BLEManager.instance.send("HEAT:0");

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
            if (hasPillowTemperature)
              "final_pillow_temperature": pillowTemperature,
          });

      activeSessionDocId = null;

      if (mounted) {
        setState(() {
          isSessionRunning = false;
          _remainingSessionSeconds = selectedSessionDurationSeconds;
        });
      }
    } finally {
      _isStoppingSession = false;
    }
  }

  void _startSessionCountdown() {
    sessionCountdownTimer?.cancel();
    final duration = selectedSessionDurationSeconds;
    _remainingSessionSeconds = duration;
    if (duration == null) return;

    sessionCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !isSessionRunning) {
        timer.cancel();
        return;
      }

      final remaining = _remainingSessionSeconds ?? 0;
      if (remaining <= 1) {
        timer.cancel();
        setState(() {
          _remainingSessionSeconds = 0;
        });
        unawaited(_finishTimedSession());
        return;
      }

      setState(() {
        _remainingSessionSeconds = remaining - 1;
      });
    });
  }

  Future<void> _finishTimedSession() async {
    await _stopSession();
    if (mounted && !isSessionRunning) {
      _showSessionMessageSnackBar("Session timer completed");
    }
  }

  String _formatSessionDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours.toString().padLeft(2, "0");
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, "0");
    final remainingSeconds = duration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, "0");
    return hours == "00"
        ? "$minutes:$remainingSeconds"
        : "$hours:$minutes:$remainingSeconds";
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

  @override
  void dispose() {
    sessionCountdownTimer?.cancel();
    _dismissSessionNotice();
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B48),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Heat Level",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            hasPillowTemperature
                                ? "Pillow ${pillowTemperature.toStringAsFixed(1)}°C"
                                : "Pillow --°C",
                            style: GoogleFonts.poppins(
                              color: Colors.orangeAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                              inactiveColor: Colors.orange.withValues(
                                alpha: 0.4,
                              ),
                              onChanged: (val) async {
                                final selectedHeat = _snapHeatLevel(val);
                                setState(() {
                                  heatLevel = selectedHeat;
                                });

                                if (isSessionRunning &&
                                    BLEManager.instance.connected) {
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
                          Text("0%", style: TextStyle(color: Colors.white70)),
                          Text("25%", style: TextStyle(color: Colors.white70)),
                          Text("50%", style: TextStyle(color: Colors.white70)),
                          Text("75%", style: TextStyle(color: Colors.white70)),
                          Text("100%", style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
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
                  onTap: () async {
                    if (isSessionRunning) {
                      _showSessionMessageSnackBar(
                        "Stop the current session before changing its timer.",
                      );
                      return;
                    }

                    final timerSettings =
                        await Navigator.push<SessionTimerSettings>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SetTimerScreen(
                              initialVibrationLevel: currentSessionLevel,
                              initialHeatLevel: heatLevel,
                              initialDurationSeconds:
                                  selectedSessionDurationSeconds,
                            ),
                          ),
                        );
                    if (timerSettings != null && mounted) {
                      setState(() {
                        selectedSessionDurationSeconds =
                            timerSettings.durationSeconds;
                        _remainingSessionSeconds =
                            timerSettings.durationSeconds;
                        currentSessionLevel = timerSettings.vibrationLevel;
                        vibrationLevel = timerSettings.vibrationLevel;
                        heatLevel = timerSettings.heatLevel;
                      });
                    }
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

                        Text(
                          selectedSessionDurationSeconds == null
                              ? "No timer"
                              : _formatSessionDuration(
                                  isSessionRunning
                                      ? (_remainingSessionSeconds ??
                                            selectedSessionDurationSeconds!)
                                      : selectedSessionDurationSeconds!,
                                ),
                          style: GoogleFonts.poppins(
                            color: Colors.cyanAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(width: 10),

                        const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
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
                      if (isSessionRunning) return;

                      if (selectedSessionDurationSeconds == null) {
                        _showSessionMessageSnackBar(
                          "Select and save a timer before starting.",
                        );
                        return;
                      }

                      if (!bleConnected) {
                        _showSessionMessageSnackBar(
                          "Connect to the device before starting a session.",
                        );
                        return;
                      }

                      if (_heaterSafetyFaultActive) {
                        _showSessionMessageSnackBar(
                          "Heat pad safety lockout. Wait for the pad to cool and the sensor to report safe readings.",
                        );
                        return;
                      }

                      String? newSessionDocId;
                      try {
                        final startTime = DateTime.now();
                        final docRef = await FirebaseFirestore.instance
                            .collection("vibrator_logs")
                            .add({
                              "type": "session",
                              "status": "running",
                              "start_time": Timestamp.fromDate(startTime),
                              "vibration_level": (currentSessionLevel * 100)
                                  .round(),
                              "heat_level": heatLevel.round(),
                              "timestamp": FieldValue.serverTimestamp(),
                            });
                        newSessionDocId = docRef.id;

                        await BLEManager.instance.send(
                          "VIB:${(currentSessionLevel * 100).round()}",
                        );
                        await BLEManager.instance.send(
                          "HEAT:${heatLevel.round()}",
                        );
                        await BLEManager.instance.send("ON");
                        if (_heaterSafetyFaultActive) {
                          throw StateError("Heat pad safety lockout detected.");
                        }

                        sessionStartTime = DateTime.now();
                        activeSessionDocId = newSessionDocId;

                        setState(() {
                          isSessionRunning = true;
                        });

                        _startSessionCountdown();
                        _showSessionMessageSnackBar("Session started");

                        print("ACTIVE SESSION: $activeSessionDocId");
                      } catch (error) {
                        await BLEManager.instance.send("OFF");
                        await BLEManager.instance.send("HEAT:0");

                        if (newSessionDocId != null) {
                          await FirebaseFirestore.instance
                              .collection("vibrator_logs")
                              .doc(newSessionDocId)
                              .update({"status": "failed"});
                        }

                        activeSessionDocId = null;
                        if (mounted) {
                          _showSessionMessageSnackBar(
                            "Session could not start: $error",
                          );
                        }
                      }
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
                      if (activeSessionDocId == null ||
                          sessionStartTime == null) {
                        _showSessionMessageSnackBar("No active session");
                        return;
                      }

                      _showStopSessionConfirmation();
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
}
