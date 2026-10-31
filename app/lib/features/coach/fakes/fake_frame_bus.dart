import 'dart:async';

import '../../../core/contracts.dart';
import '../../../core/models.dart';

class FakeFrameBus implements FrameBus {
  final _controller = StreamController<CameraFrame>.broadcast();

  @override
  Stream<CameraFrame> get frames => _controller.stream;

  void add(CameraFrame frame) => _controller.add(frame);

  Future<void> close() => _controller.close();
}
