import 'package:flutter/material.dart';
import 'package:warm_alarm/warm_alarm.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _readiness;
  String? _exactScheduling;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WarmAlarm Example'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_readiness == null)
              const SizedBox.shrink()
            else
              Column(
                children: [
                  Text(
                    'Readiness: $_readiness',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Exact scheduling: $_exactScheduling'),
                ],
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                if (!context.mounted) return;
                try {
                  final readiness = await WarmAlarm.getReadiness();
                  final capabilities = await WarmAlarm.getCapabilities();
                  setState(() {
                    _readiness = readiness.level.name;
                    _exactScheduling = capabilities.exactScheduling.name;
                  });
                } on Exception catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Theme.of(context).primaryColor,
                      content: Text('$error'),
                    ),
                  );
                }
              },
              child: const Text('Inspect Alarm API'),
            ),
          ],
        ),
      ),
    );
  }
}
