import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Браузер: Notification API и короткие сигналы через Web Audio.

@JS('Notification')
extension type _JSNotification._(JSObject _) implements JSObject {
  external factory _JSNotification(String title, _NotificationOptions options);
  external static String get permission;
  external static JSPromise<JSString> requestPermission();
}

extension type _NotificationOptions._(JSObject _) implements JSObject {
  external factory _NotificationOptions({String? body, String? tag, bool? requireInteraction});
}

@JS('AudioContext')
extension type _AudioContext._(JSObject _) implements JSObject {
  external factory _AudioContext();
  external _OscillatorNode createOscillator();
  external _GainNode createGain();
  external JSObject get destination;
  external double get currentTime;
  external String get state;
  external JSPromise<JSAny?> resume();
}

extension type _OscillatorNode._(JSObject _) implements JSObject {
  external _AudioParam get frequency;
  external set type(String value);
  external JSObject connect(JSObject destination);
  external void start(double when);
  external void stop(double when);
}

extension type _GainNode._(JSObject _) implements JSObject {
  external _AudioParam get gain;
  external JSObject connect(JSObject destination);
}

extension type _AudioParam._(JSObject _) implements JSObject {
  external void setValueAtTime(double value, double time);
  external void linearRampToValueAtTime(double value, double time);
}

bool get supported => globalContext.has('Notification');

String get permission => supported ? _JSNotification.permission : 'unsupported';

Future<bool> requestPermission() async {
  if (!supported) return false;
  if (permission == 'granted') return true;
  final result = await _JSNotification.requestPermission().toDart;
  return result.toDart == 'granted';
}

void show(String title, String body) {
  if (!supported || permission != 'granted') return;
  _JSNotification(title, _NotificationOptions(body: body, tag: 'rodquest-$title', requireInteraction: false));
}

_AudioContext? _ctx;

void beep({bool alarm = false}) {
  if (!globalContext.has('AudioContext')) return;
  final ctx = _ctx ??= _AudioContext();
  if (ctx.state == 'suspended') ctx.resume();
  final t0 = ctx.currentTime + 0.02;
  final count = alarm ? 3 : 1;
  for (var i = 0; i < count; i++) {
    final start = t0 + i * 0.32;
    final osc = ctx.createOscillator();
    final gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(alarm ? 880 : 660, start);
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.linearRampToValueAtTime(alarm ? 0.35 : 0.2, start + 0.02);
    gain.gain.linearRampToValueAtTime(0.0001, start + 0.24);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start(start);
    osc.stop(start + 0.26);
  }
}
