import 'dart:collection' show IterableExtensions;
import 'dart:async';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'core/metrics.dart';
import 'core/store.dart';
import 'core/vault.dart';
part 'ui/shared.dart';
part 'features/editor.dart';
part 'features/life.dart';
part 'features/personal.dart';
part 'features/dashboard.dart';
part 'features/trackers.dart';
part 'features/analytics.dart';
part 'features/settings.dart';

void main(){WidgetsFlutterBinding.ensureInitialized();runApp(const Bootstrap());}
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override State<Bootstrap> createState()=>_BootstrapState();
}
class _BootstrapState extends State<Bootstrap>{
  final store=Store();
  late Future<void> ready=store.init();
  @override Widget build(BuildContext context)=>FutureBuilder(future:ready,builder:(c,s){
    if(s.connectionState==ConnectionState.done && !s.hasError) return ProviderScope(
      overrides:[storeProvider.overrideWith((_)=>store)],child:const XTrack());
    return MaterialApp(home:Scaffold(body:Center(child:s.hasError?
      Column(mainAxisSize:MainAxisSize.min,children:[const Text('Could not open XTrack'),Text('${s.error}'),TextButton(onPressed:()=>setState(()=>ready=store.init()),child:const Text('Retry'))]):
      const Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.insights,size:52,color:green),Text('XTrack',style:TextStyle(fontSize:28,fontWeight:FontWeight.bold)),SizedBox(height:16),SizedBox(width:96,child:LinearProgressIndicator(color:green))]))));
  });
}
const green=Color(0xff16a34a), accent=Color(0xff22c55e), red=Color(0xffdc4047);
ThemeData appearance(Brightness b){
  final dark=b==Brightness.dark;
  final scheme=ColorScheme.fromSeed(seedColor:green,brightness:b).copyWith(primary:dark?accent:green,surface:dark?const Color(0xff1b1d1c):Colors.white);
  return ThemeData(useMaterial3:true,colorScheme:scheme,scaffoldBackgroundColor:dark?const Color(0xff101010):const Color(0xfff5f7f6),
    appBarTheme:const AppBarTheme(backgroundColor:Colors.transparent,scrolledUnderElevation:0),
    inputDecorationTheme:const InputDecorationTheme(border:OutlineInputBorder(borderRadius:BorderRadius.all(Radius.circular(14)))),
    navigationBarTheme:NavigationBarThemeData(height:68,indicatorColor:green.withAlpha(36)));
}
class XTrack extends ConsumerStatefulWidget{
  const XTrack({super.key});
  @override ConsumerState<XTrack> createState()=>_XTrackState();
}
class _XTrackState extends ConsumerState<XTrack> with WidgetsBindingObserver{
  late bool locked;
  Timer? timer;
  String date=today;
  @override void initState(){super.initState();locked=ref.read(storeProvider).hasPin;WidgetsBinding.instance.addObserver(this);
    timer=Timer.periodic(const Duration(seconds:30),(_){if(date!=today){date=today;ref.read(storeProvider).refresh();}});}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);timer?.cancel();super.dispose();}
  @override void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.paused && ref.read(storeProvider).hasPin) setState(()=>locked=true);
    if(state==AppLifecycleState.resumed){ref.read(storeProvider).resumed(); }
  }
  @override Widget build(BuildContext context){
    final s=ref.watch(storeProvider);
    return MaterialApp(title:'XTrack',debugShowCheckedModeBanner:false,theme:appearance(Brightness.light),darkTheme:appearance(Brightness.dark),
      themeMode:ThemeMode.values.byName(s.pref('theme','system')),home:const Shell(),
      builder:(context,child)=>Stack(children:[Offstage(offstage:locked,child:ExcludeFocus(excluding:locked,child:child!)),
        if(locked) Positioned.fill(child:HeroControllerScope.none(child:Navigator(onGenerateRoute:(_)=>MaterialPageRoute(builder:(_)=>LockPage(onUnlock:()=>setState(()=>locked=false))))))]));
  }
}
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override State<Shell> createState()=>_ShellState();
}
class _ShellState extends State<Shell>{
  int index=0;
  static const titles=['Home','Finance','Planner','Personal','More'];
  static const symbols=[Icons.home_outlined,Icons.account_balance_wallet_outlined,Icons.calendar_month_outlined,Icons.person_outline,Icons.more_horiz];
  DateTime selected=DateTime.now();
  @override Widget build(BuildContext c)=>Scaffold(
    appBar:AppBar(title:Text(index==0?'XTrack':titles[index],style:const TextStyle(fontWeight:FontWeight.w800)),actions:[
      IconButton(tooltip:'Search',onPressed:()=>open(c,const SearchRecords()),icon:const Icon(Icons.search)),
      IconButton(tooltip:'Reminders',onPressed:()=>open(c,const ReminderPage()),icon:const Icon(Icons.notifications_none))]),
    body:SafeArea(child:IndexedStack(index:index,children:[const Dashboard(),const Finance(),Planner(selected,(d)=>setState(()=>selected=d)),const LifeHub(),const MoreHub()])),
    floatingActionButton:index==4?null:FloatingActionButton.small(tooltip:'Quick Add',onPressed:()=>addMenu(c,index,selected),child:const Icon(Icons.add)),
    bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(i)=>setState(()=>index=i),destinations:[
      for(var i=0;i<titles.length;i++)NavigationDestination(icon:Icon(symbols[i]),label:titles[i])]));
}
