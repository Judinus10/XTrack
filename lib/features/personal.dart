part of '../main.dart';

String clock(BuildContext c,int? minute)=>minute==null?'Time not recorded':TimeOfDay(hour:minute~/60,minute:minute%60).format(c);
Future<void> customReminder(BuildContext c,Store s,{String? title})=>guard(c,()async{
  final name=title??await prompt(c,'Reminder title');
  if(name==null||name.trim().isEmpty||!c.mounted)return;
  final day=await showDatePicker(context:c,initialDate:DateTime.now(),firstDate:DateTime.now(),lastDate:DateTime(2200));
  if(day==null||!c.mounted)return;
  final time=await showTimePicker(context:c,initialTime:TimeOfDay.now());
  if(time==null||!c.mounted)return;
  final input=await prompt(c,'Repeat every how many days? (0 = once)',initial:title==null?'0':'7');
  if(input==null)return;
  final gap=int.tryParse(input);
  if(gap==null||gap<0||gap>365)throw StateError('Choose 0–365 days');
  if(gap==0&&!DateTime(day.year,day.month,day.day,time.hour,time.minute).isAfter(DateTime.now()))throw StateError('Choose a future time');
  var mask=0;
  if(gap==1 && c.mounted){
    final selected=await prompt(c,'Weekdays (1=Mon … 7=Sun)',initial:'1234567');
    if(selected==null)return;
    if(!RegExp(r'^[1-7]+$').hasMatch(selected))throw StateError('Choose weekdays 1–7');
    for(final ch in selected.split('')){mask|=1<<(int.parse(ch)-1);}
  }
  await s.save('custom_reminders',{'name':name,'day':dayKey(day),'minute':time.hour*60+time.minute,'intervalDays':gap,'days':mask});
  if(c.mounted && s.pref('notifications','0')!='1')await remindersEnabled(c,s,true);
});
class Personal extends ConsumerWidget{
  const Personal({super.key});
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider);
    final rows=[...s.rows('measurements')]..sort((a,b)=>(b['day'] as String).compareTo(a['day']));
    return Scaffold(appBar:AppBar(title:const Text('Personal')),body:feed([
      panel(c,[heading('Height'),link('${s.pref('height','Set height')} cm',()=>guard(c,()async{
        final value=await prompt(c,'Height in cm');if(value==null)return;
        if((minor(value)??0)<=0)throw StateError('Enter a positive height');
        await s.setting('height',value);
      }))]),
      panel(c,[heading('Weight history'),link('Log weight',()=>logWeight(c,s)),link('Schedule weight check-ins',()=>customReminder(c,s,title:'Log your weight')),
      if(rows.length>1)SizedBox(height:120,child:LineChart(LineChartData(titlesData:const FlTitlesData(show:false),lineBarsData:[LineChartBarData(color:green,spots:[for(final r in rows.reversed)FlSpot(DateTime.parse(r['day']).millisecondsSinceEpoch/86400000,r['weight']/100)])]))),
      if(rows.isEmpty)note('No measurements yet.'),
      for(final r in rows)ListTile(title:Text('${decimal(r['weight'])} kg'),subtitle:Text(r['day']))])]));
  }
}
Future<void> logWeight(BuildContext c,Store s)=>guard(c,()async{
  final d=await showDatePicker(context:c,initialDate:DateTime.now(),firstDate:DateTime(1900),lastDate:DateTime.now());
  if(d==null||!c.mounted)return;
  final input=await prompt(c,'Weight in kg');if(input==null)return;
  final n=minor(input);if(n==null||n<=0)throw StateError('Enter a positive weight');
  await s.write((t)async{
    await t.rawInsert('INSERT OR REPLACE INTO measurements(day,weight) VALUES(?,?)',[dayKey(d),n]);
    await t.execute("UPDATE goals SET current=(SELECT weight FROM measurements ORDER BY day DESC LIMIT 1) WHERE category='Weight loss'");
  });
});
class PatternPad extends StatefulWidget{
  const PatternPad(this.submit,{super.key});
  final ValueChanged<String> submit;
  @override State<PatternPad> createState()=>_PatternState();
}
class _PatternState extends State<PatternPad>{
  final nodes=<int>[];
  void hit(Offset point){
    for(var i=0;i<9;i++){
      final center=Offset(35.0+70*(i%3),35.0+70*(i~/3));
      if((point-center).distance<23&&!nodes.contains(i))setState(()=>nodes.add(i));
    }
  }
  @override Widget build(BuildContext c)=>Center(child:GestureDetector(
    behavior:HitTestBehavior.opaque,onPanDown:(e){nodes.clear();hit(e.localPosition);},onPanUpdate:(e)=>hit(e.localPosition),
    onPanEnd:(_){final result=nodes.join();setState(nodes.clear);if(result.length>=4)widget.submit('pattern:$result');},
    child:SizedBox(width:210,height:210,child:Wrap(children:[for(var i=0;i<9;i++)SizedBox(width:70,height:70,child:Center(child:Icon(Icons.circle,color:nodes.contains(i)?green:Colors.grey)))]))));
}
Future<String?> pattern(BuildContext c,String title)=>showDialog<String>(context:c,builder:(ctx)=>AlertDialog(title:Text(title),content:Column(mainAxisSize:MainAxisSize.min,children:[const Text('Connect at least four dots'),PatternPad((v)=>Navigator.pop(ctx,v))])));
Future<void> payout(BuildContext c,Store s,RowData deposit)=>guard(c,()async{
  final accounts=s.rows('accounts').where((a)=>a['archived']==0&&a['type']!='Fixed deposit');
  final destination=await showDialog<int>(context:c,builder:(ctx)=>SimpleDialog(title:const Text('Receive payout into'),children:[for(final a in accounts)SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,a['id']),child:Text(a['name']))]));
  if(destination==null||!c.mounted)return;
  final principal=s.balance(deposit);
  final input=await prompt(c,'Actual payout',initial:decimal(deposit['expected']??principal));if(input==null)return;
  final amount=minor(input);if(amount==null||amount<0||principal<=0)throw StateError('Check principal and payout');
  await s.write((t)async{
    final updated=await t.update('accounts',{'archived':1},where:'id=? AND archived=0',whereArgs:[deposit['id']]);
    if(updated!=1)throw StateError('Already paid out');
    await t.insert('transactions',{'kind':'Transfer','account':deposit['id'],'destination':destination,'amount':principal,'day':today});
    final difference=amount-principal;
    if(difference!=0){
      final kind=difference>0?'Income':'Expense',name=difference>0?'Deposit interest':'Deposit fee';
      await t.rawInsert('INSERT OR IGNORE INTO categories(name,kind) VALUES(?,?)',[name,kind]);
      final category=(await t.query('categories',where:'name=? AND kind=?',whereArgs:[name,kind])).single;
      await t.insert('transactions',{'kind':kind,'account':destination,'category':category['id'],'amount':difference.abs(),'day':today});
    }
  },reschedule:true);
});
