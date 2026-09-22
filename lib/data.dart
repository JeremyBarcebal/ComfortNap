import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'weekly_sleep_screen.dart';
import 'monthly_sleep_screen.dart';
import 'package:table_calendar/table_calendar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SleepSessionScreen(),
    ),
  );
}

class SleepSessionScreen extends StatefulWidget {
  const SleepSessionScreen({super.key});

  @override
  State<SleepSessionScreen> createState() => _SleepSessionScreenState();
}

class _SleepSessionScreenState extends State<SleepSessionScreen> {
  int selectedDayIndex = DateTime.now().weekday % 7;
  DateTime selectedDate = DateTime.now();

  // ✅ ADDED ONLY
  final Map<String, Map<String, dynamic>> _deletedCache = {};

  bool isSameSelectedDay(Timestamp ts) {
    final date = ts.toDate();
    return date.year == selectedDate.year &&
        date.month == selectedDate.month &&
        date.day == selectedDate.day;
  }

  // ✅ ADDED ONLY (DELETE + UNDO LOGIC)
  Future<void> deleteWithUndo(String docId, Map<String, dynamic> data) async {
    _deletedCache[docId] = data;

    await FirebaseFirestore.instance
        .collection("vibrator_logs")
        .doc(docId)
        .delete();

    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Deleted"),
        duration: const Duration(seconds: 3), // ⬅️ auto close after 3 sec
        action: SnackBarAction(
          label: "UNDO",
          onPressed: () async {
            final restored = _deletedCache[docId];

            if (restored != null) {
              await FirebaseFirestore.instance
                  .collection("vibrator_logs")
                  .doc(docId)
                  .set(restored);

              _deletedCache.remove(docId);
            }
          },
        ),
      ),
    );

    // ⬅️ after 3 seconds, remove undo data (prevents restore after timeout)
    Future.delayed(const Duration(seconds: 3), () {
      _deletedCache.remove(docId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = selectedDate;

    return Scaffold(
      backgroundColor: const Color(0xFF09042F),

      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("vibrator_logs")
              .orderBy("timestamp", descending: true)
              .snapshots(),

          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              );
            }

            final docs = snapshot.data!.docs;

            final sessionLogs = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              if (data["type"] != "session") return false;
              if (data["timestamp"] == null) return false;
              return isSameSelectedDay(data["timestamp"]);
            }).toList();

            final timerLogs = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              if (data["type"] != "timer") return false;
              if (data["timestamp"] == null) return false;
              return isSameSelectedDay(data["timestamp"]);
            }).toList();

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => WeeklySleepScreen(
                                  selectedDate: selectedDate,
                                ),
                              ),
                            );
                          },
                          child: _iconButton(Icons.calendar_view_week),
                        ),

                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const MonthlySleepScreen(),
                              ),
                            );
                          },
                          child: _iconButton(Icons.calendar_month),
                        ),

                        GestureDetector(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: const Color(0xFF09042F),
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(25),
                                ),
                              ),
                              builder: (_) => CalendarOverlay(
                                onDateSelected: (date) {
                                  setState(() {
                                    selectedDate = date;
                                    selectedDayIndex = date.weekday % 7;
                                  });
                                },
                              ),
                            );
                          },
                          child: _iconButton(Icons.calendar_today),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Text(
                  DateFormat('EEEE').format(now),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  DateFormat('MMMM d, y').format(now),
                  style: TextStyle(
                    color: Colors.white.withOpacity(.7),
                    fontSize: 17,
                  ),
                ),

                const SizedBox(height: 25),

                SizedBox(
                  height: 62,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: List.generate(7, (index) {
                      DateTime weekStart = selectedDate.subtract(
                        Duration(days: selectedDate.weekday % 7),
                      );

                      DateTime day = weekStart.add(Duration(days: index));

                      return buildDay(day, index);
                    }),
                  ),
                ),

                const SizedBox(height: 30),

                const Text(
                  "Session History",
                  style: TextStyle(color: Colors.white, fontSize: 22),
                ),

                const SizedBox(height: 18),

                ...sessionLogs.map((doc) => buildSessionCard(doc)),

                const SizedBox(height: 25),

                const Text(
                  "Timer Logs",
                  style: TextStyle(color: Colors.white, fontSize: 22),
                ),

                const SizedBox(height: 18),

                ...timerLogs.map((doc) => buildTimerCard(doc)),
              ],
            );
          },
        ),
      ),
    );
  }

  // ================= ICON =================
  Widget _iconButton(IconData icon) {
    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }

  // ================= DAY =================
  Widget buildDay(DateTime day, int index) {
    final isSelected =
        day.year == selectedDate.year &&
        day.month == selectedDate.month &&
        day.day == selectedDate.day;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedDate = day;
          selectedDayIndex = index;
        });
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF6B5BFF), Color(0xFF24E0FF)],
                )
              : null,
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('EEE').format(day),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              day.day.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= SESSION CARD (UNCHANGED + WRAPPED) =================
  Widget buildSessionCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final start = data["start_time"];
    final end = data["end_time"];
    final duration = data["duration"] ?? 0;
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;

    String durationText = "";

    if (hours > 0) {
      durationText += "${hours}h ";
    }
    if (minutes > 0 || hours > 0) {
      durationText += "${minutes}m ";
    }
    durationText += "${seconds}s";

    DateTime? startTime = start is Timestamp ? start.toDate() : null;

    DateTime? endTime = end is Timestamp ? end.toDate() : null;

    // ================= VIBRATION / HEAT LEVELS =================
    final vibrationStart = data["vibration_level"];
    final vibrationEnd = data["final_vibration_level"];
    final heatStart = data["heat_level"];
    final heatEnd = data["final_heat_level"];

    String vibrationText = vibrationStart == null
        ? "-"
        : vibrationEnd == null
            ? "$vibrationStart%"
            : "$vibrationStart% → $vibrationEnd%";

    String heatText = heatStart == null
        ? "-"
        : heatEnd == null
            ? "$heatStart°C"
            : "$heatStart°C → $heatEnd°C";

    return Dismissible(
      key: Key(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 20),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => deleteWithUndo(doc.id, data),

      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF1B154B),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Sleep Session Summary",
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),

            const SizedBox(height: 20),

            Text(
              durationText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            buildInfoRow(
              Icons.nightlight,
              "Start",
              startTime != null ? DateFormat('hh:mm a').format(startTime) : "-",
            ),

            buildInfoRow(
              Icons.wb_sunny,
              "End",
              endTime != null ? DateFormat('hh:mm a').format(endTime) : "-",
            ),

            buildInfoRow(Icons.vibration, "Vibration Level", vibrationText),

            buildInfoRow(Icons.thermostat, "Heat Level", heatText),
          ],
        ),
      ),
    );
  }

  // ================= TIMER CARD =================
  Widget buildTimerCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final duration = data["duration"] ?? 0;
    final start = data["set_time"]; // timer docs store start as "set_time"
    final end = data["end_time"];
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;

    String durationText = "";

    if (hours > 0) {
      durationText += "${hours}h ";
    }
    if (minutes > 0 || hours > 0) {
      durationText += "${minutes}m ";
    }
    durationText += "${seconds}s";

    DateTime? startTime = start is Timestamp ? start.toDate() : null;
    DateTime? endTime = end is Timestamp ? end.toDate() : null;

    // Timer levels don't change mid-run (slider is locked while running),
    // so there's just one value each — no start/end pair needed here.
    final vibrationLevel = data["vibration_level"];
    final heatLevel = data["heat_level"];

    final vibrationText = vibrationLevel == null ? "-" : "$vibrationLevel%";
    final heatText = heatLevel == null ? "-" : "$heatLevel°C";

    return Dismissible(
      key: Key(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 20),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => deleteWithUndo(doc.id, data),

      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF1B154B),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Timer Session",
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),

            const SizedBox(height: 15),

            Text(
              durationText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            buildInfoRow(
              Icons.nightlight,
              "Start",
              startTime != null ? DateFormat('hh:mm a').format(startTime) : "-",
            ),

            buildInfoRow(
              Icons.wb_sunny,
              "End",
              endTime != null ? DateFormat('hh:mm a').format(endTime) : "-",
            ),

            buildInfoRow(Icons.vibration, "Vibration Level", vibrationText),

            buildInfoRow(Icons.thermostat, "Heat Level", heatText),
          ],
        ),
      ),
    );
  }

  // ================= SLEEP CARD =================
  Widget buildSleepCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final start = data["sleep_start"];
    final end = data["sleep_end"];
    final duration = data["sleep_duration_minutes"] ?? 0;

    DateTime? startTime = start is Timestamp ? start.toDate() : null;

    DateTime? endTime = end is Timestamp ? end.toDate() : null;

    return Dismissible(
      key: Key(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 20),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => deleteWithUndo(doc.id, data),

      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF1B154B),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Sleep Session",
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),

            const SizedBox(height: 20),

            Text(
              "${duration ~/ 60}h ${duration % 60}m",
              style: const TextStyle(color: Colors.white, fontSize: 32),
            ),

            const SizedBox(height: 20),

            buildInfoRow(
              Icons.nightlight,
              "Start",
              startTime != null ? DateFormat('hh:mm a').format(startTime) : "-",
            ),

            buildInfoRow(
              Icons.wb_sunny,
              "End",
              endTime != null ? DateFormat('hh:mm a').format(endTime) : "-",
            ),
          ],
        ),
      ),
    );
  }

  Widget buildInfoRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyanAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: const TextStyle(color: Colors.white)),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ================= CALENDAR =================
