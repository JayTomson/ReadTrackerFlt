import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart' as igs;
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

// ══════════════════════════════════════════════════════════
// ДИЗАЙН-ТОКЕНЫ — Единственный источник правды
// ══════════════════════════════════════════════════════════

const kAccent    = Color(0xFFFF9F0A);   // Тёплый янтарь
const kAccentDim = Color(0x20FF9F0A);  // 12% прозрачности акцента

// Приглушённые статусы
const kSPlanned   = Color(0xFF60A5FA);
const kSReading   = Color(0xFF34D399);
const kSPaused    = Color(0xFFFBBF24);
const kSCompleted = Color(0xFFA78BFA);
const kSDropped   = Color(0xFFF87171);

// Скругления углов
const kR   = 12.0;
const kRs  =  8.0;
const kRl  = 20.0;

// @override отступы
const kP   = 16.0;
const kPs  =  8.0;
const kPl  = 24.0;

// ══════════════════════════════════════════════════════════
// СИСТЕМА ТЕМЫ — Гарантия визуального соответствия
// ══════════════════════════════════════════════════════════

ThemeData _buildTheme(int mode) {
  final isDark   = mode != 2;
  final bg       = mode == 0 ? Colors.black
                 : mode == 1 ? const Color(0xFF0F0F0F)
                 :              const Color(0xFFF2F2F7);
  final card     = mode == 0 ? const Color(0xFF141414)
                 : mode == 1 ? const Color(0xFF1C1C1E)
                 :              Colors.white;
  final fg       = isDark ? Colors.white : Colors.black;
  final divider  = isDark ? Colors.white10 : Colors.black12;
  final base     = isDark ? ThemeData.dark(useMaterial3: true)
                          : ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    cardColor: card,
    colorScheme: isDark
        ? ColorScheme.dark(primary: kAccent, surface: card, surfaceContainer: card)
        : ColorScheme.light(primary: kAccent, surface: card),

    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      toolbarHeight: 48,
      titleSpacing: 8, // Уменьшено расстояние, чтобы заголовки были ближе к стрелке "Назад"
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20, fontWeight: FontWeight.w800, color: fg, letterSpacing: -0.3),
      iconTheme: IconThemeData(color: fg, size: 22),
      actionsIconTheme: IconThemeData(color: fg, size: 22),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: card,
      selectedItemColor: kAccent,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700),
      unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 11),
    ),

    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: fg, displayColor: fg),

    dividerColor: divider,

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kR),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kR),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kR),
        borderSide: const BorderSide(color: kAccent, width: 1.5),
      ),
      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 14),
      labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? kAccent
              : isDark ? Colors.white24 : Colors.black26),
    ),
  );
}

// ══════════════════════════════════════════════════════════
// ГЛОБАЛЬНОЕ СОСТОЯНИЕ
// ══════════════════════════════════════════════════════════

class AppState extends ChangeNotifier {
  int  themeMode       = 1;
  bool shortenNumbers  = false;
  bool showShareButton = false; // По умолчанию отключено
  bool stackedStats    = false;
  bool showCovers      = false; // По умолчанию отключено
  bool hideBottomBar   = true;  // По умолчанию включено
  bool showWebChapters = true;  // По умолчанию включено
  bool disableAnimations = false; // Отключение анимаций переходов
  
  // Настройки
  bool showBookmarks   = true;   
  int  bookmarkPosition = 1;     // По умолчанию "в ряд" (1)
  bool enableAdaptationStart = false; 
  
  bool enableHybrid    = true;   
  bool enableRating    = true;   
  int  ratingScale     = 10;     
  bool showWebInStats  = true;   

  int  savedTabIndex   = 0;
  List<Book> books     = [];

  Color statusColor(BookStatus s) => switch (s) {
    BookStatus.planned   => kSPlanned,
    BookStatus.reading   => kSReading,
    BookStatus.paused    => kSPaused,
    BookStatus.completed => kSCompleted,
    BookStatus.dropped   => kSDropped,
  };

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode       = p.getInt('themeMode')       ?? 1;
    shortenNumbers  = p.getBool('shortenNumbers')  ?? false;
    showShareButton = p.getBool('showShareButton') ?? false; // По умолчанию отключено
    stackedStats    = p.getBool('stackedStats')    ?? false;
    showCovers      = p.getBool('showCovers')      ?? false; // По умолчанию отключено
    hideBottomBar   = p.getBool('hideBottomBar')   ?? true;  // По умолчанию включено
    showWebChapters = p.getBool('showWebChapters') ?? true;  // По умолчанию включено
    disableAnimations = p.getBool('disableAnimations') ?? false;
    
    showBookmarks   = p.getBool('showBookmarks')   ?? true;
    bookmarkPosition = p.getInt('bookmarkPosition') ?? 1;     // По умолчанию "в ряд" (1)
    enableAdaptationStart = p.getBool('enableAdaptationStart') ?? false;

    enableHybrid    = p.getBool('enableHybrid')    ?? true;
    enableRating    = p.getBool('enableRating')    ?? true;
    ratingScale     = p.getInt('ratingScale')      ?? 10;
    showWebInStats  = p.getBool('showWebInStats')  ?? true;

    savedTabIndex   = p.getInt('savedTabIndex')    ?? 0;
    
    final bj = p.getString('books');
    if (bj != null) {
      try {
        books = (jsonDecode(bj) as List).map((e) => Book.fromJson(e)).toList();
      } catch (_) {
        books = [];
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('themeMode', themeMode);
    await p.setBool('shortenNumbers', shortenNumbers);
    await p.setBool('showShareButton', showShareButton);
    await p.setBool('stackedStats', stackedStats);
    await p.setBool('showCovers', showCovers);
    await p.setBool('hideBottomBar', hideBottomBar);
    await p.setBool('showWebChapters', showWebChapters);
    await p.setBool('disableAnimations', disableAnimations);
    
    await p.setBool('showBookmarks', showBookmarks);
    await p.setInt('bookmarkPosition', bookmarkPosition);
    await p.setBool('enableAdaptationStart', enableAdaptationStart);

    await p.setBool('enableHybrid', enableHybrid);
    await p.setBool('enableRating', enableRating);
    await p.setInt('ratingScale', ratingScale);
    await p.setBool('showWebInStats', showWebInStats);

    await p.setString('books', jsonEncode(books.map((b) => b.toJson()).toList()));
  }

  void toggleShortenNumbers(bool v)  { shortenNumbers  = v; _save(); notifyListeners(); }
  void toggleShareButton(bool v)     { showShareButton = v; _save(); notifyListeners(); }
  void toggleStackedStats(bool v)    { stackedStats    = v; _save(); notifyListeners(); }
  void toggleShowCovers(bool v)      { showCovers      = v; _save(); notifyListeners(); }
  void toggleHideBottomBar(bool v)   { hideBottomBar   = v; _save(); notifyListeners(); }
  void toggleShowWebChapters(bool v) { showWebChapters = v; _save(); notifyListeners(); }
  void toggleDisableAnimations(bool v){ disableAnimations = v; _save(); notifyListeners(); }
  
  void toggleShowBookmarks(bool v)   { showBookmarks   = v; _save(); notifyListeners(); }
  void setBookmarkPosition(int pos)  { bookmarkPosition = pos; _save(); notifyListeners(); }
  void toggleAdaptationStart(bool v) { enableAdaptationStart = v; _save(); notifyListeners(); }

  void toggleEnableHybrid(bool v)    { enableHybrid    = v; _save(); notifyListeners(); }
  void toggleEnableRating(bool v)    { enableRating    = v; _save(); notifyListeners(); }
  void setRatingScale(int v)         { ratingScale     = v; _save(); notifyListeners(); }
  void toggleShowWebInStats(bool v)  { showWebInStats  = v; _save(); notifyListeners(); }

  void changeTheme(int m)            { themeMode       = m; _save(); notifyListeners(); }

  void addBook(Book b)    { books.insert(0, b); _save(); notifyListeners(); }
  void updateBook(Book b) {
    final i = books.indexWhere((x) => x.id == b.id);
    if (i != -1) { books[i] = b; _save(); notifyListeners(); }
  }
  void deleteBook(String id) { books.removeWhere((b) => b.id == id); _save(); notifyListeners(); }

  Future<void> importBooks(List<Book> imported) async {
    books = imported; await _save(); notifyListeners();
  }

  void saveTabIndex(int i) {
    savedTabIndex = i;
    SharedPreferences.getInstance()
        .then((p) => p.setInt('savedTabIndex', savedTabIndex));
  }

  int get completedSeries       => books.where((b) => b.status == BookStatus.completed && b.isSeries).length;
  int get completedWeb          => books.where((b) => b.status == BookStatus.completed && b.isWeb).length;
  int get totalVolumes          => books.fold(0, (s, b) => s + b.effectiveVolumes);
  int get totalWords            => books.fold(0, (s, b) => s + b.effectiveWords);
  bool get anyBooksCountVolumes => books.any((b) => b.countVolumes);
  int countByStatus(BookStatus s) => books.where((b) => b.status == s).length;
}

final appState = AppState();

// ══════════════════════════════════════════════════════════
// ФОРМАТИРОВАНИЕ ЧИСЕЛ
// ══════════════════════════════════════════════════════════

String fmtNum(int n) {
  if (appState.shortenNumbers) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
  }
  return n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ');
}

// ══════════════════════════════════════════════════════════
// МОДЕЛИ ДАННЫХ
// ══════════════════════════════════════════════════════════

enum BookStatus { planned, reading, paused, completed, dropped }

extension BookStatusX on BookStatus {
  String get label => switch (this) {
    BookStatus.planned   => 'В планах',
    BookStatus.reading   => 'Читаю',
    BookStatus.paused    => 'На паузе',
    BookStatus.completed => 'Завершено',
    BookStatus.dropped   => 'Брошено',
  };
  Color get color => appState.statusColor(this);
}

class Book {
  String id, title;
  BookStatus status;
  bool isSeries, isWeb, isSingle, countVolumes, isOngoing, useDetailedVolumes;
  int? words, volumes, totalVolumesInSeries;
  int? webChapters, totalWebChapters;
  Color coverColor;
  String? coverUrl, localImagePath;
  List<Map<String, dynamic>> volumeEntries;

  String? currentBookmark;             
  bool isHybridFormat;                 
  int? hybridWebChapters;              
  int? hybridTotalWebChapters;
  int? rating;                         

  int? startVolume;                    
  int? startChapter;                   

  Book({
    required this.id,
    required this.title,
    required this.status,
    this.isSeries = false,
    this.isWeb = false,
    this.isSingle = false,
    this.countVolumes = true,
    this.words = 0,
    this.volumes = 0,
    this.totalVolumesInSeries,
    this.isOngoing = false,
    this.coverColor = Colors.blueGrey,
    this.coverUrl,
    this.localImagePath,
    this.useDetailedVolumes = false,
    this.webChapters,
    this.totalWebChapters,
    List<Map<String, dynamic>>? volumeEntries,
    
    this.currentBookmark,
    this.isHybridFormat = false,
    this.hybridWebChapters,
    this.hybridTotalWebChapters,
    this.rating,

    this.startVolume,
    this.startChapter,
  }) : volumeEntries = volumeEntries ?? [];

