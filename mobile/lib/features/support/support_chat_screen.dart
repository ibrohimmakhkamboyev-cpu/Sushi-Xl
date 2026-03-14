import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/sushi_localizations.dart';
import '../../core/state/providers.dart';

class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key});

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen> {
  final _messageCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = SushiLocalizations.of(context);
    final locale = ref.watch(localeProvider);
    ref
        .read(supportCenterProvider.notifier)
        .ensureBackendSynced(lang: locale.languageCode);
    final supportConfig = ref.watch(supportCenterProvider);
    final session = ref.watch(userSessionProvider) ?? UserSession.guest();
    final threadId = ref.read(supportInboxProvider.notifier).threadIdForSession(
          session,
        );
    final messages = ref.watch(supportThreadMessagesProvider(threadId));

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F5),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFFEE482B),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          supportConfig.chatLabel.trim().isEmpty
                              ? t.t('chat_with_us')
                              : supportConfig.chatLabel,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF231816),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          supportConfig.chatSubtitle.trim().isEmpty
                              ? t.t('support_chat_subtitle')
                              : supportConfig.chatSubtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF847C80),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? _EmptyChatState(label: t.t('support_chat_empty'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final item = messages[index];
                        final isUser = item.sender == 'user';
                        final isEscalation = item.sender == 'bot_escalation';
                        return _ChatBubble(
                          text: item.text,
                          label: isUser
                              ? t.t('you')
                              : (item.senderLabel.isEmpty
                                  ? t.t(isEscalation
                                      ? 'support_admin_badge'
                                      : 'support_app_badge')
                                  : item.senderLabel),
                          isUser: isUser,
                          highlight: isEscalation,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        controller: _messageCtrl,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: t.t('support_message_hint'),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEE482B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: _sending
                          ? null
                          : () => _sendMessage(
                                context,
                                session: session,
                              ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage(
    BuildContext context, {
    required UserSession session,
  }) async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(supportInboxProvider.notifier)
          .sendUserMessage(session: session, message: text);
      _messageCtrl.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SushiLocalizations.of(context).t('support_chat_send_failed'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            height: 1.5,
            color: Color(0xFF847C80),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.text,
    required this.label,
    required this.isUser,
    this.highlight = false,
  });

  final String text;
  final String label;
  final bool isUser;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isUser
        ? const Color(0xFFEE482B)
        : (highlight ? const Color(0xFFFFE7DF) : Colors.white);
    final textColor = isUser ? Colors.white : const Color(0xFF2A1E1C);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFD9B3A5).withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isUser
                    ? Colors.white.withOpacity(0.84)
                    : const Color(0xFF8A7E80),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