class CalendarOverlay extends StatefulWidget {
  final Function(DateTime) onDateSelected;

  const CalendarOverlay({super.key, required this.onDateSelected});

  @override
  State<CalendarOverlay> createState() => _CalendarOverlayState();
}

class _CalendarOverlayState extends State<CalendarOverlay> {
  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;

  Map<DateTime, bool> hasRecordDates = {};

  @override
  void initState() {
    super.initState();
    loadRecordDates();
  }

  Future<void> loadRecordDates() async {
    final snapshot = await FirebaseFirestore.instance
        .collection("vibrator_logs")
        .get();

    Map<DateTime, bool> temp = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();

      Timestamp? ts = data["timestamp"];

      if (ts != null) {
        DateTime date = ts.toDate();

        DateTime cleanDate = DateTime(date.year, date.month, date.day);

        temp[cleanDate] = true;
      }

      Timestamp? sleepStart = data["sleep_start"];

      if (sleepStart != null) {
        DateTime date = sleepStart.toDate();

        DateTime cleanDate = DateTime(date.year, date.month, date.day);

        temp[cleanDate] = true;
      }
    }

    setState(() {
      hasRecordDates = temp;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.85,
      child: TableCalendar(
        firstDay: DateTime.utc(2020),
        lastDay: DateTime.utc(2035),
        focusedDay: focusedDay,
        selectedDayPredicate: (day) => isSameDay(selectedDay, day),
        onDaySelected: (selected, focused) {
          setState(() {
            selectedDay = selected;
            focusedDay = focused;
          });

          widget.onDateSelected(selected);

          Navigator.pop(context); // close calendar after select
        },
        calendarBuilders: CalendarBuilders(
          defaultBuilder: (context, day, focusedDay) {
            final cleanDay = DateTime(day.year, day.month, day.day);

            bool hasRecord = hasRecordDates[cleanDay] ?? false;

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${day.day}', style: const TextStyle(color: Colors.white)),

                const SizedBox(height: 2),

                if (hasRecord)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.cyanAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            );
          },
        ),

        calendarStyle: const CalendarStyle(
          defaultTextStyle: TextStyle(color: Colors.white),
          weekendTextStyle: TextStyle(color: Colors.cyanAccent),
          selectedDecoration: BoxDecoration(
            color: Colors.cyanAccent,
            shape: BoxShape.circle,
          ),
          todayDecoration: BoxDecoration(
            color: Colors.deepPurpleAccent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
