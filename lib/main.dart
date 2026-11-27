// ============================================================
// ذِكرى (Dhikra) — مصحف + مواقيت صلاة + أذكار + قبلة
// Phase 1 MVP — full-file main.dart (no compiler was used on this file)
// ============================================================
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adhan_dart/adhan_dart.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_compass_v3/flutter_compass_v3.dart';
import 'package:url_launcher/url_launcher.dart';

// ===================== constants =====================
const String kAppName = 'ذِكرى';
const String kAppVersion = '1.0.0';

const Color kGreen = Color(0xFF0E6B4E);
const Color kGreenDeep = Color(0xFF0A4D38);
const Color kGold = Color(0xFFC9A227);
const Color kCream = Color(0xFFFAF6EE);
const Color kDarkBg = Color(0xFF101D18);
const Color kDarkCard = Color(0xFF1B2D25);

const String kAssetQuran = 'assets/quran-uthmani-numbered.txt';
const String kAssetMeta = 'assets/sura_meta.json';
const String kAssetAdhkar = 'assets/adhkar.json';

const List<String> kWeekdaysAr = <String>[
  'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'
];
const List<String> kMonthsAr = <String>[
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
];
const List<String> kPrayerNamesAr = <String>[
  'الفجر', 'الشروق', 'الظهر', 'العصر', 'المغرب', 'العشاء'
];

// ===================== helpers =====================
String arNum(Object n) {
  const List<String> d = <String>['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  final String s = n.toString();
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final int c = s.codeUnitAt(i);
    if (c >= 48 && c <= 57) {
      b.write(d[c - 48]);
    } else {
      b.write(s[i]);
    }
  }
  return b.toString();
}

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime t) {
  int h = t.hour;
  final String per = h < 12 ? 'ص' : 'م';
  h = h % 12;
  if (h == 0) h = 12;
  return '${arNum('$h:${two(t.minute)}')} $per';
}

String fmtCountdown(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes % 60;
  final int s = d.inSeconds % 60;
  return arNum('${two(h)}:${two(m)}:${two(s)}');
}

// ===================== cities =====================
class City {
  final String name;
  final double lat;
  final double lng;
  const City(this.name, this.lat, this.lng);
}

const List<City> kCities = <City>[
  City('القاهرة', 30.0444, 31.2357),
  City('الجيزة', 30.0131, 31.2089),
  City('الإسكندرية', 31.2001, 29.9187),
  City('المنصورة', 31.0364, 31.3807),
  City('طنطا', 30.7865, 31.0004),
  City('الزقازيق', 30.5877, 31.5020),
  City('بنها', 30.4591, 31.1844),
  City('دمنهور', 31.0341, 30.4682),
  City('كفر الشيخ', 31.1117, 30.9388),
  City('دمياط', 31.4165, 31.8133),
  City('بورسعيد', 31.2653, 32.3019),
  City('الإسماعيلية', 30.5965, 32.2715),
  City('السويس', 29.9668, 32.5498),
  City('الفيوم', 29.3084, 30.8428),
  City('بني سويف', 29.0661, 31.0994),
  City('المنيا', 28.1099, 30.7503),
  City('أسيوط', 27.1809, 31.1837),
  City('سوهاج', 26.5569, 31.6948),
  City('قنا', 26.1642, 32.7267),
  City('الأقصر', 25.6872, 32.6396),
  City('أسوان', 24.0889, 32.8998),
  City('الغردقة', 27.2579, 33.8116),
  City('شرم الشيخ', 27.9158, 34.3299),
  City('مرسى مطروح', 31.3525, 27.2373),
  City('العريش', 31.1311, 33.7983),
];

// ===================== persistent store =====================
class Store {
  static late SharedPreferences p;

  static Future<void> init() async {
    p = await SharedPreferences.getInstance();
  }

  static bool get night => p.getBool('night') ?? false;
  static set night(bool v) {
    p.setBool('night', v);
  }

  static double get fontSize => p.getDouble('fontSize') ?? 26.0;
  static set fontSize(double v) {
    p.setDouble('fontSize', v);
  }

  static int get lastSura => p.getInt('lastSura') ?? 1;
  static int get lastAya => p.getInt('lastAya') ?? 1;

  static Future<void> setLastRead(int s, int a) async {
    await p.setInt('lastSura', s);
    await p.setInt('lastAya', a);
  }

  static List<String> get bookmarks => p.getStringList('bookmarks') ?? <String>[];

  static Future<void> toggleBookmark(String key) async {
    final List<String> b = List<String>.from(bookmarks);
    if (b.contains(key)) {
      b.remove(key);
    } else {
      b.add(key);
    }
    b.sort();
    await p.setStringList('bookmarks', b);
  }

