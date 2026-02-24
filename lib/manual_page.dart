import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'packer.dart';

// ── Data model for a rectangle in manual mode ─────────────────────────────

class ManualRect {
  double wx, wy; // top-left position in square world-coords
  int typeIndex;
  bool inSquare;
  int rotation; // 0..3 (multiples of 90°)
  double origW, origH;

  ManualRect({
    required this.wx,
    required this.wy,
    required this.typeIndex,
    required this.inSquare,
    required this.rotation,
    required this.origW,
    required this.origH,
  });

  double get worldW => rotation % 2 == 0 ? origW : origH;
  double get worldH => rotation % 2 == 0 ? origH : origW;

  ManualRect copyWith(
          {double? wx, double? wy, bool? inSquare, int? rotation}) =>
      ManualRect(
        wx: wx ?? this.wx,
        wy: wy ?? this.wy,
        typeIndex: typeIndex,
        inSquare: inSquare ?? this.inSquare,
        rotation: rotation ?? this.rotation,
        origW: origW,
        origH: origH,
      );
}

// ── Saved state that survives navigation ──────────────────────────────────

class ManualPageData {
  final double squareSize;
  final List<ManualRect> rects;
  ManualPageData({required this.squareSize, required this.rects});
}

// ── Page ──────────────────────────────────────────────────────────────────

class ManualPage extends StatefulWidget {
  final List<RectType> types;
  final ManualPageData? savedData;
  final void Function(ManualPageData)? onSave;

  const ManualPage({
    super.key,
    required this.types,
    this.savedData,
    this.onSave,
  });

  @override
  State<ManualPage> createState() => _ManualPageState();
}

class _ManualPageState extends State<ManualPage> {
  // World state
  late double _squareSize;
  late List<ManualRect> _rects;

  // Display state — pixels per world unit, computed once on first layout
  double _ppu = 1.0;
  bool _ppuReady = false;

  // Fixed screen position of the square's top-left corner
  static const double _kSqLeft = 16.0;
  static const double _kSqTop = 8.0;

  // Palette constants
  static const double _kPalPad = 10.0;
  static const double _kPalGapAbove = 20.0;

  // Drag state
  int _dragIdx = -1;
  Offset _dragPos = Offset.zero; // screen TL of the dragged rect
  Offset _dragAnchor = Offset.zero; // cursor offset from rect TL

  // Resize state (only BR corner)
  bool _resizing = false;
  static const double _kCornerHitR = 20.0;

  // Snap-to-align threshold (screen pixels)
  static const double _kSnapPx = 12.0;

  // Palette scroll state
  double _palScrollOffset = 0.0;
  double _palMaxScroll = 0.0; // updated each build pass (no setState)
  bool _scrollingPalette = false;

  @override
  void initState() {
    super.initState();
    if (widget.savedData != null) {
      _squareSize = widget.savedData!.squareSize;
      _rects = widget.savedData!.rects.map((r) => r.copyWith()).toList();
    } else {
      _initFresh();
    }
  }

  @override
  void dispose() {
    widget.onSave?.call(ManualPageData(
      squareSize: _squareSize,
      rects: _rects.map((r) => r.copyWith()).toList(),
    ));
    super.dispose();
  }

  void _initFresh() {
    double totalArea = 0, maxDim = 0;
    for (final t in widget.types) {
      totalArea += t.width * t.height * t.count;
      maxDim = math.max(maxDim, math.max(t.width, t.height));
    }
    _squareSize = math.max(maxDim, math.sqrt(totalArea) * 1.5);
    _palScrollOffset = 0.0;
    _rects = [
      for (int i = 0; i < widget.types.length; i++)
        for (int j = 0; j < widget.types[i].count; j++)
          ManualRect(
            wx: 0,
            wy: 0,
            typeIndex: i,
            inSquare: false,
            rotation: 0,
            origW: widget.types[i].width,
            origH: widget.types[i].height,
          ),
    ];
  }

