part of '../main.dart';

Future<void> createWorkoutTemplate(BuildContext c,Store s)async{
  final name=await prompt(c,'Workout name');
  if(name==null||name.trim().isEmpty||!c.mounted)return;
  await s.save('workout_templates',{'name':name.trim(),'created':DateTime.now().millisecondsSinceEpoch});
}

Future<void> createExercise(BuildContext c,Store s)async{
  final name=await prompt(c,'Exercise name');
  if(name==null||name.trim().isEmpty||!c.mounted)return;
  if(s.rows('exercise_catalog').any((e)=>(e['name'] as String).trim().toLowerCase()==name.trim().toLowerCase())){message(c,'That exercise is already in your library.');return;}
  final equipment=await prompt(c,'Equipment (optional)');
  if(equipment==null||!c.mounted)return;
  final unit=await choose(c,'Weight unit',['kg','lb','bodyweight']);
  if(unit==null)return;
  await s.save('exercise_catalog',{'name':name.trim(),'equipment':equipment.trim(),'unit':unit,'archived':0});
}

Future<void> addTemplateExercise(BuildContext c,Store s,RowData template)async{
  final available=s.rows('exercise_catalog').where((e)=>e['archived']==0).toList();
  if(available.isEmpty){
    if(await confirm(c,'Create an exercise first?','Add each exercise to your library once, then reuse it in workouts.')&&c.mounted)await createExercise(c,s);
    return;
  }
  final choices=available.map((e)=>'${e['name']} · ${e['equipment'].toString().isEmpty?e['unit']:'${e['equipment']} · ${e['unit']}'}').toList();
  final selected=await choose(c,'Choose an exercise',choices);
  if(selected==null||!c.mounted)return;
  final exercise=available[choices.indexOf(selected)];
  if(s.rows('template_exercises').any((r)=>r['template']==template['id']&&r['exercise']==exercise['id'])){message(c,'That exercise is already in this workout.');return;}
  final position=s.rows('template_exercises').where((r)=>r['template']==template['id']).length;
  await s.save('template_exercises',{'template':template['id'],'exercise':exercise['id'],'position':position,'target_sets':3,'target_reps':10});
}
Future<void> editTemplatePlan(BuildContext c,Store s,RowData plan)async{
  final sets=await prompt(c,'Planned sets',initial:'${plan['target_sets']}');if(sets==null)return;
  final reps=await prompt(c,'Target reps per set',initial:'${plan['target_reps']}');if(reps==null)return;
  final setCount=int.tryParse(sets),repCount=int.tryParse(reps);
  if(setCount==null||repCount==null||setCount<1||setCount>20||repCount<1||repCount>100)throw StateError('Use 1–20 sets and 1–100 reps.');
  await s.change('template_exercises',plan['id'],{'target_sets':setCount,'target_reps':repCount});
}

Future<void> startWorkout(BuildContext c,Store s,RowData template)async{
  final planned=s.rows('template_exercises').where((r)=>r['template']==template['id']).toList()..sort((a,b)=>(a['position'] as int).compareTo(b['position'] as int));
  if(planned.isEmpty){message(c,'Add exercises to this workout first.');return;}
  final started=DateTime.now().millisecondsSinceEpoch;
  await s.save('workout_sessions',{'template':template['id'],'name':template['name'],'day':today,'started':started,'ended':null,'notes':''});
  final session=s.rows('workout_sessions').firstWhere((r)=>r['started']==started&&r['template']==template['id']);
  for(final plan in planned){
    final exercise=plan['exercise'] as int;
    await s.save('workout_session_exercises',{'session':session['id'],'exercise':exercise,'position':plan['position']});
    final previousSessions=s.rows('workout_session_exercises').where((r)=>r['exercise']==exercise&&r['session']!=session['id']).map((r)=>r['session'] as int).toSet();
    final history=s.rows('workout_sessions').where((r)=>previousSessions.contains(r['id'])&&r['ended']!=null).toList()..sort((a,b)=>(b['started'] as int).compareTo(a['started'] as int));
    final oldSets=history.isEmpty?const <RowData>[]:(s.rows('workout_sets').where((r)=>r['session']==history.first['id']&&r['exercise']==exercise).toList()..sort((a,b)=>(a['set_no'] as int).compareTo(b['set_no'] as int)));
    final count=oldSets.isEmpty?plan['target_sets'] as int:oldSets.length;
    for(var i=0;i<count;i++){
      final old=i<oldSets.length?oldSets[i]:null;
      await s.save('workout_sets',{'session':session['id'],'exercise':exercise,'set_no':i+1,'reps':old?['reps']??plan['target_reps'],'load':old?['load']??0});
    }
  }
  if(c.mounted)await open<void>(c,WorkoutSessionPage(session['id']));
}

