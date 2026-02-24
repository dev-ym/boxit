import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'optimize_page.dart';
import 'manual_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _types = <RectType>[];
  ManualPageData? _savedManualData;

  void _typesChanged() => _savedManualData = null;

  void _add() {
    final rng = math.Random();
    final existing = _types.map((t) => (t.width, t.height)).toSet();
    if (existing.length >= 8 * 7) return; // all 56 combos exhausted
    double w, h;
    do {
      w = (1 + rng.nextInt(8)).toDouble(); // 1..8
      h = (1 + rng.nextInt(7)).toDouble(); // 1..7
    } while (existing.contains((w, h)));
    setState(() {
      _typesChanged();
      _types.add(RectType(
        width: w,
        height: h,
        count: 1 + rng.nextInt(5), // 1..5
        color: kRectColors[_types.length % kRectColors.length],
      ));
    });
  }

  bool get _valid =>
      _types.isNotEmpty &&
      _types.every((t) => t.width > 0 && t.height > 0 && t.count > 0);

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 1,
        title: const Text('BoxIt — Rectangle Packer',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_types.isNotEmpty) ...[
                  _Header(),
                  const SizedBox(height: 4),
                ],
                Expanded(
                  child: _types.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.grid_view,
                                  size: 64, color: Color(0xFF21262D)),
                              const SizedBox(height: 16),
                              const Text('No rectangle types yet',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 16)),
                              const SizedBox(height: 8),
                              const Text('Press "Add Type" to begin',
                                  style: TextStyle(
                                      color: Colors.white24, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _types.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) => _TypeRow(
                            key: ValueKey(i),
                            type: _types[i],
                            onChanged: (t) => setState(() { _typesChanged(); _types[i] = t; }),
                            onDelete: () =>
                                setState(() { _typesChanged(); _types.removeAt(i); }),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ActionBtn(
                      icon: Icons.add,
                      label: 'Add Type',
                      onPressed: _add,
                      color: const Color(0xFF21262D),
                    ),
                    const Spacer(),
                    _ActionBtn(
                      icon: Icons.auto_fix_high,
                      label: 'Optimize',
                      onPressed: _valid
                          ? () => _push(OptimizePage(types: List.from(_types)))
                          : null,
                      color: const Color(0xFF1F6FEB),
                    ),
                    const SizedBox(width: 10),
                    _ActionBtn(
                      icon: Icons.pan_tool_alt,
                      label: 'Manual',
                      onPressed: _valid
                          ? () => _push(ManualPage(
                              types: List.from(_types),
                              savedData: _savedManualData,
                              onSave: (data) => _savedManualData = data,
                            ))
                          : null,
                      color: const Color(0xFF238636),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 46, right: 44),
        child: Row(children: const [
          Expanded(
              child: Text('Width',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600))),
          SizedBox(width: 8),
          Expanded(
              child: Text('Height',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600))),
          SizedBox(width: 8),
          Expanded(
              child: Text('Count',
                  style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w600))),
        ]),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;

  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      this.onPressed});

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF21262D),
          disabledForegroundColor: Colors.white24,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      );
}

// ── Individual row for one rect type ──────────────────────────────────────

class _TypeRow extends StatefulWidget {
  final RectType type;
  final ValueChanged<RectType> onChanged;
  final VoidCallback onDelete;

  const _TypeRow(
      {super.key,
      required this.type,
      required this.onChanged,
      required this.onDelete});

  @override
  State<_TypeRow> createState() => _TypeRowState();
}

class _TypeRowState extends State<_TypeRow> {
  late final TextEditingController _w;
  late final TextEditingController _h;
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _w = TextEditingController(text: _fmt(widget.type.width));
    _h = TextEditingController(text: _fmt(widget.type.height));
    _c = TextEditingController(text: widget.type.count.toString());
  }

  @override
  void didUpdateWidget(_TypeRow old) {
    super.didUpdateWidget(old);
    if (old.type.width != widget.type.width) _w.text = _fmt(widget.type.width);
    if (old.type.height != widget.type.height) _h.text = _fmt(widget.type.height);
    if (old.type.count != widget.type.count) _c.text = widget.type.count.toString();
  }

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _c.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  void _emit() {
    final w = double.tryParse(_w.text) ?? widget.type.width;
    final h = double.tryParse(_h.text) ?? widget.type.height;
    final c = int.tryParse(_c.text) ?? widget.type.count;
    widget.onChanged(widget.type.copyWith(
      width: math.max(0.01, w),
      height: math.max(0.01, h),
      count: math.max(1, c),
    ));
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12, width: 0.8),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: widget.type.color,
                borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(child: _field(_w)),
          const SizedBox(width: 8),
          Expanded(child: _field(_h)),
          const SizedBox(width: 8),
          Expanded(child: _field(_c, isInt: true)),
          const SizedBox(width: 4),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 16, color: Colors.white38),
              onPressed: widget.onDelete,
              hoverColor: Colors.redAccent.withValues(alpha: 0.15),
            ),
          ),
        ]),
      );

  Widget _field(TextEditingController ctrl, {bool isInt = false}) =>
      TextField(
        controller: ctrl,
        onChanged: (_) => _emit(),
        keyboardType: isInt
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: isInt
            ? [FilteringTextInputFormatter.digitsOnly]
            : [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          filled: true,
          fillColor: const Color(0xFF0D1117),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide:
                  const BorderSide(color: Colors.white12, width: 0.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(
                  color: Color(0xFF388BFD), width: 1.5)),
        ),
      );
}
