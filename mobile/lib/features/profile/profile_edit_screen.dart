import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/providers.dart';
import '../../core/config.dart';
import '../../core/cache/session_cache.dart';
import '../../core/cache/profile_cache.dart';
import '../../core/cache/user_registry_cache.dart';
import '../../core/localization/sushi_localizations.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _photoPath;
  bool _saving = false;
  static const _uzPrefix = '+998';
  static const _fallbackAvatar = 'assets/images/profile_default.png';
  static const _fallbackFemaleAvatar = 'assets/images/profile_female.png';

  @override
  void initState() {
    super.initState();
    final session = ref.read(userSessionProvider);
    _nameController.text = session?.fullName ?? '';
    final phone = session?.phone ?? '';
    _phoneController.text = _stripUzPrefix(phone);
    _photoPath = ref.read(profilePhotoProvider);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final result =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (result == null) return;
    setState(() => _photoPath = result.path);
  }

  Future<void> _save() async {
    final t = SushiLocalizations.of(context);
    final session = ref.read(userSessionProvider);
    if (session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.t('session_not_found_login_again'))),
        );
      }
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.t('please_enter_full_name'))),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final phoneDigits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
      final phone = phoneDigits.isEmpty ? '' : '$_uzPrefix$phoneDigits';
      if (useBackend && phoneDigits.length != 9) {
        throw Exception('${t.t('phone')}: 9 digits required');
      }
      UserSession updated = UserSession(
        userId: session.userId,
        phone: phone,
        fullName: name,
        preferredLang: session.preferredLang,
        gender: session.gender,
        accessToken: session.accessToken,
      );
      if (useBackend) {
        final auth = ref.read(authRepositoryProvider);
        if (session.userId > 0 && session.accessToken.trim().isNotEmpty) {
          final response = await auth.updateProfile(
            phone: phone,
            fullName: name,
            preferredLang: session.preferredLang,
          );
          updated = UserSession(
            userId: response.userId,
            phone: response.phone,
            fullName: response.fullName,
            preferredLang: response.preferredLang,
            gender: session.gender,
            accessToken: response.accessToken,
          );
        } else {
          final challenge = await auth.requestLoginCode(
            phone: phone,
            fullName: name,
            preferredLang: session.preferredLang,
          );
          String code = challenge.debugCode.trim();
          if (code.isEmpty) {
            code = (await _promptOtpCode(t, phone: phone) ?? '').trim();
          }
          if (code.isEmpty) {
            throw Exception(t.t('otp_code_required'));
          }
          final response = await auth.verifyLoginCode(
            phone: phone,
            code: code,
            fullName: name,
            preferredLang: session.preferredLang,
          );
          updated = UserSession(
            userId: response.userId,
            phone: response.phone,
            fullName: response.fullName,
            preferredLang: response.preferredLang,
            gender: session.gender,
            accessToken: response.accessToken,
          );
        }
      }
      ref.read(userSessionProvider.notifier).state = updated;
      await SessionCache().save(updated.toJson());
      await UserRegistryCache().upsert(
        phone: updated.phone,
        name: updated.fullName,
        gender: updated.gender,
      );

      ref.read(profilePhotoProvider.notifier).state = _photoPath;
      await ProfileCache().savePhotoPath(_photoPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.t('profile_saved_successfully'))),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Profile save failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_authErrorMessage(t, e))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                  border: const OutlineInputBorder(),
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

  String _authErrorMessage(SushiLocalizations t, Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        final detail = '${data['detail']}'.trim();
        if (detail.isNotEmpty) return detail;
      }
      final message = error.message?.trim() ?? '';
      if (message.isNotEmpty) return message;
      return t.t('save_failed');
    }
    final text = error.toString().trim();
    if (text.isNotEmpty && text != 'Exception') {
      return text.replaceFirst('Exception: ', '');
    }
    return t.t('save_failed');
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final session = ref.watch(userSessionProvider);
    final fallbackAvatar =
        session?.gender == 'female' ? _fallbackFemaleAvatar : _fallbackAvatar;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F6),
      appBar: AppBar(
        title: Text(t.t('profile_edit_title')),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.white,
                  backgroundImage: _photoPath != null &&
                          _photoPath!.isNotEmpty &&
                          File(_photoPath!).existsSync()
                      ? FileImage(File(_photoPath!)) as ImageProvider
                      : AssetImage(fallbackAvatar),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: InkWell(
                    onTap: _pickImage,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                          color: Color(0xFFEE482B), shape: BoxShape.circle),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(t.t('full_name'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4E4A46))),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: t.t('full_name'),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE6DFDA))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE6DFDA))),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: Color(0xFFEE482B), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(t.t('phone'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4E4A46))),
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
              hintText: t.t('phone'),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE6DFDA))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE6DFDA))),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: Color(0xFFEE482B), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEE482B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '...' : t.t('save'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  String _stripUzPrefix(String phone) {
    if (phone.startsWith(_uzPrefix)) {
      return phone.substring(_uzPrefix.length);
    }
    return phone;
  }
}
