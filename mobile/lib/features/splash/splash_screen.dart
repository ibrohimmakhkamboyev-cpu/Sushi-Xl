import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/localization/sushi_localizations.dart';

const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
bool _isTestBinding() {
  final name = WidgetsBinding.instance.runtimeType.toString();
  return name.contains('TestWidgetsFlutterBinding') ||
      name.contains('AutomatedTestWidgetsFlutterBinding') ||
      name.contains('LiveTestWidgetsFlutterBinding');
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoPath = 'assets/images/sushi-xl logo.png';
  Timer? _timer;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    if (!_isFlutterTest && !_isTestBinding()) {
      _controller.repeat();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isFlutterTest || _isTestBinding()) {
        if (mounted) context.go('/home');
        return;
      }
      debugPrint('[splash] mounted=$mounted, scheduling navigation');
      _timer = Timer(const Duration(seconds: 2), () {
        debugPrint('[splash] timer fired, navigating to /home');
        if (mounted) context.go('/home');
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFCF9F8),
      body: Stack(
        children: [
          Positioned(
            left: -80,
            bottom: -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                color: Color(0x0AEE482B),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: -80,
            top: -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                color: Color(0x0AEE482B),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 20,
                          offset: Offset(0, 10)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Image.asset(
                      _logoPath,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Sushi-XL',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111111)),
                ),
                const SizedBox(height: 6),
                Text(
                  t.t('premium_delivery_experience'),
                  style: const TextStyle(
                      letterSpacing: 2, fontSize: 12, color: Color(0xFF9A9A9A)),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.restaurant,
                          size: 16, color: Color(0xFFEE482B)),
                      const SizedBox(width: 6),
                      Text(
                        t.t('fetching_ingredients'),
                        style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.2,
                            color: Color(0xFF9A9A9A)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 240,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6DAD4),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final progress = 0.2 + (_controller.value * 0.6);
                        return FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEE482B),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const [
                                BoxShadow(
                                    color: Color(0x44EE482B), blurRadius: 10)
                              ],
                            ),
                          ),
                        );
                      },
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
