/// v0.9: как называется своя группа — «Семья» или «Клан» (на выбор главы).
///
/// Раньше семья называлась «гильдией». С версии 0.9 гильдия — уровень выше:
/// в неё вступают семьи, кланы и одиночные герои (см. lib/sync/alliance.dart).
enum GroupKind { family, clan }

extension GroupKindInfo on GroupKind {
  String get label => switch (this) {
        GroupKind.family => 'Семья',
        GroupKind.clan => 'Клан',
      };

  String get emoji => switch (this) {
        GroupKind.family => '🏡',
        GroupKind.clan => '⚔️',
      };

  String get hint => switch (this) {
        GroupKind.family => 'Родители и дети, общие дела дома',
        GroupKind.clan => 'Друзья, соседи, команда — кто угодно',
      };

  static GroupKind fromName(Object? name) => name == 'clan' ? GroupKind.clan : GroupKind.family;
}

/// Слова для текущей группы. Контроллер обновляет [kind] при загрузке и
/// изменении данных — экраны просто берут нужную форму слова.
class Words {
  const Words._();

  static GroupKind kind = GroupKind.family;

  static bool get clan => kind == GroupKind.clan;

  /// Семья / Клан
  static String get group => kind.label;

  /// семья / клан
  static String get groupLower => clan ? 'клан' : 'семья';

  /// (нет) семьи / клана
  static String get groupGen => clan ? 'клана' : 'семьи';

  /// (к) семье / клану
  static String get groupDat => clan ? 'клану' : 'семье';

  /// (в) семью / клан
  static String get groupAcc => clan ? 'клан' : 'семью';

  /// (в) семье / клане
  static String get groupPrep => clan ? 'клане' : 'семье';

  /// (всей) семьёй / кланом
  static String get groupIns => clan ? 'кланом' : 'семьёй';

  static String get emoji => kind.emoji;

  /// Глава семьи / Глава клана
  static String get leader => 'Глава $groupGen';

  /// главе семьи / главе клана
  static String get leaderDat => 'главе $groupGen';

  /// Семейная цель / Цель клана
  static String get sharedGoal => clan ? 'Цель клана' : 'Семейная цель';

  /// Семейные цели / Цели клана
  static String get sharedGoals => clan ? 'Цели клана' : 'Семейные цели';

  /// Короткая метка общей цели: «семья» / «клан».
  static String get sharedPill => groupLower;

  /// Члены семьи / Участники клана
  static String get people => clan ? 'Участники клана' : 'Члены семьи';
}
