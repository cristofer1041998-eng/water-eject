import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF04121F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const WaterEjectApp());
}

class WaterEjectApp extends StatelessWidget {
  const WaterEjectApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00C2FF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Water Eject',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: base.copyWith(
          surface: const Color(0xFF04121F),
          primary: const Color(0xFF00D1FF),
          secondary: const Color(0xFF7AF5E4),
        ),
        scaffoldBackgroundColor: const Color(0xFF04121F),
        fontFamily: 'Roboto',
      ),
      home: const HomePage(),
    );
  }
}

/// Genera un WAV PCM 16-bit mono con un tono senoidal de frecuencia [freq]
/// ajustada a un número entero de ciclos para que el bucle sea perfecto.
Uint8List buildToneWav(double freq, {int sampleRate = 44100}) {
  int cycles = freq.round().clamp(40, 4000);
  double realFreq = cycles.toDouble();
  int total = (sampleRate * cycles / realFreq).round();
  const int channels = 1;
  const int bits = 16;
  int dataSize = total * channels * bits ~/ 8;
  ByteData bd = ByteData(44 + dataSize);

  void writeStr(int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      bd.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeStr(0, 'RIFF');
  bd.setUint32(4, 36 + dataSize, Endian.little);
  writeStr(8, 'WAVE');
  writeStr(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * channels * bits ~/ 8, Endian.little);
  bd.setUint16(32, channels * bits ~/ 8, Endian.little);
  bd.setUint16(34, bits, Endian.little);
  writeStr(36, 'data');
  bd.setUint32(40, dataSize, Endian.little);

  // Amplitud con un leve refuerzo de armónicos para mover más aire.
  const double amp = 0.92;
  for (int i = 0; i < total; i++) {
    double t = i / sampleRate;
    double v = math.sin(2 * math.pi * realFreq * t) * 0.80 +
        math.sin(2 * math.pi * realFreq * 2 * t) * 0.14 +
        math.sin(2 * math.pi * realFreq * 3 * t) * 0.06;
    int s = (v * amp * 32767).round().clamp(-32768, 32767);
    bd.setInt16(44 + i * 2, s, Endian.little);
  }
  return bd.buffer.asUint8List();
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  static const List<_Preset> _presets = <_Preset>[
    _Preset('Eyectar', 165, Icons.water_drop),
    _Preset('Gota', 145, Icons.grain),
    _Preset('Bajos', 90, Icons.graphic_eq),
    _Preset('Agudos', 220, Icons.bolt),
  ];

  final AudioPlayer _player = AudioPlayer();
  final List<Timer> _timers = <Timer>[];

  late final AnimationController _waveCtrl;
  late final AnimationController _pulseCtrl;

  double _freq = 165;
  double _volume = 0.9;
  int _seconds = 30; // 0 = continuo
  int _remaining = 0;
  bool _playing = false;
  bool _loading = false;
  String? _error;

  int get _activePreset {
    for (int i = 0; i < _presets.length; i++) {
      if ((_presets[i].hz - _freq).abs() < 2) return i;
    }
    return -1;
  }

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _player.setReleaseMode(ReleaseMode.loop);
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (state == PlayerState.completed && _playing) {
        _stop();
      }
    });
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _waveCtrl.dispose();
    _pulseCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = buildToneWav(_freq);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/water_eject_tone.wav');
      await file.writeAsBytes(bytes, flush: true);

      await _player.stop();
      await _player.setVolume(_volume);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(DeviceFileSource(file.path), volume: _volume);

      HapticFeedback.heavyImpact();
      _pulseCtrl.repeat(reverse: true);

      setState(() {
        _playing = true;
        _loading = false;
        _remaining = _seconds;
      });

      for (final t in _timers) {
        t.cancel();
      }
      _timers.clear();
      if (_seconds > 0) {
        _timers.add(
          Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!_playing) {
              timer.cancel();
              return;
            }
            setState(() {
              _remaining = _remaining - 1;
            });
            if (_remaining <= 0) {
              timer.cancel();
              _stop();
            }
          }),
        );
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _playing = false;
        _error = 'No se pudo reproducir el tono.';
      });
    }
  }

  Future<void> _stop() async {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _pulseCtrl.stop();
    _pulseCtrl.value = 0;
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _playing = false;
      _remaining = 0;
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _stop();
    } else {
      await _start();
    }
  }

  void _setFreq(double hz) {
    setState(() => _freq = hz.roundToDouble());
    if (_playing) {
      _stop();
      _start();
    }
  }

  String get _timerLabel {
    if (_seconds == 0) return '∞';
    if (_playing) {
      final m = (_remaining ~/ 60).toString().padLeft(2, '0');
      final s = (_remaining % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }
    return '${_seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    const pad = EdgeInsets.symmetric(horizontal: 20);

    return Scaffold(
      body: Stack(
        children: <Widget>[
          const _Background(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const SizedBox(height: 8),
                      Padding(
                        padding: pad,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const <Widget>[
                            Icon(Icons.water_drop,
                                color: Color(0xFF00D1FF), size: 26),
                            SizedBox(width: 8),
                            Text(
                              'WATER EJECT',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: pad,
                        child: Text(
                          'Expulsa el agua del altavoz con ondas de baja frecuencia',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.62),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildDial(),
                      const SizedBox(height: 18),
                      Padding(padding: pad, child: _buildFrequencyCard()),
                      const SizedBox(height: 12),
                      Padding(padding: pad, child: _buildTimerRow()),
                      const SizedBox(height: 12),
                      Padding(padding: pad, child: _buildVolumeRow()),
                      const SizedBox(height: 14),
                      Padding(padding: pad, child: _buildPresets()),
                      const SizedBox(height: 16),
                      Padding(padding: pad, child: _buildTip()),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFFF7A7A), fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDial() {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_waveCtrl, _pulseCtrl]),
      builder: (context, _) {
        final glow = _playing ? 0.35 + 0.35 * _pulseCtrl.value : 0.0;
        return SizedBox(
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                size: const Size(260, 260),
                painter: _RipplePainter(
                  progress: _waveCtrl.value,
                  intensity: _playing ? 1 : 0.25,
                ),
              ),
              Container(
                width: 186,
                height: 186,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF0B4A6B), Color(0xFF06222F)],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF00D1FF).withValues(alpha: glow),
                      blurRadius: 46,
                      spreadRadius: 6,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.09),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _loading ? null : _toggle,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (_loading)
                            const SizedBox(
                              width: 44,
                              height: 44,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF00D1FF)),
                              ),
                            )
                          else
                            Icon(
                              _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                              size: 76,
                              color: Colors.white,
                            ),
                          const SizedBox(height: 2),
                          Text(
                            _playing ? 'DETENER' : 'INICIAR',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_freq.round()} Hz',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF7AF5E4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_playing)
                Positioned(
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                          color: const Color(0xFF00D1FF).withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      _seconds == 0 ? 'SONANDO · ∞' : 'SONANDO · $_timerLabel',
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9BE9FF),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFrequencyCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.tune, size: 16, color: Color(0xFF7AF5E4)),
              const SizedBox(width: 8),
              const Text(
                'Frecuencia',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${_freq.round()} Hz',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF7AF5E4),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: const Color(0xFF00D1FF),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: Colors.white,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              min: 60,
              max: 300,
              divisions: 240,
              value: _freq,
              onChanged: (v) => setState(() => _freq = v),
              onChangeEnd: _setFreq,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _hint('60 Hz · bajos'),
              _hint('300 Hz · agudos'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hint(String t) => Text(
        t,
        style: TextStyle(
          fontSize: 10.5,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      );

  Widget _buildTimerRow() {
    const options = <int>[15, 30, 60, 0];
    return Row(
      children: <Widget>[
        for (final s in options)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: s == 0 ? 0 : 8),
              child: _Chip(
                label: s == 0 ? '∞' : '${s}s',
                selected: _seconds == s,
                onTap: () {
                  setState(() => _seconds = s);
                  if (_playing) {
                    _stop();
                    _start();
                  }
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVolumeRow() {
    return _Card(
      child: Row(
        children: <Widget>[
          Icon(
            _volume == 0
                ? Icons.volume_off_rounded
                : (_volume < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded),
            size: 18,
            color: const Color(0xFF7AF5E4),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: const Color(0xFF7AF5E4),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                thumbColor: Colors.white,
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: _volume,
                onChanged: (v) {
                  setState(() => _volume = v);
                  _player.setVolume(v);
                },
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '${(_volume * 100).round()}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresets() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: <Widget>[
        for (int i = 0; i < _presets.length; i++)
          GestureDetector(
            onTap: () => _setFreq(_presets[i].hz.toDouble()),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: _activePreset == i
                    ? const Color(0xFF00D1FF).withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: _activePreset == i
                      ? const Color(0xFF00D1FF).withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    _presets[i].icon,
                    size: 14,
                    color: _activePreset == i
                        ? const Color(0xFF9BE9FF)
                        : Colors.white60,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_presets[i].label} ${_presets[i].hz}Hz',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _activePreset == i
                          ? const Color(0xFF9BE9FF)
                          : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTip() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.tips_and_updates_outlined,
              size: 16, color: Color(0xFF7AF5E4)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sube el volumen al máximo, coloca el teléfono boca abajo y deja '
              'sonar el tono 30 segundos. Repite con la rejilla apuntando hacia '
              'abajo hasta que el sonido vuelva a sonar nítido.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Preset {
  final String label;
  final int hz;
  final IconData icon;
  const _Preset(this.label, this.hz, this.icon);
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00D1FF).withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF00D1FF).withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF9BE9FF) : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF07293C),
            Color(0xFF04121F),
            Color(0xFF020A12),
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final double intensity;
  _RipplePainter({required this.progress, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    for (int i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final r = 90 + (maxR - 90) * t;
      final alpha = (1 - t) * 0.35 * intensity;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF00D1FF).withValues(alpha: alpha);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) =>
      old.progress != progress || old.intensity != intensity;
}
