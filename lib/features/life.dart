part of '../main.dart';

const units={'Water':'ml','Sleep':'hours','Workout':'minutes','Body measurement':'cm','Mood':'','Journal':''};
Store storeOf(BuildContext c)=>ProviderScope.containerOf(c).read(storeProvider);
Widget destination(BuildContext c,String label,IconData icon,Widget page)=>ListTile(leading:Icon(icon),title:Text(label),trailing:const Icon(Icons.chevron_right),onTap:()=>open(c,page));
Widget screen(String title,Widget child)=>Scaffold(appBar:AppBar(title:Text(title)),body:SafeArea(child:child));
Future<String?> choose(BuildContext c,String title,List<String> values)=>showModalBottomSheet<String>(context:c,showDragHandle:true,builder:(ctx)=>SafeArea(child:ListView(shrinkWrap:true,children:[Padding(padding:const EdgeInsets.all(16),child:heading(title)),for(final v in values)ListTile(title:Text(v),onTap:()=>Navigator.pop(ctx,v))])));
Future<void> addMenu(BuildContext c,int index,DateTime date)async{
  final options=[['Income','Expense','Transfer','Task','Habit','Goal','Water','Journal'],['Income','Expense','Transfer','Account','Budget','Asset'],['Task','Habit','Project'],['Goal',...units.keys]];
  final kind=await choose(c,'Quick Add',options[index]);if(kind==null||!c.mounted)return;
  if(units.containsKey(kind)||['Budget','Asset','Project'].contains(kind)){await entry(c,kind);return;}
  await open(c,Editor(kind:kind,initialDay:index==2?dayKey(date):null));
}
String tableFor(String kind)=>switch(kind){'Budget'=>'budgets','Asset'=>'valuations','Project'=>'projects',_=>'personal_logs'};
Future<void> entry(BuildContext c,String kind,[RowData? r])=>guard(c,()async{
  final s=storeOf(c),budget=kind=='Budget',asset=kind=='Asset',project=kind=='Project';
  final date=await showDatePicker(context:c,initialDate:DateTime.parse(r?['day']??(budget&&r!=null?"${r['month']}-01":today)),firstDate:DateTime(1900),lastDate:DateTime(2200));
  if(date==null||!c.mounted)return;
  final day=dayKey(date);
  Future<int?> number(String title,String key)async{
    final str=await prompt(c,title,initial:r==null?'':decimal(r[key]));if(str==null)return null;
    final n=minor(str);if(n==null||n<0)throw StateError('Enter a non-negative number');return n;
  }
  late RowData row;
  if(budget){
    final category=await choose(c,'Budget category',['All expenses',...s.rows('categories').where((v)=>v['kind']=='Expense').map((v)=>v['name'] as String)]);
    if(category==null||!c.mounted)return;
    final amount=await number('Monthly limit','amount');if(amount==null)return;
    if(amount==0)throw StateError('Limit must be positive');
    row={'month':day.substring(0,7),'category':category,'amount':amount};
  }else{
    final name=await prompt(c,kind=='Journal'?'Journal title':kind=='Mood'?'How did you feel?':'$kind name',initial:r?['name']??(units[kind]?.isNotEmpty==true?kind:''));if(name==null||!c.mounted)return;
    if(name.isEmpty)throw StateError('Enter a name');
    if(asset){
      final type=await choose(c,'Asset type',['Stocks','Gold','Unit trust','Property','Vehicle','Other']);if(type==null||!c.mounted)return;
      final cost=await number('Purchase value','cost');if(cost==null||!c.mounted)return;
      final value=await number('Current estimated value','value');if(value==null)return;
      row={'name':name,'kind':type,'day':day,'cost':cost,'value':value};
    }else{
      int? quantity=0;
      if(units[kind]?.isNotEmpty==true){quantity=await number('Amount in ${units[kind]}','quantity');if(quantity==null||!c.mounted)return;if(quantity==0)throw StateError('Amount must be positive');}
      final notes=await prompt(c,'Notes (optional)',initial:r?['notes']??'');if(notes==null)return;
      row={'name':name,'day':day,'notes':notes,if(!project)'kind':kind,if(!project)'quantity':quantity};
    }
  }
  await s.save(tableFor(kind),row,id:r?['id']);
});
class Records extends ConsumerWidget{
  const Records(this.kind,{super.key});final String kind;
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider),table=tableFor(kind);
    final rows=s.rows(table).where((r)=>table!='personal_logs'||r['kind']==kind).toList()..sort((a,b)=>(b['day']??b['month']).compareTo(a['day']??a['month']) as int);
    return screen(kind,feed([link('Add $kind',()=>entry(c,kind)),if(rows.isEmpty)note('No records yet.'),for(final r in rows)Builder(builder:(_){
      String detail;
      if(kind=='Budget'){
        final spent=s.rows('transactions').where((t)=>t['kind']=='Expense' && t['day'].startsWith(r['month'])&&(r['category']=='All expenses'||label(s,'categories',t['category'])==r['category'])).fold<int>(0,(v,t)=>v+(t['amount'] as int));
        detail="${r['month']} · ${s.money(spent)} spent · ${s.money(r['amount']-spent)} remaining";
      }else if(kind=='Asset'){detail="${r['kind']} · ${s.money(r['value'])} · Change ${s.money(r['value']-r['cost'])}";}
      else if(kind=='Project'){final tasks=s.rows('tasks').where((t)=>t['project']==r['id']);detail="${r['day']} · ${tasks.where((t)=>t['completed']!=null).length}/${tasks.length} tasks done";}
      else{detail="${r['day']} · ${units[kind]!.isEmpty?'':decimal(r['quantity'])+' '+units[kind]!} ${r['notes']}";}
      return panel(c,[ListTile(title:Text(r['name']??r['category']),subtitle:Text(detail),onTap:()=>entry(c,kind,r),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{if(await confirm(c,'Delete record?','Remove this entry?')&&c.mounted)await guard(c,()=>s.remove(table,r['id']));}))]);
    })]));
  }
}
class Planner extends ConsumerWidget{
  const Planner(this.date,this.select,{super.key});final DateTime date;final ValueChanged<DateTime> select;
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider),day=dayKey(date),mon=shift(date,1-date.weekday);
    final tasks=s.rows('tasks').where((r)=>r['day']==day).toList()..sort((a,b)=>((a['startMinute']??1440) as int).compareTo(b['startMinute']??1440));
    return feed([heading('${months[date.month-1]} ${date.year}',action:link('Today',()=>select(DateTime.now()))),
      Row(children:[IconButton(tooltip:'Previous week',icon:const Icon(Icons.chevron_left),onPressed:()=>select(shift(date,-7))),Expanded(child:Text(day,textAlign:TextAlign.center)),IconButton(tooltip:'Next week',icon:const Icon(Icons.chevron_right),onPressed:()=>select(shift(date,7)))]),
      Row(children:[for(var i=0;i<7;i++)Expanded(child:InkWell(onTap:()=>select(shift(mon,i)),child:Container(padding:const EdgeInsets.symmetric(vertical:10),decoration:BoxDecoration(color:i==date.weekday-1?green.withAlpha(65):null,borderRadius:BorderRadius.circular(12)),child:Text('${weekdays[i]}\n${shift(mon,i).day}',textAlign:TextAlign.center))))]),
      panel(c,[heading('Agenda'),for(final t in tasks)ListTile(leading:Text(t['startMinute']==null?'All day':clock(c,t['startMinute'])),title:Text(t['name']),subtitle:Text(t['completed']!=null?'Completed':t['stage']??'To Do'),onTap:()=>edit(c,'Task',t)),
      for(final h in s.habits.where((h)=>h['archived']==0&&scheduled(h,date)))ListTile(leading:const Icon(Icons.repeat),title:Text(h['name']),subtitle:const Text('Scheduled habit'),onTap:()=>edit(c,'Habit',h))]),
      destination(c,'Tasks',Icons.checklist,screen('Tasks',const TaskPage())),destination(c,'Habits',Icons.repeat,screen('Habits',const HabitPage())),destination(c,'Projects',Icons.folder_outlined,const Records('Project')),destination(c,'Kanban board',Icons.view_column,const Board()),destination(c,'Focus timer',Icons.timer_outlined,const FocusTimer())]);
  }
}
class FocusTimer extends ConsumerStatefulWidget{const FocusTimer({super.key});@override ConsumerState<FocusTimer> createState()=>_FocusState();}
class _FocusState extends ConsumerState<FocusTimer>{
  Timer? tick;
  @override void initState(){super.initState();tick=Timer.periodic(const Duration(seconds:1),(_)=>setState((){}));}
  @override void dispose(){tick?.cancel();super.dispose();}
  @override Widget build(BuildContext c){final s=ref.watch(storeProvider),rows=s.rows('focus_sessions').reversed.toList(),active=rows.where((r)=>r['ended']==null).firstOrNull;
    return screen('Focus timer',feed([FilledButton(onPressed:()=>guard(c,()async{
      if(active!=null){await s.change('focus_sessions',active['id'],{'ended':DateTime.now().millisecondsSinceEpoch});return;}
      final name=await prompt(c,'What are you working on?');if(name!=null&&name.isNotEmpty)await s.save('focus_sessions',{'name':name,'started':DateTime.now().millisecondsSinceEpoch});
    }),child:Text(active==null?'Start session':'Finish session')),for(final r in rows)ListTile(title:Text(r['name']),subtitle:Text(Duration(milliseconds:(r['ended']??DateTime.now().millisecondsSinceEpoch)-r['started']).toString().split('.').first))]));
  }
}
class LifeHub extends StatelessWidget{const LifeHub({super.key});@override Widget build(BuildContext c)=>feed([destination(c,'Goals',Icons.flag_outlined,const GoalPage()),destination(c,'Height and weight',Icons.monitor_weight_outlined,const Personal()),for(final kind in units.keys)destination(c,kind,Icons.edit_note,Records(kind))]);}
class MoreHub extends StatelessWidget{const MoreHub({super.key});@override Widget build(BuildContext c)=>feed([destination(c,'Analytics',Icons.bar_chart,const Analytics()),destination(c,'Reminders',Icons.notifications_none,const ReminderPage()),destination(c,'Reports and exports',Icons.file_download_outlined,const ReportsPage()),destination(c,'Recycle bin',Icons.restore_from_trash,const BinPage()),destination(c,'Settings and backup',Icons.settings_outlined,const SettingsPage())]);}
class SearchRecords extends ConsumerStatefulWidget{const SearchRecords({super.key});@override ConsumerState<SearchRecords> createState()=>_SearchState();}
class _SearchState extends ConsumerState<SearchRecords>{
  String query='';
  @override Widget build(BuildContext c){final s=ref.watch(storeProvider);return screen('Search',feed([TextField(autofocus:true,decoration:const InputDecoration(labelText:'Search records'),onChanged:(v)=>setState(()=>query=v.trim().toLowerCase())),if(query.isNotEmpty)for(final group in {'tasks':'Task','habits':'Habit','goals':'Goal','accounts':'Account','projects':'Project','personal_logs':'Personal'}.entries)for(final r in s.rows(group.key).where((r)=>(r['name'] as String).toLowerCase().contains(query)))ListTile(title:Text(r['name']),subtitle:Text(group.value),onTap:()=>['Project','Personal'].contains(group.value)?entry(c,group.value=='Project'?'Project':r['kind'],r):edit(c,group.value,r))]));}
}
class FinanceTools extends ConsumerWidget{
  const FinanceTools({super.key});
  Future<void> create(BuildContext c,Store s,String kind)async{
    final name=await prompt(c,'Name');if(name==null||name.isEmpty||!c.mounted)return;
    final amount=minor(await prompt(c,'Amount')??'');if(amount==null||amount<=0||!c.mounted)return;
    final accts=s.rows('accounts').where((a)=>a['archived']==0&&a['type']!='Fixed deposit').toList();
    String display(RowData a)=>"${a['name']} (#${a['id']})";
    final pick=await choose(c,'Account',accts.map(display).toList());if(pick==null||!c.mounted)return;
    final acct=accts.firstWhere((a)=>display(a)==pick)['id'];
    final day=await showDatePicker(context:c,initialDate:DateTime.now(),firstDate:DateTime(1900),lastDate:kind=='Debt'||kind=='Lending'?DateTime.now():DateTime(2200));if(day==null||!c.mounted)return;
    if(kind=='Debt'||kind=='Lending'){
      final due=await showDatePicker(context:c,initialDate:day,firstDate:day,lastDate:DateTime(2200));if(due==null)return;
      await s.save('loans',{'name':name,'kind':kind,'account':acct,'principal':amount,'day':dayKey(day),'due':dayKey(due)});return;
    }
    final type=kind=='Subscription'?'Expense':await choose(c,'Transaction type',['Income','Expense']);if(type==null||!c.mounted)return;
    final categories=s.rows('categories').where((a)=>a['kind']==type);
    final cat=await choose(c,'Category',categories.map((v)=>v['name'] as String).toList());if(cat==null||!c.mounted)return;
    final freq=await choose(c,'Frequency',['Daily','Weekly','Monthly','Yearly','Custom']);if(freq==null||!c.mounted)return;
    final days=freq=='Custom'?int.tryParse(await prompt(c,'Interval in days')??''):1;if(days==null||days<1)return;
    if(!c.mounted||!await confirm(c,'Enable automatic posting?','Due occurrences from the selected date will post to the account.'))return;
    await s.save('recurring',{'name':name,'account':acct,'kind':type,'category':categories.firstWhere((r)=>r['name']==cat)['id'],'amount':amount,'subscription':kind=='Subscription'?1:0,'next':dayKey(day),'frequency':freq,'anchor':day.day,'intervalDays':days});
  }
  int remaining(Store s,RowData l)=>l['principal']-s.rows('repayments').where((r)=>r['loan']==l['id']).fold<int>(0,(v,r)=>v+(r['principal'] as int));
  Future<void> repay(BuildContext c,Store s,RowData loan)async{
    final principal=minor(await prompt(c,'Principal repaid')??'');if(principal==null||!c.mounted)return;
    final interest=minor(await prompt(c,'Interest paid',initial:'0')??'');if(interest==null)return;
    if(principal<0||interest<0||principal+interest==0)throw StateError('Enter a valid payment');
    await s.write((t)async{
      final paid=(await t.rawQuery('SELECT COALESCE(SUM(principal),0) AS n FROM repayments WHERE loan=?',[loan['id']])).single['n'] as int;
      if(paid+principal>loan['principal'])throw StateError('Principal exceeds outstanding balance');
      await t.insert('repayments',{'loan':loan['id'],'account':loan['account'],'day':today,'principal':principal,'interest':interest});
      if(interest>0){
        final kind=loan['kind']=='Debt'?'Expense':'Income';
        await t.rawInsert('INSERT OR IGNORE INTO categories(name,kind) VALUES(?,?)',['Loan interest',kind]);
        final cat=(await t.query('categories',where:'name=? AND kind=?',whereArgs:['Loan interest',kind])).single;
        await t.insert('transactions',{'kind':kind,'amount':interest,'category':cat['id'],'day':today,'account':loan['account'],'description':loan['name']});
      }
    });
  }
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider),loans=s.rows('loans');
    final debt=loans.where((r)=>r['kind']=='Debt').fold<int>(0,(n,l)=>n+remaining(s,l));
    final owed=loans.where((r)=>r['kind']=='Lending').fold<int>(0,(n,l)=>n+remaining(s,l));
    final assets=s.rows('accounts').fold<int>(0,(n,a)=>n+s.balance(a))+owed+s.rows('valuations').fold<int>(0,(n,a)=>n+(a['value'] as int));
    return screen('Loans and schedules',feed([panel(c,[heading('Net worth'),note(s.money(assets-debt)),note('Assets ${s.money(assets)} · Liabilities ${s.money(debt)}')]),
      Wrap(children:[for(final k in ['Debt','Lending','Recurring','Subscription'])link('Add $k',()=>guard(c,()=>create(c,s,k)))]),
      for(final l in loans)panel(c,[heading(l['name']),note("${l['kind']} · Due ${l['due']} · ${s.money(remaining(s,l))} outstanding"),if(remaining(s,l)>0)link('Record repayment',()=>guard(c,()=>repay(c,s,l))),for(final r in s.rows('repayments').where((r)=>r['loan']==l['id']))note("${r['day']} · ${s.money(r['principal'])} principal + ${s.money(r['interest'])} interest")]),
      for(final r in s.rows('recurring'))SwitchListTile(title:Text(r['name']),subtitle:Text("${r['frequency']} · ${s.money(r['amount'])} · Next ${r['next']}"),value:r['paused']==0,onChanged:(v)=>guard(c,()=>s.change('recurring',r['id'],{'paused':v?0:1,if(v&&r['next'].compareTo(today)<0)'next':today}))) ]));
  }
}
Widget metricGrid(BuildContext c,Map<String,String> values)=>LayoutBuilder(builder:(ctx,box){
  final narrow=box.maxWidth<315||MediaQuery.textScalerOf(c).scale(16)>22;
  return Wrap(spacing:10,children:[for(final e in values.entries)SizedBox(width:narrow?box.maxWidth:(box.maxWidth-10)/2,child:panel(c,[Text(e.key),const SizedBox(height:8),Text(e.value,style:Theme.of(c).textTheme.titleLarge)]))]);
});
class CardSettings extends ConsumerWidget{
  const CardSettings(this.keysList,{super.key});final List<String> keysList;
  @override Widget build(BuildContext c,WidgetRef ref){final s=ref.watch(storeProvider),order=s.pref('cards',keysList.join('|')).split('|').where(keysList.contains).toList();
    return screen('Dashboard cards',ListView(children:[for(final key in [...order,...keysList.where((k)=>!order.contains(k))])ListTile(title:Text(key),leading:Checkbox(value:order.contains(key),onChanged:(v)=>guard(c,()=>s.setting('cards',(v==true?[...order,key]:order.where((k)=>k!=key)).join('|')))),trailing:order.indexOf(key)>0?IconButton(tooltip:'Move up',icon:const Icon(Icons.arrow_upward),onPressed:()=>guard(c,()async{final at=order.indexOf(key);order.removeAt(at);order.insert(at-1,key);await s.setting('cards',order.join('|'));})):null)]));
  }
}
class BinPage extends ConsumerWidget{
  const BinPage({super.key});
  @override Widget build(BuildContext c,WidgetRef ref){final s=ref.watch(storeProvider),rows=s.rows('deleted_records');return screen('Recycle bin',feed([note('Deleted entries are recoverable for 30 days.'),for(final r in rows)ListTile(title:Text(r['title']),subtitle:Text(r['removed']),onTap:()=>guard(c,()=>s.recover(r)),trailing:IconButton(tooltip:'Permanently delete',icon:const Icon(Icons.delete_forever),onPressed:()async{if(await confirm(c,'Permanently delete?','This entry cannot be recovered.')&&c.mounted)await guard(c,()=>s.remove('deleted_records',r['id']));}))]));}
}
class ReportsPage extends ConsumerStatefulWidget{
  const ReportsPage({super.key});
  @override ConsumerState<ReportsPage> createState()=>_ReportsState();
}
class _ReportsState extends ConsumerState<ReportsPage>{
  late DateTimeRange range=DateTimeRange(start:DateTime(DateTime.now().year,DateTime.now().month),end:DateTime.now());
  @override Widget build(BuildContext c){final s=ref.watch(storeProvider);
    bool included(String day)=>within(day,range.start,shift(range.end,1));
    final tx=recent(s).where((r)=>included(r['day'])).toList();
    final summary={'Income':s.money(total(tx,'Income')),'Expenses':s.money(total(tx,'Expense')),'Savings':s.money(total(tx,'Income')-total(tx,'Expense')),'Habit check-ins':'${s.rows('habit_logs').where((r)=>included(r['day'])).length}','Tasks completed':'${s.rows('tasks').where((r)=>r['completed']!=null&&included(r['completed'])).length}'};
    Future<void> export(bool pdf)async{
      Uint8List bytes;
      if(pdf){
        final document=pw.Document();document.addPage(pw.MultiPage(build:(_)=>[pw.Header(level:0,text:'XTrack summary'),pw.Text('${dayKey(range.start)} - ${dayKey(range.end)}'),for(final e in summary.entries)pw.Paragraph(text:'${e.key}: ${e.value}')]));
        bytes=await document.save();
      }else{
        if(s.pref('hidden','0')=='1')throw StateError('Show financial balances before exporting transactions');
        final rows=<List<dynamic>>[['Date','Type','Amount','Account','Destination','Category','Description'],for(final t in tx)[t['day'],t['kind'],decimal(t['amount']),label(s,'accounts',t['account']),label(s,'accounts',t['destination']),label(s,'categories',t['category']),t['description']]];
        bytes=Uint8List.fromList(utf8.encode(const ListToCsvConverter().convert(rows)));
      }
      await Vault.device.invokeMethod<bool>('report',{'name':'XTrack-${dayKey(range.end)}.${pdf?'pdf':'csv'}','mime':pdf?'application/pdf':'text/csv','bytes':bytes});
    }
    return screen('Reports',feed([link('${dayKey(range.start)} – ${dayKey(range.end)}',()async{final v=await showDateRangePicker(context:c,firstDate:DateTime(1900),lastDate:DateTime.now(),initialDateRange:range);if(v!=null)setState(()=>range=v);}),metricGrid(c,summary),link('Import transaction CSV',()=>guard(c,()=>importCsv(c,s))),link('Export summary PDF',()=>guard(c,()=>export(true))),link('Export transactions CSV',()=>guard(c,()=>export(false)))]));
  }
}
class CheckItems extends ConsumerWidget{
  const CheckItems(this.kind,this.id,{super.key});final String kind;final int id;
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider),task=kind=='Task',table=task?'subtasks':'milestones',owner=task?'task':'goal';
    return panel(c,[heading(task?'Subtasks':'Milestones',action:link('Add',()=>guard(c,()async{
      final name=await prompt(c,task?'Subtask name':'Milestone name');if(name!=null&&name.isNotEmpty)await s.save(table,{owner:id,'name':name});
    }))),for(final r in s.rows(table).where((r)=>r[owner]==id))CheckboxListTile(value:r['done']==1,title:Text(r['name']),onChanged:(v)=>guard(c,()=>s.change(table,r['id'],{'done':v==true?1:0})))]);
  }
}
class Board extends ConsumerWidget{
  const Board({super.key});
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider);
    return screen('Kanban board',feed([for(final stage in ['To Do','In Progress','Completed'])panel(c,[heading(stage),for(final r in s.rows('tasks').where((t)=>(t['completed']!=null?'Completed':t['stage']??'To Do')==stage))ListTile(title:Text(r['name']),subtitle:Text(r['day']),onTap:()=>edit(c,'Task',r),trailing:PopupMenuButton<String>(onSelected:(v)=>guard(c,()=>s.change('tasks',r['id'],{'stage':v=='Completed'?'To Do':v,'completed':v=='Completed'?today:null})),itemBuilder:(_)=>[for(final v in ['To Do','In Progress','Completed'])PopupMenuItem(value:v,child:Text(v))]))])]));
  }
}
Future<void> importCsv(BuildContext c,Store s)async{
  final raw=await Vault.device.invokeMethod<Uint8List>('open');if(raw==null||!c.mounted)return;
  final lines=const CsvToListConverter(shouldParseNumbers:false,eol:'\n').convert(utf8.decode(raw).replaceAll('\r\n','\n'));
  if(lines.isEmpty||lines.first.join('|')!='Date|Type|Amount|Account|Destination|Category|Description')throw const FormatException('Use the columns from the XTrack transaction CSV export');
  final candidates=<RowData>[];var skipped=0;
  int resolve(String table,String name,{String? kind}){
    final matches=s.rows(table).where((r)=>r['name']==name&&(kind==null||r['kind']==kind));
    if(matches.length!=1)throw FormatException('Missing or ambiguous $table entry: $name');
    return matches.single['id'];
  }
  String fingerprint(RowData r)=>jsonEncode([for(final key in ['day','kind','amount','account','destination','category','description'])r[key]]);
  final seen=s.rows('transactions').map(fingerprint).toSet();
  for(final line in lines.skip(1)){
    if(line.length==1&&line.first=='')continue;
    if(line.length!=7)throw const FormatException('Expected seven columns per row');
    final day=line[0] as String,kind=line[1] as String,amount=minor(line[2]);
    if(dayKey(DateTime.parse(day))!=day||day.compareTo(today)>0||amount==null||amount<=0||!['Income','Expense','Transfer'].contains(kind))throw FormatException('Invalid transaction: $day $kind');
    final r={'day':day,'kind':kind,'amount':amount,'account':resolve('accounts',line[3]),'destination':kind=='Transfer'?resolve('accounts',line[4]):null,'category':kind=='Transfer'?null:resolve('categories',line[5],kind:kind),'description':line[6]};
    if(seen.add(fingerprint(r))){candidates.add(r);}else{skipped++;}
  }
  if(!c.mounted||!await confirm(c,'Import ${candidates.length} transactions?','$skipped duplicate rows skipped.\n${candidates.take(4).map((r)=>"${r['day']} · ${r['kind']} · ${s.money(r['amount'])}").join('\n')}'))return;
  await s.write((t)async{
    final existing=(await t.query('transactions')).map(fingerprint).toSet();
    for(final r in candidates){if(existing.add(fingerprint(r)))await t.insert('transactions',r);}
  });
}
