import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/authenticator_launcher.dart';
import '../../data/repositories/repositories.dart';
import '../../data/session/session_controller.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';

class MfaChallengeScreen extends ConsumerStatefulWidget {
  const MfaChallengeScreen({super.key});
  @override
  ConsumerState<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends ConsumerState<MfaChallengeScreen> {
  final code = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> verify() async {
    if (busy) return;
    if (code.text.length != 6) {
      setState(() => error = 'Digite os 6 dígitos do aplicativo autenticador.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      final factors = await repo.totpFactors();
      if (factors.isEmpty) throw StateError('No TOTP factor');
      await repo.verifyTotp(factors.first, code.text);
      await ref.read(sessionProvider.notifier).reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível verificar o código. Confira e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SecurityLayout(
    title: 'Verificação em duas etapas',
    children: [
      const _SecurityIntro(
        title: 'Confirme que é você',
        description:
            'Abra seu aplicativo autenticador e digite o código para continuar.',
      ),
      const SizedBox(height: 24),
      AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CodeInput(
              controller: code,
              enabled: !busy,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => verify(),
            ),
            if (error != null) _SecurityError(error!),
            const SizedBox(height: 20),
            PrimaryButton(
              busy ? 'Verificando...' : 'Verificar',
              color: context.successForeground,
              onPressed: busy || code.text.length != 6 ? null : verify,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Sem acesso ao autenticador? Entre em contato com o suporte da plataforma.',
        style: AdminStyles.body(context),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: busy
            ? null
            : () => ref.read(sessionProvider.notifier).logout(),
        child: const Text('Sair'),
      ),
    ],
  );
}

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  final code = TextEditingController();
  List<String>? factors;
  ({String id, String secret, String qr, String uri})? enrollment;
  bool busy = false;
  bool copied = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) setState(() => error = null);
    try {
      final result = await ref.read(authRepositoryProvider).totpFactors();
      if (mounted) setState(() => factors = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Não foi possível carregar a segurança da conta.',
        );
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível concluir. Confira o código e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> copyKey(String secret) async {
    try {
      await Clipboard.setData(ClipboardData(text: secret));
      if (mounted) setState(() => copied = true);
    } catch (_) {
      notice(
        'Não foi possível copiar. Selecione a chave para copiá-la manualmente.',
      );
    }
  }

  Future<void> openAuthenticator(String uri) async {
    final opened = await ref.read(authenticatorLauncherProvider).open(uri);
    if (!opened) {
      notice(
        'Não foi possível abrir um autenticador. Copie a chave ou escaneie o QR code.',
      );
    }
  }

  Future<void> cancelEnrollment(String id) => run(() async {
    await ref.read(authRepositoryProvider).removeTotp(id);
    if (mounted) {
      setState(() {
        enrollment = null;
        copied = false;
        code.clear();
      });
    }
  });

  Future<void> confirmEnrollment(String id) => run(() async {
    await ref.read(authRepositoryProvider).verifyTotp(id, code.text);
    if (mounted) {
      setState(() {
        enrollment = null;
        copied = false;
        code.clear();
      });
    }
    await load();
    await ref.read(sessionProvider.notifier).reload();
  });

  Future<void> disable(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desativar verificação?'),
        content: const Text('Sua conta ficará protegida apenas pela senha.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await run(() async {
      await ref.read(authRepositoryProvider).removeTotp(id);
      await load();
      await ref.read(sessionProvider.notifier).reload();
    });
  }

  @override
  Widget build(BuildContext context) => _SecurityLayout(
    title: 'Segurança da conta',
    onBack: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(ref.read(sessionProvider).value?.homePath ?? '/contexts');
      }
    },
    children: [
      _SecurityIntro(
        title: 'Verificação em duas etapas',
        description:
            'Adicione uma camada de proteção à sua conta com um aplicativo autenticador.',
        status: enrollment != null
            ? 'Em configuração'
            : factors == null
            ? null
            : factors!.isEmpty
            ? 'Desativada'
            : 'Ativada',
        enabled: factors?.isNotEmpty == true,
      ),
      const SizedBox(height: 24),
      if (factors == null && error == null) const _SecurityLoading(),
      if (factors != null && enrollment == null)
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                factors!.isEmpty
                    ? 'Proteja seu próximo acesso'
                    : 'Autenticador conectado',
                style: AdminStyles.formTitle(context),
              ),
              const SizedBox(height: 8),
              Text(
                factors!.isEmpty
                    ? 'Além da senha, você usará um código temporário do aplicativo ao entrar.'
                    : 'Um código do aplicativo será solicitado ao entrar. Mantenha acesso ao seu autenticador.',
                style: AdminStyles.body(context),
              ),
              const SizedBox(height: 20),
              if (factors!.isEmpty)
                PrimaryButton(
                  busy ? 'Preparando...' : 'Ativar',
                  color: context.successForeground,
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final result = await ref
                              .read(authRepositoryProvider)
                              .enrollTotp();
                          if (mounted) {
                            setState(() {
                              enrollment = result;
                              copied = false;
                            });
                          }
                        }),
                ),
              for (final id in factors!)
                OutlinedButton(
                  onPressed: busy ? null : () => disable(id),
                  child: const Text('Desativar autenticador'),
                ),
            ],
          ),
        ),
      if (enrollment case final setup?) ...[
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _StepTitle(number: '1', title: 'Configure o autenticador'),
              const SizedBox(height: 12),
              Text(
                'Escaneie o QR code com seu aplicativo autenticador.',
                style: AdminStyles.body(context),
              ),
              const SizedBox(height: 20),
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      label: 'QR code para configurar o autenticador',
                      child: SvgPicture.string(
                        setup.qr.replaceFirst('data:image/svg+xml;utf-8,', ''),
                        width: 184,
                        height: 184,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: busy ? null : () => openAuthenticator(setup.uri),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.successForeground,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: SvgIcon(
                  AppIcons.key,
                  size: 18,
                  color: context.successForeground,
                ),
                label: const Text('Abrir autenticador'),
              ),
              const SizedBox(height: 8),
              Text(
                'Neste dispositivo, tente abrir o aplicativo diretamente. Se ele não abrir, use o QR code ou a chave abaixo.',
                style: AdminStyles.emptyState(context),
              ),
              const Divider(height: 32),
              Text(
                'Prefere configurar manualmente?',
                style: AdminStyles.cardTitle(context),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  setup.secret.replaceAllMapped(
                    RegExp(r'.{4}(?=.)'),
                    (match) => '${match[0]} ',
                  ),
                  style: AdminStyles.fieldText(context).copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1.2,
                    height: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: busy ? null : () => copyKey(setup.secret),
                  icon: SvgIcon(
                    copied ? AppIcons.check : AppIcons.copy,
                    size: 18,
                    color: context.successForeground,
                  ),
                  label: Text(copied ? 'Chave copiada' : 'Copiar chave'),
                ),
              ),
              Text(
                'Mantenha esta chave em segredo. Não envie capturas do QR code ou da chave.',
                style: AdminStyles.emptyState(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _StepTitle(number: '2', title: 'Confirme a ativação'),
              const SizedBox(height: 12),
              Text(
                'Digite os 6 dígitos exibidos no aplicativo para concluir.',
                style: AdminStyles.body(context),
              ),
              const SizedBox(height: 16),
              _CodeInput(
                controller: code,
                enabled: !busy,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (code.text.length == 6) confirmEnrollment(setup.id);
                },
              ),
              if (error != null) _SecurityError(error!),
              const SizedBox(height: 20),
              PrimaryButton(
                busy ? 'Confirmando...' : 'Confirmar ativação',
                color: context.successForeground,
                onPressed: busy || code.text.length != 6
                    ? null
                    : () => confirmEnrollment(setup.id),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : () => cancelEnrollment(setup.id),
          child: const Text('Cancelar'),
        ),
      ],
      if (error != null && enrollment == null) ...[
        _SecurityError(error!),
        if (factors == null)
          TextButton(onPressed: load, child: const Text('Tentar novamente')),
      ],
    ],
  );
}

