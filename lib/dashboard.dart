import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:screenshot/screenshot.dart';
import 'database_helper.dart';
import 'logs_screen.dart';
import 'reminder_screen.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late final WebViewController _controller;
  final ScreenshotController screenshotController = ScreenshotController();

  bool isCameraConnected = false;
  bool isFlashOn = false;
  bool isVacuumOn = false;
  String lastStatus = "System Ready";
  int _selectedIndex = 0;

  Timer? _autoLogTimer;
  Timer? _movementTimer;
  int _timerCounter = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            _controller.runJavaScript("""
              document.body.style.margin = '0';
              document.body.style.padding = '0';
              document.body.style.display = 'flex';
              document.body.style.justifyContent = 'center';
              document.body.style.alignItems = 'center';
              document.body.style.backgroundColor = 'black';
              var img = document.getElementsByTagName('img')[0];
              if (img) {
                img.style.width = '100%';
                img.style.height = '100%';
                img.style.objectFit = 'contain';
              }
            """);
          },
        ),
      )
      ..loadRequest(Uri.parse('http://192.168.4.1:81/stream'));

    _startLoggingTimer();
  }

  @override
  void dispose() {
    _autoLogTimer?.cancel();
    _movementTimer?.cancel();
    super.dispose();
  }

  // ── CONTINUOUS MOVEMENT ────────────────────────────────────────────────────

  void _startMovement(String cmd) {
    sendCommand(cmd);
    _movementTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      sendCommand(cmd);
    });
  }

  void _stopMovement() {
    _movementTimer?.cancel();
    sendCommand("S");
  }

  // ── AUTO LOGGING ───────────────────────────────────────────────────────────

  void _startLoggingTimer() {
    _autoLogTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _timerCounter++;

      if (isVacuumOn && _timerCounter >= 10) {
        _captureScreenshot("VACUUM ON");
        _timerCounter = 0;
      } else if (isCameraConnected && _timerCounter >= 30) {
        _captureScreenshot("VACUUM OFF");
        _timerCounter = 0;
      }
    });
  }

  Future<void> _captureScreenshot(String vacuumStatus) async {
    try {
      final Uint8List? image = await screenshotController.capture();
      if (image != null) {
        await DatabaseHelper.instance.insertLog(vacuumStatus, image);
      }
    } catch (e) {
      debugPrint("Screenshot failed: $e");
    }
  }

  Future<void> sendCommand(String cmd) async {
    final String url = "http://192.168.4.1/state?cmd=$cmd";
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(milliseconds: 500));
      if (response.statusCode == 200) {
        setState(() => lastStatus = "Sent: $cmd");
      }
    } catch (e) {
      setState(() => lastStatus = "Offline");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildControlInterface(),
      const LogsScreen(),
      const ReminderScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: _selectedIndex == 0
          ? AppBar(
              title: const Text(
                "SCOOPY CONTROL",
                style: TextStyle(
                  fontSize: 16,
                  letterSpacing: 2,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              actions: [
                // Status badge
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.blueAccent.withAlpha(75)),
                      ),
                      child: Text(
                        lastStatus,
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1D1E33),
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_remote), label: "HOME"),
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long), label: "LOGS"),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications), label: "REMINDERS"),
        ],
      ),
    );
  }

  // ── CONTROL INTERFACE ──────────────────────────────────────────────────────

  Widget _buildControlInterface() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildCameraFeed(),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Row(
              children: [
                Expanded(
                    child: _buildGlassToggle(
                        "CAM", Icons.videocam, isCameraConnected, (v) {
                  setState(() {
                    isCameraConnected = v ?? false;
                    _timerCounter = 0;
                  });
                })),
                const SizedBox(width: 15),
                Expanded(
                    child: _buildGlassToggle(
                        "FLASH", Icons.flashlight_on, isFlashOn, (v) {
                  setState(() => isFlashOn = v ?? false);
                  sendCommand(isFlashOn ? "W" : "w");
                })),
              ],
            ),
          ),
          const Divider(
              color: Colors.white10, height: 40, indent: 40, endIndent: 40),
          _buildSpecialtyControls(),
          const SizedBox(height: 20),
          _buildModernDPad(),
        ],
      ),
    );
  }

  Widget _buildCameraFeed() {
    return Screenshot(
      controller: screenshotController,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        height: 220,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: isCameraConnected
                  ? Colors.blueAccent.withAlpha(38)
                  : Colors.black,
              blurRadius: 20,
              spreadRadius: 5,
            )
          ],
          border: Border.all(
            color: isCameraConnected
                ? Colors.blueAccent.withAlpha(127)
                : Colors.white10,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: isCameraConnected
              ? WebViewWidget(controller: _controller)
              : const Center(
                  child:
                      Icon(Icons.videocam_off, color: Colors.white12, size: 60)),
        ),
      ),
    );
  }

  Widget _buildSpecialtyControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _miniControlBtn(Icons.arrow_circle_down_outlined, "G", "TILT DOWN"),
        const SizedBox(width: 30),
        _buildVacuumButton(),
        const SizedBox(width: 30),
        _miniControlBtn(Icons.arrow_circle_up_outlined, "H", "TILT UP"),
      ],
    );
  }

  Widget _buildVacuumButton() {
    return Column(
      children: [
        GestureDetector(
          onTap: () async {
            setState(() {
              isVacuumOn = !isVacuumOn;
              _timerCounter = 0;
            });
            sendCommand("Z");
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: isVacuumOn
                    ? [Colors.redAccent, const Color(0xFF660000)]
                    : [Colors.greenAccent, const Color(0xFF003300)],
                center: const Alignment(-0.2, -0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: isVacuumOn
                      ? Colors.redAccent.withAlpha(102)
                      : Colors.greenAccent.withAlpha(102),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Icon(
              isVacuumOn ? Icons.power_settings_new : Icons.cleaning_services,
              color: Colors.white,
              size: 35,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "VACUUM",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isVacuumOn ? Colors.redAccent : Colors.greenAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildModernDPad() {
    return Column(
      children: [
        _modernMoveBtn(Icons.keyboard_arrow_up_rounded, "F"),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _modernMoveBtn(Icons.keyboard_arrow_left_rounded, "L"),
            const SizedBox(width: 70),
            _modernMoveBtn(Icons.keyboard_arrow_right_rounded, "R"),
          ],
        ),
        _modernMoveBtn(Icons.keyboard_arrow_down_rounded, "B"),
      ],
    );
  }

  Widget _modernMoveBtn(IconData icon, String cmd) {
    return GestureDetector(
      onTapDown: (_) => _startMovement(cmd),
      onTapUp: (_) => _stopMovement(),
      onTapCancel: () => _stopMovement(),
      child: Container(
        margin: const EdgeInsets.all(8),
        width: 75,
        height: 75,
        decoration: BoxDecoration(
          color: Colors.blueAccent.withAlpha(12),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: Colors.blueAccent.withAlpha(76), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(76),
                blurRadius: 8,
                offset: const Offset(0, 4))
          ],
        ),
        child: Icon(icon, color: Colors.blueAccent, size: 45),
      ),
    );
  }

  Widget _buildGlassToggle(
      String label, IconData icon, bool val, Function(bool?) onChg) {
    return InkWell(
      onTap: () => onChg(!val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color:
              val ? Colors.blueAccent.withAlpha(38) : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: val ? Colors.blueAccent : Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: val ? Colors.blueAccent : Colors.grey, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: val ? Colors.blueAccent : Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniControlBtn(IconData icon, String cmd, String label) {
    return Column(
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.orangeAccent.withAlpha(204), size: 32),
          onPressed: () => sendCommand(cmd),
        ),
        Text(label,
            style: const TextStyle(
                fontSize: 8,
                color: Colors.grey,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}