  static Future<void> removeBookmark(String key) async {
    final List<String> b = List<String>.from(bookmarks)..remove(key);
    await p.setStringList('bookmarks', b);
  }

  static int get cityIdx => p.getInt('cityIdx') ?? 0;
  static set cityIdx(int v) {
    p.setInt('cityIdx', v);
  }

  static bool get customLoc => p.getBool('customLoc') ?? false;
  static set customLoc(bool v) {
    p.setBool('customLoc', v);
  }

  static double get customLat => p.getDouble('customLat') ?? 30.0444;
  static set customLat(double v) {
    p.setDouble('customLat', v);
  }

  static double get customLng => p.getDouble('customLng') ?? 31.2357;
  static set customLng(double v) {
    p.setDouble('customLng', v);
  }

  static bool get hanafi => p.getBool('hanafi') ?? false;
  static set hanafi(bool v) {
    p.setBool('hanafi', v);
  }

  // per-prayer minute adjustments: 0 fajr, 1 dhuhr, 2 asr, 3 maghrib, 4 isha
  static int adj(int i) => p.getInt('adj$i') ?? 0;
  static Future<void> setAdj(int i, int v) async {
    await p.setInt('adj$i', v);
  }

  static bool get notifOn => p.getBool('notifOn') ?? true;
  static set notifOn(bool v) {
    p.setBool('notifOn', v);
  }

  static bool get reminderOn => p.getBool('reminderOn') ?? true;
  static set reminderOn(bool v) {
    p.setBool('reminderOn', v);
  }

  static bool get batteryHintDismissed => p.getBool('batteryHintDismissed') ?? false;
  static set batteryHintDismissed(bool v) {
    p.setBool('batteryHintDismissed', v);
  }

  static String _todayKey() {
    final DateTime n = DateTime.now();
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  static Map<String, int> adhkarCounts() {
    try {
      if (p.getString('adhkarDate') != _todayKey()) {
        p.setString('adhkarDate', _todayKey());
        p.setString('adhkarCounts', '{}');
        return <String, int>{};
      }
      final String raw = p.getString('adhkarCounts') ?? '{}';
      final Map<String, dynamic> m = json.decode(raw) as Map<String, dynamic>;
      final Map<String, int> out = <String, int>{};
      m.forEach((String k, dynamic v) {
        if (v is int) out[k] = v;
      });
      return out;
    } catch (_) {
      return <String, int>{};
    }
  }

  static Future<void> setDhikrCount(String id, int v) async {
    final Map<String, int> m = adhkarCounts();
    m[id] = v;
    await p.setString('adhkarCounts', json.encode(m));
  }

  static Future<void> resetAdhkar() async {
    await p.setString('adhkarCounts', '{}');
  }
}

// ===================== quran data =====================
class SuraInfo {
  final int n;
  final String name;
  final int ayas;
  final bool madani;
  const SuraInfo(this.n, this.name, this.ayas, this.madani);
}

class QuranLib {
  static String bismillah = '';
  static List<SuraInfo> suras = <SuraInfo>[];
  static List<List<String>> text = <List<String>>[];

  static Future<void> load() async {
    final String raw = await rootBundle.loadString(kAssetQuran);
    final List<List<String>> map =
        List<List<String>>.generate(115, (_) => <String>[]);
    for (final String line in const LineSplitter().convert(raw)) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final int i1 = line.indexOf('|');
      if (i1 < 1) continue;
      final int i2 = line.indexOf('|', i1 + 1);
      if (i2 < 0) continue;
      final int s = int.tryParse(line.substring(0, i1)) ?? 0;
      if (s < 1 || s > 114) continue;
      map[s].add(line.substring(i2 + 1));
    }
    text = map;
    final String metaRaw = await rootBundle.loadString(kAssetMeta);
    final Map<String, dynamic> mj = json.decode(metaRaw) as Map<String, dynamic>;
    bismillah = (mj['bismillah'] ?? '') as String;
    final List<SuraInfo> out = <SuraInfo>[];
    for (final dynamic e in (mj['suras'] as List<dynamic>)) {
      final Map<String, dynamic> em = e as Map<String, dynamic>;
      out.add(SuraInfo(
        (em['n'] as num).toInt(),
        (em['name'] ?? '') as String,
        (em['ayas'] as num).toInt(),
        (em['madani'] ?? false) as bool,
      ));
    }
    suras = out;
    if (suras.length != 114) {
      throw StateError('sura_meta.json incomplete');
    }
  }
}

// ===================== adhkar data =====================
class Dhikr {
  final String id;
  final String text;
  final int count;
  final String fadl;
  const Dhikr(this.id, this.text, this.count, this.fadl);
}

class AdhkarLib {
  static List<Dhikr> morning = <Dhikr>[];
  static List<Dhikr> evening = <Dhikr>[];

