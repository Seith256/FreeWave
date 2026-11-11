import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby/nearby.dart';

class MeshService {
  MeshService({
    required this.nodeId,
    required this.displayName,
    required this.onPacket,
    required this.onPeersChanged,
    required this.onLog,
    required this.confirmIncomingConnection,
  });

  final String nodeId;
  final String displayName;
  final Future<void> Function(Map<String, dynamic>) onPacket;
  final void Function(List<String>) onPeersChanged;
  final void Function(String) onLog;
  final Future<bool> Function(String peerId, String displayName, String pin)
      confirmIncomingConnection;

  static const serviceId = 'freewave';
  late final NearbyService _nearby = NearbyService(
    localDisplayName: displayName,
    localPeerId: nodeId,
  );

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _running = false;
  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _subscriptions.add(_nearby.discoveredPeersStream.listen((peers) {
      onPeersChanged(peers.map((p) => '${p.displayName} · ${p.id}').toList());
    }));
    _subscriptions.add(_nearby.connectionRequestsStream.listen((request) async {
      final peerId = request.peer.id as String;
      final peerName = request.peer.displayName as String;
      final pin = request.authenticationPin as String;
      final approved = await confirmIncomingConnection(peerId, peerName, pin);
      try {
        if (approved) {
          await _nearby.acceptConnection(peerId);
          onLog('Accepted verified session with $peerName');
        } else {
          await _nearby.rejectConnection(peerId);
          onLog('Rejected connection from $peerName');
        }
      } catch (e) {
        onLog('Could not complete peer decision: $e');
      }
    }));
    _subscriptions.add(_nearby.payloadReceivedStream.listen((payload) async {
      if (payload.type != PayloadType.bytes || payload.bytes == null) return;
      try {
        final decoded = jsonDecode(utf8.decode(payload.bytes!));
        if (decoded is Map<String, dynamic>) await onPacket(decoded);
      } catch (e) {
        onLog('Ignored malformed packet: $e');
      }
    }));

    await _nearby.startAdvertising(
      options: AdvertisingOptions(
        serviceId: serviceId,
        strategy: DiscoveryStrategy.hybrid,
        securityMode: SecurityMode.pinVerification,
      ),
    );
    await _nearby.startDiscovery(
      options: const DiscoveryOptions(
        serviceId: serviceId,
        strategy: DiscoveryStrategy.hybrid,
      ),
    );
    _running = true;
    onLog('Advertising and discovery started');
  }

  Future<void> connectToFirstDiscovered() async {
    final peers = await _nearby.discoveredPeersStream
        .firstWhere((peers) => peers.isNotEmpty)
        .timeout(const Duration(seconds: 20));
    final peer = peers.first;
    await _nearby.requestConnection(peer);
    onLog('Connection requested to ${peer.displayName}. Compare the PIN before accepting.');
  }

  Future<void> send(Map<String, dynamic> envelope) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    await _nearby.sendBytesToAll(bytes);
  }

  Future<void> stop() async {
    if (!_running) return;
    await _nearby.stopDiscovery();
    await _nearby.stopAdvertising();
    await _nearby.disconnectAll();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _nearby.dispose();
    _running = false;
    onPeersChanged([]);
    onLog('Mesh stopped');
  }
}
