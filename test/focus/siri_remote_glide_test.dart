import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tvos/flutter_tvos.dart'
    show TvRemoteTouchEvent, TvRemoteTouchPhase;
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/focus/gamepad/gamepad_key_synthesizer.dart';
import 'package:moonfin/util/focus/siri_remote_glide.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final glide = SiriRemoteGlide.instance;
  final pressed = <LogicalKeyboardKey>[];
  bool capture(KeyEvent event) {
    if (event is KeyDownEvent &&
        GamepadKeySynthesizer.isSynthetic(event.physicalKey)) {
      pressed.add(event.logicalKey);
    }
    return true;
  }

  void touch(TvRemoteTouchPhase phase, double x, double y) {
    glide.debugHandleTouch(TvRemoteTouchEvent(phase: phase, x: x, y: y));
  }

  /// A directional press the way the engine reports one from the clickpad
  /// ring, an infrared remote or a controller d-pad: a real arrow key on its
  /// own physical key, nothing like the ones the glide synthesizes.
  void buttonDown(LogicalKeyboardKey key) {
    glide.debugHandleKeyEvent(
      KeyDownEvent(
        physicalKey: _physicalFor(key),
        logicalKey: key,
        timeStamp: Duration.zero,
      ),
    );
  }

  void buttonUp(LogicalKeyboardKey key) {
    glide.debugHandleKeyEvent(
      KeyUpEvent(
        physicalKey: _physicalFor(key),
        logicalKey: key,
        timeStamp: Duration.zero,
      ),
    );
  }

  setUp(() {
    pressed.clear();
    // The step counts below are written against the high thresholds.
    glide.sensitivity = SiriRemoteSwipeSensitivity.high;
    HardwareKeyboard.instance.addHandler(capture);
  });

  tearDown(() {
    glide.debugReset();
    glide.debugDetach();
    HardwareKeyboard.instance.removeHandler(capture);
  });

  test('medium is the default and lower sensitivity steps less per drag', () {
    expect(
      UserPreferences.siriRemoteSwipeSensitivity.defaultValue,
      SiriRemoteSwipeSensitivity.medium,
    );

    int stepsFor(SiriRemoteSwipeSensitivity sensitivity) {
      glide.sensitivity = sensitivity;
      pressed.clear();
      var x = -0.9;
      touch(TvRemoteTouchPhase.started, x, 0);
      // A full edge-to-edge slow drag.
      for (var i = 0; i < 18; i++) {
        x += 0.1;
        touch(TvRemoteTouchPhase.move, x, 0);
      }
      touch(TvRemoteTouchPhase.ended, x, 0);
      return pressed.length;
    }

    final high = stepsFor(SiriRemoteSwipeSensitivity.high);
    final medium = stepsFor(SiriRemoteSwipeSensitivity.medium);
    final low = stepsFor(SiriRemoteSwipeSensitivity.low);
    expect(high, 5);
    expect(medium, 3);
    expect(low, 2);
  });

  testWidgets('slow drag steps focus per distance and stops on release', (
    tester,
  ) async {
    touch(TvRemoteTouchPhase.started, -0.8, 0);
    var x = -0.8;
    // 16 moves of 0.1 each, crossing 1.6 units of travel: one step at 0.28
    // then one every 0.36, so four steps in total.
    for (var i = 0; i < 16; i++) {
      x += 0.1;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    expect(pressed, List.filled(4, LogicalKeyboardKey.arrowRight));

    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length, 4, reason: 'a drag must not keep moving');
  });

  testWidgets('dragging toward positive y steps down', (tester) async {
    touch(TvRemoteTouchPhase.started, 0, -0.2);
    touch(TvRemoteTouchPhase.move, 0, 0.2);
    expect(pressed, [LogicalKeyboardKey.arrowDown]);
    touch(TvRemoteTouchPhase.ended, 0, 0.2);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('dragging toward negative y steps up', (tester) async {
    touch(TvRemoteTouchPhase.started, 0, 0.2);
    touch(TvRemoteTouchPhase.move, 0, -0.2);
    expect(pressed, [LogicalKeyboardKey.arrowUp]);
    touch(TvRemoteTouchPhase.ended, 0, -0.2);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a fast flick does not auto scroll after release', (
    tester,
  ) async {
    touch(TvRemoteTouchPhase.started, -0.6, 0);
    var x = -0.6;
    for (var i = 0; i < 5; i++) {
      x += 0.15;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    final duringDrag = pressed.length;
    expect(duringDrag, greaterThan(0));

    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(
      pressed.length,
      duringDrag,
      reason: 'the finger lifting must end the gesture',
    );
  });

  testWidgets('a flick travels the same distance as a slow drag', (
    tester,
  ) async {
    touch(TvRemoteTouchPhase.started, -0.8, 0);
    var slow = -0.8;
    for (var i = 0; i < 16; i++) {
      slow += 0.1;
      touch(TvRemoteTouchPhase.move, slow, 0);
    }
    touch(TvRemoteTouchPhase.ended, slow, 0);
    final slowSteps = pressed.length;

    pressed.clear();
    touch(TvRemoteTouchPhase.started, -0.8, 0);
    var fast = -0.8;
    // The same 1.6 units, delivered in four large moves instead of sixteen
    // small ones.
    for (var i = 0; i < 4; i++) {
      fast += 0.4;
      touch(TvRemoteTouchPhase.move, fast, 0);
    }
    touch(TvRemoteTouchPhase.ended, fast, 0);
    await tester.pump(const Duration(seconds: 3));

    expect(
      pressed.length,
      slowSteps,
      reason: 'travel decides the step count, not speed',
    );
  });

  testWidgets('holding still after a swipe emits nothing more', (tester) async {
    touch(TvRemoteTouchPhase.started, -0.6, 0);
    var x = -0.6;
    for (var i = 0; i < 5; i++) {
      x += 0.15;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    final afterSwipe = pressed.length;

    // Finger resting on the pad: repeated moves that report the same point.
    for (var i = 0; i < 20; i++) {
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    await tester.pump(const Duration(seconds: 3));
    expect(
      pressed.length,
      afterSwipe,
      reason: 'a held finger must not step focus',
    );

    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed.length, afterSwipe);
  });

  testWidgets('direction reversal mid drag responds immediately', (
    tester,
  ) async {
    touch(TvRemoteTouchPhase.started, 0.0, 0);
    touch(TvRemoteTouchPhase.move, 0.3, 0);
    expect(pressed, [LogicalKeyboardKey.arrowRight]);

    // Coming back shouldn't have to unwind the forward accumulator.
    touch(TvRemoteTouchPhase.move, 0.0, 0);
    touch(TvRemoteTouchPhase.move, -0.1, 0);
    expect(pressed.last, LogicalKeyboardKey.arrowLeft);
    touch(TvRemoteTouchPhase.ended, -0.1, 0);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a clickpad ring press is not read as a swipe as well', (
    tester,
  ) async {
    // The thumb lands on the right edge of the ring, the click registers as a
    // real arrow press, and the thumb rolls inward as it pushes. That roll is
    // well past the first step threshold on high.
    touch(TvRemoteTouchPhase.started, 0.85, 0.05);
    buttonDown(LogicalKeyboardKey.arrowRight);
    touch(TvRemoteTouchPhase.move, 0.7, 0.05);
    touch(TvRemoteTouchPhase.move, 0.5, 0.0);
    touch(TvRemoteTouchPhase.move, 0.3, -0.05);
    buttonUp(LogicalKeyboardKey.arrowRight);
    touch(TvRemoteTouchPhase.move, 0.25, -0.05);
    touch(TvRemoteTouchPhase.ended, 0.25, -0.05);
    await tester.pump(const Duration(seconds: 3));
    expect(
      pressed,
      isEmpty,
      reason: 'the button already moved focus; the thumb under it must not',
    );
  });

  testWidgets(
    'a held ring button keeps the touch quiet until the thumb lifts',
    (tester) async {
      touch(TvRemoteTouchPhase.started, 0.0, 0.8);
      buttonDown(LogicalKeyboardKey.arrowDown);
      // The engine repeats the held arrow itself; the pad meanwhile sees the
      // thumb drifting a full step's worth.
      for (var i = 0; i < 8; i++) {
        touch(TvRemoteTouchPhase.move, 0.0, 0.8 - i * 0.1);
      }
      expect(pressed, isEmpty);
      buttonUp(LogicalKeyboardKey.arrowDown);
      touch(TvRemoteTouchPhase.ended, 0.0, 0.1);
      await tester.pump(const Duration(seconds: 3));
      expect(pressed, isEmpty);
    },
  );

  testWidgets('a select click is not read as a swipe either', (tester) async {
    // Clicking the centre of the clickpad rolls the thumb too, and a step
    // here would move focus off the item the select was meant for.
    touch(TvRemoteTouchPhase.started, 0.1, 0.1);
    touch(TvRemoteTouchPhase.clickStart, 0, 0);
    touch(TvRemoteTouchPhase.move, 0.1, 0.3);
    touch(TvRemoteTouchPhase.move, 0.1, 0.5);
    touch(TvRemoteTouchPhase.clickEnd, 0, 0);
    touch(TvRemoteTouchPhase.ended, 0.1, 0.5);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed, isEmpty);
  });

  testWidgets('a swipe after a ring press works as before', (tester) async {
    touch(TvRemoteTouchPhase.started, 0.85, 0);
    buttonDown(LogicalKeyboardKey.arrowRight);
    touch(TvRemoteTouchPhase.move, 0.6, 0);
    buttonUp(LogicalKeyboardKey.arrowRight);
    touch(TvRemoteTouchPhase.ended, 0.6, 0);
    expect(pressed, isEmpty);

    // A fresh touch is a swipe again.
    touch(TvRemoteTouchPhase.started, -0.6, 0);
    touch(TvRemoteTouchPhase.move, -0.2, 0);
    expect(pressed, [LogicalKeyboardKey.arrowRight]);
    touch(TvRemoteTouchPhase.ended, -0.2, 0);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a directional press with the pad untouched changes nothing', (
    tester,
  ) async {
    // An infrared or third party remote sends arrows with no finger on the
    // Siri Remote. The next swipe must not be taken for a click.
    buttonDown(LogicalKeyboardKey.arrowLeft);
    buttonUp(LogicalKeyboardKey.arrowLeft);
    touch(TvRemoteTouchPhase.started, 0.6, 0);
    touch(TvRemoteTouchPhase.move, 0.2, 0);
    expect(pressed, [LogicalKeyboardKey.arrowLeft]);
    touch(TvRemoteTouchPhase.ended, 0.2, 0);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the glide\'s own steps do not end the swipe that made them', (
    tester,
  ) async {
    // Once attached the steps come back through the same hardware keyboard
    // handler that watches for button presses. They are arrows too, and if
    // they counted the first one would silence the rest of the drag.
    glide.attach();
    touch(TvRemoteTouchPhase.started, -0.8, 0);
    var x = -0.8;
    for (var i = 0; i < 16; i++) {
      x += 0.1;
      touch(TvRemoteTouchPhase.move, x, 0);
    }
    expect(pressed, List.filled(4, LogicalKeyboardKey.arrowRight));
    touch(TvRemoteTouchPhase.ended, x, 0);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a non directional key under the thumb leaves the swipe alone', (
    tester,
  ) async {
    touch(TvRemoteTouchPhase.started, -0.6, 0);
    buttonDown(LogicalKeyboardKey.select);
    touch(TvRemoteTouchPhase.move, -0.2, 0);
    expect(pressed, [LogicalKeyboardKey.arrowRight]);
    buttonUp(LogicalKeyboardKey.select);
    touch(TvRemoteTouchPhase.ended, -0.2, 0);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('attach wires the press watch into the hardware keyboard', (
    tester,
  ) async {
    glide.attach();
    touch(TvRemoteTouchPhase.started, 0.85, 0);
    await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
    touch(TvRemoteTouchPhase.move, 0.4, 0);
    await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
    touch(TvRemoteTouchPhase.ended, 0.4, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(pressed, isEmpty);
  });
}

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.arrowUp => PhysicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown => PhysicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft => PhysicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight => PhysicalKeyboardKey.arrowRight,
  _ => PhysicalKeyboardKey.select,
};
