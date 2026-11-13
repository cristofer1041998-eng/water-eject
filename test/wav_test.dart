import 'package:flutter_test/flutter_test.dart';
import 'package:water_eject/main.dart';

void main() {
  test('buildToneWav genera un WAV mono 16-bit coherente', () {
    final bytes = buildToneWav(165);
    expect(bytes.length, greaterThan(44 + 1000));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    // 44.1 kHz * 165 ciclos / 165 Hz = 1 segundo de audio
    expect(bytes.length, 44 + 44100 * 2);
  });

  test('el tono tiene amplitud audible y pico cercano a 1.0', () {
    final bytes = buildToneWav(90);
    int peak = 0;
    for (int i = 44; i + 1 < bytes.length; i += 2) {
      final v = bytes[i] | (bytes[i + 1] << 8);
      final s = v >= 32768 ? v - 65536 : v;
      if (s.abs() > peak) peak = s.abs();
    }
    expect(peak, greaterThan(20000));
    expect(peak, lessThanOrEqualTo(32767));
  });
}
