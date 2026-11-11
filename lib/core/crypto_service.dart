import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'identity_service.dart';

class TrustedContact {
  const TrustedContact({
    required this.nodeId,
    required this.name,
    required this.encryptionPublicKey,
    required this.signingPublicKey,
  });

  final String nodeId;
  final String name;
  final String encryptionPublicKey;
  final String signingPublicKey;

  Map<String, dynamic> toJson() => {
    'nodeId': nodeId,
    'name': name,
    'encryptionPublicKey': encryptionPublicKey,
    'signingPublicKey': signingPublicKey,
  };

  factory TrustedContact.fromJson(Map<String, dynamic> json) => TrustedContact(
    nodeId: json['nodeId'] as String,
    name: json['name'] as String,
    encryptionPublicKey: json['encryptionPublicKey'] as String,
    signingPublicKey: json['signingPublicKey'] as String,
  );
}

class CryptoService {
  CryptoService(this.identity);

  final FreeWaveIdentity identity;
  final X25519 _x25519 = X25519();
  final Ed25519 _ed25519 = Ed25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Cipher _cipher = Chacha20.poly1305Aead();

  Future<Map<String, dynamic>> seal({
    required String recipientId,
    required String recipientEncryptionPublicKey,
    required String messageId,
    required String plaintext,
    required int createdAt,
    required int expiresAt,
    required int hopsLeft,
  }) async {
    final recipientKey = SimplePublicKey(
      base64Decode(recipientEncryptionPublicKey),
      type: KeyPairType.x25519,
    );
    final ephemeralPair = await _x25519.newKeyPair();
    final ephemeralPublic = await ephemeralPair.extractPublicKey();
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralPair,
      remotePublicKey: recipientKey,
    );
    final nonce = await _cipher.newNonce();
    final secretKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: ephemeralPublic.bytes,
      info: utf8.encode('FreeWave message v1'),
    );

    final aad = utf8.encode('$messageId|${identity.nodeId}|$recipientId|$createdAt|$expiresAt');
    final box = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
      aad: aad,
    );

    final unsigned = <String, dynamic>{
      'version': 1,
      'type': 'message',
      'id': messageId,
      'from': identity.nodeId,
      'to': recipientId,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
      'hopsLeft': hopsLeft,
      'ephemeralPublicKey': base64Encode(ephemeralPublic.bytes),
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };

    final signedFields = Map<String, dynamic>.from(unsigned)
      ..remove('hopsLeft');
    final signature = await _ed25519.sign(
      _canonical(signedFields),
      keyPair: identity.signingKeyPair,
    );

    return {
      ...unsigned,
      'signature': base64Encode(signature.bytes),
    };
  }

  Future<String> open({
    required Map<String, dynamic> envelope,
    required TrustedContact sender,
  }) async {
    if (envelope['version'] != 1 || envelope['type'] != 'message') {
      throw const FormatException('Unsupported FreeWave packet');
    }
    if (envelope['from'] != sender.nodeId) {
      throw const FormatException('Sender identity does not match trusted contact');
    }

    final signedFields = Map<String, dynamic>.from(envelope)
      ..remove('signature')
      ..remove('hopsLeft');
    final signingKey = SimplePublicKey(
      base64Decode(sender.signingPublicKey),
      type: KeyPairType.ed25519,
    );
    final signature = Signature(
      base64Decode(envelope['signature'] as String),
      publicKey: signingKey,
    );
    final valid = await _ed25519.verify(
      _canonical(signedFields),
      signature: signature,
      publicKey: signingKey,
    );
    if (!valid) throw const FormatException('Invalid sender signature');

    final ephemeral = SimplePublicKey(
      base64Decode(envelope['ephemeralPublicKey'] as String),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: identity.encryptionKeyPair,
      remotePublicKey: ephemeral,
    );
    final secretKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: ephemeral.bytes,
      info: utf8.encode('FreeWave message v1'),
    );

    final messageId = envelope['id'] as String;
    final from = envelope['from'] as String;
    final to = envelope['to'] as String;
    final createdAt = envelope['createdAt'] as int;
    final expiresAt = envelope['expiresAt'] as int;
    final aad = utf8.encode('$messageId|$from|$to|$createdAt|$expiresAt');
    final box = SecretBox(
      base64Decode(envelope['cipherText'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    );
    final clear = await _cipher.decrypt(box, secretKey: secretKey, aad: aad);
    return utf8.decode(clear);
  }

  Uint8List _canonical(Map<String, dynamic> value) {
    final keys = value.keys.toList()..sort();
    final ordered = <String, dynamic>{for (final key in keys) key: value[key]};
    return Uint8List.fromList(utf8.encode(jsonEncode(ordered)));
  }
}
