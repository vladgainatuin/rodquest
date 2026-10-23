import 'package:flutter/material.dart';

import '../logic/game_rules.dart';
import '../logic/time_rules.dart';
import '../models/models.dart';
import '../services/notifier.dart';
import '../services/push.dart';
import '../state/game_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Открыть экран будильников и напоминаний.
void openAlarms(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AlarmsScreen()),
  );
}

class AlarmsScreen extends StatefulWidget {
  const AlarmsScreen({super.key});

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends State<AlarmsScreen> {
  /// Разрешения на системные уведомления (приложение на телефоне/Mac).
  PushAccess _access = PushAccess.unsupported;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  Future<void> _loadAccess() async {
    final a = await GameScope.read(context).push.access();
    if (mounted) setState(() => _access = a);
  }

  Future<void> _requestAccess({bool exact = false}) async {
    final a = await GameScope.read(context).push.request(exact: exact);
    if (mounted) setState(() => _access = a);
  }

  Widget _accessCard(BuildContext context, {required String title, required String text, required String button, required VoidCallback onPressed}) {
    return RqCard(
      color: RqColors.p.highlightBg,
      borderColor: RqColors.p.highlightBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          ChunkyButton(label: button, icon: '🔔', expand: false, onPressed: onPressed),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final hero = game.activeHero!;
    final now = game.now;
    final mine = game.remindersOf(hero.id);
    final others = hero.role.isAdult ? game.reminders.where((r) => r.heroId != hero.id).toList() : const <Reminder>[];
    final permission = Notifier.permission;

    return Scaffold(
      appBar: AppBar(title: const Text('Будильники и напоминания')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: RqColors.primary,
        foregroundColor: RqColors.onAccent,
        onPressed: () => openReminderEditor(context),
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              if (_access.supported && !_access.allowed)
                _accessCard(
                  context,
                  title: '🔔 Разрешите уведомления',
                  text: 'Тогда будильник и напоминания зазвонят, даже если Родквест закрыт.',
                  button: 'Разрешить',
                  onPressed: () => _requestAccess(),
                )
              else if (_access.supported && !_access.exact)
                _accessCard(
                  context,
                  title: '⏰ Будильник минута в минуту',
                  text: 'Сейчас телефон может сдвинуть звонок на несколько минут ради экономии батареи. '
                      'Разрешите Родквесту «Будильники и напоминания» в настройках.',
                  button: 'Открыть настройки',
                  onPressed: () => _requestAccess(exact: true),
                ),
              if (Notifier.supported && permission == 'default')
                RqCard(
                  color: RqColors.p.highlightBg,
                  borderColor: RqColors.p.highlightBorder,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🔔 Разрешите уведомления',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Тогда будильник и напоминания покажутся, даже если вкладка с Родквестом свёрнута.',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      ChunkyButton(
                        label: 'Разрешить',
                        icon: '🔔',
                        expand: false,
                        onPressed: () async {
                          await Notifier.requestPermission();
                          Notifier.beep();
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                )
              else if (Notifier.supported && permission == 'denied')
                const EmptyHint(
                  emoji: '🔕',
                  text: 'Уведомления браузера запрещены. Будильник зазвонит, пока вкладка открыта; '
                      'разрешить уведомления можно в настройках сайта (значок замка в адресной строке).',
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(
                  _access.supported
                      ? 'Когда Родквест закрыт, будильник звонит системным уведомлением — нажмите на него, '
                          'чтобы выключить или отложить. Пока приложение открыто, звонит оно само.'
                      : 'Будильник звонит, пока Родквест открыт — в браузере или в приложении. '
                          'Если приложение было закрыто, при запуске покажем, что пропущено.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              SectionTitle('${hero.avatar} Мои'),
              if (mine.isEmpty)
                const EmptyHint(
                  emoji: '⏰',
                  text: 'Пока ничего нет. Поставьте будильник «Подъём» на будни или напоминание '
                      'к рутине — например, «Зарядка» в 7:15.',
                ),
              for (final r in mine) ReminderTile(reminder: r, now: now),
              if (others.isNotEmpty) ...[
                const SectionTitle('🛡 Семья'),
                for (final r in others) ReminderTile(reminder: r, now: now, showOwner: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ReminderTile extends StatelessWidget {
  const ReminderTile({super.key, required this.reminder, required this.now, this.showOwner = false});

  final Reminder reminder;
  final DateTime now;
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final r = reminder;
    final next = TimeRules.nextRing(r, now);
    final owner = game.heroById(r.heroId);
    final goal = game.goalById(r.goalId);
    final on = r.enabled && next != null;
    final canEdit = game.canEditReminder(r);
    final color = r.kind == ReminderKind.alarm ? RqColors.primary : RqColors.gold;
    return RqCard(
      onTap: canEdit ? () => openReminderEditor(context, reminder: r) : null,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Text(r.kind.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.timeLabel,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    fontFamily: RqColors.p.fontDisplay,
                    color: on ? RqColors.ink : RqColors.inkSoft,
                  ),
                ),
                Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    MiniPill(TimeRules.repeatLabel(r), color),
                    if (r.wakeUp) MiniPill('🌄 подъём', RqColors.xp),
                    if (goal != null) MiniPill('${goal.tier.emoji} ${goal.title}', RqColors.tier(goal.tier)),
                    if (showOwner && owner != null) MiniPill('${owner.avatar} ${owner.name}', RqColors.inkSoft),
                    if (on) MiniPill(TimeRules.untilLabel(next, now), RqColors.inkSoft),
                    if (r.snoozedUntil != null && on) MiniPill('💤 отложен', RqColors.inkSoft),
                  ],
                ),
              ],
            ),
          ),
          Switch(
            value: r.enabled,
            onChanged: canEdit ? (v) => game.setReminderEnabled(r.id, v) : null,
          ),
        ],
      ),
    );
  }
}

/// Редактор будильника/напоминания. [goal] — сразу связать с целью.
Future<void> openReminderEditor(BuildContext context, {Reminder? reminder, Goal? goal, ReminderKind? kind}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GameScope(
      controller: GameScope.read(context),
      child: _ReminderEditor(reminder: reminder, goal: goal, kind: kind),
    ),
  );
}

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({this.reminder, this.goal, this.kind});

  final Reminder? reminder;
  final Goal? goal;
  final ReminderKind? kind;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late final TextEditingController _title;
  late ReminderKind _kind;
  late TimeOfDay _time;
  Set<int> _days = {};
  DateTime? _date;
  String? _goalId;
  String? _ownerId;
  bool _wakeUp = false;
  int _snooze = 5;
  bool _inited = false;

  @override
  void initState() {
    super.initState();
    final r = widget.reminder;
    final g = widget.goal;
    _kind = r?.kind ?? widget.kind ?? (g != null ? ReminderKind.reminder : ReminderKind.alarm);
    _title = TextEditingController(text: r?.title ?? g?.title ?? '');
    _time = r != null ? TimeOfDay(hour: r.hour, minute: r.minute) : TimeOfDay(hour: g == null ? 7 : 9, minute: 0);
    _days = {...?r?.weekdays};
    _date = r?.date;
    _goalId = r?.goalId ?? g?.id;
    _ownerId = r?.heroId;
    _wakeUp = r?.wakeUp ?? (r == null && _kind == ReminderKind.alarm);
    _snooze = r?.snoozeMinutes ?? 5;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final game = GameScope.read(context);
    _ownerId ??= game.activeHero?.id;
    final g = widget.goal;
    if (widget.reminder == null && g != null) {
      if (g.isDaily) {
        // Напоминание к рутине — в её дни.
        if (g.repeat == Repeat.daily) _days = {...g.weekdays};
        if (g.repeat == Repeat.weekly && g.weekdays.isNotEmpty) _days = {g.weekdays.first};
      } else {
        final due = g.dueDate;
        final n = game.now;
        // К сроку: накануне в 9:00 (или сегодня, если срок уже скоро).
        final day = due == null
            ? DateTime(n.year, n.month, n.day + 1)
            : DateTime(due.year, due.month, due.day - 1).isBefore(DateTime(n.year, n.month, n.day))
                ? DateTime(due.year, due.month, due.day)
                : DateTime(due.year, due.month, due.day - 1);
        _date = day;
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Время',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) setState(() => _time = t);
  }

  Future<void> _pickDate() async {
    final now = GameScope.read(context).now;
    final today = DateTime(now.year, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 3)),
      helpText: 'Дата напоминания',
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final game = GameScope.read(context);
    final r = widget.reminder;
    if (r == null) {
      await game.addReminder(
        title: _title.text,
        kind: _kind,
        hour: _time.hour,
        minute: _time.minute,
        weekdays: _days.toList(),
        date: _date,
        goalId: _goalId,
        heroId: _ownerId,
        wakeUp: _wakeUp,
        snoozeMinutes: _snooze,
      );
    } else {
      await game.updateReminder(
        r,
        title: _title.text,
        kind: _kind,
        hour: _time.hour,
        minute: _time.minute,
        weekdays: _days.toList(),
        date: _date,
        goalId: _goalId,
        wakeUp: _wakeUp,
        snoozeMinutes: _snooze,
      );
    }
    // Хороший момент попросить разрешение на уведомления браузера.
    if (Notifier.permission == 'default') await Notifier.requestPermission();
    // В приложении — разрешение на системные уведомления (спросит один раз).
    final push = game.push;
    final access = await push.access();
    if (access.supported && !access.allowed) await push.request(exact: _kind == ReminderKind.alarm);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final theme = Theme.of(context);
    final me = game.activeHero!;
    final isEdit = widget.reminder != null;
    final goals = game.goals.where((g) => !g.done && (g.ownerId == me.id || g.isFamily)).toList()
      ..sort((a, b) => a.tier.rank.compareTo(b.tier.rank));
    if (_goalId != null && !goals.any((g) => g.id == _goalId)) {
      final g = game.goalById(_goalId);
      if (g != null) goals.insert(0, g);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Изменить' : 'Новый ${_kind == ReminderKind.alarm ? 'будильник' : 'напоминание'}',
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              SegmentedButton<ReminderKind>(
                showSelectedIcon: false,
                segments: [
                  for (final k in ReminderKind.values) ButtonSegment(value: k, label: Text('${k.emoji} ${k.label}')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  if (_kind == ReminderKind.reminder) _wakeUp = false;
                }),
              ),
              const SizedBox(height: 14),
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(RqColors.p.radius),
                  onTap: _pickTime,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    child: Text(
                      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        fontFamily: RqColors.p.fontDisplay,
                        color: RqColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
              Center(child: Text('нажмите, чтобы изменить время', style: theme.textTheme.bodySmall)),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                    hintText: _kind == ReminderKind.alarm ? 'Название: «Подъём»' : 'О чём напомнить'),
              ),
              _label(context, 'Когда'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Повторять'),
                    selected: _date == null,
                    onSelected: (_) => setState(() => _date = null),
                  ),
                  ChoiceChip(
                    label: Text(_date == null
                        ? '📅 Один раз'
                        : '📅 ${GameRules.shortDate(_date!)}.${_date!.year}'),
                    selected: _date != null,
                    onSelected: (_) => _pickDate(),
                  ),
                ],
              ),
              if (_date == null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(GameRules.weekdayShort[d - 1]),
                        showCheckmark: false,
                        selected: _days.contains(d),
                        onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                      ),
                    ActionChip(label: const Text('Будни'), onPressed: () => setState(() => _days = {1, 2, 3, 4, 5})),
                    ActionChip(label: const Text('Каждый день'), onPressed: () => setState(() => _days = {})),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      _days.isEmpty || _days.length == 7
                          ? 'Каждый день'
                          : 'По дням: ${(_days.toList()..sort()).map((d) => GameRules.weekdayShort[d - 1]).join(', ')}',
                      style: theme.textTheme.bodySmall),
                ),
              ],
              if (_kind == ReminderKind.alarm) ...[
                _label(context, 'Отложить на'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final m in const [5, 10, 15])
                      ChoiceChip(label: Text('$m мин'), selected: _snooze == m, onSelected: (_) => setState(() => _snooze = m)),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _wakeUp,
                  onChanged: (v) => setState(() => _wakeUp = v),
                  title: const Text('🌄 Это подъём', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Выключите не позже 10 минут после звонка — +5 XP, монеты '
                      'и ⏰ пунктуальность (раз в день)'),
                ),
              ],
              _label(context, 'Связать с целью (необязательно)'),
              if (goals.isEmpty)
                Text('Нет активных целей.', style: theme.textTheme.bodySmall)
              else
                DropdownButton<String?>(
                  isExpanded: true,
                  value: goals.any((g) => g.id == _goalId) ? _goalId : null,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Без цели')),
                    for (final g in goals)
                      DropdownMenuItem<String?>(
                        value: g.id,
                        child: Text('${g.tier.emoji} ${g.title}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _goalId = v;
                    if (v != null && _title.text.trim().isEmpty) _title.text = game.goalById(v)?.title ?? '';
                  }),
                ),
              if (me.role.isAdult && game.heroes.length > 1 && !isEdit) ...[
                _label(context, 'Для кого'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final h in game.heroes)
                      ChoiceChip(
                        label: Text('${h.avatar} ${h.name}'),
                        selected: _ownerId == h.id,
                        onSelected: (_) => setState(() => _ownerId = h.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              ChunkyButton(label: isEdit ? 'Сохранить' : 'Поставить', icon: _kind.emoji, onPressed: _save),
              if (isEdit) ...[
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    icon: Icon(Icons.delete_outline_rounded, color: RqColors.danger),
                    label: Text('Удалить', style: TextStyle(color: RqColors.danger, fontWeight: FontWeight.w800)),
                    onPressed: () async {
                      await game.deleteReminder(widget.reminder!.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget _label(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
    );

/// Ближайший звонок героя — для карточки на экране «Сегодня».
(Reminder, DateTime)? nextReminderOf(GameController game, String heroId) {
  final now = game.now;
  (Reminder, DateTime)? best;
  for (final r in game.remindersOf(heroId)) {
    final t = TimeRules.nextRing(r, now);
    if (t != null && (best == null || t.isBefore(best.$2))) best = (r, t);
  }
  return best;
}
