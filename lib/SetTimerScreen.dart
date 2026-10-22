import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SessionTimerSettings {
  const SessionTimerSettings({
    required this.durationSeconds,
    required this.vibrationLevel,
    required this.heatLevel,
  });

  final int durationSeconds;
  final double vibrationLevel;
  final double heatLevel;
}

class SetTimerScreen extends StatefulWidget {
  const SetTimerScreen({
    super.key,
    this.initialVibrationLevel = 0.5,
    this.initialHeatLevel = 50.0,
    this.initialDurationSeconds,
  });

  final double initialVibrationLevel;
  final double initialHeatLevel;
  final int? initialDurationSeconds;

  @override
  State<SetTimerScreen> createState() => _SetTimerScreenState();
}

class _SetTimerScreenState extends State<SetTimerScreen> {
  double selectedLevel = 0.5;
  double heatLevel = 50.0;
  int? selectedDurationSeconds;

  static const List<double> _heatLevels = [0.0, 25.0, 50.0, 75.0, 100.0];

  @override
  void initState() {
    super.initState();
    selectedLevel = widget.initialVibrationLevel;
    heatLevel = widget.initialHeatLevel;
    selectedDurationSeconds = widget.initialDurationSeconds;
  }

  double _snapHeatLevel(double value) {
    double closest = _heatLevels.first;

    for (final level in _heatLevels.skip(1)) {
      if ((value - level).abs() < (value - closest).abs()) {
        closest = level;
      }
    }

    return closest;
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
                    setState(() {
                      selectedDurationSeconds = totalSeconds;
                    });
                  },
                  child: const Text("Select"),
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

                  onChanged: (val) {
                    setState(() {
                      selectedLevel = val;
                    });
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
                  onChanged: (val) {
                    final selectedHeat = _snapHeatLevel(val);
                    setState(() {
                      heatLevel = selectedHeat;
                    });
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
    final isSelected = selectedDurationSeconds == sec;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected
              ? Colors.blueAccent
              : const Color(0xFF1E1B48),
          minimumSize: const Size(double.infinity, 50),
        ),
        onPressed: () {
          setState(() {
            selectedDurationSeconds = sec;
          });
        },
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remainingSeconds = duration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return hours == '00'
        ? '$minutes:$remainingSeconds'
        : '$hours:$minutes:$remainingSeconds';
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0731),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
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
                      "Selected Timer",
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedDurationSeconds == null
                          ? "No timer selected"
                          : _formatDuration(selectedDurationSeconds!),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

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

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: showCustomTimeDialog,
                      child: const Text("Custom Timer"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: selectedDurationSeconds == null
                          ? null
                          : () => Navigator.pop(
                              context,
                              SessionTimerSettings(
                                durationSeconds: selectedDurationSeconds!,
                                vibrationLevel: selectedLevel,
                                heatLevel: heatLevel,
                              ),
                            ),
                      child: const Text("Save"),
                    ),
                  ),
                ],
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
