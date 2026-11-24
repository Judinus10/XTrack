part of '../main.dart';
class HabitPage extends ConsumerStatefulWidget{
  const HabitPage({super.key});
  @override ConsumerState<HabitPage> createState()=>_HabitState();
}
class _HabitState extends ConsumerState<HabitPage>{
  String filter='Today';
  int week=0;
  @override Widget build(BuildContext c){
    final s=ref.watch(storeProvider),now=DateTime.now();
    final habits=s.habits;
    final planned=habits.where((h)=>h['archived']==0&&scheduled(h,now));
    final done=planned.where((h)=>logs(s,h).contains(today)).length;
    final shown=habits.where((h)=>filter=='Archived'?h['archived']==1:h['archived']==0&&(filter=='All'||scheduled(h,now))).toList();
    final monday=shift(now,1-now.weekday+week*7);
    return feed([panel(c,[heading('Daily progress',action:link('New habit',()=>edit(c,'Habit'))),note(planned.isEmpty?'Nothing scheduled today.':'$done of ${planned.length} complete · ${(done*100/planned.length).round()}%'),meter(planned.isEmpty?0:done/planned.length)]),
      filters(['Today','All','Archived'],filter,(x)=>setState(()=>filter=x)),
      Row(children:[IconButton(tooltip:'Previous week',onPressed:()=>setState(()=>week--),icon:const Icon(Icons.chevron_left)),Expanded(child:Center(child:Text('Week of ${dayKey(monday)}'))),IconButton(tooltip:'Next week',onPressed:week<0?()=>setState(()=>week++):null,icon:const Icon(Icons.chevron_right))]),
      if(shown.isEmpty)note('No habits in this view.'),
      for(final h in shown)Builder(builder:(ctx){
        final history=logs(s,h),streak=streaks(h,history,now);
        return panel(c,[ListTile(contentPadding:EdgeInsets.zero,leading:badge(h),title:Text(h['name']),subtitle:Text('Current streak ${streak.$1} · Best ${streak.$2}'),onTap:()=>edit(c,'Habit',h),
          trailing:scheduled(h,now)&&h['archived']==0?Checkbox(value:history.contains(today),onChanged:(_)=>guard(c,()=>s.log(h['id'],today))):null),
          Row(children:[for(var i=0;i<7;i++)Expanded(child:Builder(builder:(_){
            final d=shift(monday,i),day=dayKey(d),checked=history.contains(day);
            final active=scheduled(h,d)&&day.compareTo(today)<=0&&h['archived']==0;
            return Semantics(label:'$day ${checked?'complete':'incomplete'}',child:InkWell(onTap:active?()=>guard(c,()=>s.log(h['id'],day)):null,child:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Column(children:[Text(weekdays[i][0]),const SizedBox(height:5),Icon(checked?Icons.check_circle:active?Icons.radio_button_unchecked:Icons.remove,size:18,color:checked?green:Colors.grey)]))));
          }))]),
          Align(alignment:Alignment.centerRight,child:link('History',()=>showModalBottomSheet<void>(context:c,showDragHandle:true,builder:(_)=>SafeArea(child:feed([heading(h['name']),if(history.isEmpty)note('No check-ins recorded.'),for(final d in (history.toList()..sort((a,b)=>b.compareTo(a))))ListTile(leading:const Icon(Icons.check,color:green),title:Text(d))])))))]);
      })]);
  }
}
Widget taskTile(BuildContext c,Store s,RowData task){
  final done=task['completed']!=null,lateTask=task['completed']==null&&(task['day'] as String).compareTo(today)<0;
  return ListTile(contentPadding:EdgeInsets.zero,leading:Checkbox(value:done,onChanged:(_)=>guard(c,()=>s.change('tasks',task['id'],{'completed':done?null:today}))),onTap:()=>edit(c,'Task',task),
    title:Text(task['name'],style:TextStyle(decoration:done?TextDecoration.lineThrough:null,color:done?green:null)),
    subtitle:Text('${lateTask?'Overdue · ':''}${task['day']} · ${task['priority']} · ${task['category']}',style:TextStyle(color:lateTask?red:null)));
}
class TaskPage extends ConsumerStatefulWidget{
  const TaskPage({super.key});
  @override ConsumerState<TaskPage> createState()=>_TaskState();
}
class _TaskState extends ConsumerState<TaskPage>{
  String tab='Today',priority='Any priority';
  @override Widget build(BuildContext c){
    final s=ref.watch(storeProvider);
    final list=s.rows('tasks').where((r){
      if(priority!='Any priority'&&r['priority']!=priority)return false;
      final diff=(r['day'] as String).compareTo(today);
      return switch(tab){'Completed'=>r['completed']!=null,'Today'=>r['completed']==null&&diff<=0,'Upcoming'=>r['completed']==null&&diff>0,_=>true};
    }).toList()..sort((a,b)=>(a['day'] as String).compareTo(b['day']));
    return feed([heading('Your tasks',action:link('New task',()=>edit(c,'Task'))),filters(['Today','Upcoming','Completed','All'],tab,(v)=>setState(()=>tab=v)),
      DropdownButton<String>(value:priority,items:[for(final p in ['Any priority','High','Medium','Low'])DropdownMenuItem(value:p,child:Text(p))],onChanged:(v)=>setState(()=>priority=v!)),
      panel(c,[if(list.isEmpty)note('No tasks in this view.'),for(final t in list)taskTile(c,s,t)])]);
  }
}
Widget goalTile(BuildContext c,Store s,RowData g){
  final loss=g['category']=='Weight loss';
  final progress=loss?(g['baseline']-g['current'])/(g['baseline']-g['target']):(g['current'] as int)/(g['target'] as int);
  final hidden=g['category']=='Financial'&&s.pref('hidden','0')=='1';
  final remaining=loss?((g['current'] as int)-(g['target'] as int)).clamp(0,1<<52).toInt():((g['target'] as int)-(g['current'] as int)).clamp(0,g['target'] as int).toInt();
  return InkWell(onTap:()=>edit(c,'Goal',g),child:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    ListTile(contentPadding:EdgeInsets.zero,leading:badge(g),title:Text(g['name']),subtitle:Text('${g['category']} · Due ${g['day']}'),trailing:Text('${(progress*100).round()}%')),
    meter(progress),Text(hidden?'Balances hidden':'${decimal(g['current'])} / ${decimal(g['target'])} ${g['unit']} · ${decimal(remaining)} remaining')])));
}
class GoalPage extends ConsumerWidget{
  const GoalPage({super.key});
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider);
    return Scaffold(appBar:AppBar(title:const Text('Goals'),actions:[IconButton(tooltip:'New goal',onPressed:()=>edit(c,'Goal'),icon:const Icon(Icons.add))]),
      body:SafeArea(child:feed([if(s.rows('goals').isEmpty)panel(c,[note('Set a target to track your progress.'),link('Create goal',()=>edit(c,'Goal'))]),
        for(final g in s.rows('goals'))panel(c,[goalTile(c,s,g),Align(alignment:Alignment.centerRight,child:link('Update progress',()async {
          final value=await prompt(c,'Current progress (${g['unit']})',initial:decimal(g['current']));if(value==null||!c.mounted)return;
          final n=minor(value);if(n==null||n<0){message(c,'Enter a non-negative number with up to two decimals');return;}
          await guard(c,()=>s.change('goals',g['id'],{'current':n}));
        }))]) ])));
  }
}
