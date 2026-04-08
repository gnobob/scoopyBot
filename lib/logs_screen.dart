import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // AppBar-style header
        Container(
          color: const Color(0xFF0A0E21),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 8,
            bottom: 8,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "ROBOT ACTIVITY LOGS",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_today, color: Colors.white),
                onPressed: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2025),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseHelper.instance.fetchLogsByDate(_selectedDate),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final logs = snapshot.data!;
              if (logs.isEmpty) {
                return const Center(child: Text("No records found for this date.", style: TextStyle(color: Colors.white70)));
              }

              return ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  final DateTime time = DateTime.parse(log['time']);

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D1E33),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: log['image'] != null
                              ? Image.memory(log['image'], width: 100, height: 75, fit: BoxFit.cover)
                              : Container(width: 100, height: 75, color: Colors.black, child: const Icon(Icons.broken_image)),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log['status'],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: log['status'].contains("ON") ? Colors.greenAccent : Colors.orangeAccent,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                DateFormat('MMMM dd, yyyy').format(time),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              Text(
                                DateFormat('hh:mm:ss a').format(time),
                                style: const TextStyle(fontSize: 14, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}