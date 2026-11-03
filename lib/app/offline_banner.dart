import 'package:flutter/material.dart';

import 'connectivity/connectivity.dart' as connectivity;

/// Browser connectivity is only a hint; HTTP/Auth failures never imply offline.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({
    super.key,
    required this.child,
    this.changes,
    this.initial,
  });

  final Widget child;
  final Stream<bool>? changes;
  final bool? initial;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late final Stream<bool> _changes =
      widget.changes ?? connectivity.offlineChanges();

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _changes,
    initialData: widget.initial ?? connectivity.isOffline,
    builder: (context, snapshot) => Column(
      children: [
        if (snapshot.data == true)
          Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sem conexão com a internet. Reconecte-se para acessar seus dados.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    ),
  );
}