  static Future<void> load() async {
    final String raw = await rootBundle.loadString(kAssetAdhkar);
    final Map<String, dynamic> j = json.decode(raw) as Map<String, dynamic>;
    morning = _parseList(j['morning']);
    evening = _parseList(j['evening']);
  }

  static List<Dhikr> _parseList(dynamic arr) {
    final List<Dhikr> out = <Dhikr>[];
    if (arr is List<dynamic>) {
      for (final dynamic e in arr) {
        final Map<String, dynamic> em = e as Map<String, dynamic>;
        out.add(Dhikr(
          (em['id'] ?? '') as String,
          (em['text'] ?? '') as String,
          (em['count'] as num?)?.toInt() ?? 1,
          (em['fadl'] ?? '') as String,
        ));
      }
    }
    return out;
  }
}

// ===================== prayer logic =====================
class DayTimes {
  final DateTime fajr;
  final DateTime sunrise;
  final DateTime dhuhr;
  final DateTime asr;
  final DateTime maghrib;
  final DateTime isha;
  const DayTimes(this.fajr, this.sunrise, this.dhuhr, this.asr, this.maghrib, this.isha);

  List<DateTime> get all => <DateTime>[fajr, sunrise, dhuhr, asr, maghrib, isha];
}

class PrayerLogic {
  static tz.Location get loc => tz.getLocation('Africa/Cairo');

  static Coordinates coords() {
    if (Store.customLoc) {
      return Coordinates(Store.customLat, Store.customLng);
    }
    final int i = math.min(kCities.length - 1, math.max(0, Store.cityIdx));
    return Coordinates(kCities[i].lat, kCities[i].lng);
  }

  static String cityName() {
    if (Store.customLoc) return 'موقع مخصص';
    final int i = math.min(kCities.length - 1, math.max(0, Store.cityIdx));
    return kCities[i].name;
  }

  static CalculationParameters params() {
    final CalculationParameters cp = CalculationMethodParameters.egyptian();
    cp.madhab = Store.hanafi ? Madhab.hanafi : Madhab.shafi;
    cp.adjustments = <Prayer, int>{
      Prayer.fajr: Store.adj(0),
      Prayer.dhuhr: Store.adj(1),
      Prayer.asr: Store.adj(2),
      Prayer.maghrib: Store.adj(3),
      Prayer.isha: Store.adj(4),
    };
    return cp;
  }

  static DayTimes timesFor(DateTime day) {
    final PrayerTimes pt = PrayerTimes(
      date: DateTime(day.year, day.month, day.day),
      coordinates: coords(),
      calculationParameters: params(),
    );
    DateTime c(DateTime u) => tz.TZDateTime.from(u, loc);
    return DayTimes(c(pt.fajr), c(pt.sunrise), c(pt.dhuhr), c(pt.asr), c(pt.maghrib), c(pt.isha));
  }

  // index into DayTimes.all (0 fajr .. 5 isha) + its time
  static ({int idx, DateTime at}) nextEvent() {
    final DateTime now = DateTime.now();
    final DayTimes today = timesFor(now);
    for (int i = 0; i < 6; i++) {
      if (today.all[i].isAfter(now)) {
        return (idx: i, at: today.all[i]);
      }
    }
    final DayTimes tomorrow = timesFor(now.add(const Duration(days: 1)));
    return (idx: 0, at: tomorrow.fajr);
  }
}

// ===================== notifications =====================
class NotifSvc {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    try {
      const AndroidInitializationSettings androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: androidInit));
      final AndroidFlutterLocalNotificationsPlugin? a =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      try {
        await a?.requestNotificationsPermission();
      } catch (_) {}
      try {
        await a?.requestExactAlarmsPermission();
      } catch (_) {}
      _ready = true;
    } catch (_) {}
  }

  static NotificationDetails _details(String chId, String chName, {bool alarm = false}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        chId,
        chName,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        category: alarm ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
      ),
    );
  }

  static Future<void> _z(int id, String title, String body, DateTime when, String chId, String chName, {bool alarm = false}) async {
    final tz.TZDateTime dt = tz.TZDateTime.from(when, PrayerLogic.loc);
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        dt,
        _details(chId, chName, alarm: alarm),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (_) {
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          dt,
          _details(chId, chName, alarm: alarm),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (_) {}
    }
  }

  // schedules the next 7 days of adhan + reminder notifications
  static Future<void> scheduleWeek() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!Store.notifOn) return;
      final DateTime now = DateTime.now();
      int id = 100;
      const List<int> prayedIdx = <int>[0, 2, 3, 4, 5]; // skip sunrise
      for (int d = 0; d < 7; d++) {
        final DateTime day = now.add(Duration(days: d));
        final DayTimes t = PrayerLogic.timesFor(day);
        for (final int pi in prayedIdx) {
          final DateTime at = t.all[pi];
          final String name = kPrayerNamesAr[pi];
          if (at.isAfter(now)) {
            await _z(id++, 'حان الآن وقت صلاة $name', 'تقبل الله طاعتكم 🤲', at, 'adhan_times', 'مواقيت الصلاة', alarm: true);
          }
          if (Store.reminderOn) {
            final DateTime r = at.subtract(const Duration(minutes: 20));
            if (r.isAfter(now)) {
              await _z(id++, 'اقترب موعد صلاة $name', 'باقي ٢٠ دقيقة على الأذان 🕌', r, 'adhan_reminder', 'تذكير قبل الأذان');
            }
          }
        }
      }
    } catch (_) {}
  }
}

