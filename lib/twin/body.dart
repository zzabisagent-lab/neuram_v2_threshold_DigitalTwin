import '../engine/sim.dart';
import '../engine/synapse.dart';
import 'twin_params.dart';

/// The body translates between the world and the engine, using only the engine's
/// public API (`Stimulator`).
///
/// - **Sensory encoding:** sensor intensity I -> input pulse x = sensorGain·I.
///   Brighter light => larger x => threshold ① (firing) decides whether the
///   signal passes at all.
/// - **Motor decoding:** a wheel speed is the sum of `propagate` over the synapses
///   feeding that motor. `propagate` is > 0 only when the synapse fired, is active,
///   and its effective strength clears thetaPrune — so weak or non-firing paths are
///   silently gated out. This is threshold ②'s propagation gate made into motion.
class Body {
  final Stimulator sim;
  final TwinParams tp;

  Body(this.sim, this.tp);

  double encode(double intensity) => tp.sensorGain * intensity;

  /// Deliver a sensory pulse (threshold ①). Returns whether it fired.
  bool senseInto(Synapse s, double t, double intensity) =>
      sim.pulse(s, t, encode(intensity));

  /// Wheel speed = summed gated propagation of the synapses feeding the motor.
  double motor(List<Synapse> incoming, double t) =>
      incoming.fold(0.0, (acc, s) => acc + sim.propagate(s, t));
}
