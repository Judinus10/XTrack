import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xtrack/core/vault.dart';
void main(){
  test('backup decrypts with its passphrase and rejects tampering',()async{
    const pass='a long test passphrase';
    final bytes=await Vault.seal(pass,{'amount':1299});
    expect(await Vault.unseal(pass,bytes),{'amount':1299});
    await expectLater(Vault.unseal('incorrect passphrase',bytes),throwsA(anything));
    final changed=Uint8List.fromList(bytes);changed[changed.length-1]^=1;
    await expectLater(Vault.unseal(pass,changed),throwsA(anything));
  });
}