  void _reset() {
    setState(() {
      _initFresh();
      _ppuReady = false; // recompute scale to fit reset square
      _dragIdx = -1;
      _resizing = false;
      _scrollingPalette = false;
    });
  }

  void _copyOptimized() {
    final result = findOptimalPacking(widget.types);
    if (result == null) return;
    setState(() {
      _squareSize = result.squareSize;
      _rects = result.placed.map((p) {
        final t = widget.types[p.typeIndex];
        return ManualRect(
          wx: p.x,
          wy: p.y,
          typeIndex: p.typeIndex,
          inSquare: true,
          rotation: p.rotated ? 1 : 0,
          origW: t.width,
          origH: t.height,
        );
      }).toList();
      _ppuReady = false;
      _dragIdx = -1;
      _resizing = false;
      _palScrollOffset = 0.0;
      _scrollingPalette = false;
    });
  }

  // ── Geometry helpers ────────────────────────────────────────────────────

  void _initPpu(BuildContext ctx) {
    if (_ppuReady) return;
    final screen = MediaQuery.of(ctx).size;
    _ppu = math.min(screen.width * 0.85, screen.height * 0.65) / _squareSize;
    _ppuReady = true;
  }

  Rect _squareRect() => Rect.fromLTWH(
      _kSqLeft, _kSqTop, _squareSize * _ppu, _squareSize * _ppu);

  double _palTop() => _squareRect().bottom + _kPalGapAbove;

  Offset _worldToScreen(double wx, double wy) {
    final sq = _squareRect();
    return Offset(sq.left + wx * _ppu, sq.top + wy * _ppu);
  }

  Offset _screenToWorld(Offset p) {
    final sq = _squareRect();
    return Offset((p.dx - sq.left) / _ppu, (p.dy - sq.top) / _ppu);
  }

  // Returns the screen TL position of each rect in the palette (null if in
  // square or currently being dragged).
  List<Offset?> _palettePositions(Size size) {
    final result = List<Offset?>.filled(_rects.length, null);
    double x = _kSqLeft;
    double y = _palTop() - _palScrollOffset; // scroll applied
    double rowH = 0;

    for (int i = 0; i < _rects.length; i++) {
      final r = _rects[i];
      if (r.inSquare) continue; // in square — skip

      final rw = r.worldW * _ppu;
      final rh = r.worldH * _ppu;

      // Wrap to next row if needed
      if (x + rw > size.width - _kSqLeft && x > _kSqLeft) {
        x = _kSqLeft;
        y += rowH + _kPalPad;
        rowH = 0;
      }

      if (i != _dragIdx) {
        result[i] = Offset(x, y);
      }
      // Whether dragging or not, advance layout so other rects don't jump
      x += rw + _kPalPad;
      rowH = math.max(rowH, rh);
    }

    // Cache max scroll (layout-derived, no setState needed)
    _palMaxScroll = math.max(0.0, y + rowH + _palScrollOffset - size.height);
    return result;
  }

  // ── Hit testing ──────────────────────────────────────────────────────────

  bool _nearBRCorner(Offset pos) {
    final sq = _squareRect();
    return (pos - sq.bottomRight).distance < _kCornerHitR;
  }

  int _hitTest(Offset pos, Size size) {
    // Check placed rects (reverse so top-most is found first)
    for (int i = _rects.length - 1; i >= 0; i--) {
      final r = _rects[i];
      if (!r.inSquare) continue;
      final p = _worldToScreen(r.wx, r.wy);
      if (Rect.fromLTWH(p.dx, p.dy, r.worldW * _ppu, r.worldH * _ppu)
          .contains(pos)) {
        return i;
      }
    }
    // Check palette rects
    final pal = _palettePositions(size);
    for (int i = 0; i < _rects.length; i++) {
      final p = pal[i];
      if (p == null) continue;
      final r = _rects[i];
      if (Rect.fromLTWH(p.dx, p.dy, r.worldW * _ppu, r.worldH * _ppu)
          .contains(pos)) {
        return i;
      }
    }
    return -1;
  }

