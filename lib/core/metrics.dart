typedef RowData = Map<String, dynamic>;
String dayKey(DateTime d) => d.toIso8601String().split('T').first;
DateTime shift(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);
String get today => dayKey(DateTime.now());
bool scheduled(RowData habit, DateTime d) {
  final date=dayKey(d);
  if(date.compareTo(habit['start'])<0)return false;
  var mask=habit['days'] as int;
  String latest='';
  for(final entry in (habit['history'] as List? ?? const [])){
    final since=entry['day'] as String;
    if(since.compareTo(date)<=0 && since.compareTo(latest)>0){
      mask=entry['days'] as int;
      latest=since;
    }
  }
  return (mask & (1 << (d.weekday-1)))!=0;
}

int? minor(String input) {
  final match = RegExp(r'^(-?)(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch(input.trim());
  if (match == null) return null;
  final cents = int.parse(match[2]!) * 100 + int.parse((match[3] ?? '').padRight(2, '0'));
  return match[1] == '-' ? -cents : cents;
}
String decimal(int cents) =>
    "${cents < 0 ? '-' : ''}${cents.abs() ~/ 100}.${(cents.abs() % 100).toString().padLeft(2,'0')}";

(int,int) streaks(RowData habit, Set<String> logs, DateTime now) {
  var run = 0, longest = 0;
  for (var d = DateTime.parse(habit['start']); !d.isAfter(now); d = shift(d,1)) {
    if (!scheduled(habit,d)) continue;
    if (logs.contains(dayKey(d))) {
      run++;
      if (run > longest) longest = run;
    } else if (dayKey(d) != dayKey(now)) {
      run = 0;
    }
  }
  return (run,longest);
}
