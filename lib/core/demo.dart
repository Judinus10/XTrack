part of 'store.dart';
extension Demo on Store {
  Future<void> clearDemo()=>write((t) async {
    for(final table in ['transactions','accounts','habits','tasks','goals']){
      await t.delete(table,where:'demo=1');
    }
  },reschedule:true);
  Future<void> loadDemo()=>write((t) async {
    if((await t.query('accounts',where:'demo=1')).isNotEmpty) return;
    final now=DateTime.now();
    final bank=await t.insert('accounts',{'name':'Demo · Sampath Bank','type':'Bank account','opening':2450000,'icon':'Bank','color':'Green','demo':1});
    final cash=await t.insert('accounts',{'name':'Demo · Pocket cash','type':'Cash','opening':450000,'icon':'Wallet','color':'Amber','demo':1});
    final categories=await t.query('categories');
    int cat(String name)=>categories.firstWhere((r)=>r['name']==name)['id'] as int;
    for(final offset in [27,21,14,9,6,4,2,1,0]) {
      final income=offset==27||offset==4;
      await t.insert('transactions',{'account':income?bank:cash,'kind':income?'Income':'Expense','amount':income?3500000:13500+offset*700,'category':cat(income?'Freelance':offset.isEven?'Food':'Transport'),'day':dayKey(shift(now,-offset)),'description':income?'Design project':offset.isEven?'Groceries':'Bus fare','demo':1});
    }
    await t.insert('transactions',{'account':bank,'destination':cash,'kind':'Transfer','amount':250000,'day':today,'demo':1});
    for(final name in ['Morning walk','Practice Java']){
      final mask=name=='Morning walk'?127:31;
      final start=dayKey(shift(now,-20));
      final id=await t.insert('habits',{'name':name,'days':mask,'start':start,'icon':mask==127?'Fitness':'Book','color':mask==127?'Green':'Blue','demo':1});
      await t.insert('habit_schedules',{'habit':id,'day':start,'days':mask});
      for(var i=0;i<21;i++) {
        final d=shift(now,-i);
        if(scheduled({'days':mask,'start':start},d) && (i+mask)%5!=0) await t.insert('habit_logs',{'habit':id,'day':dayKey(d)});
      }
    }
    for(final item in [('Review expenses',0),('Apply for a role',1),('Renew bus pass',-2),('Plan the week',-1)]){
      await t.insert('tasks',{'name':item.$1,'category':'Personal','priority':'Medium','day':dayKey(shift(now,item.$2)),'completed':item.$2==-1?today:null,'demo':1});
    }
    await t.insert('goals',{'name':'Emergency fund','category':'Financial','target':10000000,'current':3250000,'unit':'LKR','day':dayKey(shift(now,90)),'icon':'Flag','color':'Green','demo':1});
  });
}
