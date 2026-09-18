import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent;
import 'package:flutter_tvos/flutter_tvos.dart'
    show TvRemoteController, TvRemoteTouchEvent, TvRemoteTouchPhase;

import '../../preference/preference_constants.dart'
    show SiriRemoteSwipeSensitivity;
import 'dpad_keys.dart';
import 'gamepad/gamepad_key_synthesizer.dart';

/// Turns Siri Remote touchpad gestures into focus navigation. Focus steps one
/// item at a time as the finger travels and stops when the finger does, so a
/// drag moves the same number of items however fast it was made.
///
/// The engine's own swipe detectors are switched off by config, since one
/// emits a single arrow per gesture and the other latches while the finger
/// rests and runs focus away. Clicks and buttons stay native: the engine turns
/// every directional press it is handed, whether from the clickpad ring, an
/// infrared remote, or a controller d-pad, into a real arrow key event and
/// repeats it while held. Steps go out as real arrow key events through
/// [GamepadKeySynthesizer], so every existing key handler and focus widget
/// behaves exactly as it does for a click.
///
/// The clickpad on the second generation remote and later is the touch
/// surface itself, so every click, on the directional ring or the centre,
/// lands with the thumb on the pad and reaches here as a touch as well as a
/// press. The press is the user's whole intent and the thumb rolling as it
/// pushes down is not a swipe, so once a press arrives the touch under it is
/// left alone until the thumb lifts. Otherwise a firm click can nudge focus
/// one item before the button acts on it: a ring click steps twice, and a
/// select lands on the neighbour of what was focused.
///
/// While a native view controller covers Flutter the engine stops forwarding
/// touches, so this layer goes quiet on its own.
class SiriRemoteGlide {
  SiriRemoteGlide._();

  static final SiriRemoteGlide instance = SiriRemoteGlide._();

  SiriRemoteSwipeSensitivity sensitivity = SiriRemoteSwipeSensitivity.medium;

  final GamepadKeySynthesizer _synthesizer = GamepadKeySynthesizer();

  bool _attached = false;
  bool _touching = false;

  /// Set once a press lands while the pad is touched. The pad feels the thumb
  /// before the click travels and both reports leave the main thread in
  /// order, so the touch is always known by the time the press is.
  bool _pressedThisTouch = false;
  double _lastX = 0;
  double _lastY = 0;
  double _accX = 0;
  double _accY = 0;
  bool _steppedThisGesture = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    TvRemoteController.instance.addRawListener(_onTouch);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @visibleForTesting
  void debugReset() {
    _synthesizer.releaseAll();
    _touching = false;
    _pressedThisTouch = false;
  }

  /// Undoes [attach] so a test can wire the glide up again. The test binding
  /// drops every hardware keyboard handler between tests, which would leave a
  /// second attach a no-op with nothing listening.
  @visibleForTesting
  void debugDetach() {
    if (!_attached) return;
    _attached = false;
    TvRemoteController.instance.removeRawListener(_onTouch);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
  }

  @visibleForTesting
  void debugHandleTouch(TvRemoteTouchEvent event) => _onTouch(event);

  @visibleForTesting
  void debugHandleKeyEvent(KeyEvent event) => _onKeyEvent(event);

  /// Watches for directional presses, the ring on the clickpad or the arrows
  /// of any other remote, so the touch that made one is not also read as a
  /// swipe. Only real presses count: the steps this class makes are arrows
  /// too, and taking them as clicks would end every swipe at its first step.
  /// Never claims the event, so the focus tree sees it as before.
  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!event.logicalKey.isDirectional) return false;
    if (GamepadKeySynthesizer.isSynthetic(event.physicalKey)) return false;
    if (_touching) _pressedThisTouch = true;
    return false;
  }

  void _onTouch(TvRemoteTouchEvent event) {
    switch (event.phase) {
      case TvRemoteTouchPhase.started:
        _beginGesture(event.x, event.y);
      case TvRemoteTouchPhase.move:
        if (!_touching) {
          _beginGesture(event.x, event.y);
          return;
        }
        _onMove(event.x, event.y);
      case TvRemoteTouchPhase.ended:
      case TvRemoteTouchPhase.cancelled:
        _touching = false;
        _pressedThisTouch = false;
      case TvRemoteTouchPhase.clickStart:
        // The engine reports the select click here before it emits the key,
        // so the centre of the clickpad is covered the same way as the ring.
        if (_touching) _pressedThisTouch = true;
      case TvRemoteTouchPhase.loc:
      case TvRemoteTouchPhase.clickEnd:
        break;
    }
  }

  void _beginGesture(double x, double y) {
    _touching = true;
    _lastX = x;
    _lastY = y;
    _accX = 0;
    _accY = 0;
    _steppedThisGesture = false;
    _pressedThisTouch = false;
  }

  void _onMove(double x, double y) {
    final dx = x - _lastX;
    final dy = y - _lastY;
    _lastX = x;
    _lastY = y;
    // The thumb behind a directional press is pushing a button, not swiping.
    if (_pressedThisTouch) return;

    // A reversal replaces the accumulator instead of unwinding it, so
    // changing direction mid drag responds immediately.
    _accX = dx.sign != 0 && dx.sign != _accX.sign ? dx : _accX + dx;
    _accY = dy.sign != 0 && dy.sign != _accY.sign ? dy : _accY + dy;

    final threshold = _steppedThisGesture
        ? sensitivity.stepTravel
        : sensitivity.firstStepTravel;
    final horizontal = _accX.abs() >= _accY.abs();
    final travel = horizontal ? _accX : _accY;
    if (travel.abs() < threshold) return;

    final direction = horizontal
        ? (travel > 0 ? GamepadNavKey.right : GamepadNavKey.left)
        // The pad reports up as negative y, so travelling positive is a
        // finger moving down the surface.
        : (travel > 0 ? GamepadNavKey.down : GamepadNavKey.up);
    _step(direction);
    _steppedThisGesture = true;
    if (horizontal) {
      _accX -= travel.sign * threshold;
      _accY = 0;
    } else {
      _accY -= travel.sign * threshold;
      _accX = 0;
    }
  }

  void _step(GamepadNavKey direction) {
    _synthesizer.press(direction);
    _synthesizer.release(direction);
  }
}
