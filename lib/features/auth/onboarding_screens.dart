import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';

class ContextSelectionScreen extends ConsumerStatefulWidget {
  const ContextSelectionScreen({super.key});

  @override
  ConsumerState<ContextSelectionScreen> createState() =>
      _ContextSelectionScreenState();
}

class _ContextSelectionScreenState
    extends ConsumerState<ContextSelectionScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).value;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escolher perfil'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: const Text('Sair'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Olá, ${session.user.fullName}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text('Como você deseja acessar o EducaDOR?'),
          const SizedBox(height: 24),
          if (session.contexts.isEmpty)
            const AppCard(
              child: Text(
                'Ainda não há perfis disponíveis. '
                'Peça um convite ao administrador.',
              ),
            ),
          for (final access in session.contexts) ...[
            AppCard(
              onTap: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await ref.read(sessionProvider.notifier).select(access);
                        if (context.mounted) {
                          context.go(ref.read(sessionProvider).value!.homePath);
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Este perfil não está disponível.'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      access.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SvgIcon(AppIcons.chevronRight, color: AppColors.primary),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class AcceptInviteScreen extends ConsumerStatefulWidget {
  final String token;
  const AcceptInviteScreen({super.key, required this.token});

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(invitationRepositoryProvider).accept(widget.token);
      final session = await ref.read(sessionProvider.notifier).reload();
      if (!mounted) return;
      context.go(
        session?.needsPassword == true ? '/set-password' : '/contexts',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Convite inválido, expirado ou destinado a outro e-mail.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Aceitar convite')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Confirme seu convite para adicionar este perfil à sua conta.',
          ),
          const SizedBox(height: 16),
          if (widget.token.isEmpty) const Text('Link de convite inválido.'),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 16),
          if (auth.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (auth.value == null)
            PrimaryButton(
              'Entrar para aceitar',
              onPressed: widget.token.isEmpty
                  ? null
                  : () {
                      final target = Uri(
                        path: '/invite/accept',
                        queryParameters: {'token': widget.token},
                      ).toString();
                      context.go(
                        Uri(
                          path: '/login',
                          queryParameters: {'redirect': target},
                        ).toString(),
                      );
                    },
            )
          else
            PrimaryButton(
              _busy ? 'Aceitando...' : 'Aceitar convite',
              onPressed: _busy || widget.token.isEmpty ? null : _accept,
            ),
        ],
      ),
    );
  }
}

class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 8 || _password.text != _confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Use pelo menos 8 caracteres e confirme a mesma senha.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(_password.text);
      final session = await ref.read(sessionProvider.notifier).reload();
      if (mounted) context.go(session?.homePath ?? '/login');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível atualizar a senha. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(sessionProvider);
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.value == null) {
      return Scaffold(body: Center(child: PrimaryButton('Entrar',
        onPressed: () => context.go('/login'))));
    }
    return Scaffold(
    appBar: AppBar(title: const Text('Criar senha')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Crie uma senha para acessar todos os seus perfis.'),
        const SizedBox(height: 20),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Nova senha'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirm,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirmar senha'),
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          _busy ? 'Salvando...' : 'Salvar senha',
          onPressed: _busy ? null : _submit,
        ),
      ],
    ),
    );
  }
}

class SessionErrorScreen extends ConsumerWidget {
  const SessionErrorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Conexão indisponível')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Não foi possível carregar seus perfis. Verifique a conexão e tente novamente.'),
        const SizedBox(height: 20),
        PrimaryButton('Tentar novamente', onPressed: () {
          ref.invalidate(sessionProvider);
          context.go('/splash');
        }),
      ]))),
  );
}

Future<void> showInviteLink(BuildContext context, String link) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Convite criado'),
      content: const Text(
        'Compartilhe o link por um canal privado. '
        'Ele expira em breve e dá acesso à conta do convidado.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fechar'),
        ),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copiado. Compartilhe com segurança.'),
                ),
              );
            }
          },
          child: const Text('Copiar link'),
        ),
      ],
    ),
  );
}
