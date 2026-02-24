import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models.dart';
import 'packer.dart';

// Shared number formatter — strips unnecessary trailing zeros.
String _fmt(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

class OptimizePage extends StatefulWidget {
  final List<RectType> types;
  const OptimizePage({super.key, required this.types});

  @override
  State<OptimizePage> createState() => _OptimizePageState();
}

class _OptimizePageState extends State<OptimizePage> {
  PackResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      try {
        final r = findOptimalPacking(widget.types);
        if (mounted) setState(() { _result = r; _loading = false; });
      } catch (e) {
        if (mounted) setState(() { _error = e.toString(); _loading = false; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Optimal Packing',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text('Error: $_error',
                      style: const TextStyle(color: Colors.redAccent)))
              : _result == null
                  ? const Center(
                      child: Text('No valid packing found.',
                          style: TextStyle(color: Colors.white54)))
                  : Column(
                      children: [
                        _InfoBar(result: _result!, types: widget.types),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: LayoutBuilder(
                              builder: (ctx, cst) {
                                final screen = MediaQuery.of(ctx).size;
                                final ppu = math.min(screen.width * 0.85,
                                        screen.height * 0.65) /
                                    _result!.squareSize;
                                return CustomPaint(
                                  size: Size(cst.maxWidth, cst.maxHeight),
                                  painter: _PackPainter(
                                      _result!, widget.types, ppu),
                                );
                              },
                            ),
                          ),
                        ),
                        _Legend(types: widget.types),
                        const SizedBox(height: 12),
                      ],
                    ),
    );
  }
}

// ── Info bar ────────────────────────────────────────────────────────────────

class _InfoBar extends StatelessWidget {
  final PackResult result;
  final List<RectType> types;
  const _InfoBar({required this.result, required this.types});

  @override
  Widget build(BuildContext context) {
    final total = result.placed.length;
    final sz = result.squareSize;
    final usedArea =
        types.fold(0.0, (s, t) => s + t.width * t.height * t.count);
    final squareArea = sz * sz;
    final freeArea = squareArea - usedArea;
    final freePct = freeArea / squareArea * 100;
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 20,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle_outline,
                color: Color(0xFF3FB950), size: 16),
            const SizedBox(width: 8),
            Text('Square: ${_fmt(sz)} × ${_fmt(sz)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
          Text('$total rectangle${total == 1 ? '' : 's'} packed',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
          Text('Free: ${_fmt(freeArea)} (${_fmt(freePct)}%)',
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Color legend ─────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  final List<RectType> types;
  const _Legend({required this.types});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        children: [
          for (final t in types)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                      color: t.color,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(
                '${_fmt(t.width)}×${_fmt(t.height)}  ×${t.count}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ]),
        ],
      ),
    );
  }

}

// ── CustomPainter ─────────────────────────────────────────────────────────

class _PackPainter extends CustomPainter {
  final PackResult result;
  final List<RectType> types;
  final double ppu;

  _PackPainter(this.result, this.types, this.ppu);

  @override
  void paint(Canvas canvas, Size size) {
    final s = ppu;
    final ox = (size.width - result.squareSize * s) / 2;
    final oy = (size.height - result.squareSize * s) / 2;
    final sqW = result.squareSize * s;

    // Square background
    canvas.drawRect(
        Rect.fromLTWH(ox, oy, sqW, sqW),
        Paint()..color = const Color(0xFF161B22));
    canvas.drawRect(
        Rect.fromLTWH(ox, oy, sqW, sqW),
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Subtle grid
    _drawGrid(canvas, ox, oy, sqW, s);

    // Rectangles
    for (final r in result.placed) {
      final rx = ox + r.x * s;
      final ry = oy + r.y * s;
      final rw = r.w * s;
      final rh = r.h * s;
      final color = types[r.typeIndex].color;

      canvas.drawRect(
          Rect.fromLTWH(rx, ry, rw, rh),
          Paint()..color = color.withAlpha(220));
      canvas.drawRect(
          Rect.fromLTWH(rx, ry, rw, rh),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7);

      // Dimension label
      if (rw > 28 && rh > 14) {
        final t = types[r.typeIndex];
        final label = r.rotated
            ? '${_fmt(t.height)}×${_fmt(t.width)}'
            : '${_fmt(t.width)}×${_fmt(t.height)}';
        _drawLabel(canvas, label, rx + rw / 2, ry + rh / 2);
      }
    }

    // Axis labels
    _drawAxisLabel(canvas, '0', ox - 6, oy - 6, align: Alignment.bottomRight);
    _drawAxisLabel(canvas, _fmt(result.squareSize), ox + sqW + 4, oy - 6,
        align: Alignment.bottomLeft);
    _drawAxisLabel(canvas, _fmt(result.squareSize), ox - 4, oy + sqW + 4,
        align: Alignment.topRight);
  }

  void _drawGrid(Canvas canvas, double ox, double oy, double sqW, double s) {
    final step = _niceStep(result.squareSize);
    final paint = Paint()
      ..color = Colors.white.withAlpha(18)
      ..strokeWidth = 0.5;
    for (double v = step; v < result.squareSize - 1e-9; v += step) {
      final px = ox + v * s;
      final py = oy + v * s;
      canvas.drawLine(Offset(px, oy), Offset(px, oy + sqW), paint);
      canvas.drawLine(Offset(ox, py), Offset(ox + sqW, py), paint);
    }
  }

  double _niceStep(double size) {
    if (size <= 10) return 1;
    if (size <= 50) return 5;
    if (size <= 200) return 10;
    if (size <= 1000) return 50;
    return 100;
  }

  void _drawLabel(Canvas canvas, String text, double cx, double cy) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(blurRadius: 2, color: Colors.black)])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  void _drawAxisLabel(Canvas canvas, String text, double x, double y,
      {required Alignment align}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(color: Colors.white38, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    final ox = align == Alignment.bottomRight || align == Alignment.topRight
        ? -tp.width
        : 0.0;
    final oy2 = align == Alignment.bottomLeft || align == Alignment.bottomRight
        ? -tp.height
        : 0.0;
    tp.paint(canvas, Offset(x + ox, y + oy2));
  }

  @override
  bool shouldRepaint(_PackPainter old) => old.ppu != ppu;
}
