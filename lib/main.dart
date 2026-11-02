import 'native/native_word_screen.dart';

import 'package:flutter/material.dart';

void main() => runApp(const ArtOfficeCraftApp());

enum EditorKind { word, excel, slides, pdf }

extension EditorInfo on EditorKind {
  String get title => switch (this) {
    EditorKind.word => 'Документ.docx',
    EditorKind.excel => 'Книга.xlsx',
    EditorKind.slides => 'Презентация.pptx',
    EditorKind.pdf => 'Документ.pdf',
  };
  String get label => switch (this) {
    EditorKind.word => 'Документ',
    EditorKind.excel => 'Таблица',
    EditorKind.slides => 'Презентация',
    EditorKind.pdf => 'PDF',
  };
  String get format => switch (this) {
    EditorKind.word => 'DOCX',
    EditorKind.excel => 'XLSX',
    EditorKind.slides => 'PPTX',
    EditorKind.pdf => 'PDF',
  };
  IconData get glyph => switch (this) {
    EditorKind.word => Icons.description_outlined,
    EditorKind.excel => Icons.grid_on_outlined,
    EditorKind.slides => Icons.slideshow_outlined,
    EditorKind.pdf => Icons.picture_as_pdf_outlined,
  };
  Color get tint => switch (this) {
    EditorKind.word => const Color(0xff4876cd),
    EditorKind.excel => const Color(0xff148259),
    EditorKind.slides => const Color(0xffd57345),
    EditorKind.pdf => const Color(0xffbd4c5a),
  };
}

class ArtOfficeCraftApp extends StatefulWidget {
  const ArtOfficeCraftApp({super.key});
  @override
  State<ArtOfficeCraftApp> createState() => _ArtOfficeCraftAppState();
}