class WorkoutHub extends ConsumerWidget{
  const WorkoutHub({super.key});
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider),templates=s.rows('workout_templates'),sessions=[...s.rows('workout_sessions')]..sort((a,b)=>(b['started'] as int).compareTo(a['started'] as int));
    return Scaffold(appBar:AppBar(title:const Text('Workouts'),actions:[IconButton(tooltip:'Exercise library',onPressed:()=>open(c,const ExerciseLibrary()),icon:const Icon(Icons.fitness_center))]),body:SafeArea(child:feed([
      panel(c,[heading('Your routines',action:FilledButton.icon(onPressed:()=>createWorkoutTemplate(c,s),icon:const Icon(Icons.add),label:const Text('New routine'))),if(templates.isEmpty)note('Create a routine once. Your last sets and weights will be ready next time.'),
        for(final t in templates)Builder(builder:(_){final exercises=s.rows('template_exercises').where((r)=>r['template']==t['id']).length;final active=s.rows('workout_sessions').where((r)=>r['template']==t['id']&&r['ended']==null).firstOrNull;return ListTile(contentPadding:EdgeInsets.zero,title:Text(t['name']),subtitle:Text('$exercises ${exercises==1?'exercise':'exercises'}'),onTap:()=>open(c,WorkoutTemplatePage(t)),trailing:FilledButton.tonal(onPressed:active!=null?()=>open(c,WorkoutSessionPage(active['id'])):exercises==0?()=>open(c,WorkoutTemplatePage(t)):()=>startWorkout(c,s,t),child:Text(active!=null?'Resume':exercises==0?'Set up':'Start')));})]),
      panel(c,[heading('Recent sessions'),if(sessions.isEmpty)note('Completed workouts will appear here.'),for(final session in sessions.take(10))ListTile(title:Text(session['name']),subtitle:Text('${session['day']} · ${session['ended']==null?'In progress':'Completed'}'),trailing:const Icon(Icons.chevron_right),onTap:()=>open(c,WorkoutSessionPage(session['id'])))])
    ])));
  }
}

class ExerciseLibrary extends ConsumerWidget{
  const ExerciseLibrary({super.key});
  @override Widget build(BuildContext c,WidgetRef ref){final s=ref.watch(storeProvider),exercises=s.rows('exercise_catalog').where((e)=>e['archived']==0).toList()..sort((a,b)=>(a['name'] as String).compareTo(b['name'] as String));return screen('Exercise library',feed([
    FilledButton.icon(onPressed:()=>createExercise(c,s),icon:const Icon(Icons.add),label:const Text('Add exercise')),
    if(exercises.isEmpty)note('Add an exercise once. You can reuse it across routines.'),
    for(final e in exercises)ListTile(leading:const Icon(Icons.fitness_center),title:Text(e['name']),subtitle:Text('${e['equipment'].isEmpty?'Exercise':e['equipment']} · ${e['unit']}'),trailing:const Icon(Icons.show_chart),onTap:()=>open(c,ExerciseProgress(e)))
  ]));}
}

