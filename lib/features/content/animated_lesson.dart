import 'dart:async';
import 'package:flutter/material.dart';

/// Both GIF codecs and image sequences pause with the same explicit controls.
class AnimatedLesson extends StatefulWidget {
  final List<String> urls;
  final int frameMs;
  final bool gif;
  const AnimatedLesson({
    super.key,
    required this.urls,
    this.frameMs = 1000,
    this.gif = false,
  });
  @override
  State<AnimatedLesson> createState() => _AnimatedLessonState();
}

class _AnimatedLessonState extends State<AnimatedLesson>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _index = 0;
  bool _playing = false;
  bool _initialized = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _playing = !MediaQuery.disableAnimationsOf(context);
      _schedule();
    } else if (MediaQuery.disableAnimationsOf(context) && _playing) {
      _playing = false;
      _timer?.cancel();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_playing || widget.gif || widget.urls.length < 2) return;
    _timer = Timer.periodic(Duration(milliseconds: widget.frameMs), (_) {
      if (mounted) setState(() => _index = (_index + 1) % widget.urls.length);
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedLesson oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.urls.isEmpty || _index >= widget.urls.length) _index = 0;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        _playing = false;
        _timer?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return const Text('Animação sem imagens.');
    final image = TickerMode(
      enabled: _playing,
      child: Image.network(
        widget.urls[_index],
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        fit: BoxFit.contain,
        semanticLabel: widget.gif
            ? 'Animação da aula'
            : 'Quadro ${_index + 1} de ${widget.urls.length}',
        errorBuilder: (_, _, _) => const Center(
          child: Text(
            'Imagem indisponível. Reabra a aula para tentar novamente.',
          ),
        ),
      ),
    );
    final controls = Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        TextButton(
          onPressed: () => setState(() {
            _playing = !_playing;
            _schedule();
          }),
          child: Text(_playing ? 'Pausar' : 'Reproduzir'),
        ),
        if (!widget.gif) ...[
          TextButton(
            onPressed: () => setState(() {
              _playing = false;
              _timer?.cancel();
              _index = (_index - 1 + widget.urls.length) % widget.urls.length;
            }),
            child: const Text('Anterior'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _playing = false;
              _timer?.cancel();
              _index = (_index + 1) % widget.urls.length;
            }),
            child: const Text('Próximo'),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${_index + 1} / ${widget.urls.length}'),
          ),
        ],
      ],
    );
    // Inside the lesson player the parent gives a bounded height, so the
    // frames take every available pixel while the controls keep their size.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: constraints.hasBoundedHeight
            ? MainAxisSize.max
            : MainAxisSize.min,
        children: [
          if (constraints.hasBoundedHeight)
            Expanded(child: image)
          else
            AspectRatio(aspectRatio: 4 / 3, child: image),
          controls,
        ],
      ),
    );
  }
}