  int get effectiveWords {
    if (useDetailedVolumes && !isWeb) {
      return volumeEntries.fold(0, (s, e) => s + ((e['w'] as num?)?.toInt() ?? 0));
    }
    return words ?? 0;
  }

  int get effectiveVolumes => useDetailedVolumes ? volumeEntries.length : (volumes ?? 0);

  String volumeLabel() {
    if (!countVolumes && !isHybridFormat) return '';
    final v = effectiveVolumes;
    if (isOngoing) return '$v/? т.';
    if (totalVolumesInSeries != null) return '$v/$totalVolumesInSeries т.';
    return '$v т.';
  }

  String chapterLabel() {
    int c = 0;
    int? tot;
    if (isHybridFormat) {
      c = hybridWebChapters ?? 0;
      tot = hybridTotalWebChapters;
    } else {
      c = webChapters ?? 0;
      tot = totalWebChapters;
    }
    if (tot != null) return '$c/$tot гл.';
    return '$c гл.';
  }

  String getRatingDisplay(int scale) {
    if (rating == null) return '';
    if (scale == 5) {
      final val = (rating! / 2).round();
      return '$val/5 ★';
    }
    return '$rating/10 ★';
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'status': status.index,
    'isSeries': isSeries, 'isWeb': isWeb, 'isSingle': isSingle,
    'countVolumes': countVolumes,
    'words': words ?? 0, 'volumes': volumes ?? 0,
    'totalVolumesInSeries': totalVolumesInSeries,
    'isOngoing': isOngoing,
    'coverColor': coverColor.value,
    'coverUrl': coverUrl, 'localImagePath': localImagePath,
    'useDetailedVolumes': useDetailedVolumes,
    'volumeEntries': volumeEntries,
    'webChapters': webChapters,
    'totalWebChapters': totalWebChapters,
    
    'currentBookmark': currentBookmark,
    'isHybridFormat': isHybridFormat,
    'hybridWebChapters': hybridWebChapters,
    'hybridTotalWebChapters': hybridTotalWebChapters,
    'rating': rating,

    'startVolume': startVolume,
    'startChapter': startChapter,
  };

  factory Book.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> entries = [];
    if (j['volumeEntries'] != null) {
      for (final e in (j['volumeEntries'] as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        entries.add({
          'v': (m['v'] as num?)?.toDouble() ?? 0.0,
          'w': (m['w'] as num?)?.toInt() ?? 0,
        });
      }
    }
    return Book(
      id: j['id'] as String,
      title: j['title'] as String,
      status: BookStatus.values[j['status'] as int],
      isSeries: j['isSeries'] as bool? ?? false,
      isWeb: j['isWeb'] as bool? ?? false,
      isSingle: j['isSingle'] as bool? ?? false,
      countVolumes: j['countVolumes'] as bool? ?? true,
      words: j['words'] as int? ?? 0,
      volumes: j['volumes'] as int? ?? 0,
      totalVolumesInSeries: j['totalVolumesInSeries'] as int?,
      isOngoing: j['isOngoing'] as bool? ?? false,
      coverColor: Color(j['coverColor'] as int? ?? Colors.blueGrey.value),
      coverUrl: j['coverUrl'] as String?,
      localImagePath: j['localImagePath'] as String?,
      useDetailedVolumes: j['useDetailedVolumes'] as bool? ?? false,
      volumeEntries: entries,
      webChapters: j['webChapters'] as int?,
      totalWebChapters: j['totalWebChapters'] as int?,
      
      currentBookmark: j['currentBookmark'] as String?,
      isHybridFormat: j['isHybridFormat'] as bool? ?? false,
      hybridWebChapters: j['hybridWebChapters'] as int?,
      hybridTotalWebChapters: j['hybridTotalWebChapters'] as int?,
      rating: j['rating'] as int?,

      startVolume: j['startVolume'] as int?,
      startChapter: j['startChapter'] as int?,
    );
  }
}

// ══════════════════════════════════════════════════════════
// SCROLL BEHAVIOR — Плавный нативный скроллинг
// ══════════════════════════════════════════════════════════

class _Bouncy extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(BuildContext c, Widget child, ScrollableDetails d) => child;
  @override
  ScrollPhysics getScrollPhysics(BuildContext c) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

// ══════════════════════════════════════════════════════════
// ТОЧКА ВХОДА ПРИЛОЖЕНИЯ
// ══════════════════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.load();
  runApp(const _App());
}

class _App extends StatefulWidget {
  const _App();
  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  void _onChange() => setState(() {});

  @override
  void initState() { 
    super.initState(); 
    appState.addListener(_onChange); 
  }
  @override
  void dispose() { 
    appState.removeListener(_onChange); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ReadTracker',
    debugShowCheckedModeBanner: false,
    theme: _buildTheme(appState.themeMode),
    builder: (c, child) => ScrollConfiguration(behavior: _Bouncy(), child: child!),
    home: const _Nav(),
  );
}

// ══════════════════════════════════════════════════════════
// НАВИГАЦИЯ (Разделённые вьюпорты для экономии отрисовки)
// ══════════════════════════════════════════════════════════

class _Nav extends StatefulWidget {
  const _Nav();
  @override
  State<_Nav> createState() => _NavState();
}

class _NavState extends State<_Nav> {
  int _tab = 0;
  void _onChange() { if (mounted) setState(() {}); }

  @override
  void initState() { super.initState(); appState.addListener(_onChange); }
  @override
  void dispose() { appState.removeListener(_onChange); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final fab = FloatingActionButton(
      backgroundColor: kAccent,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: () => Navigator.push(context, _route(const AddEditBookScreen())),
      child: const Icon(Icons.add_rounded, size: 26),
    );

    if (appState.hideBottomBar) {
      return Scaffold(
        body: const LibraryPage(showStatsButton: true),
        floatingActionButton: fab,
      );
    }

    return Scaffold(
      body: IndexedStack(index: _tab, children: const [LibraryPage(), StatisticsPage()]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        Divider(height: 0.5, thickness: 0.5, color: Theme.of(context).dividerColor),
        BottomNavigationBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.library_books_rounded), label: 'Библиотека'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Аналитика'),
          ],
        ),
      ]),
      floatingActionButton: _tab == 0 ? fab : null,
    );
  }
}

// ══════════════════════════════════════════════════════════
// БИБЛИОТЕКА
// ══════════════════════════════════════════════════════════

class LibraryPage extends StatefulWidget {
  final bool showStatsButton;
  const LibraryPage({super.key, this.showStatsButton = false});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  static const _labels  = ['Все', 'Читаю', 'В планах', 'Завершено', 'На паузе', 'Брошено'];
  static const _filters = <BookStatus?>[null, BookStatus.reading, BookStatus.planned, BookStatus.completed, BookStatus.paused, BookStatus.dropped];

  void _onChange() { if (mounted) setState(() {}); }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _labels.length,
      vsync: this,
      initialIndex: appState.savedTabIndex.clamp(0, _labels.length - 1),
    );
    _tabs.addListener(() { if (!_tabs.indexIsChanging) appState.saveTabIndex(_tabs.index); });
    appState.addListener(_onChange);
  }

  @override
  void dispose() {
    appState.removeListener(_onChange);
    _tabs.dispose();
    super.dispose();
  }

  void _shareSheet() => showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(kRl))),
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(kP, 12, kP, kP),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Align(alignment: Alignment.centerLeft,
          child: Text('Поделиться',
            style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w800))),
        const SizedBox(height: 14),
        _ShareOptionTile(
          icon: Icons.analytics_outlined, color: kAccent,
          title: 'Аналитика', sub: 'Карточка со статистикой',
          onTap: () { Navigator.pop(ctx); Navigator.push(context, _route(const ShareAnalyticsPage())); },
        ),
        const SizedBox(height: kPs),
        _ShareOptionTile(
          icon: Icons.format_list_bulleted_rounded, color: kSReading,
          title: 'Список тайтлов', sub: 'Все тайтлы в одной карточке',
          onTap: () { Navigator.pop(ctx); Navigator.push(context, _route(const ShareLibraryPage())); },
        ),
      ]),
    )),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 46, // Оптимальная высота toolbar
        titleSpacing: kP,
        title: Text(
          'Библиотека',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22, 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          if (widget.showStatsButton)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Material(
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(kRs + 2),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: const Icon(Icons.bar_chart_rounded, color: kAccent),
                    onPressed: () => Navigator.push(context, _route(const StatisticsPage())),
                  ),
                ),
              ),
            ),
          if (appState.showShareButton)
            SizedBox(
              width: 36,
              height: 36,
              child: Material(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(kRs + 2),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 17,
                  icon: const Icon(Icons.ios_share_rounded, color: kAccent),
                  onPressed: _shareSheet,
                ),
              ),
            ),
          const SizedBox(width: kP),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28), // Вернули высоту зоны вкладок для прежней пропорции
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(bottom: 2), 
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicator: UnderlineTabIndicator(
                borderSide: const BorderSide(color: kAccent, width: 2.2),
                borderRadius: BorderRadius.circular(2),
              ),
              labelColor: kAccent,
              unselectedLabelColor: Colors.grey,
              labelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700), // Вернули шрифт 13
              unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500), // Вернули шрифт 13
              labelPadding: const EdgeInsets.symmetric(horizontal: 10),
              tabs: _labels.map((t) => Tab(height: 26, text: t)).toList(), // Вернули оригинальную высоту вкладок 26
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: List.generate(_filters.length, (i) => _BookList(filter: _filters[i])),
      ),
    );
  }
}

void _confirmDelete(BuildContext context, Book book) {
  showDialog(
    context: context,
    builder: (dlg) => AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRl)),
      title: Text('Удалить тайтл?',
        style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w800)),
      content: Text('«${book.title}» будет удалён без возможности восстановления.',
        style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dlg),
          child: Text('Отмена',
            style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontWeight: FontWeight.w600))),
        TextButton(
          onPressed: () { Navigator.pop(dlg); appState.deleteBook(book.id); },
          child: Text('Удалить',
            style: GoogleFonts.plusJakartaSans(color: kSDropped, fontWeight: FontWeight.w700))),
      ],
    ),
  );
}

class _BookList extends StatelessWidget {
  final BookStatus? filter;
  const _BookList({this.filter});

  @override
  Widget build(BuildContext context) {
    final books = filter == null
        ? appState.books
        : appState.books.where((b) => b.status == filter).toList();

    if (books.isEmpty) return _Empty();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 100), 
      itemCount: books.length,
      itemBuilder: (ctx, i) {
        final book = books[i];
        return appState.showCovers
            ? BookCardCover(book: book)
            : BookCardCompact(book: book);
      },
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(color: kAccentDim, shape: BoxShape.circle),
        child: const Icon(Icons.menu_book_rounded, size: 40, color: kAccent),
      ),
      const SizedBox(height: 16),
      Text('Список пуст',
        style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Нажмите + чтобы добавить тайтл',
        style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.grey)),
    ]),
  );
}

