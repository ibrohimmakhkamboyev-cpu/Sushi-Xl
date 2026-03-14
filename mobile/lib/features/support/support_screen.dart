import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/sushi_localizations.dart';
import '../../core/state/providers.dart';

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  static const _bg = Color(0xFFF7F4F5);
  static const _primary = Color(0xFFEE482B);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = SushiLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    ref
        .read(supportCenterProvider.notifier)
        .ensureBackendSynced(lang: locale.languageCode);
    final config = ref.watch(supportCenterProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _primary,
                    size: 28,
                  ),
                ),
                Expanded(
                  child: Text(
                    t.t('support_help'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF231816),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _SupportActionCard(
                    icon: Icons.call_rounded,
                    iconTint: const Color(0xFFE84A4A),
                    label: config.callLabel.trim().isEmpty
                        ? t.t('call_support')
                        : config.callLabel,
                    onTap: () => _callSupport(
                      context,
                      phoneNumber: config.phoneNumber,
                      failedLabel: t.t('support_call_failed'),
                      copiedLabel: t.t('support_call_copied'),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _SupportActionCard(
                    icon: Icons.chat_bubble_rounded,
                    iconTint: const Color(0xFF4A7DE8),
                    label: config.chatLabel.trim().isEmpty
                        ? t.t('chat_with_us')
                        : config.chatLabel,
                    onTap: () => context.push('/support/chat'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              t.t('common_questions'),
              style: const TextStyle(
                fontSize: 13,
                letterSpacing: 2,
                color: Color(0xFF988C8E),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...config.faqs.map((faq) => _FaqTile(item: faq)),
          ],
        ),
      ),
    );
  }

  Future<void> _callSupport(
    BuildContext context, {
    required String phoneNumber,
    required String failedLabel,
    required String copiedLabel,
  }) async {
    final rawPhone = phoneNumber.trim();
    final dialablePhone = _normalizeDialablePhone(rawPhone);
    if (dialablePhone.isEmpty) return;
    final launched = await _launchDialer(dialablePhone);
    if (launched || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: rawPhone));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$failedLabel $copiedLabel $rawPhone')),
    );
  }

  Future<bool> _launchDialer(String phoneNumber) async {
    final candidates = <Uri>[
      Uri.parse('tel:$phoneNumber'),
    ];
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      candidates.insert(0, Uri.parse('telprompt:$phoneNumber'));
    }

    for (final uri in candidates) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  String _normalizeDialablePhone(String phoneNumber) {
    final trimmed = phoneNumber.trim();
    if (trimmed.isEmpty) return '';
    final hasLeadingPlus = trimmed.startsWith('+');
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return hasLeadingPlus ? '+$digits' : digits;
  }
}

class _SupportActionCard extends StatelessWidget {
  const _SupportActionCard({
    required this.icon,
    required this.iconTint,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconTint;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fontSize = _fontSizeForLabel(label);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        height: 156,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.92)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFD9B3A5).withOpacity(0.14),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconTint.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconTint, size: 28),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Text(
                label,
                maxLines: 3,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF231816),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _fontSizeForLabel(String value) {
    final length = value.trim().length;
    if (length >= 25) return 13;
    if (length >= 18) return 14.5;
    return 17;
  }
}

class _FaqTile extends StatefulWidget {
  const _FaqTile({required this.item});

  final SupportFaqItem item;

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.96)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFD9B3A5).withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
            title: Text(
              widget.item.question,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF231816),
              ),
            ),
            trailing: Icon(
              _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: const Color(0xFF9C9091),
              size: 30,
            ),
            onTap: () => setState(() => _open = !_open),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Text(
                widget.item.answer,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Color(0xFF625658),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
