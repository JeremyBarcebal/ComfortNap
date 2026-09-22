import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class MonthlySleepScreen extends StatefulWidget {
  const MonthlySleepScreen({super.key});

  @override
  State<MonthlySleepScreen> createState() => _MonthlySleepScreenState();
}

class _MonthlySleepScreenState extends State<MonthlySleepScreen> {
  DateTime currentMonth = DateTime.now();

  bool isLoading = true;

  int totalSleep = 0;

  int totalSessions = 0;

  int bestSleep = 0;

  int shortestSleep = 999999;

  DateTime? bestDay;

  List<int> dailySleep = [];

  List<Map<String, dynamic>> sleepRecords = [];

  @override
  void initState() {
    super.initState();

    loadMonthlyData();
  }

  Future<void> loadMonthlyData() async {
    setState(() {
      isLoading = true;
    });

    DateTime monthStart = DateTime(currentMonth.year, currentMonth.month, 1);

    DateTime monthEnd = DateTime(currentMonth.year, currentMonth.month + 1, 1);

    final snapshot = await FirebaseFirestore.instance
        .collection("vibrator_logs")
        .where("sleep_start", isGreaterThanOrEqualTo: monthStart)
        .where("sleep_start", isLessThan: monthEnd)
        .orderBy("sleep_start")
        .get();

    int total = 0;

    int sessions = 0;

    int longest = 0;

    int shortest = 999999;

    DateTime? longestDay;

    int daysInMonth = DateTime(
      currentMonth.year,
      currentMonth.month + 1,
      0,
    ).day;

    List<int> chart = List.generate(daysInMonth, (_) => 0);

    List<Map<String, dynamic>> records = [];

    for (var doc in snapshot.docs) {
      final data = doc.data();

      int duration = data["sleep_duration_minutes"] ?? 0;

      Timestamp ts = data["sleep_start"];

      DateTime date = ts.toDate();

      total += duration;

      sessions++;

      if (duration > longest) {
        longest = duration;

        longestDay = date;
      }

      if (duration < shortest) {
        shortest = duration;
      }

      chart[date.day - 1] += duration;

      records.add({
        "date": date,
        "duration": duration,
        "start": data["sleep_start"],
        "end": data["sleep_end"],
      });
    }

    setState(() {
      totalSleep = total;

      totalSessions = sessions;

      bestSleep = longest;

      shortestSleep = shortest == 999999 ? 0 : shortest;

      bestDay = longestDay;

      dailySleep = chart;

      sleepRecords = records;

      isLoading = false;
    });
  }

  String formatMinutes(int minutes) {
    int h = minutes ~/ 60;

    int m = minutes % 60;

    return "${h}h ${m}m";
  }

  String formatTime(Timestamp? ts) {
    if (ts == null) return "-";

    return DateFormat("hh:mm a").format(ts.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07051F),
      body: SafeArea(
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              )
            : RefreshIndicator(
                color: Colors.cyanAccent,
                onRefresh: loadMonthlyData,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // ================= HEADER =================
                    Row(
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

                        const SizedBox(width: 15),

                        const Expanded(
                          child: Text(
                            "Monthly Sleep",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    // ================= MONTH =================
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () {
                            setState(() {
                              currentMonth = DateTime(
                                currentMonth.year,
                                currentMonth.month - 1,
                              );
                            });

                            loadMonthlyData();
                          },

                          icon: const Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                            size: 35,
                          ),
                        ),

                        Text(
                          DateFormat("MMMM yyyy").format(currentMonth),

                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        IconButton(
                          onPressed: () {
                            setState(() {
                              currentMonth = DateTime(
                                currentMonth.year,
                                currentMonth.month + 1,
                              );
                            });

                            loadMonthlyData();
                          },

                          icon: const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                            size: 35,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 25),

                    summaryCard(
                      "Total Sleep",
                      formatMinutes(totalSleep),
                      Icons.bed,
                      Colors.cyanAccent,
                    ),

                    const SizedBox(height: 15),

                    summaryCard(
                      "Average Sleep",
                      totalSessions == 0
                          ? "-"
                          : formatMinutes(totalSleep ~/ totalSessions),
                      Icons.hotel,
                      Colors.greenAccent,
                    ),

                    const SizedBox(height: 15),

                    summaryCard(
                      "Best Sleep",
                      bestDay == null
                          ? "-"
                          : "${DateFormat("MMM d").format(bestDay!)} (${formatMinutes(bestSleep)})",
                      Icons.star,
                      Colors.orangeAccent,
                    ),

                    const SizedBox(height: 15),

                    summaryCard(
                      "Shortest Sleep",
                      formatMinutes(shortestSleep),
                      Icons.schedule,
                      Colors.redAccent,
                    ),

                    const SizedBox(height: 15),

                    summaryCard(
                      "Total Sessions",
                      "$totalSessions",
                      Icons.nightlight,
                      Colors.purpleAccent,
                    ),

                    const SizedBox(height: 30),

                    const Text(
                      "Monthly Sleep Trend",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    buildBarChart(),

                    const SizedBox(height: 30),

                    const Text(
                      "Daily Sleep Records",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    if (sleepRecords.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(40),

                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.05),
                          borderRadius: BorderRadius.circular(20),
                        ),

                        child: const Center(
                          child: Text(
                            "No sleep records this month",
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                    else
                      ...sleepRecords.reversed.map(
                        (record) => buildSleepRecord(record),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(.2),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.white.withOpacity(.7)),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildBarChart() {
    if (dailySleep.isEmpty) {
      return const SizedBox();
    }

    return SizedBox(
      height: 260,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 35,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                getTitlesWidget: (value, meta) {
                  return Text(
                    "${value.toInt() + 1}",
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(
            dailySleep.length,
            (i) => BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: dailySleep[i] / 60,
                  width: 8,
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.cyanAccent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSleepRecord(Map<String, dynamic> record) {
    Timestamp? start = record["start"];
    Timestamp? end = record["end"];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat("MMMM d, yyyy").format(record["date"]),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            formatMinutes(record["duration"]),
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.bedtime, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                formatTime(start),
                style: const TextStyle(color: Colors.white),
              ),
              const Spacer(),
              const Icon(Icons.wb_sunny, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                formatTime(end),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
