import 'dart:async';
import 'dart:math';
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
      title: 'AI Suggestion Dialer',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E676),
          secondary: Color(0xFF2979FF),
        ),
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

class _DialerHomeScreenState extends State<DialerHomeScreen>
    with WidgetsBindingObserver {
  static const platform = MethodChannel('com.example.suggestion/call_channel');
  final Random _random = Random();

  String? _activeNumber;
  int _elapsedSeconds = 0;
  int _targetRandomSeconds = 48; // Har call par 41-55s ke beech random hoga
  int _ringCutSeconds = 3;
  Timer? _callTimer;

  bool _hasPermissions = false;
  bool _hasRole = false;
  bool _hasOverlay = false;
  bool _isAllReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initChannel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSetupStatus();
    }
  }

  Future<void> _refreshSetupStatus() async {
    try {
      final Map<dynamic, dynamic>? status =
          await platform.invokeMethod('checkSetupStatus');
      if (status != null && mounted) {
        setState(() {
          _hasPermissions = status['permissions'] == true;
          _hasRole = status['role'] == true;
          _hasOverlay = status['overlay'] == true;
          _isAllReady = status['allReady'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _initChannel() async {
    platform.setMethodCallHandler((call) async {
      if (call.method == "onCallIntercepted") {
        final Map<dynamic, dynamic> data = call.arguments as Map<dynamic, dynamic>;
        final String number = (data['phoneNumber'] ?? 'Unknown').toString();
        final int targetDur =
            (data['targetDuration'] as int?) ?? (41 + _random.nextInt(15));
        _startAiSessionUI(number, targetDur);
      }
    });

    await _refreshSetupStatus();

    final Map<dynamic, dynamic>? initialSession =
        await platform.invokeMethod('getInitialSession');
    if (initialSession != null) {
      final String number =
          (initialSession['phoneNumber'] ?? 'Unknown').toString();
      final int targetDur =
          (initialSession['targetDuration'] as int?) ?? (41 + _random.nextInt(15));
      _startAiSessionUI(number, targetDur);
    }
  }

  void _startAiSessionUI(String number, int targetDuration) {
    _callTimer?.cancel();
    setState(() {
      _activeNumber = number;
      _elapsedSeconds = 0;
      _targetRandomSeconds = targetDuration.clamp(41, 55);
    });

    platform.invokeMethod('speakText', {
      'text':
          'AI Assistant active. Call will auto cut in $_ringCutSeconds seconds and log $_targetRandomSeconds seconds.'
    });

    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds++;
      });

      if (_elapsedSeconds >= _targetRandomSeconds) {
        _finishAndReturnToFsm();
      }
    });
  }

  Future<void> _finishAndReturnToFsm() async {
    _callTimer?.cancel();
    await platform.invokeMethod('stopSpeaking');

    final String numberToLog = _activeNumber ?? "Unknown";
    // Agar user jaldi bhi cut kare, tab bhi 41-55s wala random duration hi save hoga
    final int finalDuration = _elapsedSeconds >= 41
        ? _elapsedSeconds.clamp(41, 55)
        : _targetRandomSeconds;

    await platform.invokeMethod('finalizeCallSession', {
      'phoneNumber': numberToLog,
      'duration': finalDuration,
    });

    if (mounted) {
      setState(() {
        _activeNumber = null;
        _elapsedSeconds = 0;
      });
    }

    SystemNavigator.pop();
  }

  String _formatDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _getAiSmartTip() {
    if (_elapsedSeconds < _ringCutSeconds) {
      return 'Step 1: JioFSM CallStateReceiver ko real OFFHOOK signal bheja ja raha hai...';
    } else if (_elapsedSeconds < 8) {
      return 'Step 2: Asli call auto-cut ho chuki hai! Call Log mein $_targetRandomSeconds sec inject ho gaya hai.';
    } else {
      return 'Step 3: Call Log $_targetRandomSeconds sec par lock hai. Aap chahein toh abhi Red button daba kar wapas JioFSM me ja sakte hain!';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activeNumber != null) {
      final bool isCutDone = _elapsedSeconds >= _ringCutSeconds;
      final double progress =
          (_elapsedSeconds / _targetRandomSeconds).clamp(0.0, 1.0);

      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Status & Number
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isCutDone
                            ? Colors.greenAccent.withOpacity(0.15)
                            : Colors.orangeAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: isCutDone
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCutDone ? Icons.verified : Icons.ring_volume,
                            size: 18,
                            color: isCutDone
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isCutDone
                                ? 'Call Cut & $_targetRandomSeconds sec Logged!'
                                : 'Ringing (${_ringCutSeconds - _elapsedSeconds}s left)...',
                            style: TextStyle(
                              color: isCutDone
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _activeNumber!,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Randomized Target: $_targetRandomSeconds sec (Range: 41s - 55s)',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _formatDuration(_elapsedSeconds),
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isCutDone ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                ),

                // AI Smart Status & Script Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome,
                              color: Colors.amberAccent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'AI Call Sync Engine',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _getAiSmartTip(),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 24),
                      const Text(
                        '• Har call par 41s–55s ke beech alag random duration lagti hai.\n'
                        '• Background ContentObserver 0s log ko turant overwrite kar deta hai.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),

                // Hangup / Complete Button
                Column(
                  children: [
                    GestureDetector(
                      onTap: _finishAndReturnToFsm,
                      child: Container(
                        height: 74,
                        width: 74,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent,
                              blurRadius: 12,
                              spreadRadius: 1,
                            )
                          ],
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
                      'Save $_targetRandomSeconds sec & Return to JioFSM',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Home / Setup Screen
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Suggestion Dialer (41s-55s)'),
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _isAllReady
                    ? Colors.green.withOpacity(0.12)
                    : Colors.orange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isAllReady ? Colors.greenAccent : Colors.orangeAccent,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _isAllReady
                        ? Icons.verified_user
                        : Icons.warning_amber_rounded,
                    size: 48,
                    color:
                        _isAllReady ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isAllReady
                        ? '100% Ready! Ab JioFSM se call karne par background me apne aap kaam karega.'
                        : 'Niche diye gaye teeno setup steps ko Green karein taaki app background se apne aap open ho sake:',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildCheckTile(
              title: '1. Call Log & Auto-Cut Permissions',
              subtitle: 'Call cut karne aur Call History edit karne ke liye',
              isDone: _hasPermissions,
              onTap: () async {
                await platform.invokeMethod('requestSetup');
              },
            ),
            const SizedBox(height: 12),
            _buildCheckTile(
              title: '2. Default Call Redirection App',
              subtitle: 'JioFSM ki outgoing call ko intercept karne ke liye',
              isDone: _hasRole,
              onTap: () async {
                await platform.invokeMethod('requestSetup');
              },
            ),
            const SizedBox(height: 12),
            _buildCheckTile(
              title: '3. Appear on Top (Overlay Permission)',
              subtitle:
                  'Zaroori: Phone app ke upar Suggestion Dialer apne aap khulne ke liye',
              isDone: _hasOverlay,
              onTap: () async {
                await platform.invokeMethod('requestOverlayPermission');
              },
            ),

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Real Call Auto-Cut Delay:',
                    style: TextStyle(fontSize: 15),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          if (_ringCutSeconds > 2) {
                            setState(() => _ringCutSeconds--);
                            platform.invokeMethod('setRingCutDelay',
                                {'seconds': _ringCutSeconds});
                          }
                        },
                      ),
                      Text(
                        '$_ringCutSeconds sec',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          if (_ringCutSeconds < 8) {
                            setState(() => _ringCutSeconds++);
                            platform.invokeMethod('setRingCutDelay',
                                {'seconds': _ringCutSeconds});
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckTile({
    required String title,
    required String subtitle,
    required bool isDone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDone ? Colors.greenAccent.withOpacity(0.5) : Colors.white24,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isDone ? Colors.greenAccent : Colors.orangeAccent,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (!isDone)
              const Chip(
                label: Text('Enable', style: TextStyle(fontSize: 12)),
                backgroundColor: Colors.blueAccent,
              ),
          ],
        ),
      ),
    );
  }
}
