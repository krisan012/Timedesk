import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

final themeFadeKey = GlobalKey<ThemeFadeState>();

/// Reveals a new theme in a circle that grows from where it was switched.
/// A snapshot of the old frame sits on top and a growing hole is cut in it.
/// Lerping ThemeData instead mixes old and new colors, because widgets that
/// branch on brightness flip at the halfway point.
class ThemeFade extends StatefulWidget {
  final Widget child;
  const ThemeFade({Key? key, required this.child}) : super(key: key);

  @override
  State<ThemeFade> createState() => ThemeFadeState();
}

class ThemeFadeState extends State<ThemeFade>
    with SingleTickerProviderStateMixin {
  final _boundaryKey = GlobalKey();
  late final _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  late final _progress =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
  ui.Image? _snapshot;
  Offset? _origin;

  Future<void> run(Future<void> Function() changeTheme,
      {Offset? origin}) async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null || _snapshot != null) {
      await changeTheme();
      return;
    }
    final image = await boundary.toImage(
        pixelRatio: MediaQuery.of(context).devicePixelRatio);
    // The last run left the value at 1: start with the snapshot whole.
    _controller.value = 0;
    setState(() {
      _snapshot = image;
      _origin = origin;
    });
    await changeTheme();
    await WidgetsBinding.instance.endOfFrame;
    await _controller.forward(from: 0);
    if (!mounted) return;
    setState(() => _snapshot = null);
    image.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _boundaryKey, child: widget.child),
        if (_snapshot != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipPath(
                clipper: _HoleClipper(_progress, _origin),
                child: RawImage(image: _snapshot, fit: BoxFit.fill),
              ),
            ),
          ),
      ],
    );
  }
}

/// Everything except a circle around [origin] whose radius grows with
/// [progress] until it covers the farthest corner.
class _HoleClipper extends CustomClipper<Path> {
  final Animation<double> progress;
  final Offset? origin;
  _HoleClipper(this.progress, this.origin) : super(reclip: progress);

  @override
  Path getClip(Size size) {
    final o = origin ?? size.center(Offset.zero);
    final maxRadius = [
      o,
      Offset(size.width - o.dx, o.dy),
      Offset(o.dx, size.height - o.dy),
      Offset(size.width - o.dx, size.height - o.dy),
    ].map((d) => d.distance).reduce(math.max);
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: o, radius: maxRadius * progress.value));
  }

  @override
  bool shouldReclip(_HoleClipper old) => old.origin != origin;
}

/// Changes the theme with the reveal when the main window hosts one.
Future<void> changeThemeWithFade(Future<void> Function() changeTheme,
    {Offset? origin}) {
  final state = themeFadeKey.currentState;
  return state == null
      ? changeTheme()
      : state.run(changeTheme, origin: origin);
}
