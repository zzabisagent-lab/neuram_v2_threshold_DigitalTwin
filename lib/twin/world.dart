import 'dart:math' as math;

import 'twin_params.dart';

/// Left/right light intensities seen by the two sensors, each in [0, imax].
class Sensors {
  final double left;
  final double right;
  const Sensors(this.left, this.right);
}

/// A self-contained 2D world: a differential-drive agent and a (toggleable) point
/// light on an infinite plane. The world knows nothing about the engine.
class World {
  final TwinParams tp;

  double x;
  double y;
  double heading; // radians

  double lightX;
  double lightY;
  bool lightOn;

  World(
    this.tp, {
    this.x = 0.0,
    this.y = 0.0,
    this.heading = 0.0,
    this.lightX = 0.0,
    this.lightY = 0.0,
    this.lightOn = true,
  });

  void setPose(double nx, double ny, double nheading) {
    x = nx;
    y = ny;
    heading = nheading;
  }

  void setLight(double lx, double ly, {bool on = true}) {
    lightX = lx;
    lightY = ly;
    lightOn = on;
  }

  double get distance {
    final dx = lightX - x;
    final dy = lightY - y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Left/right sensor intensities. Each sensor faces heading ± sensorAngle; its
  /// reading is the distance-attenuated intensity projected onto its facing
  /// (max(0, cos(bearing))). The left/right asymmetry is the steering signal.
  Sensors sense() {
    if (!lightOn) return const Sensors(0.0, 0.0);
    final dx = lightX - x;
    final dy = lightY - y;
    final d = math.sqrt(dx * dx + dy * dy);
    final base = tp.imax / (1.0 + tp.falloff * d * d);
    final angToLight = math.atan2(dy, dx);

    double comp(double sensorDir) {
      final bearing = _norm(angToLight - sensorDir);
      final c = math.cos(bearing);
      return c > 0 ? base * c : 0.0;
    }

    return Sensors(
      comp(heading + tp.sensorAngle),
      comp(heading - tp.sensorAngle),
    );
  }

  /// Differential drive: heading turns by (vR - vL)·turnGain; the body advances by
  /// the mean wheel speed ·moveGain along the new heading. Infinite plane.
  void step(double vL, double vR) {
    heading += (vR - vL) * tp.turnGain;
    final fwd = (vL + vR) / 2.0 * tp.moveGain;
    x += fwd * math.cos(heading);
    y += fwd * math.sin(heading);
  }
}

double _norm(double a) {
  var v = a;
  while (v > math.pi) {
    v -= 2 * math.pi;
  }
  while (v < -math.pi) {
    v += 2 * math.pi;
  }
  return v;
}
