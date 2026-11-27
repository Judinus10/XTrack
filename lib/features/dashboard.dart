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
    final tasks=s.rows('tasks').where((r)=>r['day'].compareTo(today)<=0&&r['completed']==null);
    final goals=s.rows('goals').where((r)=>r['category']=='Weight loss'?r['current']>r['target']:r['current']<r['target']);
    final cards=<String,Widget>{
      'Available balance':overview(c,s,monthly),
      'Daily overview':panel(c,[heading('Today at a glance'),
        ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.checklist,color:green),title:const Text('Tasks'),subtitle:Text('${tasks.length} pending'),trailing:const Icon(Icons.chevron_right),onTap:()=>open(c,screen('Tasks',const TaskPage()))),
        ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.repeat,color:green),title:const Text('Habits'),subtitle:Text('$done of ${habits.length} complete'),trailing:const Icon(Icons.chevron_right),onTap:()=>open(c,screen('Habits',const HabitPage())))]),
      'Schedule':panel(c,[heading('Today’s schedule'),if(tasks.isEmpty)note('You’re clear for today.'),for(final t in tasks)taskTile(c,s,t)]),
      'Cash flow':panel(c,[heading('Cash flow',action:link('Analytics',()=>open(c,const Analytics()))),cashFlow(s,b)]),
      'Goals':panel(c,[heading('Active goals',action:link('View all',()=>open(c,const GoalPage()))),if(goals.isEmpty)link('Set a goal',()=>edit(c,'Goal')),for(final g in goals.take(3))goalTile(c,s,g)]),
      'Transactions':panel(c,[heading('Recent transactions'),if(all.isEmpty)note('No transactions yet.'),for(final r in all.take(5))txTile(c,s,r)])
    };
    final order=s.pref('cards',cards.keys.join('|')).split('|').where(cards.containsKey).toList();
    return feed([heading(now.hour<12?'Good morning':now.hour<18?'Good afternoon':'Good evening',action:IconButton(tooltip:'Customize dashboard',icon:const Icon(Icons.tune),onPressed:()=>open(c,CardSettings(cards.keys.toList())))),
      note('${weekdays[now.weekday-1]}, ${now.day} ${months[now.month-1]} ${now.year}'),
      panel(c,[heading('Quick actions'),Wrap(spacing:8,runSpacing:4,children:[
        ActionChip(avatar:const Icon(Icons.north_east,color:red),label:const Text('Expense'),onPressed:()=>edit(c,'Expense')),
        ActionChip(avatar:const Icon(Icons.checklist,color:green),label:const Text('Task'),onPressed:()=>edit(c,'Task')),
        ActionChip(avatar:const Icon(Icons.repeat,color:green),label:const Text('Habit'),onPressed:()=>edit(c,'Habit')),
        ActionChip(avatar:const Icon(Icons.water_drop,color:Colors.blue),label:const Text('Water'),onPressed:()=>entry(c,'Water')),
        ActionChip(avatar:const Icon(Icons.monitor_weight_outlined),label:const Text('Weight'),onPressed:()=>logWeight(c,s))])]),
      for(final key in order)cards[key]!]);
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
    return feed([panel(c,[heading('Manage money'),Wrap(spacing:6,runSpacing:2,children:[
        ActionChip(avatar:const Icon(Icons.pie_chart_outline),label:const Text('Budgets'),onPressed:()=>open(c,const Records('Budget'))),
        ActionChip(avatar:const Icon(Icons.savings_outlined),label:const Text('Fixed deposits'),onPressed:()=>showModalBottomSheet<void>(context:c,showDragHandle:true,builder:(sheetContext)=>SafeArea(child:feed([heading('Fixed deposits'),for(final a in accounts.where((a)=>a['type']=='Fixed deposit'))ListTile(title:Text(a['name']),subtitle:Text('${s.money(s.balance(a))} · Matures ${a['maturity']}'),onTap:(){Navigator.pop(sheetContext);open(c,AccountDetail(a));}),if(!accounts.any((a)=>a['type']=='Fixed deposit'))note('No fixed deposits yet.'),FilledButton.icon(onPressed:(){Navigator.pop(sheetContext);open(c,Editor(kind:'Account',initialAccountType:'Fixed deposit'));},icon:const Icon(Icons.add),label:const Text('Add fixed deposit'))])))),
        ActionChip(avatar:const Icon(Icons.trending_up),label:const Text('Investments'),onPressed:()=>open(c,const Records('Asset'))),
        ActionChip(avatar:const Icon(Icons.receipt_long_outlined),label:const Text('Loans & recurring'),onPressed:()=>open(c,const FinanceTools()))])]),filters(['Week','Month','Year','All'],period,(v)=>setState(()=>period=v)),const SizedBox(height:10),overview(c,s,rows),
      panel(c,[heading('Accounts',action:link('Add account',()=>edit(c,'Account'))),if(accounts.isEmpty)note('Create your first account.'),
        for(final a in accounts.where((a)=>a['type']!='Fixed deposit')) ListTile(contentPadding:EdgeInsets.zero,leading:badge(a),title:Text(a['name']),subtitle:Text(a['archived']==1?'Archived':a['type']),trailing:Text(s.money(s.balance(a))),onTap:()=>open(c,AccountDetail(a))),
        if(accounts.any((a)=>a['type']=='Fixed deposit'))heading('Fixed deposits'),
        for(final a in accounts.where((a)=>a['type']=='Fixed deposit'))ListTile(title:Text(a['name']),subtitle:Text('${s.money(s.balance(a))} · ${a['maturity']}'),onTap:()=>open(c,AccountDetail(a)),trailing:a['archived']==0?link('Payout',()=>payout(c,s,a)):null),
        if(s.rows('accounts').any((r)=>r['archived']==1))link(archived?'Hide archived':'Show archived',()=>setState(()=>archived=!archived))]),
      panel(c,[heading('Expenses by category'),donut(s,rows)]),
      panel(c,[heading('Transactions',action:link('Add',()=>quick(c))),TextField(decoration:const InputDecoration(hintText:'Search transactions',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>query=v)),const SizedBox(height:8),
        filters(['All','Income','Expense','Transfer'],kind,(v)=>setState(()=>kind=v)),if(found.isEmpty)note('No matching transactions.'),for(final r in found)txTile(c,s,r)])]);
  }
}
class AccountDetail extends ConsumerWidget{
  const AccountDetail(this.account,{super.key});
  final RowData account;
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider),rows=recent(s).where((r)=>r['account']==account['id']||r['destination']==account['id']).take(30).toList();
    return Scaffold(appBar:AppBar(title:Text(account['name']),actions:[IconButton(tooltip:'Edit account',onPressed:()=>edit(c,'Account',account),icon:const Icon(Icons.edit_outlined))]),body:SafeArea(child:feed([
      panel(c,[Text(account['type'],style:Theme.of(c).textTheme.titleMedium),const SizedBox(height:8),Text(s.money(s.balance(account)),style:Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),if(account['type']=='Fixed deposit')... [note('Maturity date · ${account['maturity']}'),if(account['archived']==0)FilledButton.tonal(onPressed:()=>payout(c,s,account),child:const Text('Record payout'))]]),
      panel(c,[heading('Transactions'),if(rows.isEmpty)note('No transactions for this account yet.'),for(final r in rows)txTile(c,s,r)])
    ])));
  }
}
