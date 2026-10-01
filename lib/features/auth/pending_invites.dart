import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import 'onboarding_screens.dart';

class PendingInvitesSection extends ConsumerStatefulWidget {
  final Role role;
  final String? companyId;
  final Map<String, String> companyNames;

  const PendingInvitesSection({
    super.key,
    required this.role,
    this.companyId,
    this.companyNames = const {},
  });

  @override
  ConsumerState<PendingInvitesSection> createState() =>
      _PendingInvitesSectionState();
}

class _PendingInvitesSectionState extends ConsumerState<PendingInvitesSection> {
  late Future<List<PendingInvitation>> _pending;
  PendingInvitation? _busyInvite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _pending = ref
        .read(invitationRepositoryProvider)
        .pending(role: widget.role, companyId: widget.companyId);
  }

  Future<void> _regenerate(PendingInvitation invite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gerar novo link?'),
        content: const Text(
          'O link anterior deixará de funcionar. Compartilhe o novo link apenas '
          'com a pessoa convidada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Gerar novo link'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyInvite = invite);
    try {
      final link = await ref
          .read(invitationRepositoryProvider)
          .regenerate(invite);
      if (!mounted) return;
      await showInviteLink(context, link);
      if (mounted) setState(_load);
    } catch (_) {
      if (mounted) {
        setState(_load);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível gerar o link. Tente novamente.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyInvite = null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PendingInvitation>>(
    future: _pending,
    builder: (context, snapshot) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Convites pendentes'),
        if (snapshot.hasError)
          const Text('Não foi possível carregar os convites.'),
        if (!snapshot.hasData && !snapshot.hasError)
          const AppCard(
            child: Row(
              children: [
                CircleAvatar(backgroundColor: AppColors.chipBg, radius: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InvitePlaceholder(width: 140, height: 16),
                      SizedBox(height: 8),
                      _InvitePlaceholder(width: 200, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (snapshot.hasData && snapshot.data!.isEmpty)
          const Text('Nenhum convite pendente.'),
        for (final invite in snapshot.data ?? <PendingInvitation>[]) ...[
          _PendingInviteCard(
            invite: invite,
            companyName: invite.companyId != null && widget.companyId == null
                ? widget.companyNames[invite.companyId] ?? 'Empresa'
                : null,
            busy: _busyInvite == invite,
            onRegenerate: _busyInvite == null
                ? () => _regenerate(invite)
                : null,
          ),
          const SizedBox(height: 10),
        ],
      ],
    ),
  );
}

class _PendingInviteCard extends StatelessWidget {
  final PendingInvitation invite;
  final String? companyName;
  final bool busy;
  final VoidCallback? onRegenerate;

  const _PendingInviteCard({
    required this.invite,
    required this.companyName,
    required this.busy,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final name = invite.name?.trim();
    final hasName = name != null && name.isNotEmpty;
    final title = hasName ? name : invite.email;
    final initials = hasName
        ? name.split(RegExp(r'\s+')).take(2).map((part) => part[0]).join()
        : invite.email.substring(0, 1);
    final company = companyName == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SvgIcon(
                AppIcons.building,
                size: 16,
                color: AppColors.successDarkGreen,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  companyName!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.navy),
                ),
              ),
            ],
          );
    final action = OutlinedButton.icon(
      onPressed: onRegenerate,
      icon: SvgIcon(
        AppIcons.key,
        size: 16,
        color: busy ? AppColors.textMuted : AppColors.primary,
      ),
      label: Text(busy ? 'Gerando...' : 'Gerar novo link'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 520;
          final identity = Row(
            children: [
              AvatarBadge(initials.toUpperCase(), size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    if (hasName) ...[
                      const SizedBox(height: 2),
                      Text(
                        invite.email,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.navy),
                      ),
                    ],
                    if (wide && company != null) ...[
                      const SizedBox(height: 6),
                      company,
                    ],
                  ],
                ),
              ),
            ],
          );
          if (wide) {
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 16),
                action,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: company == null
                      ? WrapAlignment.end
                      : WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [?company, action],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InvitePlaceholder extends StatelessWidget {
  final double width;
  final double height;

  const _InvitePlaceholder({required this.width, required this.height});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.chipBg,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
