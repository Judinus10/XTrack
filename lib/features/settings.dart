part of '../main.dart';
class LockPage extends StatefulWidget{
  const LockPage({super.key,required this.onUnlock});
  final VoidCallback onUnlock;
  @override State<LockPage> createState()=>_LockState();
}
class _LockState extends State<LockPage>{
  final pin=TextEditingController();
  bool busy=false;
  String error='';
  @override void dispose(){pin.dispose();super.dispose();}
  Future<void> unlock(bool bio) async {
    if(busy)return;
    setState(()=>busy=true);
    try{
      final passed=bio?await Vault.biometric():await Vault.check(pin.text);
      if(!mounted)return;
      if(passed){
        if(!await Vault.patternEnabled() && mounted){
          final next=await pattern(context,'Create your unlock pattern');
          if(next==null||!mounted||await pattern(context,'Confirm pattern')!=next)return;
          await Vault.setPin(next);
        }
        widget.onUnlock();
      }else{pin.clear();setState(()=>error='Authentication failed');}
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext c)=>PopScope(canPop:false,child:Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(26),child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Icon(Icons.lock_outline,size:42,color:green),const SizedBox(height:18),Text('Unlock XTrack',style:Theme.of(c).textTheme.headlineSmall),const SizedBox(height:18),
    FutureBuilder<bool>(future:Vault.patternEnabled(),builder:(c,state){
      if(!state.hasData)return const CircularProgressIndicator();
      if(state.data!)return PatternPad((value){pin.text=value;unlock(false);});
      return TextField(controller:pin,keyboardType:TextInputType.number,obscureText:true,maxLength:6,decoration:const InputDecoration(labelText:'Existing PIN'),onSubmitted:(_)=>unlock(false));
    }),Text(error),
    Consumer(builder:(c,ref,_)=>ref.watch(storeProvider).bio?TextButton.icon(onPressed:busy?null:()=>unlock(true),icon:const Icon(Icons.fingerprint),label:const Text('Use biometrics')):const SizedBox())]))))));
}
Future<void> remindersEnabled(BuildContext c,Store s,bool value)=>guard(c,()async {
  if(value && !await s.alarms.permission())throw StateError('Notifications are disabled in Android settings.');
  await s.setting('notifications',value?'1':'0');
});
class ReminderPage extends ConsumerWidget{
  const ReminderPage({super.key});
  @override Widget build(BuildContext c,WidgetRef ref){
    final s=ref.watch(storeProvider),items=s.rows('reminders');
    return Scaffold(appBar:AppBar(title:const Text('Reminders')),body:SafeArea(child:feed([
      SwitchListTile(title:const Text('Local reminders'),value:s.pref('notifications','0')=='1',onChanged:(v)=>remindersEnabled(c,s,v)),
      link('Add custom reminder',()=>customReminder(c,s)),for(final r in s.rows('custom_reminders'))ListTile(title:Text(r['name']),subtitle:Text('${r['day']} · ${clock(c,r['minute'])}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>guard(c,()=>s.remove('custom_reminders',r['id'])))),if(s.reminderError!=null)note(s.reminderError!),if(items.isEmpty)note('Choose a reminder time when editing a task or habit.'),
      for(final r in items)Builder(builder:(_){
        final habit=r['habit']!=null,kind=habit?'Habit':'Task';
        final row=s.rows(habit?'habits':'tasks').firstWhere((v)=>v['id']==(r['habit']??r['task']));
        final time=TimeOfDay(hour:(r['minute'] as int)~/60,minute:(r['minute'] as int)%60);
        return ListTile(title:Text(row['name']),subtitle:Text('$kind · ${time.format(c)}${row['archived']==1||row['completed']!=null?' · inactive':''}'),onTap:()=>edit(c,kind,row));
      })])));
  }
}
class SettingsPage extends ConsumerStatefulWidget{
  const SettingsPage({super.key});
  @override ConsumerState<SettingsPage> createState()=>_SettingsState();
}
class _SettingsState extends ConsumerState<SettingsPage>{
  bool busy=false;
  Future<void> run(Future<void> Function() work)async{
    if(busy)return;setState(()=>busy=true);
    await guard(context,work);if(mounted)setState(()=>busy=false);
  }
  Future<bool> verify(Store s)async{
    if(!s.hasPin)return true;
    final value=await Vault.patternEnabled()?await pattern(context,'Verify pattern'):await prompt(context,'Enter existing PIN',secret:true);
    if(value==null)return false;
    if(!await Vault.check(value))throw StateError('Incorrect PIN');
    return true;
  }
  Future<void> pin(Store s,bool enable)async{
    if(!await verify(s)||!mounted)return;
    if(enable){
      final value=await pattern(context,'Create pattern');
      if(value==null||!mounted)return;
      if(await pattern(context,'Confirm pattern')!=value)throw StateError('Patterns differ');
      await Vault.setPin(value);
    }else{
      await Vault.storage.delete(key:'bio');s.bio=false;
      await Vault.storage.delete(key:'pin');await Vault.storage.delete(key:'attempts');
    }
    s.hasPin=enable;await s.refresh();
  }
  Future<void> backup(Store s,bool restore)async{
    Uint8List? bytes;
    if(restore){
      bytes=await Vault.device.invokeMethod<Uint8List>('open');
      if(bytes==null||!mounted)return;
    }
    final pass=await prompt(context,restore?'Backup passphrase':'Create backup passphrase (10+ characters)',secret:true);
    if(pass==null||!mounted)return;
    if(pass.length<10)throw StateError('Use a passphrase of at least 10 characters.');
    if(restore){
      final decoded=await Vault.unseal(pass,bytes!);
      if(!mounted||!await confirm(context,'Replace current records?','Restore replaces all records and preferences. Your device PIN is kept.'))return;
      await s.restore(decoded);
    }else{
      if(await prompt(context,'Confirm backup passphrase',secret:true)!=pass)throw StateError('Passphrases did not match');
      final encrypted=await Vault.seal(pass,{'version':4,'data':s.data});
      if(encrypted.length>32*1024*1024)throw StateError('Backup exceeds 32 MB');
      if(await Vault.device.invokeMethod<bool>('save',encrypted)!=true)return;
    }
    if(mounted)message(context,restore?'Backup restored':'Encrypted backup saved');
  }
  @override Widget build(BuildContext c){
    final s=ref.watch(storeProvider);
    Widget setting(String title,String key,List<String> options,String fallback)=>ListTile(title:Text(title),trailing:DropdownButton<String>(
      value:s.pref(key,fallback),items:[for(final o in options)DropdownMenuItem(value:o,child:Text(o))],onChanged:(v)=>run(()=>s.setting(key,v!))));
    return Scaffold(appBar:AppBar(title:const Text('Settings')),body:SafeArea(child:AbsorbPointer(absorbing:busy,child:feed([
      if(busy)const LinearProgressIndicator(),
      panel(c,[heading('Appearance'),setting('Theme','theme',['system','light','dark'],'system'),setting('Currency label','currency',['LKR','USD','EUR','GBP','INR'],'LKR'),note('Changing the label keeps the recorded amounts.')]),
      panel(c,[heading('Reminders'),SwitchListTile(title:const Text('Enable reminders'),value:s.pref('notifications','0')=='1',onChanged:(v)=>run(()=>remindersEnabled(c,s,v))),if(s.reminderError!=null)note(s.reminderError!)]),
      panel(c,[heading('Security'),SwitchListTile(title:const Text('Application pattern'),value:s.hasPin,onChanged:(v)=>run(()=>pin(s,v))),
        if(s.hasPin)...[link('Change pattern',()=>run(()=>pin(s,true))),SwitchListTile(title:const Text('Biometric unlock'),value:s.bio,onChanged:(v)=>run(()async {
          if(!await verify(s))return;
          if(v&&!await Vault.biometric())throw StateError('Biometric verification failed');
          await Vault.storage.write(key:'bio',value:v?'1':'0');s.bio=v;await s.refresh();
        }))]]),
      panel(c,[heading('Local data'),ListTile(leading:const Icon(Icons.file_upload_outlined),title:const Text('Export encrypted backup'),onTap:()=>run(()=>backup(s,false))),
        ListTile(leading:const Icon(Icons.file_download_outlined),title:const Text('Restore encrypted backup'),onTap:()=>run(()=>backup(s,true))),
        ListTile(title:const Text('Reset application data',style:TextStyle(color:red)),onTap:()=>run(()async{
          if(!await verify(s)||!c.mounted||!await confirm(c,'Reset XTrack?','Delete all records, preferences, PIN and reminders on this device?'))return;
          await s.reset();for(final k in ['bio','attempts','pin']){await Vault.storage.delete(key:k);}s.hasPin=false;s.bio=false;await s.refresh();
        }))]),
      panel(c,[heading('XTrack'),note('Version 2.0.0 · Offline personal tracker')])] ))));
  }
}
