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

// Merges adjacent free rectangles that share the same dimension on their
// common edge (e.g. two rectangles with the same height side by side).
void _mergeFree(List<_F> free) {
  bool merged = true;
  while (merged) {
    merged = false;
    outer:
    for (int i = 0; i < free.length; i++) {
      for (int j = i + 1; j < free.length; j++) {
        final a = free[i];
        final b = free[j];
        // Horizontally adjacent: same y and h, touching x edges
        if ((a.y - b.y).abs() < 1e-9 && (a.h - b.h).abs() < 1e-9) {
          if ((a.x + a.w - b.x).abs() < 1e-9) {
            free[i] = _F(a.x, a.y, a.w + b.w, a.h);
            free.removeAt(j);
            merged = true;
            break outer;
          } else if ((b.x + b.w - a.x).abs() < 1e-9) {
            free[i] = _F(b.x, a.y, a.w + b.w, a.h);
            free.removeAt(j);
            merged = true;
            break outer;
          }
        }
        // Vertically adjacent: same x and w, touching y edges
        if ((a.x - b.x).abs() < 1e-9 && (a.w - b.w).abs() < 1e-9) {
          if ((a.y + a.h - b.y).abs() < 1e-9) {
            free[i] = _F(a.x, a.y, a.w, a.h + b.h);
            free.removeAt(j);
            merged = true;
            break outer;
          } else if ((b.y + b.h - a.y).abs() < 1e-9) {
            free[i] = _F(a.x, b.y, a.w, a.h + b.h);
            free.removeAt(j);
            merged = true;
            break outer;
          }
        }
      }
    }
  }
}

// Runs the guillotine loop on [items] given [free] spaces and [prePlaced] rects.
List<PlacedRect>? _guillotinePack(
    List<_F> free, List<PlacedRect> prePlaced, List<_I> items) {
  final placed = List<PlacedRect>.from(prePlaced);

  _mergeFree(free);

  for (final item in items) {
    int bi = -1;
    bool br = false;
    double bs = double.infinity;

    for (int i = 0; i < free.length; i++) {
      final f = free[i];
      if (item.w <= f.w + 1e-9 && item.h <= f.h + 1e-9) {
        final s = math.min(f.w - item.w, f.h - item.h);
        if (s < bs) { bs = s; bi = i; br = false; }
      }
      if (item.h <= f.w + 1e-9 && item.w <= f.h + 1e-9) {
        final s = math.min(f.w - item.h, f.h - item.w);
        if (s < bs) { bs = s; bi = i; br = true; }
      }
    }

    if (bi < 0) return null;

    final f = free[bi];
    final pw = br ? item.h : item.w;
    final ph = br ? item.w : item.h;
    placed.add(PlacedRect(
        x: f.x, y: f.y, w: pw, h: ph, typeIndex: item.idx, rotated: br));

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
    _mergeFree(free);
  }
  return placed;
}

List<PlacedRect>? _tryPack(List<_I> items, double size) {
  return _guillotinePack([_F(0, 0, size, size)], [], items);
}

// Tries packing by placing the first (largest) item at every integer position
// in the upper-left quadrant, in addition to the standard [0,0] start.
List<PlacedRect>? _tryPackMultiStart(List<_I> items, double size) {
  // Standard placement first (fast path)
  final standard = _tryPack(items, size);
  if (standard != null) return standard;

  if (items.isEmpty) return [];

  final first = items[0];
  final rest = items.sublist(1);

  for (double oy = 0; oy <= size / 2 + 1e-9; oy += 1) {
    for (double ox = 0; ox <= size / 2 + 1e-9; ox += 1) {
      if (ox < 1e-9 && oy < 1e-9) continue; // already tried as standard

      for (final rotated in [false, true]) {
        final pw = rotated ? first.h : first.w;
        final ph = rotated ? first.w : first.h;

        if (ox + pw > size + 1e-9 || oy + ph > size + 1e-9) continue;

        // Decompose the complement of the pre-placed item into free rectangles:
        //   above (full width), left (item height to bottom), right, below item
        final free = <_F>[];
        if (oy > 1e-9) free.add(_F(0, 0, size, oy));
        if (ox > 1e-9) free.add(_F(0, oy, ox, size - oy));
        if (ox + pw < size - 1e-9) free.add(_F(ox + pw, oy, size - ox - pw, size - oy));
        if (oy + ph < size - 1e-9) free.add(_F(ox, oy + ph, pw, size - oy - ph));

        final prePlaced = [
          PlacedRect(x: ox, y: oy, w: pw, h: ph, typeIndex: first.idx, rotated: rotated)
        ];
        final result = _guillotinePack(free, prePlaced, rest);
        if (result != null) return result;
      }
    }
  }
  return null;
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
  while (_tryPackMultiStart(items, hi) == null) {
    hi *= 1.25;
  }

  var bestPacked = _tryPackMultiStart(items, hi)!;
  var bestSize = hi;

  // Binary search for minimum square size
  for (int k = 0; k < 64; k++) {
    if (hi - lo < 0.005) break;
    final mid = (lo + hi) / 2;
    final r = _tryPackMultiStart(items, mid);
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