class BookCardCover extends StatelessWidget {
  final Book book;
  const BookCardCover({super.key, required this.book});

  Widget _cover() {
    if (book.localImagePath?.isNotEmpty == true) {
      return Image.file(
        File(book.localImagePath!), 
        fit: BoxFit.cover,
        cacheWidth: 156, 
      );
    }
    if (book.coverUrl?.isNotEmpty == true) {
      return CachedNetworkImage(
        imageUrl: book.coverUrl!, 
        fit: BoxFit.cover,
        memCacheWidth: 156, 
        placeholder: (_, __) => Container(color: book.coverColor.withOpacity(0.3)),
        errorWidget: (_, __, ___) => Center(
          child: Icon(Icons.broken_image_rounded, color: Colors.grey.shade600, size: 20)),
      );
    }
    return Center(child: Icon(Icons.image_rounded, color: Colors.grey.shade600, size: 22));
  }

  @override
  Widget build(BuildContext context) {
    final sc  = book.status.color;
    final vol = book.volumeLabel();
    final ratingStr = appState.enableRating ? book.getRatingDisplay(appState.ratingScale) : '';

    return GestureDetector(
      onTap: () => Navigator.push(context, _route(AddEditBookScreen(book: book))),
      onLongPress: () => _confirmDelete(context, book),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: kP, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(kR),
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(kRs),
            child: Container(width: 52, height: 74, color: book.coverColor, child: _cover()),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                Expanded(
                  child: Text(book.title,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (ratingStr.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ratingStr,
                      style: GoogleFonts.plusJakartaSans(
                        color: kAccent, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 5),
            Wrap(spacing: 5, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7,
                    decoration: BoxDecoration(color: sc, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(book.status.label,
                    style: GoogleFonts.plusJakartaSans(
                      color: sc, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
                if (book.isHybridFormat) _Badge('LN+WN', kAccent),
                if (book.isSeries && !book.isHybridFormat) _Badge('Серия',  kSCompleted),
                if (book.isWeb && !book.isHybridFormat)    _Badge('Веб',    kSPaused),
                if (book.isSingle) _Badge('Сингл',  kAccent),
                if (book.isOngoing) _Badge('Онг.',   kSReading),
                
                if (appState.enableAdaptationStart) ...[
                  if (book.startVolume != null && (book.isSeries || book.isSingle))
                    _Badge('Старт: т. ${book.startVolume}', kSReading),
                  if (book.startChapter != null && (book.isWeb || book.isHybridFormat))
                    _Badge('Старт: гл. ${book.startChapter}', kSReading),
                ],
              ]),
            const SizedBox(height: 5),
            Row(children: [
              const Icon(Icons.text_fields_rounded, size: 11, color: Colors.grey),
              const SizedBox(width: 3),
              Text('${fmtNum(book.effectiveWords)} сл.',
                style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 11)),
              
              if ((book.countVolumes || book.isHybridFormat) && vol.isNotEmpty) ...[
                const SizedBox(width: 10),
                const Icon(Icons.layers_rounded, size: 11, color: Colors.grey),
                const SizedBox(width: 3),
                Text(vol, style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 11)),
              ],
              
              if ((book.isWeb || book.isHybridFormat) && appState.showWebChapters) ...[
                const SizedBox(width: 10),
                const Icon(Icons.format_list_numbered_rounded, size: 11, color: Colors.grey),
                const SizedBox(width: 3),
                Text(book.chapterLabel(),
                  style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 11)),
              ],

              if (appState.showBookmarks && 
                  appState.bookmarkPosition == 1 && 
                  book.currentBookmark != null && 
                  book.currentBookmark!.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                const Icon(Icons.bookmark_rounded, size: 11, color: kAccent),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    book.currentBookmark!,
                    style: GoogleFonts.plusJakartaSans(color: kAccent, fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ]),
            
            if (appState.showBookmarks && 
                appState.bookmarkPosition == 0 && 
                book.currentBookmark != null && 
                book.currentBookmark!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.bookmark_rounded, size: 11, color: kAccent),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    book.currentBookmark!,
                    style: GoogleFonts.plusJakartaSans(color: kAccent, fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ]
          ])),
          const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
        ]),
      ),
    );
  }
}

class BookCardCompact extends StatelessWidget {
  final Book book;
  const BookCardCompact({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final sc  = book.status.color;
    final vol = book.volumeLabel();
    final ratingStr = appState.enableRating ? book.getRatingDisplay(appState.ratingScale) : '';

    return GestureDetector(
      onTap: () => Navigator.push(context, _route(AddEditBookScreen(book: book))),
      onLongPress: () => _confirmDelete(context, book),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: kP, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(kR),
        ),
        child: Row(children: [
          Container(width: 3, height: 40,
            decoration: BoxDecoration(color: sc, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(book.title,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              if (ratingStr.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(ratingStr, style: GoogleFonts.plusJakartaSans(
                    color: kAccent, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 4),
              ],
              if (book.isHybridFormat) _Badge('LN+WN', kAccent),
              if (book.isSeries && !book.isHybridFormat) _Badge('Серия',  kSCompleted),
              if (book.isWeb && !book.isHybridFormat)    _Badge('Веб',    kSPaused),
              if (book.isSingle) _Badge('Сингл',  kAccent),
              if (book.isOngoing) _Badge('Онг.',   kSReading),
              
              if (appState.enableAdaptationStart) ...[
                if (book.startVolume != null && (book.isSeries || book.isSingle))
                  _Badge('Старт: т. ${book.startVolume}', kSReading),
                if (book.startChapter != null && (book.isWeb || book.isHybridFormat))
                  _Badge('Старт: гл. ${book.startChapter}', kSReading),
              ],
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Text(book.status.label,
                style: GoogleFonts.plusJakartaSans(color: sc, fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              const Icon(Icons.text_fields_rounded, size: 11, color: Colors.grey),
              const SizedBox(width: 3),
              Text('${fmtNum(book.effectiveWords)} сл.',
                style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 11)),
              if ((book.countVolumes || book.isHybridFormat) && vol.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Icon(Icons.layers_rounded, size: 11, color: Colors.grey),
                const SizedBox(width: 3),
                Text(vol, style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 11)),
              ],
              if ((book.isWeb || book.isHybridFormat) && appState.showWebChapters) ...[
                const SizedBox(width: 8),
                const Icon(Icons.format_list_numbered_rounded, size: 11, color: Colors.grey),
                const SizedBox(width: 3),
                Text(book.chapterLabel(),
                  style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 11)),
              ],

              if (appState.showBookmarks && 
                  appState.bookmarkPosition == 1 && 
                  book.currentBookmark != null && 
                  book.currentBookmark!.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                const Icon(Icons.bookmark_rounded, size: 11, color: kAccent),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    book.currentBookmark!,
                    style: GoogleFonts.plusJakartaSans(color: kAccent, fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ]),

            if (appState.showBookmarks && 
                appState.bookmarkPosition == 0 && 
                book.currentBookmark != null && 
                book.currentBookmark!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.bookmark_rounded, size: 11, color: kAccent),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    book.currentBookmark!,
                    style: GoogleFonts.plusJakartaSans(color: kAccent, fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ]
          ])),
          const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 2),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(label, style: GoogleFonts.plusJakartaSans(
      color: color, fontSize: 10, fontWeight: FontWeight.w700)),
  );
}

// ══════════════════════════════════════════════════════════
// ДОБАВИТЬ / РЕДАКТИРОВАТЬ
// ══════════════════════════════════════════════════════════

class _VolCtrl {
  final TextEditingController vol, words;
  _VolCtrl({String v = '', String w = ''})
      : vol   = TextEditingController(text: v),
        words = TextEditingController(text: w);
  void dispose() { vol.dispose(); words.dispose(); }
}

const _kStepTitles = ['Тайтл', 'Статус', 'Данные'];

class AddEditBookScreen extends StatefulWidget {
  final Book? book;
  const AddEditBookScreen({super.key, this.book});
  @override
  State<AddEditBookScreen> createState() => _AddEditState();
}

class _AddEditState extends State<AddEditBookScreen> with SingleTickerProviderStateMixin {
  late TextEditingController _title, _words, _vols, _totalVols;
  late TextEditingController _webChaps, _totalWebChaps;
  
  late TextEditingController _bookmarkCtrl;
  late TextEditingController _hybridWebChaps;
  late TextEditingController _hybridTotalWebChaps;

  late TextEditingController _startVolumeCtrl;
  late TextEditingController _startChapterCtrl;

  late BookStatus _status;
  late bool _isSeries, _isWeb, _isSingle, _countVols, _detailed, _ongoing;
  
  late bool _isHybridFormat;
  int? _ratingValue;

  String? _coverUrl, _localImg;
  Color   _coverColor = Colors.indigo.shade900;
  final   _picker = ImagePicker();
  
  List<_VolCtrl> _volCtrls = [];

  final _pageCtrl = PageController();
  int _step = 0;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _title     = TextEditingController(text: b?.title ?? '');
    _words     = TextEditingController(text: b?.words?.toString() ?? '0');
    _vols      = TextEditingController(text: b?.volumes?.toString() ?? '0');
    _totalVols = TextEditingController(text: b?.totalVolumesInSeries?.toString() ?? '');
    _webChaps      = TextEditingController(text: b?.webChapters?.toString() ?? '0');
    _totalWebChaps = TextEditingController(text: b?.totalWebChapters?.toString() ?? '0');
    
    _bookmarkCtrl  = TextEditingController(text: b?.currentBookmark ?? '');
    _hybridWebChaps = TextEditingController(text: b?.hybridWebChapters?.toString() ?? '0');
    _hybridTotalWebChaps = TextEditingController(text: b?.hybridTotalWebChapters?.toString() ?? '0');

    _startVolumeCtrl = TextEditingController(text: b?.startVolume?.toString() ?? '');
    _startChapterCtrl = TextEditingController(text: b?.startChapter?.toString() ?? '');

    _status    = b?.status ?? BookStatus.planned;
    _isSeries  = b?.isSeries  ?? false;
    _isWeb     = b?.isWeb     ?? false;
    _isSingle  = b?.isSingle  ?? false;
    _countVols = b?.countVolumes ?? true;
    _detailed  = b?.useDetailedVolumes ?? false;
    _ongoing   = b?.isOngoing ?? false;
    _coverUrl  = b?.coverUrl;
    _localImg  = b?.localImagePath;
    _coverColor = b?.coverColor ?? Colors.indigo.shade900;

    _isHybridFormat  = b?.isHybridFormat ?? false;
    _ratingValue     = b?.rating;

    if (_detailed && b != null && b.volumeEntries.isNotEmpty) {
      _volCtrls = b.volumeEntries.map((e) {
        final vn = e['v'] as double? ?? 0.0;
        return _VolCtrl(
          v: vn == vn.truncateToDouble() ? vn.toInt().toString() : vn.toString(),
          w: (e['w'] as int? ?? 0).toString(),
        );
      }).toList();
    } else if (_detailed) {
      _volCtrls = [_VolCtrl(v: '1', w: '')];
    }
  }

  @override
  void dispose() {
    _title.dispose(); _words.dispose(); _vols.dispose(); _totalVols.dispose();
    _webChaps.dispose(); _totalWebChaps.dispose();
    _bookmarkCtrl.dispose(); _hybridWebChaps.dispose(); _hybridTotalWebChaps.dispose();
    _startVolumeCtrl.dispose(); _startChapterCtrl.dispose();
    _pageCtrl.dispose();
    for (final c in _volCtrls) c.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step);
    _pageCtrl.animateToPage(step,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut);
  }

