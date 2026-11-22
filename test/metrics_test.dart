import 'package:flutter_test/flutter_test.dart';
import 'package:xtrack/core/metrics.dart';

void main(){
  test('decimal parsing stays exact at input boundaries',(){
    expect(minor('0.29'),29);
    expect(minor('123456789012.99'),12345678901299);
    expect(minor('-0.01'),-1);
    expect(decimal(-1),'-0.01');
    for(final bad in ['','12.345','1e4','NaN','4,000']){expect(minor(bad),isNull);}
  });
  test('streak survives weekends and an unfinished scheduled day',(){
    final h={'start':'2026-11-19','days':31};
    expect(streaks(h,{'2026-11-19','2026-11-20'},DateTime(2026,11,23)),(2,2));
    expect(streaks(h,{'2026-11-19','2026-11-20'},DateTime(2026,11,24)),(0,2));
  });
  test('schedule changes preserve earlier scheduled days',(){
    final h={'start':'2026-11-19','days':1,'history':[{'day':'2026-11-19','days':31},{'day':'2026-11-23','days':1}]};
    expect(scheduled(h,DateTime(2026,11,20)),isTrue);
    expect(scheduled(h,DateTime(2026,11,24)),isFalse);
  });
}