class _SecurityLayout extends StatelessWidget {
  const _SecurityLayout({
    required this.title,
    required this.children,
    this.onBack,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Theme(
    data: AdminStyles.formTheme(Theme.of(context)),
    child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
        leading: onBack == null ? null : BackButton(onPressed: onBack),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SecurityIntro extends StatelessWidget {
  const _SecurityIntro({
    required this.title,
    required this.description,
    this.status,
    this.enabled = false,
  });
  final String title;
  final String description;
  final String? status;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.successSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SvgIcon(
          AppIcons.shield,
          color: context.successForeground,
          size: 24,
        ),
      ),
      const SizedBox(height: 16),
      Semantics(
        header: true,
        child: Text(title, style: AdminStyles.pageTitle(context)),
      ),
      const SizedBox(height: 8),
      Text(description, style: AdminStyles.body(context)),
      if (status != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: enabled
                ? context.successSurface
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: enabled
                  ? context.successSurface
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            status!,
            style: AdminStyles.fieldLabel(context).copyWith(
              color: enabled
                  ? context.successForeground
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ],
  );
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.number, required this.title});
  final String number;
  final String title;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.successSurface,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: AdminStyles.cardTitle(
              context,
            ).copyWith(color: context.successForeground),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: AdminStyles.formTitle(context))),
      ],
    ),
  );
}

class _CodeInput extends StatelessWidget {
  const _CodeInput({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Código de autenticação', style: AdminStyles.fieldLabel(context)),
      const SizedBox(height: 8),
      Semantics(
        label: 'Código de autenticação',
        child: TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: AdminStyles.fieldText(
            context,
          ).copyWith(fontSize: 20, letterSpacing: 6),
          decoration: const InputDecoration(hintText: '000000'),
          onChanged: onChanged,
          onSubmitted: onSubmitted,
        ),
      ),
    ],
  );
}

class _SecurityLoading extends StatelessWidget {
  const _SecurityLoading();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carregando configurações de segurança',
    child: AppCard(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        height: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 18,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Spacer(),
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SecurityError extends StatelessWidget {
  const _SecurityError(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: AdminStyles.body(
          context,
        ).copyWith(color: context.dangerForeground),
      ),
    ),
  );
}
