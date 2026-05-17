import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class AvatarCropScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const AvatarCropScreen({super.key, required this.imageBytes});

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  static const LinearGradient _grad =
      LinearGradient(colors: [Color(0xFFF5A623), Color(0xFFBF5B0A)]);

  final TransformationController _ctrl = TransformationController();
  final GlobalKey _stackKey = GlobalKey();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Capture the whole Stack (image + overlay) then crop the circle out
      final boundary =
          _stackKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final fullImg = await boundary.toImage(pixelRatio: 2.0);
      final size = MediaQuery.of(context).size;
      final circleDia = size.width - 32;
      final circleTop = (size.height - circleDia) / 2;

      // Crop to the circle rect from the captured image
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final r = circleDia * 2.0; // pixelRatio 2.0
      final t = circleTop * 2.0;
      final l = 16.0 * 2.0;

      // Clip to circle then draw the relevant portion
      canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, r, r)));
      canvas.drawImageRect(
        fullImg,
        Rect.fromLTWH(l, t, r, r),
        Rect.fromLTWH(0, 0, r, r),
        Paint(),
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(r.toInt(), r.toInt());
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        setState(() => _saving = false);
        return;
      }
      if (mounted) Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleDia = size.width - 32;
    final circleCenter =
        Offset(size.width / 2, (size.height - circleDia) / 2 + circleDia / 2);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // ── Single RepaintBoundary wrapping everything ─────────────
        Positioned.fill(
          child: RepaintBoundary(
            key: _stackKey,
            child: Stack(children: [
              // Full-screen interactive image — ONE instance only
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

              // Dark overlay with circular cutout
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _OverlayPainter(
                      circleCenter: circleCenter,
                      circleRadius: circleDia / 2,
                    ),
                  ),
                ),
              ),

              // Gold circle border
              Positioned(
                left: 16,
                top: (size.height - circleDia) / 2,
                width: circleDia,
                height: circleDia,
                child: IgnorePointer(
                  child: CustomPaint(painter: _CircleBorderPainter()),
                ),
              ),
            ]),
          ),
        ),

        // ── Top bar (outside RepaintBoundary so not captured) ──────
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
                  child: Text('Drag and pinch to adjust',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 48),
              ]),
            ),
          ),
        ),

        // ── Bottom buttons ─────────────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(children: [
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

class _OverlayPainter extends CustomPainter {
  final Offset circleCenter;
  final double circleRadius;
  const _OverlayPainter(
      {required this.circleCenter, required this.circleRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addOval(Rect.fromCircle(center: circleCenter, radius: circleRadius));
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, hole),
      Paint()..color = Colors.black.withOpacity(0.6),
    );
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.circleCenter != circleCenter || old.circleRadius != circleRadius;
}

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
