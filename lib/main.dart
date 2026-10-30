import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Suggestion Dialer',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const DialerHomeScreen(),
    );
  }
}

class DialerHomeScreen extends StatefulWidget {
  const DialerHomeScreen({super.key});

  @override
  State<DialerHomeScreen> createState() => _DialerHomeScreenState();
}

class _DialerHomeScreenState extends State<DialerHomeScreen> {
  static const platform = MethodChannel('com.example.suggestion/call_channel');

  String? _activeNumber;
  int _elapsedSeconds = 0;
  final int _maxSeconds = 60;
  Timer? _callTimer;
  bool _isSetupDone = false;

  @override
  void initState() {
    super.initState();
    _initChannel();
  }

  Future<void> _initChannel() async {
    // Jab app pehle se background me ho aur JioFSM se nayi call intercept ho
    platform.setMethodCallHandler((call) async {
      if (call.method == "onCallIntercepted") {
        final String number = call.arguments as String;
        _startSimulatedCall(number);
      }
    });

    // Check karein ki permissions aur role enabled hain ya nahi
    final bool status = await platform.invokeMethod('checkSetupStatus') ?? false;
    setState(() {
      _isSetupDone = status;
    });

    // Agar app band thi aur call intercept hone se launch hui
    final String? initialNumber = await platform.invokeMethod('getInitialNumber');
    if (initialNumber != null && initialNumber.isNotEmpty) {
      _startSimulatedCall(initialNumber);
    }
  }

  void _startSimulatedCall(String number) {
    _callTimer?.cancel();
    setState(() {
      _activeNumber = number;
      _elapsedSeconds = 0;
    });

    // IVR / Suggestion voice start karein
    platform.invokeMethod('speakText', {
      'text': 'Call connected to $number. Your 60 seconds preparation session has started.'
    });

    // Har 1 second par timer badhayein
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });

      // 60 seconds pure hone par automatic save aur close
      if (_elapsedSeconds >= _maxSeconds) {
        _endCallAndSaveLog();
      }
    });
  }

  Future<void> _endCallAndSaveLog() async {
    _callTimer?.cancel();
    await platform.invokeMethod('stopSpeaking');

    final String numberToLog = _activeNumber ?? "Unknown";
    // Agar 0 second par cut kiya toh kam se kam 1 sec log karein, warna exact seconds (e.g. 45s)
    final int durationToLog = _elapsedSeconds > 0 ? _elapsedSeconds : 1;

    await platform.invokeMethod('insertCallLog', {
      'phoneNumber': numberToLog,
      'duration': durationToLog,
    });

    setState(() {
      _activeNumber = null;
      _elapsedSeconds = 0;
    });

    // App close karke wapas JioFSM screen par bhej dein
    SystemNavigator.pop();
  }

  String _formatDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Agar Call Intercept hui hai toh Native-style Active Call UI dikhayein
    if (_activeNumber != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    const Text(
                      'Connected (Simulated IVR)',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _activeNumber!,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _formatDuration(_elapsedSeconds),
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),

                // Suggestions Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Call Preparation Points:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text('• Customer details verify karein.'),
                      SizedBox(height: 6),
                      Text('• JioFSM task status note karein.'),
                      SizedBox(height: 6),
                      Text('• Jab chahein Red button daba kar call end karein, exact seconds Call History mein save ho jayenge.'),
                    ],
                  ),
                ),

                // Red Hangup / End Call Button
                Column(
                  children: [
                    GestureDetector(
                      onTap: _endCallAndSaveLog,
                      child: Container(
                        height: 72,
                        width: 72,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'End & Log (${_elapsedSeconds}s)',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 2. Normal Setup Screen (Jab koi call active na ho)
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suggestion Dialer Setup'),
        backgroundColor: Colors.black26,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isSetupDone ? Icons.check_circle : Icons.warning_amber_rounded,
                size: 64,
                color: _isSetupDone ? Colors.greenAccent : Colors.orangeAccent,
              ),
              const SizedBox(height: 16),
              Text(
                _isSetupDone
                    ? 'App Ready Hai! Ab aap JioFSM se call click kar sakte hain.'
                    : 'Pehle Permissions aur Call Redirection enable karein.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  await platform.invokeMethod('requestSetup');
                  await Future.delayed(const Duration(seconds: 2));
                  final bool status =
                      await platform.invokeMethod('checkSetupStatus') ?? false;
                  setState(() {
                    _isSetupDone = status;
                  });
                },
                icon: const Icon(Icons.security),
                label: const Text('Enable Permissions & Call Interception'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  _startSimulatedCall('9876543210');
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Test Fake Call Timer (Demo)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
