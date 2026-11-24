import 'dart:collection' show IterableExtensions;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'metrics.dart';
import 'vault.dart';
import 'alarms.dart';
part 'demo.dart';

final storeProvider=ChangeNotifierProvider<Store>((ref)=>throw StateError('Store not initialized'));
const tables=['categories','accounts','transactions','habits','habit_schedules','habit_logs','tasks','goals','reminders','custom_reminders','measurements','snoozes','settings'];
class Store extends ChangeNotifier {
  late Database db;
  final alarms=Alarms();
  Map<String,List<RowData>> data={};
  List<RowData> ledger=[];
  bool hasPin=false, bio=false;
  String? reminderError;
  Future<void> _pending=Future.value();
  Future<void> init() async {
    var key=await Vault.storage.read(key:'database');
    if(key==null) {
      key=base64UrlEncode(Vault.random(32));
      await Vault.storage.write(key:'database',value:key);
    }
    db=await openDatabase('${await getDatabasesPath()}/xtrack.db',version:4,password:key,
      onConfigure:(d)=>d.execute('PRAGMA foreign_keys=ON'),
      onCreate:(d,v)=>migrate(d,0,v),onUpgrade:migrate);
    hasPin=await Vault.storage.containsKey(key:'pin');
    bio=await Vault.storage.read(key:'bio')=='1';
    await refresh();
    try { await alarms.init(); await sync(); } catch(e) {reminderError=e.toString();}
  }
  static Future<void> migrate(Database db,int from,int to) async {
    for(var v=from+1;v<=to;v++) {
      final sql=await rootBundle.loadString('assets/v$v.sql');
      for(final stmt in sql.split(';').where((s)=>s.trim().isNotEmpty)) {await db.execute(stmt);}
    }
  }
  List<RowData> rows(String table)=>data[table]!;
  List<RowData> get habits=>[for(final h in rows('habits')) {...h,'history':rows('habit_schedules').where((r)=>r['habit']==h['id']).toList()}];
  String pref(String key,String fallback)=>rows('settings').where((r)=>r['key']==key).firstOrNull?['value']??fallback;
  String money(int cents) {
    if(pref('hidden','0')=='1')return '••••';
    final parts=decimal(cents).split('.');
    final grouped=parts.first.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'),(m)=>'${m[1]},');
    return "${pref('currency','LKR')} $grouped.${parts.last}";
  }
  Future<void> refresh() async {
    final snapshot=await db.transaction((t) async {
      final records={for(final name in tables) name:await t.query(name)};
      return (records,await t.query('ledger_entries'));
    });
    data=snapshot.$1;
    ledger=snapshot.$2;
    notifyListeners();
  }
  Future<void> sync() async {
    try {await alarms.sync(data,pref('notifications','0')=='1');reminderError=null;}
    catch(e){reminderError='Could not schedule reminders: $e';}
    notifyListeners();
  }
  Future<void> resumed() {
    final job=_pending.then((_) async {
      await refresh();
      if(pref('notifications','0')=='1')await sync();
    });
    _pending=job.catchError((Object _) {});
    return job;
  }
  Future<void> write(Future<void> Function(Transaction) action,{bool reschedule=false}) {
    final job=_pending.then((_) async {
      await db.transaction(action);
      await refresh();
      if(reschedule) await sync();
    });
    _pending=job.catchError((Object _) {});
    return job;
  }
  Future<void> setting(String key,String value)=>write((t) async {
    await t.insert('settings',{'key':key,'value':value},conflictAlgorithm:ConflictAlgorithm.replace);
  },reschedule:key=='notifications');
  Future<void> save(String table,RowData record,{int? id,int? minute})=>write((t) async {
    if(id!=null)await t.delete('snoozes',where:'owner=? AND ownerId=?',whereArgs:[table,id]);
    if(id==null){id=await t.insert(table,record);} else {await t.update(table,record,where:'id=?',whereArgs:[id]);}
    if(table=='habits'){
      final previous=await t.query('habit_schedules',where:'habit=?',whereArgs:[id],orderBy:'day DESC',limit:1);
      if(previous.isEmpty || previous.first['days']!=record['days']){
        final row=(await t.query('habits',where:'id=?',whereArgs:[id])).single;
        if(row['archived']==0)await t.insert('habit_schedules',{'habit':id,'day':previous.isEmpty?record['start']:today,'days':record['days']},conflictAlgorithm:ConflictAlgorithm.replace);
      }
    }
    if(table=='habits'||table=='tasks'){
      final col=table=='habits'?'habit':'task';
      await t.delete('reminders',where:'$col=?',whereArgs:[id]);
      if(minute!=null) await t.insert('reminders',{col:id,'minute':minute});
    }
  },reschedule:['habits','tasks','accounts','custom_reminders'].contains(table));
  Future<void> change(String table,int id,RowData fields)=>write((t) async {
    await t.delete('snoozes',where:'owner=? AND ownerId=?',whereArgs:[table,id]);
    await t.update(table,fields,where:'id=?',whereArgs:[id]);
    if(table=='habits' && fields.containsKey('archived')){
      final row=(await t.query('habits',where:'id=?',whereArgs:[id])).single;
      await t.insert('habit_schedules',{'habit':id,'day':today,'days':fields['archived']==1?0:row['days']},conflictAlgorithm:ConflictAlgorithm.replace);
    }
  },reschedule:['habits','tasks','accounts','custom_reminders'].contains(table));
  Future<void> remove(String table,int id)=>write((t) async {await t.delete(table,where:'id=?',whereArgs:[id]);},reschedule:true);
  Future<void> log(int habit,String day)=>write((t) async {
    final h=(await t.query('habits',where:'id=?',whereArgs:[habit])).single;
    if(h['archived']==1||day.compareTo(today)>0||!scheduled({...h,'history':await t.query('habit_schedules',where:'habit=?',whereArgs:[habit])},DateTime.parse(day))) throw StateError('Outside habit schedule');
    await t.delete('snoozes',where:'owner=? AND ownerId=?',whereArgs:['habits',habit]);
    final removed=await t.delete('habit_logs',where:'habit=? AND day=?',whereArgs:[habit,day]);
    if(removed==0) await t.insert('habit_logs',{'habit':habit,'day':day});
  },reschedule:true);
  int balance(RowData a,{String? until})=>(a['opening'] as int)+ledger
    .where((r)=>r['account_id']==a['id']&&(until==null||(r['day'] as String).compareTo(until)<=0))
    .fold<int>(0,(n,r)=>n+(r['delta'] as int));
  Future<void> restore(dynamic backup)=>write((t) async {
    if(backup is! Map || ![3,4].contains(backup['version'])) throw const FormatException('Unsupported backup version');
    final records=backup['data'];
    if(backup['version']==3 && records is Map){records['custom_reminders']=[];records['measurements']=[];records['snoozes']=[];}
    if(records is! Map || tables.any((name)=>records[name] is! List)){
      throw const FormatException('Backup is missing a record group');
    }
    for(final name in tables.reversed){await t.delete(name);}
    for(final name in tables){
      final columns=(await t.rawQuery('PRAGMA table_info($name)')).map((r)=>r['name']).toSet();
      for(final row in records[name] as List){
        if(row is! Map || row.keys.any((key)=>!columns.contains(key)))throw const FormatException('Invalid backup fields');
        if(name=='settings' && row['key']=='theme' && !['system','dark','light'].contains(row['value']))throw const FormatException('Invalid theme');
        if(name=='settings' && row['key']=='currency' && !['LKR','USD','EUR','GBP','INR'].contains(row['value']))throw const FormatException('Invalid currency');
        await t.insert(name,Map<String,Object?>.from(row));
      }
    }
    if((await t.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) throw const FormatException('Invalid relationships');
  },reschedule:true);
  Future<void> reset()=>write((t) async {
    for(final name in tables.reversed){await t.delete(name);}
    final sql=await rootBundle.loadString('assets/v1.sql');
    for(final stmt in sql.split(';').map((s)=>s.trim()).where((s)=>s.startsWith('INSERT '))){await t.execute(stmt);}
  },reschedule:true);
}
