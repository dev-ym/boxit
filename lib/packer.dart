import 'dart:math' as math;
import 'models.dart';

// ── Guillotine bin-packer with best-short-side-fit heuristic ──────────────

class _F {
  double x, y, w, h;
  _F(this.x, this.y, this.w, this.h);
}

class _I {
  final double w, h;
  final int idx;
  const _I(this.w, this.h, this.idx);
}

List<PlacedRect>? _tryPack(List<_I> items, double size) {
  final free = [_F(0, 0, size, size)];
  final placed = <PlacedRect>[];

  for (final item in items) {
    int bi = -1;
    bool br = false;
    double bs = double.infinity;

    for (int i = 0; i < free.length; i++) {
      final f = free[i];
      // Try normal orientation
      if (item.w <= f.w + 1e-9 && item.h <= f.h + 1e-9) {
        final s = math.min(f.w - item.w, f.h - item.h);
        if (s < bs) {
          bs = s;
          bi = i;
          br = false;
        }
      }
      // Try rotated 90°
      if (item.h <= f.w + 1e-9 && item.w <= f.h + 1e-9) {
        final s = math.min(f.w - item.h, f.h - item.w);
        if (s < bs) {
          bs = s;
          bi = i;
          br = true;
        }
      }
    }

    if (bi < 0) return null;

    final f = free[bi];
    final pw = br ? item.h : item.w;
    final ph = br ? item.w : item.h;
    placed.add(PlacedRect(
        x: f.x, y: f.y, w: pw, h: ph, typeIndex: item.idx, rotated: br));

    // Guillotine split — longer-axis heuristic
    free.removeAt(bi);
    final rw = f.w - pw;
    final bh = f.h - ph;
    if (rw >= bh) {
      if (rw > 1e-9) free.add(_F(f.x + pw, f.y, rw, f.h));
      if (bh > 1e-9) free.add(_F(f.x, f.y + ph, pw, bh));
    } else {
      if (bh > 1e-9) free.add(_F(f.x, f.y + ph, f.w, bh));
      if (rw > 1e-9) free.add(_F(f.x + pw, f.y, rw, ph));
    }
  }
  return placed;
}

/// Finds the minimum square that contains all given rectangles, packed without
/// overlap.  Rectangles may be rotated 90°.  Returns null only if types is
/// empty or all counts are zero.
PackResult? findOptimalPacking(List<RectType> types) {
  final items = <_I>[];
  for (int i = 0; i < types.length; i++) {
    for (int j = 0; j < types[i].count; j++) {
      items.add(_I(types[i].width, types[i].height, i));
    }
  }
  if (items.isEmpty) return null;

  // Sort by area descending for better packing
  items.sort((a, b) => (b.w * b.h).compareTo(a.w * a.h));

  final totalArea = items.fold(0.0, (s, r) => s + r.w * r.h);
  final minDim = items.fold(0.0, (m, r) => math.max(m, math.max(r.w, r.h)));
  double lo = math.max(minDim, math.sqrt(totalArea));

  // Find a working upper bound
  double hi = lo;
  while (_tryPack(items, hi) == null) {
    hi *= 1.25;
  }

  var bestPacked = _tryPack(items, hi)!;
  var bestSize = hi;

  // Binary search for minimum square size
  for (int k = 0; k < 64; k++) {
    if (hi - lo < 0.005) break;
    final mid = (lo + hi) / 2;
    final r = _tryPack(items, mid);
    if (r != null) {
      bestPacked = r;
      bestSize = mid;
      hi = mid;
    } else {
      lo = mid;
    }
  }

  return PackResult(squareSize: bestSize, placed: bestPacked);
}
