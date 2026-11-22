import 'dart:collection' show IterableExtensions;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'metrics.dart';
import 'vault.dart';

class Alarms {
  final plugin=FlutterLocalNotificationsPlugin();
  Future<void> init() async {
    zones.initializeTimeZones();
    await plugin.initialize(const InitializationSettings(android:AndroidInitializationSettings('ic_reminder')));
  }
  Future<bool> permission() async =>
    await plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? false;
  Future<void> sync(Map<String,List<RowData>> data, bool enabled) async {
    await plugin.cancelAll();
    if(!enabled) return;
    final android=plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if(await android?.areNotificationsEnabled()==false){
      throw StateError('Notifications are blocked in Android settings.');
    }
    final zone=tz.getLocation(await Vault.device.invokeMethod<String>('zone') ?? 'UTC');
    final now=tz.TZDateTime.now(zone);
    const details=NotificationDetails(android:AndroidNotificationDetails('xtrack_reminders','Tracker reminders',importance:Importance.high,priority:Priority.high));
    for(final r in data['reminders']!) {
      final habit=r['habit']!=null;
      final owner=data[habit?'habits':'tasks']!.where((v)=>v['id']==(r['habit']??r['task'])).firstOrNull;
      if(owner==null || owner['archived']==1 || owner['completed']!=null) continue;
      final minute=r['minute'] as int;
      for(var offset=0;offset<(habit?8:1);offset++) {
        final d=habit?DateTime(now.year,now.month,now.day+offset):DateTime.parse(owner['day']);
        final at=tz.TZDateTime(zone,d.year,d.month,d.day,minute~/60,minute%60);
        if(!at.isAfter(now) || (habit && (!scheduled(owner,d) || (offset==7 && minute>now.hour*60+now.minute)))) continue;
        await plugin.zonedSchedule((r['id'] as int)*8+(habit?d.weekday:0),'XTrack reminder',
          habit?'Time for a scheduled habit.':'You have a scheduled task.',at,details,
          androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents:habit?DateTimeComponents.dayOfWeekAndTime:null);
      }
    }
  }
}
