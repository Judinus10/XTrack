// Run on a disposable Android emulator. This suite resets XTrack's test data.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xtrack/core/metrics.dart';
import 'package:xtrack/core/store.dart';
import 'package:xtrack/core/vault.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('encrypted Android store survives restart and cancels edited alarms', (tester) async {
    await tester.runAsync(() async {
      final s=Store();
      await s.init();
      await s.reset();
      expect(await s.db.rawQuery('PRAGMA cipher_version'),isNotEmpty);
      await s.save('accounts',{'name':'Savings','type':'Savings account','opening':100000,'icon':'Bank','color':'Green'});
      final a=s.rows('accounts').first, b=s.rows('accounts').last;
      await s.save('transactions',{'kind':'Transfer','account':a['id'],'destination':b['id'],'amount':12501,'day':today});
      expect(s.balance(b),112501);
      await s.save('habits',{'name':'Study','start':today,'days':127,'icon':'Book','color':'Blue'});
      final h=s.rows('habits').single;
      await s.log(h['id'],today);
      expect(s.rows('habit_logs').length,1);
      await s.log(h['id'],today);
      expect(s.rows('habit_logs'),isEmpty);
      await s.save('tasks',{'name':'Review','category':'Learning','priority':'Medium','day':dayKey(shift(DateTime.now(),1))},minute:540);
      final task=s.rows('tasks').single;
      await s.setting('notifications','1');
      expect(s.reminderError,isNull,reason:'Grant notification permission to the test installation.');
      expect(await s.alarms.plugin.pendingNotificationRequests(),hasLength(1));
      await s.change('tasks',task['id'],{'completed':today});
      expect(await s.alarms.plugin.pendingNotificationRequests(),isEmpty);
      await s.save('goals',{'name':'Read','category':'Learning','unit':'books','current':200,'target':1000,'day':today,'icon':'Book','color':'Blue'});
      await s.setting('theme','dark');
      await Vault.setPin('345678');
      for(var i=0;i<5;i++){expect(await Vault.check('000000'),isFalse);}
      await expectLater(Vault.check('345678'),throwsStateError);
      await Vault.storage.delete(key:'attempts');
      expect(await Vault.check('345678'),isTrue);
      await s.db.close();
      final reopened=Store();
      await reopened.init();
      expect(reopened.hasPin,isTrue);
      expect(reopened.pref('theme','system'),'dark');
      expect(reopened.balance(reopened.rows('accounts').last),112501);
      expect(reopened.rows('goals').single['current'],200);
      expect(reopened.rows('tasks').single['completed'],today);
      await Vault.storage.delete(key:'pin');
      await reopened.reset();
      await reopened.db.close();
    });
  });
}
