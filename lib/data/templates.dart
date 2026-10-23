import '../models/models.dart';

/// Узел шаблона: цель со вложенными шагами.
class TplNode {
  const TplNode(
    this.title,
    this.tier, {
    this.description = '',
    this.stat,
    this.area,
    this.repeat = Repeat.daily,
    this.weekdays = const [],
    this.monthDay,
    this.children = const [],
  });

  final String title;
  final GoalTier tier;
  final String description;
  final HeroStat? stat;
  final LifeArea? area;
  final Repeat repeat;
  final List<int> weekdays;
  final int? monthDay;
  final List<TplNode> children;

  int get count => 1 + children.fold<int>(0, (s, c) => s + c.count);
}

/// Готовый план для «взрослой» темы: деньги, здоровье, документы, карьера…
/// Создаёт цепочку целей, которую потом можно отредактировать под себя.
class GoalTemplate {
  const GoalTemplate({
    required this.id,
    required this.title,
    required this.emoji,
    required this.area,
    required this.description,
    required this.nodes,
    this.adultOnly = true,
  });

  final String id;
  final String title;
  final String emoji;
  final LifeArea area;
  final String description;
  final List<TplNode> nodes;
  final bool adultOnly;

  int get count => nodes.fold<int>(0, (s, n) => s + n.count);
}

// Короткие помощники, чтобы шаблоны читались как план.
TplNode _t(String title, {String d = ''}) => TplNode(title, GoalTier.task, description: d);
TplNode _q(String title, List<TplNode> steps, {String d = ''}) =>
    TplNode(title, GoalTier.quest, description: d, children: steps);
TplNode _daily(String title, {List<int> days = const []}) => TplNode(title, GoalTier.daily, weekdays: days);
TplNode _weekly(String title, {int? day}) =>
    TplNode(title, GoalTier.daily, repeat: Repeat.weekly, weekdays: day == null ? const [] : [day]);
TplNode _monthly(String title, {int? day}) => TplNode(title, GoalTier.daily, repeat: Repeat.monthly, monthDay: day);

const _fin = LifeArea.finance;

