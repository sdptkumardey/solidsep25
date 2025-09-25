import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CallReportPage extends StatefulWidget {
  const CallReportPage({Key? key}) : super(key: key);

  @override
  State<CallReportPage> createState() => _CallReportPageState();
}

class _CallReportPageState extends State<CallReportPage> {
  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  bool isLoading = true;
  List<dynamic> msReport = [];
  List<dynamic> stageSummary = [];

  final DateFormat apiFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    fetchReport(); // load on init with today
  }

  Future<void> pickDate({required bool isFrom}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? fromDate : toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          fromDate = picked;
        } else {
          toDate = picked;
        }
      });
    }
  }

  Future<void> fetchReport() async {
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '7';
      final mob = prefs.getString('mob') ?? '8101282803';

      final response = await http.post(
        Uri.parse("https://solidply.in/native_app/call_report.php?subject=call&action=report"),
        body: {
          "user_id": userId,
          "mob": mob,
          "start_date": apiFormat.format(fromDate),
          "end_date": apiFormat.format(toDate),
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          msReport = data['ms_report'] ?? [];
          stageSummary = data['stage_summary'] ?? [];



          // Debug: print each stage with quotes to catch spaces
          for (var s in stageSummary) {
            debugPrint("Stage => '${s['stage']}' Count => ${s['count']}");
          }



          isLoading = false;
        });
      } else {
        throw Exception("Failed to load report");
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint("Error: $e");
    }
  }

  Widget buildStageSummary() {
    final colors = {
      "Company Introduction": Colors.blue,
      "Negotiation": Colors.orange,
      "Closure": Colors.green,
      "After Sale Meet": Colors.purple,
    };

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: stageSummary.map((item) {
          final stage = (item['stage'] ?? '').toString().trim();
          final count = item['count']?.toString() ?? '0';
          final color = colors[stage] ?? Colors.grey;

          return Container(
            width: (MediaQuery.of(context).size.width / 2) - 20, // 2 per row
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.bar_chart, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stage,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12, // smaller font
                          color: color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                      Text(
                        count,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }




  Widget buildCallCard(dynamic call, int index) {
    final fields = {
      "CALL NUM": call['call_num'],
      "DATE": call['call_entry_date'],
      "CLIENT TYPE": call['client_type'],
      "CLIENT NAME": call['party_name'],
      "CONTACT": call['party_mobile'],
      "CLIENT ADDRESS": call['party_address'],
      "CALL STAGE": call['det_call_stage'],
      "FOLLOWUP DATE": call['det_follow_up_date'],
      "REMARKS": call['det_remarks'],
      "PRICE OFFERED": call['det_offered_price'],
      "PRICE WANTED": call['det_wanted_price'],
      "DELIVERY DATE": call['det_delivery_date'],
      "PLACE OF SUPPLY": call['det_supply_place'],
      "PAYMENT POSITION": call['det_payment_pos'],
      "ESTIMATED PAYMENT DATE": call['det_payment_date'],
      "CLOSURE TYPE": call['det_closure_type'],
    };

    // Color for left border (cycle through)
    final borderColors = [Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.teal];
    final borderColor = borderColors[index % borderColors.length];

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: borderColor, width: 5),
            ),
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: fields.entries
                  .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
                  .map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${e.key}: ",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        e.value.toString(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ))
                  .toList(),
            ),
          ),
        ),
        // Badge
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Text(
              "${index + 1}",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Call Report", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF104270),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Date range with search
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => pickDate(isFrom: true),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text("From: ${apiFormat.format(fromDate)}"),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => pickDate(isFrom: false),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text("To: ${apiFormat.format(toDate)}"),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: fetchReport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF104270),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Search"),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
              child: Column(
                children: [
                  buildStageSummary(),
                  const SizedBox(height: 10),
                  ...msReport.asMap().entries.map((entry) {
                    final index = entry.key;
                    final call = entry.value;
                    return buildCallCard(call, index);
                  }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
