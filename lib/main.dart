import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app/theme.dart';
import 'screens/ask_screen.dart';
import 'screens/guide_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'services/detector_service.dart';
import 'services/history_service.dart';
import 'services/settings_service.dart';
import 'services/time_service.dart';
import 'services/waste_advisor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final settings = SettingsService();
  final time = TimeService();
  final history = HistoryService(time);
  final detector = DetectorService();
  await Future.wait([settings.load(), history.load()]);
  detector.scoreThreshold = settings.confidence;
  final advisor = await WasteAdvisor.load();

  // Network work happens in the background; the app is usable offline.
  time.sync();
  detector.load(useGpu: settings.useGpu);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: time),
      ChangeNotifierProvider.value(value: history),
      ChangeNotifierProvider.value(value: detector),
      Provider.value(value: advisor),
    ],
    child: const EcoSortApp(),
  ));
}

class EcoSortApp extends StatelessWidget {
  const EcoSortApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoSort',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenAsk: () => setState(() => _index = 1)),
      const AskScreen(),
      const HistoryScreen(),
      const GuideScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum_rounded), label: 'Ask'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'History'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'Guide'),
        ],
      ),
    );
  }
}