  void _next() {
    if (_step < 2) _goTo(_step + 1);
    else _save();
  }

  void _back() {
    if (_step > 0) _goTo(_step - 1);
    else Navigator.pop(context);
  }

  void _toggleDetailed(bool v) {
    setState(() {
      _detailed = v;
      if (v && _volCtrls.isEmpty) _volCtrls = [_VolCtrl(v: '1', w: '')];
      if (!v) {
        _words.text = _volCtrls.fold(0, (s, c) => s + (int.tryParse(c.words.text) ?? 0)).toString();
        _vols.text  = _volCtrls.length.toString();
      }
    });
  }

  void _addVol() {
    double next = 1;
    if (_volCtrls.isNotEmpty) {
      final last = double.tryParse(_volCtrls.last.vol.text) ?? _volCtrls.length.toDouble();
      next = last + 1;
    }
    final s = next == next.truncateToDouble() ? next.toInt().toString() : next.toString();
    setState(() => _volCtrls.add(_VolCtrl(v: s, w: '')));
  }

  void _removeVol(int i) => setState(() { _volCtrls[i].dispose(); _volCtrls.removeAt(i); });

  void _save() {
    final vEntries = _detailed
        ? _volCtrls.map((c) => {
            'v': double.tryParse(c.vol.text) ?? 0.0,
            'w': int.tryParse(c.words.text)  ?? 0,
          }).toList()
        : <Map<String, dynamic>>[];

    int calculatedWords = 0;
    if (!_isWeb && _detailed) {
      calculatedWords = _volCtrls.fold(0, (s, c) => s + (int.tryParse(c.words.text) ?? 0));
    } else {
      calculatedWords = int.tryParse(_words.text) ?? 0;
    }

    final book = Book(
      id: widget.book?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _title.text.trim().isEmpty ? 'Без названия' : _title.text.trim(),
      status: _status,
      isSeries: _isSeries, isWeb: _isWeb, isSingle: _isSingle,
      countVolumes: _countVols,
      words:   calculatedWords,
      volumes: int.tryParse(_vols.text)   ?? 0,
      totalVolumesInSeries: (_ongoing || _totalVols.text.isEmpty) ? null : int.tryParse(_totalVols.text),
      isOngoing: _ongoing,
      coverUrl: _coverUrl, localImagePath: _localImg, coverColor: _coverColor,
      useDetailedVolumes: _detailed, 
      volumeEntries: vEntries,
      webChapters: _isWeb ? (int.tryParse(_webChaps.text) ?? 0) : null,
      totalWebChapters: _isWeb && _totalWebChaps.text.isNotEmpty ? int.tryParse(_totalWebChaps.text) : null,
      
      currentBookmark: _bookmarkCtrl.text,
      isHybridFormat: _isHybridFormat,
      hybridWebChapters: _isHybridFormat ? (int.tryParse(_hybridWebChaps.text) ?? 0) : null,
      hybridTotalWebChapters: _isHybridFormat && _hybridTotalWebChaps.text.isNotEmpty ? int.tryParse(_hybridTotalWebChaps.text) : null,
      rating: appState.enableRating ? _ratingValue : null,

      startVolume: appState.enableAdaptationStart && (_isSeries || _isSingle) ? int.tryParse(_startVolumeCtrl.text) : null,
      startChapter: appState.enableAdaptationStart && (_isWeb || _isHybridFormat) ? int.tryParse(_startChapterCtrl.text) : null,
    );

    widget.book == null ? appState.addBook(book) : appState.updateBook(book);
    Navigator.pop(context);
  }