class WorkoutTemplatePage extends ConsumerWidget{
  const WorkoutTemplatePage(this.template,{super.key});final RowData template;
  @override Widget build(BuildContext c,WidgetRef ref){final s=ref.watch(storeProvider),items=s.rows('template_exercises').where((r)=>r['template']==template['id']).toList()..sort((a,b)=>(a['position'] as int).compareTo(b['position'] as int));final active=s.rows('workout_sessions').where((r)=>r['template']==template['id']&&r['ended']==null).firstOrNull;return screen(template['name'],feed([
    panel(c,[note('Your previous sets and loads are copied into each new session. Change only what is different today.'),FilledButton.icon(onPressed:active==null?()=>startWorkout(c,s,template):()=>open(c,WorkoutSessionPage(active['id'])),icon:Icon(active==null?Icons.play_arrow:Icons.play_circle_outline),label:Text(active==null?'Start workout':'Resume workout'))]),
    panel(c,[heading('Exercises',action:ActionChip(label:const Text('Add exercise'),onPressed:()=>addTemplateExercise(c,s,template))),if(items.isEmpty)note('Add exercises to this routine.'),for(final item in items)Builder(builder:(_){final e=s.rows('exercise_catalog').where((r)=>r['id']==item['exercise']).firstOrNull;return e==null?const SizedBox.shrink():ListTile(title:Text(e['name']),subtitle:Text('${item['target_sets']} sets · ${item['target_reps']} reps · ${e['unit']}'),trailing:PopupMenuButton<String>(tooltip:'Exercise options',onSelected:(v)=>v=='Plan'?editTemplatePlan(c,s,item):guard(c,()=>s.remove('template_exercises',item['id'])),itemBuilder:(_)=>[const PopupMenuItem(value:'Plan',child:Text('Edit sets and reps')),const PopupMenuItem(value:'Remove',child:Text('Remove exercise'))]));})])
  ]));}
}

