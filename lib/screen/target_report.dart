import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class TargetReportPage extends StatefulWidget {
  const TargetReportPage({Key? key}) : super(key: key);

  @override
  State<TargetReportPage> createState() => _TargetReportPageState();
}

class _TargetReportPageState extends State<TargetReportPage> {
  List<dynamic> incentives = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchTargetReport();
  }

  Future<void> fetchTargetReport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      final mob = prefs.getString('mob') ?? '';

      final response = await http.post(
        Uri.parse("https://solidply.in/native_app/target_report.php?subject=target&action=report"),
        body: {"user_id": userId, "mob": mob},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          incentives = data['ms_incentive'] ?? [];
          isLoading = false;
        });
      } else {
        throw Exception("Failed to load data");
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      debugPrint("Error fetching data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            "Target Report",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: const Color(0xFF104270),
          iconTheme: const IconThemeData(
            color: Colors.white,
          ),
        ),

        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : incentives.isEmpty
            ? const Center(child: Text("No records found"))
            : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: incentives.length,
          itemBuilder: (context, index) {
            final item = incentives[index];

            double targetNa = double.tryParse(item['target_na'].toString()) ?? 0;
            double targetTon = double.tryParse(item['target_ton'].toString()) ?? 0;
            double achievedNa = double.tryParse(item['target_achieve_na'].toString()) ?? 0;
            double achievedTon = double.tryParse(item['target_achive_ton'].toString()) ?? 0;

            double pendingNa = targetNa - achievedNa;
            double pendingTon = targetTon - achievedTon;

            double incentive = double.tryParse(item['incentive'].toString()) ?? 0;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['month_label'] ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF104270),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Row of Target / Achieved / Pending
                    Row(
                      children: [
                        Expanded(
                          child: _InfoCard(
                            icon: Icons.flag,
                            color: Colors.blue,
                            title: "Target",
                            ton: targetTon.toStringAsFixed(2),
                            na: targetNa.toStringAsFixed(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InfoCard(
                            icon: Icons.check_circle,
                            color: Colors.green,
                            title: "Achieved",
                            ton: achievedTon.toStringAsFixed(2),
                            na: achievedNa.toStringAsFixed(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _InfoCard(
                            icon: Icons.pending,
                            color: Colors.orange,
                            title: "Pending",
                            ton: pendingTon.toStringAsFixed(2),
                            na: pendingNa.toStringAsFixed(2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Incentive box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet,
                              color: Colors.purple, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Incentive: ${incentive.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String ton;
  final String na;
  final Color color;

  const _InfoCard({
    Key? key,
    required this.icon,
    required this.title,
    required this.ton,
    required this.na,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            "Ton - $ton",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          Text(
            "NA - $na",
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
