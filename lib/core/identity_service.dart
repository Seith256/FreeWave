import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class FreeWaveIdentity {
  const FreeWaveIdentity({
    required this.nodeId,
    required this.encryptionKeyPair,
    required this.signingKeyPair,
  });

  final String nodeId;
  final SimpleKeyPairData encryptionKeyPair;
  final SimpleKeyPairData signingKeyPair;

  Future<String> get encryptionPublicKeyBase64 async =>
      base64Encode(await encryptionKeyPair.extractPublicKey().then((k) => k.bytes));

  Future<String> get signingPublicKeyBase64 async =>
      base64Encode(await signingKeyPair.extractPublicKey().then((k) => k.bytes));
}

class IdentityService {
  IdentityService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _nodeIdKey = 'freewave.node_id';
  static const _xPrivateKey = 'freewave.x25519.private';
  static const _xPublicKey = 'freewave.x25519.public';
  static const _edPrivateKey = 'freewave.ed25519.private';
  static const _edPublicKey = 'freewave.ed25519.public';

  final X25519 _x25519 = X25519();
  final Ed25519 _ed25519 = Ed25519();

  Future<FreeWaveIdentity> loadOrCreate() async {
    final nodeId = await _storage.read(key: _nodeIdKey) ?? const Uuid().v4();
    await _storage.write(key: _nodeIdKey, value: nodeId);

    final xPair = await _loadOrCreatePair(
      privateKey: _xPrivateKey,
      publicKey: _xPublicKey,
      algorithm: _x25519,
      type: KeyPairType.x25519,
    );
    final edPair = await _loadOrCreatePair(
      privateKey: _edPrivateKey,
      publicKey: _edPublicKey,
      algorithm: _ed25519,
      type: KeyPairType.ed25519,
    );

    return FreeWaveIdentity(
      nodeId: nodeId,
      encryptionKeyPair: xPair,
      signingKeyPair: edPair,
    );
  }

  Future<SimpleKeyPairData> _loadOrCreatePair({
    required String privateKey,
    required String publicKey,
    required dynamic algorithm,
    required KeyPairType type,
  }) async {
    final privateText = await _storage.read(key: privateKey);
    final publicText = await _storage.read(key: publicKey);
    if (privateText != null && publicText != null) {
      return SimpleKeyPairData(
        base64Decode(privateText),
        publicKey: SimplePublicKey(base64Decode(publicText), type: type),
        type: type,
      );
    }

    final generated = await algorithm.newKeyPair();
    final privateBytes = await generated.extractPrivateKeyBytes();
    final publicBytes = (await generated.extractPublicKey()).bytes;
    await _storage.write(key: privateKey, value: base64Encode(privateBytes));
    await _storage.write(key: publicKey, value: base64Encode(publicBytes));
    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicBytes, type: type),
      type: type,
    );
  }
}
