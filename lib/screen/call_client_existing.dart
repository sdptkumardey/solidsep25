import 'package:flutter/material.dart';
import 'app_drawer.dart';
class CallClientExisting extends StatefulWidget {
  static const String id = 'call_client_existing';
  @override
  State<CallClientExisting> createState() => _CallClientExistingState();
}

class _CallClientExistingState extends State<CallClientExisting> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(child: Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF104270),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('View Existing Client', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Text('View Existing Client...'),
      ),
    ));
  }
}