// ===================== app root =====================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? bootError;
  try {
    tzdata.initializeTimeZones();
  } catch (e) {
    bootError = 'خطأ في تهيئة المنطقة الزمنية';
  }
  try {
    await Store.init();
  } catch (e) {
    bootError = 'خطأ في تهيئة الإعدادات';
  }
  try {
    await QuranLib.load();
  } catch (e) {
    bootError = 'تعذر تحميل نص المصحف. تأكد من ملفات assets';
  }
  try {
    await AdhkarLib.load();
  } catch (_) {}
  NotifSvc.init();
  runApp(NoorApp(bootError: bootError));
  Future<void>.delayed(const Duration(seconds: 3), NotifSvc.scheduleWeek);
}

class NoorApp extends StatefulWidget {
  final String? bootError;
  const NoorApp({super.key, this.bootError});

  static NoorAppState of(BuildContext context) =>
      context.findAncestorStateOfType<NoorAppState>()!;

  @override
  State<NoorApp> createState() => NoorAppState();
}

class NoorAppState extends State<NoorApp> {
  bool night = Store.night;

  void setNight(bool v) {
    setState(() {
      night = v;
      Store.night = v;
    });
  }

  ThemeData _light() {
    final ColorScheme cs = ColorScheme.fromSeed(
      seedColor: kGreen,
      brightness: Brightness.light,
    ).copyWith(primary: kGreen, secondary: kGold, surface: kCream);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: cs,
      scaffoldBackgroundColor: kCream,
      appBarTheme: const AppBarTheme(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
    );
  }

  ThemeData _dark() {
    final ColorScheme cs = ColorScheme.fromSeed(
      seedColor: kGreen,
      brightness: Brightness.dark,
    ).copyWith(primary: const Color(0xFF7BC8A4), secondary: kGold, surface: kDarkCard);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      scaffoldBackgroundColor: kDarkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: kGreenDeep,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _light(),
      darkTheme: _dark(),
      themeMode: night ? ThemeMode.dark : ThemeMode.light,
      home: widget.bootError != null
          ? BootErrorScreen(message: widget.bootError!)
          : const HomeShell(),
    );
  }
}

class BootErrorScreen extends StatelessWidget {
  final String message;
  const BootErrorScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 64, color: kGreen),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            ],
          ),
        ),
      ),
    );
  }
}

// ===================== home shell =====================
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotifSvc.scheduleWeek();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      const QuranTab(),
      const PrayerTab(),
      const AdhkarTab(),
      const QiblaTab(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (int i) => setState(() => _tab = i),
        destinations: const <Widget>[
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'المصحف'),
          NavigationDestination(icon: Icon(Icons.access_time_outlined), selectedIcon: Icon(Icons.access_time), label: 'المواقيت'),
          NavigationDestination(icon: Icon(Icons.volunteer_activism_outlined), selectedIcon: Icon(Icons.volunteer_activism), label: 'الأذكار'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'القبلة'),
        ],
      ),
    );
  }
}

// ===================== quran tab =====================
class QuranTab extends StatefulWidget {
  const QuranTab({super.key});

  @override
  State<QuranTab> createState() => _QuranTabState();
}

