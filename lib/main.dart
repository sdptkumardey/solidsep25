import 'package:flutter/material.dart';
import 'package:solidplyaug25/screen/route_observer.dart';
import 'screen/home_screen.dart';
import 'screen/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screen/route_observer.dart'; // <-- import the file above
import 'screen/call_manage.dart';
import 'screen/call_client_add.dart';
import 'screen/call_client_existing.dart';
import 'screen/call_client_list.dart';
import 'screen/call_client_det.dart';
import 'screen/call_client_select_stage.dart';
import 'screen/call_client_company_introduction.dart';
import 'screen/call_client_negotiation.dart';
import 'screen/call_client_closure.dart';
import 'screen/call_client_after_sale_meet.dart';
import 'screen/call_stage_args.dart';
import 'screen/exp.dart';
import 'screen/exp_app.dart';
import 'screen/download.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();


  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solid Ply',
      debugShowCheckedModeBanner: false,
      home: const StartupPage(),
      navigatorObservers: [routeObserver], // <-- add this line
      theme: ThemeData(
        fontFamily: "Roboto", // 👈 Default font for the whole app
      ),
 routes: {
   HomeScreen.id:(context)=>HomeScreen(),
   CallManage.id:(context)=>CallManage(),
   AddEditClientScreen.id:(context)=>AddEditClientScreen(),
   CallClientExisting.id:(context)=>CallClientExisting(),
   ExistingClientScreen.id:(context)=>ExistingClientScreen(),
   ClientDetailScreen.id:(context)=>ClientDetailScreen(),
   CallClientSelectStageScreen.id: (_) => const CallClientSelectStageScreen(),
   CompanyIntroductionScreen.id: (_) => const CompanyIntroductionScreen(),
   NegotiationScreen.id: (_) => const NegotiationScreen(),
   ClosureScreen.id: (_) => const ClosureScreen(),
   AfterSaleMeetScreen.id: (_) => const AfterSaleMeetScreen(),
   Exp.id: (_) => Exp(),
   ExpApp.id: (_) => ExpApp(),
   Download.id: (_) => Download(),
 },
    );
  }
}


class StartupPage extends StatefulWidget {
  const StartupPage({super.key});
  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('isLoggedIn') ?? false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
            loggedIn ? HomeScreen() : const LoginScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}