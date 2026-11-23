import 'dart:math' as math;

/// Unit quaternion mapping sensor/body coordinates into the reference frame.
/// Euler angles are readouts only; composition and animation stay in 3D.
class Orientation {
  const Orientation(this.w, this.x, this.y, this.z);
  static const identity = Orientation(1, 0, 0, 0);
  final double w, x, y, z;

  Orientation get normalized {
    final n = math.sqrt(w * w + x * x + y * y + z * z);
    return n < 1e-12 ? identity : Orientation(w / n, x / n, y / n, z / n);
  }

  Orientation get inverse => Orientation(w, -x, -y, -z);

  Orientation operator *(Orientation b) => Orientation(
    w * b.w - x * b.x - y * b.y - z * b.z,
    w * b.x + x * b.w + y * b.z - z * b.y,
    w * b.y - x * b.z + y * b.w + z * b.x,
    w * b.z + x * b.y - y * b.x + z * b.w,
  );

  /// ZYX convention, radians: Rz(yaw) * Ry(pitch) * Rx(roll).
  factory Orientation.euler(double roll, double pitch, double yaw) =>
      (Orientation.rotationVector([0, 0, yaw]) *
              Orientation.rotationVector([0, pitch, 0]) *
              Orientation.rotationVector([roll, 0, 0]))
          .normalized;

  /// Exponential map: vector direction is the axis, length is radians.
  factory Orientation.rotationVector(List<double> v) {
    final angle = math.sqrt(v.fold(0.0, (s, x) => s + x * x));
    if (angle < 1e-12) return identity;
    final s = math.sin(angle / 2) / angle;
    return Orientation(math.cos(angle / 2), v[0] * s, v[1] * s, v[2] * s);
  }

  /// Shortest rotation between unit vectors, including opposite directions.
  factory Orientation.between(List<double> from, List<double> to) {
    final dot = from[0] * to[0] + from[1] * to[1] + from[2] * to[2];
    if (dot < -1 + 1e-10) {
      final axis =
          from[0].abs() < from[2].abs()
              ? [0.0, -from[2], from[1]]
              : [-from[1], from[0], 0.0];
      return Orientation(0, axis[0], axis[1], axis[2]).normalized;
    }
    return Orientation(
      1 + dot,
      from[1] * to[2] - from[2] * to[1],
      from[2] * to[0] - from[0] * to[2],
      from[0] * to[1] - from[1] * to[0],
    ).normalized;
  }

  List<double> rotate(List<double> v) {
    final r = this * Orientation(0, v[0], v[1], v[2]) * inverse;
    return [r.x, r.y, r.z];
  }

  /// Shortest arc; q and -q describe exactly the same physical orientation.
  Orientation slerp(Orientation other, double t) {
    var dot = w * other.w + x * other.x + y * other.y + z * other.z;
    var b = other;
    if (dot < 0) {
      b = Orientation(-b.w, -b.x, -b.y, -b.z);
      dot = -dot;
    }
    double aWeight, bWeight;
    if (dot > 0.9995) {
      aWeight = 1 - t;
      bWeight = t;
    } else {
      final angle = math.acos(dot.clamp(-1.0, 1.0));
      aWeight = math.sin((1 - t) * angle) / math.sin(angle);
      bWeight = math.sin(t * angle) / math.sin(angle);
    }
    return Orientation(
      w * aWeight + b.w * bWeight,
      x * aWeight + b.x * bWeight,
      y * aWeight + b.y * bWeight,
      z * aWeight + b.z * bWeight,
    ).normalized;
  }

  double get _sinPitch => 2 * (w * y - z * x);
  bool get _atPole => _sinPitch.abs() >= 1 - 1e-12;

  // At pitch +/-90, roll and yaw are not separately defined. Choose roll=0
  // and the equivalent yaw from non-degenerate matrix elements. Never feed
  // these display values back into integration, recovery or interpolation.
  double get roll =>
      _atPole ? 0 : math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y));
  double get pitch =>
      _atPole
          ? _sinPitch.sign * math.pi / 2
          : math.asin(_sinPitch.clamp(-1.0, 1.0));
  double get yaw =>
      _atPole
          ? math.atan2(2 * (w * z - x * y), 1 - 2 * (x * x + z * z))
          : math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z));

  @override
  bool operator ==(Object other) =>
      other is Orientation &&
      w == other.w &&
      x == other.x &&
      y == other.y &&
      z == other.z;
  @override
  int get hashCode => Object.hash(w, x, y, z);
}
