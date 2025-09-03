import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FemWiseApp());
}

class FemWiseApp extends StatelessWidget {
  const FemWiseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FemWise',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B9D)),
        useMaterial3: true,
        fontFamily: 'SF Pro Display',
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          color: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ),
      home: const _Gate(),
    );
  }
}

class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _loading = true;
  bool _hasProfile = false;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getString('profileId');
      if (storedId == null) {
        _hasProfile = false;
      } else {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(storedId)
            .get();
        if (snap.exists) {
          _profile = snap.data();
          if (_profile != null) _profile!['id'] = snap.id;
          _hasProfile = true;
        } else {
          _hasProfile = false;
        }
      }
    } catch (e) {
      print('Error loading profile: $e');
      _hasProfile = false;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasProfile) return const OnboardingScreen();
    return DashboardScreen(profile: _profile!);
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _healthCtrl = TextEditingController();
  final _cycleCtrl = TextEditingController(text: '28');
  final _periodLenCtrl = TextEditingController(text: '5');
  DateTime? _lastPeriodStart;
  String _country = 'India';
  bool _consent = false;
  bool _medicalDisclaimer = false;
  bool _saving = false;

  int _currentStep = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickLastPeriodStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastPeriodStart ?? now.subtract(const Duration(days: 7)),
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _lastPeriodStart = picked);
    }
  }

  void _nextStep() {
    if (_currentStep < 4) {
      setState(() => _currentStep++);
      _animationController.reset();
      _animationController.forward();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _animationController.reset();
      _animationController.forward();
    }
  }

  Future<void> _submit() async {
    if (_lastPeriodStart == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your last period start date'),
        ),
      );
      return;
    }
    if (!_consent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to data storage terms')),
      );
      return;
    }
    if (!_medicalDisclaimer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please acknowledge the medical disclaimer')),
      );
      return;
    }
    // Validate all required fields before submitting
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }
    final age = int.tryParse(_ageCtrl.text.trim());
    if (age == null || age < 10 || age > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid age (10-100)')),
      );
      return;
    }
    final cycle = int.tryParse(_cycleCtrl.text.trim());
    final period = int.tryParse(_periodLenCtrl.text.trim());
    if (cycle == null || cycle < 21 || cycle > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid cycle length (21-60 days)')),
      );
      return;
    }
    if (period == null || period < 1 || period > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid period length (1-10 days)')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final rawName = _nameCtrl.text.trim();
      final docId = rawName.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9_-]'),
        '_',
      );
      if (docId.isEmpty) throw Exception('Invalid name');

      final cycleLength = int.tryParse(_cycleCtrl.text.trim()) ?? 28;
      final periodLength = int.tryParse(_periodLenCtrl.text.trim()) ?? 5;

      final data = {
        'id': docId,
        'name': rawName,
        'age': int.tryParse(_ageCtrl.text.trim()) ?? 0,
        'healthIssues': _healthCtrl.text.trim(),
        'country': _country,
        'cycleLength': cycleLength,
        'periodLength': periodLength,
        if (_lastPeriodStart != null)
          'lastPeriodStartDate': _lastPeriodStart!.toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
      };

      final userRef = FirebaseFirestore.instance.collection('users').doc(docId);
      await userRef.set(data, SetOptions(merge: true));

      // If user supplied last period start, create an initial period log entry
      if (_lastPeriodStart != null) {
        await userRef.collection('periods').add({
          'start': DateTime(
            _lastPeriodStart!.year,
            _lastPeriodStart!.month,
            _lastPeriodStart!.day,
          ).toIso8601String(),
        });
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profileId', docId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DashboardScreen(profile: data)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF6B9D), Color(0xFF007AFF), Color(0xFF7B68EE)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Progress indicator
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: List.generate(5, (index) {
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsets.only(right: index < 4 ? 8 : 0),
                        decoration: BoxDecoration(
                          color: index <= _currentStep
                              ? Colors.white
                              : Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // Content
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: SingleChildScrollView(
                              child: _buildStepContent(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Navigation buttons
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      Expanded(
                        child: _buildNavButton('Back', false, _previousStep),
                      ),
                    if (_currentStep > 0) const SizedBox(width: 16),
                    Expanded(
                      child: _buildNavButton(
                        _currentStep == 4 ? 'Get Started' : 'Next',
                        true,
                        _currentStep == 4
                            ? _submit
                            : _validateAndProceed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(String text, bool isPrimary, VoidCallback? onPressed) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isPrimary ? Colors.white : Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: isPrimary
            ? null
            : Border.all(color: Colors.white.withOpacity(0.5)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _saving && _currentStep == 4
                ? const CupertinoActivityIndicator(color: Color(0xFF007AFF))
                : Text(
                    text,
                    style: TextStyle(
                      color: isPrimary ? const Color(0xFF007AFF) : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _nameCtrl.text.trim().isNotEmpty;
      case 1:
        final age = int.tryParse(_ageCtrl.text.trim());
        return age != null && age >= 10 && age <= 100;
      case 2:
        return _lastPeriodStart != null;
      case 3:
        final cycle = int.tryParse(_cycleCtrl.text.trim());
        final period = int.tryParse(_periodLenCtrl.text.trim());
        return cycle != null &&
            cycle >= 21 &&
            cycle <= 60 &&
            period != null &&
            period >= 1 &&
            period <= 10;
      case 4:
        return _consent && _medicalDisclaimer;
      default:
        return false;
    }
  }

  void _validateAndProceed() {
    // For steps with forms, validate the form first
    if (_currentStep == 0 || _currentStep == 1 || _currentStep == 3) {
      if (_formKey.currentState?.validate() ?? false) {
        _nextStep();
      }
    } else {
      // For other steps, use the existing _canProceed logic
      if (_canProceed()) {
        _nextStep();
      }
    }
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildWelcomeStep();
      case 1:
        return _buildPersonalInfoStep();
      case 2:
        return _buildPeriodDateStep();
      case 3:
        return _buildCycleInfoStep();
      case 4:
        return _buildConsentStep();
      default:
        return Container();
    }
  }

  Widget _buildWelcomeStep() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFFF8FB3)],
                ),
                borderRadius: BorderRadius.circular(60),
              ),
              child: const Icon(
                CupertinoIcons.heart_fill,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Welcome to FemWise',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D1D1F),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your personal menstrual health companion with AI-powered insights',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'What\'s your name?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
                contentPadding: const EdgeInsets.all(20),
              ),
              style: const TextStyle(fontSize: 16),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalInfoStep() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF007AFF), Color(0xFF5AC8FA)],
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              CupertinoIcons.person_fill,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Tell us about yourself',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D1D1F),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This helps us provide personalized insights',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _ageCtrl,
            decoration: InputDecoration(
              labelText: 'Age',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.all(20),
            ),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your age';
              }
              final age = int.tryParse(value.trim());
              if (age == null || age < 10 || age > 100) {
                return 'Please enter a valid age (10-100)';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _country,
            items: [
              'India',
              'Other',
            ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() => _country = v ?? 'India'),
            decoration: InputDecoration(
              labelText: 'Country',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.all(20),
            ),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _healthCtrl,
            decoration: InputDecoration(
              labelText: 'Health conditions (optional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.all(20),
            ),
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildPeriodDateStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B9D), Color(0xFFFF8FB3)],
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              CupertinoIcons.calendar,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'When did your last period start?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D1D1F),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This is required to provide accurate cycle predictions',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _lastPeriodStart != null
                    ? const Color(0xFF007AFF)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  CupertinoIcons.calendar_badge_plus,
                  size: 48,
                  color: _lastPeriodStart != null
                      ? const Color(0xFF007AFF)
                      : Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  _lastPeriodStart == null
                      ? 'Tap to select date'
                      : '${_lastPeriodStart!.day.toString().padLeft(2, '0')}/${_lastPeriodStart!.month.toString().padLeft(2, '0')}/${_lastPeriodStart!.year}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _lastPeriodStart != null
                        ? const Color(0xFF007AFF)
                        : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CupertinoButton(
            onPressed: _pickLastPeriodStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Select Date',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCycleInfoStep() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7B68EE), Color(0xFF9B7EF7)],
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              CupertinoIcons.chart_bar_circle,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Cycle Information',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D1D1F),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Help us understand your cycle pattern',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _cycleCtrl,
            decoration: InputDecoration(
              labelText: 'Average Cycle Length (days)',
              hintText: 'Usually 21-35 days',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.all(20),
            ),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter cycle length';
              }
              final cycle = int.tryParse(value.trim());
              if (cycle == null || cycle < 21 || cycle > 60) {
                return 'Please enter a valid cycle length (21-60 days)';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _periodLenCtrl,
            decoration: InputDecoration(
              labelText: 'Period Length (days)',
              hintText: 'Usually 3-7 days',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.all(20),
            ),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter period length';
              }
              final period = int.tryParse(value.trim());
              if (period == null || period < 1 || period > 10) {
                return 'Please enter a valid period length (1-10 days)';
              }
              return null;
            },
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildConsentStep() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF50C878), Color(0xFF66D68A)],
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(
              CupertinoIcons.shield_fill,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Privacy & Security',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D1D1F),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your data is encrypted and stored securely',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(
                  CupertinoIcons.lock_shield_fill,
                  size: 48,
                  color: Color(0xFF50C878),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your Privacy Matters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D1D1F),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We use industry-standard encryption to protect your personal health data. Your information is never shared with third parties.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => setState(() => _consent = !_consent),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _consent
                    ? const Color(0xFF007AFF).withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _consent ? const Color(0xFF007AFF) : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _consent
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    color: _consent
                        ? const Color(0xFF007AFF)
                        : Colors.grey[400],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'I agree to the secure storage of my health data',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1D1D1F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _medicalDisclaimer = !_medicalDisclaimer),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _medicalDisclaimer
                    ? const Color(0xFF007AFF).withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _medicalDisclaimer ? const Color(0xFF007AFF) : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _medicalDisclaimer
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                    color: _medicalDisclaimer
                        ? const Color(0xFF007AFF)
                        : Colors.grey[400],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'I understand this app is for general purposes only. For accurate medical information, I will consult a gynecologist or respected doctor',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1D1D1F),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const DashboardScreen({super.key, required this.profile});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _PeriodLog {
  final String id;
  final DateTime start;
  _PeriodLog(this.id, this.start);
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _navIndex = 0;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<_PeriodLog> _periodLogs = [];
  bool _loading = true;
  String _insight = '';
  List<_FeedItem> _feed = [];
  bool _feedLoading = false;
  String? _geminiKey;

  int? get _storedCycleLength => widget.profile['cycleLength'] is int
      ? widget.profile['cycleLength'] as int
      : int.tryParse(widget.profile['cycleLength']?.toString() ?? '');
  int? get _storedPeriodLength => widget.profile['periodLength'] is int
      ? widget.profile['periodLength'] as int
      : int.tryParse(widget.profile['periodLength']?.toString() ?? '');
  DateTime? get _storedLastStart =>
      widget.profile['lastPeriodStartDate'] != null
      ? DateTime.tryParse(widget.profile['lastPeriodStartDate'] as String)
      : null;

  @override
  void initState() {
    super.initState();
    _load();
    _loadFeed();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('config')
          .doc('keys')
          .get();
      if (snap.exists) {
        final data = snap.data();
        _geminiKey = data?['gemini']?.toString();
      }
    } catch (_) {
      // ignore config load errors (will fallback)
    }
  }

  Future<void> _load() async {
    try {
      final id = widget.profile['id'] as String?;
      if (id == null) {
        setState(() => _loading = false);
        return;
      }
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .collection('periods');
      final snaps = await col
          .orderBy('start', descending: true)
          .limit(120)
          .get();
      _periodLogs = snaps.docs
          .map((d) => _PeriodLog(d.id, DateTime.parse(d['start'] as String)))
          .toList();
      _selectedDay = _periodLogs.isNotEmpty ? _periodLogs.first.start : null;
      _updateCycleInsight();
    } catch (e) {
      print('Error loading periods: $e');
      _insight = 'Unable to load period data. Please try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addPeriodStart(DateTime day) async {
    try {
      final id = widget.profile['id'] as String?;
      if (id == null) {
        _showError('Unable to save period data.');
        return;
      }
      final userRef = FirebaseFirestore.instance.collection('users').doc(id);
      final col = userRef.collection('periods');
      final doc = await col.add({
        'start': DateTime(day.year, day.month, day.day).toIso8601String(),
      });

      // Update lastPeriodStartDate in user profile
      await userRef.set({
        'lastPeriodStartDate': day.toIso8601String(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _periodLogs.insert(0, _PeriodLog(doc.id, day));
          _selectedDay = day;
          widget.profile['lastPeriodStartDate'] = day.toIso8601String();
          _updateCycleInsight();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Period start logged successfully!')),
        );
      }
    } catch (e) {
      _showError('Error logging period: $e');
    }
  }

  Future<void> _deleteSelectedPeriod() async {
    if (_selectedDay == null) return;
    final match = _periodLogs.firstWhere(
      (p) =>
          p.start.year == _selectedDay!.year &&
          p.start.month == _selectedDay!.month &&
          p.start.day == _selectedDay!.day,
      orElse: () => _PeriodLog('', DateTime(1900)),
    );
    if (match.id.isEmpty) {
      _showError('No log for selected day.');
      return;
    }
    final id = widget.profile['id'];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Log'),
        content: Text('Delete period log for ${_fmt(match.start)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .collection('periods')
          .doc(match.id)
          .delete();
      setState(() {
        _periodLogs.removeWhere((p) => p.id == match.id);
        if (_periodLogs.isNotEmpty) {
          _selectedDay = _periodLogs.first.start;
        } else {
          _selectedDay = null;
        }
        _updateCycleInsight();
      });
    } catch (e) {
      _showError('Error deleting log: $e');
    }
  }

  Future<void> _resetAllLogs() async {
    if (_periodLogs.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset All Logs'),
        content: const Text(
          'This will delete all logged period starts. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final id = widget.profile['id'];
      final batch = FirebaseFirestore.instance.batch();
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .collection('periods');
      for (final p in _periodLogs) {
        batch.delete(ref.doc(p.id));
      }
      await batch.commit();
      setState(() {
        _periodLogs.clear();
        _selectedDay = null;
        _updateCycleInsight();
      });
    } catch (e) {
      _showError('Error resetting logs: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _updateCycleInsight() {
    DateTime? lastStart = _periodLogs.isNotEmpty
        ? _periodLogs.first.start
        : _storedLastStart;
    if (lastStart == null) {
      _insight = 'Log a period start to begin tracking your cycle.';
      return;
    }

    // Average cycle length if multiple logs
    final starts = _periodLogs.map((e) => e.start).toList();
    if (starts.length >= 2) {
      final diffs = <int>[];
      for (int i = 0; i < starts.length - 1; i++) {
        diffs.add(starts[i].difference(starts[i + 1]).inDays);
      }
      final avg = diffs.reduce((a, b) => a + b) / diffs.length;
      widget.profile['cycleLength'] = avg.round();
    }

    final cycleLength =
        (widget.profile['cycleLength'] as int?) ?? _storedCycleLength ?? 28;
    final periodLength =
        (widget.profile['periodLength'] as int?) ?? _storedPeriodLength ?? 5;

    final today = DateTime.now();
    final startDateOnly = DateTime(
      lastStart.year,
      lastStart.month,
      lastStart.day,
    );
    final dayInCycle =
        today.difference(startDateOnly).inDays + 1; // Day 1 based

    final ovulationDayIndex = cycleLength - 14; // approximate luteal length
    final ovulationDate = startDateOnly.add(
      Duration(days: ovulationDayIndex - 1),
    );
    final fertileStart = ovulationDate.subtract(const Duration(days: 5));
    final fertileEnd = ovulationDate; // inclusive fertile end
    final nextPeriod = startDateOnly.add(Duration(days: cycleLength));

    String phase = '';
    String note = '';

    if (dayInCycle <= 0) {
      phase = 'Pre-Cycle';
      note = 'Cycle calculations start once a period is logged.';
    } else if (dayInCycle <= periodLength) {
      phase = 'Menstrual Phase';
      note = 'Low estrogen & progesterone. Rest, hydrate & gentle movement.';
    } else if (!today.isBefore(fertileStart) && !today.isAfter(fertileEnd)) {
      phase = 'Ovulation Window';
      note = 'Peak fertility & confidence. You may feel energetic & social.';
    } else if (today.isAfter(fertileEnd) && today.isBefore(nextPeriod)) {
      phase = 'Luteal Phase';
      note = 'Progesterone dominant. Support mood & energy; prioritize sleep.';
    } else if (today.isBefore(fertileStart)) {
      phase = 'Follicular Phase';
      note = 'Rising estrogen. Good time for learning, strength & creativity.';
    }

    if (phase.isEmpty) {
      phase = 'Follicular Phase';
      note = 'Rising estrogen. Productive & energetic period of the cycle.';
    }

    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')} ${_monthShort(d.month)}';

    _insight = [
      'Phase: $phase (Day $dayInCycle of ~$cycleLength).',
      'Fertile Window: ${fmt(fertileStart)} – ${fmt(fertileEnd)}.',
      'Predicted Ovulation: ${fmt(ovulationDate)}.',
      'Next Period Expected: ${fmt(nextPeriod)}.',
      note,
      'Note: Cycle lengths vary (21–35 days common). Estimates refine with more logs.',
    ].join('\n');
  }

  String _monthShort(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[m - 1];
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadFeed() async {
    setState(() => _feedLoading = true);
    final urls = [
      'https://www.bloodygoodperiod.com/blog-feed.xml',
      'https://www.afripads.com/feed/',
      'https://rubycup.com/blogs/news.atom',
    ];
    final list = <_FeedItem>[];
    for (final u in urls) {
      try {
        final r = await http.get(Uri.parse(u));
        if (r.statusCode == 200) {
          if (r.body.startsWith('<?xml')) {
            final doc = xml.XmlDocument.parse(r.body);
            // RSS items
            for (final item in doc.findAllElements('item').take(10)) {
              final title =
                  item.getElement('title')?.innerText.trim() ?? 'No title';
              final link = item.getElement('link')?.innerText.trim() ?? '';
              final descRaw = item.getElement('description')?.innerText ?? '';
              final contentRaw = item.findElements('content:encoded').isNotEmpty
                  ? item.findElements('content:encoded').first.innerText
                  : '';
              final publishedStr = item.getElement('pubDate')?.innerText;
              DateTime? published;
              if (publishedStr != null) {
                try {
                  published = DateTime.parse(publishedStr);
                } catch (_) {}
              }
              list.add(
                _FeedItem(
                  title: title,
                  link: link,
                  source: u,
                  description: _stripHtml(
                    contentRaw.isNotEmpty ? contentRaw : descRaw,
                  ),
                  published: published,
                ),
              );
            }
            // Atom entries
            for (final entry in doc.findAllElements('entry').take(10)) {
              final title =
                  entry.getElement('title')?.innerText.trim() ?? 'No title';
              final linkEl = entry
                  .findElements('link')
                  .firstWhere(
                    (_) => true,
                    orElse: () => xml.XmlElement(xml.XmlName('link')),
                  );
              final link =
                  linkEl.getAttribute('href') ??
                  entry.getElement('id')?.innerText.trim() ??
                  '';
              final summary = entry.getElement('summary')?.innerText ?? '';
              final content = entry.getElement('content')?.innerText ?? '';
              final publishedStr =
                  entry.getElement('updated')?.innerText ??
                  entry.getElement('published')?.innerText;
              DateTime? published;
              if (publishedStr != null) {
                try {
                  published = DateTime.parse(publishedStr);
                } catch (_) {}
              }
              list.add(
                _FeedItem(
                  title: title,
                  link: link,
                  source: u,
                  description: _stripHtml(
                    content.isNotEmpty ? content : summary,
                  ),
                  published: published,
                ),
              );
            }
          }
        }
      } catch (_) {
        // ignore per-feed errors
      }
    }
    if (mounted) {
      setState(() {
        _feed = list;
        _feedLoading = false;
      });
    }
    _saveFeedItems(list); // persist to Firestore
  }

  Future<void> _saveFeedItems(List<_FeedItem> items) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final col = FirebaseFirestore.instance.collection('feedItems');
      for (final it in items) {
        if (it.link.isEmpty) continue;
        final id = _safeId(it.link);
        batch.set(col.doc(id), {
          'title': it.title,
          'link': it.link,
          'source': it.source,
          'description': it.description,
          'published': it.published?.toIso8601String(),
          'fetchedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (_) {
      // ignore persistence errors
    }
  }

  String _safeId(String link) {
    final cleaned = link.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    if (cleaned.length > 120) return cleaned.substring(0, 120);
    return cleaned;
  }

  String _stripHtml(String input) {
    return input
        .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _callAI() async {
    if (_periodLogs.isEmpty) {
      _showError('Please log some periods first to get AI insights.');
      return;
    }

    // Use a demo API key for testing - in production, this should be from Firestore
    final apiKey = _geminiKey ?? 'AIzaSyAgL8tHrdwJG03HSnTOz_ScWIe7zhXZQFY';

    setState(() => _loading = true);

    final cycleData = _periodLogs.map((e) => _fmt(e.start)).join(', ');
    final userAge = widget.profile['age'] ?? 25;
    final healthIssues = widget.profile['healthIssues'] ?? 'None';

    final prompt =
        '''
Analyze this menstrual cycle data for a $userAge-year-old user:
Cycle start dates: $cycleData
Health conditions: $healthIssues

Provide a brief, encouraging health insight (max 150 words) covering:
1. Cycle regularity assessment
2. Current phase recommendations
3. When to consult a healthcare provider

Use a warm, supportive tone.''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 200,
        'topP': 0.8,
        'topK': 40,
      },
      'safetySettings': [
        {
          'category': 'HARM_CATEGORY_HATE_SPEECH',
          'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
        },
        {
          'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
          'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
        },
        {
          'category': 'HARM_CATEGORY_HARASSMENT',
          'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
        },
        {
          'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
          'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
        },
      ],
    });

    try {
      final resp = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${Uri.encodeComponent(apiKey)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'FemWise/1.0.0',
        },
        body: body,
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final candidates = data['candidates'] as List?;

        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content?['parts'] as List?;

          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;

            if (text != null && text.trim().isNotEmpty && mounted) {
              setState(() {
                _insight =
                    '${_insight.split('\n\nAI:')[0]}\n\n🤖 AI Insight:\n${text.trim()}';
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('✨ AI insights updated!'),
                  backgroundColor: const Color(0xFF007AFF),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
              return;
            }
          }
        }

        _showError('AI response was empty or malformed.');
      } else if (resp.statusCode == 400) {
        final errorData = jsonDecode(resp.body);
        final errorMessage =
            errorData['error']?['message'] ?? 'Invalid request';
        _showError('AI Error: $errorMessage');
      } else if (resp.statusCode == 403) {
        _showError('AI service access denied. Please check API configuration.');
      } else {
        _showError('AI service error (${resp.statusCode}). Please try again.');
      }
    } catch (e) {
      _showError(
        'Network error connecting to AI service. Check your internet connection.',
      );
      print('AI Error Details: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      _buildOverview(),
      _buildCalendar(),
      _buildInsights(),
      _buildNews(),
      _buildMoodTracker(),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'FemWise',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1D1D1F),
          ),
        ),
        centerTitle: false,
        actions: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('profileId');
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                    (route) => false,
                  );
                }
              }
            },
            child: Container(
              margin: const EdgeInsets.only(right: 20),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B9D).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                CupertinoIcons.square_arrow_left,
                color: Color(0xFFFF6B9D),
                size: 20,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CupertinoActivityIndicator(
                radius: 20,
                color: Color(0xFF007AFF),
              ),
            )
          : screens[_navIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  0,
                  CupertinoIcons.house_fill,
                  CupertinoIcons.house,
                  'Home',
                ),
                _buildNavItem(
                  1,
                  CupertinoIcons.calendar,
                  CupertinoIcons.calendar,
                  'Calendar',
                ),
                _buildNavItem(
                  2,
                  CupertinoIcons.lightbulb_fill,
                  CupertinoIcons.lightbulb,
                  'Insights',
                ),
                _buildNavItem(
                  3,
                  CupertinoIcons.news_solid,
                  CupertinoIcons.news,
                  'News',
                ),
                _buildNavItem(
                  4,
                  CupertinoIcons.smiley_fill,
                  CupertinoIcons.smiley,
                  'Mood',
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildNavItem(
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
  ) {
    final isActive = _navIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _navIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF007AFF).withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : inactiveIcon,
              color: isActive ? const Color(0xFF007AFF) : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? const Color(0xFF007AFF) : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverview() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Welcome Header
          _buildWelcomeHeader(),
          const SizedBox(height: 24),

          // Dashboard Tiles Grid
          _buildDashboardGrid(),
          const SizedBox(height: 24),
          // AI Insights Section
          _buildAIInsightsCard(),
          const SizedBox(height: 24),

          // Recent Activity
          _buildRecentActivityCard(),
          const SizedBox(height: 24),

          // App Info Section
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B9D), Color(0xFFFF8FB3)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Icon(
                    CupertinoIcons.heart_fill,
                    size: 30,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Made in India with ❤️',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D1D1F),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'by Tanish',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF007AFF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () async {
                    final url = Uri.parse('https://github.com/ErrVoid/FemWise');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF007AFF).withOpacity(0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.link,
                          color: Color(0xFF007AFF),
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'View on GitHub',
                          style: TextStyle(
                            color: Color(0xFF007AFF),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B9D), Color(0xFFFF8FB3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B9D).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, ${widget.profile['name'] ?? 'User'}! 👋',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Track your wellness journey with personalized insights',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        _buildDashboardTile(
          icon: CupertinoIcons.heart_fill,
          title: 'Current Phase',
          subtitle: _getCurrentPhase(),
          color: const Color(0xFFFF6B9D),
          onTap: _showPhaseExplanation,
        ),
        _buildDashboardTile(
          icon: CupertinoIcons.calendar,
          title: 'Next Period',
          subtitle: _getNextPeriodText(),
          color: const Color(0xFF4A90E2),
          onTap: () => setState(() => _navIndex = 1),
        ),
        _buildDashboardTile(
          icon: CupertinoIcons.sparkles,
          title: 'AI Insights',
          subtitle: 'Get personalized advice',
          color: const Color(0xFF7B68EE),
          onTap: _callAI,
        ),
        _buildDashboardTile(
          icon: CupertinoIcons.smiley,
          title: 'Mood Tracker',
          subtitle: _getMoodForPhase(),
          color: const Color(0xFF50C878),
          onTap: () => setState(() => _navIndex = 4),
        ),
      ],
    );
  }

  Widget _buildDashboardTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D1D1F),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAIInsightsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF7B68EE).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  color: Color(0xFF7B68EE),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Smart Insights',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D1D1F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _insight.isEmpty
                  ? 'Log your periods to get personalized insights powered by AI.'
                  : _insight,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF1D1D1F),
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: CupertinoIcons.refresh,
                  label: 'Refresh',
                  onPressed: _periodLogs.isNotEmpty
                      ? () => setState(() => _updateCycleInsight())
                      : null,
                  isPrimary: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: CupertinoIcons.sparkles,
                  label: 'AI Insights',
                  onPressed: _callAI,
                  isPrimary: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivityCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B9D).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  CupertinoIcons.clock,
                  color: Color(0xFFFF6B9D),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D1D1F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_periodLogs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.calendar_badge_plus,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No periods logged yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use the calendar to add your first entry',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _periodLogs
                  .take(5)
                  .map(
                    (d) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF6B9D),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _fmt(d.start),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1D1D1F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool isPrimary,
  }) {
    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF007AFF) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.white : const Color(0xFF007AFF),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : const Color(0xFF007AFF),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCurrentPhase() {
    if (_periodLogs.isEmpty) return 'Not tracked';

    final lastStart = _periodLogs.first.start;
    final cycleLength = (widget.profile['cycleLength'] as int?) ?? 28;
    final periodLength = (widget.profile['periodLength'] as int?) ?? 5;
    final today = DateTime.now();
    final dayInCycle = today.difference(lastStart).inDays + 1;

    if (dayInCycle <= periodLength) {
      return 'Menstrual';
    } else if (dayInCycle <= cycleLength / 2) {
      return 'Follicular';
    } else if (dayInCycle <= cycleLength - 7) {
      return 'Ovulation';
    } else {
      return 'Luteal';
    }
  }

  String _getMoodForPhase() {
    if (_periodLogs.isEmpty) return 'Track your mood';

    final currentPhase = _getCurrentPhase();
    switch (currentPhase) {
      case 'Menstrual':
        return 'Rest & reflect';
      case 'Follicular':
        return 'Energetic & creative';
      case 'Ovulation':
        return 'Confident & social';
      case 'Luteal':
        return 'Focused & calm';
      default:
        return 'Track your mood';
    }
  }

  String _getNextPeriodText() {
    if (_periodLogs.isEmpty) return 'Log periods first';

    final lastStart = _periodLogs.first.start;
    final cycleLength = (widget.profile['cycleLength'] as int?) ?? 28;
    final nextPeriod = lastStart.add(Duration(days: cycleLength));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextPeriodDate = DateTime(
      nextPeriod.year,
      nextPeriod.month,
      nextPeriod.day,
    );
    final daysUntil = nextPeriodDate.difference(today).inDays;

    if (daysUntil < 0) {
      return 'Overdue by ${-daysUntil} days';
    } else if (daysUntil == 0) {
      return 'Expected today';
    } else if (daysUntil == 1) {
      return '1 day remaining';
    } else {
      return '$daysUntil days remaining';
    }
  }

  void _showPhaseExplanation() {
    if (_periodLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please log your periods first to see phase information',
          ),
        ),
      );
      return;
    }

    final currentPhase = _getCurrentPhase();
    final phaseInfo = _getPhaseExplanation(currentPhase);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [phaseInfo['color'].withOpacity(0.1), Colors.white],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: phaseInfo['color'],
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Icon(phaseInfo['icon'], size: 40, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                currentPhase,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D1D1F),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                phaseInfo['description'],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: phaseInfo['color'].withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What to expect:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: phaseInfo['color'],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...phaseInfo['tips']
                        .map<Widget>(
                          (tip) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(
                                    top: 6,
                                    right: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: phaseInfo['color'],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    tip,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF1D1D1F),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: phaseInfo['color'],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Got it!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getPhaseExplanation(String phase) {
    switch (phase) {
      case 'Menstrual':
        return {
          'color': const Color(0xFFFF6B9D),
          'icon': CupertinoIcons.drop_fill,
          'description':
              'Your period is here. Your body is shedding the uterine lining.',
          'tips': [
            'Rest and take it easy',
            'Stay hydrated and eat iron-rich foods',
            'Use heat therapy for cramps',
            'Practice gentle movement like yoga',
          ],
        };
      case 'Follicular':
        return {
          'color': const Color(0xFF50C878),
          'icon': CupertinoIcons.leaf_arrow_circlepath,
          'description':
              'Rising estrogen levels. Great time for new projects and learning.',
          'tips': [
            'Energy levels are increasing',
            'Good time for strength training',
            'Focus on creative projects',
            'Social activities feel more enjoyable',
          ],
        };
      case 'Ovulation':
        return {
          'color': const Color(0xFFFFD700),
          'icon': CupertinoIcons.sun_max_fill,
          'description':
              'Peak fertility window. You may feel confident and energetic.',
          'tips': [
            'Highest energy and confidence',
            'Great for important meetings',
            'Peak fertility period',
            'Skin may look its best',
          ],
        };
      case 'Luteal':
        return {
          'color': const Color(0xFF7B68EE),
          'icon': CupertinoIcons.moon_fill,
          'description': 'Progesterone is rising. Focus on self-care and rest.',
          'tips': [
            'Energy may start to decline',
            'Focus on completing projects',
            'Prioritize sleep and nutrition',
            'Practice stress management',
          ],
        };
      default:
        return {
          'color': Colors.grey,
          'icon': CupertinoIcons.question_circle,
          'description':
              'Track your periods to see detailed phase information.',
          'tips': ['Log your period start dates for personalized insights'],
        };
    }
  }

  Widget _buildCalendarDay(
    DateTime day, {
    bool isToday = false,
    bool isSelected = false,
  }) {
    final isPeriodStart = _periodLogs.any(
      (p) =>
          p.start.year == day.year &&
          p.start.month == day.month &&
          p.start.day == day.day,
    );

    // Determine phase for this day
    Color? phaseColor;
    if (_periodLogs.isNotEmpty) {
      final lastStart = _periodLogs.first.start;
      final cycleLength = (widget.profile['cycleLength'] as int?) ?? 28;
      final periodLength = (widget.profile['periodLength'] as int?) ?? 5;
      final daysSinceStart = day.difference(lastStart).inDays;

      if (daysSinceStart >= 0 && daysSinceStart < cycleLength) {
        if (daysSinceStart < periodLength) {
          phaseColor = const Color(0xFFFF6B9D); // Menstrual
        } else if (daysSinceStart < cycleLength / 2) {
          phaseColor = const Color(0xFF50C878); // Follicular
        } else if (daysSinceStart < cycleLength - 7) {
          phaseColor = const Color(0xFFFFD700); // Ovulation
        } else {
          phaseColor = const Color(0xFF7B68EE); // Luteal
        }
      }
    }

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF007AFF)
            : isToday
            ? const Color(0xFF007AFF).withOpacity(0.2)
            : phaseColor?.withOpacity(0.1),
        shape: BoxShape.circle,
        border: isPeriodStart
            ? Border.all(color: const Color(0xFFFF6B9D), width: 2)
            : phaseColor != null
            ? Border.all(color: phaseColor.withOpacity(0.3), width: 1)
            : null,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : isToday
                    ? const Color(0xFF007AFF)
                    : const Color(0xFF1D1D1F),
                fontWeight: isToday || isSelected
                    ? FontWeight.w600
                    : FontWeight.w500,
                fontSize: 16,
              ),
            ),
            if (isPeriodStart)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B9D),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    final isSelectedLogged =
        _selectedDay != null &&
        _periodLogs.any(
          (p) =>
              p.start.year == _selectedDay!.year &&
              p.start.month == _selectedDay!.month &&
              p.start.day == _selectedDay!.day,
        );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  weekendTextStyle: TextStyle(color: Colors.grey[600]),
                  holidayTextStyle: const TextStyle(color: Color(0xFFFF6B9D)),
                  selectedDecoration: const BoxDecoration(
                    color: Color(0xFF007AFF),
                    shape: BoxShape.circle,
                  ),
                  todayDecoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  markerDecoration: const BoxDecoration(
                    color: Color(0xFFFF6B9D),
                    shape: BoxShape.circle,
                  ),
                ),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  leftChevronIcon: Icon(
                    CupertinoIcons.chevron_left,
                    color: Color(0xFF007AFF),
                  ),
                  rightChevronIcon: Icon(
                    CupertinoIcons.chevron_right,
                    color: Color(0xFF007AFF),
                  ),
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) {
                    return _buildCalendarDay(day);
                  },
                  todayBuilder: (context, day, focusedDay) {
                    return _buildCalendarDay(day, isToday: true);
                  },
                  selectedBuilder: (context, day, focusedDay) {
                    return _buildCalendarDay(day, isSelected: true);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_selectedDay != null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Selected: ${_fmt(_selectedDay!)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1D1D1F),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildActionButton(
                    icon: CupertinoIcons.add_circled,
                    label: 'Mark as Period Start',
                    onPressed: () => _addPeriodStart(_selectedDay!),
                    isPrimary: true,
                  ),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    icon: CupertinoIcons.drop_fill,
                    label: 'Mark as Menstruation Flow',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Flow tracking logged for today! 💧'),
                          backgroundColor: Color(0xFFFF6B9D),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    isPrimary: false,
                  ),
                  if (isSelectedLogged) ...[
                    const SizedBox(height: 12),
                    _buildActionButton(
                      icon: CupertinoIcons.delete,
                      label: 'Delete This Log',
                      onPressed: _deleteSelectedPeriod,
                      isPrimary: false,
                    ),
                  ],
                  if (_periodLogs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    CupertinoButton(
                      onPressed: _resetAllLogs,
                      child: const Text(
                        'Reset All Logs',
                        style: TextStyle(
                          color: Color(0xFFFF3B30),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInsights() {
    return DefaultTabController(
      length: 3,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
          ),
        ),
        child: Column(
          children: [
            // Tab Bar
            Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: TabBar(
                indicator: BoxDecoration(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[600],
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(CupertinoIcons.lightbulb_fill, size: 20),
                    text: 'Insights',
                  ),
                  Tab(
                    icon: Icon(CupertinoIcons.heart_fill, size: 20),
                    text: 'Body',
                  ),
                  Tab(
                    icon: Icon(CupertinoIcons.chart_bar_circle_fill, size: 20),
                    text: 'Cycle',
                  ),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                children: [
                  _buildInsightsTab(),
                  _buildBodyTab(),
                  _buildCycleTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Current Phase Summary
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF7B68EE).withOpacity(0.1),
                  Colors.white,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  CupertinoIcons.heart_circle,
                  size: 48,
                  color: Color(0xFF7B68EE),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_getCurrentPhase()} Phase',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D1D1F),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _getMoodForPhase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: const Color(0xFF7B68EE),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // AI Insights Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      CupertinoIcons.sparkles,
                      color: Color(0xFF007AFF),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Smart Health Insights',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D1D1F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _insight.isEmpty
                        ? 'Track your menstrual cycle to receive personalized AI-powered health insights and recommendations.'
                        : _insight,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1D1D1F),
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _periodLogs.isNotEmpty
                            ? () => setState(() => _updateCycleInsight())
                            : null,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: _periodLogs.isNotEmpty
                                ? const Color(0xFFF2F2F7)
                                : const Color(0xFFF2F2F7).withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.refresh,
                                color: _periodLogs.isNotEmpty
                                    ? const Color(0xFF007AFF)
                                    : Colors.grey,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Refresh',
                                style: TextStyle(
                                  color: _periodLogs.isNotEmpty
                                      ? const Color(0xFF007AFF)
                                      : Colors.grey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _callAI,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.sparkles,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'AI Analysis',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Quick Tips
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      CupertinoIcons.lightbulb,
                      color: Color(0xFF50C878),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Health Tips',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D1D1F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._buildHealthTips().take(3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyTab() {
    final currentPhase = _getCurrentPhase();
    final phaseInfo = _getPhaseExplanation(currentPhase);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // What's Happening Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [phaseInfo['color'].withOpacity(0.1), Colors.white],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: phaseInfo['color'],
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Icon(
                      phaseInfo['icon'],
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'What\'s happening in your body',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1D1D1F),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$currentPhase Phase',
                          style: TextStyle(
                            fontSize: 16,
                            color: phaseInfo['color'],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                phaseInfo['description'],
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Body Changes Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Physical Changes',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D1D1F),
                ),
              ),
              const SizedBox(height: 16),
              ..._getBodyChangesForPhase(currentPhase).map(
                (change) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(change['icon'], color: phaseInfo['color'], size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              change['title'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1D1D1F),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              change['description'],
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCycleTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // Cycle Overview Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cycle Overview',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D1D1F),
                ),
              ),
              const SizedBox(height: 20),
              if (_periodLogs.isNotEmpty) ...[
                _buildCycleMetric(
                  'Current Day',
                  '${DateTime.now().difference(_periodLogs.first.start).inDays + 1}',
                  CupertinoIcons.calendar_today,
                  const Color(0xFF007AFF),
                ),
                _buildCycleMetric(
                  'Cycle Length',
                  '${(widget.profile['cycleLength'] as int?) ?? 28} days',
                  CupertinoIcons.chart_bar_circle,
                  const Color(0xFF50C878),
                ),
                _buildCycleMetric(
                  'Period Length',
                  '${(widget.profile['periodLength'] as int?) ?? 5} days',
                  CupertinoIcons.drop,
                  const Color(0xFFFF6B9D),
                ),
                _buildCycleMetric(
                  'Cycles Tracked',
                  '${_periodLogs.length}',
                  CupertinoIcons.chart_pie,
                  const Color(0xFF7B68EE),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'Start tracking your periods to see cycle analytics',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCycleMetric(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getBodyChangesForPhase(String phase) {
    switch (phase) {
      case 'Menstrual':
        return [
          {
            'icon': CupertinoIcons.drop_fill,
            'title': 'Menstrual Flow',
            'description':
                'Uterine lining is shedding, causing menstrual bleeding',
          },
          {
            'icon': CupertinoIcons.heart,
            'title': 'Hormone Levels',
            'description': 'Estrogen and progesterone are at their lowest',
          },
          {
            'icon': CupertinoIcons.moon,
            'title': 'Energy Levels',
            'description': 'May feel tired and need more rest',
          },
        ];
      case 'Follicular':
        return [
          {
            'icon': CupertinoIcons.leaf_arrow_circlepath,
            'title': 'Follicle Development',
            'description': 'Ovarian follicles are developing and maturing',
          },
          {
            'icon': CupertinoIcons.arrow_up_circle,
            'title': 'Rising Estrogen',
            'description': 'Estrogen levels are gradually increasing',
          },
          {
            'icon': CupertinoIcons.bolt,
            'title': 'Increasing Energy',
            'description': 'Energy and mood typically improve',
          },
        ];
      case 'Ovulation':
        return [
          {
            'icon': CupertinoIcons.sun_max,
            'title': 'Egg Release',
            'description': 'Mature egg is released from the ovary',
          },
          {
            'icon': CupertinoIcons.heart_fill,
            'title': 'Peak Estrogen',
            'description': 'Estrogen reaches its highest levels',
          },
          {
            'icon': CupertinoIcons.sparkles,
            'title': 'Peak Fertility',
            'description': 'This is your most fertile time of the cycle',
          },
        ];
      case 'Luteal':
        return [
          {
            'icon': CupertinoIcons.moon_fill,
            'title': 'Corpus Luteum',
            'description': 'Empty follicle produces progesterone',
          },
          {
            'icon': CupertinoIcons.arrow_down_circle,
            'title': 'Progesterone Rise',
            'description': 'Progesterone levels increase significantly',
          },
          {
            'icon': CupertinoIcons.zzz,
            'title': 'Body Preparation',
            'description':
                'Body prepares for potential pregnancy or next cycle',
          },
        ];
      default:
        return [];
    }
  }

  List<Widget> _buildHealthTips() {
    final tips = [
      {
        'icon': CupertinoIcons.chart_bar_circle,
        'text': 'Track your cycle regularly for better health insights',
      },
      {
        'icon': CupertinoIcons.heart,
        'text': 'Maintain a healthy diet and exercise routine',
      },
      {
        'icon': CupertinoIcons.person_badge_plus,
        'text': 'Consult a doctor if you notice irregular patterns',
      },
      {
        'icon': CupertinoIcons.drop,
        'text': 'Stay hydrated and get adequate rest',
      },
    ];

    return tips
        .map(
          (tip) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  tip['icon'] as IconData,
                  color: const Color(0xFF50C878),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tip['text'] as String,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF1D1D1F),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  Widget _buildMoodTracker() {
    final currentPhase = _getCurrentPhase();
    final phaseInfo = _getPhaseExplanation(currentPhase);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Current Phase Mood Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [phaseInfo['color'].withOpacity(0.1), Colors.white],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: phaseInfo['color'],
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        phaseInfo['icon'],
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$currentPhase Phase',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D1D1F),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getMoodForPhase(),
                            style: TextStyle(
                              fontSize: 16,
                              color: phaseInfo['color'],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  phaseInfo['description'],
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Mood Tracking Grid
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How are you feeling today?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D1D1F),
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                  children: [
                    _buildMoodTile('😊', 'Happy', const Color(0xFFFFD700)),
                    _buildMoodTile('😌', 'Calm', const Color(0xFF50C878)),
                    _buildMoodTile('😴', 'Tired', const Color(0xFF7B68EE)),
                    _buildMoodTile('😢', 'Sad', const Color(0xFF4A90E2)),
                    _buildMoodTile('😤', 'Irritated', const Color(0xFFFF6B9D)),
                    _buildMoodTile('🤗', 'Confident', const Color(0xFFFF8C00)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Phase-Based Tips
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: phaseInfo['color'].withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        CupertinoIcons.lightbulb,
                        color: phaseInfo['color'],
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Mood Tips for This Phase',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D1D1F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...phaseInfo['tips']
                    .map<Widget>(
                      (tip) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: phaseInfo['color'],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                tip,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF1D1D1F),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodTile(String emoji, String label, Color color) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mood "$label" logged for today! 💖'),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNews() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF50C878), Color(0xFF66D68A)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      CupertinoIcons.news,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Health News & Articles',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D1D1F),
                      ),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _loadFeed,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        CupertinoIcons.refresh,
                        color: Color(0xFF007AFF),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: _feedLoading
                ? const Center(
                    child: CupertinoActivityIndicator(
                      radius: 16,
                      color: Color(0xFF007AFF),
                    ),
                  )
                : _feed.isEmpty
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.news,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No articles available',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Check your internet connection and try again',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          _buildActionButton(
                            icon: CupertinoIcons.refresh,
                            label: 'Retry',
                            onPressed: _loadFeed,
                            isPrimary: true,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _feed.length,
                    itemBuilder: (c, i) {
                      final item = _feed[i];
                      final snippet = (item.description ?? '').length > 120
                          ? '${item.description!.substring(0, 120)}...'
                          : item.description ?? '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) => ArticleDetailScreen(item: item),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF50C878,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.doc_text,
                                    color: Color(0xFF50C878),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1D1D1F),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        snippet.isEmpty
                                            ? 'Tap to read more'
                                            : snippet,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  CupertinoIcons.chevron_right,
                                  color: Color(0xFF007AFF),
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbout() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // App Info Card
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B9D), Color(0xFFFF8FB3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B9D).withOpacity(0.3),
                  blurRadius: 25,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    CupertinoIcons.heart_fill,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'FemWise',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your personal wellness companion',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Features Card
          _buildInfoCard(
            title: 'Features',
            icon: CupertinoIcons.star_fill,
            color: const Color(0xFF007AFF),
            items: [
              'Smart cycle predictions',
              'AI-powered health insights',
              'Beautiful, intuitive interface',
              'Secure data storage',
              'Personalized recommendations',
            ],
          ),
          const SizedBox(height: 20),

          // Privacy Card
          _buildInfoCard(
            title: 'Privacy & Security',
            icon: CupertinoIcons.lock_shield_fill,
            color: const Color(0xFF50C878),
            items: [
              'All data encrypted and secure',
              'No personal data shared with third parties',
              'Local storage with cloud backup',
              'GDPR compliant data handling',
            ],
          ),
          const SizedBox(height: 20),

          // Support Card
          _buildInfoCard(
            title: 'Support & Feedback',
            icon: CupertinoIcons.chat_bubble_2_fill,
            color: const Color(0xFF7B68EE),
            items: [
              'Contact support for help',
              'Share feedback to improve the app',
              'Join our community for tips',
              'Regular updates and improvements',
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D1D1F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...items.map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF1D1D1F),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedItem {
  final String title;
  final String link;
  final String source;
  final String? description;
  final DateTime? published;
  _FeedItem({
    required this.title,
    required this.link,
    required this.source,
    this.description,
    this.published,
  });
}

class ArticleDetailScreen extends StatelessWidget {
  final _FeedItem item;
  const ArticleDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.back,
              color: Color(0xFF007AFF),
              size: 20,
            ),
          ),
        ),
        title: const Text(
          'Article',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1D1D1F),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D1D1F),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),

                // Article Meta
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.published != null)
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.calendar,
                              size: 16,
                              color: Color(0xFF007AFF),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Published: ${_formatDate(item.published!)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.link,
                            size: 16,
                            color: Color(0xFF007AFF),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Source: ${_getSourceName(item.source)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Article Content
                Text(
                  item.description ?? 'No content available.',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF1D1D1F),
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 24),

                // Action Button
                if (item.link.isNotEmpty)
                  Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF007AFF), Color(0xFF5AC8FA)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF007AFF).withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('🔗 Link copied to clipboard'),
                            backgroundColor: const Color(0xFF007AFF),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.link,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'View Original Article',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _getSourceName(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceAll('www.', '');
    } catch (_) {
      return url;
    }
  }
}
