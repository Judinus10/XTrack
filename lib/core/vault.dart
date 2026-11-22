import 'dart:convert';
import 'dart:math';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class Vault {
  static const storage = FlutterSecureStorage();
  static const device = MethodChannel('xtrack/device');
  static List<int> random(int n) { final rng = Random.secure(); return List.generate(n, (_) => rng.nextInt(256)); }
  static Future<SecretKey> derive(String value, List<int> salt) async {
    final bytes=await Isolate.run(() async {
      final algorithm=Pbkdf2(macAlgorithm:Hmac.sha256(),iterations:210000,bits:256);
      final key=await algorithm.deriveKey(secretKey:SecretKey(utf8.encode(value)),nonce:salt);
      return key.extractBytes();
    });
    return SecretKey(bytes);
  }
  static Future<void> setPin(String pin) async {
    final salt = random(16);
    final hash = await (await derive(pin,salt)).extractBytes();
    await storage.write(key:'pin', value:jsonEncode([base64Encode(salt),base64Encode(hash)]));
    await storage.delete(key:'attempts');
  }
  static Future<bool> check(String pin) async {
    final raw = await storage.read(key:'pin');
    if (raw == null) return false;
    final tries = jsonDecode(await storage.read(key:'attempts') ?? '[0,0]');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < tries[1]) throw StateError('Too many attempts. Try again in ${((tries[1]-now)/1000).ceil()} seconds.');
    final stored = jsonDecode(raw);
    final actual = await (await derive(pin,base64Decode(stored[0]))).extractBytes();
    final expected = base64Decode(stored[1]);
    var diff = 0;
    for (var i=0;i<actual.length;i++) { diff |= actual[i] ^ expected[i]; }
    if (diff == 0) { await storage.delete(key:'attempts'); return true; }
    final count = (tries[0] as int)+1;
    final delay = count < 5 ? 0 : min(900, 30 * (1 << min(5,count-5)));
    await storage.write(key:'attempts',value:jsonEncode([count,now+delay*1000]));
    return false;
  }
  static Future<bool> biometric() => LocalAuthentication().authenticate(
    localizedReason:'Unlock XTrack',options:const AuthenticationOptions(biometricOnly:true,stickyAuth:true));
  static Future<Uint8List> seal(String pass, Object data) async {
    final salt = random(16);
    final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode(data)),secretKey:await derive(pass,salt));
    return Uint8List.fromList([...ascii.encode('XTB1'),...salt,...box.concatenation()]);
  }
  static Future<dynamic> unseal(String pass, Uint8List bytes) async {
    if(bytes.length<48 || ascii.decode(bytes.take(4).toList(),allowInvalid:true)!='XTB1') {
      throw const FormatException('Invalid XTrack backup');
    }
    final box=SecretBox.fromConcatenation(bytes.sublist(20),nonceLength:12,macLength:16);
    try {
      final clear=await AesGcm.with256bits().decrypt(box,secretKey:await derive(pass,bytes.sublist(4,20)));
      return jsonDecode(utf8.decode(clear));
    } on SecretBoxAuthenticationError {
      throw const FormatException('Incorrect passphrase or damaged backup.');
    }
  }
}
