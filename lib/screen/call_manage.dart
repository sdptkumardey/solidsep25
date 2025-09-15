// call_manage.dart
import 'package:flutter/material.dart';
import 'app_drawer.dart';
import 'call_client_add.dart';   // Add/Edit screen (AddEditClientScreen)
import 'call_client_list.dart';  // ExistingClientScreen (the real one)

class CallManage extends StatefulWidget {
  static const String id = 'call_manage';

  const CallManage({super.key});

  @override
  State<CallManage> createState() => _CallManageState();
}

class _CallManageState extends State<CallManage> {
  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF104270);

    return SafeArea(
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          backgroundColor: brand,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Manage Calls', style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 520;

                  final children = <Widget>[
                    _BigActionCard(
                      icon: Icons.person_add_alt_1,
                      title: 'New Client',
                      subtitle: 'Create/log a new client call',
                      onTap: () {
                        // If your AddEditClientScreen defaults to "add" with no args, this is fine.
                        // Otherwise, pass: arguments: AddEditClientArgs.add()
                        Navigator.pushNamed(context, AddEditClientScreen.id);
                      },
                    ),
                    _BigActionCard(
                      icon: Icons.people_alt,
                      title: 'Existing Client',
                      subtitle: 'Search & manage existing client calls',
                      onTap: () {
                        // This resolves to the class defined in call_client_list.dart
                        Navigator.pushNamed(context, ExistingClientScreen.id);
                      },
                    ),
                  ];

                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: children[0]),
                        const SizedBox(width: 16),
                        Expanded(child: children[1]),
                      ],
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      children[0],
                      const SizedBox(height: 16),
                      children[1],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BigActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BigActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF104270);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: brand.withOpacity(0.25), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: brand.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: brand.withOpacity(0.15)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 36, color: brand),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}
