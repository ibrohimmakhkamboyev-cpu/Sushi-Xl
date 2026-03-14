import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../core/localization/sushi_localizations.dart';
import '../../core/state/providers.dart';
import '../../core/config.dart';
import '../../core/cache/favorites_cache.dart';
import '../../core/cache/session_cache.dart';
import '../../core/cache/location_cache.dart';
import '../../core/cache/registration_reminder_cache.dart';
import '../../core/cache/user_registry_cache.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  String _lang = 'ru';
  String _gender = 'male';
  bool _loading = false;
  static const _uzPrefix = '+998';

  @override
  void initState() {
    super.initState();
    // Force default language to Russian on first load.
    _lang = 'ru';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(localeProvider.notifier).state = const Locale('ru');
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<String?> _promptOtpCode(
    SushiLocalizations t, {
    required String phone,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(t.t('login_required')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t.t('otp_code_prompt')}\n$phone'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: t.t('otp_code_label'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t.t('cancel')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(t.t('continue')),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _upgradeSessionWithOtp({
    required String phone,
    required String name,
    required String lang,
  }) async {
    final t = SushiLocalizations.of(context);
    final auth = ref.read(authRepositoryProvider);
    final challenge = await auth
        .requestLoginCode(
          phone: phone,
          fullName: name,
          preferredLang: lang,
        )
        .timeout(const Duration(seconds: 8));
    String code = challenge.debugCode.trim();
    if (code.isEmpty) {
      if (!mounted) return;
      final entered = await _promptOtpCode(t, phone: phone);
      code = (entered ?? '').trim();
    }
    if (code.isEmpty) {
      return;
    }
    final res = await auth
        .verifyLoginCode(
          phone: phone,
          code: code,
          fullName: name,
          preferredLang: lang,
        )
        .timeout(const Duration(seconds: 8));
    final serverSession = UserSession(
      userId: res.userId,
      phone: res.phone,
      fullName: res.fullName,
      preferredLang: res.preferredLang,
      gender: _gender,
      accessToken: res.accessToken,
    );
    ref.read(userSessionProvider.notifier).state = serverSession;
    await ref.read(cartProvider.notifier).loadFromCache();
    await ref.read(localOrderHistoryProvider.notifier).loadFromCache();
    if (serverSession.userId > 0) {
      await FavoritesCache().clear(scope: 'uid_${serverSession.userId}');
    }
    await ref.read(favoritesProvider.notifier).clear();
    await SessionCache().save(serverSession.toJson());
    await UserRegistryCache().upsert(
      phone: serverSession.phone,
      name: serverSession.fullName,
      gender: serverSession.gender,
    );
  }

  Future<void> _continue() async {
    final t = SushiLocalizations.of(context);
    debugPrint('[onboarding] continue tapped');
    setState(() => _loading = true);
    final phoneDigits = _phoneController.text.trim();
    final phone = phoneDigits.isEmpty ? '' : '$_uzPrefix$phoneDigits';
    final name = _nameController.text.trim();
    if (useBackend) {
      if (phoneDigits.length != 9) {
        _showMessage('${t.t('phone')}: 9 digits required');
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
      if (name.isEmpty) {
        _showMessage(t.t('please_enter_full_name'));
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }
    }
    ref.read(deliveryLocationProvider.notifier).state = null;
    await LocationCache().clear(scope: 'guest');
    final localSession = UserSession(
      userId: 0,
      phone: phone,
      fullName: name,
      preferredLang: _lang,
      gender: _gender,
      accessToken: '',
    );
    if (phone.isNotEmpty && name.isNotEmpty) {
      await RegistrationReminderCache().disableForever();
    }
    debugPrint(
        '[onboarding] saving local session: ${localSession.phone} / ${localSession.fullName}');
    await ref.read(cartProvider.notifier).clear();
    ref.read(userSessionProvider.notifier).state = localSession;
    await ref.read(cartProvider.notifier).loadFromCache();
    await ref.read(localOrderHistoryProvider.notifier).loadFromCache();
    await FavoritesCache().clear(scope: 'phone_$phone');
    await ref.read(favoritesProvider.notifier).clear();
    await SessionCache().save(localSession.toJson());
    await UserRegistryCache().upsert(
      phone: localSession.phone,
      name: localSession.fullName,
      gender: localSession.gender,
    );
    ref.read(localeProvider.notifier).state = Locale(_lang);

    if (useBackend && phone.isNotEmpty && name.isNotEmpty) {
      try {
        await _upgradeSessionWithOtp(phone: phone, name: name, lang: _lang);
      } catch (error) {
        _showMessage(_authErrorMessage(t, error));
        return;
      } finally {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
    } else {
      if (mounted) {
        setState(() => _loading = false);
      }
    }

    if (mounted) {
      debugPrint('[onboarding] navigating to /home');
      context.go('/home');
    }
  }

  String _authErrorMessage(SushiLocalizations t, Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        final detail = '${data['detail']}'.trim();
        if (detail.isNotEmpty) return detail;
      }
      final message = error.message?.trim() ?? '';
      if (message.isNotEmpty) return message;
    }
    return t.t('generic_error');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    const bg = Color(0xFF0B0B0B);
    const surface = Color(0xFFF8F6F6);
    const border = Color(0xFFE6DFDA);
    return Scaffold(
      backgroundColor: surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE6DFDA)),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 14,
                      color: Color(0xFF1B1B1B),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    _BrandLogo(),
                    const SizedBox(height: 12),
                    Text(
                      t.t('onboarding_title'),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.t('onboarding_subtitle'),
                      style: const TextStyle(color: Color(0xFFBDBDBD)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.t('select_language'),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1B1B1B)),
                    ),
                    const SizedBox(height: 10),
                    _LanguageFlags(
                      value: _lang,
                      onChanged: (value) {
                        setState(() => _lang = value);
                        ref.read(localeProvider.notifier).state = Locale(value);
                        ref.invalidate(menuProvider);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.t('phone'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4E4A46)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(9),
                      ],
                      decoration: InputDecoration(
                        prefixText: '$_uzPrefix ',
                        hintText: '90 123 45 67',
                        filled: true,
                        fillColor: Colors.white,
                        hintStyle: const TextStyle(color: Color(0xFF9A9A9A)),
                        prefixStyle: const TextStyle(
                            color: Color(0xFF1B1B1B),
                            fontWeight: FontWeight.w700),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: border)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: Color(0xFFEE482B), width: 1.5),
                        ),
                      ),
                      style: const TextStyle(color: Color(0xFF1B1B1B)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t.t('full_name'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4E4A46)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Akmal Karimov',
                        filled: true,
                        fillColor: Colors.white,
                        hintStyle: const TextStyle(color: Color(0xFF9A9A9A)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: border)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: Color(0xFFEE482B), width: 1.5),
                        ),
                      ),
                      style: const TextStyle(color: Color(0xFF1B1B1B)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t.t('gender'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4E4A46)),
                    ),
                    const SizedBox(height: 8),
                    _GenderSelector(
                      value: _gender,
                      onChanged: (value) => setState(() => _gender = value),
                      t: t,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 54,
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEE482B),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _loading ? null : _continue,
                        child: Text(_loading ? '...' : t.t('continue'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
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
}

class _BrandLogo extends StatelessWidget {
  static const _logoPath = 'assets/images/sushi-xl logo.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 20, offset: Offset(0, 10)),
        ],
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Image.asset(
          _logoPath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _LanguageFlags extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _LanguageFlags({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FlagCard(
            flag: '🇺🇿',
            label: 'O‘zbek',
            selected: value == 'uz',
            onTap: () => onChanged('uz'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FlagCard(
            flag: '🇷🇺',
            label: 'Русский',
            selected: value == 'ru',
            onTap: () => onChanged('ru'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FlagCard(
            flag: '🇬🇧',
            label: 'English',
            selected: value == 'en',
            onTap: () => onChanged('en'),
          ),
        ),
      ],
    );
  }
}

class _FlagCard extends StatelessWidget {
  final String flag;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FlagCard(
      {required this.flag,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFEFEA) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
                  selected ? const Color(0xFFEE482B) : const Color(0xFFE6DFDA)),
        ),
        child: Column(
          children: [
            Text(flag, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: selected
                    ? const Color(0xFF1B1B1B)
                    : const Color(0xFF6F6F6F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenderSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final SushiLocalizations t;
  const _GenderSelector(
      {required this.value, required this.onChanged, required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _GenderButton(
            label: t.t('male'),
            selected: value == 'male',
            onTap: () => onChanged('male'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _GenderButton(
            label: t.t('female'),
            selected: value == 'female',
            onTap: () => onChanged('female'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _GenderButton(
            label: t.t('other'),
            selected: value == 'other',
            onTap: () => onChanged('other'),
          ),
        ),
      ],
    );
  }
}

class _GenderButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _GenderButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFEFEA) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color:
                  selected ? const Color(0xFFEE482B) : const Color(0xFFE6DFDA)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color:
                  selected ? const Color(0xFF1B1B1B) : const Color(0xFF6F6F6F),
            ),
          ),
        ),
      ),
    );
  }
}
