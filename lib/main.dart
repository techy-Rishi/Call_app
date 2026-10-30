import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SuggestionDialerApp());
}

class SuggestionDialerApp extends StatelessWidget {
  const SuggestionDialerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Suggestion Call',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.tealAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const platform = MethodChannel('com.example.suggestion_dialer/call_channel');

  final List<String> _suggestions = [
    "Take a deep breath and speak 15% slower than usual.",
    "State your main purpose clearly in the first 20 seconds.",
    "Listen actively without interrupting while they respond.",
    "Ask open-ended questions starting with 'How' or 'What'.",
    "Smile while talking—it noticeably changes your vocal tone.",
    "Confirm the next action item before hanging up.",
    "Keep your posture upright to project confidence.",
    "If you need time to think, pause instead of using filler words."
  ];

  bool _speakSuggestionsAloud = true;
  bool _autoPlaceRealCallAfterTimer = false;
  String? _activeInterceptedNumber;
  int _secondsRemaining = 60;
  String _currentSuggestion = "";
  Timer? _countdownTimer;
  final TextEditingController _newSuggestionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _setupMethodChannelListener();
    _checkInitialLaunchNumber();
  }

  void _setupMethodChannelListener() {
    platform.setMethodCallHandler((call) async {
      if (call.method == 'onIncomingDial') {
        final String number = call.arguments as String? ?? "Unknown Number";
        _startSuggestionCallSession(number);
      }
    });
  }

  Future<void> _checkInitialLaunchNumber() async {
    try {
      final String? initialNumber = await platform.invokeMethod('getInitialNumber');
      if (initialNumber != null && initialNumber.isNotEmpty) {
        _startSuggestionCallSession(initialNumber);
      }
    } on PlatformException {
      // Ignore on normal startup
    }
  }

  void _startSuggestionCallSession(String phoneNumber) {
    _countdownTimer?.cancel();
    setState(() {
      _activeInterceptedNumber = phoneNumber;
      _secondsRemaining = 60;
      _currentSuggestion = _getRandomSuggestion();
    });

    if (_speakSuggestionsAloud) {
      platform.invokeMethod('speakText', {'text': _currentSuggestion});
    }

        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
          // Rotate suggestion every 10 seconds
          if (_secondsRemaining % 10 == 0) {
            _currentSuggestion = _getRandomSuggestion();
            if (_speakSuggestionsAloud) {
              platform.invokeMethod('speakText', {'text': _currentSuggestion});
            }
          }
        });
      } else {
        timer.cancel();
        // Time's up! Stop speaking and close suggestion screen, call is already live
        platform.invokeMethod('stopSpeaking');
        setState(() {
          _activeInterceptedNumber = null;
        });
      }
    });

  }

  String _getRandomSuggestion() {
    if (_suggestions.isEmpty) return "Stay calm and focused.";
    return _suggestions[Random().nextInt(_suggestions.length)];
  }

  void _nextSuggestionManually() {
    setState(() {
      _currentSuggestion = _getRandomSuggestion();
    });
    if (_speakSuggestionsAloud) {
      platform.invokeMethod('speakText', {'text': _currentSuggestion});
    }
  }

  void _endSuggestionSession() {
    _countdownTimer?.cancel();
    platform.invokeMethod('stopSpeaking');
    setState(() {
      _activeInterceptedNumber = null;
    });
    SystemNavigator.pop();
  }

  void _triggerRealCall() {
    final number = _activeInterceptedNumber;
    _countdownTimer?.cancel();
    platform.invokeMethod('stopSpeaking');
    setState(() {
      _activeInterceptedNumber = null;
    });
    if (number != null) {
      platform.invokeMethod('placeRealCall', {'number': number});
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _newSuggestionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show the 1-Minute Suggestion Call Screen whenever a call is intercepted
    if (_activeInterceptedNumber != null) {
      return _buildActiveCallScreen();
    }

    // Otherwise, show the Setup & Customization Dashboard
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suggestion Call Setup'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Step 1: Enable Call Redirection',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Grant permissions and set this app as your Default Call Redirection or Dialer app so calls from any app open here first.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => platform.invokeMethod('requestPermissions'),
                    icon: const Icon(Icons.security),
                    label: const Text('1. Grant Phone Permissions'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => platform.invokeMethod('requestCallRedirectionRole'),
                    icon: const Icon(Icons.call_split),
                    label: const Text('2. Set as Call Redirection App (Recommended)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => platform.invokeMethod('requestDefaultDialerRole'),
                    icon: const Icon(Icons.phone_android),
                    label: const Text('3. Set as Default Dialer App (Optional)'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Speak Suggestions Aloud (Voice Mode)'),
                  subtitle: const Text('Reads suggestions like a live phone call'),
                  value: _speakSuggestionsAloud,
                  onChanged: (val) => setState(() => _speakSuggestionsAloud = val),
                ),
                SwitchListTile(
                  title: const Text('Auto-Dial Real Call After 60s'),
                  subtitle: const Text(
                    'If OFF, the call simply ends after giving 1 minute of suggestions',
                  ),
                  value: _autoPlaceRealCallAfterTimer,
                  onChanged: (val) => setState(() => _autoPlaceRealCallAfterTimer = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _startSuggestionCallSession('+91 98765 43210'),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Test 1-Minute Suggestion Call Now'),
          ),
          const SizedBox(height: 24),
          const Text(
            'Your Custom Suggestions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newSuggestionController,
                  decoration: const InputDecoration(
                    hintText: 'Add a new suggestion...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.add),
                onPressed: () {
                  final text = _newSuggestionController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _suggestions.insert(0, text);
                      _newSuggestionController.clear();
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._suggestions.asMap().entries.map((entry) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(entry.value),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () {
                    setState(() {
                      _suggestions.removeAt(entry.key);
                    });
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActiveCallScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  const Text(
                    'SUGGESTION CALL ACTIVE',
                    style: TextStyle(
                      color: Colors.tealAccent,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _activeInterceptedNumber ?? '',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: CircularProgressIndicator(
                      value: _secondsRemaining / 60.0,
                      strokeWidth: 8,
                      color: Colors.tealAccent,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  Text(
                    '${_secondsRemaining}s',
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.lightbulb, color: Colors.amberAccent, size: 36),
                    const SizedBox(height: 16),
                    Text(
                      _currentSuggestion,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _nextSuggestionManually,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Next Suggestion'),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      FloatingActionButton.large(
                        heroTag: 'end_btn',
                        backgroundColor: Colors.redAccent,
                        onPressed: _endSuggestionSession,
                        child: const Icon(Icons.call_end, size: 36, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const Text('End / Close'),
                    ],
                  ),
                  Column(
                    children: [
                      FloatingActionButton.large(
                        heroTag: 'call_btn',
                        backgroundColor: Colors.green,
                        onPressed: _triggerRealCall,
                        child: const Icon(Icons.call, size: 36, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const Text('Dial Real Call'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
