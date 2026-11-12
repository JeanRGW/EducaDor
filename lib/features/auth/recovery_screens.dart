import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/recovery_link.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';

const recoveryConfirmation =
    'Se houver uma conta com este e-mail, você receberá um link para criar uma nova senha.';

class RecoverPasswordScreen extends ConsumerStatefulWidget {
  const RecoverPasswordScreen({super.key});
  @override
  ConsumerState<RecoverPasswordScreen> createState() =>
      _RecoverPasswordScreenState();
}

class _RecoverPasswordScreenState extends ConsumerState<RecoverPasswordScreen> {
  final email = TextEditingController();
  bool busy = false;
  bool sent = false;
  int remaining = 0;
  Timer? cooldown;
  String? error;

  @override
  void dispose() {
    cooldown?.cancel();
    email.dispose();
    super.dispose();
  }

  Future<void> request() async {
    if (busy || remaining > 0) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.text.trim())) {
      setState(() => error = 'Informe um e-mail válido.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(authRepositoryProvider).requestPasswordReset(email.text);
      if (!mounted) return;
      setState(() {
        sent = true;
        remaining = 60;
      });
      cooldown?.cancel();
      cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => remaining = (60 - timer.tick).clamp(0, 60));
        if (remaining == 0) timer.cancel();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível solicitar o link agora. Tente novamente mais tarde.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _RecoveryPage(
    appBar: 'Recuperar senha',
    title: sent ? 'Confira seu e-mail' : 'Recupere seu acesso',
    description: sent
        ? recoveryConfirmation
        : 'Informe o e-mail da sua conta para receber um link seguro.',
    icon: AppIcons.mail,
    children: [
      if (!sent) ...[
        TextField(
          controller: email,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.send,
          decoration: const InputDecoration(labelText: 'E-mail'),
          onSubmitted: (_) => request(),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          busy ? 'Enviando...' : 'Enviar link de recuperação',
          onPressed: busy ? null : request,
        ),
      ] else ...[
        Text(
          'Confira também a caixa de spam. Se não receber, fale com o administrador da plataforma.',
          style: AdminStyles.body(context),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: busy || remaining > 0 ? null : request,
          child: Text(
            busy
                ? 'Enviando...'
                : remaining > 0
                ? 'Reenviar em ${remaining}s'
                : 'Reenviar link',
          ),
        ),
      ],
      if (error != null) _RecoveryError(error!),
      const SizedBox(height: 8),
      TextButton(
        onPressed: busy ? null : () => context.go('/login'),
        child: const Text('Voltar para entrar'),
      ),
    ],
  );
}

class RecoveryLinkScreen extends ConsumerStatefulWidget {
  const RecoveryLinkScreen({super.key, required this.tokenHash});
  final String? tokenHash;
  @override
  ConsumerState<RecoveryLinkScreen> createState() => _RecoveryLinkScreenState();
}

class _RecoveryLinkScreenState extends ConsumerState<RecoveryLinkScreen> {
  bool busy = false;
  bool verified = false;
  String? error;

