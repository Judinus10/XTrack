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
    final latest=rows.firstOrNull;
    return Scaffold(appBar:AppBar(title:const Text('Health & activity')),body:feed([
      panel(c,[heading('Height'),link('${s.pref('height','Set height')} cm',()=>guard(c,()async{
        final value=await prompt(c,'Height in cm');if(value==null)return;
        if((minor(value)??0)<=0)throw StateError('Enter a positive height');
        await s.setting('height',value);
      }))]),
      panel(c,[heading('Weight'),if(latest!=null)Text('${decimal(latest['weight'])} kg',style:Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),if(latest!=null)note('Latest entry · ${latest['day']}'),FilledButton.icon(onPressed:()=>logWeight(c,s),icon:const Icon(Icons.add),label:const Text('Log weight')),link('Schedule weight check-ins',()=>customReminder(c,s,title:'Log your weight')),
      if(rows.length>1)...[heading('Weight trend'),weightTrend(rows)],
      if(rows.isEmpty)note('No measurements yet.'),
      for(final r in rows)ListTile(title:Text('${decimal(r['weight'])} kg'),subtitle:Text(r['day']),onTap:()=>logWeight(c,s,record:r))])]));
  }
}
Widget weightTrend(List<RowData> descending){
  final rows=descending.reversed.toList();
  final spots=[for(final r in rows)FlSpot(DateTime.parse(r['day']).millisecondsSinceEpoch/86400000,r['weight']/100)];
  final minX=spots.first.x,maxX=spots.last.x,span=maxX-minX;
  final safeMin=span==0?minX-1:minX,safeMax=span==0?maxX+1:maxX;
  return SizedBox(height:210,child:LineChart(LineChartData(minX:safeMin,maxX:safeMax,gridData:const FlGridData(show:false),borderData:FlBorderData(show:false),
    titlesData:FlTitlesData(topTitles:const AxisTitles(),rightTitles:const AxisTitles(),leftTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:40,getTitlesWidget:(v,_)=>Text(v.toStringAsFixed(1),style:const TextStyle(fontSize:10)))),bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:26,interval:span<=4?1:span/4,getTitlesWidget:(v,_) {final d=DateTime.fromMillisecondsSinceEpoch((v*86400000).round());return Text('${d.day}/${d.month}',style:const TextStyle(fontSize:10));}))),
    lineBarsData:[LineChartBarData(spots:spots,color:green,barWidth:3,dotData:const FlDotData(show:true))])));
}
Future<void> logWeight(BuildContext c,Store s,{RowData? record})=>guard(c,()async{
  final controller=TextEditingController(text:record==null?'':decimal(record['weight']));
  var selectedDay=record?['day']??today;
  final saved=await showDialog<bool>(context:c,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(title:Text(record==null?'Log weight':'Edit weight'),content:Column(mainAxisSize:MainAxisSize.min,children:[
    TextField(controller:controller,autofocus:true,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Weight',suffixText:'kg')),
    Align(alignment:Alignment.centerLeft,child:TextButton.icon(onPressed:()async{final d=await showDatePicker(context:ctx,initialDate:DateTime.parse(selectedDay),firstDate:DateTime(1900),lastDate:DateTime.now());if(d!=null)setDialog(()=>selectedDay=dayKey(d));},icon:const Icon(Icons.calendar_today_outlined),label:Text(selectedDay==today?'Today · Change date':selectedDay)))
  ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))])));
  if(saved!=true||!c.mounted){controller.dispose();return;}
  final n=minor(controller.text);controller.dispose();
  if(n==null||n<=0)throw StateError('Enter a positive weight.');
  await s.write((t)async{
    if(record!=null&&record['day']!=selectedDay)await t.delete('measurements',where:'day=?',whereArgs:[record['day']]);
    final measuredAt=selectedDay==today?DateTime.now().millisecondsSinceEpoch:DateTime.parse('${selectedDay}T12:00:00').millisecondsSinceEpoch;
    await t.rawInsert('INSERT OR REPLACE INTO measurements(day,weight,measured_at) VALUES(?,?,?)',[selectedDay,n,measuredAt]);
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
