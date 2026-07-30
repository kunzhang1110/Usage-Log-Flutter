import 'constants.dart';
import 'models/app_event.dart';
import 'models/app_model.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:usage_stats/usage_stats.dart';

import 'models/app_usage.dart';
import 'utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<AppEvent> _appEvents = [];
  List<AppUsage> _appUsages = [];
  List<AppUsage> _appConciseUsages = [];
  int _selectedIndex = 0;
  bool _isSearching = false;
  String _searchQuery = '';
  static const MethodChannel _appInfoChannel =
      MethodChannel('usage_log/app_info');
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  final PageController _pageController = PageController();
  final List<ScrollController> _scrollControllers =
      List.generate(3, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshIndicatorKey.currentState?.show();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _scrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Filter by app',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                )
              : const Text("Usage Log"),
          actions: [
            if (_isSearching)
              IconButton(
                onPressed: () => setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                }),
                icon: const Icon(Icons.close),
              )
            else ...[
              IconButton(
                onPressed: () => setState(() => _isSearching = true),
                icon: const Icon(Icons.search),
              ),
              if (_selectedIndex == 0)
                IconButton(
                  onPressed: _handleCopyPressed,
                  icon: const Icon(Icons.copy),
                ),
            ],
          ],
        ),
        // Swipe left/right to switch tabs; kept in sync with the nav bar.
        body: PageView(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _selectedIndex = index),
          children: [
            _buildRefreshableList(0, _filterByApp(_appConciseUsages),
                refreshKey: _refreshIndicatorKey),
            _buildRefreshableList(1, _filterByApp(_appUsages)),
            _buildRefreshableList(2, _filterByApp(_appEvents)),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            final controller = _scrollControllers[_selectedIndex];
            if (controller.hasClients) {
              controller.animateTo(
                0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
              );
            }
          },
          child: const Icon(Icons.arrow_upward),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          ),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.summarize),
              label: 'Concise',
            ),
            NavigationDestination(
              icon: Icon(Icons.apps),
              label: 'All',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long),
              label: 'Raw',
            ),
          ],
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme =
        ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // Keep the top bar the same color as the bottom NavigationBar, and stop
      // it from re-tinting when content scrolls underneath.
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surfaceContainer,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
      ),
    );
  }

  bool _isResumed(AppEvent appEvent) {
    return appEvent.eventType == "Activity Resumed";
  }

  bool _isPausedOrStopped(AppEvent appEvent) {
    return appEvent.eventType == "Activity Paused" ||
        appEvent.eventType == "Activity Stopped";
  }

  /// Resolves the label and icon for [packageNames] via the native channel.
  /// Packages that can't be resolved are simply absent from the result.
  Future<Map<String, _AppInfo>> _loadAppInfos(Set<String> packageNames) async {
    final infos = <String, _AppInfo>{};
    try {
      final raw = await _appInfoChannel.invokeMethod<Map<Object?, Object?>>(
        'getAppInfos',
        packageNames.toList(),
      );
      raw?.forEach((key, value) {
        final info = (value as Map).cast<Object?, Object?>();
        infos[key as String] = _AppInfo(
          label: info['label'] as String?,
          icon: info['icon'] as Uint8List?,
        );
      });
    } catch (e) {
      debugPrint('$e');
    }
    return infos;
  }

  Future<void> _updateData() async {
    UsageStats.grantUsagePermission();

    if (_appEvents.isNotEmpty) {
      setState(() {
        _appEvents.clear();
        _appUsages.clear();
        _appConciseUsages.clear();
      });
    }

    DateTime endDate = DateTime.now();
    DateTime startDate =
        endDate.add(const Duration(days: -daysOfEventsIncluded));

    List<EventUsageInfo> queryEvents =
        await UsageStats.queryEvents(startDate, endDate);

    List<AppEvent> appEvents = [];
    List<AppUsage> appUsages = [];
    List<AppUsage> appConciseUsages = [];
    Map<String, List<AppEvent>> appNameToAppEventMap = {};

    // Resolve the label and icon for each distinct package once, in a single
    // native call, instead of two channel round-trips per usage event.
    final packageNames = <String>{
      for (var event in queryEvents)
        if (event.packageName != null) event.packageName!,
    };
    final appInfos = await _loadAppInfos(packageNames);

    for (var event in queryEvents) {
      var packageName = event.packageName;
      var eventType = eventTypeMap[int.parse(event.eventType!)];
      if (eventType == null || packageName == null) continue;

      final info = appInfos[packageName];
      final appName = info?.label ?? packageName;
      if (appNameExcludedList.contains(appName)) continue;

      var appEvent = AppEvent.empty();
      appEvent.eventType = eventType;
      appEvent.time =
          DateTime.fromMillisecondsSinceEpoch(int.parse(event.timeStamp!));
      appEvent.appName = appName;
      appEvent.appIconByte = info?.icon;

      if (eventTypeForDurationList.contains(eventType)) {
        appNameToAppEventMap
            .putIfAbsent(appEvent.appName, () => List.empty(growable: true))
            .add(appEvent);
      }
      appEvents.add(appEvent);
    }

    // calculate app usages
    appNameToAppEventMap.forEach(
      (String appName, List<AppEvent> events) {
        for (int x = 0; x < events.length; x++) {
          var eventX = events[x];

          if (_isResumed(eventX)) {
            int y = x + 1;

            while (y < events.length && !_isPausedOrStopped(events[y])) {
              y++;
            }

            if (y < events.length) {
              var eventY = events[y];
              Duration duration = eventY.time.difference(eventX.time);
              int durationInSeconds = duration.inSeconds;

              if (durationInSeconds > 0) {
                var appUsage = AppUsage(
                  appName: appName,
                  appIconByte: eventX.appIconByte,
                  time: eventX.time,
                  durationInSeconds: durationInSeconds,
                );
                appUsage.durationInSeconds = durationInSeconds;
                appUsages.add(appUsage);
                x = y;
              }
            }
          }
        }
      },
    );

    appUsages.sort();

    // calculate screen locked usage from app usages gaps
    for (int i = 0; i < appUsages.length - 1; i++) {
      AppUsage currentAppUsage = appUsages[i];
      AppUsage nextAppUsage = appUsages[i + 1];

      DateTime currentAppUsageEndTime = currentAppUsage.time
          .add(Duration(seconds: currentAppUsage.durationInSeconds));
      Duration timeDiff = nextAppUsage.time.difference(currentAppUsageEndTime);

      if (timeDiff.inSeconds > 1) {
        AppUsage screenLockedAppUsage = AppUsage(
          appName: "Screen Locked",
          durationInSeconds: timeDiff.inSeconds,
          time: currentAppUsageEndTime,
          appIconByte: null,
        );

        appUsages.insert(i + 1, screenLockedAppUsage);

        if (screenLockedAppUsage.durationInSeconds >= conciseMinTimeInSeconds) {
          appConciseUsages.add(screenLockedAppUsage);
          appConciseUsages.add(nextAppUsage);
        }

        i++; // Skip next iteration to avoid duplication
      }
    }

    setState(() {
      _appEvents = appEvents.reversed.toList();
      _appUsages = appUsages.reversed.toList();
      _appConciseUsages = appConciseUsages.reversed.toList();
    });
  }

  /// Copies the times of concise activities that fall within the configured
  /// copy session (copySessionStartTime–copySessionEndTime) to the clipboard.
  void _handleCopyPressed() async {
    final copyText = <String>[];

    final DateTime firstStartDateTime = _appConciseUsages.last.time;
    final DateTime referenceDateTime = DateTime(
      firstStartDateTime.year,
      firstStartDateTime.month,
      firstStartDateTime.day,
      0,
      0,
    );

    for (var i = _appConciseUsages.length - 1; i > 0; i--) {
      final appUsageStartDateTime = _appConciseUsages[i].time;
      final durationInSeconds = _appConciseUsages[i].durationInSeconds;

      final DateTime sessionStartDateTime = DateTime(
        referenceDateTime.year,
        referenceDateTime.month,
        referenceDateTime.day,
        copySessionStartTime.hour,
        copySessionStartTime.minute,
      );

      final DateTime sessionEndDateTime = DateTime(
        referenceDateTime.year,
        referenceDateTime.month,
        referenceDateTime.day + 1,
        copySessionEndTime.hour,
        copySessionEndTime.minute,
      );

      final bool isInCopySession = appUsageStartDateTime.isAfter(sessionStartDateTime) &&
          appUsageStartDateTime.isBefore(sessionEndDateTime);

      if (isInCopySession && durationInSeconds > conciseMinTimeInSeconds) {
        copyText.add(appModelTimeText(_appConciseUsages, i));
      }
    }

    final clipboardData = ClipboardData(text: copyText.join(' '));
    await Clipboard.setData(clipboardData);
  }

  /// Filters [models] to those whose app name contains the search query.
  List<T> _filterByApp<T extends AppModel>(List<T> models) {
    if (_searchQuery.isEmpty) return models;
    final query = _searchQuery.toLowerCase();
    return models
        .where((model) => model.appName.toLowerCase().contains(query))
        .toList();
  }

  Widget _buildRefreshableList(int tabIndex, List<AppModel> appModels,
      {Key? refreshKey}) {
    return RefreshIndicator(
      key: refreshKey,
      onRefresh: _updateData,
      child: _buildListView(tabIndex, appModels),
    );
  }

  Widget _buildListView(int tabIndex, List<AppModel> appModels) {
    return ListView.separated(
      controller: _scrollControllers[tabIndex],
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 16, endIndent: 16),
      itemCount: appModels.length,
      itemBuilder: (context, index) {
        final theme = Theme.of(context);
        final appModel = appModels[index];

        // Highlight long sessions (name + duration) in red, matching Android.
        final bool highlight = appModel is AppUsage &&
            appModel.durationInSeconds > conciseMinTimeInSeconds;
        final Color mutedColor = theme.colorScheme.onSurfaceVariant;
        final Color? nameColor = highlight ? Colors.red : null;

        Widget? subText;
        if (appModel is AppUsage) {
          subText = Text(
            appModel.durationInText ?? '',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: highlight ? Colors.red : mutedColor),
          );
        } else if (appModel is AppEvent) {
          subText = Text(
            appModel.eventType ?? '',
            style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
          );
        }

        // Screen Locked and unresolved apps use themed Material icons so they
        // stay visible in both light and dark mode; real app icons are bitmaps.
        final Widget iconWidget;
        if (appModel.appName == "Screen Locked") {
          iconWidget = Icon(Icons.lock_outline,
              size: 35, color: theme.colorScheme.onSurface);
        } else if (appModel.appIconByte != null &&
            appModel.appIconByte!.isNotEmpty) {
          iconWidget =
              Image.memory(appModel.appIconByte!, width: 35, height: 35);
        } else {
          iconWidget =
              Icon(Icons.android, size: 35, color: mutedColor);
        }

        return InkWell(
          onLongPress: () async {
            if (index >= 1) {
              await Clipboard.setData(
                  ClipboardData(text: appModelTimeText(appModels, index)));
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    appModel.time.toString().substring(0, 16),
                    style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
                  ),
                ),
                const SizedBox(width: 12),
                iconWidget,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        appModel.appName,
                        style:
                            theme.textTheme.bodyLarge?.copyWith(color: nameColor),
                      ),
                      if (subText != null) subText,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppInfo {
  _AppInfo({required this.label, required this.icon});

  final String? label;
  final Uint8List? icon;
}