  @override
  void didUpdateWidget(covariant RecoveryLinkScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tokenHash != widget.tokenHash) {
      verified = false;
      error = null;
    }
  }

  Future<void> continueRecovery() async {
    final token = widget.tokenHash;
    if (busy || token == null || !isRecoveryTokenHash(token)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!verified) {
        try {
          await ref.read(authRepositoryProvider).verifyRecoveryToken(token);
        } catch (_) {
          if (mounted && widget.tokenHash == token) {
            setState(
              () => error =
                  'Este link é inválido, expirou ou já foi utilizado. Solicite um novo link.',
            );
          }
          return;
        }
        if (!mounted || widget.tokenHash != token) return;
        setState(() => verified = true);
      }
      await ref.read(sessionProvider.notifier).reload();
      if (mounted && widget.tokenHash == token) context.go('/reset-password');
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Link confirmado. Não foi possível carregar sua conta. Tente continuar novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _RecoveryPage(
    appBar: 'Recuperar senha',
    title: widget.tokenHash == null
        ? 'Link de recuperação inválido'
        : 'Crie uma nova senha',
    description: widget.tokenHash == null
        ? 'Abra o link recebido por e-mail ou solicite um novo.'
        : 'Continue para confirmar o link e escolher sua nova senha. Se sua conta usa autenticação em duas etapas, o código também será solicitado.',
    icon: AppIcons.key,
    children: [
      if (widget.tokenHash != null)
        PrimaryButton(
          busy
              ? 'Verificando...'
              : verified
              ? 'Continuar recuperação'
              : 'Continuar',
          onPressed: busy ? null : continueRecovery,
        ),
      if (error != null) _RecoveryError(error!),
      const SizedBox(height: 12),
      TextButton(
        onPressed: busy ? null : () => context.go('/recover'),
        child: const Text('Solicitar novo link'),
      ),
    ],
  );
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  bool passwordSaved = false;
  bool setupCompleted = false;
  bool finished = false;
  String? error;

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!passwordSaved &&
        (password.text.length < 8 || password.text != confirm.text)) {
      setState(
        () => error = 'Use pelo menos 8 caracteres e confirme a mesma senha.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!passwordSaved) {
        await ref
            .read(authRepositoryProvider)
            .updateRecoveredPassword(password.text);
        if (!mounted) return;
        setState(() {
          passwordSaved = true;
          password.clear();
          confirm.clear();
        });
      }
      if (!setupCompleted) {
        await ref.read(authRepositoryProvider).completeRecoveredPassword();
        if (!mounted) return;
        setState(() => setupCompleted = true);
      }
      await ref.read(sessionProvider.notifier).logout();
      if (mounted) setState(() => finished = true);
    } catch (_) {
      if (mounted) {
        if (setupCompleted && ref.read(sessionProvider).value == null) {
          setState(() => finished = true);
        } else {
          setState(
            () => error = passwordSaved
                ? 'Senha alterada. Não foi possível finalizar. Tente finalizar novamente.'
                : 'Não foi possível salvar a senha. Escolha uma senha diferente da anterior ou solicite outro link.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (finished) {
      return _RecoveryPage(
        appBar: 'Recuperar senha',
        title: 'Senha atualizada',
        description: 'Entre novamente usando sua nova senha.',
        icon: AppIcons.checkCircle,
        children: [
          PrimaryButton('Entrar', onPressed: () => context.go('/login')),
        ],
      );
    }
    if (session.isLoading) {
      return const _RecoveryPage(
        appBar: 'Recuperar senha',
        title: 'Preparando sua conta',
        description: 'Aguarde enquanto verificamos sua sessão.',
        icon: AppIcons.key,
        children: [SizedBox(height: 160)],
      );
    }
    final current = session.value;
    if (current?.recoveringPassword != true || current!.needsMfa) {
      return _RecoveryPage(
        appBar: 'Recuperar senha',
        title: 'Abra o link de recuperação',
        description:
            'Solicite um novo link para redefinir sua senha com segurança.',
        icon: AppIcons.key,
        children: [
          PrimaryButton(
            'Solicitar novo link',
            onPressed: () => context.go('/recover'),
          ),
        ],
      );
    }
    return _RecoveryPage(
      appBar: 'Recuperar senha',
      title: passwordSaved
          ? 'Finalize a recuperação'
          : 'Escolha sua nova senha',
      description: passwordSaved
          ? 'Sua senha já foi alterada. Finalize para entrar novamente.'
          : 'Use pelo menos 8 caracteres e uma senha diferente da anterior.',
      icon: AppIcons.lock,
      children: [
        if (!passwordSaved) ...[
          TextField(
            controller: password,
            enabled: !busy,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'Nova senha'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: confirm,
            enabled: !busy,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: 'Confirmar nova senha',
            ),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 20),
        ],
        if (error != null) _RecoveryError(error!),
        PrimaryButton(
          busy
              ? 'Salvando...'
              : passwordSaved
              ? 'Finalizar recuperação'
              : 'Salvar nova senha',
          onPressed: busy ? null : submit,
        ),
      ],
    );
  }
}

class _RecoveryPage extends StatelessWidget {
  const _RecoveryPage({
    required this.appBar,
    required this.title,
    required this.description,
    required this.icon,
    required this.children,
  });
  final String appBar;
  final String title;
  final String description;
  final String icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Theme(
    data: AdminStyles.formTheme(Theme.of(context)),
    child: Scaffold(
      appBar: AppBar(
        title: Text(appBar),
        titleSpacing: 20,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AppCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.successSurface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SvgIcon(
                            icon,
                            size: 24,
                            color: context.successForeground,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: AdminStyles.pageTitle(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(description, style: AdminStyles.body(context)),
                      const SizedBox(height: 24),
                      ...children,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RecoveryError extends StatelessWidget {
  const _RecoveryError(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: AdminStyles.body(
          context,
        ).copyWith(color: context.dangerForeground),
      ),
    ),
  );
}