  void _pickImage() => showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRl))),
    builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.symmetric(vertical: kPs),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _PickerTile(Icons.photo_library_rounded, 'Из галереи', () async {
          Navigator.pop(ctx);
          final f = await _picker.pickImage(source: ImageSource.gallery);
          if (f != null) setState(() { _localImg = f.path; _coverUrl = null; });
        }),
        _PickerTile(Icons.link_rounded, 'По URL', () {
          Navigator.pop(ctx); _askUrl();
        }),
      ]),
    )),
  );

  Future<void> _askUrl() async {
    final ctrl = TextEditingController(text: _coverUrl ?? '');
    final url  = await showDialog<String>(context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRl)),
        title: Text('URL обложки',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 17)),
        content: TextField(controller: ctrl,
          decoration: const InputDecoration(hintText: 'Вставьте ссылку...'),
          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: GoogleFonts.plusJakartaSans(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text('Сохранить',
              style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.w700))),
        ],
      ));
    if (url != null && url.isNotEmpty) setState(() { _coverUrl = url; _localImg = null; });
  }

  Widget? _coverWidget() {
    if (_localImg?.isNotEmpty == true) {
      return Image.file(File(_localImg!), fit: BoxFit.cover, cacheWidth: 200);
    }
    if (_coverUrl?.isNotEmpty == true) {
      return CachedNetworkImage(
        imageUrl: _coverUrl!, 
        fit: BoxFit.cover,
        memCacheWidth: 200,
        placeholder: (_, __) => const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
        errorWidget: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_rounded, color: Colors.grey)));
    }
    return null;
  }

  bool get _hasCover => (_localImg?.isNotEmpty == true) || (_coverUrl?.isNotEmpty == true);

  int get _totalDetailed => _volCtrls.fold(0, (s, c) => s + (int.tryParse(c.words.text) ?? 0));

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final card     = Theme.of(context).cardColor;
    final isEdit   = widget.book != null;

    if (isEdit) return _buildEditForm(context, isDark, card);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(_step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded),
          onPressed: _back,
        ),
        title: const Text('Добавить тайтл'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _StepIndicator(current: _step, onTap: _goTo),
        ),
      ),
      body: PageView(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _StepCover(
            hasCover: _hasCover,
            coverColor: _coverColor,
            coverChild: _hasCover ? _coverWidget() : null,
            title: _title,
            onPickImage: _pickImage,
            isDark: isDark,
          ),
          _StepStatus(
            status: _status,
            isSeries: _isSeries, isWeb: _isWeb, isSingle: _isSingle,
            countVols: _countVols,
            card: card, isDark: isDark,
            
            enableHybrid: appState.enableHybrid,
            isHybrid: _isHybridFormat,
            onHybridChanged: (v) {
              setState(() {
                _isHybridFormat = v;
                if (v) {
                  _isWeb = false;
                  _isSeries = true;
                  _isSingle = false;
                  _countVols = true;
                }
              });
            },

            onStatus: (s) => setState(() => _status = s),
            onSeries: (v) => setState(() { _isSeries = v; if (v) { _isWeb = false; _isSingle = false; _isHybridFormat = false; } }),
            onWeb:    (v) => setState(() { _isWeb    = v; if (v) { _isSeries = false; _isSingle = false; _countVols = false; _isHybridFormat = false; } else { _countVols = true; } }),
            onSingle: (v) => setState(() { _isSingle = v; if (v) { _isSeries = false; _isWeb = false; _isHybridFormat = false; } }),
            onCountVols: (v) => setState(() => _countVols = v),
          ),
          _StepData(
            words: _words, vols: _vols, totalVols: _totalVols,
            webChaps: _webChaps, totalWebChaps: _totalWebChaps,
            countVols: _countVols, detailed: _detailed, ongoing: _ongoing,
            isWeb: _isWeb,
            volCtrls: _volCtrls,
            totalDetailed: _totalDetailed,
            onToggleDetailed: _toggleDetailed,
            onToggleOngoing: (v) => setState(() => _ongoing = v),
            onAddVol: _addVol,
            onRemoveVol: _removeVol,
            onChanged: () => setState(() {}),
            card: card,
            
            showBookmarks: appState.showBookmarks,
            bookmarkCtrl: _bookmarkCtrl,
            isHybrid: _isHybridFormat,
            hybridWebChaps: _hybridWebChaps,
            hybridTotalWebChaps: _hybridTotalWebChaps,

            enableRating: appState.enableRating,
            ratingScale: appState.ratingScale,
            ratingValue: _ratingValue,
            onRatingChanged: (v) => setState(() => _ratingValue = v),

            enableAdaptationStart: appState.enableAdaptationStart,
            startVolumeCtrl: _startVolumeCtrl,
            startChapterCtrl: _startChapterCtrl,
            isSeries: _isSeries,
            isSingle: _isSingle,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kP, 0, kP, kP),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kR)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  _step < 2 ? 'Далее' : 'Добавить',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 6),
                Icon(
                  _step < 2 ? Icons.arrow_forward_rounded : Icons.check_rounded,
                  color: Colors.white, size: 20),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditForm(BuildContext context, bool isDark, Color card) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded, color: kAccent),
            onPressed: _save,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(kP, kP, kP, 60), children: [

        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 80, height: 110,
              decoration: BoxDecoration(
                color: _hasCover ? _coverColor : Colors.transparent,
                borderRadius: BorderRadius.circular(kRs),
                boxShadow: _hasCover ? [BoxShadow(
                  color: _coverColor.withOpacity(0.3),
                  blurRadius: 10, offset: const Offset(0, 4))] : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(kRs),
                child: _hasCover && _coverWidget() != null
                    ? Stack(children: [
                        Positioned.fill(child: _coverWidget()!),
                        Positioned(bottom: 0, left: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            color: Colors.black.withOpacity(0.55),
                            child: Center(child: Text('Изменить',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white, fontSize: 9,
                                fontWeight: FontWeight.w700))))),
                      ])
                    : CustomPaint(
                        painter: _DashedBorderPainter(),
                        child: Center(child: Column(
                          mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.camera_alt_rounded, color: kAccent, size: 24),
                          const SizedBox(height: 4),
                          Text('Обложка',
                            style: GoogleFonts.plusJakartaSans(
                              color: kAccent, fontSize: 9, fontWeight: FontWeight.w700)),
                        ])),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 2),
            _SectionLabel('НАЗВАНИЕ'),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(hintText: 'Введите название...'),
            ),
          ])),
        ]),
        const SizedBox(height: kPl),

        _SectionLabel('СТАТУС'),
        Wrap(spacing: kPs, runSpacing: kPs,
          children: BookStatus.values.map((s) {
            final sel = _status == s;
            return GestureDetector(
              onTap: () => setState(() => _status = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? s.color.withOpacity(0.12) : card,
                  borderRadius: BorderRadius.circular(kRs + 2),
                  border: Border.all(
                    color: sel ? s.color : (isDark ? Colors.white12 : Colors.black12),
                    width: sel ? 1.5 : 1)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(s.label, style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? s.color : null)),
                ]),
              ),
            );
          }).toList()),
        const SizedBox(height: kPl),

        _SectionLabel('ФОРМАТ ИЗДАНИЯ'),
        
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(kR),
          ),
          child: Column(
            children: [
              if (appState.enableHybrid) ...[
                RadioListTile<bool>(
                  value: true,
                  groupValue: _isHybridFormat,
                  activeColor: kAccent,
                  title: Text(
                    'LN+WN Гибрид',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Комплексный формат (LN тома + WN онгоинг главы)',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey),
                  ),
                  secondary: const Icon(Icons.bolt_rounded),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _isHybridFormat = val;
                        _isWeb = false;
                        _isSeries = true;
                        _isSingle = false;
                        _countVols = true;
                      });
                    }
                  },
                ),
                Divider(height: 1, indent: kP, endIndent: kP, color: Theme.of(context).dividerColor),
              ],
              RadioListTile<String>(
                value: 'series',
                groupValue: _isHybridFormat ? 'hybrid' : (_isSeries ? 'series' : (_isWeb ? 'web' : 'single')),
                activeColor: kAccent,
                title: Text(
                  'Серия томов',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'Серийное издание печатных томов (LN / Книги)',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey),
                ),
                secondary: const Icon(Icons.layers_rounded),
                onChanged: (val) {
                  setState(() {
                    _isHybridFormat = false;
                    _isSeries = true;
                    _isWeb = false;
                    _isSingle = false;
                    _countVols = true;
                  });
                },
              ),
              Divider(height: 1, indent: kP, endIndent: kP, color: Theme.of(context).dividerColor),
              RadioListTile<String>(
                value: 'web',
                groupValue: _isHybridFormat ? 'hybrid' : (_isSeries ? 'series' : (_isWeb ? 'web' : 'single')),
                activeColor: kAccent,
                title: Text(
                  'Веб-новелла',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'Азиатские веб-романы, разбитые строго по главам (WN)',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey),
                ),
                secondary: const Icon(Icons.language_rounded),
                onChanged: (val) {
                  setState(() {
                    _isHybridFormat = false;
                    _isSeries = false;
                    _isWeb = true;
                    _isSingle = false;
                    _countVols = false;
                  });
                },
              ),
              Divider(height: 1, indent: kP, endIndent: kP, color: Theme.of(context).dividerColor),
              RadioListTile<String>(
                value: 'single',
                groupValue: _isHybridFormat ? 'hybrid' : (_isSeries ? 'series' : (_isWeb ? 'web' : 'single')),
                activeColor: kAccent,
                title: Text(
                  'Сингл (Одиночное)',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'Одиночный роман (Оношот / Том-сингл)',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey),
                ),
                secondary: const Icon(Icons.menu_book_rounded),
                onChanged: (val) {
                  setState(() {
                    _isHybridFormat = false;
                    _isSeries = false;
                    _isWeb = false;
                    _isSingle = true;
                    _countVols = true;
                  });
                },
              ),
            ],
          ),
        ),
        
        if (!_isWeb && !_isHybridFormat) ...[
          const SizedBox(height: 12),
          _CardGroup(children: [
            _SwitchRow('Учитывать тома', _countVols, 'Отключите для изданий без томов',
              (v) => setState(() => _countVols = v)),
          ]),
        ],
        const SizedBox(height: kPl),

        if (appState.showBookmarks) ...[
          _SectionLabel('ЗАКЛАДКА'),
          TextField(
            controller: _bookmarkCtrl,
            decoration: const InputDecoration(
              hintText: 'Пример: 1.4 глава, 2х3.1 арка...',
              prefixIcon: Icon(Icons.bookmark_rounded, size: 18, color: kAccent)),
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
          ),
          const SizedBox(height: kPl),
        ],

        if (appState.enableAdaptationStart) ...[
          _SectionLabel('СТАРТ ПОСЛЕ АДАПТАЦИИ'),
          if (_isSeries || _isSingle) ...[
            TextField(
              controller: _startVolumeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Начальный том (с какого начали)',
                prefixIcon: Icon(Icons.play_arrow_rounded, color: kAccent),
              ),
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
            ),
          ],
          if (_isWeb || _isHybridFormat) ...[
            if (_isSeries || _isSingle) const SizedBox(height: kPs),
            TextField(
              controller: _startChapterCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Начальная глава (с какой начали)',
                prefixIcon: Icon(Icons.play_arrow_rounded, color: kAccent),
              ),
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
            ),
          ],
          const SizedBox(height: kPl),
        ],

        if (appState.enableRating) ...[
          _SectionLabel('ОЦЕНКА ТАЙТЛА'),
          _buildRatingSelector(),
          const SizedBox(height: kPl),
        ],

        if (_isWeb || _isHybridFormat) ...[
          _SectionLabel(_isHybridFormat ? 'ПРОГРЕСС ВЕБ-ГЛАВ (В ГИБРИДЕ)' : 'ПРОГРЕСС ГЛАВ'),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SectionLabel('ПРОЧИТАНО'),
              TextField(
                controller: _isHybridFormat ? _hybridWebChaps : _webChaps, 
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.format_list_numbered_rounded, size: 18, color: Colors.grey))),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SectionLabel('ВСЕГО'),
              TextField(
                controller: _isHybridFormat ? _hybridTotalWebChaps : _totalWebChaps, 
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Необяз.',
                  prefixIcon: Icon(Icons.bookmark_border_rounded, size: 18, color: Colors.grey))),
            ])),
          ]),
          const SizedBox(height: kPl),
        ],

        _SectionLabel('СЛОВА / РАСЧЁТ'),
        if (!_isWeb && _countVols) ...[
          _CardGroup(children: [
            _SwitchRow('Расчёт по томам', _detailed,
              _detailed ? 'Слова по каждому тому' : 'Ввести суммарно',
              _toggleDetailed),
          ]),
          const SizedBox(height: 12),
        ],

        if (!_isWeb && _detailed) ...[
          ..._volCtrls.asMap().entries.map((entry) {
            final i = entry.key; final c = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: kPs),
              child: Row(children: [
                SizedBox(width: 76, child: TextField(
                  controller: c.vol,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Том'),
                )),
                const SizedBox(width: kPs),
                Expanded(child: TextField(
                  controller: c.words, keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Слов'),
                )),
                const SizedBox(width: kPs),
                GestureDetector(
                  onTap: () => _removeVol(i),
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: kSDropped.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(kRs)),
                    child: const Icon(Icons.remove_rounded, color: kSDropped, size: 18)),
                ),
              ]),
            );
          }),
          OutlinedButton.icon(
            onPressed: _addVol,
            icon: const Icon(Icons.add_rounded, color: kAccent, size: 18),
            label: Text('Добавить том',
              style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kR)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              minimumSize: const Size(double.infinity, 0)),
          ),
          if (_volCtrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 12),
              decoration: BoxDecoration(
                color: kAccentDim, borderRadius: BorderRadius.circular(kR),
                border: Border.all(color: kAccent.withOpacity(0.2))),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Томов: ${_volCtrls.length}',
                  style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.w700)),
                Text('Слов: ${fmtNum(_totalDetailed)}',
                  style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ] else ...[
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SectionLabel('СЛОВ'),
              TextField(controller: _words, keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.text_fields_rounded, size: 18, color: Colors.grey))),
            ])),
            if (_countVols) ...[
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _SectionLabel('ТОМОВ'),
                TextField(controller: _vols, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.layers_rounded, size: 18, color: Colors.grey))),
              ])),
            ],
          ]),
        ],

        if (_countVols) ...[
          const SizedBox(height: kPl),
          _SectionLabel('ВСЕГО ТОМОВ В СЕРИИ'),
          _CardGroup(children: [
            _SwitchRow('Онгоинг', _ongoing,
              _ongoing ? 'Отображается как 5/?' : 'Кол-во томов известно',
              (v) => setState(() => _ongoing = v)),
          ]),
          if (!_ongoing) ...[
            const SizedBox(height: kPs),
            TextField(controller: _totalVols, keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Необязательно — напр. 25',
                prefixIcon: Icon(Icons.bookmark_border_rounded, size: 18, color: Colors.grey))),
          ],
        ],
      ]),
    );
  }

  Widget _buildRatingSelector() {
    final scale = appState.ratingScale;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kR),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(scale, (index) {
              final starVal = index + 1;
              bool isActive = false;
              if (_ratingValue != null) {
                if (scale == 5) {
                  isActive = (_ratingValue! / 2).round() >= starVal;
                } else {
                  isActive = _ratingValue! >= starVal;
                }
              }
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (scale == 5) {
                      _ratingValue = starVal * 2;
                    } else {
                      _ratingValue = starVal;
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    isActive ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isActive ? kAccent : Colors.grey.shade600,
                    size: scale == 5 ? 32 : 24,
                  ),
                ),
              );
            }),
          ),
          if (_ratingValue != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Выбрано: ${scale == 5 ? (_ratingValue! / 2).round() : _ratingValue} из $scale',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w700, color: kAccent),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _ratingValue = null),
                  child: Text(
                    'Сбросить',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: kSDropped, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          ],
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  const _StepIndicator({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kP, 0, kP, 12),
      child: Row(children: List.generate(3, (i) {
        final done   = i < current;
        final active = i == current;
        return Expanded(child: GestureDetector(
          onTap: () { if (done) onTap(i); },
          child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                height: 3,
                decoration: BoxDecoration(
                  color: active || done ? kAccent : Colors.grey.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 5),
              Text(_kStepTitles[i],
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? kAccent : done ? Colors.grey : Colors.grey.withOpacity(0.5),
                )),
            ]),
          ),
        ));
      })),
    );
  }
}

