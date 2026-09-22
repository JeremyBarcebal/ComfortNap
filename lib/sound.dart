import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class SoundScreen extends StatefulWidget {
  const SoundScreen({super.key});

  @override
  State<SoundScreen> createState() => _SoundScreenState();
}

class _SoundScreenState extends State<SoundScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isDisposed = false; // Track if widget is disposed
  String? selectedSound;
  String? selectedFile;
  bool isPlaying = false;

  final List<Map<String, dynamic>> sounds = [
    {"icon": Icons.cloud, "label": "Rain", "file": "calming-rain-257596.mp3"},
    {
      "icon": Icons.ac_unit,
      "label": "Snow",
      "file": "sledding-on-snow-sliding-on-snow-snow-and-sledding-16590.mp3",
    },
    {
      "icon": Icons.nightlight_round,
      "label": "Owl",
      "file": "scops-owl-57475.mp3",
    },
    {
      "icon": Icons.filter_vintage,
      "label": "Bird",
      "file": "bird-chipping-426107.mp3",
    },
    {
      "icon": Icons.local_fire_department,
      "label": "Fire",
      "file": "crackle-fireplace-campfire-402289.mp3",
    },
    {
      "icon": Icons.bedtime,
      "label": "Night",
      "file": "night-ambience-17064.mp3",
    },
    {
      "icon": Icons.waves,
      "label": "Ocean",
      "file": "ocean-waves-crashing-the-shoreline-423649.mp3",
    },
    {
      "icon": Icons.air,
      "label": "Wind",
      "file": "wind-blowing-sfx-01-423673.mp3",
    },
    {"icon": Icons.chair, "label": "Swing", "file": "swing-squeak-73201.mp3"},
  ];

  Future<void> playSound(String fileName) async {
    try {
      // Stop any currently playing sound
      await _audioPlayer.stop();

      // If widget disposed in the meantime, exit
      if (_isDisposed) return;

      // Play new sound
      await _audioPlayer.play(AssetSource('sounds/$fileName'));
    } catch (e) {
      print("⚠️ Error playing sound: $e");
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0530),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1B48),
        elevation: 0,
        title: const Text(
          "Sleep Sounds",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Expanded(
                child: GridView.builder(
                  itemCount: sounds.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                  ),
                  itemBuilder: (context, index) {
                    final sound = sounds[index];
                    return GestureDetector(
                      onTap: () async {
                        // Stop previous sound and play new one safely
                        await playSound(sound['file']);

                        // Return selected sound to main screen
                        setState(() {
                          selectedSound = sound['label'];
                          selectedFile = sound['file'];
                          isPlaying = true;
                        });

                        // Optional: show snackbar
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Playing ${sound['label']}"),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade800,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(sound["icon"], color: Colors.white, size: 40),
                            const SizedBox(height: 10),
                            Text(
                              sound["label"],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // MINI PLAYER
              if (selectedSound != null)
                Container(
                  margin: const EdgeInsets.only(top: 15),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade900,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note, color: Colors.white),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          selectedSound!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        onPressed: () async {
                          if (isPlaying) {
                            await _audioPlayer.pause();
                          } else {
                            await _audioPlayer.resume();
                          }

                          setState(() {
                            isPlaying = !isPlaying;
                          });
                        },
                      ),

                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, {
                            'label': selectedSound,
                            'file': selectedFile,
                          });
                        },
                        child: const Text("Use"),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
