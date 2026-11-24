part of '../main.dart';
typedef Bucket=({DateTime start,DateTime end,String label});
List<Bucket> buckets(String period){
  final now=DateTime.now();
  if(period=='Week'){
    final mon=shift(now,1-now.weekday);
    return [for(var i=0;i<7;i++)(start:shift(mon,i),end:shift(mon,i+1),label:weekdays[i])];
  }
  if(period=='Year')return [for(var m=1;m<=12;m++)(start:DateTime(now.year,m),end:DateTime(now.year,m+1),label:months[m-1])];
  return [for(var d=1;d<=DateTime(now.year,now.month+1,0).day;d+=7)
    (start:DateTime(now.year,now.month,d),end:DateTime(now.year,now.month,(d+7).clamp(1,DateTime(now.year,now.month+1,0).day+1).toInt()),label:'$d')];
}
bool within(String day,DateTime start,DateTime end)=>day.compareTo(dayKey(start))>=0&&day.compareTo(dayKey(end))<0;
int total(Iterable<RowData> rows,String kind)=>rows.where((r)=>r['kind']==kind).fold(0,(n,r)=>n+(r['amount'] as int));
const plotColors=[green,Color(0xff408cae),Color(0xffe29c4a),Color(0xff8d74c4),Color(0xffe67980)];
Widget legend(String name,Color color)=>Row(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.circle,size:9,color:color),const SizedBox(width:5),Text(name)]);
FlTitlesData axis(List<String> labels)=>FlTitlesData(topTitles:const AxisTitles(),rightTitles:const AxisTitles(),leftTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:40,getTitlesWidget:(v,m){
    final n=v.abs();
    final label=n>=1000000?'${(v/1000000).toStringAsFixed(1)}m':n>=1000?'${(v/1000).toStringAsFixed(1)}k':v.toStringAsFixed(n<1&&n!=0?1:0);
    return Text(label,style:const TextStyle(fontSize:10));
  })),bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,interval:1,reservedSize:24,
  getTitlesWidget:(x,m){final i=x.toInt();return Padding(padding:const EdgeInsets.only(top:5),child:Text(i>=0&&i<labels.length?labels[i]:'',style:const TextStyle(fontSize:10)));})));
Widget bars(List<String> labels,List<List<double>> series,List<String> names,List<Color> shades,{String empty='No activity in this period.'}){
  if(series.every((s)=>s.every((n)=>n==0)))return note(empty);
  return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const SizedBox(height:14),SizedBox(height:145,child:BarChart(BarChartData(
    titlesData:axis(labels),gridData:const FlGridData(show:false),borderData:FlBorderData(show:false),
    barGroups:[for(var i=0;i<labels.length;i++) BarChartGroupData(x:i,barsSpace:2,barRods:[for(var j=0;j<series.length;j++)BarChartRodData(toY:series[j][i],width:labels.length>7?6:10,color:shades[j],borderRadius:const BorderRadius.vertical(top:Radius.circular(3)))])]))),
    Wrap(spacing:14,children:[for(var j=0;j<names.length;j++)legend(names[j],shades[j])])]);
}
Widget cashFlow(Store s,List<Bucket> b){
  if(s.pref('hidden','0')=='1')return note('Balances hidden');
  List<double> values(String kind)=>[for(final p in b)total(s.rows('transactions').where((r)=>within(r['day'],p.start,p.end)),kind)/100];
  return bars([for(final p in b)p.label],[values('Income'),values('Expense')],['Income','Expenses'],[green,red]);
}
Widget donut(Store s,List<RowData> records){
  if(s.pref('hidden','0')=='1')return note('Balances hidden');
  final sums=<String,int>{};
  for(final r in records.where((r)=>r['kind']=='Expense')){
    final name=label(s,'categories',r['category']);sums[name]=(sums[name]??0)+(r['amount'] as int);
  }
  final entries=sums.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
  if(entries.isEmpty)return note('No expenses in this period.');
  return Column(children:[SizedBox(height:155,child:PieChart(PieChartData(centerSpaceRadius:39,sectionsSpace:2,sections:[
    for(var i=0;i<entries.length;i++) PieChartSectionData(value:entries[i].value.toDouble(),color:plotColors[i%plotColors.length],radius:24,showTitle:false)]))),
    for(var i=0;i<entries.length;i++)ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:Icon(Icons.circle,color:plotColors[i%plotColors.length],size:12),title:Text(entries[i].key),trailing:Text(s.money(entries[i].value)))]);
}
class Analytics extends ConsumerStatefulWidget{
  const Analytics({super.key});
  @override ConsumerState<Analytics> createState()=>_AnalyticsState();
}
class _AnalyticsState extends ConsumerState<Analytics>{
  String period='Month';
  @override Widget build(BuildContext c){
    final s=ref.watch(storeProvider),b=buckets(period);
    final labels=b.map((p)=>p.label).toList();
    final records=s.rows('transactions').where((r)=>within(r['day'],b.first.start,b.last.end)).toList();
    final spots=<FlSpot>[];
    for(var i=0;i<b.length;i++){
      if(dayKey(b[i].start).compareTo(today)>0)break;
      final end=shift(b[i].end,-1);
      final until=end.isAfter(DateTime.now())?today:dayKey(end);
      spots.add(FlSpot(i.toDouble(),s.rows('accounts').where((a)=>a['type']!='Fixed deposit').fold<int>(0,(n,a)=>n+s.balance(a,until:until))/100));
    }
    final habits=[for(final p in b)s.rows('habit_logs').where((r)=>within(r['day'],p.start,p.end)).length.toDouble()];
    final done=[for(final p in b)s.rows('tasks').where((r)=>r['completed']!=null&&within(r['completed'],p.start,p.end)).length.toDouble()];
    final due=[for(final p in b)s.rows('tasks').where((r)=>r['completed']==null&&within(r['day'],p.start,p.end)).length.toDouble()];
    final goals=s.rows('goals').where((r)=>within(r['day'],b.first.start,b.last.end)).toList();
    return Scaffold(appBar:AppBar(title:const Text('Analytics')),body:SafeArea(child:feed([
      filters(['Week','Month','Year'],period,(v)=>setState(()=>period=v)),const SizedBox(height:12),
      panel(c,[heading('Income vs expenses'),cashFlow(s,b)]),panel(c,[heading('Expenses by category'),donut(s,records)]),
      panel(c,[heading('Balance trend'),if(s.pref('hidden','0')=='1')note('Balances hidden') else if(spots.every((p)=>p.y==0)&&records.isEmpty)note('No balance activity yet.') else ...[
        note('Closing balance · ${s.money((spots.last.y*100).round())}'),
        SizedBox(height:145,child:LineChart(LineChartData(minX:0,maxX:(b.length-1).toDouble(),titlesData:axis(labels),gridData:const FlGridData(show:false),borderData:FlBorderData(show:false),lineBarsData:[LineChartBarData(spots:spots,color:green,barWidth:3,dotData:const FlDotData(show:true))])))] ]),
      panel(c,[heading('Habit completions'),bars(labels,[habits],['Check-ins'],[green])]),
      panel(c,[heading('Task completion'),bars(labels,[done,due],['Completed','Pending due'],[green,Colors.blueGrey])]),
      panel(c,[heading('Goals due this period'),if(goals.isEmpty)note('No goals due this period.'),for(final g in goals)goalTile(c,s,g)])])));
  }
}