class _StepCover extends StatelessWidget {
  final bool hasCover;
  final Color coverColor;
  final Widget? coverChild;
  final TextEditingController title;
  final VoidCallback onPickImage;
  final bool isDark;
  const _StepCover({
    required this.hasCover, required this.coverColor,
    required this.coverChild, required this.title,
    required this.onPickImage, required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(kP, kPl, kP, kP),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: GestureDetector(
          onTap: onPickImage,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 200, width: 138,
            decoration: BoxDecoration(
              color: hasCover ? coverColor : Colors.transparent,
              borderRadius: BorderRadius.circular(kR + 4),
              boxShadow: hasCover ? [BoxShadow(
                color: coverColor.withOpacity(0.35),
                blurRadius: 24, offset: const Offset(0, 8))] : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kR + 4),
              child: Stack(children: [
                if (hasCover && coverChild != null)
                  Positioned.fill(child: coverChild!),
                if (!hasCover)
                  Positioned.fill(child: CustomPaint(
                    painter: _DashedBorderPainter(),
                    child: Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.camera_alt_rounded,
                        color: kAccent, size: 32),
                      const SizedBox(height: 8),
                      Text('Обложка',
                        style: GoogleFonts.plusJakartaSans(
                          color: kAccent, fontSize: 11,
                          fontWeight: FontWeight.w700)),
                    ])),
                  )),
                if (hasCover)
                  Positioned(bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent,
                            Colors.black.withOpacity(0.72)])),
                      child: Center(child: Text('Изменить',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.w700))))),
              ]),
            ),
          ),
        )),

        const SizedBox(height: kPl + 8),

        Text('НАЗВАНИЕ',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.grey, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: kPs),
        TextField(
          controller: title,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.w600),
          decoration: const InputDecoration(hintText: 'Введите название...'),
        ),

        const SizedBox(height: kP),
        Row(children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text('Обложка необязательна',
            style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _StepStatus extends StatelessWidget {
  final BookStatus status;
  final bool isSeries, isWeb, isSingle, countVols, isDark;
  final Color card;
  final ValueChanged<BookStatus> onStatus;
  final ValueChanged<bool> onSeries, onWeb, onSingle, onCountVols;

  final bool enableHybrid;
  final bool isHybrid;
  final ValueChanged<bool> onHybridChanged;

  const _StepStatus({
    required this.status, required this.isSeries, required this.isWeb,
    required this.isSingle, required this.countVols, required this.isDark,
    required this.card, required this.onStatus, required this.onSeries,
    required this.onWeb, required this.onSingle, required this.onCountVols,
    required this.enableHybrid, required this.isHybrid, required this.onHybridChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(kP, kPl, kP, kP),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Text('СТАТУС',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.grey, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: kPs),

        ...BookStatus.values.map((s) {
          final sel = status == s;
          return Padding(
            padding: const EdgeInsets.only(bottom: kPs - 2),
            child: GestureDetector(
              onTap: () => onStatus(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 13),
                decoration: BoxDecoration(
                  color: sel ? s.color.withOpacity(0.10) : card,
                  borderRadius: BorderRadius.circular(kR),
                  border: Border.all(
                    color: sel ? s.color : (isDark ? Colors.white12 : Colors.black12),
                    width: sel ? 1.5 : 1)),
                child: Row(children: [
                  Container(width: 10, height: 10,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? s.color : null))),
                  if (sel)
                    Icon(Icons.check_circle_rounded, color: s.color, size: 18),
                ]),
              ),
            ),
          );
        }),

        const SizedBox(height: kP),
        Text('ФОРМАТ ИЗДАНИЯ',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.grey, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: kPs),

        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(kR),
          ),
          child: Column(
            children: [
              if (enableHybrid) ...[
                RadioListTile<bool>(
                  value: true,
                  groupValue: isHybrid,
                  activeColor: kAccent,
                  title: Text(
                    'LN+WN Гибрид',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Комплексный формат (LN тома + WN онгоинг главы)',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey),
                  ),
                  secondary: const Icon(Icons.bolt_rounded),
                  onChanged: (val) {
                    if (val != null) onHybridChanged(val);
                  },
                ),
                Divider(height: 1, indent: kP, endIndent: kP, color: Theme.of(context).dividerColor),
              ],
              RadioListTile<String>(
                value: 'series',
                groupValue: isHybrid ? 'hybrid' : (isSeries ? 'series' : (isWeb ? 'web' : 'single')),
                activeColor: kAccent,
                title: Text(
                  'Серия томов',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'Серийное издание печатных томов (LN / Книги)',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey),
                ),
                secondary: const Icon(Icons.layers_rounded),
                onChanged: (val) {
                  onHybridChanged(false);
                  onSeries(true);
                  onCountVols(true);
                },
              ),
              Divider(height: 1, indent: kP, endIndent: kP, color: Theme.of(context).dividerColor),
              RadioListTile<String>(
                value: 'web',
                groupValue: isHybrid ? 'hybrid' : (isSeries ? 'series' : (isWeb ? 'web' : 'single')),
                activeColor: kAccent,
                title: Text(
                  'Веб-новелла',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'Азиатские веб-романы, разбитые строго по главам (WN)',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey),
                ),
                secondary: const Icon(Icons.language_rounded),
                onChanged: (val) {
                  onHybridChanged(false);
                  onWeb(true);
                },
              ),
              Divider(height: 1, indent: kP, endIndent: kP, color: Theme.of(context).dividerColor),
              RadioListTile<String>(
                value: 'single',
                groupValue: isHybrid ? 'hybrid' : (isSeries ? 'series' : (isWeb ? 'web' : 'single')),
                activeColor: kAccent,
                title: Text(
                  'Сингл (Одиночное)',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  'Одиночный роман (Оношот / Том-сингл)',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey),
                ),
                secondary: const Icon(Icons.menu_book_rounded),
                onChanged: (val) {
                  onHybridChanged(false);
                  onSingle(true);
                  onCountVols(true);
                },
              ),
            ],
          ),
        ),
        
        if (!isWeb && !isHybrid) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(kR),
            ),
            child: _SwitchRow('Учитывать тома', countVols,
              'Отключите для изданий без томов', (v) => onCountVols(v)),
          ),
        ],
      ]),
    );
  }
}

class _StepData extends StatelessWidget {
  final TextEditingController words, vols, totalVols;
  final TextEditingController webChaps, totalWebChaps;
  final bool countVols, detailed, ongoing, isWeb;
  final List<_VolCtrl> volCtrls;
  final int totalDetailed;
  final Color card;
  final ValueChanged<bool> onToggleDetailed, onToggleOngoing;
  final VoidCallback onAddVol, onChanged;
  final ValueChanged<int> onRemoveVol;

  final bool showBookmarks;
  final TextEditingController bookmarkCtrl;
  final bool isHybrid;
  final TextEditingController hybridWebChaps, hybridTotalWebChaps;

  final bool enableRating;
  final int ratingScale;
  final int? ratingValue;
  final ValueChanged<int?> onRatingChanged;

  final bool enableAdaptationStart;
  final TextEditingController startVolumeCtrl;
  final TextEditingController startChapterCtrl;
  final bool isSeries;
  final bool isSingle;

  const _StepData({
    required this.words, required this.vols, required this.totalVols,
    required this.webChaps, required this.totalWebChaps,
    required this.countVols, required this.detailed, required this.ongoing,
    required this.isWeb,
    required this.volCtrls, required this.totalDetailed, required this.card,
    required this.onToggleDetailed, required this.onToggleOngoing,
    required this.onAddVol, required this.onRemoveVol, required this.onChanged,
    
    required this.showBookmarks, required this.bookmarkCtrl,
    required this.isHybrid, required this.hybridWebChaps, required this.hybridTotalWebChaps,

    required this.enableRating, required this.ratingScale,
    required this.ratingValue, required this.onRatingChanged,

    required this.enableAdaptationStart,
    required this.startVolumeCtrl,
    required this.startChapterCtrl,
    required this.isSeries,
    required this.isSingle,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(kP, kPl, kP, kP),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        if (showBookmarks) ...[
          Text('ЗАКЛАДКА',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.grey, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: kPs),
          TextField(
            controller: bookmarkCtrl,
            decoration: const InputDecoration(
              hintText: 'Впишите главу/том, например: 1.4 глава, 1х3.3',
              prefixIcon: Icon(Icons.bookmark_rounded, size: 18, color: kAccent)),
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
          ),
          const SizedBox(height: kPl),
        ],

        if (enableAdaptationStart) ...[
          Text('СТАРТ ПОСЛЕ АДАПТАЦИИ',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.grey, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: kPs),
          if (isSeries || isSingle) ...[
            TextField(
              controller: startVolumeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Начальный том (с какого начали)',
                prefixIcon: Icon(Icons.play_arrow_rounded, color: kAccent)),
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
            ),
          ],
          if (isWeb || isHybrid) ...[
            if (isSeries || isSingle) const SizedBox(height: kPs),
            TextField(
              controller: startChapterCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Начальная глава (с какой начали)',
                prefixIcon: Icon(Icons.play_arrow_rounded, color: kAccent)),
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
            ),
          ],
          const SizedBox(height: kPl),
        ],

        if (enableRating) ...[
          Text('ОЦЕНКА ТАЙТЛА',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.grey, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: kPs),
          _buildRatingSelector(context),
          const SizedBox(height: kPl),
        ],

