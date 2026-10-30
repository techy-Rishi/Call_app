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
  int _ringCutSeconds = 3; // Kitne seconds baad asli call auto-cut karni hai
  bool _realCallCutDone = false;
  Timer? _callTimer;
  bool _isSetupDone = false;

  @override
  void initState() {
    super.initState();
    _initChannel();
  }

  Future<void> _initChannel() async {
    platform.setMethodCallHandler((call) async {
      if (call.method == "onCallIntercepted") {
        final String number = call.arguments as String;
        _startHybridCallSession(number);
      }
    });

    final bool status = await platform.invokeMethod('checkSetupStatus') ?? false;
    setState(() {
      _isSetupDone = status;
    });

    final String? initialNumber = await platform.invokeMethod('getInitialNumber');
    if (initialNumber != null && initialNumber.isNotEmpty) {
      _startHybridCallSession(initialNumber);
    }
  }

  void _startHybridCallSession(String number) {
    _callTimer?.cancel();
    setState(() {
      _activeNumber = number;
      _elapsedSeconds = 0;
      _realCallCutDone = false;
    });

    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      setState(() {
        _elapsedSeconds++;
      });

      // Jaise hi Ring Delay (e.g. 3 seconds) pura ho, asli call cut karein aur usi log ko edit karein
      if (_elapsedSeconds == _ringCutSeconds && !_realCallCutDone) {
        setState(() {
          _realCallCutDone = true;
        });

        await platform.invokeMethod('cutRealCallAndPreUpdateLog', {
          'phoneNumber': number,
          'duration': _maxSeconds,
        });

        platform.invokeMethod('speakText', {
          'text': 'Real call disconnected and log updated. Timer is running.'
        });
      }

      // 60 seconds pure hone par final duration update karein aur wapas JioFSM par bhej dein
      if (_elapsedSeconds >= _maxSeconds) {
        _endCallAndSaveFinalLog();
      }
    });
  }

  Future<void> _endCallAndSaveFinalLog() async {
    _callTimer?.cancel();
    await platform.invokeMethod('stopSpeaking');

    final String numberToLog = _activeNumber ?? "Unknown";
    final int durationToLog = _elapsedSeconds > 0 ? _elapsedSeconds : 1;

    // Agar user ne 3 second se pehle hi cut daba diya toh bhi real call cut karein
    if (!_realCallCutDone) {
      await platform.invokeMethod('cutRealCallAndPreUpdateLog', {
        'phoneNumber': numberToLog,
        'duration': durationToLog,
      });
      await Future.delayed(const Duration(milliseconds: 900));
    }

    // Usi same Call Log entry mein exact seconds (e.g. 45s) update karein
    await platform.invokeMethod('updateFinalCallLog', {
      'phoneNumber': numberToLog,
      'duration': durationToLog,
    });

    setState(() {
      _activeNumber = null;
      _elapsedSeconds = 0;
      _realCallCutDone = false;
    });

    // Wapas JioFSM par laut jayein
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _realCallCutDone ? Colors.green.shade800 : Colors.orange.shade800,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _realCallCutDone
                            ? 'Real Call Cut & Log Edited! (Timer Active)'
                            : 'Dialing Real Call (Auto-cutting in ${_ringCutSeconds - _elapsedSeconds}s)...',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                        'How This Works with JioFSM:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.amberAccent,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text('1. Asli call lagti hai taaki JioFSM call state detect kar le.'),
                      SizedBox(height: 6),
                      Text('2. 3 seconds mein asli call cut ho jati hai aur usi Call Log mein 60s update ho jata hai.'),
                      SizedBox(height: 6),
                      Text('3. Jab aap Red button dabayenge (jaise 45s par), usi log mein 45s save ho jayega.'),
                    ],
                  ),
                ),

                Column(
                  children: [
                    GestureDetector(
                      onTap: _endCallAndSaveFinalLog,
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
                      'End & Update Same Log (${_elapsedSeconds}s)',
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
                    ? 'Ready! JioFSM se call click karne par 3s ring hokar auto-cut hogi aur wahi log edit hoga.'
                    : 'Permissions (Phone, Call Log, Auto-End Call) aur Call Redirection allow karein.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Auto-Cut Ring Delay: ', style: TextStyle(fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      if (_ringCutSeconds > 1) {
                        setState(() => _ringCutSeconds--);
                      }
                    },
                  ),
                  Text('$_ringCutSeconds sec', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      if (_ringCutSeconds < 10) {
                        setState(() => _ringCutSeconds++);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
            ],
          ),
        ),
      ),
    );
  }
}