class _QuranTabState extends State<QuranTab> {
  void _openReader(int sura, int aya) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ReaderPage(sura: sura, initialAya: aya)))
        .then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final List<String> bm = Store.bookmarks;
    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName, style: TextStyle(fontWeight: FontWeight.bold)),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: 'العلامات',
            onPressed: () => showBookmarksSheet(context),
          ),
          IconButton(
            icon: Icon(NoorApp.of(context).night ? Icons.wb_sunny_outlined : Icons.nightlight_outlined),
            tooltip: 'الوضع الليلي',
            onPressed: () => NoorApp.of(context).setNight(!NoorApp.of(context).night),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: QuranLib.suras.length + 1,
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            final int ls = math.min(114, math.max(1, Store.lastSura));
            final SuraInfo info = QuranLib.suras[ls - 1];
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _openReader(ls, Store.lastAya),
                child: Container(
                  decoration: BoxDecoration(
                    color: kGreen,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text('متابعة القراءة',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('سورة ${info.name} — آية ${arNum(Store.lastAya)}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final SuraInfo s = QuranLib.suras[i - 1];
          final bool hasBm = bm.any((String b) => b.startsWith('${s.n}:'));
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: kGreen.withValues(alpha: 0.12),
              child: Text(arNum(s.n), style: const TextStyle(color: kGreen, fontWeight: FontWeight.bold)),
            ),
            title: Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            subtitle: Text('${s.madani ? 'مدنية' : 'مكية'} • ${arNum(s.ayas)} آية'),
            trailing: hasBm ? const Icon(Icons.bookmark, color: kGold, size: 20) : null,
            onTap: () => _openReader(s.n, 1),
          );
        },
      ),
    );
  }
}

void showBookmarksSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) {
      return StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSheet) {
          final List<String> bm = Store.bookmarks;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('العلامات المرجعية',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (bm.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('لا توجد علامات بعد.\nاضغط مطولًا على أي آية لحفظها.',
                          textAlign: TextAlign.center),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: bm.length,
                        itemBuilder: (BuildContext ctx, int i) {
                          final List<String> parts = bm[i].split(':');
                          final int s = int.tryParse(parts[0]) ?? 1;
                          final int a = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
                          final String name = (s >= 1 && s <= 114) ? QuranLib.suras[s - 1].name : '';
                          return ListTile(
                            leading: const Icon(Icons.bookmark, color: kGold),
                            title: Text('سورة $name'),
                            subtitle: Text('آية ${arNum(a)}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await Store.removeBookmark(bm[i]);
                                setSheet(() {});
                              },
                            ),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              Navigator.of(context)
                                  .push(MaterialPageRoute<void>(
                                      builder: (_) => ReaderPage(sura: s, initialAya: a)))
                                  .then((_) {});
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

// ===================== reader page =====================
class ReaderPage extends StatefulWidget {
  final int sura;
  final int initialAya;
  const ReaderPage({super.key, required this.sura, this.initialAya = 1});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final ScrollController _ctrl = ScrollController();
  late SuraInfo info;

  @override
  void initState() {
    super.initState();
    info = QuranLib.suras[widget.sura - 1];
    if (widget.initialAya > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (_ctrl.hasClients) {
            final double target = (widget.initialAya - 1) * 130.0;
            final double max = _ctrl.position.maxScrollExtent;
            _ctrl.jumpTo(target > max ? max : target);
          }
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _fontSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheet) {
            final double v = Store.fontSize;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('حجم الخط', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Slider(
                      value: v,
                      min: 18,
                      max: 42,
                      divisions: 24,
                      label: arNum(v.toStringAsFixed(0)),
                      onChanged: (double nv) {
                        Store.fontSize = nv;
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                    Text('بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: v, height: 1.9)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> ayat = QuranLib.text[widget.sura];
    final List<String> bm = Store.bookmarks;
    final bool showBismillah = widget.sura != 1 && widget.sura != 9;
    final double fs = Store.fontSize;
    return Scaffold(
      appBar: AppBar(
        title: Text('سورة ${info.name}'),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.bookmark_outline), tooltip: 'العلامات', onPressed: () => showBookmarksSheet(context)),
          IconButton(icon: const Icon(Icons.text_fields), tooltip: 'حجم الخط', onPressed: _fontSheet),
        ],
      ),
      body: ListView.builder(
        controller: _ctrl,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        itemCount: ayat.length + 1,
        itemBuilder: (BuildContext context, int i) {
          if (i == 0) {
            return Column(
              children: <Widget>[
                const SizedBox(height: 12),
                Text('${info.madani ? 'مدنية' : 'مكية'} • ${arNum(info.ayas)} آية',
                    style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 13)),
                if (showBismillah) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(QuranLib.bismillah,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: fs, height: 1.9, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 12),
              ],
            );
          }
          final int a = i;
          final String key = '${widget.sura}:$a';
          final bool marked = bm.contains(key);
          return GestureDetector(
            onTap: () {
              Store.setLastRead(widget.sura, a);
            },
            onLongPress: () async {
              await Store.toggleBookmark(key);
              setState(() {});
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: marked ? kGold.withValues(alpha: 0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: marked ? Border.all(color: kGold.withValues(alpha: 0.5)) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    '${ayat[i - 1]} ﴿${arNum(a)}﴾',
                    textAlign: TextAlign.justify,
                    style: TextStyle(fontSize: fs, height: 2.0),
                  ),
                  if (marked)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(Icons.bookmark, color: kGold, size: 16),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===================== prayer tab =====================
class PrayerTab extends StatefulWidget {
  const PrayerTab({super.key});

  @override
  State<PrayerTab> createState() => _PrayerTabState();
}

class _PrayerTabState extends State<PrayerTab> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    try {
      HijriCalendar.setLocal('ar');
    } catch (_) {}
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _hijriText() {
    try {
      final HijriCalendar h = HijriCalendar.now();
      return '${arNum(h.toFormat("dd MMMM yyyy"))} هـ';
    } catch (_) {
      return '';
    }
  }

  String _gregText() {
    final DateTime n = DateTime.now();
    return '${kWeekdaysAr[n.weekday - 1]}، ${arNum(n.day)} ${kMonthsAr[n.month - 1]} ${arNum(n.year)}';
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => const PrayerSettingsSheet(),
    );
    if (mounted) setState(() {});
    NotifSvc.scheduleWeek();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    DayTimes times;
    ({int idx, DateTime at}) next;
    try {
      times = PrayerLogic.timesFor(now);
      next = PrayerLogic.nextEvent();
    } catch (e) {
      return Scaffold(
        appBar: AppBar(title: const Text('مواقيت الصلاة')),
        body: const Center(child: Text('تعذر حساب المواقيت')),
      );
    }
    final Duration remain = next.at.difference(now);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مواقيت الصلاة'),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'الإعدادات', onPressed: _openSettings),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(_hijriText(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(_gregText(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          Text(PrayerLogic.cityName(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: kGreen)),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: kGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: <Widget>[
                Text('باقي على صلاة ${kPrayerNamesAr[next.idx]}',
                    style: const TextStyle(color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 8),
                Text(fmtCountdown(remain),
                    style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 8),
                Text('الأذان ${fmtTime(next.at)}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < 6; i++)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: i == next.idx
                    ? kGold.withValues(alpha: 0.15)
                    : (NoorApp.of(context).night ? kDarkCard : Colors.white),
                borderRadius: BorderRadius.circular(14),
                border: i == next.idx ? Border.all(color: kGold) : null,
              ),
              child: ListTile(
                leading: Icon(
                  i == 0
                      ? Icons.wb_twilight
                      : i == 1
                          ? Icons.wb_sunny_outlined
                          : i == 2
                              ? Icons.wb_sunny
                              : i == 3
                                  ? Icons.wb_cloudy_outlined
                                  : i == 4
                                      ? Icons.nights_stay_outlined
                                      : Icons.nights_stay,
                  color: i == next.idx ? kGold : kGreen,
                ),
                title: Text(kPrayerNamesAr[i], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                trailing: Text(fmtTime(times.all[i]), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
          if (!Store.batteryHintDismissed)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kGold.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('عشان إشعارات الأذان توصل في معادها:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 6),
                  const Text(
                    'من إعدادات الموبايل ← التطبيقات ← $kAppName ← البطارية ← اختار "بدون قيود" أو Unrestricted. بعض الموبايلات بتمنع إشعارات التطبيقات المقيدة.',
                    style: TextStyle(fontSize: 13, height: 1.6),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () {
                        Store.batteryHintDismissed = true;
                        setState(() {});
                      },
                      child: const Text('فهمت'),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'طريقة الحساب: الهيئة المصرية العامة للمساحة • المذهب: ${Store.hanafi ? 'حنفي' : 'شافعي'}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class PrayerSettingsSheet extends StatefulWidget {
  const PrayerSettingsSheet({super.key});

  @override
  State<PrayerSettingsSheet> createState() => _PrayerSettingsSheetState();
}

class _PrayerSettingsSheetState extends State<PrayerSettingsSheet> {
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lngCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _latCtrl.text = Store.customLat.toString();
    _lngCtrl.text = Store.customLng.toString();
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  void _saveCustom() {
    final double? la = double.tryParse(_latCtrl.text.trim());
    final double? ln = double.tryParse(_lngCtrl.text.trim());
    if (la != null && la >= -90 && la <= 90) Store.customLat = la;
    if (ln != null && ln >= -180 && ln <= 180) Store.customLng = ln;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          top: 8,
          right: 16,
          left: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Center(
              child: Text('إعدادات المواقيت', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('موقع مخصص (خارج مصر)'),
              value: Store.customLoc,
              onChanged: (bool v) => setState(() => Store.customLoc = v),
            ),
            if (!Store.customLoc)
              DropdownButtonFormField<int>(
                initialValue: math.min(kCities.length - 1, math.max(0, Store.cityIdx)),
                decoration: const InputDecoration(labelText: 'المدينة', border: OutlineInputBorder()),
                items: <DropdownMenuItem<int>>[
                  for (int i = 0; i < kCities.length; i++)
                    DropdownMenuItem<int>(value: i, child: Text(kCities[i].name)),
                ],
                onChanged: (int? v) {
                  if (v != null) setState(() => Store.cityIdx = v);
                },
              ),
            if (Store.customLoc)
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'خط العرض', border: OutlineInputBorder()),
                      onChanged: (_) => _saveCustom(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'خط الطول', border: OutlineInputBorder()),
                      onChanged: (_) => _saveCustom(),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            const Text('مذهب حساب العصر', style: TextStyle(fontWeight: FontWeight.bold)),
            RadioGroup<bool>(
              groupValue: Store.hanafi,
              onChanged: (bool? v) => setState(() => Store.hanafi = v ?? false),
              child: const Column(
                children: <Widget>[
                  RadioListTile<bool>(title: Text('شافعي'), value: false),
                  RadioListTile<bool>(title: Text('حنفي'), value: true),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('تعديل المواقيت (بالدقائق)', style: TextStyle(fontWeight: FontWeight.bold)),
            for (int i = 0; i < 5; i++)
              Builder(
                builder: (BuildContext context) {
                  const List<int> mapIdx = <int>[0, 2, 3, 4, 5];
                  final int pi = mapIdx[i];
                  final int v = Store.adj(i);
                  return Row(
                    children: <Widget>[
                      Expanded(child: Text(kPrayerNamesAr[pi])),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () async {
                          await Store.setAdj(i, v - 1);
                          setState(() {});
                        },
                      ),
                      Text('${v >= 0 ? '+' : '−'}${arNum(v.abs())}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () async {
                          await Store.setAdj(i, v + 1);
                          setState(() {});
                        },
                      ),
                    ],
                  );
                },
              ),
            const Divider(),
            SwitchListTile(
              title: const Text('إشعارات الأذان'),
              value: Store.notifOn,
              onChanged: (bool v) => setState(() => Store.notifOn = v),
            ),
            SwitchListTile(
              title: const Text('تذكير قبل الأذان بـ ٢٠ دقيقة'),
              value: Store.reminderOn,
              onChanged: (bool v) => setState(() => Store.reminderOn = v),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: kGreen),
              title: const Text('عن التطبيق والمصادر'),
              onTap: () => showAboutSheet(context),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGreen, foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('تم'),
            ),
          ],
        ),
      ),
    );
  }
}

void showAboutSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(kAppName, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: kGreen)),
              Text('الإصدار ${arNum(kAppVersion)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              const Text(
                'مصحف كامل بالرواية العثمانية، مواقيت صلاة دقيقة، أذكار الصباح والمساء، واتجاه القبلة. مجاني بالكامل، بلا إعلانات، ويعمل دون إنترنت.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.7),
              ),
              const Divider(height: 28),
              const Text('نص المصحف: Tanzil Project — النص العثماني الإصدار 1.1',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  try {
                    await launchUrl(Uri.parse('https://tanzil.net'), mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                child: const Text('tanzil.net — رخصة CC BY 3.0',
                    style: TextStyle(fontSize: 13, color: kGreen, decoration: TextDecoration.underline)),
              ),
              const SizedBox(height: 8),
              const Text('حساب المواقيت: مكتبة adhan_dart • التقويم الهجري: أم القرى',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    },
  );
}

// ===================== adhkar tab =====================
class AdhkarTab extends StatefulWidget {
  const AdhkarTab({super.key});

  @override
  State<AdhkarTab> createState() => _AdhkarTabState();
}

class _AdhkarTabState extends State<AdhkarTab> {
  bool morning = true;

  @override
  Widget build(BuildContext context) {
    final List<Dhikr> items = morning ? AdhkarLib.morning : AdhkarLib.evening;
    final Map<String, int> counts = Store.adhkarCounts();
    int done = 0;
    for (final Dhikr d in items) {
      if ((counts[d.id] ?? 0) >= d.count) done++;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأذكار'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تصفير العدّادات',
            onPressed: () async {
              await Store.resetAdhkar();
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: true, label: Text('أذكار الصباح'), icon: Icon(Icons.wb_sunny_outlined)),
                ButtonSegment<bool>(value: false, label: Text('أذكار المساء'), icon: Icon(Icons.nights_stay_outlined)),
              ],
              selected: <bool>{morning},
              onSelectionChanged: (Set<bool> s) => setState(() => morning = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: LinearProgressIndicator(
                    value: items.isEmpty ? 0 : done / items.length,
                    backgroundColor: kGreen.withValues(alpha: 0.12),
                    color: kGreen,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${arNum(done)}/${arNum(items.length)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: items.length,
              itemBuilder: (BuildContext context, int i) {
                final Dhikr d = items[i];
                final int c = counts[d.id] ?? 0;
                final bool complete = c >= d.count;
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    if (c < d.count) {
                      await Store.setDhikrCount(d.id, c + 1);
                      setState(() {});
                    }
                  },
                  onLongPress: () async {
                    await Store.setDhikrCount(d.id, 0);
                    setState(() {});
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: complete
                          ? kGreen.withValues(alpha: 0.10)
                          : (NoorApp.of(context).night ? kDarkCard : Colors.white),
                      borderRadius: BorderRadius.circular(16),
                      border: complete ? Border.all(color: kGreen.withValues(alpha: 0.4)) : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(d.text, style: const TextStyle(fontSize: 16, height: 1.9)),
                        if (d.fadl.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(d.fadl, style: const TextStyle(fontSize: 12, color: kGold)),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: LinearProgressIndicator(
                                value: d.count == 0 ? 1 : (c / d.count).clamp(0.0, 1.0).toDouble(),
                                backgroundColor: kGreen.withValues(alpha: 0.10),
                                color: complete ? kGreen : kGold,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: complete ? kGreen : kGreen.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                complete ? 'تم ✓' : '${arNum(c)} / ${arNum(d.count)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: complete ? Colors.white : kGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ===================== qibla tab =====================
class QiblaTab extends StatelessWidget {
  const QiblaTab({super.key});

  static double qiblaBearing(double lat, double lng) {
    final double la = lat * math.pi / 180;
    final double lo = lng * math.pi / 180;
    const double ka = 21.422487 * math.pi / 180;
    const double ko = 39.826206 * math.pi / 180;
    final double dLon = ko - lo;
    final double y = math.sin(dLon);
    final double x = math.cos(la) * math.tan(ka) - math.sin(la) * math.cos(dLon);
    final double brng = math.atan2(y, x) * 180 / math.pi;
    return (brng + 360) % 360;
  }

  @override
  Widget build(BuildContext context) {
    final Coordinates c = PrayerLogic.coords();
    final double bearing = qiblaBearing(c.latitude, c.longitude);
    return Scaffold(
      appBar: AppBar(title: const Text('اتجاه القبلة')),
      body: StreamBuilder<CompassEvent>(
        stream: FlutterCompass.events,
        builder: (BuildContext context, AsyncSnapshot<CompassEvent> snap) {
          if (snap.hasError) {
            return const Center(child: Text('تعذر الوصول إلى البوصلة'));
          }
          if (!snap.hasData) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  CircularProgressIndicator(color: kGreen),
                  SizedBox(height: 16),
                  Text('جاري تجهيز البوصلة…'),
                ],
              ),
            );
          }
          final double? heading = snap.data?.heading;
          if (heading == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('البوصلة غير متوفرة على هذا الجهاز', textAlign: TextAlign.center),
              ),
            );
          }
          final double headingRad = heading * math.pi / 180;
          final double qiblaRad = (bearing - heading) * math.pi / 180;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              Text(
                'اتجاه القبلة ${arNum(bearing.toStringAsFixed(0))}° من الشمال',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'الموقع: ${PrayerLogic.cityName()}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Center(
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: NoorApp.of(context).night ? kDarkCard : Colors.white,
                          border: Border.all(color: kGreen.withValues(alpha: 0.4), width: 2),
                        ),
                      ),
                      Transform.rotate(
                        angle: -headingRad,
                        child: SizedBox(
                          width: 260,
                          height: 260,
                          child: Stack(
                            children: <Widget>[
                              const Align(alignment: Alignment.topCenter, child: Padding(padding: EdgeInsets.all(10), child: Text('ش', style: TextStyle(fontWeight: FontWeight.bold, color: kGreen, fontSize: 18)))),
                              const Align(alignment: Alignment.bottomCenter, child: Padding(padding: EdgeInsets.all(10), child: Text('ج', style: TextStyle(fontSize: 15, color: Colors.grey)))),
                              const Align(alignment: Alignment.centerRight, child: Padding(padding: EdgeInsets.all(10), child: Text('ق', style: TextStyle(fontSize: 15, color: Colors.grey)))),
                              const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.all(10), child: Text('غ', style: TextStyle(fontSize: 15, color: Colors.grey)))),
                            ],
                          ),
                        ),
                      ),
                      Transform.rotate(
                        angle: qiblaRad,
                        child: const Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: EdgeInsets.only(top: 34),
                            child: Text('🕋', style: TextStyle(fontSize: 26)),
                          ),
                        ),
                      ),
                      Transform.rotate(
                        angle: qiblaRad,
                        child: const Icon(Icons.navigation, size: 110, color: kGreen),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'وجّه الموبايل لحد ما السهم الأخضر يبقى لفوق تمامًا. للدقة: ابعد عن المغانط والأسطح المعدنية وحرّك الموبايل على شكل ٨ لو الاتجاه مش ثابت.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.7, color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}