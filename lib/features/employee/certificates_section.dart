import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/employee_providers.dart';
import '../../data/repositories/repositories.dart';
import '../../shared/widgets/admin_styles.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/common.dart';
import '../gestor/widgets.dart' show DataSkeleton, DataErrorCard;
import 'widgets.dart';

class CertificatesSection extends ConsumerStatefulWidget {
  final bool compact;
  const CertificatesSection({super.key, this.compact = false});
  @override
  ConsumerState<CertificatesSection> createState() =>
      _CertificatesSectionState();
}

class _CertificatesSectionState extends ConsumerState<CertificatesSection> {
  int _offset = 0;
  String? _downloading;
  EmployeeScope? _scope;
  Future<void> _download(EarnedCertificate certificate) async {
    if (_downloading != null) return;
    setState(() => _downloading = certificate.id);
    try {
      await ref
          .read(certificateDocumentRepositoryProvider)
          .download(certificate);
    } catch (_) {
      if (mounted) {
        employeeMessage(
          context,
          'Não foi possível baixar o certificado. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(employeeScopeProvider);
    if (scope != _scope) {
      _scope = scope;
      _offset = 0;
    }
    final pages = [
      for (var offset = 0; offset <= _offset; offset += 50)
        ref.watch(employeeCertificatesProvider((scope: scope, offset: offset))),
    ];
    final items = [for (final page in pages) ...?page.asData?.value.items];
    final total = pages.first.asData?.value.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < pages.length; i++)
          if (pages[i].hasError)
            DataErrorCard(
              message: 'Não foi possível carregar certificados.',
              retry: () => ref.invalidate(
                employeeCertificatesProvider((scope: scope, offset: i * 50)),
              ),
            ),
        if (pages.any((page) => page.isLoading)) const DataSkeleton(),
        if (total == 0)
          const AppCard(
            child: Text(
              'Conclua um curso e emita seu primeiro certificado.',
              style: AdminStyles.body,
            ),
          ),
        for (final certificate in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: widget.compact ? 6 : 12,
              ),
              child: Row(
                children: [
                  const SvgIcon(
                    AppIcons.award,
                    color: AppColors.successDarkGreen,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          certificate.courseTitle,
                          style: AdminStyles.cardTitle,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${employeeDate(certificate.issuedAt.toLocal())} · ID: ${certificate.code}',
                          style: AdminStyles.fieldLabel.copyWith(
                            fontSize: widget.compact ? 11 : 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    style: widget.compact
                        ? IconButton.styleFrom(
                            backgroundColor: AppColors.successBgSoft,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          )
                        : null,
                    tooltip: 'Baixar certificado',
                    onPressed: _downloading == null
                        ? () => _download(certificate)
                        : null,
                    icon: _downloading == certificate.id
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const SvgIcon(
                            AppIcons.download,
                            color: AppColors.successDarkGreen,
                            size: 20,
                          ),
                  ),
                ],
              ),
            ),
          ),
        if (total != null &&
            items.length < total &&
            pages.last.asData?.value.items.length == 50)
          TextButton(
            onPressed: () => setState(() => _offset += 50),
            child: const Text('Carregar mais certificados'),
          ),
      ],
    );
  }
}
