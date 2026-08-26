/// Past training (`FR-1.5`) — the session list and the calendar, with search still to come.
///
/// The four aliases that pinned `TR-1.3`'s package edges here are gone: `SessionListState` names
/// ``WorkoutRepository``, ``ExerciseRepository`` and ``SettingsRepository``, `SessionListView` names
/// ``Route`` and the token scales, and `SessionSummary` names ``Weight``. See
/// `ExerciseLibraryModule`, which is the exemplar this header follows.
///
/// `CalendarState` and `MonthGrid` add a fifth edge that is neither a package nor a token:
/// `Foundation`'s ``Calendar``. Every month, week and day question here is asked of it rather than
/// computed, and the one it is asked is the *viewer's* — `@Environment(\.calendar)`, adopted by the
/// screen — so a month is never thirty days and a week never starts on Sunday by assumption.
public enum HistoryModule {}
