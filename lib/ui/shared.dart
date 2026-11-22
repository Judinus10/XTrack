part of '../main.dart';
const icons={'Wallet':Icons.account_balance_wallet_outlined,'Bank':Icons.account_balance_outlined,'Book':Icons.menu_book_outlined,'Fitness':Icons.directions_run,'Flag':Icons.flag_outlined,'Leaf':Icons.eco_outlined,'Star':Icons.star_outline};
const colors={'Green':green,'Blue':Color(0xff327ac2),'Amber':Color(0xffb47e13),'Purple':Color(0xff9261bd)};
const weekdays=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
const months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
Future<T?> open<T>(BuildContext c,Widget page)=>Navigator.push<T>(c,MaterialPageRoute(builder:(_)=>page));
void edit(BuildContext c,String kind,[RowData? row])=>open(c,Editor(kind:kind,row:row));
void message(BuildContext c,Object text){if(c.mounted) ScaffoldMessenger.of(c)..hideCurrentSnackBar()..showSnackBar(SnackBar(content:Text(text.toString())));}
Future<void> guard(BuildContext c,Future<void> Function() action) async {try{await action();}catch(e){if(c.mounted)message(c,e);}}
Future<bool> confirm(BuildContext c,String title,String body) async =>await showDialog<bool>(context:c,builder:(ctx)=>AlertDialog(title:Text(title),content:Text(body),actions:[
  TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm'))]))??false;
Future<String?> prompt(BuildContext c,String title,{bool secret=false,String initial=''}) async {
  var value=initial;
  return showDialog<String>(context:c,builder:(ctx)=>AlertDialog(title:Text(title),content:TextFormField(initialValue:initial,autofocus:true,obscureText:secret,onChanged:(v)=>value=v),actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,value.trim()),child:const Text('Continue'))]));
}
Widget panel(BuildContext c,List<Widget> children)=>Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(16),
  decoration:BoxDecoration(color:Theme.of(c).colorScheme.surface,borderRadius:BorderRadius.circular(18)),
  child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:children));
Widget heading(String title,{Widget? action})=>Row(children:[Expanded(child:Text(title,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700))),if(action!=null) action]);
Widget note(String text)=>Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Text(text,style:const TextStyle(fontSize:14)));
Widget feed(List<Widget> items)=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,32),children:items);
Widget badge(RowData r)=>CircleAvatar(backgroundColor:(colors[r['color']]??green).withAlpha(26),foregroundColor:colors[r['color']]??green,child:Icon(icons[r['icon']]??Icons.circle_outlined));
Widget link(String title,VoidCallback tap)=>TextButton(onPressed:tap,child:Text(title));
Widget filters(List<String> choices,String value,ValueChanged<String> change)=>SingleChildScrollView(scrollDirection:Axis.horizontal,
  child:Row(children:[for(final item in choices) Padding(padding:const EdgeInsets.only(right:8),child:ChoiceChip(label:Text(item),selected:item==value,onSelected:(_)=>change(item)))]));
String label(Store s,String table,dynamic id)=>s.rows(table).where((r)=>r['id']==id).firstOrNull?['name']??'';
List<RowData> recent(Store s)=>[...s.rows('transactions')]..sort((a,b){final d=(b['day'] as String).compareTo(a['day']);return d==0?(b['id'] as int).compareTo(a['id']):d;});
Widget txTile(BuildContext c,Store s,RowData r){
  final transfer=r['kind']=='Transfer',income=r['kind']=='Income';
  final color=transfer?Colors.blueGrey:income?green:red;
  return ListTile(contentPadding:EdgeInsets.zero,onTap:()=>edit(c,r['kind'],r),leading:CircleAvatar(backgroundColor:color.withAlpha(24),child:Icon(transfer?Icons.swap_horiz:income?Icons.south_west:Icons.north_east,color:color)),
    title:Text(transfer?'Transfer':label(s,'categories',r['category'])),subtitle:Text('${label(s,'accounts',r['account'])}${transfer?' → ${label(s,'accounts',r['destination'])}':''}\n${r['day']}'),
    trailing:Text(s.money(r['amount']),style:TextStyle(color:color,fontWeight:FontWeight.w600)));
}
Set<String> logs(Store s,RowData h)=>{for(final l in s.rows('habit_logs')) if(l['habit']==h['id']) l['day'] as String};
Widget meter(double ratio)=>Padding(padding:const EdgeInsets.symmetric(vertical:8),child:ClipRRect(borderRadius:BorderRadius.circular(8),child:LinearProgressIndicator(minHeight:7,value:ratio.clamp(0,1).toDouble())));
Future<void> quick(BuildContext c) async {
  final kind=await showModalBottomSheet<String>(context:c,showDragHandle:true,builder:(ctx)=>SafeArea(child:SingleChildScrollView(child:Wrap(children:[
    for(final k in ['Income','Expense','Transfer','Habit','Task','Goal']) ListTile(title:Text(k),leading:Icon({'Income':Icons.south_west,'Expense':Icons.north_east,'Transfer':Icons.swap_horiz,'Habit':Icons.repeat,'Task':Icons.checklist,'Goal':Icons.flag_outlined}[k]),onTap:()=>Navigator.pop(ctx,k))]))));
  if(c.mounted && kind!=null)edit(c,kind);
}
