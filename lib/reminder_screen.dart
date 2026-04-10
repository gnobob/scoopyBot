import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

enum ReminderMode { timeBased, afterLastClean }

class ReminderScreen extends StatefulWidget {
  const ReminderScreen({super.key});

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  // ── AudioPlayer lives IN the widget — same pattern as fishwell & monitoring ─
  final AudioPlayer player = AudioPlayer();

  static const String _cleaningTargetKey = 'cleaning_target_time';
  static const String _lastCleanedKey = 'last_cleaned_time';
  static const String _reminderModeKey = 'reminder_mode';

  DateTime? _lastCleaned;
  String _lastCleanedLabel = 'No record yet';

  int _selectedHours = 0;
  int _selectedMinutes = 1;
  bool _reminderActive = false;
  DateTime? _reminderTarget;
  String _countdownLabel = '';
  bool _hasChangedTime = false;
  bool _alarmFired = false;
  bool _stateLoaded = false;
  ReminderMode _selectedMode = ReminderMode.timeBased;
  ReminderMode _activeMode = ReminderMode.timeBased;

  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.requestPermissions();
    _loadSavedState();
    // Fires every second — countdown display + alarm trigger
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    player.dispose();
    super.dispose();
  }

  // ── Load saved reminder from SharedPrefs on startup ────────────────────────
  Future<void> _loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    final targetStr = prefs.getString(_cleaningTargetKey);
    final lastStr = prefs.getString(_lastCleanedKey);
    final modeStr = prefs.getString(_reminderModeKey);

    DateTime? target;
    if (targetStr != null) {
      target = DateTime.tryParse(targetStr);
      if (target != null && target.isBefore(DateTime.now())) {
        await prefs.remove(_cleaningTargetKey);
        target = null;
      }
    }

    DateTime? lastCleaned;
    if (lastStr != null) lastCleaned = DateTime.tryParse(lastStr);
    final ReminderMode mode = modeStr == 'after_last_clean'
        ? ReminderMode.afterLastClean
        : ReminderMode.timeBased;

    if (!mounted) return;
    setState(() {
      _reminderTarget = target;
      _reminderActive = target != null;
      _lastCleaned = lastCleaned;
      _selectedMode = mode;
      _activeMode = mode;
      _stateLoaded = true;
    });
    _refreshLastCleanedLabel();
  }

  // ── Fires every second ─────────────────────────────────────────────────────
  void _tick() {
    if (!mounted || !_stateLoaded) return;

    _refreshLastCleanedLabel();

    if (!_reminderActive || _reminderTarget == null) return;

    final remaining = _reminderTarget!.difference(DateTime.now());

    if (remaining.isNegative) {
      if (!_alarmFired) {
        _alarmFired = true;
        debugPrint('⏰ ALARM FIRED');
        player.play(AssetSource('alarmsound.mp3')); // fire and forget — 1 line
        final bool isAfterLastClean =
            _activeMode == ReminderMode.afterLastClean;
        NotificationService.instance.showAlarmNotification(
          title: 'Reminder',
          body: isAfterLastClean
              ? 'It has been 24 hours since the last cleaning.'
              : 'Time to clean pet waste.',
          payload: isAfterLastClean
              ? 'after_last_clean_reminder'
              : 'time_based_reminder',
        );
        _clearSavedTarget();
      }
      if (mounted) {
        setState(() {
          _reminderActive = false;
          _reminderTarget = null;
          _countdownLabel = '';
          _alarmFired = false;
        });
      }
    } else {
      final h = remaining.inHours;
      final m = remaining.inMinutes % 60;
      final s = remaining.inSeconds % 60;
      if (mounted) {
        setState(() {
          _countdownLabel = h > 0
              ? '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s'
              : '${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
        });
      }
    }
  }

  void _refreshLastCleanedLabel() {
    if (_lastCleaned == null) return;
    final diff = DateTime.now().difference(_lastCleaned!);
    final label = diff.inMinutes < 1
        ? 'Just now'
        : diff.inHours < 1
        ? '${diff.inMinutes} min ago'
        : diff.inMinutes % 60 > 0
        ? '${diff.inHours}h ${diff.inMinutes % 60}m ago'
        : '${diff.inHours}h ago';
    if (mounted) setState(() => _lastCleanedLabel = label);
  }

  Future<void> _setReminder() async {
    final prefs = await SharedPreferences.getInstance();
    DateTime target;

    if (_selectedMode == ReminderMode.timeBased) {
      final now = DateTime.now();
      target = DateTime(
        now.year,
        now.month,
        now.day,
        _selectedHours,
        _selectedMinutes,
      );
      if (!target.isAfter(now)) {
        target = target.add(const Duration(days: 1));
      }
      await NotificationService.instance.scheduleTimeBasedReminder(target);
      await prefs.setString(_reminderModeKey, 'time_based');
    } else {
      if (_lastCleaned == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mark cleaned first to use this reminder mode.'),
          ),
        );
        return;
      }
      target = _lastCleaned!.add(const Duration(hours: 24));
      await NotificationService.instance.scheduleAfterLastCleanReminder(
        _lastCleaned!,
      );
      await prefs.setString(_reminderModeKey, 'after_last_clean');
    }

    await prefs.setString(_cleaningTargetKey, target.toIso8601String());

    setState(() {
      _reminderTarget = target;
      _reminderActive = true;
      _alarmFired = false;
      _hasChangedTime = false;
      _activeMode = _selectedMode;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedMode == ReminderMode.timeBased
                ? '⏰ Reminder set for ${_pad(_selectedHours)}:${_pad(_selectedMinutes)}.'
                : '⏰ Reminder set for 24h after last cleaning.',
          ),
          backgroundColor: Colors.blueAccent,
        ),
      );
    }
  }

  Future<void> _cancelReminder() async {
    await NotificationService.instance.cancelAlarm(); // cancel OS alarm too
    await _clearSavedTarget();
    setState(() {
      _reminderActive = false;
      _reminderTarget = null;
      _countdownLabel = '';
      _hasChangedTime = false;
      _alarmFired = false;
    });
  }

  Future<void> _clearSavedTarget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cleaningTargetKey);
    await prefs.remove(_reminderModeKey);
  }

  Future<void> _markCleaned() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(_lastCleanedKey, now.toIso8601String());
    setState(() => _lastCleaned = now);
    _refreshLastCleanedLabel();
    if (_reminderActive && _activeMode == ReminderMode.afterLastClean) {
      final target = now.add(const Duration(hours: 24));
      await NotificationService.instance.scheduleAfterLastCleanReminder(now);
      await prefs.setString(_cleaningTargetKey, target.toIso8601String());
      if (mounted) setState(() => _reminderTarget = target);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Cleaning recorded!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF0A0E21),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            bottom: 8,
          ),
          child: const Center(
            child: Text(
              'REMINDERS & STATUS',
              style: TextStyle(
                fontSize: 14,
                letterSpacing: 2,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        if (!_stateLoaded)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                children: [
                  // ── LAST CLEANED ─────────────────────────────────────────────
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.cleaning_services,
                              color: Colors.greenAccent,
                              size: 24,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'LAST CLEANED',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _lastCleanedLabel,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_lastCleaned != null)
                                  Text(
                                    _formatDate(_lastCleaned!),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                            _smallBtn(
                              'MARK CLEANED',
                              Colors.greenAccent,
                              _markCleaned,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── CLEANING REMINDER ─────────────────────────────────────────
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.alarm,
                              color: Colors.blueAccent,
                              size: 24,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'CLEANING REMINDER',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Choose reminder type and schedule.',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Time-Based Reminder'),
                              selected: _selectedMode == ReminderMode.timeBased,
                              onSelected: (selected) {
                                if (!selected) return;
                                setState(() {
                                  _selectedMode = ReminderMode.timeBased;
                                  _hasChangedTime = true;
                                });
                              },
                            ),
                            ChoiceChip(
                              label: const Text('After Last Clean (24h)'),
                              selected:
                                  _selectedMode == ReminderMode.afterLastClean,
                              onSelected: (selected) {
                                if (!selected) return;
                                setState(() {
                                  _selectedMode = ReminderMode.afterLastClean;
                                  _hasChangedTime = true;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        if (_selectedMode == ReminderMode.timeBased)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _timePicker(
                                label: 'Hour',
                                value: _selectedHours,
                                max: 23,
                                onChanged: (v) => setState(() {
                                  _selectedHours = v;
                                  _hasChangedTime = true;
                                }),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  ':',
                                  style: TextStyle(
                                    fontSize: 30,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              _timePicker(
                                label: 'Min',
                                value: _selectedMinutes,
                                max: 59,
                                onChanged: (v) => setState(() {
                                  _selectedMinutes = v;
                                  _hasChangedTime = true;
                                }),
                              ),
                            ],
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withAlpha(15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.blueAccent.withAlpha(80),
                              ),
                            ),
                            child: const Text(
                              'Reminder will fire 24 hours after the recorded last cleaning time.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _hasChangedTime || !_reminderActive
                                ? _setReminder
                                : null,
                            icon: const Icon(
                              Icons.notifications_active_outlined,
                            ),
                            label: Text(
                              _reminderActive && !_hasChangedTime
                                  ? 'REMINDER SET ✓'
                                  : 'SET REMINDER',
                              style: const TextStyle(
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _reminderActive && !_hasChangedTime
                                  ? Colors.blueAccent.withAlpha(60)
                                  : Colors.blueAccent,
                              foregroundColor:
                                  _reminderActive && !_hasChangedTime
                                  ? Colors.blueAccent
                                  : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: _reminderActive && !_hasChangedTime
                                  ? const BorderSide(color: Colors.blueAccent)
                                  : BorderSide.none,
                            ),
                          ),
                        ),

                        if (_reminderActive && _reminderTarget != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.blueAccent.withAlpha(80),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.timer_outlined,
                                        color: Colors.blueAccent,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Time remaining',
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 10,
                                            ),
                                          ),
                                          Text(
                                            _countdownLabel,
                                            style: const TextStyle(
                                              color: Colors.blueAccent,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: _cancelReminder,
                                    child: const Icon(
                                      Icons.cancel_outlined,
                                      color: Colors.redAccent,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionCard({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF1D1E33),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white10),
    ),
    child: child,
  );

  Widget _smallBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(120)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );

  Widget _timePicker({
    required String label,
    required int value,
    required int max,
    required ValueChanged<int> onChanged,
  }) => Column(
    children: [
      IconButton(
        icon: const Icon(
          Icons.keyboard_arrow_up_rounded,
          color: Colors.blueAccent,
          size: 32,
        ),
        onPressed: () => onChanged(value < max ? value + 1 : 0),
      ),
      Container(
        width: 70,
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.blueAccent.withAlpha(20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.blueAccent.withAlpha(100)),
        ),
        child: Text(
          value.toString().padLeft(2, '0'),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      IconButton(
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.blueAccent,
          size: 32,
        ),
        onPressed: () => onChanged(value > 0 ? value - 1 : max),
      ),
      Text(
        label,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );

  String _formatDate(DateTime dt) {
    final mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${mo[dt.month - 1]} ${dt.day}, ${dt.year}  '
        '${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
