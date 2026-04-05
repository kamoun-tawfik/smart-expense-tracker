/*
// lib/core/utils/image_processor.dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class ImageProcessor {
  /// Returns true if image is sharp and well-lit enough for OCR
  static Future<bool> isImageQualityGood(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return false;

    final gray = img.grayscale(image);
    final resized = img.copyResize(gray, width: 300);

    final variance = _laplacianVariance(resized);
    if (variance < 80) return false;

    final brightness = _meanBrightness(resized);
    if (brightness < 40 || brightness > 240) return false;

    return true;
  }

  static double _laplacianVariance(img.Image image) {
    final data = image.data!;
    double sum = 0, sumSq = 0;
    int count = 0;

    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        final center = data.getPixel(x, y).r.toDouble();
        final neighbors = [
          data.getPixel(x - 1, y).r,
          data.getPixel(x + 1, y).r,
          data.getPixel(x, y - 1).r,
          data.getPixel(x, y + 1).r,
        ].map((e) => e.toDouble()).toList();

        final laplacian = 4 * center - neighbors.reduce((a, b) => a + b);
        sum += laplacian;
        sumSq += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0) return 0;
    final mean = sum / count;
    return sumSq / count - mean * mean;
  }

  static double _meanBrightness(img.Image image) {
    final data = image.data!;
    double sum = 0;
    for (final pixel in data) {
      sum += pixel.r;
    }
    return sum / data.length;
  }

  /// Balanced preprocessing pipeline for receipts
  /// Works reliably on both clean printed receipts and messy/low-quality ones
  static Uint8List preprocessReceipt(Uint8List originalBytes) {
    var image = img.decodeImage(originalBytes);
    if (image == null) return originalBytes;

    // 1. Grayscale
    image = img.grayscale(image);

    // 2. Moderate contrast and brightness boost (safe for clean receipts)
    image = img.adjustColor(
      image,
      contrast: 1.8,     // Reduced from 3.0 to avoid over-saturation
      brightness: 0.1,   // Gentle brightness lift
    );

    // 3. Light noise reduction
    image = img.gaussianBlur(image, radius: 1);

    // 4. Apply aggressive binarization only if the image has low sharpness/contrast
    // This prevents destroying clean receipts while still helping messy ones
    final variance = _laplacianVariance(img.copyResize(image, width: 300));
    if (variance < 150) {
      // Low-contrast/messy receipt → use the "magic" sequence
      image = img.adjustColor(image, contrast: 2.0);
      image = img.invert(image);
      image = img.gaussianBlur(image, radius: 1);
      image = img.invert(image);
    }

    // 5. Final gentle sharpen to restore edges
    image = img.convolution(
      image,
      filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
      div: 1,
      offset: 0,
    );

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  /// Pick sharpest from burst
  static Future<Uint8List> pickSharpestFromBurst(List<XFile> files) async {
    double bestScore = -1;
    Uint8List? bestBytes;

    for (final file in files) {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) continue;

      final score = _laplacianVariance(img.grayscale(img.copyResize(image, width: 300)));
      if (score > bestScore) {
        bestScore = score;
        bestBytes = bytes;
      }
    }

    return bestBytes ?? await files.first.readAsBytes();
  }
}
*/