        if (isWeb) ...[
          Text('ПРОГРЕСС ГЛАВ ВЕБ-НОВЕЛЛЫ',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.grey, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: kPs),
          Row(children: [
            Expanded(child: TextField(
              controller: webChaps,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Прочитано глав',
                prefixIcon: Icon(Icons.format_list_numbered_rounded, size: 18, color: Colors.grey)),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: totalWebChaps,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Всего глав',
                hintText: 'Необяз.',
                prefixIcon: Icon(Icons.bookmark_border_rounded, size: 18, color: Colors.grey)),
            )),
          ]),
          const SizedBox(height: kPl),
        ],

        if (isHybrid) ...[
          Text('ПРОГРЕСС ВЕБ-ГЛАВ (В ГИБРИДЕ)',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.grey, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: kPs),
          Row(children: [
            Expanded(child: TextField(
              controller: hybridWebChaps,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Прочитано веб-глав',
                prefixIcon: Icon(Icons.format_list_numbered_rounded, size: 18, color: Colors.grey)),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: hybridTotalWebChaps,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Всего глав',
                hintText: 'Необяз.',
                prefixIcon: Icon(Icons.bookmark_border_rounded, size: 18, color: Colors.grey)),
            )),
          ]),
          const SizedBox(height: kPl),
        ],

        Text('СЛОВА И РАСЧЁТЫ',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.grey, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: kPs),

        if (!isWeb && countVols) ...[
          _CardGroup(children: [
            _SwitchRow('Расчёт по томам', detailed,
              detailed ? 'Записывать слова каждого тома' : 'Ввести суммарно по книге',
              onToggleDetailed),
          ]),
          const SizedBox(height: kP),
        ],

        if (!isWeb && detailed) ...[
          ...volCtrls.asMap().entries.map((e) {
            final i = e.key; final c = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: kPs),
              child: Row(children: [
                SizedBox(width: 76, child: TextField(
                  controller: c.vol,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(labelText: 'Том'),
                )),
                const SizedBox(width: kPs),
                Expanded(child: TextField(
                  controller: c.words,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(labelText: 'Слов'),
                )),
                const SizedBox(width: kPs),
                GestureDetector(
                  onTap: () => onRemoveVol(i),
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: kSDropped.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(kRs)),
                    child: const Icon(Icons.remove_rounded, color: kSDropped, size: 18)),
                ),
              ]),
            );
          }),

          OutlinedButton.icon(
            onPressed: onAddVol,
            icon: const Icon(Icons.add_rounded, color: kAccent, size: 18),
            label: Text('Добавить том',
              style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kR)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              minimumSize: const Size(double.infinity, 0)),
          ),

          if (volCtrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 12),
              decoration: BoxDecoration(
                color: kAccentDim,
                borderRadius: BorderRadius.circular(kR),
                border: Border.all(color: kAccent.withOpacity(0.2))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Томов: ${volCtrls.length}',
                    style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.w700)),
                  Text('Слов: ${fmtNum(totalDetailed)}',
                    style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.w700)),
                ]),
            ),
          ],
        ] 
        else ...[
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('СЛОВ',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.grey, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              const SizedBox(height: kPs),
              TextField(
                controller: words, keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.text_fields_rounded, size: 18, color: Colors.grey)),
              ),
            ])),
            if (countVols) ...[
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ТОМОВ',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.grey, fontSize: 11,
                    fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                const SizedBox(height: kPs),
                TextField(
                  controller: vols, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.layers_rounded, size: 18, color: Colors.grey)),
                ),
              ])),
            ],
          ]),
        ],

        if (countVols) ...[
          const SizedBox(height: kPl),
          Text('ВСЕГО ТОМОВ В СЕРИИ',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.grey, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: kPs),
          _CardGroup(children: [
            _SwitchRow('Онгоинг', ongoing,
              ongoing ? 'Отображается как 5/?' : 'Кол-во томов известно',
              onToggleOngoing),
          ]),
          if (!ongoing) ...[
            const SizedBox(height: kPs),
            TextField(
              controller: totalVols, keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Необязательно — напр. 25',
                prefixIcon: Icon(Icons.bookmark_border_rounded, size: 18, color: Colors.grey)),
            ),
          ],
        ],
      ]),
    );
  }

  Widget _buildRatingSelector(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kR),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(ratingScale, (index) {
              final starVal = index + 1;
              bool isActive = false;
              if (ratingValue != null) {
                if (ratingScale == 5) {
                  isActive = (ratingValue! / 2).round() >= starVal;
                } else {
                  isActive = ratingValue! >= starVal;
                }
              }
              return GestureDetector(
                onTap: () {
                  if (ratingScale == 5) {
                    onRatingChanged(starVal * 2);
                  } else {
                    onRatingChanged(starVal);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    isActive ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isActive ? kAccent : Colors.grey.shade600,
                    size: ratingScale == 5 ? 32 : 24,
                  ),
                ),
              );
            }),
          ),
          if (ratingValue != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Выбрано: ${ratingScale == 5 ? (ratingValue! / 2).round() : ratingValue} из $ratingScale',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w700, color: kAccent),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => onRatingChanged(null),
                  child: Text(
                    'Сбросить',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: kSDropped, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          ],
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  const _PickerTile(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kAccentDim, borderRadius: BorderRadius.circular(kRs)),
      child: Icon(icon, color: kAccent, size: 20)),
    title: Text(label,
      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
    onTap: onTap,
  );
}

// ══════════════════════════════════════════════════════════
// АНАЛИТИКА / СТАТИСТИКА
// ══════════════════════════════════════════════════════════

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});
  @override
  State<StatisticsPage> createState() => _StatsState();
}

class _StatsState extends State<StatisticsPage> {
  void _onChange() { if (mounted) setState(() {}); }
  @override
  void initState() { super.initState(); appState.addListener(_onChange); }
  @override
  void dispose() { appState.removeListener(_onChange); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final hasVols = appState.anyBooksCountVolumes;
    final showWeb = appState.showWebInStats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Аналитика'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(kP, kP, kP, 40), children: [

        if (appState.stackedStats) ...[
          _StatCard(Icons.emoji_events_rounded, kSReading,  'Завершено серий', appState.completedSeries.toString()),
          if (showWeb) ...[
            const SizedBox(height: 10),
            _StatCard(Icons.language_rounded, kSCompleted, 'Завершено веб-новелл', appState.completedWeb.toString()),
          ],
          if (hasVols) ...[
            const SizedBox(height: 10),
            _StatCard(Icons.layers_rounded, kSPlanned, 'Прочитано томов', fmtNum(appState.totalVolumes)),
          ],
        ] else ...[
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _StatCard(Icons.emoji_events_rounded, kSReading, 'Завершено серий', appState.completedSeries.toString())),
            if (showWeb) ...[
              const SizedBox(width: 10),
              Expanded(child: _StatCard(Icons.language_rounded, kSCompleted, 'Завершено веб', appState.completedWeb.toString())),
            ],
            if (hasVols) ...[
              const SizedBox(width: 10),
              Expanded(child: _StatCard(Icons.layers_rounded, kSPlanned, 'Прочитано томов', fmtNum(appState.totalVolumes))),
            ],
          ])),
        ],
        const SizedBox(height: 10),
        _StatCard(Icons.text_fields_rounded, kAccent, 'Прочитано слов', fmtNum(appState.totalWords), wide: true),

        const SizedBox(height: kPl),
        _SectionLabel('ПО СТАТУСАМ'),
        const SizedBox(height: kPs),

        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(kR),
          ),
          child: Column(children: List.generate(BookStatus.values.length, (i) {
            final s     = BookStatus.values[i];
            final count = appState.countByStatus(s);
            final total = appState.books.isEmpty ? 1 : appState.books.length;
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 9, height: 9,
                      decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.label,
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: s.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(kRs)),
                      child: Text(count.toString(),
                        style: GoogleFonts.plusJakartaSans(
                          color: s.color, fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: count / total,
                      backgroundColor: s.color.withOpacity(0.10),
                      valueColor: AlwaysStoppedAnimation(s.color),
                      minHeight: 4,
                    ),
                  ),
                ]),
              ),
              if (i < BookStatus.values.length - 1)
                Divider(height: 1, indent: kP, endIndent: kP,
                  color: Theme.of(context).dividerColor),
            ]);
          })),
        ),

        const SizedBox(height: kPl),
        GestureDetector(
          onTap: () => Navigator.push(context, _route(const SettingsPage())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(kR)),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kAccentDim, borderRadius: BorderRadius.circular(kRs)),
                child: const Icon(Icons.settings_rounded, color: kAccent, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Настройки',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('Управление функциями, тема, экспорт',
                  style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 12)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// НАСТРОЙКИ 
// ══════════════════════════════════════════════════════════

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  void _onChange() { if (mounted) setState(() {}); }
  @override
  void initState() { super.initState(); appState.addListener(_onChange); }
  @override
  void dispose() { appState.removeListener(_onChange); super.dispose(); }

  Future<void> _export() async {
    try {
      final json = const JsonEncoder.withIndent('  ')
          .convert(appState.books.map((b) => b.toJson()).toList());
      final file = File('${Directory.systemTemp.path}/readtracker_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(json);
      await Share.shareXFiles([XFile(file.path)], text: 'ReadTracker — экспорт библиотеки');
    } catch (e) {
      if (mounted) _snack('Ошибка экспорта: $e', isError: true);
    }
  }

  Future<void> _import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final books = (jsonDecode(utf8.decode(bytes)) as List)
          .map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
      if (!mounted) return;
      final ok = await showDialog<bool>(context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRl)),
          title: Text('Импорт библиотеки',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 17)),
          content: Text('Будет загружено ${books.length} тайтлов. Текущая библиотека будет заменена.',
            style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 14)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: GoogleFonts.plusJakartaSans(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Заменить',
                style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.w700))),
          ],
        ));
      if (ok != true) return;
      await appState.importBooks(books);
      if (mounted) _snack('Загружено ${books.length} тайтлов');
    } catch (e) {
      if (mounted) _snack('Ошибка импорта: $e', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
      backgroundColor: isError ? kSDropped : kAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kR)),
      margin: const EdgeInsets.only(bottom: 20, left: kP, right: kP),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(kP, kP, kP, 40), children: [

        _SectionLabel('ТЕМА'),
        _CardGroup(children: [
          _ThemeTile('AMOLED',  Icons.dark_mode_rounded,        0),
          _ThemeTile('Тёмная',  Icons.nightlight_round_rounded, 1),
          _ThemeTile('Светлая', Icons.wb_sunny_rounded,         2),
        ]),
        const SizedBox(height: kPl),

        _SectionLabel('ДОПОЛНИТЕЛЬНЫЙ ФУНКЦИОНАЛ'),
        _CardGroup(children: [
          _SwitchRow('Закладки', appState.showBookmarks, 
            appState.showBookmarks ? 'Поле введения текущей главы без влияния на статистику' : 'Поле заметок отключено', 
            appState.toggleShowBookmarks),
          
          if (appState.showBookmarks)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Расположение закладки', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 15)),
                  DropdownButton<int>(
                    value: appState.bookmarkPosition,
                    dropdownColor: Theme.of(context).cardColor,
                    underline: Container(),
                    style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.bold, fontSize: 15),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Снизу')),
                      DropdownMenuItem(value: 1, child: Text('В ряд')),
                    ],
                    onChanged: (val) {
                      if (val != null) appState.setBookmarkPosition(val);
                    },
                  ),
                ],
              ),
            ),
          
          _SwitchRow('Читать после адаптации', appState.enableAdaptationStart,
            appState.enableAdaptationStart ? 'Возможность указать том/главу, с которых вы начали' : 'Функция "Старт после адаптации" отключена',
            appState.toggleAdaptationStart),

          _SwitchRow('Гибридный формат LN+WN', appState.enableHybrid, 
            appState.enableHybrid ? 'Позволяет объединить LN и WN в одной карточке' : 'Раздельные карточки томов и глав', 
            appState.toggleEnableHybrid),
          _SwitchRow('Оценка тайтлов', appState.enableRating, 
            appState.enableRating ? 'Возможность оценивать тайтлы' : 'Функция выставления оценки отключена', 
            appState.toggleEnableRating),
          if (appState.enableRating)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Шкала оценки', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 15)),
                  DropdownButton<int>(
                    value: appState.ratingScale,
                    dropdownColor: Theme.of(context).cardColor,
                    underline: Container(),
                    style: GoogleFonts.plusJakartaSans(color: kAccent, fontWeight: FontWeight.bold, fontSize: 15),
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5 звёзд')),
                      DropdownMenuItem(value: 10, child: Text('10 звёзд')),
                    ],
                    onChanged: (val) {
                      if (val != null) appState.setRatingScale(val);
                    },
                  ),
                ],
              ),
            ),
        ]),
        const SizedBox(height: kPl),

        _SectionLabel('ОТОБРАЖЕНИЕ И СИСТЕМА'),
        _CardGroup(children: [
          _SwitchRow('Отключить анимации', appState.disableAnimations, 
            appState.disableAnimations ? 'Мгновенный переход между экранами' : 'Используются стандартные системные переходы', 
            appState.toggleDisableAnimations),
          _SwitchRow('Показ Веб в аналитике', appState.showWebInStats, 
            appState.showWebInStats ? 'Отображает прочитанные веб-новеллы в статистике' : 'Скрывает метрики веб-новелл в отчётах', 
            appState.toggleShowWebInStats),
          _SwitchRow('Обложки тайтлов',
            appState.showCovers,
            appState.showCovers ? 'Показывать обложки в списке' : 'Компактный вид без обложек',
            appState.toggleShowCovers),
          _SwitchRow('Сокращать числа',
            appState.shortenNumbers, '150K вместо 150 000', appState.toggleShortenNumbers),
          _SwitchRow('Широкие карточки статистики',
            appState.stackedStats, 'Метрики друг под другом', appState.toggleStackedStats),
          _SwitchRow('Кнопка «Поделиться»',
            appState.showShareButton, 'В шапке библиотеки', appState.toggleShareButton),
          _SwitchRow('Скрыть нижний бар',
            appState.hideBottomBar,
            appState.hideBottomBar ? 'Статистика через кнопку вверху' : 'Нижняя навигация активна',
            appState.toggleHideBottomBar),
          _SwitchRow('Главы для Веб-романов',
            appState.showWebChapters,
            appState.showWebChapters ? 'Показывать X/Y гл. на карточках' : 'Прогресс глав скрыт',
            appState.toggleShowWebChapters),
        ]),
        const SizedBox(height: kPl),

        _SectionLabel('ДАННЫЕ'),
        _CardGroup(children: [
          _ActionTile(Icons.upload_file_rounded,          kSReading,  'Экспорт библиотеки', 'Сохранить в JSON-файл',   _export),
          _ActionTile(Icons.download_for_offline_rounded, kSPlanned,  'Импорт библиотеки',  'Загрузить из JSON-файла', _import),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ПОДЕЛИТЬСЯ — КАРТОЧКА АНАЛИТИКИ
// ══════════════════════════════════════════════════════════

class ShareAnalyticsPage extends StatefulWidget {
  const ShareAnalyticsPage({super.key});
  @override
  State<ShareAnalyticsPage> createState() => _ShareAnalyticsState();
}

class _ShareAnalyticsState extends State<ShareAnalyticsPage> {
  final _key    = GlobalKey();
  bool  _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image    = await boundary.toImage(pixelRatio: 3.0);
      final bd       = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) throw Exception('no bytes');
      await igs.ImageGallerySaverPlus.saveImage(
        bd.buffer.asUint8List(),
        name: 'readtracker_analytics_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text('Сохранено в галерею',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        ]),
        backgroundColor: kAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kR)),
        margin: const EdgeInsets.only(bottom: 20, left: kP, right: kP)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: kSDropped));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Аналитика')),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(kPl),
        child: Column(children: [

          RepaintBoundary(key: _key, child: Container(
            padding: const EdgeInsets.all(kPl),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRl),
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF1A1024), const Color(0xFF0F0A1A)]
                    : [const Color(0xFFFFF8EC), const Color(0xFFFFF0D0)]),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: kAccentDim,
                      borderRadius: BorderRadius.circular(kR)),
                    child: const Icon(Icons.auto_stories_rounded, color: kAccent, size: 22)),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ReadTracker',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17, fontWeight: FontWeight.w900, color: kAccent)),
                    Text('Моя статистика',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey)),
                  ]),
                ]),
                const SizedBox(height: kPl),
                _ShareMetricRow(Icons.emoji_events_rounded, kSReading, 'Завершено серий', appState.completedSeries.toString()),
                if (appState.showWebInStats) ...[
                  const SizedBox(height: 14),
                  _ShareMetricRow(Icons.language_rounded, kSCompleted, 'Завершено веб-новелл', appState.completedWeb.toString()),
                ],
                if (appState.anyBooksCountVolumes) ...[
                  const SizedBox(height: 14),
                  _ShareMetricRow(Icons.layers_rounded, kSPlanned, 'Прочитано томов', fmtNum(appState.totalVolumes)),
                ],
                const SizedBox(height: 14),
                _ShareMetricRow(Icons.text_fields_rounded, kAccent, 'Прочитано слов', fmtNum(appState.totalWords)),
              ]),
          )),

          const SizedBox(height: kPl),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_rounded, color: Colors.white),
            label: Text(_saving ? 'Сохраняем...' : 'Сохранить в галерею',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kR)),
              elevation: 0),
          )),
        ]))),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ПОДЕЛИТЬСЯ — СПИСОК КНИГ В КАРТОЧКЕ
