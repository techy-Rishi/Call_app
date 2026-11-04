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
      title: 'Phone',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        primaryColor: Colors.blue,
        colorScheme: const ColorScheme.light(
          primary: Colors.blue,
          secondary: Colors.blueAccent,
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
  int _targetRandomSeconds = 48;
  int _ringCutSeconds = 5;
  bool _isDialerActive = true;
  
  // In-call toggles
  bool _isMuted = false;
  bool _isSpeakerOn = true; // Default speaker on for IVR voice
  bool _isHeld = false;

  Timer? _callTimer;
  Timer? _ivrPromptTimer;

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
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.resumed) {
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
        if (!_isDialerActive) return;
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
    if (initialSession != null && _isDialerActive) {
      final String number =
          (initialSession['phoneNumber'] ?? 'Unknown').toString();
      final int targetDur =
          (initialSession['targetDuration'] as int?) ?? (41 + _random.nextInt(15));
      _startAiSessionUI(number, targetDur);
    }
  }

  void _startAiSessionUI(String number, int targetDuration) {
    _callTimer?.cancel();
    _ivrPromptTimer?.cancel();

    setState(() {
      _activeNumber = number;
      _elapsedSeconds = 0;
      _targetRandomSeconds = targetDuration.clamp(41, 55);
      _isMuted = false;
      _isSpeakerOn = true;
      _isHeld = false;
    });

    // Initial IVR Welcome Speech
    _speakIvrVoice('Aapka call connect ho gaya hai. Kripya line par bane rahein.');

    // Periodic IVR Voice Prompts to simulate automated system
    _ivrPromptTimer = Timer.periodic(const Duration(seconds: 12), (timer) {
      if (!mounted || _activeNumber == null) {
        timer.cancel();
        return;
      }
      if (!_isMuted && !_isHeld) {
        _speakIvrVoice('Network verification jari hai. Kripya pratiksha karein.');
      }
    });

    // Main Call Duration Timer
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

  void _speakIvrVoice(String text) {
    if (_isSpeakerOn && !_isMuted) {
      platform.invokeMethod('speakText', {'text': text});
    }
  }

  Future<void> _finishAndReturnToFsm() async {
    _callTimer?.cancel();
    _ivrPromptTimer?.cancel();
    await platform.invokeMethod('stopSpeaking');

    final String numberToLog = _activeNumber ?? "Unknown";
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callTimer?.cancel();
    _ivrPromptTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // --- PROFESSIONAL CENTER-ALIGNED IN-CALL UI ---
    if (_activeNumber != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Caller Info Header
                        Column(
                          children: [
                            const SizedBox(height: 20),
                            Text(
                              _activeNumber!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w400,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Connected • IVR System',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black54,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _formatDuration(_elapsedSeconds),
                              style: const TextStyle(
                                fontSize: 46,
                                fontWeight: FontWeight.w200,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),

                        // Standard Phone Call Action Grid (Speaker, Mute, Hold, etc.)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildCallActionButton(
                                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                                    label: 'Mute',
                                    isActive: _isMuted,
                                    onPressed: () {
                                      setState(() => _isMuted = !_isMuted);
                                      if (_isMuted) platform.invokeMethod('stopSpeaking');
                                    },
                                  ),
                                  _buildCallActionButton(
                                    icon: Icons.dialpad,
                                    label: 'Keypad',
                                    isActive: false,
                                    onPressed: () {},
                                  ),
                                  _buildCallActionButton(
                                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                                    label: 'Speaker',
                                    isActive: _isSpeakerOn,
                                    onPressed: () {
                                      setState(() => _isSpeakerOn = !_isSpeakerOn);
                                      if (!_isSpeakerOn) {
                                        platform.invokeMethod('stopSpeaking');
                                      } else {
                                        _speakIvrVoice('Speaker mode enabled.');
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildCallActionButton(
                                    icon: Icons.add_call,
                                    label: 'Add call',
                                    isActive: false,
                                    onPressed: () {},
                                  ),
                                  _buildCallActionButton(
                                    icon: _isHeld ? Icons.play_arrow : Icons.pause,
                                    label: _isHeld ? 'Resume' : 'Hold',
                                    isActive: _isHeld,
                                    onPressed: () {
                                      setState(() => _isHeld = !_isHeld);
                                    },
                                  ),
                                  _buildCallActionButton(
                                    icon: Icons.bluetooth_audio,
                                    label: 'Bluetooth',
                                    isActive: false,
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // End Call Button (Center Aligned)
                        Column(
                          children: [
                            GestureDetector(
                              onTap: _finishAndReturnToFsm,
                              child: Container(
                                height: 72,
                                width: 72,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                      offset: Offset(0, 4),
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
                            const Text(
                              'End Call',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 14,
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
            },
          ),
        ),
      );
    }

    // --- HOME / CONFIGURATION SETTINGS SCREEN ---
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone Settings', style: TextStyle(color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggestion Dialer',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Inactive karne par normal calls jayengi',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
                Switch(
                  value: _isDialerActive,
                  activeColor: Colors.blue,
                  onChanged: (val) {
                    setState(() => _isDialerActive = val);
                    platform.invokeMethod('setDialerActiveState', {'isActive': val});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Configuration',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Auto-Cut Delay (3 - 30s)',
                        style: TextStyle(fontSize: 15, color: Colors.black87)),
                    Text('$_ringCutSeconds sec',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue)),
                  ],
                ),
                Slider(
                  value: _ringCutSeconds.toDouble(),
                  min: 3,
                  max: 30,
                  divisions: 27,
                  label: '$_ringCutSeconds sec',
                  onChanged: (val) {
                    setState(() => _ringCutSeconds = val.toInt());
                    platform.invokeMethod(
                        'setRingCutDelay', {'seconds': _ringCutSeconds});
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text(
            'Permissions Status',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),

          _buildCheckTile(
              title: 'Call Log & Permissions', isDone: _hasPermissions, onTap: () => platform.invokeMethod('requestSetup')),
          const SizedBox(height: 8),
          _buildCheckTile(
              title: 'Default Call Redirection App', isDone: _hasRole, onTap: () => platform.invokeMethod('requestSetup')),
          const SizedBox(height: 8),
          _buildCheckTile(
              title: 'Appear on Top (Overlay)', isDone: _hasOverlay, onTap: () => platform.invokeMethod('requestOverlayPermission')),
        ],
      ),
    );
  }

  Widget _buildCallActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            height: 60,
            width: 60,
            decoration: BoxDecoration(
              color: isActive ? Colors.blue.withOpacity(0.15) : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.blue : Colors.black87,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckTile({
    required String title,
    required bool isDone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isDone ? Icons.check_circle : Icons.error_outline,
              color: isDone ? Colors.green : Colors.orange,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Colors.black87),
              ),
            ),
            if (!isDone)
              const Text('Fix',
                  style: TextStyle(
                      color: Colors.blue, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
