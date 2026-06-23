//VND VENDORED — read-only mirror of neuram_v2_threshold @ 45ad1c0008af70ea8d901c93b7acf58a4979301f. Do not edit. The twin must not modify the engine.
//VND sha256(body, LF, excl //VND lines)=4b84ad13c61d222e4adba191877763ea9a2939249d04ee69b43ebbffc9f99897
import 'synapse.dart';

/// A minimal neuron: an identity plus the set of synapses leaving it.
///
/// The two threshold dynamics live on the [Synapse] (threshold ① is evaluated per
/// synapse on its own leaky-integrated input). The neuron is kept deliberately thin
/// so the model stays synapse-centric, matching the single goal of the project.
class Neuron {
  final int id;
  final List<Synapse> outgoing;

  Neuron(this.id, {List<Synapse>? outgoing})
    : outgoing = outgoing ?? <Synapse>[];

  Synapse connect(Synapse s) {
    outgoing.add(s);
    return s;
  }
}