class WorkoutSessionPage extends ConsumerStatefulWidget{
  const WorkoutSessionPage(this.sessionId,{super.key});final int sessionId;
  @override ConsumerState<WorkoutSessionPage> createState()=>_WorkoutSessionState();
}
class _WorkoutSessionState extends ConsumerState<WorkoutSessionPage>{
  final reps=<int,TextEditingController>{},loads=<int,TextEditingController>{};bool busy=false;
  @override void dispose(){for(final c in reps.values)c.dispose();for(final c in loads.values)c.dispose();super.dispose();}
  void hydrate(Iterable<RowData> rows){for(final r in rows){final id=r['id'] as int;reps.putIfAbsent(id,()=>TextEditingController(text:'${r['reps']}'));loads.putIfAbsent(id,()=>TextEditingController(text:decimal(r['load'])));}}
  Future<void> addSet(Store s,int session,int exercise,List<RowData> existing)async{
    final last=existing.isEmpty?null:existing.last;
    final no=existing.isEmpty?1:(existing.map((r)=>r['set_no'] as int).reduce((a,b)=>a>b?a:b)+1);
    await s.save('workout_sets',{'session':session,'exercise':exercise,'set_no':no,'reps':last?['reps']??10,'load':last?['load']??0});
  }
  Future<bool> saveSets(Store s,List<RowData> all)async{
    for(final row in all){final id=row['id'] as int;final r=int.tryParse(reps[id]?.text??'');final load=minor(loads[id]?.text??'');if(r==null||r<1||load==null||load<0){message(context,'Enter a valid positive rep count and a non-negative load for each set.');return false;}}
    setState(()=>busy=true);
    for(final row in all){final id=row['id'] as int;await s.change('workout_sets',id,{'reps':int.parse(reps[id]!.text),'load':minor(loads[id]!.text)!});}
    if(mounted)setState(()=>busy=false);return true;
  }
  @override Widget build(BuildContext c){
    final s=ref.watch(storeProvider),session=s.rows('workout_sessions').where((r)=>r['id']==widget.sessionId).firstOrNull;
    if(session==null)return screen('Workout',feed([note('This session is no longer available.')]));
    final finished=session['ended']!=null,sessionExercises=s.rows('workout_session_exercises').where((r)=>r['session']==widget.sessionId).toList()..sort((a,b)=>(a['position'] as int).compareTo(b['position'] as int));
    final all=s.rows('workout_sets').where((r)=>r['session']==widget.sessionId).toList();hydrate(all);
    Future<void> saveProgress()async{if(await saveSets(s,all)&&mounted)message(c,'Workout progress saved.');}
    Future<void> finish()async{if(!await saveSets(s,all)||!mounted)return;await s.change('workout_sessions',widget.sessionId,{'ended':DateTime.now().millisecondsSinceEpoch});if(mounted)Navigator.pop(c);}
    return Scaffold(appBar:AppBar(title:Text('${session['name']} · ${session['day']}')),body:SafeArea(child:feed([
      if(!finished)note('Last session values are prefilled. Adjust today’s sets as you go.'),
      for(final se in sessionExercises)Builder(builder:(_){
        final ex=s.rows('exercise_catalog').where((e)=>e['id']==se['exercise']).firstOrNull;if(ex==null)return const SizedBox.shrink();
        final sets=all.where((r)=>r['exercise']==ex['id']).toList()..sort((a,b)=>(a['set_no'] as int).compareTo(b['set_no'] as int));
        return panel(c,[heading(ex['name'],action:IconButton(tooltip:'View progress',onPressed:()=>open(c,ExerciseProgress(ex)),icon:const Icon(Icons.show_chart))),if(ex['equipment'].isNotEmpty)note('${ex['equipment']} · ${ex['unit']}'),
          for(final set in sets)Row(children:[SizedBox(width:42,child:Text('Set ${set['set_no']}')),Expanded(child:TextField(controller:reps[set['id']],readOnly:finished,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Reps'))),const SizedBox(width:10),Expanded(child:TextField(controller:loads[set['id']],readOnly:finished,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'Load (${ex['unit']})')))]),
          if(!finished)Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:()=>addSet(s,widget.sessionId,ex['id'],sets),icon:const Icon(Icons.add),label:const Text('Add set')))
        ]);
      })
    ]))),bottomNavigationBar:finished?null:SafeArea(top:false,child:Padding(padding:const EdgeInsets.fromLTRB(16,8,16,12),child:Row(children:[Expanded(child:OutlinedButton(onPressed:busy?null:saveProgress,child:const Text('Save progress'))),const SizedBox(width:10),Expanded(child:FilledButton.icon(onPressed:busy?null:finish,icon:const Icon(Icons.check),label:const Text('Finish')))])));
  }
}

class ExerciseProgress extends ConsumerWidget{
  const ExerciseProgress(this.exercise,{super.key});final RowData exercise;
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider),sessionIds=s.rows('workout_session_exercises').where((r)=>r['exercise']==exercise['id']).map((r)=>r['session'] as int).toSet();
    final sessions=s.rows('workout_sessions').where((r)=>sessionIds.contains(r['id'])&&r['ended']!=null).toList()..sort((a,b)=>(a['started'] as int).compareTo(b['started'] as int));
    final labels=<String>[],values=<double>[],chartSessions=<RowData>[];
    for(final session in sessions){final sets=s.rows('workout_sets').where((r)=>r['session']==session['id']&&r['exercise']==exercise['id']).toList();if(sets.isEmpty)continue;final top=sets.map((r)=>r['load'] as int).reduce((a,b)=>a>b?a:b);chartSessions.add(session);labels.add(session['day'].substring(5));values.add(top/100);}
    final spots=[for(var i=0;i<values.length;i++)FlSpot(i.toDouble(),values[i])];
    return screen('${exercise['name']} progress',feed([
      panel(c,[heading('Top set · ${exercise['unit']}'),if(spots.isEmpty)note('Finish a workout with this exercise to start the chart.'),if(spots.isNotEmpty)SizedBox(height:220,child:LineChart(LineChartData(minX:0,maxX:(spots.length-1).clamp(1,1<<20).toDouble(),titlesData:axis(labels),gridData:const FlGridData(show:false),borderData:FlBorderData(show:false),lineBarsData:[LineChartBarData(spots:spots,color:green,barWidth:3,dotData:const FlDotData(show:true))])))]),
      panel(c,[heading('Session history'),for(var i=chartSessions.length-1;i>=0;i--)ListTile(title:Text(chartSessions[i]['day']),trailing:Text('${values[i].toStringAsFixed(1)} ${exercise['unit']}'))])
    ]));
  }
}
