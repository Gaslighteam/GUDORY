import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/features/camera/widgets/controls.dart';

void main() {
  test('minor ticks are evenly spaced at every zoom while scrolling', () {
    const gap = zoomRulerMinorStep * 180;
    for (final zoom in [0.6, 0.83, 1.0, 1.47, 2.0, 3.3, 5.0, 7.7, 9.9]) {
      final xs = zoomRulerMinorTicks(
        zoom: zoom,
        min: 0.6,
        max: 10,
        width: 260,
        pxPerLog: 180,
        majors: const [0.6, 1.0, 2.0, 3.0, 5.0, 10.0],
      );
      expect(xs.length, greaterThan(5), reason: 'zoom $zoom');
      for (var i = 1; i < xs.length; i++) {
        final steps = (xs[i] - xs[i - 1]) / gap;
        // Equal gaps; a gap of 2 steps only where a major tick sits.
        expect(steps, anyOf(closeTo(1, 1e-6), closeTo(2, 1e-6)));
      }
    }
  });
}
