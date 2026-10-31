import 'package:flutter_test/flutter_test.dart';
import 'package:gudory/features/camera/widgets/controls.dart';

void main() {
  test('live zoom always shows one decimal', () {
    expect(ZoomControlLabels.live(0.94), '0.9×');
    expect(ZoomControlLabels.live(0.9), '0.9×');
    expect(ZoomControlLabels.live(1.0), '1.0×');
    expect(ZoomControlLabels.live(1.04), '1.0×');
    expect(ZoomControlLabels.live(1.1), '1.1×');
    expect(ZoomControlLabels.live(10), '10.0×');
  });

  test('preset chips stay compact', () {
    expect(ZoomControlLabels.preset(0.6), '.6');
    expect(ZoomControlLabels.preset(1), '1');
    expect(ZoomControlLabels.preset(3), '3');
  });
}
