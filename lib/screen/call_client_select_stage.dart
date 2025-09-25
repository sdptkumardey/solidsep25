// call_client_select_stage.dart
import 'package:flutter/material.dart';
import 'call_stage_args.dart';
import 'call_client_company_introduction.dart';
import 'call_client_negotiation.dart';
import 'call_client_closure.dart';
import 'call_client_after_sale_meet.dart';

class CallClientSelectStageArgs {
  final int clientId;
  final String? clientName;
  const CallClientSelectStageArgs({required this.clientId, this.clientName});
}

class CallClientSelectStageScreen extends StatefulWidget {
  static const String id = 'call_client_select_stage';

  const CallClientSelectStageScreen({super.key});

  @override
  State<CallClientSelectStageScreen> createState() => _CallClientSelectStageScreenState();
}

class _CallClientSelectStageScreenState extends State<CallClientSelectStageScreen> {
  bool _didInit = false;
  late CallClientSelectStageArgs _args;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;

    final a = ModalRoute.of(context)?.settings.arguments;
    if (a is CallClientSelectStageArgs) {
      _args = a;
    } else {
      // Fallback so you don't crash if args missing
      _args = const CallClientSelectStageArgs(clientId: 0, clientName: '');
    }
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF104270);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: brand,
        title: const Text('Select Call Stage', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final isWide = c.maxWidth > 600;
                  final tiles = <Widget>[
                    _StageCard(
                      color: const Color(0xFF2962FF),
                      icon: Icons.apartment_rounded,
                      title: 'Company Introduction',
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          CompanyIntroductionScreen.id,
                          arguments: CallStageArgs(
                            clientId: _args.clientId,
                            clientName: _args.clientName,
                          ),
                        );
                      },
                    ),
                    _StageCard(
                      color: const Color(0xFFFF6D00),
                      icon: Icons.handshake_rounded,
                      title: 'Negotiation',
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          NegotiationScreen.id,
                          arguments: CallStageArgs(
                            clientId: _args.clientId,
                            clientName: _args.clientName,
                          ),
                        );
                      },
                    ),
                    _StageCard(
                      color: const Color(0xFF00C853),
                      icon: Icons.verified_rounded,
                      title: 'Closure',
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          ClosureScreen.id,
                          arguments: CallStageArgs(
                            clientId: _args.clientId,
                            clientName: _args.clientName,
                          ),
                        );
                      },
                    ),
                    _StageCard(
                      color: const Color(0xFFAA00FF),
                      icon: Icons.support_agent_rounded,
                      title: 'After Sale Meet',
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          AfterSaleMeetScreen.id,
                          arguments: CallStageArgs(
                            clientId: _args.clientId,
                            clientName: _args.clientName,
                          ),
                        );
                      },
                    ),
                  ];

                  if (isWide) {
                    return GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.9,
                      children: tiles,
                    );
                  }
                  return ListView.separated(
                    itemCount: tiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (_, i) => tiles[i],
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

class _StageCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _StageCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color.withOpacity(0.08);
    final border = color.withOpacity(0.22);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 38, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color.withOpacity(0.95),
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: color.withOpacity(0.9)),
          ],
        ),
      ),
    );
  }
}
