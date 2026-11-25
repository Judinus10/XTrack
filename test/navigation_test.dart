import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xtrack/core/store.dart';
import 'package:xtrack/main.dart';

void main(){
  Store emptyStore()=>Store()..data={for(final table in tables)table:[]};
  Future<void> mount(WidgetTester tester,Store s) async{
    await tester.pumpWidget(ProviderScope(overrides:[storeProvider.overrideWith((_)=>s)],child:const XTrack()));
    await tester.pumpAndSettle();
  }
  testWidgets('dashboard opens task form through Quick Add', (tester) async{
    await mount(tester,emptyStore());
    await tester.tap(find.byTooltip('Quick Add'));await tester.pumpAndSettle();
    await tester.tap(find.text('Task').last);await tester.pumpAndSettle();
    expect(find.text('New Task'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('PIN on launch conceals dashboard', (tester) async{
    await mount(tester,emptyStore()..hasPin=true);
    expect(find.text('Unlock XTrack'),findsOneWidget);
    expect(find.text('Available balance'),findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('stored dark preference selects the dark theme', (tester) async{
    final store=emptyStore();
    store.data['settings']=[{'key':'theme','value':'dark'}];
    await mount(tester,store);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,ThemeMode.dark);
    await tester.pumpWidget(const SizedBox());
  });
}
