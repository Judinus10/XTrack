part of '../main.dart';
class Editor extends ConsumerStatefulWidget{
  const Editor({super.key,required this.kind,this.row});
  final String kind;
  final RowData? row;
  @override ConsumerState<Editor> createState()=>_EditorState();
}
class _EditorState extends ConsumerState<Editor>{
  final form=GlobalKey<FormState>();
  final fields=<String,TextEditingController>{};
  late final RowData v;
  int? minute;
  bool busy=false;
  String get kind=>widget.kind;
  bool get tx=>['Income','Expense','Transfer'].contains(kind);
  String get table=>tx?'transactions':{'Account':'accounts','Task':'tasks','Habit':'habits','Goal':'goals'}[kind]!;
  @override void initState(){
    super.initState();
    final s=ref.read(storeProvider);
    v={ 'day':today,'type':'Cash','start':today,'days':127,'priority':'Medium','icon':'Leaf','color':'Green',
      'category':kind=='Goal'?'Personal':kind=='Task'?'Personal':null,...?widget.row};
    for(final key in ['name','description','amount','opening','unit','current','target','expected','bank','taskCategory']){
      final raw=key=='taskCategory'?v['category']:v[key];
      final initial=['amount','opening','current','target','expected'].contains(key)?
        raw!=null?decimal(raw as int):['opening','current'].contains(key)?'0':'':raw?.toString()??'';
      fields[key]=TextEditingController(text:initial);
    }
    if(kind=='Expense' && widget.row==null)v['minute']=DateTime.now().hour*60+DateTime.now().minute;
    if(kind=='Account'&&widget.row==null)v['icon']='Wallet';
    if(kind=='Goal'&&widget.row==null)v['icon']='Flag';
    if(widget.row!=null && (kind=='Habit'||kind=='Task')){
      minute=s.rows('reminders').where((r)=>r[kind.toLowerCase()]==widget.row!['id']).firstOrNull?['minute'];
    }
  }
  @override void dispose(){for(final f in fields.values){f.dispose();}super.dispose();}
  Widget field(String key,String title,{bool required=true,bool numeric=false,bool negative=false}){
    return TextFormField(controller:fields[key],maxLength:numeric?17: key=='description'?500:80,
      keyboardType:numeric?TextInputType.numberWithOptions(decimal:true,signed:negative):TextInputType.text,
      decoration:InputDecoration(labelText:title,counterText:''),
      validator:(raw){final text=raw?.trim()??'';if(required&&text.isEmpty)return 'Enter $title';
        if(numeric){final n=minor(text);if(n==null)return 'Use up to 12 digits and two decimal places';
          if(!negative && (n<0 || (['amount','target'].contains(key)&&n==0)))return 'Enter a valid positive value';}return null;});
  }
  Widget pick(String key,String title,List<String> values)=>DropdownButtonFormField<String>(
    value:v[key],decoration:InputDecoration(labelText:title),items:[for(final x in values) DropdownMenuItem(value:x,child:Text(x))],onChanged:(x)=>setState(()=>v[key]=x));
  Widget recordPick(String key,String title,List<RowData> records){
    final current=v[key];if(!records.any((r)=>r['id']==current))v[key]=records.firstOrNull?['id'];
    return DropdownButtonFormField<int>(value:v[key],isExpanded:true,decoration:InputDecoration(labelText:title),
      items:[for(final row in records)DropdownMenuItem<int>(value:row['id'],child:Text(row['name']))],
      validator:(x)=>x==null?'Choose $title':null,onChanged:(x)=>setState(()=>v[key]=x));
  }
  Future<void> date() async {
    final d=await showDatePicker(context:context,initialDate:DateTime.parse(v['day']),firstDate:DateTime(1900),lastDate:tx?DateTime.now():DateTime(2200));
    if(d!=null)setState(()=>v['day']=dayKey(d));
  }
  Future<void> save() async {
    if(busy||!form.currentState!.validate())return;
    if(kind=='Habit'&&v['days']==0){message(context,'Choose at least one scheduled day');return;}
    setState(()=>busy=true);
    await guard(context,() async {
      final s=ref.read(storeProvider);
      String f(String k)=>fields[k]!.text.trim();
      final look={'icon':v['icon'],'color':v['color']};
      final RowData record;
      if(tx){
        record={'kind':kind,'minute':kind=='Expense'?v['minute']:null,'amount':minor(f('amount')),'day':v['day'],'account':v['account'],'category':kind=='Transfer'?null:v['category'],'destination':kind=='Transfer'?v['destination']:null,'description':f('description')};
      }else if(kind=='Account'){
        record={'name':f('name'),'type':v['type'],'bank':f('bank'),'expected':minor(f('expected')),'started':v['started']??today,'maturityMinute':v['maturityMinute']??540,'maturity':v['type']=='Fixed deposit'?(v['maturity']??today):null,'opening':minor(f('opening')),...look};
      }else if(kind=='Habit'){
        record={'name':f('name'),'start':v['start'],'days':v['days'],...look};
      }else if(kind=='Task'){
        record={'name':f('name'),'day':v['day'],'priority':v['priority'],'category':f('taskCategory'),'description':f('description')};
      }else{
        record={'name':f('name'),'category':v['category'],'baseline':v['category']=='Weight loss'?(widget.row?['baseline']==null||widget.row?['baseline']==0?minor(f('current')):widget.row!['baseline']):0,'unit':v['category']=='Weight loss'?'kg':f('unit'),'day':v['day'],'target':minor(f('target')),'current':minor(f('current')),...look};
      }
      if(record['category']=='Weight loss' && record['baseline']<=record['target'])throw StateError('Target must be below starting weight');
      await s.save(table,record,id:widget.row?['id'],minute:minute);
      if(mounted) Navigator.pop(context);
    });
    if(mounted)setState(()=>busy=false);
  }
  Future<void> action(bool archive) async {
    final row=widget.row!;
    final verb=archive?(row['archived']==1?'Unarchive':'Archive'):'Delete';
    if(!await confirm(context,'$verb $kind?',archive?'Existing history is kept.':'This record will be permanently deleted.'))return;
    if(!mounted)return;
    await guard(context,() async {
      final s=ref.read(storeProvider);
      if(archive){await s.change(table,row['id'],{'archived':row['archived']==1?0:1});}else{await s.remove(table,row['id']);}
      if(mounted)Navigator.pop(context);
    });
  }
  @override Widget build(BuildContext c){
    final s=ref.watch(storeProvider);
    final accounts=s.rows('accounts').where((r)=>r['demo']==(widget.row?['demo']??0) && (r['archived']==0||r['id']==widget.row?['account']||r['id']==widget.row?['destination'])).toList();
    final widgets=<Widget>[
      if(!tx) field('name',kind=='Task'?'Title':'Name'),
      if(tx)...[
        if(kind=='Expense')ListTile(title:const Text('Expense time'),subtitle:Text(clock(c,v['minute'])),onTap:()async{final t=await showTimePicker(context:c,initialTime:TimeOfDay.now());if(t!=null)setState(()=>v['minute']=t.hour*60+t.minute);}),
        field('amount','Amount (${s.pref('currency','LKR')})',numeric:true),
        recordPick('account','Account',accounts),
        if(kind=='Transfer')recordPick('destination','Destination account',accounts.where((r)=>r['id']!=v['account']).toList()),
        if(accounts.length<(kind=='Transfer'?2:1))link('Create account',()=>edit(c,'Account')),
        if(kind!='Transfer')...[
          recordPick('category','Category',s.rows('categories').where((r)=>r['kind']==kind).toList()),
          link('Add custom category',() async {
            final name=await prompt(c,'Category name');if(name==null||!c.mounted)return;
            if(name.isEmpty||name.length>80){message(c,'Enter 1–80 characters');return;}
            await guard(c,() async {await s.save('categories',{'name':name,'kind':kind});if(mounted)setState(()=>v['category']=s.rows('categories').firstWhere((r)=>r['name']==name&&r['kind']==kind)['id']);});
          })],
        field('description','Description (optional)',required:false)],
      if(kind=='Account')...[pick('type','Account type',['Cash','Bank account','Savings account','Digital wallet','Fixed deposit']),field('opening','Opening balance',numeric:true,negative:true)],
      if(kind=='Account'&&v['type']=='Fixed deposit')...[
        field('bank','Bank name'),field('expected','Expected payout',numeric:true),
        ListTile(title:Text('Start date · ${v['started']??today}'),onTap:()async{final d=await showDatePicker(context:c,initialDate:DateTime.parse(v['started']??today),firstDate:DateTime(1900),lastDate:DateTime.now());if(d!=null)setState(()=>v['started']=dayKey(d));}),
        ListTile(title:Text('Reminder · ${clock(c,v['maturityMinute']??540)}'),onTap:()async{final t=await showTimePicker(context:c,initialTime:const TimeOfDay(hour:9,minute:0));if(t!=null)setState(()=>v['maturityMinute']=t.hour*60+t.minute);}),
      ],if(kind=='Account'&&v['type']=='Fixed deposit')ListTile(title:const Text('Maturity date'),subtitle:Text(v['maturity']??today),onTap:()async{final d=await showDatePicker(context:c,initialDate:DateTime.parse(v['maturity']??today),firstDate:DateTime(1900),lastDate:DateTime(2200));if(d!=null)setState(()=>v['maturity']=dayKey(d));}),
      if(kind=='Task')...[field('description','Description (optional)',required:false),field('taskCategory','Category'),pick('priority','Priority',['Low','Medium','High'])],
      if(kind=='Goal')...[pick('category','Category',['Financial','Personal','Learning','Fitness','Weight loss','Custom']),if(v['category']!='Weight loss')field('unit','Unit (e.g. LKR, hours)'),note('A unit describes what you measure: kg, hours, books or LKR.'),field('target','Target',numeric:true),field('current','Current progress',numeric:true)],
      if(tx||kind=='Goal'||kind=='Task')ListTile(title:Text(kind=='Goal'?'Deadline':tx?'Date':'Due date'),subtitle:Text(v['day']),trailing:const Icon(Icons.calendar_today_outlined),onTap:date),
      if(kind=='Habit')...[heading('Scheduled days'),Wrap(spacing:6,children:[for(var i=0;i<7;i++)FilterChip(label:Text(weekdays[i]),selected:((v['days'] as int)&(1<<i))!=0,onSelected:(_)=>setState(()=>v['days']=(v['days'] as int)^(1<<i)))])],
      if(kind=='Habit'||kind=='Task') ListTile(title:const Text('Reminder'),subtitle:Text(minute==null?'Off':TimeOfDay(hour:minute!~/60,minute:minute!%60).format(c)),trailing:minute==null?const Icon(Icons.alarm_add):IconButton(tooltip:'Remove reminder',icon:const Icon(Icons.clear),onPressed:()=>setState(()=>minute=null)),
        onTap:() async {final t=await showTimePicker(context:c,initialTime:minute==null?const TimeOfDay(hour:9,minute:0):TimeOfDay(hour:minute!~/60,minute:minute!%60));if(t!=null&&mounted)setState(()=>minute=t.hour*60+t.minute);}),
      if(!tx&&kind!='Task')...[pick('icon','Icon',icons.keys.toList()),pick('color','Color',colors.keys.toList())],
      FilledButton(onPressed:busy?null:save,child:Text(widget.row==null?'Create $kind':'Save changes')),
      if(widget.row!=null && ['Account','Habit'].contains(kind))OutlinedButton(onPressed:busy?null:()=>action(true),child:Text(widget.row!['archived']==1?'Unarchive':'Archive')),
      if(widget.row!=null && kind!='Account')TextButton(onPressed:busy?null:()=>action(false),child:const Text('Delete record',style:TextStyle(color:red)))];
    return Scaffold(appBar:AppBar(title:Text('${widget.row==null?'New':'Edit'} $kind')),body:SafeArea(child:Form(key:form,child:feed([for(final w in widgets)Padding(padding:const EdgeInsets.only(bottom:14),child:w)]))));
  }
}