// ══════════════════════════════════════════════════════════

class ShareLibraryPage extends StatefulWidget {
  const ShareLibraryPage({super.key});
  @override
  State<ShareLibraryPage> createState() => _ShareLibraryState();
}

class _ShareLibraryState extends State<ShareLibraryPage> {
  final _key    = GlobalKey();
  bool  _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image    = await boundary.toImage(pixelRatio: 3.0);
      final bd       = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) throw Exception('no bytes');
      await igs.ImageGallerySaverPlus.saveImage(
        bd.buffer.asUint8List(),
        name: 'readtracker_library_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text('Сохранено в галерею',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        ]),
        backgroundColor: kSReading,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kR)),
        margin: const EdgeInsets.only(bottom: 20, left: kP, right: kP)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: kSDropped));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final books  = appState.books;
    return Scaffold(
      appBar: AppBar(title: const Text('Список тайтлов')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(kPl),
        child: Column(children: [

          RepaintBoundary(key: _key, child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(kPl),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kRl),
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF0D1A14), const Color(0xFF061008)]
                    : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)]),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kSReading.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(kR)),
                  child: const Icon(Icons.format_list_bulleted_rounded, color: kSReading, size: 22)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ReadTracker',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17, fontWeight: FontWeight.w900, color: kSReading)),
                  Text('Тайтлов: ${books.length}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.grey)),
                ]),
              ]),
              const SizedBox(height: kP),
              if (appState.showWebInStats) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Серий завершено: ${appState.completedSeries}  |  Веб завершено: ${appState.completedWeb}',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: kSReading),
                  ),
                ),
              ],
              ...books.map((book) {
                final sc = book.status.color;
                final vl = book.volumeLabel();
                final ratingStr = appState.enableRating ? book.getRatingDisplay(appState.ratingScale) : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 3, height: 44,
                      decoration: BoxDecoration(color: sc, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(book.title,
                              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (ratingStr.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(ratingStr, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: kAccent, fontWeight: FontWeight.bold)),
                          ]
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(children: [
                        Text(book.status.label,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: sc, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${fmtNum(book.effectiveWords)} сл.',
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.grey)),
                        if ((book.countVolumes || book.isHybridFormat) && vl.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(vl, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: Colors.grey)),
                        ],
                      ]),
                    ])),
                  ]),
                );
              }),
            ]),
          )),

          const SizedBox(height: kP),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_rounded, color: Colors.white),
            label: Text(_saving ? 'Сохраняем...' : 'Сохранить в галерею',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kSReading,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kR)),
              elevation: 0),
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// ПЕРЕИСПОЛЬЗУЕМЫЕ МИНИ-ВИДЖЕТЫ
// ══════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: kPs),
    child: Text(text, style: GoogleFonts.plusJakartaSans(
      color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
  );
}

class _CardGroup extends StatelessWidget {
  final List<Widget> children;
  const _CardGroup({required this.children});
  @override
  Widget build(BuildContext context) {
    final div = Divider(height: 1, indent: kP, endIndent: kP,
      color: Theme.of(context).dividerColor);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kR)),
      child: Column(children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) div,
        ],
      ]),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _SwitchRow(this.title, this.value, this.subtitle, this.onChanged);

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onChanged == null ? 0.38 : 1.0,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 11),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 15)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 12)),
          ],
        ])),
        const SizedBox(width: kPs),
        Switch(value: value, onChanged: onChanged),
      ]),
    ),
  );
}

class _ThemeTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final int value;
  const _ThemeTile(this.title, this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    final sel = appState.themeMode == value;
    return InkWell(
      borderRadius: BorderRadius.circular(kR),
      onTap: () => appState.changeTheme(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 14),
        child: Row(children: [
          Icon(icon, color: sel ? kAccent : Colors.grey, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
              color: sel ? kAccent : null))),
          Icon(sel ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: sel ? kAccent : Colors.grey, size: 20),
        ]),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   title, subtitle;
  final VoidCallback onTap;
  const _ActionTile(this.icon, this.color, this.title, this.subtitle, this.onTap);

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(kR),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 13),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(kRs)),
          child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 15)),
          Text(subtitle, style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 12)),
        ])),
        const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
      ]),
    ),
  );
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title, value;
  final bool     wide;
  const _StatCard(this.icon, this.iconColor, this.title, this.value, {this.wide = false});

  @override
  Widget build(BuildContext context) => Container(
    width: wide ? double.infinity : null,
    padding: const EdgeInsets.all(kP),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(kR)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(kRs)),
        child: Icon(icon, color: iconColor, size: 18)),
      const SizedBox(height: 10),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, style: GoogleFonts.plusJakartaSans(
          fontSize: 28, fontWeight: FontWeight.w800, height: 1.1))),
      const SizedBox(height: 2),
      Text(title, style: GoogleFonts.plusJakartaSans(
        color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
    ]),
  );
}

class _ShareMetricRow extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   label, value;
  const _ShareMetricRow(this.icon, this.iconColor, this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(kRs)),
      child: Icon(icon, color: iconColor, size: 18)),
    const SizedBox(width: 14),
    Expanded(child: Text(label, style: GoogleFonts.plusJakartaSans(
      fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500))),
    Text(value, style: GoogleFonts.plusJakartaSans(
      fontSize: 22, fontWeight: FontWeight.w800)),
  ]);
}

class _ShareOptionTile extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   title, sub;
  final VoidCallback onTap;
  const _ShareOptionTile({
    required this.icon, required this.color,
    required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: kP, vertical: 13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(kR),
        border: Border.all(color: color.withOpacity(0.18))),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(kRs)),
          child: Icon(icon, color: color, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700)),
          Text(sub, style: GoogleFonts.plusJakartaSans(color: Colors.grey, fontSize: 12)),
        ])),
        Icon(Icons.arrow_forward_ios_rounded, color: color, size: 15),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════
// ГЛОБАЛЬНЫЙ РОУТЕР (Поддерживает моментальные переходы)
// ══════════════════════════════════════════════════════════

Route _route(Widget page) {
  if (appState.disableAnimations) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }
  return MaterialPageRoute(builder: (_) => page);
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kAccent.withOpacity(0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dashW = 6.0;
    const gapW  = 4.0;
    final r = Radius.circular(kR + 4);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height), r));
    final metric = path.computeMetrics().first;
    double dist = 0;
    while (dist < metric.length) {
      final end = (dist + dashW).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(dist, end), paint);
      dist += dashW + gapW;
    }
  }
  @override
  bool shouldRepaint(_) => false;
}

