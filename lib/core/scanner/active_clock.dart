/// Đồng hồ chỉ chạy khi quét thật sự diễn ra: dừng khi người dùng tạm dừng HOẶC khi
/// app ra nền (hệ điều hành làm ngừng/chậm tiến trình, thời gian đó không phải thời
/// gian quét). Thời gian ngoài nền được cộng riêng ở [backgroundTime].
class ActiveClock {
  final Stopwatch _active = Stopwatch();
  final Stopwatch _background = Stopwatch();
  bool _wanted = false; // người dùng/ứng dụng muốn đồng hồ chạy
  bool _foreground = true;

  /// Thời gian quét thật (không tính tạm dừng, không tính lúc ở nền).
  Duration get elapsed => _active.elapsed;

  /// Tổng thời gian app nằm ngoài nền khi đang quét (không tính vào [elapsed]).
  Duration get backgroundTime => _background.elapsed;

  bool get isRunning => _active.isRunning;

  void start() {
    _wanted = true;
    _sync();
  }

  void stop() {
    _wanted = false;
    _sync();
  }

  void reset() {
    _active.reset();
    _background.reset();
    _sync();
  }

  /// Gọi khi vòng đời app đổi: false = ra nền, true = quay lại.
  void setForeground(bool value) {
    _foreground = value;
    _sync();
  }

  void _sync() {
    if (_wanted && _foreground) {
      _active.start();
    } else {
      _active.stop();
    }
    if (_wanted && !_foreground) {
      _background.start();
    } else {
      _background.stop();
    }
  }
}