class _ArtOfficeCraftAppState extends State<ArtOfficeCraftApp> {
  ThemeMode theme = ThemeMode.dark;
  @override
  Widget build(BuildContext context) {
    const background = Color(0xff11151b);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ArtOfficeCraft Mobile',
      themeMode: theme,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff426db7)),
        scaffoldBackgroundColor: const Color(0xfff5f7fa),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff5b88d4),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: background,
      ),
      home: HomeScreen(
        theme: theme,
        toggleTheme: () => setState(() {
          theme = theme == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        }),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.toggleTheme, required this.theme});
  final VoidCallback toggleTheme;
  final ThemeMode theme;
  void open(BuildContext context, EditorKind kind) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => kind == EditorKind.word
            ? const NativeWordScreen()
            : EditorScreen(kind: kind),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ArtOfficeCraft',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Документы · Таблицы · Слайды · PDF',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Изменить тему',
            icon: Icon(
              theme == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
            onPressed: toggleTheme,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              gradient: const LinearGradient(
                colors: [Color(0xff19335e), Color(0xff315c99)],
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ARTOFFICECRAFT MOBILE',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
                SizedBox(height: 9),
                Text(
                  'Четыре редактора.\nОдно приложение.',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Интерактивный Flutter-прототип интерфейса',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Создать',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 12),
          GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            crossAxisCount: 2,
            mainAxisSpacing: 11,
            crossAxisSpacing: 11,
            childAspectRatio: 1.9,
            children: EditorKind.values
                .map(
                  (kind) => Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => open(context, kind),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: kind.tint,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                kind.glyph,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    kind.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    kind.format,
                                    style: TextStyle(
                                      color: dark
                                          ? Colors.white54
                                          : Colors.black54,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
          const Text(
            'Рабочие пространства',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          const SizedBox(height: 8),
          ...EditorKind.values.map(
            (kind) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
              leading: Icon(kind.glyph, color: kind.tint),
              title: Text(kind.title, style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                'Демонстрационный документ · ${kind.format}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(context, kind),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Предпросмотр интерфейса. Настоящие файлы Office ещё не импортируются '
            'и не сохраняются: интеграция нативных движков выполняется отдельно.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.kind});
  final EditorKind kind;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  bool tools = false;
  bool readOnly = false;
  String tab = 'Главная';
  final text = TextEditingController(
    text:
        'План развития проекта\n\nArtOfficeCraft Mobile объединяет '
        'текстовые документы, электронные таблицы, презентации и PDF '
        'в одном Android-приложении.\n\nОсновные принципы\n\n'
        'Документы открываются локально. Управление предсказуемо: '
        'основная рабочая область занимает максимум доступного пространства. '
        'Текст по умолчанию выровнен по ширине; переносы отключены.',
  );
  final formula = TextEditingController();
  final Map<int, Map<String, String>> sheets = {
    0: {
      'A1': 'Месяц',
      'B1': 'Выручка',
      'C1': 'Расходы',
      'D1': 'Прибыль',
      'A2': 'Январь',
      'B2': '150000',
      'C2': '92000',
      'D2': '=B2-C2',
      'A3': 'Февраль',
      'B3': '172000',
      'C3': '106000',
      'D3': '=B3-C3',
      'A4': 'Март',
      'B4': '184000',
      'C4': '110000',
      'D4': '=B4-C4',
    },
    1: {'A1': 'Отдельный лист', 'B1': 'Значение'},
  };
  Map<String, String> get cells => sheets.putIfAbsent(sheet, () => {});
  int sheet = 0;
  int sheetCount = 2;
  String cell = 'B2';
  int slide = 0;
  final slides = <List<String>>[
    ['Обзор проекта', 'ArtOfficeCraft Mobile · единый офис Android'],
    ['Четыре редактора', 'Документы · Таблицы · Презентации · PDF'],
    ['Офлайн', 'Данные остаются на устройстве'],
  ];
  int page = 0;
  int turn = 0;
  final Map<int, List<String>> notes = {};
  bool showSheets = false;
  bool highlight = false;
  TextAlign wordAlign = TextAlign.justify;
  double wordScale = 1;
  @override
  void initState() {
    super.initState();
    formula.text = cells[cell] ?? '';
  }

  @override
  void dispose() {
    text.dispose();
    formula.dispose();
    super.dispose();
  }

  void chooseCell(String key) {
    setState(() {
      cell = key;
      formula.text = cells[key] ?? '';
    });
  }

  void commitCell() {
    setState(() {
      cells[cell] = formula.text;
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  List<String> get tabs => switch (widget.kind) {
    EditorKind.word => [
      'Главная',
      'Вставить',
      'Макет',
      'Рецензирование',
      'Вид',
    ],
    EditorKind.excel => [
      'Главная',
      'Вставить',
      'Формулы',
      'Данные',
      'Рецензирование',
      'Вид',
    ],
    EditorKind.slides => [
      'Главная',
      'Вставить',
      'Дизайн',
      'Переходы',
      'Показ',
      'Вид',
    ],
    EditorKind.pdf => ['Аннотации', 'Страницы', 'Вид'],
  };
  void message(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
  );
  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kind.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Text(
              '${readOnly ? 'Просмотр' : 'Правка'} · ${kind.format}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: readOnly ? 'Перейти к правке' : 'Только просмотр',
            onPressed: () => setState(() {
              readOnly = !readOnly;
            }),
            icon: Icon(
              readOnly ? Icons.edit_outlined : Icons.visibility_outlined,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'about', child: Text('О прототипе')),
            ],
            onSelected: (_) => message(
              'Демонстрационное состояние. Сохранение файлов подключим через Rust.',
            ),
          ),
        ],
      ),
      body: switch (kind) {
        EditorKind.word => wordBody(),
        EditorKind.excel => excelBody(),
        EditorKind.slides => slidesBody(),
        EditorKind.pdf => pdfBody(),
      },
      bottomNavigationBar: SafeArea(top: false, child: bottomTools()),
    );
  }

  Widget wordBody() => Column(
    children: [
      Container(
        height: 35,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: const Text(
          '▤  Страница 1 из 1     ·     A4',
          style: TextStyle(fontSize: 11),
        ),
      ),
      Expanded(
        child: ColoredBox(
          color: const Color(0xffd3d8df),
          child: ListView(
            padding: const EdgeInsets.all(13),
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 530),
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 27,
                  vertical: 35,
                ),
                child: TextField(
                  controller: text,
                  readOnly: readOnly,
                  maxLines: null,
                  style: TextStyle(
                    fontFamily: 'serif',
                    color: const Color(0xff223048),
                    fontSize: 14 * wordScale,
                    height: 1.55,
                  ),
                  textAlign: wordAlign,
                  decoration: const InputDecoration.collapsed(
                    hintText: 'Введите текст документа',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Container(
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Text(
          'Символов: ${text.text.length} · Демонстрация WordCraft',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    ],
  );
  String column(int index) => String.fromCharCode(65 + index);
  Widget excelBody() => Column(
    children: [
      Expanded(
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Colors.white),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(74),
                border: TableBorder.all(
                  color: const Color(0xffd9dde2),
                  width: .7,
                ),
                children: [
                  TableRow(
                    children: [
                      head('', corner: true),
                      for (int x = 0; x < 12; x++) head(column(x)),
                    ],
                  ),
                  for (int r = 1; r <= 70; r++)
                    TableRow(
                      children: [
                        head(r.toString(), corner: true),
                        for (int c = 0; c < 12; c++)
                          cellWidget(column(c) + r.toString()),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      Container(
        height: 43,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Text(
              'ƒₓ',
              style: TextStyle(fontSize: 21, fontStyle: FontStyle.italic),
            ),
            const SizedBox(width: 8),
            Text(
              cell,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: TextField(
                controller: formula,
                readOnly: readOnly,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Значение или формула',
                ),
                onSubmitted: (_) => commitCell(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Отменить ввод',
              onPressed: () => setState(() {
                formula.text = cells[cell] ?? '';
              }),
            ),
            IconButton(
              icon: const Icon(Icons.check, size: 19, color: Colors.green),
              tooltip: 'Применить',
              onPressed: readOnly ? null : commitCell,
            ),
          ],
        ),
      ),
      if (showSheets)
        Row(
          children: [
            for (int i = 0; i < sheetCount; i++)
              TextButton(
                onPressed: () => setState(() {
                  sheet = i;
                }),
                child: Text(
                  'Лист ${i + 1}',
                  style: TextStyle(
                    fontWeight: i == sheet ? FontWeight.bold : null,
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Новый лист',
              onPressed: () => setState(() {
                sheetCount++;
                sheet = sheetCount - 1;
              }),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
    ],
  );
  Widget head(String value, {bool corner = false}) => Container(
    height: 28,
    alignment: Alignment.center,
    color: const Color(0xff0f1317),
    child: Text(
      value,
      style: const TextStyle(color: Color(0xffc5c9d0), fontSize: 11),
    ),
  );
  Widget cellWidget(String id) => InkWell(
    onTap: () => chooseCell(id),
    child: Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: id == cell
            ? Border.all(color: const Color(0xff158452), width: 2)
            : null,
      ),
      child: Text(
        cells[id] ?? '',
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(color: Color(0xff202b36), fontSize: 11),
      ),
    ),
  );
  Widget slidesBody() => Column(
    children: [
      SizedBox(
        height: 88,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(7),
          children: [
            for (int i = 0; i < slides.length; i++)
              InkWell(
                onTap: () => setState(() {
                  slide = i;
                }),
                child: Container(
                  width: 113,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: slide == i
                          ? Colors.deepOrange
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Text(
                    slides[i][0],
                    style: const TextStyle(
                      color: Color(0xff273450),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            IconButton(
              onPressed: addSlide,
              tooltip: 'Добавить слайд',
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      Expanded(
        child: Container(
          color: const Color(0xff293644),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xffd67648), width: 6),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slides[slide][0],
                    style: const TextStyle(
                      color: Color(0xff273750),
                      fontWeight: FontWeight.w800,
                      fontSize: 23,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    slides[slide][1],
                    style: const TextStyle(
                      color: Color(0xff66748c),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Слайд ${slide + 1} из ${slides.length}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: editSlide,
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('Текст слайда'),
          ),
          TextButton.icon(
            onPressed: showSlide,
            icon: const Icon(Icons.play_arrow, size: 19),
            label: const Text('Показ'),
          ),
        ],
      ),
    ],
  );
  void addSlide() => setState(() {
    slides.add(['Новый слайд', 'Добавьте текст']);
    slide = slides.length - 1;
  });
  Future<void> editSlide() async {
    final name = TextEditingController(text: slides[slide][0]);
    final subtitle = TextEditingController(text: slides[slide][1]);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изменить слайд'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Заголовок'),
            ),
            TextField(
              controller: subtitle,
              decoration: const InputDecoration(labelText: 'Подзаголовок'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                slides[slide] = [name.text, subtitle.text];
              });
              Navigator.pop(context);
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    );
    name.dispose();
    subtitle.dispose();
  }

  void showSlide() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(slides[slide][0]),
      content: Text(slides[slide][1]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
  Widget pdfBody() => Container(
    color: const Color(0xff29313d),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Страница ${page + 1} из 3',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
              IconButton(
                tooltip: 'Повернуть страницу',
                onPressed: () => setState(() {
                  turn = (turn + 1) % 4;
                }),
                icon: const Icon(Icons.rotate_right, color: Colors.white70),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(11),
              child: RotatedBox(
                quarterTurns: turn,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 480),
                  color: Colors.white,
                  padding: const EdgeInsets.all(29),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ARTOFFICECRAFT / OFFICE SUITE',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xff546d87),
                        ),
                      ),
                      const SizedBox(height: 38),
                      Text(
                        [
                          'Руководство пользователя',
                          'Основные функции',
                          'Подписи и формы',
                        ][page],
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff293e5e),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Эта страница — образец интерфейса просмотра PDF. '
                        'Нативный движок PDFCraft ещё не подключён.',
                        style: TextStyle(
                          fontSize: 13,
                          backgroundColor: highlight
                              ? Colors.yellowAccent
                              : Colors.transparent,
                          color: const Color(0xff273850),
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (final note in notes[page] ?? <String>[])
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(9),
                          color: const Color(0xffffeab4),
                          child: Text(
                            'Комментарий: $note',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Future<void> addNote() async {
    final input = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Комментарий к странице'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Текст комментария'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                setState(() {
                  notes.putIfAbsent(page, () => []).add(input.text.trim());
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    input.dispose();
  }

  Widget bottomTools() {
    if (widget.kind == EditorKind.excel && !tools) {
      return Container(
        height: 52,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.view_carousel_outlined),
              label: const Text('Листы'),
              onPressed: () => setState(() {
                showSheets = !showSheets;
              }),
            ),
            IconButton(
              onPressed: () => message('Поиск подключим к данным GridCraft'),
              tooltip: 'Поиск',
              icon: const Icon(Icons.search),
            ),
            IconButton(
              onPressed: () => setState(() {
                tools = true;
                tab = 'Данные';
              }),
              tooltip: 'Инструменты данных',
              icon: const Icon(Icons.filter_list),
            ),
            IconButton(
              onPressed: () => setState(() {
                tools = true;
              }),
              tooltip: 'Открыть инструменты',
              icon: const Icon(Icons.more_horiz),
            ),
          ],
        ),
      );
    }
    if (widget.kind == EditorKind.pdf) {
      return SizedBox(
        height: 53,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              onPressed: page == 0
                  ? null
                  : () => setState(() {
                      page--;
                    }),
              tooltip: 'Предыдущая страница',
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              onPressed: () => setState(() {
                highlight = !highlight;
              }),
              tooltip: 'Выделить текст',
              icon: const Icon(Icons.format_color_fill),
            ),
            IconButton(
              onPressed: addNote,
              tooltip: 'Комментарий',
              icon: const Icon(Icons.comment_outlined),
            ),
            IconButton(
              onPressed: page == 2
                  ? null
                  : () => setState(() {
                      page++;
                    }),
              tooltip: 'Следующая страница',
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 42,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              PopupMenuButton<String>(
                tooltip: 'Вкладки инструментов',
                initialValue: tab,
                onSelected: (value) => setState(() {
                  tab = value;
                  tools = true;
                }),
                itemBuilder: (context) => tabs
                    .map((v) => PopupMenuItem(value: v, child: Text(v)))
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '$tab ⌄',
                    style: const TextStyle(
                      color: Color(0xff25a675),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() {
                  tools = !tools;
                }),
                tooltip: tools ? 'Свернуть панель' : 'Показать инструменты',
                icon: Icon(
                  tools ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                ),
              ),
            ],
          ),
        ),
        if (tools)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 175),
            child: ListView(shrinkWrap: true, children: actionsForTab()),
          ),
      ],
    );
  }

  List<Widget> actionsForTab() {
    final actions = <(String, IconData, VoidCallback)>[];
    void add(String title, IconData icon, VoidCallback fn) {
      actions.add((title, icon, fn));
    }

    switch (widget.kind) {
      case EditorKind.word:
        if (tab == 'Главная') {
          add(
            'По ширине',
            Icons.format_align_justify,
            () => setState(() {
              wordAlign = TextAlign.justify;
            }),
          );
          add(
            'По левому краю',
            Icons.format_align_left,
            () => setState(() {
              wordAlign = TextAlign.left;
            }),
          );
        } else if (tab == 'Вид' || tab == 'Макет') {
          add(
            'Увеличить текст',
            Icons.zoom_in,
            () => setState(() {
              wordScale = (wordScale + .1).clamp(.8, 1.6);
            }),
          );
          add(
            'Уменьшить текст',
            Icons.zoom_out,
            () => setState(() {
              wordScale = (wordScale - .1).clamp(.8, 1.6);
            }),
          );
        }
      case EditorKind.excel:
        if (tab == 'Вид') {
          add(
            'Показать листы',
            Icons.view_carousel,
            () => setState(() {
              showSheets = !showSheets;
            }),
          );
        } else {
          add(
            'Новый лист',
            Icons.add,
            () => setState(() {
              sheetCount++;
            }),
          );
        }
      case EditorKind.slides:
        add('Добавить слайд', Icons.add, addSlide);
        add('Изменить текст слайда', Icons.edit, editSlide);
        if (slides.length > 1) {
          add(
            'Удалить текущий слайд',
            Icons.delete_outline,
            () => setState(() {
              slides.removeAt(slide);
              slide = slide.clamp(0, slides.length - 1);
            }),
          );
        }
      case EditorKind.pdf:
        break;
    }
    return actions
        .map(
          (entry) => ListTile(
            dense: true,
            leading: Icon(entry.$2, size: 19),
            title: Text(entry.$1, style: const TextStyle(fontSize: 13)),
            onTap: entry.$3,
          ),
        )
        .toList();
  }
}
