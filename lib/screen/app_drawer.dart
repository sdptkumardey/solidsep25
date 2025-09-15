// app_drawer.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solidplyaug25/screen/download.dart';
import 'package:solidplyaug25/screen/home_screen.dart';
import 'login_screen.dart';
import 'check_out_screen.dart';
import 'attendance_service.dart'; // <-- added
import 'call_manage.dart';
import 'exp.dart';
import 'exp_app.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<Map<String, String>> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString('name') ?? '',
      'mob': prefs.getString('mob') ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: FutureBuilder<Map<String, String>>(
        future: _loadUser(),
        builder: (context, snapshot) {
          final name = snapshot.data?['name'] ?? '';
          final mob  = snapshot.data?['mob'] ?? '';

          return Column(
            children: [
              UserAccountsDrawerHeader(
                decoration: const BoxDecoration(color: Color(0xFF104270)),
                accountName: Text(name.isEmpty ? 'User' : name),
                accountEmail: Text(mob.isEmpty ? '' : mob),
                currentAccountPicture: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home, color: Colors.deepPurple),
                title: const Text('Home'),
                onTap: () {
                  Navigator.pushNamed(context, HomeScreen.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.call, color: Colors.green),
                title: const Text('Manage Calls'),
                onTap: () {
                      Navigator.pushNamed(context, CallManage.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.blue),
                title: const Text('Post Expense'),
                onTap: () {
                  Navigator.pushNamed(context, Exp.id);
                  // TODO: Navigate to Post Expense
                },
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.blue),
                title: const Text('Expense Approval'),
                onTap: () {
                  Navigator.pushNamed(context, ExpApp.id);
                  // TODO: Navigate to Post Expense
                },
              ),


              ListTile(
                leading: const Icon(Icons.download, color: Colors.blue),
                title: const Text('Downloads'),
                onTap: () {
                  Navigator.pushNamed(context, Download.id);
                  // TODO: Navigate to Post Expense
                },
              ),


              // Show "Check Out" ONLY if today's check-in is already done
              FutureBuilder<bool>(
                future: AttendanceService.instance.isTodayPending(),
                builder: (context, snap) {
                  final pending = snap.data ?? true; // default hide while loading
                  if (pending) return const SizedBox.shrink();
                  return ListTile(
                    leading: const Icon(Icons.logout, color: Colors.indigo),
                    title: const Text('Check Out'),
                    onTap: () async {
                      Navigator.pop(context); // close drawer
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CheckOutScreen()),
                      );
                      // No callback needed; your page can refresh via RouteObserver/didPopNext or similar.
                    },
                  );
                },
              ),

              const Divider(),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                title: const Text('LogOut'),
                onTap: () async {
                  Navigator.pop(context); // close the drawer
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('isLoggedIn');
                  await prefs.remove('name');
                  await prefs.remove('user_id');
                  await prefs.remove('mob');

                  // remove attendance cache (so next login re-checks server)
                  await prefs.remove('att_date');
                  await prefs.remove('att_done');
                  await prefs.remove('att_uid'); // in case you add Option B below
                  await prefs.remove('out_date');
                  await prefs.remove('out_done');
                  await prefs.remove('out_send_date_time');
                  await prefs.remove('out_lat');
                  await prefs.remove('out_lon');
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
