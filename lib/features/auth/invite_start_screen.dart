import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/invite_link.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';

class InviteStartScreen extends ConsumerStatefulWidget {
  const InviteStartScreen({super.key, required this.link});
  final InviteAuthLink? link;

  @override
  ConsumerState<InviteStartScreen> createState() => _InviteStartScreenState();
}

class _InviteStartScreenState extends ConsumerState<InviteStartScreen> {
  bool _busy = false;
  bool _verified = false;
  String? _error;

  @override
  void didUpdateWidget(covariant InviteStartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link?.tokenHash != widget.link?.tokenHash ||
        oldWidget.link?.token != widget.link?.token ||
        oldWidget.link?.type != widget.link?.type) {
      _verified = false;
      _error = null;
    }
  }

  Future<void> _continue() async {
    final link = widget.link;
    if (_busy || link == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_verified) {
        try {
          await ref.read(authRepositoryProvider).verifyInviteToken(link);
        } catch (_) {
          if (mounted) {
            setState(
              () => _error =
                  'Este link expirou ou já foi utilizado. Peça um novo convite a quem enviou.',
            );
          }
          return;
        }
        if (!mounted || widget.link?.identity != link.identity) return;
        _verified = true;
      }
      await ref.read(sessionProvider.notifier).reload();
      if (mounted && widget.link?.identity == link.identity) {
        context.go('/invite/accept?token=${link.token}');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Link confirmado. Não foi possível carregar sua conta. Tente continuar novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Seu convite')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: SvgIcon(AppIcons.mail, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              widget.link == null
                  ? 'Link de convite inválido'
                  : 'Bem-vindo ao EducaDor',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              widget.link == null
                  ? 'Abra o link completo ou peça um novo convite a quem enviou.'
                  : 'Continue para confirmar seu acesso. Depois, você poderá aceitar o convite e criar sua senha.',
              style: AdminStyles.body,
            ),
            const SizedBox(height: 24),
            if (widget.link != null)
              PrimaryButton(
                _busy ? 'Confirmando...' : 'Continuar',
                onPressed: _busy ? null : _continue,
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ],
        ),
      ),
    ),
  );
}
