import 'dart:collection' show IterableExtensions;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as zones;
import 'package:timezone/timezone.dart' as tz;
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'store.dart';
import 'metrics.dart';
import 'vault.dart';

@pragma('vm:entry-point')
Future<void> snoozeAction(NotificationResponse response) async {
  if(!['later5','later10','later15','later30','later60','complete'].contains(response.actionId)||response.payload==null)return;
  WidgetsFlutterBinding.ensureInitialized();
  final p=jsonDecode(response.payload!);
  final store=Store();
  await store.init();
  if(response.actionId=='complete'){
    if(p[3]=='tasks')await store.change('tasks',p[4],{'completed':today});
    if(p[3]=='habits' && !store.rows('habit_logs').any((r)=>r['habit']==p[4]&&r['day']==today))await store.log(p[4],today);
    return;
  }
  final fire=DateTime.now().add(Duration(minutes:int.parse(response.actionId!.substring(5))));
  await store.write((t)async{
    await t.rawInsert('INSERT OR REPLACE INTO snoozes(id,fire,title,body,owner,ownerId) VALUES(?,?,?,?,?,?)',[p[0],fire.millisecondsSinceEpoch,p[1],p[2],p[3],p[4]]);
  },reschedule:true);
}
class Alarms {
  final plugin=FlutterLocalNotificationsPlugin();
  Future<void> init() async {
    zones.initializeTimeZones();
    await plugin.initialize(const InitializationSettings(android:AndroidInitializationSettings('ic_reminder')),onDidReceiveBackgroundNotificationResponse:snoozeAction,onDidReceiveNotificationResponse:snoozeAction);
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
    String? zoneName;
    try{zoneName=await Vault.device.invokeMethod<String>('zone');}catch(_){zoneName=await Vault.storage.read(key:'zone');}
    if(zoneName!=null)await Vault.storage.write(key:'zone',value:zoneName);
    final zone=tz.getLocation(zoneName??'UTC');
    final now=tz.TZDateTime.now(zone);
    const details=NotificationDetails(android:AndroidNotificationDetails('xtrack_reminders','Tracker reminders',importance:Importance.high,priority:Priority.high));
    final snooze=data['settings']!.where((r)=>r['key']=='snooze').firstOrNull?['value']??'10';
    final actionable=NotificationDetails(android:AndroidNotificationDetails('xtrack_actions','Actionable reminders',importance:Importance.high,priority:Priority.high,actions:[AndroidNotificationAction('later$snooze','Snooze $snooze min')]));
    for(final r in data['snoozes']!){
      final at=tz.TZDateTime.fromMillisecondsSinceEpoch(zone,r['fire']);
      if(!at.isAfter(now))continue;
      final owner=data[r['owner']]?.where((v)=>v['id']==r['ownerId']).firstOrNull;
      if(owner==null||owner['archived']==1||owner['completed']!=null)continue;
      await plugin.zonedSchedule(1100000000+(r['id'] as int),r['title'],r['body'],at,actionable,androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,payload:jsonEncode([r['id'],r['title'],r['body'],r['owner'],r['ownerId']]));
    }
    Future<void> once(int id,String title,String body,String day,int minute,{int? custom})async{
      final d=DateTime.parse(day);
      final at=tz.TZDateTime(zone,d.year,d.month,d.day,minute~/60,minute%60);
      if(at.isAfter(now))await plugin.zonedSchedule(id,title,body,at,custom==null?details:actionable,payload:custom==null?null:jsonEncode([id,title,body,'custom_reminders',custom]),androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle);
    }
    for(final a in data['accounts']!){
      if(a['type']=='Fixed deposit' && a['archived']==0 && a['maturity']!=null)await once(500000000+a['id'] as int,'Fixed deposit matures today','Open Finance to review the deposit.',a['maturity'],a['maturityMinute']);
    }
    for(final r in data['custom_reminders']!){
      var d=DateTime.parse(r['day']);final gap=r['intervalDays'] as int;
      for(var i=0;i<(gap==0?1:32);){
        final minute=r['minute'] as int;
        final at=tz.TZDateTime(zone,d.year,d.month,d.day,minute~/60,minute%60);
        if(at.isAfter(now) && (r['days']==0 || ((r['days'] as int)&(1<<(d.weekday-1)))!=0)){await once(700000000+(r['id'] as int)*32+i,r['name'],'Personal reminder',dayKey(d),minute,custom:r['id']);i++;}
        if(gap==0)break;
        d=shift(d,gap);
      }
    }
    for(final r in data['reminders']!) {
      final habit=r['habit']!=null;
      final owner=data[habit?'habits':'tasks']!.where((v)=>v['id']==(r['habit']??r['task'])).firstOrNull;
      if(owner==null || owner['archived']==1 || owner['completed']!=null) continue;
      final minute=r['minute'] as int;
      for(var offset=0;offset<(habit?8:1);offset++) {
        final d=habit?DateTime(now.year,now.month,now.day+offset):DateTime.parse(owner['day']);
        final at=tz.TZDateTime(zone,d.year,d.month,d.day,minute~/60,minute%60);
        if(!at.isAfter(now) || (habit && (!scheduled(owner,d) || (offset==7 && minute>now.hour*60+now.minute)))) continue;
        await plugin.zonedSchedule((r['id'] as int)*8+(habit?d.weekday:0),habit?'Habit due':'Task due',
          owner['name'] as String,at,NotificationDetails(android:AndroidNotificationDetails('xtrack_actions','Actionable reminders',importance:Importance.high,actions:[const AndroidNotificationAction('complete','Complete'),AndroidNotificationAction('later$snooze','Snooze $snooze min')])),payload:jsonEncode([(r['id'] as int)*8+(habit?d.weekday:0),habit?'Habit due':'Task due',owner['name'],habit?'habits':'tasks',owner['id']]),
          androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents:habit?DateTimeComponents.dayOfWeekAndTime:null);
      }
    }
  }
}
