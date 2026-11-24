part of '../main.dart';
Widget overview(BuildContext c,Store s,List<RowData> records){
  final balance=s.rows('accounts').where((a)=>a['type']!='Fixed deposit').fold<int>(0,(sum,a)=>sum+s.balance(a));
  return Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xff103d2a),borderRadius:BorderRadius.circular(20)),
    child:DefaultTextStyle(style:const TextStyle(color:Colors.white),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Expanded(child:Text('Available balance')),IconButton(tooltip:'Show or hide financial amounts',color:Colors.white,icon:Icon(s.pref('hidden','0')=='1'?Icons.visibility_off_outlined:Icons.visibility_outlined),onPressed:()=>guard(c,()=>s.setting('hidden',s.pref('hidden','0')=='1'?'0':'1')))]),
      FittedBox(fit:BoxFit.scaleDown,child:Text(s.money(balance),style:const TextStyle(fontSize:32,fontWeight:FontWeight.w700))),const SizedBox(height:16),
      Wrap(spacing:28,runSpacing:8,children:[for(final kind in ['Income','Expense'])Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(kind,style:const TextStyle(color:Colors.white70)),Text(s.money(total(records,kind)),style:const TextStyle(fontWeight:FontWeight.w600))])])])));
}
class Dashboard extends ConsumerWidget{
  const Dashboard({super.key});
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider),now=DateTime.now(),b=buckets('Month');
    final all=recent(s),monthly=all.where((r)=>within(r['day'],b.first.start,b.last.end)).toList();
    final habits=s.habits.where((h)=>h['archived']==0&&scheduled(h,now)).toList();
    final done=habits.where((h)=>logs(s,h).contains(today)).length;
    final tasks=s.rows('tasks').where((r)=>r['day']==today&&r['completed']==null);
    final goals=s.rows('goals').where((r)=>r['category']=='Weight loss'?r['current']>r['target']:r['current']<r['target']);
    return feed([Text(now.hour<12?'Good morning':now.hour<18?'Good afternoon':'Good evening',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),
      link('Personal measurements',()=>open(c,const Personal())),note('${weekdays[now.weekday-1]}, ${now.day} ${months[now.month-1]} ${now.year}'),overview(c,s,monthly),
      panel(c,[heading('This month',action:link('Analytics',()=>open(c,const Analytics()))),cashFlow(s,b)]),
      panel(c,[heading('Today’s habits'),if(habits.isEmpty)link('Create a habit',()=>edit(c,'Habit')) else ...[note('$done of ${habits.length} completed'),meter(done/habits.length)]]),
      panel(c,[heading('Today’s tasks',action:link('Add',()=>edit(c,'Task'))),if(tasks.isEmpty)note('No pending tasks due today.'),for(final t in tasks)taskTile(c,s,t)]),
      panel(c,[heading('Active goals',action:link('View all',()=>open(c,const GoalPage()))),if(goals.isEmpty)link('Set a goal',()=>edit(c,'Goal')),for(final g in goals.take(3))goalTile(c,s,g)]),
      panel(c,[heading('Recent transactions'),if(all.isEmpty)link('Add an expense',()=>edit(c,'Expense')),for(final r in all.take(5))txTile(c,s,r)])]);
  }
}
class Finance extends ConsumerStatefulWidget{
  const Finance({super.key});
  @override ConsumerState<Finance> createState()=>_FinanceState();
}
class _FinanceState extends ConsumerState<Finance>{
  String period='Month',kind='All',query='';
  bool archived=false;
  @override Widget build(BuildContext c){
    final s=ref.watch(storeProvider),b=buckets(period=='All'?'Year':period);
    final rows=recent(s).where((r)=>period=='All'||within(r['day'],b.first.start,b.last.end)).toList();
    final found=rows.where((r)=>(kind=='All'||kind==r['kind']) && [r['description'],r['kind'],r['day'],label(s,'categories',r['category']),label(s,'accounts',r['account']),label(s,'accounts',r['destination'])].join(' ').toLowerCase().contains(query.toLowerCase()));
    final accounts=s.rows('accounts').where((r)=>archived||r['archived']==0);
    return feed([filters(['Week','Month','Year','All'],period,(v)=>setState(()=>period=v)),const SizedBox(height:10),overview(c,s,rows),
      panel(c,[heading('Accounts',action:link('Add account',()=>edit(c,'Account'))),if(accounts.isEmpty)note('Create your first account.'),
        for(final a in accounts.where((a)=>a['type']!='Fixed deposit')) ListTile(contentPadding:EdgeInsets.zero,leading:badge(a),title:Text(a['name']),subtitle:Text(a['archived']==1?'Archived':a['type']),trailing:Text(s.money(s.balance(a))),onTap:()=>edit(c,'Account',a)),
        if(accounts.any((a)=>a['type']=='Fixed deposit'))heading('Fixed deposits'),
        for(final a in accounts.where((a)=>a['type']=='Fixed deposit'))ListTile(title:Text(a['name']),subtitle:Text('${s.money(s.balance(a))} · ${a['maturity']}'),onTap:()=>edit(c,'Account',a),trailing:a['archived']==0?link('Payout',()=>payout(c,s,a)):null),
        if(s.rows('accounts').any((r)=>r['archived']==1))link(archived?'Hide archived':'Show archived',()=>setState(()=>archived=!archived))]),
      panel(c,[heading('Expenses by category'),donut(s,rows)]),
      panel(c,[heading('Transactions',action:link('Add',()=>quick(c))),TextField(decoration:const InputDecoration(hintText:'Search transactions',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>query=v)),const SizedBox(height:8),
        filters(['All','Income','Expense','Transfer'],kind,(v)=>setState(()=>kind=v)),if(found.isEmpty)note('No matching transactions.'),for(final r in found)txTile(c,s,r)])]);
  }
}