  // ── Gesture handlers ─────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d, Size size) {
    final pos = d.localPosition;

    if (_nearBRCorner(pos)) {
      setState(() => _resizing = true);
      return;
    }

    final idx = _hitTest(pos, size);
    if (idx < 0) {
      // No rect hit — start palette scroll if touch is below the square
      if (_ppuReady && pos.dy > _squareRect().bottom) {
        setState(() => _scrollingPalette = true);
      }
      return;
    }

    final r = _rects[idx];
    final Offset rectTL;
    if (r.inSquare) {
      rectTL = _worldToScreen(r.wx, r.wy);
    } else {
      final pal = _palettePositions(size);
      rectTL = pal[idx] ?? pos;
    }

    setState(() {
      _dragIdx = idx;
      _dragAnchor = pos - rectTL;
      _dragPos = rectTL;
    });
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    final pos = d.localPosition;

    if (_resizing) {
      final sq = _squareRect();
      final newPx = math.max(pos.dx - sq.left, pos.dy - sq.top);
      final newSize = newPx / _ppu;
      final minSize = _minSizeToContain();
      setState(() => _squareSize = math.max(newSize, minSize));
      return;
    }

    if (_scrollingPalette) {
      setState(() {
        _palScrollOffset =
            (_palScrollOffset - d.delta.dy).clamp(0.0, _palMaxScroll);
      });
      return;
    }