final goalTemplates = <GoalTemplate>[
  // ---------- Финансы ----------
  GoalTemplate(
    id: 'safety_cushion',
    title: 'Финансовая подушка',
    emoji: '🛟',
    area: _fin,
    description: 'Запас на 3–6 месяцев обязательных расходов на случай болезни или потери работы.',
    nodes: [
      TplNode('Финансовая подушка на 6 месяцев', GoalTier.epic,
          description: 'Деньги «на чёрный день» — отдельно от повседневных трат. '
              'Укажите сумму («💰 Накопить сумму на цель») — копилка появится в «Бюджете».',
          children: [
            _q('Посчитать, сколько нужно', [
              _t('Выписать обязательные расходы за 3 месяца', d: 'Жильё, еда, транспорт, кредиты, связь, лекарства'),
              _t('Посчитать средние расходы в месяц'),
              _t('Умножить на 6 — это цель подушки'),
            ]),
            _q('Где хранить', [
              _t('Сравнить накопительные счета и вклады в 2–3 банках'),
              _t('Открыть отдельный счёт только для подушки'),
              _t('Настроить автоперевод в день зарплаты'),
            ]),
            _monthly('Отложить 10% дохода в подушку', day: 10),
          ]),
    ],
  ),
  GoalTemplate(
    id: 'debts',
    title: 'Закрыть кредиты и долги',
    emoji: '💳',
    area: _fin,
    description: 'План выхода из долгов: список, стратегия, рефинансирование, ежемесячные платежи.',
    nodes: [
      TplNode('Жить без долгов', GoalTier.legend, children: [
        _q('Навести порядок в долгах', [
          _t('Выписать все долги: сумма, ставка, платёж, дата', d: 'Кредиты, кредитные карты, рассрочки, займы'),
          _t('Выбрать стратегию', d: '«Лавина» — сначала самая высокая ставка; «снежный ком» — сначала самый маленький долг'),
          _t('Узнать условия рефинансирования в 2–3 банках'),
          _t('Отказаться от новых займов и рассрочек на время плана'),
        ]),
        TplNode('Закрыть первый долг', GoalTier.epic, children: [
          _t('Платить по выбранному долгу больше минимума'),
          _t('Получить справку о закрытии долга'),
        ]),
        _monthly('Внести платежи по кредитам вовремя', day: 5),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'tax_deduction',
    title: 'Налоговый вычет',
    emoji: '🧾',
    area: _fin,
    description: 'Вернуть часть НДФЛ за лечение, обучение, спорт или покупку жилья.',
    nodes: [
      _q('Получить налоговый вычет', [
        _t('Проверить, на какие вычеты есть право', d: 'Лечение, лекарства, обучение, спорт, жильё, ипотечные проценты'),
        _t('Собрать документы и чеки', d: 'Договоры, справки об оплате, чеки — по каждому виду вычета свои'),
        _t('Проверить сведения о доходах в личном кабинете налогоплательщика'),
        _t('Заполнить и отправить декларацию 3‑НДФЛ или заявление на упрощённый вычет'),
        _t('Отследить статус проверки и поступление денег'),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'home_purchase',
    title: 'Своё жильё',
    emoji: '🏡',
    area: _fin,
    description: 'Большая цель: первоначальный взнос, выбор ипотеки и квартиры, сделка.',
    nodes: [
      TplNode('Купить своё жильё', GoalTier.legend, stat: HeroStat.mastery, children: [
        TplNode('Накопить первоначальный взнос', GoalTier.epic, children: [
          _t('Определить бюджет покупки и размер взноса'),
          _t('Открыть отдельный накопительный счёт'),
          _monthly('Пополнить счёт на взнос', day: 10),
        ]),
        TplNode('Выбрать ипотеку', GoalTier.epic, children: [
          _t('Проверить кредитную историю'),
          _t('Узнать о льготных программах для своей семьи'),
          _t('Сравнить ставки и условия в 3 банках'),
          _t('Получить предварительное одобрение'),
        ]),
        TplNode('Выбрать квартиру', GoalTier.epic, children: [
          _t('Составить требования: район, площадь, этаж, транспорт'),
          _t('Посмотреть не меньше 10 вариантов'),
          _t('Проверить юридическую чистоту выбранного варианта'),
        ]),
        _q('Сделка', [
          _t('Оценка и страхование'),
          _t('Подписать договор'),
          _t('Зарегистрировать право собственности'),
        ]),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'investing',
    title: 'Инвестиции и будущая пенсия',
    emoji: '📈',
    area: _fin,
    description: 'Спокойный долгосрочный план: основы, цель, счёт, регулярные пополнения.',
    nodes: [
      TplNode('Начать инвестировать на долгий срок', GoalTier.epic, children: [
        _q('Разобраться в основах', [
          _t('Прочитать одну книгу об инвестициях для начинающих'),
          _t('Понять разницу между вкладом, облигациями, акциями и фондами'),
          _t('Сначала собрать подушку безопасности'),
        ]),
        _q('Составить план', [
          _t('Записать цель, срок и сумму'),
          _t('Выбрать брокера и тип счёта'),
          _t('Решить, в каких долях распределять деньги'),
        ]),
        _monthly('Пополнить инвестиционный счёт', day: 15),
        _monthly('Не трогать и не паниковать: проверить план раз в месяц', day: 28),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'family_budget',
    title: 'Семейный бюджет под контролем',
    emoji: '📊',
    area: _fin,
    description: 'Учёт расходов, лимиты, ежемесячный разбор — вместе с вкладкой «Бюджет».',
    nodes: [
      _q('Навести порядок в бюджете', [
        _t('Записывать все расходы месяц', d: 'Используйте вкладку «Бюджет» — она посчитает остаток'),
        _t('Поставить лимиты на 3 самые большие категории'),
        _t('Найти и отключить ненужные подписки'),
        _monthly('Семейный разбор бюджета', day: 1),
      ]),
    ],
  ),

  // ---------- Здоровье ----------
  GoalTemplate(
    id: 'checkup',
    title: 'Ежегодный чек-ап',
    emoji: '🩺',
    area: LifeArea.health,
    description: 'Профилактика раз в год: терапевт, анализы, стоматолог, зрение.',
    nodes: [
      _q('Пройти обследование в этом году', [
        _t('Записаться к терапевту или на диспансеризацию'),
        _t('Сдать анализы, которые назначит врач'),
        _t('Сходить к стоматологу'),
        _t('Проверить зрение'),
        _t('Обсудить с врачом дополнительные обследования по возрасту'),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'sleep',
    title: 'Наладить сон',
    emoji: '😴',
    area: LifeArea.health,
    description: 'Режим, вечерний ритуал и спальня, в которой хорошо спится.',
    nodes: [
      TplNode('Высыпаться каждый день', GoalTier.epic, children: [
        _daily('Лечь спать до 23:30'),
        _daily('Без экрана за час до сна'),
        _t('Не пить кофе после 16:00 — попробовать неделю'),
        _t('Сделать спальню тёмной, тихой и прохладной'),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'fitness',
    title: 'Вернуть форму',
    emoji: '🏋️',
    area: LifeArea.sport,
    description: 'Тренировки по расписанию, шаги, стартовые замеры.',
    nodes: [
      TplNode('Вернуть спортивную форму', GoalTier.epic, children: [
        _t('Записать стартовые замеры', d: 'Добавьте навыки «Отжимания» или «Бег 1 км» — рекорды покажут прогресс'),
        _t('Составить план тренировок на месяц'),
        _daily('Тренировка', days: [1, 3, 5]),
        _daily('Пройти 8000 шагов'),
        _weekly('Длинная прогулка или поход', day: 7),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'stress',
    title: 'Меньше стресса',
    emoji: '🧘',
    area: LifeArea.mind,
    description: 'Паузы в течение дня, прогулки и разбор того, что выматывает.',
    nodes: [
      TplNode('Жить спокойнее', GoalTier.epic, children: [
        _t('Выписать 3 главных источника стресса и что можно изменить'),
        _daily('10 минут тишины без телефона'),
        _weekly('Прогулка на природе'),
        _t('Если тяжело долго — записаться к психологу'),
      ]),
    ],
  ),

  // ---------- Карьера ----------
  GoalTemplate(
    id: 'career_growth',
    title: 'Повышение или новая работа',
    emoji: '💼',
    area: LifeArea.career,
    description: 'Достижения, навыки, рынок и разговор о зарплате.',
    nodes: [
      TplNode('Выйти на новый уровень в работе', GoalTier.legend, children: [
        _q('Подготовка', [
          _t('Собрать список своих достижений за год с цифрами'),
          _t('Обновить резюме и профиль на сайтах вакансий'),
          _t('Узнать рыночную зарплату для своей должности'),
        ]),
        _q('Прокачать навыки', [
          _t('Выбрать один курс или книгу по профессии'),
          _weekly('2 часа на профессиональное обучение'),
        ]),
        _q('Разговор', [
          _t('Назначить встречу с руководителем'),
          _t('Подготовить аргументы и желаемую сумму'),
          _t('Провести разговор и договориться о сроках'),
        ]),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'side_business',
    title: 'Своё дело',
    emoji: '🚀',
    area: LifeArea.career,
    description: 'От идеи до первого клиента — без увольнения с основной работы.',
    nodes: [
      TplNode('Запустить своё дело', GoalTier.legend, children: [
        _q('Проверить идею', [
          _t('Описать, кому и какую проблему решаю'),
          _t('Поговорить с 10 потенциальными клиентами'),
          _t('Посчитать расходы и цену'),
        ]),
        _q('Оформить', [
          _t('Выбрать форму: самозанятость, ИП или ООО'),
          _t('Зарегистрироваться и открыть счёт'),
        ]),
        _q('Первые продажи', [
          _t('Сделать простую страницу или профиль с предложением'),
          _t('Получить первого платящего клиента'),
        ]),
      ]),
    ],
  ),

  // ---------- Документы и дела ----------
  GoalTemplate(
    id: 'documents',
    title: 'Документы в порядке',
    emoji: '📑',
    area: LifeArea.docs,
    description: 'Сроки паспортов, полисы, страховки, электронные копии.',
    nodes: [
      _q('Привести документы в порядок', [
        _t('Проверить сроки паспорта и загранпаспорта у всей семьи'),
        _t('Проверить полисы ОМС, СНИЛС и ИНН'),
        _t('Сделать электронные копии документов и хранить их надёжно'),
        _t('Собрать бумаги в одну папку: свидетельства, договоры, гарантии'),
        _monthly('Проверить штрафы, налоги и счета', day: 20),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'family_safety',
    title: 'Защита семьи',
    emoji: '🛡',
    area: LifeArea.docs,
    description: 'Страховки, доверенности и инструкция для близких «если что-то случится».',
    nodes: [
      TplNode('Защитить семью от неожиданностей', GoalTier.epic, children: [
        _t('Застраховать жильё'),
        _t('Сравнить страхование жизни и здоровья'),
        _t('Оформить доверенности, если нужны'),
        _t('Составить для близких список счетов, страховок и контактов',
            d: 'Без паролей в открытом виде — храните их в менеджере паролей'),
        _t('Узнать у нотариуса, как оформить завещание'),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'car',
    title: 'Машина без сюрпризов',
    emoji: '🚗',
    area: LifeArea.car,
    description: 'ТО, шины, страховка и аптечка — по расписанию.',
    nodes: [
      _q('Обслуживать машину вовремя', [
        _t('Записать даты ОСАГО, ТО и замены масла'),
        _t('Проверить аптечку, огнетушитель и знак'),
        _monthly('Проверить давление в шинах и жидкости', day: 1),
      ]),
    ],
  ),

  // ---------- Дом и семья ----------
  GoalTemplate(
    id: 'renovation',
    title: 'Ремонт',
    emoji: '🔧',
    area: LifeArea.home,
    description: 'Смета, бригада, закупки, приёмка работ.',
    nodes: [
      TplNode('Сделать ремонт', GoalTier.epic, children: [
        _q('Спланировать', [
          _t('Решить, что именно меняем, и сделать план помещений'),
          _t('Составить смету с запасом 15–20%'),
          _t('Получить 3 сметы от разных мастеров'),
        ]),
        _q('Сделать', [
          _t('Заключить договор с этапами и сроками'),
          _t('Закупить материалы'),
          _weekly('Проверить ход работ'),
          _t('Принять работы и сохранить гарантии'),
        ]),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'couple',
    title: 'Время для пары',
    emoji: '❤️',
    area: LifeArea.family,
    description: 'Регулярные свидания и честные разговоры о планах.',
    nodes: [
      TplNode('Укрепить отношения', GoalTier.quest, stat: HeroStat.charisma, children: [
        _weekly('Свидание вдвоём', day: 5),
        _monthly('Разговор о планах, деньгах и мечтах'),
        _t('Спланировать выходные только вдвоём'),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'parents',
    title: 'Забота о родителях',
    emoji: '👵',
    area: LifeArea.family,
    description: 'Звонки, визиты и помощь с врачами и документами.',
    nodes: [
      TplNode('Быть рядом с родителями', GoalTier.quest, stat: HeroStat.charisma, children: [
        _weekly('Позвонить родителям', day: 7),
        _monthly('Навестить родителей'),
        _t('Помочь записаться к врачу или с документами'),
      ]),
    ],
  ),

  // ---------- Для всех ----------
  GoalTemplate(
    id: 'reading',
    title: 'Читать каждый день',
    emoji: '📖',
    area: LifeArea.study,
    description: 'Привычка чтения и список книг на год.',
    adultOnly: false,
    nodes: [
      TplNode('Прочитать 12 книг за год', GoalTier.epic, stat: HeroStat.intellect, children: [
        _t('Составить список из 12 книг'),
        _daily('Прочитать 10 страниц'),
      ]),
    ],
  ),
  GoalTemplate(
    id: 'language',
    title: 'Выучить язык',
    emoji: '🗣',
    area: LifeArea.study,
    description: 'Слова каждый день, занятия по расписанию, первый разговор.',
    adultOnly: false,
    nodes: [
      TplNode('Заговорить на новом языке', GoalTier.epic, stat: HeroStat.intellect, children: [
        _t('Выбрать учебник или приложение'),
        _daily('10 новых слов'),
        _daily('Занятие 30 минут', days: [2, 4]),
        _t('Поговорить 10 минут с носителем'),
      ]),
    ],
  ),
];

/// Готовые варианты навыков для быстрого добавления.
class SkillPreset {
  const SkillPreset(this.name, this.emoji, this.unit,
      {this.better = SkillBetter.higher, this.timed = false, this.area = LifeArea.sport});

  final String name;
  final String emoji;
  final String unit;
  final SkillBetter better;
  final bool timed;
  final LifeArea area;
}

const skillPresets = <SkillPreset>[
  SkillPreset('Отжимания', '💪', 'раз'),
  SkillPreset('Подтягивания', '🧗', 'раз'),
  SkillPreset('Приседания', '🦵', 'раз'),
  SkillPreset('Планка', '🧱', '', timed: true),
  SkillPreset('Бег 1 км', '🏃', '', timed: true, better: SkillBetter.lower),
  SkillPreset('Бег 5 км', '🏃‍♀️', '', timed: true, better: SkillBetter.lower),
  SkillPreset('Шаги за день', '👟', 'шагов', area: LifeArea.health),
  SkillPreset('Скорость печати', '⌨️', 'зн/мин', area: LifeArea.career),
  SkillPreset('Новые слова', '🗣', 'слов', area: LifeArea.study),
  SkillPreset('Чтение', '📖', 'стр.', area: LifeArea.study),
  SkillPreset('Сборка кубика', '🧩', '', timed: true, better: SkillBetter.lower, area: LifeArea.hobby),
  SkillPreset('Игра на гитаре', '🎸', 'мин', area: LifeArea.hobby),
];
