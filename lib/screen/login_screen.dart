import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'home_screen.dart';
import 'package:solidplyaug25/globals.dart' as globals;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;
  bool _isIpSet = false;
  String _ip = '';

  Future<void> login() async {
    final mob = _mobController.text.trim();
    final password = _passwordController.text;
    if (mob.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter mobile & password')),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      final baseUrl = globals.ipAddress;
     final response = await http.post(
        Uri.parse(
          '$baseUrl/native_app/login.php?subject=login&action=chk',
        ),
        body: {'mob': mob, 'password': password},
      );
      final data = jsonDecode(response.body);
      if (data['status'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('name', data['name']);
        await prefs.setString('user_id', data['user_id'].toString());
        await prefs.setString('mob', mob.toString());
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) =>  HomeScreen()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid login')),
        );
      }
    } catch (e) {
      print('HTTP error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("images/bg-001.png"),
            fit: BoxFit.cover,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('images/solid-ply-logo.png', width: 240),
            const SizedBox(height: 40),
            const Text('LOGIN',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 30,
                    color: Color(0xFFcc4c99))),
            const SizedBox(height: 8),

              const Text('Enter Mobile Number And Password',
                  style: TextStyle(fontSize: 18, color: Color(0XFF7b1a4f))),
              const SizedBox(height: 20),
              TextField(
                controller: _mobController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile Number'),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 40),
              isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: login,
                  icon: const Icon(Icons.login, color: Colors.white, ),
                  label: const Text('Login', style: TextStyle(color: Colors.white),),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF600d41),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }
}


