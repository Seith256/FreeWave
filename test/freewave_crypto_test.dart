import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freewave/core/crypto_service.dart';
import 'package:freewave/core/identity_service.dart';

Future<FreeWaveIdentity> makeIdentity(String id) async {
  final x = await X25519().newKeyPair();
  final ed = await Ed25519().newKeyPair();
  final xPrivate = await x.extractPrivateKeyBytes();
  final xPublic = await x.extractPublicKey();
  final edPrivate = await ed.extractPrivateKeyBytes();
  final edPublic = await ed.extractPublicKey();
  return FreeWaveIdentity(
    nodeId: id,
    encryptionKeyPair: SimpleKeyPairData(
      xPrivate,
      publicKey: SimplePublicKey(xPublic.bytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    ),
    signingKeyPair: SimpleKeyPairData(
      edPrivate,
      publicKey: SimplePublicKey(edPublic.bytes, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    ),
  );
}

void main() {
  test('recipient decrypts an authenticated message', () async {
    final alice = await makeIdentity('alice-node');
    final bob = await makeIdentity('bob-node');
    final aliceCrypto = CryptoService(alice);
    final bobCrypto = CryptoService(bob);

    final envelope = await aliceCrypto.seal(
      recipientId: bob.nodeId,
      recipientEncryptionPublicKey: await bob.encryptionPublicKeyBase64,
      messageId: 'test-message-1',
      plaintext: 'Hello through the mesh',
      createdAt: 100,
      expiresAt: 100000,
      hopsLeft: 10,
    );

    final aliceContact = TrustedContact(
      nodeId: alice.nodeId,
      name: 'Alice',
      encryptionPublicKey: await alice.encryptionPublicKeyBase64,
      signingPublicKey: await alice.signingPublicKeyBase64,
    );

    final clear = await bobCrypto.open(
      envelope: envelope,
      sender: aliceContact,
    );
    expect(clear, 'Hello through the mesh');
  });

  test('tampering with ciphertext fails authentication', () async {
    final alice = await makeIdentity('alice-node');
    final bob = await makeIdentity('bob-node');
    final envelope = await CryptoService(alice).seal(
      recipientId: bob.nodeId,
      recipientEncryptionPublicKey: await bob.encryptionPublicKeyBase64,
      messageId: 'test-message-2',
      plaintext: 'Do not alter me',
      createdAt: 100,
      expiresAt: 100000,
      hopsLeft: 10,
    );
    final contact = TrustedContact(
      nodeId: alice.nodeId,
      name: 'Alice',
      encryptionPublicKey: await alice.encryptionPublicKeyBase64,
      signingPublicKey: await alice.signingPublicKeyBase64,
    );
    envelope['cipherText'] = base64Encode([1, 2, 3, 4]);
    await expectLater(
      CryptoService(bob).open(envelope: envelope, sender: contact),
      throwsA(anything),
    );
  });
}
