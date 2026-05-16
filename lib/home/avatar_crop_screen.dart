import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ─────────────────────────────────────────────────────────────────────
// AvatarCropScreen — full screen editor exactly like Facebook
// - Image fills the whole screen
// - Dark semi-transparent overlay with a circular cutout showing the crop
// - User drags and pinches the image freely underneath
// - "Save" captures only what's inside the circle
// ─────────────────────────────────────────────────────────────────────
class AvatarCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const AvatarCropScreen({super.key, required this.imageBytes});

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  static const LinearGradient _grad =
      LinearGradient(colors: [Color(0xFFF5A623), Color(0xFFBF5B0A)]);

  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _ctrl = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2.0);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        setState(() => _saving = false);
        return;
      }
      if (mounted) Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Circle sits in the centre — same width as screen, square
    final circleDia = size.width - 32;
    final circleTop = (size.height - circleDia) / 2;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── 1. Full-screen interactive image ─────────────────────────
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _ctrl,
            minScale: 0.5,
            maxScale: 8.0,
            clipBehavior: Clip.none,
            child: Image.memory(
              widget.imageBytes,
              fit: BoxFit.contain,
              width: size.width,
            ),
          ),
        ),

        // ── 2. Dark overlay with circular cutout ─────────────────────
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _OverlayPainter(
                circleCenter: Offset(size.width / 2, circleTop + circleDia / 2),
                circleRadius: circleDia / 2,
              ),
            ),
          ),
        ),

        // ── 3. RepaintBoundary — captures only the circle area ────────
        Positioned(
          left: 16,
          top: circleTop,
          width: circleDia,
          height: circleDia,
          child: IgnorePointer(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: ClipOval(
                child: InteractiveViewer(
                  transformationController: _ctrl,
                  minScale: 0.5,
                  maxScale: 8.0,
                  clipBehavior: Clip.none,
                  child: Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.contain,
                    width: size.width,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── 4. Gold circle border ─────────────────────────────────────
        Positioned(
          left: 16,
          top: circleTop,
          width: circleDia,
          height: circleDia,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _CircleBorderPainter(),
            ),
          ),
        ),

        // ── 5. Top bar ────────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  onPressed: () => Navigator.of(context).pop(null),
                ),
                const Expanded(
                  child: Text(
                    'Drag and pinch to adjust',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 48),
              ]),
            ),
          ),
        ),

        // ── 6. Bottom buttons ─────────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(children: [
                // Cancel
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.4), width: 1.5),
                      ),
                      child: const Text('Cancel',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Save
                Expanded(
                  child: GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: _grad,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: _saving
                          ? const Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2)))
                          : const Text('Save Photo',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// Dark overlay with a transparent circular cutout in the centre
class _OverlayPainter extends CustomPainter {
  final Offset circleCenter;
  final double circleRadius;
  const _OverlayPainter(
      {required this.circleCenter, required this.circleRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withOpacity(0.55);
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addOval(Rect.fromCircle(center: circleCenter, radius: circleRadius));
    final cut = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(cut, overlay);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.circleCenter != circleCenter || old.circleRadius != circleRadius;
}

// Gold circle border
class _CircleBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - 1.5,
      Paint()
        ..color = const Color(0xFFD4A853)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