    if (_dragIdx >= 0) {
      setState(() => _dragPos = _snapDragPos(pos - _dragAnchor));
    }
  }

  void _onPanEnd(DragEndDetails d, Size size) {
    if (_resizing) {
      setState(() => _resizing = false);
      return;
    }
    if (_scrollingPalette) {
      setState(() => _scrollingPalette = false);
      return;
    }
    if (_dragIdx < 0) return;

    final sq = _squareRect();
    final r = _rects[_dragIdx];

    // Use center of dragged rect to decide placement
    final center = Offset(
        _dragPos.dx + r.worldW * _ppu / 2,
        _dragPos.dy + r.worldH * _ppu / 2);

    if (sq.contains(center) &&
        r.worldW <= _squareSize + 1e-9 &&
        r.worldH <= _squareSize + 1e-9) {
      final wPos = _screenToWorld(_dragPos);
      final rawWx = wPos.dx.clamp(0.0, _squareSize - r.worldW);
      final rawWy = wPos.dy.clamp(0.0, _squareSize - r.worldH);
      final (wx, wy) = _autoFix(_dragIdx, rawWx, rawWy);
      setState(() {
        _rects[_dragIdx] = r.copyWith(inSquare: true, wx: wx, wy: wy);
        _dragIdx = -1;
      });
    } else {
      setState(() {
        _rects[_dragIdx] = r.copyWith(inSquare: false);
        _dragIdx = -1;
      });
    }
  }

  void _onTapUp(TapUpDetails d, Size size) {
    final idx = _hitTest(d.localPosition, size);
    if (idx < 0) return;

    final r = _rects[idx];
    final newRot = (r.rotation + 1) % 4;
    final newR = r.copyWith(rotation: newRot);

    if (r.inSquare) {
      // Clamp position to keep rotated rect inside square
      final wx = newR.wx.clamp(0.0, _squareSize - newR.worldW);
      final wy = newR.wy.clamp(0.0, _squareSize - newR.worldH);
      if (newR.worldW <= _squareSize && newR.worldH <= _squareSize) {
        setState(() => _rects[idx] = newR.copyWith(wx: wx, wy: wy));
      }
    } else {
      setState(() => _rects[idx] = newR);
    }
  }

  // Returns the screen TL of the dragged rect after snapping its edges to
  // nearby placed-rect edges and square walls.
  Offset _snapDragPos(Offset screenTL) {
    final r = _rects[_dragIdx];
    final sq = _squareRect();
    final thresh = _kSnapPx / _ppu; // threshold in world units
    final rw = r.worldW;
    final rh = r.worldH;
    final wx0 = (screenTL.dx - sq.left) / _ppu;
    final wy0 = (screenTL.dy - sq.top) / _ppu;

    double bestDx = thresh, wx = wx0;
    double bestDy = thresh, wy = wy0;

    void tryX(double c) {
      final d = (c - wx0).abs();
      if (d < bestDx) { bestDx = d; wx = c; }
    }
    void tryY(double c) {
      final d = (c - wy0).abs();
      if (d < bestDy) { bestDy = d; wy = c; }
    }

    // Square walls
    tryX(0);                   tryX(_squareSize - rw);
    tryY(0);                   tryY(_squareSize - rh);

    // Every placed rect's edges
    for (int i = 0; i < _rects.length; i++) {
      if (i == _dragIdx || !_rects[i].inSquare) continue;
      final o = _rects[i];
      tryX(o.wx + o.worldW);          // dragged-left touches other-right
      tryX(o.wx - rw);                // dragged-right touches other-left
      tryX(o.wx);                     // align left edges
      tryX(o.wx + o.worldW - rw);    // align right edges
      tryY(o.wy + o.worldH);          // dragged-top touches other-bottom
      tryY(o.wy - rh);                // dragged-bottom touches other-top
      tryY(o.wy);                     // align top edges
      tryY(o.wy + o.worldH - rh);    // align bottom edges
    }

    return Offset(sq.left + wx * _ppu, sq.top + wy * _ppu);
  }

  double _minSizeToContain() {
    var mx = 0.0, my = 0.0;
    for (final r in _rects) {
      if (!r.inSquare) continue;
      mx = math.max(mx, r.wx + r.worldW);
      my = math.max(my, r.wy + r.worldH);
    }
    return math.max(mx, my);
  }

  // ── Overlap helpers ────────────────────────────────────────────────────────

  bool _rectsOverlap(ManualRect a, ManualRect b) {
    const tol = 1e-6;
    return a.wx < b.wx + b.worldW - tol &&
        a.wx + a.worldW > b.wx + tol &&
        a.wy < b.wy + b.worldH - tol &&
        a.wy + a.worldH > b.wy + tol;
  }

  Set<int> _computeOverlaps() {
    final result = <int>{};
    for (int i = 0; i < _rects.length; i++) {
      if (!_rects[i].inSquare) continue;
      for (int j = i + 1; j < _rects.length; j++) {
        if (!_rects[j].inSquare) continue;
        if (_rectsOverlap(_rects[i], _rects[j])) {
          result.add(i);
          result.add(j);
        }
      }
    }
    return result;
  }

  bool _isValid() =>
      _rects.every((r) => r.inSquare) && _computeOverlaps().isEmpty;

  /// Tries to nudge [moved] (currently at [wx],[wy]) away from any rect it
  /// overlaps, but only if the required push is ≤ 25 % of its shorter side.
  (double, double) _autoFix(int movedIdx, double wx, double wy) {
    final moved = _rects[movedIdx];
    final threshold = math.min(moved.worldW, moved.worldH) * 0.25;
    double cx = wx, cy = wy;

    for (int iter = 0; iter < 30; iter++) {
      bool anyFix = false;
      for (int i = 0; i < _rects.length; i++) {
        if (i == movedIdx || !_rects[i].inSquare) continue;
        final other = _rects[i];
        final xOv = math.min(cx + moved.worldW, other.wx + other.worldW) -
            math.max(cx, other.wx);
        final yOv = math.min(cy + moved.worldH, other.wy + other.worldH) -
            math.max(cy, other.wy);
        if (xOv <= 1e-9 || yOv <= 1e-9) continue; // no overlap
        if (math.min(xOv, yOv) > threshold) continue; // too large, skip
        anyFix = true;
        if (xOv <= yOv) {
          cx = cx < other.wx ? cx - xOv : cx + xOv;
        } else {
          cy = cy < other.wy ? cy - yOv : cy + yOv;
        }
        cx = cx.clamp(0.0, _squareSize - moved.worldW);
        cy = cy.clamp(0.0, _squareSize - moved.worldH);
      }
      if (!anyFix) break;
    }
    return (cx, cy);
  }

  // ── Info bar ──────────────────────────────────────────────────────────────

  Widget _buildInfoBar(bool isWide) {
    final placed = _rects.where((r) => r.inSquare).toList();
    final placedCount = placed.length;
    final overlaps = _computeOverlaps().length ~/ 2;
    final valid = _isValid();
    final squareArea = _squareSize * _squareSize;
    final usedArea = placed.fold(0.0, (s, r) => s + r.worldW * r.worldH);
    final freeArea = squareArea - usedArea;
    final freePct = squareArea > 0 ? freeArea / squareArea * 100 : 0.0;

    final squareLabel = Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.square_outlined, color: Colors.white38, size: 15),
      const SizedBox(width: 6),
      Text('${_fmtSize(_squareSize)} × ${_fmtSize(_squareSize)}',
          style: const TextStyle(color: Colors.white70, fontSize: 13)),
    ]);
    final freeLabel = Text(
        'Free: ${_fmtSize(freeArea)} (${_fmtSize(freePct)}%)',
        style: const TextStyle(color: Colors.white38, fontSize: 13));
    final placedLabel = Text('$placedCount / ${_rects.length} placed',
        style: const TextStyle(color: Colors.white38, fontSize: 13));
    final validity = valid
        ? const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle, color: Color(0xFF3FB950), size: 15),
            SizedBox(width: 5),
            Text('Valid',
                style: TextStyle(
                    color: Color(0xFF3FB950),
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ])
        : overlaps > 0
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFE3A93A), size: 15),
                const SizedBox(width: 5),
                Text('$overlaps overlap${overlaps == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: Color(0xFFE3A93A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ])
            : const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.info_outline, color: Colors.white38, size: 15),
                SizedBox(width: 5),
                Text('Place all rects',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ]);

    if (!isWide) {
      return Container(
        color: const Color(0xFF161B22),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [squareLabel, const Spacer(), validity]),
          const SizedBox(height: 3),
          Row(children: [freeLabel, const SizedBox(width: 16), placedLabel]),
        ]),
      );
    }

    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        squareLabel,
        const SizedBox(width: 20),
        freeLabel,
        const SizedBox(width: 20),
        placedLabel,
        const Spacer(),
        validity,
        const SizedBox(width: 4),
      ]),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isWide = screenW >= 600;
    final showHint = screenW >= 800;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
        title: isWide
            ? const Text('Manual Placement',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15))
            : null,
        actions: [
          TextButton.icon(
            onPressed: _copyOptimized,
            icon: const Icon(Icons.auto_fix_high,
                size: 15, color: Color(0xFF79C0FF)),
            label: const Text('Copy Optimized',
                style: TextStyle(color: Color(0xFF79C0FF), fontSize: 13)),
          ),
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt,
                size: 16, color: Colors.white54),
            label:
                const Text('Reset', style: TextStyle(color: Colors.white54)),
          ),
          if (showHint)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(
                  'Tap rect to rotate  ·  Drag to move  ·  Drag ◢ to resize square',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
        ],
      ),
      body: Column(children: [
        _buildInfoBar(isWide),
        // ── Interactive canvas ─────────────────────────────────────────────
        Expanded(child: LayoutBuilder(builder: (ctx, cst) {
        final size = Size(cst.maxWidth, cst.maxHeight);
        _initPpu(ctx);
        final sq = _squareRect();
        final pal = _palettePositions(size);
        final overlapping = _computeOverlaps();
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent && _ppuReady &&
                e.localPosition.dy > _squareRect().bottom) {
              setState(() {
                _palScrollOffset =
                    (_palScrollOffset + e.scrollDelta.dy).clamp(0.0, _palMaxScroll);
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => _onPanStart(d, size),
            onPanUpdate: (d) => _onPanUpdate(d, size),
            onPanEnd: (d) => _onPanEnd(d, size),
            onTapUp: (d) => _onTapUp(d, size),
            child: CustomPaint(
              size: size,
              painter: _ManualPainter(
                types: widget.types,
                rects: _rects,
                squareRect: sq,
                squareSize: _squareSize,
                ppu: _ppu,
                palPositions: pal,
                palTop: _palTop(),
                dragIdx: _dragIdx,
                dragPos: _dragPos,
                overlapping: overlapping,
              ),
            ),
          ),
        );
      })),
      ]),
    );
  }

  String _fmtSize(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

// ── Painter ───────────────────────────────────────────────────────────────

class _ManualPainter extends CustomPainter {
  final List<RectType> types;
  final List<ManualRect> rects;
  final Rect squareRect;
  final double squareSize, ppu;
  final List<Offset?> palPositions;
  final double palTop;
  final int dragIdx;
  final Offset dragPos;
  final Set<int> overlapping;

  _ManualPainter({
    required this.types,
    required this.rects,
    required this.squareRect,
    required this.squareSize,
    required this.ppu,
    required this.palPositions,
    required this.palTop,
    required this.dragIdx,
    required this.dragPos,
    required this.overlapping,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawSquare(canvas);
    _drawPlacedRects(canvas);
    _drawPaletteDivider(canvas, size);
    _drawPaletteRects(canvas, size);
    _drawDraggingRect(canvas);
    _drawBRHandle(canvas);
  }

  void _drawSquare(Canvas canvas) {
    // Background
    canvas.drawRect(squareRect, Paint()..color = const Color(0xFF161B22));
    // Border
    canvas.drawRect(
        squareRect,
        Paint()
          ..color = Colors.white30
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Size label above
    _label(
        canvas,
        '${_fmt(squareSize)} × ${_fmt(squareSize)}',
        squareRect.center.dx,
        squareRect.top - 12,
        fontSize: 11,
        color: Colors.white38);
  }

  void _drawPlacedRects(Canvas canvas) {
    for (int i = 0; i < rects.length; i++) {
      if (i == dragIdx) continue;
      final r = rects[i];
      if (!r.inSquare) continue;
      final x = squareRect.left + r.wx * ppu;
      final y = squareRect.top + r.wy * ppu;
      final w = r.worldW * ppu;
      final h = r.worldH * ppu;
      _drawBox(canvas, x, y, w, h, types[r.typeIndex].color,
          overlapBorder: overlapping.contains(i));
      if (w > 30 && h > 16) {
        _label(canvas, '${_fmt(r.worldW)}×${_fmt(r.worldH)}',
            x + w / 2, y + h / 2);
      }
    }
  }

  void _drawPaletteDivider(Canvas canvas, Size size) {
    canvas.drawLine(
        Offset(0, palTop - 10),
        Offset(size.width, palTop - 10),
        Paint()
          ..color = Colors.white12
          ..strokeWidth = 1);
    _label(canvas, 'Palette — drag into the square',
        size.width / 2, palTop - 3,
        fontSize: 10, color: Colors.white24);
  }

  void _drawPaletteRects(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, palTop - 13, size.width, size.height - (palTop - 13)));
    for (int i = 0; i < rects.length; i++) {
      if (i == dragIdx) continue;
      final p = palPositions[i];
      if (p == null) continue;
      final r = rects[i];
      final w = r.worldW * ppu;
      final h = r.worldH * ppu;
      _drawBox(canvas, p.dx, p.dy, w, h, types[r.typeIndex].color);
      if (w > 30 && h > 16) {
        _label(canvas, '${_fmt(r.worldW)}×${_fmt(r.worldH)}',
            p.dx + w / 2, p.dy + h / 2);
      }
      // Small rotation hint
      if (w > 24 && h > 24) {
        _drawRotIcon(canvas, p.dx + w - 10, p.dy + 4);
      }
    }
    canvas.restore();
  }

  void _drawDraggingRect(Canvas canvas) {
    if (dragIdx < 0) return;
    final r = rects[dragIdx];
    final w = r.worldW * ppu;
    final h = r.worldH * ppu;
    // Shadow
    canvas.drawRect(
        Rect.fromLTWH(dragPos.dx + 4, dragPos.dy + 4, w, h),
        Paint()..color = Colors.black38);
    // Rect (semi-transparent)
    _drawBox(canvas, dragPos.dx, dragPos.dy, w, h,
        types[r.typeIndex].color.withAlpha(190));
  }

  void _drawBRHandle(Canvas canvas) {
    final br = squareRect.bottomRight;
    canvas.drawCircle(br, 8, Paint()..color = Colors.white70);
    canvas.drawCircle(
        br,
        8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    // Triangle glyph
    final path = Path()
      ..moveTo(br.dx - 3, br.dy + 1)
      ..lineTo(br.dx + 1, br.dy - 3)
      ..lineTo(br.dx + 1, br.dy + 1)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.black87);
  }

  // ── Drawing primitives ──────────────────────────────────────────────────

  void _drawBox(Canvas canvas, double x, double y, double w, double h,
      Color color, {bool overlapBorder = false}) {
    final b = math.min(4.0, math.min(w, h) * 0.15);
    if (b < 0.5) {
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = color);
      return;
    }
    final light = _lighten(color, 0.50);
    final dark  = _darken(color, 0.40);
    // Top face
    canvas.drawPath(Path()
      ..moveTo(x,     y)
      ..lineTo(x + w, y)
      ..lineTo(x + w - b, y + b)
      ..lineTo(x + b,     y + b)
      ..close(), Paint()..color = light);
    // Left face
    canvas.drawPath(Path()
      ..moveTo(x, y)
      ..lineTo(x, y + h)
      ..lineTo(x + b, y + h - b)
      ..lineTo(x + b, y + b)
      ..close(), Paint()..color = light);
    // Bottom face
    canvas.drawPath(Path()
      ..moveTo(x,     y + h)
      ..lineTo(x + w, y + h)
      ..lineTo(x + w - b, y + h - b)
      ..lineTo(x + b,     y + h - b)
      ..close(), Paint()..color = dark);
    // Right face
    canvas.drawPath(Path()
      ..moveTo(x + w, y)
      ..lineTo(x + w, y + h)
      ..lineTo(x + w - b, y + h - b)
      ..lineTo(x + w - b, y + b)
      ..close(), Paint()..color = dark);
    // Centre surface
    canvas.drawRect(
        Rect.fromLTWH(x + b, y + b, w - 2 * b, h - 2 * b),
        Paint()..color = color);
    // Overlap border
    if (overlapBorder) {
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()
        ..color = const Color(0xFFE3A93A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0);
    }
  }

  Color _lighten(Color c, double t) => Color.fromARGB(
      (c.a * 255).round(),
      (c.r * 255 + (255 - c.r * 255) * t).round().clamp(0, 255),
      (c.g * 255 + (255 - c.g * 255) * t).round().clamp(0, 255),
      (c.b * 255 + (255 - c.b * 255) * t).round().clamp(0, 255));

  Color _darken(Color c, double t) => Color.fromARGB(
      (c.a * 255).round(),
      (c.r * 255 * (1 - t)).round().clamp(0, 255),
      (c.g * 255 * (1 - t)).round().clamp(0, 255),
      (c.b * 255 * (1 - t)).round().clamp(0, 255));

  void _drawRotIcon(Canvas canvas, double cx, double cy) {
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    // Small arc suggesting rotation
    canvas.drawArc(
        Rect.fromCenter(center: Offset(cx, cy), width: 8, height: 8),
        0,
        math.pi * 1.5,
        false,
        paint);
    // Arrow head
    canvas.drawLine(Offset(cx + 4, cy - 0.5),
        Offset(cx + 4, cy + 2.5),
        Paint()
          ..color = Colors.white38
          ..strokeWidth = 1.2);
  }

  void _label(Canvas canvas, String text, double cx, double cy,
      {double fontSize = 10.5, Color color = Colors.white}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(blurRadius: 2, color: Colors.black)])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  bool shouldRepaint(_ManualPainter old) => true;
}
