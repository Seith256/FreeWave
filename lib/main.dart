import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'core/crypto_service.dart';
import 'core/identity_service.dart';
import 'core/mesh_service.dart';
import 'data/local_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FreeWaveApp());
}

class FreeWaveApp extends StatelessWidget {
  const FreeWaveApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FreeWave',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00BFA5),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF071411),
    ),
    home: const FreeWaveHome(),
  );
}

class FreeWaveHome extends StatefulWidget {
  const FreeWaveHome({super.key});

  @override
  State<FreeWaveHome> createState() => _FreeWaveHomeState();
}

class _FreeWaveHomeState extends State<FreeWaveHome> {
  final _store = LocalStore();
  final _messageController = TextEditingController();
  final _recipientController = TextEditingController();
  final _recipientKeyController = TextEditingController();
  final _nameController = TextEditingController();
  final _events = <String>[];
  final _contacts = <TrustedContact>[];
  final _queue = <Map<String, dynamic>>[];
  final _decryptedMessages = <String>[];
  final _seenIds = <String>{};

  FreeWaveIdentity? _identity;
  CryptoService? _crypto;
  MeshService? _mesh;
  List<String> _peers = [];
  bool _loading = true;
  bool _meshRunning = false;
  String _status = 'Preparing secure identity';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final identity = await IdentityService().loadOrCreate();
      final contacts = await _store.loadContacts();
      final queue = await _store.loadQueue();
      final savedSeenIds = await _store.loadSeenIds();
      final displayName = await _store.loadDisplayName();
      _nameController.text = displayName;
      _identity = identity;
      _crypto = CryptoService(identity);
      _contacts.addAll(contacts);
      _queue.addAll(queue);
      _seenIds.addAll(savedSeenIds);
      for (final envelope in queue) {
        _seenIds.add(envelope['id'] as String);
      }
      if (mounted) setState(() {
        _loading = false;
        _status = 'Ready · offline';
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _status = 'Secure identity error: $e';
      });
    }
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _events.insert(0, '${DateTime.now().toLocal().toString().substring(11, 19)}  $message');
      if (_events.length > 50) _events.removeLast();
    });
  }

  Future<void> _startMesh() async {
    if (_identity == null || _meshRunning) return;
    final mesh = MeshService(
      nodeId: _identity!.nodeId,
      displayName: _nameController.text.trim().isEmpty ? 'FreeWave user' : _nameController.text.trim(),
      onPacket: _handlePacket,
      onPeersChanged: (peers) {
        if (mounted) setState(() => _peers = peers);
      },
      onLog: _log,
      confirmIncomingConnection: _confirmIncomingConnection,
    );
    try {
      await mesh.start();
      _mesh = mesh;
      if (mounted) setState(() {
        _meshRunning = true;
        _status = 'Mesh active · ${_peers.length} nearby';
      });
      await _flushQueue();
    } catch (e) {
      _log('Could not start nearby transport: $e');
      await mesh.stop();
    }
  }

  Future<void> _stopMesh() async {
    await _mesh?.stop();
    _mesh = null;
    if (mounted) setState(() {
      _meshRunning = false;
      _status = 'Ready · offline';
    });
  }


  Future<bool> _confirmIncomingConnection(
    String peerId,
    String displayName,
    String pin,
  ) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Verify nearby connection'),
            content: Text(
              'Device: $displayName\nNode: $peerId\n\n'
              'Compare this PIN with the other device:\n\n$pin\n\n'
              'Accept only if both screens show the same PIN.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('PIN matches — accept'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _addContact() async {
    final id = _recipientController.text.trim();
    final enc = _recipientKeyController.text.trim();
    if (id.isEmpty || enc.isEmpty) {
      _log('Enter a contact node ID and their X25519 public key');
      return;
    }
    final signing = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Verify contact identity'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Paste the contact Ed25519 signing public key. Compare both key fingerprints through a trusted channel before saving.'),
            const SizedBox(height: 10),
            TextField(controller: controller, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Signing public key (Base64)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save contact')),
          ],
        );
      },
    );
    if (signing == null || signing.isEmpty) return;
    try {
      base64Decode(enc);
      base64Decode(signing);
      _contacts.removeWhere((c) => c.nodeId == id);
      _contacts.add(TrustedContact(
        nodeId: id,
        name: id.substring(0, id.length < 8 ? id.length : 8),
        encryptionPublicKey: enc,
        signingPublicKey: signing,
      ));
      await _store.saveContacts(_contacts);
      _log('Contact saved. Confirm both fingerprints out-of-band before trusting.');
      if (mounted) setState(() {});
    } catch (_) {
      _log('Invalid Base64 public key');
    }
  }

  TrustedContact? _findContact(String nodeId) {
    for (final contact in _contacts) {
      if (contact.nodeId == nodeId) return contact;
    }
    return null;
  }

  Future<void> _sendMessage() async {
    final identity = _identity;
    final crypto = _crypto;
    final body = _messageController.text.trim();
    final recipientId = _recipientController.text.trim();
    final recipient = _findContact(recipientId);
    if (identity == null || crypto == null || body.isEmpty) return;
    if (recipient == null) {
      _log('Add and verify the recipient as a trusted contact first');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final envelope = await crypto.seal(
      recipientId: recipient.nodeId,
      recipientEncryptionPublicKey: recipient.encryptionPublicKey,
      messageId: const Uuid().v4(),
      plaintext: body,
      createdAt: now,
      expiresAt: now + const Duration(days: 7).inMilliseconds,
      hopsLeft: 24,
    );
    _queue.add(envelope);
    _seenIds.add(envelope['id'] as String);
    await _store.saveSeenIds(_seenIds);
    await _pruneQueue();
    await _store.saveQueue(_queue);
    _messageController.clear();
    if (mounted) setState(() {});
    await _sendEnvelope(envelope);
  }

  Future<void> _sendEnvelope(Map<String, dynamic> envelope) async {
    if (!_meshRunning || _mesh == null) {
      _log('Encrypted message saved. It will be relayed when the mesh is active.');
      return;
    }
    try {
      await _mesh!.send(envelope);
      _log('Encrypted packet broadcast to connected neighbours');
    } catch (e) {
      _log('Packet retained for retry: $e');
    }
  }

  Future<void> _handlePacket(Map<String, dynamic> packet) async {
    final identity = _identity;
    final crypto = _crypto;
    if (identity == null || crypto == null || packet['type'] != 'message') return;
    final id = packet['id'] as String?;
    if (id == null || _seenIds.contains(id)) return;
    _seenIds.add(id);
    await _store.saveSeenIds(_seenIds);

    final expiresAt = packet['expiresAt'] as int? ?? 0;
    final hopsLeft = packet['hopsLeft'] as int? ?? 0;
    if (expiresAt < DateTime.now().millisecondsSinceEpoch || hopsLeft <= 0) {
      _log('Expired packet discarded');
      return;
    }

    if (packet['to'] == identity.nodeId) {
      final senderId = packet['from'] as String;
      final sender = _findContact(senderId);
      if (sender == null) {
        _log('Encrypted message from unverified identity $senderId. Add and verify their contact key to read it.');
        _queue.add(packet);
        await _pruneQueue();
        await _store.saveQueue(_queue);
        return;
      }
      try {
        final text = await crypto.open(envelope: packet, sender: sender);
        _decryptedMessages.add('From ${sender.name}: $text');
        _log('Verified encrypted message received');
      } catch (e) {
        _log('Message authentication/decryption failed: $e');
      }
      if (mounted) setState(() {});
      return;
    }

    final forwarded = Map<String, dynamic>.from(packet)
      ..['hopsLeft'] = hopsLeft - 1;
    _queue.add(forwarded);
    await _pruneQueue();
    await _store.saveQueue(_queue);
    _log('Stored encrypted relay packet · ${hopsLeft - 1} hops remain');
    await _sendEnvelope(forwarded);
  }


  Future<void> _pruneQueue() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _queue.removeWhere((packet) =>
        (packet['expiresAt'] as int? ?? 0) <= now);
    if (_queue.length > 500) {
      _queue.removeRange(0, _queue.length - 500);
    }
  }

  Future<void> _flushQueue() async {
    await _pruneQueue();
    await _store.saveQueue(_queue);
    for (final packet in List<Map<String, dynamic>>.from(_queue)) {
      final expiresAt = packet['expiresAt'] as int? ?? 0;
      if (expiresAt > DateTime.now().millisecondsSinceEpoch) {
        await _sendEnvelope(packet);
      }
    }
  }

  Future<void> _copyIdentity() async {
    final identity = _identity;
    if (identity == null) return;
    final profile = {
      'nodeId': identity.nodeId,
      'encryptionPublicKey': await identity.encryptionPublicKeyBase64,
      'signingPublicKey': await identity.signingPublicKeyBase64,
    };
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(profile)));
    _log('Public identity copied. Share it privately and verify its fingerprint in person or through another trusted channel.');
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    await _store.saveDisplayName(name);
    _log('Name saved. Restart the mesh to advertise the updated name.');
  }

  @override
  void dispose() {
    _messageController.dispose();
    _recipientController.dispose();
    _recipientKeyController.dispose();
    _nameController.dispose();
    final mesh = _mesh;
    if (mesh != null) {
      unawaited(mesh.stop());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final identity = _identity;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.waves_rounded, color: Color(0xFF00BFA5)),
          SizedBox(width: 8),
          Text('FreeWave', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(onPressed: _copyIdentity, icon: const Icon(Icons.share_outlined), tooltip: 'Share public identity'),
          IconButton(onPressed: _meshRunning ? _stopMesh : _startMesh, icon: Icon(_meshRunning ? Icons.stop_circle : Icons.radar)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF10251F),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(_meshRunning ? Icons.wifi_tethering : Icons.shield_outlined, color: const Color(0xFF00BFA5)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_status, style: Theme.of(context).textTheme.titleMedium)),
                  Text('${_peers.length} peers'),
                ]),
                const SizedBox(height: 8),
                Text('Node ID: ${identity?.nodeId ?? "Unavailable"}', style: Theme.of(context).textTheme.bodySmall),
                Text('Relay: automatic · Message lifetime: 7 days · Max hops: 24', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _meshRunning ? _stopMesh : _startMesh,
                  icon: Icon(_meshRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(_meshRunning ? 'Stop mesh' : 'Start FreeWave mesh'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Text('Your identity', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder())),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _saveName, child: const Text('Save name'))),
          OutlinedButton.icon(onPressed: _copyIdentity, icon: const Icon(Icons.copy), label: const Text('Copy public identity')),
          const Divider(height: 30),
          Text('Trusted contacts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          TextField(controller: _recipientController, decoration: const InputDecoration(labelText: 'Contact node ID', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: _recipientKeyController, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Contact X25519 encryption key (Base64)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _addContact, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add / verify contact')),
          ..._contacts.map((c) => ListTile(
            dense: true,
            leading: const Icon(Icons.verified_user_outlined, color: Color(0xFF00BFA5)),
            title: Text(c.name),
            subtitle: Text(c.nodeId),
          )),
          const Divider(height: 30),
          Text('Compose encrypted message', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(controller: _messageController, minLines: 2, maxLines: 4, decoration: const InputDecoration(hintText: 'Write a private message…', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _sendMessage, icon: const Icon(Icons.lock), label: const Text('Encrypt, save and send')),
          const SizedBox(height: 20),
          Text('Messages received', style: Theme.of(context).textTheme.titleLarge),
          if (_decryptedMessages.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('No verified messages received yet.'))
          else
            ..._decryptedMessages.reversed.map((m) => Card(child: ListTile(leading: const Icon(Icons.lock_open), title: Text(m)))),
          const SizedBox(height: 18),
          Text('Relay queue (${_queue.length})', style: Theme.of(context).textTheme.titleLarge),
          const Text('The queue contains encrypted packets. A relay device cannot decrypt them.', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 14),
          Text('Nearby devices', style: Theme.of(context).textTheme.titleLarge),
          if (_peers.isEmpty) const Text('No nearby peers discovered yet.')
          else ..._peers.map((p) => ListTile(leading: const Icon(Icons.devices), title: Text(p))),
          OutlinedButton.icon(
            onPressed: _meshRunning ? () async {
              try { await _mesh!.connectToFirstDiscovered(); }
              catch (e) { _log('Connection attempt failed: $e'); }
            } : null,
            icon: const Icon(Icons.link),
            label: const Text('Connect to first discovered peer'),
          ),
          const Divider(height: 30),
          Text('Activity', style: Theme.of(context).textTheme.titleLarge),
          ..._events.take(18).map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(e, style: Theme.of(context).textTheme.bodySmall),
          )),
          const SizedBox(height: 20),
          const Text(
            'Security status: message contents are encrypted to a recipient public key and signed by the sender. Contacts must be verified by comparing key fingerprints through a trusted separate channel. Keep FreeWave open during initial testing. Background relaying and platform-specific radio behaviour are not guaranteed.',
            style: TextStyle(color: Colors.orangeAccent),
          ),
        ],
      ),
    );
  }
}
