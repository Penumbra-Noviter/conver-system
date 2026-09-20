// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CharactersTable extends Characters
    with TableInfo<$CharactersTable, Character> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharactersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _personalityMeta = const VerificationMeta(
    'personality',
  );
  @override
  late final GeneratedColumn<String> personality = GeneratedColumn<String>(
    'personality',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _scenarioMeta = const VerificationMeta(
    'scenario',
  );
  @override
  late final GeneratedColumn<String> scenario = GeneratedColumn<String>(
    'scenario',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _firstMesMeta = const VerificationMeta(
    'firstMes',
  );
  @override
  late final GeneratedColumn<String> firstMes = GeneratedColumn<String>(
    'first_mes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _mesExampleMeta = const VerificationMeta(
    'mesExample',
  );
  @override
  late final GeneratedColumn<String> mesExample = GeneratedColumn<String>(
    'mes_example',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _systemPromptMeta = const VerificationMeta(
    'systemPrompt',
  );
  @override
  late final GeneratedColumn<String> systemPrompt = GeneratedColumn<String>(
    'system_prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _postHistoryInstructionsMeta =
      const VerificationMeta('postHistoryInstructions');
  @override
  late final GeneratedColumn<String> postHistoryInstructions =
      GeneratedColumn<String>(
        'post_history_instructions',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String>
  alternateGreetings = GeneratedColumn<String>(
    'alternate_greetings',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  ).withConverter<List<String>>($CharactersTable.$converteralternateGreetings);
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> tags =
      GeneratedColumn<String>(
        'tags',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($CharactersTable.$convertertags);
  static const VerificationMeta _creatorMeta = const VerificationMeta(
    'creator',
  );
  @override
  late final GeneratedColumn<String> creator = GeneratedColumn<String>(
    'creator',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('1.0'),
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
  creatorNotes =
      GeneratedColumn<String>(
        'creator_notes',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('{}'),
      ).withConverter<Map<String, dynamic>>(
        $CharactersTable.$convertercreatorNotes,
      );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
  extensions = GeneratedColumn<String>(
    'extensions',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  ).withConverter<Map<String, dynamic>>($CharactersTable.$converterextensions);
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
    'avatar',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _temperatureMeta = const VerificationMeta(
    'temperature',
  );
  @override
  late final GeneratedColumn<double> temperature = GeneratedColumn<double>(
    'temperature',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.7),
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<Map<String, String>>, String>
  presetDialogues =
      GeneratedColumn<String>(
        'preset_dialogues',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<Map<String, String>>>(
        $CharactersTable.$converterpresetDialogues,
      );
  static const VerificationMeta _promptModeMeta = const VerificationMeta(
    'promptMode',
  );
  @override
  late final GeneratedColumn<String> promptMode = GeneratedColumn<String>(
    'prompt_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('simple'),
  );
  static const VerificationMeta _expertPromptMeta = const VerificationMeta(
    'expertPrompt',
  );
  @override
  late final GeneratedColumn<String> expertPrompt = GeneratedColumn<String>(
    'expert_prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    personality,
    scenario,
    firstMes,
    mesExample,
    systemPrompt,
    postHistoryInstructions,
    alternateGreetings,
    tags,
    creator,
    version,
    creatorNotes,
    extensions,
    avatar,
    temperature,
    presetDialogues,
    promptMode,
    expertPrompt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'characters';
  @override
  VerificationContext validateIntegrity(
    Insertable<Character> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('personality')) {
      context.handle(
        _personalityMeta,
        personality.isAcceptableOrUnknown(
          data['personality']!,
          _personalityMeta,
        ),
      );
    }
    if (data.containsKey('scenario')) {
      context.handle(
        _scenarioMeta,
        scenario.isAcceptableOrUnknown(data['scenario']!, _scenarioMeta),
      );
    }
    if (data.containsKey('first_mes')) {
      context.handle(
        _firstMesMeta,
        firstMes.isAcceptableOrUnknown(data['first_mes']!, _firstMesMeta),
      );
    }
    if (data.containsKey('mes_example')) {
      context.handle(
        _mesExampleMeta,
        mesExample.isAcceptableOrUnknown(data['mes_example']!, _mesExampleMeta),
      );
    }
    if (data.containsKey('system_prompt')) {
      context.handle(
        _systemPromptMeta,
        systemPrompt.isAcceptableOrUnknown(
          data['system_prompt']!,
          _systemPromptMeta,
        ),
      );
    }
    if (data.containsKey('post_history_instructions')) {
      context.handle(
        _postHistoryInstructionsMeta,
        postHistoryInstructions.isAcceptableOrUnknown(
          data['post_history_instructions']!,
          _postHistoryInstructionsMeta,
        ),
      );
    }
    if (data.containsKey('creator')) {
      context.handle(
        _creatorMeta,
        creator.isAcceptableOrUnknown(data['creator']!, _creatorMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('avatar')) {
      context.handle(
        _avatarMeta,
        avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta),
      );
    }
    if (data.containsKey('temperature')) {
      context.handle(
        _temperatureMeta,
        temperature.isAcceptableOrUnknown(
          data['temperature']!,
          _temperatureMeta,
        ),
      );
    }
    if (data.containsKey('prompt_mode')) {
      context.handle(
        _promptModeMeta,
        promptMode.isAcceptableOrUnknown(data['prompt_mode']!, _promptModeMeta),
      );
    }
    if (data.containsKey('expert_prompt')) {
      context.handle(
        _expertPromptMeta,
        expertPrompt.isAcceptableOrUnknown(
          data['expert_prompt']!,
          _expertPromptMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Character map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Character(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      personality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}personality'],
      )!,
      scenario: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scenario'],
      )!,
      firstMes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_mes'],
      )!,
      mesExample: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mes_example'],
      )!,
      systemPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}system_prompt'],
      )!,
      postHistoryInstructions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}post_history_instructions'],
      )!,
      alternateGreetings: $CharactersTable.$converteralternateGreetings.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}alternate_greetings'],
        )!,
      ),
      tags: $CharactersTable.$convertertags.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tags'],
        )!,
      ),
      creator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creator'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      creatorNotes: $CharactersTable.$convertercreatorNotes.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}creator_notes'],
        )!,
      ),
      extensions: $CharactersTable.$converterextensions.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}extensions'],
        )!,
      ),
      avatar: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar'],
      ),
      temperature: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}temperature'],
      )!,
      presetDialogues: $CharactersTable.$converterpresetDialogues.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}preset_dialogues'],
        )!,
      ),
      promptMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_mode'],
      )!,
      expertPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expert_prompt'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CharactersTable createAlias(String alias) {
    return $CharactersTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converteralternateGreetings =
      const StringListConverter();
  static TypeConverter<List<String>, String> $convertertags =
      const StringListConverter();
  static TypeConverter<Map<String, dynamic>, String> $convertercreatorNotes =
      const StringMapConverter();
  static TypeConverter<Map<String, dynamic>, String> $converterextensions =
      const StringMapConverter();
  static TypeConverter<List<Map<String, String>>, String>
  $converterpresetDialogues = const PresetDialogueListConverter();
}

class Character extends DataClass implements Insertable<Character> {
  final int id;

  /// 必填，桌面端 String(100) + index=True。
  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMes;
  final String mesExample;
  final String systemPrompt;
  final String postHistoryInstructions;
  final List<String> alternateGreetings;
  final List<String> tags;
  final String creator;
  final String version;
  final Map<String, dynamic> creatorNotes;
  final Map<String, dynamic> extensions;
  final String? avatar;
  final double temperature;

  /// 预设对话列表（JSON 数组 `[{name, content}]`，对齐桌面
  /// `models/character.py::Character.preset_dialogues`；缺省 `[]`）。
  ///
  /// 值域与归一化（≤[PresetDialogueListConverter] 的健壮往返之外的语义）由
  /// `character_card.dart::_normalizePresetDialogues` 单一承载——桌面
  /// `_normalize_preset_dialogues`（PRESET_DIALOGUE_MAX=10 截断 / 空字段过滤 /
  /// 同名去重）逐字镜像，导入侧落到本列前已完成归一化（深层语义不进城）。
  final List<Map<String, String>> presetDialogues;

  /// 组装模式（simple/expert，缺省 simple；对齐桌面
  /// `models/character.py::Character.prompt_mode`）。expert 且非空
  /// [Characters.expertPrompt] 时，buildMessages 以整段 expert prompt 单条
  /// 替代 system_prompt/personality、scenario、post_history_instructions
  /// 三处结构化注入（桌面 PD-5）。
  final String promptMode;

  /// 专家模式整段 system prompt（缺省空串；对齐桌面
  /// `models/character.py::Character.expert_prompt`）。expert + 空/纯空白 →
  /// 回退 simple 结构化组装（安全兜底）。
  final String expertPrompt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Character({
    required this.id,
    required this.name,
    required this.description,
    required this.personality,
    required this.scenario,
    required this.firstMes,
    required this.mesExample,
    required this.systemPrompt,
    required this.postHistoryInstructions,
    required this.alternateGreetings,
    required this.tags,
    required this.creator,
    required this.version,
    required this.creatorNotes,
    required this.extensions,
    this.avatar,
    required this.temperature,
    required this.presetDialogues,
    required this.promptMode,
    required this.expertPrompt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['personality'] = Variable<String>(personality);
    map['scenario'] = Variable<String>(scenario);
    map['first_mes'] = Variable<String>(firstMes);
    map['mes_example'] = Variable<String>(mesExample);
    map['system_prompt'] = Variable<String>(systemPrompt);
    map['post_history_instructions'] = Variable<String>(
      postHistoryInstructions,
    );
    {
      map['alternate_greetings'] = Variable<String>(
        $CharactersTable.$converteralternateGreetings.toSql(alternateGreetings),
      );
    }
    {
      map['tags'] = Variable<String>(
        $CharactersTable.$convertertags.toSql(tags),
      );
    }
    map['creator'] = Variable<String>(creator);
    map['version'] = Variable<String>(version);
    {
      map['creator_notes'] = Variable<String>(
        $CharactersTable.$convertercreatorNotes.toSql(creatorNotes),
      );
    }
    {
      map['extensions'] = Variable<String>(
        $CharactersTable.$converterextensions.toSql(extensions),
      );
    }
    if (!nullToAbsent || avatar != null) {
      map['avatar'] = Variable<String>(avatar);
    }
    map['temperature'] = Variable<double>(temperature);
    {
      map['preset_dialogues'] = Variable<String>(
        $CharactersTable.$converterpresetDialogues.toSql(presetDialogues),
      );
    }
    map['prompt_mode'] = Variable<String>(promptMode);
    map['expert_prompt'] = Variable<String>(expertPrompt);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CharactersCompanion toCompanion(bool nullToAbsent) {
    return CharactersCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      personality: Value(personality),
      scenario: Value(scenario),
      firstMes: Value(firstMes),
      mesExample: Value(mesExample),
      systemPrompt: Value(systemPrompt),
      postHistoryInstructions: Value(postHistoryInstructions),
      alternateGreetings: Value(alternateGreetings),
      tags: Value(tags),
      creator: Value(creator),
      version: Value(version),
      creatorNotes: Value(creatorNotes),
      extensions: Value(extensions),
      avatar: avatar == null && nullToAbsent
          ? const Value.absent()
          : Value(avatar),
      temperature: Value(temperature),
      presetDialogues: Value(presetDialogues),
      promptMode: Value(promptMode),
      expertPrompt: Value(expertPrompt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Character.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Character(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      personality: serializer.fromJson<String>(json['personality']),
      scenario: serializer.fromJson<String>(json['scenario']),
      firstMes: serializer.fromJson<String>(json['firstMes']),
      mesExample: serializer.fromJson<String>(json['mesExample']),
      systemPrompt: serializer.fromJson<String>(json['systemPrompt']),
      postHistoryInstructions: serializer.fromJson<String>(
        json['postHistoryInstructions'],
      ),
      alternateGreetings: serializer.fromJson<List<String>>(
        json['alternateGreetings'],
      ),
      tags: serializer.fromJson<List<String>>(json['tags']),
      creator: serializer.fromJson<String>(json['creator']),
      version: serializer.fromJson<String>(json['version']),
      creatorNotes: serializer.fromJson<Map<String, dynamic>>(
        json['creatorNotes'],
      ),
      extensions: serializer.fromJson<Map<String, dynamic>>(json['extensions']),
      avatar: serializer.fromJson<String?>(json['avatar']),
      temperature: serializer.fromJson<double>(json['temperature']),
      presetDialogues: serializer.fromJson<List<Map<String, String>>>(
        json['presetDialogues'],
      ),
      promptMode: serializer.fromJson<String>(json['promptMode']),
      expertPrompt: serializer.fromJson<String>(json['expertPrompt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'personality': serializer.toJson<String>(personality),
      'scenario': serializer.toJson<String>(scenario),
      'firstMes': serializer.toJson<String>(firstMes),
      'mesExample': serializer.toJson<String>(mesExample),
      'systemPrompt': serializer.toJson<String>(systemPrompt),
      'postHistoryInstructions': serializer.toJson<String>(
        postHistoryInstructions,
      ),
      'alternateGreetings': serializer.toJson<List<String>>(alternateGreetings),
      'tags': serializer.toJson<List<String>>(tags),
      'creator': serializer.toJson<String>(creator),
      'version': serializer.toJson<String>(version),
      'creatorNotes': serializer.toJson<Map<String, dynamic>>(creatorNotes),
      'extensions': serializer.toJson<Map<String, dynamic>>(extensions),
      'avatar': serializer.toJson<String?>(avatar),
      'temperature': serializer.toJson<double>(temperature),
      'presetDialogues': serializer.toJson<List<Map<String, String>>>(
        presetDialogues,
      ),
      'promptMode': serializer.toJson<String>(promptMode),
      'expertPrompt': serializer.toJson<String>(expertPrompt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Character copyWith({
    int? id,
    String? name,
    String? description,
    String? personality,
    String? scenario,
    String? firstMes,
    String? mesExample,
    String? systemPrompt,
    String? postHistoryInstructions,
    List<String>? alternateGreetings,
    List<String>? tags,
    String? creator,
    String? version,
    Map<String, dynamic>? creatorNotes,
    Map<String, dynamic>? extensions,
    Value<String?> avatar = const Value.absent(),
    double? temperature,
    List<Map<String, String>>? presetDialogues,
    String? promptMode,
    String? expertPrompt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Character(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    personality: personality ?? this.personality,
    scenario: scenario ?? this.scenario,
    firstMes: firstMes ?? this.firstMes,
    mesExample: mesExample ?? this.mesExample,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    postHistoryInstructions:
        postHistoryInstructions ?? this.postHistoryInstructions,
    alternateGreetings: alternateGreetings ?? this.alternateGreetings,
    tags: tags ?? this.tags,
    creator: creator ?? this.creator,
    version: version ?? this.version,
    creatorNotes: creatorNotes ?? this.creatorNotes,
    extensions: extensions ?? this.extensions,
    avatar: avatar.present ? avatar.value : this.avatar,
    temperature: temperature ?? this.temperature,
    presetDialogues: presetDialogues ?? this.presetDialogues,
    promptMode: promptMode ?? this.promptMode,
    expertPrompt: expertPrompt ?? this.expertPrompt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Character copyWithCompanion(CharactersCompanion data) {
    return Character(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      personality: data.personality.present
          ? data.personality.value
          : this.personality,
      scenario: data.scenario.present ? data.scenario.value : this.scenario,
      firstMes: data.firstMes.present ? data.firstMes.value : this.firstMes,
      mesExample: data.mesExample.present
          ? data.mesExample.value
          : this.mesExample,
      systemPrompt: data.systemPrompt.present
          ? data.systemPrompt.value
          : this.systemPrompt,
      postHistoryInstructions: data.postHistoryInstructions.present
          ? data.postHistoryInstructions.value
          : this.postHistoryInstructions,
      alternateGreetings: data.alternateGreetings.present
          ? data.alternateGreetings.value
          : this.alternateGreetings,
      tags: data.tags.present ? data.tags.value : this.tags,
      creator: data.creator.present ? data.creator.value : this.creator,
      version: data.version.present ? data.version.value : this.version,
      creatorNotes: data.creatorNotes.present
          ? data.creatorNotes.value
          : this.creatorNotes,
      extensions: data.extensions.present
          ? data.extensions.value
          : this.extensions,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      temperature: data.temperature.present
          ? data.temperature.value
          : this.temperature,
      presetDialogues: data.presetDialogues.present
          ? data.presetDialogues.value
          : this.presetDialogues,
      promptMode: data.promptMode.present
          ? data.promptMode.value
          : this.promptMode,
      expertPrompt: data.expertPrompt.present
          ? data.expertPrompt.value
          : this.expertPrompt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Character(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('personality: $personality, ')
          ..write('scenario: $scenario, ')
          ..write('firstMes: $firstMes, ')
          ..write('mesExample: $mesExample, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('postHistoryInstructions: $postHistoryInstructions, ')
          ..write('alternateGreetings: $alternateGreetings, ')
          ..write('tags: $tags, ')
          ..write('creator: $creator, ')
          ..write('version: $version, ')
          ..write('creatorNotes: $creatorNotes, ')
          ..write('extensions: $extensions, ')
          ..write('avatar: $avatar, ')
          ..write('temperature: $temperature, ')
          ..write('presetDialogues: $presetDialogues, ')
          ..write('promptMode: $promptMode, ')
          ..write('expertPrompt: $expertPrompt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    description,
    personality,
    scenario,
    firstMes,
    mesExample,
    systemPrompt,
    postHistoryInstructions,
    alternateGreetings,
    tags,
    creator,
    version,
    creatorNotes,
    extensions,
    avatar,
    temperature,
    presetDialogues,
    promptMode,
    expertPrompt,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Character &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.personality == this.personality &&
          other.scenario == this.scenario &&
          other.firstMes == this.firstMes &&
          other.mesExample == this.mesExample &&
          other.systemPrompt == this.systemPrompt &&
          other.postHistoryInstructions == this.postHistoryInstructions &&
          other.alternateGreetings == this.alternateGreetings &&
          other.tags == this.tags &&
          other.creator == this.creator &&
          other.version == this.version &&
          other.creatorNotes == this.creatorNotes &&
          other.extensions == this.extensions &&
          other.avatar == this.avatar &&
          other.temperature == this.temperature &&
          other.presetDialogues == this.presetDialogues &&
          other.promptMode == this.promptMode &&
          other.expertPrompt == this.expertPrompt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CharactersCompanion extends UpdateCompanion<Character> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> description;
  final Value<String> personality;
  final Value<String> scenario;
  final Value<String> firstMes;
  final Value<String> mesExample;
  final Value<String> systemPrompt;
  final Value<String> postHistoryInstructions;
  final Value<List<String>> alternateGreetings;
  final Value<List<String>> tags;
  final Value<String> creator;
  final Value<String> version;
  final Value<Map<String, dynamic>> creatorNotes;
  final Value<Map<String, dynamic>> extensions;
  final Value<String?> avatar;
  final Value<double> temperature;
  final Value<List<Map<String, String>>> presetDialogues;
  final Value<String> promptMode;
  final Value<String> expertPrompt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const CharactersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.personality = const Value.absent(),
    this.scenario = const Value.absent(),
    this.firstMes = const Value.absent(),
    this.mesExample = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.postHistoryInstructions = const Value.absent(),
    this.alternateGreetings = const Value.absent(),
    this.tags = const Value.absent(),
    this.creator = const Value.absent(),
    this.version = const Value.absent(),
    this.creatorNotes = const Value.absent(),
    this.extensions = const Value.absent(),
    this.avatar = const Value.absent(),
    this.temperature = const Value.absent(),
    this.presetDialogues = const Value.absent(),
    this.promptMode = const Value.absent(),
    this.expertPrompt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CharactersCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.personality = const Value.absent(),
    this.scenario = const Value.absent(),
    this.firstMes = const Value.absent(),
    this.mesExample = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.postHistoryInstructions = const Value.absent(),
    this.alternateGreetings = const Value.absent(),
    this.tags = const Value.absent(),
    this.creator = const Value.absent(),
    this.version = const Value.absent(),
    this.creatorNotes = const Value.absent(),
    this.extensions = const Value.absent(),
    this.avatar = const Value.absent(),
    this.temperature = const Value.absent(),
    this.presetDialogues = const Value.absent(),
    this.promptMode = const Value.absent(),
    this.expertPrompt = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Character> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? personality,
    Expression<String>? scenario,
    Expression<String>? firstMes,
    Expression<String>? mesExample,
    Expression<String>? systemPrompt,
    Expression<String>? postHistoryInstructions,
    Expression<String>? alternateGreetings,
    Expression<String>? tags,
    Expression<String>? creator,
    Expression<String>? version,
    Expression<String>? creatorNotes,
    Expression<String>? extensions,
    Expression<String>? avatar,
    Expression<double>? temperature,
    Expression<String>? presetDialogues,
    Expression<String>? promptMode,
    Expression<String>? expertPrompt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (personality != null) 'personality': personality,
      if (scenario != null) 'scenario': scenario,
      if (firstMes != null) 'first_mes': firstMes,
      if (mesExample != null) 'mes_example': mesExample,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
      if (postHistoryInstructions != null)
        'post_history_instructions': postHistoryInstructions,
      if (alternateGreetings != null) 'alternate_greetings': alternateGreetings,
      if (tags != null) 'tags': tags,
      if (creator != null) 'creator': creator,
      if (version != null) 'version': version,
      if (creatorNotes != null) 'creator_notes': creatorNotes,
      if (extensions != null) 'extensions': extensions,
      if (avatar != null) 'avatar': avatar,
      if (temperature != null) 'temperature': temperature,
      if (presetDialogues != null) 'preset_dialogues': presetDialogues,
      if (promptMode != null) 'prompt_mode': promptMode,
      if (expertPrompt != null) 'expert_prompt': expertPrompt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CharactersCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? description,
    Value<String>? personality,
    Value<String>? scenario,
    Value<String>? firstMes,
    Value<String>? mesExample,
    Value<String>? systemPrompt,
    Value<String>? postHistoryInstructions,
    Value<List<String>>? alternateGreetings,
    Value<List<String>>? tags,
    Value<String>? creator,
    Value<String>? version,
    Value<Map<String, dynamic>>? creatorNotes,
    Value<Map<String, dynamic>>? extensions,
    Value<String?>? avatar,
    Value<double>? temperature,
    Value<List<Map<String, String>>>? presetDialogues,
    Value<String>? promptMode,
    Value<String>? expertPrompt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return CharactersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      scenario: scenario ?? this.scenario,
      firstMes: firstMes ?? this.firstMes,
      mesExample: mesExample ?? this.mesExample,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      postHistoryInstructions:
          postHistoryInstructions ?? this.postHistoryInstructions,
      alternateGreetings: alternateGreetings ?? this.alternateGreetings,
      tags: tags ?? this.tags,
      creator: creator ?? this.creator,
      version: version ?? this.version,
      creatorNotes: creatorNotes ?? this.creatorNotes,
      extensions: extensions ?? this.extensions,
      avatar: avatar ?? this.avatar,
      temperature: temperature ?? this.temperature,
      presetDialogues: presetDialogues ?? this.presetDialogues,
      promptMode: promptMode ?? this.promptMode,
      expertPrompt: expertPrompt ?? this.expertPrompt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (personality.present) {
      map['personality'] = Variable<String>(personality.value);
    }
    if (scenario.present) {
      map['scenario'] = Variable<String>(scenario.value);
    }
    if (firstMes.present) {
      map['first_mes'] = Variable<String>(firstMes.value);
    }
    if (mesExample.present) {
      map['mes_example'] = Variable<String>(mesExample.value);
    }
    if (systemPrompt.present) {
      map['system_prompt'] = Variable<String>(systemPrompt.value);
    }
    if (postHistoryInstructions.present) {
      map['post_history_instructions'] = Variable<String>(
        postHistoryInstructions.value,
      );
    }
    if (alternateGreetings.present) {
      map['alternate_greetings'] = Variable<String>(
        $CharactersTable.$converteralternateGreetings.toSql(
          alternateGreetings.value,
        ),
      );
    }
    if (tags.present) {
      map['tags'] = Variable<String>(
        $CharactersTable.$convertertags.toSql(tags.value),
      );
    }
    if (creator.present) {
      map['creator'] = Variable<String>(creator.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (creatorNotes.present) {
      map['creator_notes'] = Variable<String>(
        $CharactersTable.$convertercreatorNotes.toSql(creatorNotes.value),
      );
    }
    if (extensions.present) {
      map['extensions'] = Variable<String>(
        $CharactersTable.$converterextensions.toSql(extensions.value),
      );
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (temperature.present) {
      map['temperature'] = Variable<double>(temperature.value);
    }
    if (presetDialogues.present) {
      map['preset_dialogues'] = Variable<String>(
        $CharactersTable.$converterpresetDialogues.toSql(presetDialogues.value),
      );
    }
    if (promptMode.present) {
      map['prompt_mode'] = Variable<String>(promptMode.value);
    }
    if (expertPrompt.present) {
      map['expert_prompt'] = Variable<String>(expertPrompt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CharactersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('personality: $personality, ')
          ..write('scenario: $scenario, ')
          ..write('firstMes: $firstMes, ')
          ..write('mesExample: $mesExample, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('postHistoryInstructions: $postHistoryInstructions, ')
          ..write('alternateGreetings: $alternateGreetings, ')
          ..write('tags: $tags, ')
          ..write('creator: $creator, ')
          ..write('version: $version, ')
          ..write('creatorNotes: $creatorNotes, ')
          ..write('extensions: $extensions, ')
          ..write('avatar: $avatar, ')
          ..write('temperature: $temperature, ')
          ..write('presetDialogues: $presetDialogues, ')
          ..write('promptMode: $promptMode, ')
          ..write('expertPrompt: $expertPrompt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('新对话'),
  );
  static const VerificationMeta _modelProviderMeta = const VerificationMeta(
    'modelProvider',
  );
  @override
  late final GeneratedColumn<String> modelProvider = GeneratedColumn<String>(
    'model_provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('claude'),
  );
  static const VerificationMeta _modelNameMeta = const VerificationMeta(
    'modelName',
  );
  @override
  late final GeneratedColumn<String> modelName = GeneratedColumn<String>(
    'model_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('claude-sonnet-5'),
  );
  static const VerificationMeta _presetDialogueMeta = const VerificationMeta(
    'presetDialogue',
  );
  @override
  late final GeneratedColumn<String> presetDialogue = GeneratedColumn<String>(
    'preset_dialogue',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _topPMeta = const VerificationMeta('topP');
  @override
  late final GeneratedColumn<double> topP = GeneratedColumn<double>(
    'top_p',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _presencePenaltyMeta = const VerificationMeta(
    'presencePenalty',
  );
  @override
  late final GeneratedColumn<double> presencePenalty = GeneratedColumn<double>(
    'presence_penalty',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _frequencyPenaltyMeta = const VerificationMeta(
    'frequencyPenalty',
  );
  @override
  late final GeneratedColumn<double> frequencyPenalty = GeneratedColumn<double>(
    'frequency_penalty',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maxTokensMeta = const VerificationMeta(
    'maxTokens',
  );
  @override
  late final GeneratedColumn<int> maxTokens = GeneratedColumn<int>(
    'max_tokens',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentConversationIdMeta =
      const VerificationMeta('parentConversationId');
  @override
  late final GeneratedColumn<int> parentConversationId = GeneratedColumn<int>(
    'parent_conversation_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _branchFromMessageIdMeta =
      const VerificationMeta('branchFromMessageId');
  @override
  late final GeneratedColumn<int> branchFromMessageId = GeneratedColumn<int>(
    'branch_from_message_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _branchTitleMeta = const VerificationMeta(
    'branchTitle',
  );
  @override
  late final GeneratedColumn<String> branchTitle = GeneratedColumn<String>(
    'branch_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    title,
    modelProvider,
    modelName,
    presetDialogue,
    topP,
    presencePenalty,
    frequencyPenalty,
    maxTokens,
    parentConversationId,
    branchFromMessageId,
    branchTitle,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('model_provider')) {
      context.handle(
        _modelProviderMeta,
        modelProvider.isAcceptableOrUnknown(
          data['model_provider']!,
          _modelProviderMeta,
        ),
      );
    }
    if (data.containsKey('model_name')) {
      context.handle(
        _modelNameMeta,
        modelName.isAcceptableOrUnknown(data['model_name']!, _modelNameMeta),
      );
    }
    if (data.containsKey('preset_dialogue')) {
      context.handle(
        _presetDialogueMeta,
        presetDialogue.isAcceptableOrUnknown(
          data['preset_dialogue']!,
          _presetDialogueMeta,
        ),
      );
    }
    if (data.containsKey('top_p')) {
      context.handle(
        _topPMeta,
        topP.isAcceptableOrUnknown(data['top_p']!, _topPMeta),
      );
    }
    if (data.containsKey('presence_penalty')) {
      context.handle(
        _presencePenaltyMeta,
        presencePenalty.isAcceptableOrUnknown(
          data['presence_penalty']!,
          _presencePenaltyMeta,
        ),
      );
    }
    if (data.containsKey('frequency_penalty')) {
      context.handle(
        _frequencyPenaltyMeta,
        frequencyPenalty.isAcceptableOrUnknown(
          data['frequency_penalty']!,
          _frequencyPenaltyMeta,
        ),
      );
    }
    if (data.containsKey('max_tokens')) {
      context.handle(
        _maxTokensMeta,
        maxTokens.isAcceptableOrUnknown(data['max_tokens']!, _maxTokensMeta),
      );
    }
    if (data.containsKey('parent_conversation_id')) {
      context.handle(
        _parentConversationIdMeta,
        parentConversationId.isAcceptableOrUnknown(
          data['parent_conversation_id']!,
          _parentConversationIdMeta,
        ),
      );
    }
    if (data.containsKey('branch_from_message_id')) {
      context.handle(
        _branchFromMessageIdMeta,
        branchFromMessageId.isAcceptableOrUnknown(
          data['branch_from_message_id']!,
          _branchFromMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('branch_title')) {
      context.handle(
        _branchTitleMeta,
        branchTitle.isAcceptableOrUnknown(
          data['branch_title']!,
          _branchTitleMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      modelProvider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_provider'],
      )!,
      modelName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_name'],
      )!,
      presetDialogue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preset_dialogue'],
      ),
      topP: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}top_p'],
      ),
      presencePenalty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}presence_penalty'],
      ),
      frequencyPenalty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}frequency_penalty'],
      ),
      maxTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_tokens'],
      ),
      parentConversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_conversation_id'],
      ),
      branchFromMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}branch_from_message_id'],
      ),
      branchTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_title'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final int id;

  /// 必填外键 → characters.id，桌面端 ondelete=CASCADE + index=True。
  final int characterId;
  final String title;
  final String modelProvider;
  final String modelName;

  /// 预设对话快照（可空 TEXT；NPD-02，对齐桌面
  /// `models/conversation.py::Conversation.preset_dialogue`）。
  ///
  /// 创建对话时固化（`createConversation` 传入的 presetDialogue 原样落列；
  /// None/空串 → null 不落伪值——桌面 `data.preset_dialogue or None` 语义）。
  /// 快照语义 = 创建时固化：改角色卡 presetDialogues 实时值不影响已建会话
  /// 注入源（对话组装只读本列）。
  final String? presetDialogue;

  /// top-p 采样（可空 REAL；SP-01，对齐桌面 chat.py ChatContext.top_p。
  /// NULL = 不覆盖 provider 默认；值域 [0,1] 的 clamp/回退守卫落在
  /// `chat_service.dart::_resolveSamplingParameters` 服务层——SR-24，表层
  /// 不设 CHECK（沿既有 F-76 先例）。
  final double? topP;

  /// presence penalty 采样（可空 REAL；SP-01，对齐桌面
  /// ChatContext.presence_penalty。NULL = 不覆盖 provider 默认；值域 [-2,2]
  /// 由服务层守卫——SR-24）。
  final double? presencePenalty;

  /// frequency penalty 采样（可空 REAL；SP-01，对齐桌面
  /// ChatContext.frequency_penalty。NULL = 不覆盖 provider 默认；值域 [-2,2]
  /// 由服务层守卫——SR-24）。
  final double? frequencyPenalty;

  /// max_tokens 覆盖（可空 INTEGER；SP-01，对齐桌面 ChatContext.max_tokens。
  /// NULL = 不覆盖 provider 默认即走全局链；≥1 校验由服务层守卫——SR-24）。
  final int? maxTokens;

  /// 派生来源会话 id（可空 INTEGER；逻辑引用**不建硬 FK**——删源会话不阻塞、
  /// 不影响已派生分支，删源时由服务层把派生分支的 parent / 锚引用置空并锁定
  /// （对齐桌面 BR-2 删源置空策略，SR-29）。
  final int? parentConversationId;

  /// 分叉锚消息 id（快照末条；可空 INTEGER；逻辑引用不建硬 FK，随删源置空）。
  final int? branchFromMessageId;

  /// 分支显示名（可空 VARCHAR 语义；删源置空时保留——分支显示名仍可用）。
  final String? branchTitle;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Conversation({
    required this.id,
    required this.characterId,
    required this.title,
    required this.modelProvider,
    required this.modelName,
    this.presetDialogue,
    this.topP,
    this.presencePenalty,
    this.frequencyPenalty,
    this.maxTokens,
    this.parentConversationId,
    this.branchFromMessageId,
    this.branchTitle,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<int>(characterId);
    map['title'] = Variable<String>(title);
    map['model_provider'] = Variable<String>(modelProvider);
    map['model_name'] = Variable<String>(modelName);
    if (!nullToAbsent || presetDialogue != null) {
      map['preset_dialogue'] = Variable<String>(presetDialogue);
    }
    if (!nullToAbsent || topP != null) {
      map['top_p'] = Variable<double>(topP);
    }
    if (!nullToAbsent || presencePenalty != null) {
      map['presence_penalty'] = Variable<double>(presencePenalty);
    }
    if (!nullToAbsent || frequencyPenalty != null) {
      map['frequency_penalty'] = Variable<double>(frequencyPenalty);
    }
    if (!nullToAbsent || maxTokens != null) {
      map['max_tokens'] = Variable<int>(maxTokens);
    }
    if (!nullToAbsent || parentConversationId != null) {
      map['parent_conversation_id'] = Variable<int>(parentConversationId);
    }
    if (!nullToAbsent || branchFromMessageId != null) {
      map['branch_from_message_id'] = Variable<int>(branchFromMessageId);
    }
    if (!nullToAbsent || branchTitle != null) {
      map['branch_title'] = Variable<String>(branchTitle);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      characterId: Value(characterId),
      title: Value(title),
      modelProvider: Value(modelProvider),
      modelName: Value(modelName),
      presetDialogue: presetDialogue == null && nullToAbsent
          ? const Value.absent()
          : Value(presetDialogue),
      topP: topP == null && nullToAbsent ? const Value.absent() : Value(topP),
      presencePenalty: presencePenalty == null && nullToAbsent
          ? const Value.absent()
          : Value(presencePenalty),
      frequencyPenalty: frequencyPenalty == null && nullToAbsent
          ? const Value.absent()
          : Value(frequencyPenalty),
      maxTokens: maxTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(maxTokens),
      parentConversationId: parentConversationId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentConversationId),
      branchFromMessageId: branchFromMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(branchFromMessageId),
      branchTitle: branchTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(branchTitle),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<int>(json['characterId']),
      title: serializer.fromJson<String>(json['title']),
      modelProvider: serializer.fromJson<String>(json['modelProvider']),
      modelName: serializer.fromJson<String>(json['modelName']),
      presetDialogue: serializer.fromJson<String?>(json['presetDialogue']),
      topP: serializer.fromJson<double?>(json['topP']),
      presencePenalty: serializer.fromJson<double?>(json['presencePenalty']),
      frequencyPenalty: serializer.fromJson<double?>(json['frequencyPenalty']),
      maxTokens: serializer.fromJson<int?>(json['maxTokens']),
      parentConversationId: serializer.fromJson<int?>(
        json['parentConversationId'],
      ),
      branchFromMessageId: serializer.fromJson<int?>(
        json['branchFromMessageId'],
      ),
      branchTitle: serializer.fromJson<String?>(json['branchTitle']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<int>(characterId),
      'title': serializer.toJson<String>(title),
      'modelProvider': serializer.toJson<String>(modelProvider),
      'modelName': serializer.toJson<String>(modelName),
      'presetDialogue': serializer.toJson<String?>(presetDialogue),
      'topP': serializer.toJson<double?>(topP),
      'presencePenalty': serializer.toJson<double?>(presencePenalty),
      'frequencyPenalty': serializer.toJson<double?>(frequencyPenalty),
      'maxTokens': serializer.toJson<int?>(maxTokens),
      'parentConversationId': serializer.toJson<int?>(parentConversationId),
      'branchFromMessageId': serializer.toJson<int?>(branchFromMessageId),
      'branchTitle': serializer.toJson<String?>(branchTitle),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Conversation copyWith({
    int? id,
    int? characterId,
    String? title,
    String? modelProvider,
    String? modelName,
    Value<String?> presetDialogue = const Value.absent(),
    Value<double?> topP = const Value.absent(),
    Value<double?> presencePenalty = const Value.absent(),
    Value<double?> frequencyPenalty = const Value.absent(),
    Value<int?> maxTokens = const Value.absent(),
    Value<int?> parentConversationId = const Value.absent(),
    Value<int?> branchFromMessageId = const Value.absent(),
    Value<String?> branchTitle = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Conversation(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    title: title ?? this.title,
    modelProvider: modelProvider ?? this.modelProvider,
    modelName: modelName ?? this.modelName,
    presetDialogue: presetDialogue.present
        ? presetDialogue.value
        : this.presetDialogue,
    topP: topP.present ? topP.value : this.topP,
    presencePenalty: presencePenalty.present
        ? presencePenalty.value
        : this.presencePenalty,
    frequencyPenalty: frequencyPenalty.present
        ? frequencyPenalty.value
        : this.frequencyPenalty,
    maxTokens: maxTokens.present ? maxTokens.value : this.maxTokens,
    parentConversationId: parentConversationId.present
        ? parentConversationId.value
        : this.parentConversationId,
    branchFromMessageId: branchFromMessageId.present
        ? branchFromMessageId.value
        : this.branchFromMessageId,
    branchTitle: branchTitle.present ? branchTitle.value : this.branchTitle,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      title: data.title.present ? data.title.value : this.title,
      modelProvider: data.modelProvider.present
          ? data.modelProvider.value
          : this.modelProvider,
      modelName: data.modelName.present ? data.modelName.value : this.modelName,
      presetDialogue: data.presetDialogue.present
          ? data.presetDialogue.value
          : this.presetDialogue,
      topP: data.topP.present ? data.topP.value : this.topP,
      presencePenalty: data.presencePenalty.present
          ? data.presencePenalty.value
          : this.presencePenalty,
      frequencyPenalty: data.frequencyPenalty.present
          ? data.frequencyPenalty.value
          : this.frequencyPenalty,
      maxTokens: data.maxTokens.present ? data.maxTokens.value : this.maxTokens,
      parentConversationId: data.parentConversationId.present
          ? data.parentConversationId.value
          : this.parentConversationId,
      branchFromMessageId: data.branchFromMessageId.present
          ? data.branchFromMessageId.value
          : this.branchFromMessageId,
      branchTitle: data.branchTitle.present
          ? data.branchTitle.value
          : this.branchTitle,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('title: $title, ')
          ..write('modelProvider: $modelProvider, ')
          ..write('modelName: $modelName, ')
          ..write('presetDialogue: $presetDialogue, ')
          ..write('topP: $topP, ')
          ..write('presencePenalty: $presencePenalty, ')
          ..write('frequencyPenalty: $frequencyPenalty, ')
          ..write('maxTokens: $maxTokens, ')
          ..write('parentConversationId: $parentConversationId, ')
          ..write('branchFromMessageId: $branchFromMessageId, ')
          ..write('branchTitle: $branchTitle, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    characterId,
    title,
    modelProvider,
    modelName,
    presetDialogue,
    topP,
    presencePenalty,
    frequencyPenalty,
    maxTokens,
    parentConversationId,
    branchFromMessageId,
    branchTitle,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.title == this.title &&
          other.modelProvider == this.modelProvider &&
          other.modelName == this.modelName &&
          other.presetDialogue == this.presetDialogue &&
          other.topP == this.topP &&
          other.presencePenalty == this.presencePenalty &&
          other.frequencyPenalty == this.frequencyPenalty &&
          other.maxTokens == this.maxTokens &&
          other.parentConversationId == this.parentConversationId &&
          other.branchFromMessageId == this.branchFromMessageId &&
          other.branchTitle == this.branchTitle &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<int> id;
  final Value<int> characterId;
  final Value<String> title;
  final Value<String> modelProvider;
  final Value<String> modelName;
  final Value<String?> presetDialogue;
  final Value<double?> topP;
  final Value<double?> presencePenalty;
  final Value<double?> frequencyPenalty;
  final Value<int?> maxTokens;
  final Value<int?> parentConversationId;
  final Value<int?> branchFromMessageId;
  final Value<String?> branchTitle;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.title = const Value.absent(),
    this.modelProvider = const Value.absent(),
    this.modelName = const Value.absent(),
    this.presetDialogue = const Value.absent(),
    this.topP = const Value.absent(),
    this.presencePenalty = const Value.absent(),
    this.frequencyPenalty = const Value.absent(),
    this.maxTokens = const Value.absent(),
    this.parentConversationId = const Value.absent(),
    this.branchFromMessageId = const Value.absent(),
    this.branchTitle = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ConversationsCompanion.insert({
    this.id = const Value.absent(),
    required int characterId,
    this.title = const Value.absent(),
    this.modelProvider = const Value.absent(),
    this.modelName = const Value.absent(),
    this.presetDialogue = const Value.absent(),
    this.topP = const Value.absent(),
    this.presencePenalty = const Value.absent(),
    this.frequencyPenalty = const Value.absent(),
    this.maxTokens = const Value.absent(),
    this.parentConversationId = const Value.absent(),
    this.branchFromMessageId = const Value.absent(),
    this.branchTitle = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : characterId = Value(characterId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Conversation> custom({
    Expression<int>? id,
    Expression<int>? characterId,
    Expression<String>? title,
    Expression<String>? modelProvider,
    Expression<String>? modelName,
    Expression<String>? presetDialogue,
    Expression<double>? topP,
    Expression<double>? presencePenalty,
    Expression<double>? frequencyPenalty,
    Expression<int>? maxTokens,
    Expression<int>? parentConversationId,
    Expression<int>? branchFromMessageId,
    Expression<String>? branchTitle,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (title != null) 'title': title,
      if (modelProvider != null) 'model_provider': modelProvider,
      if (modelName != null) 'model_name': modelName,
      if (presetDialogue != null) 'preset_dialogue': presetDialogue,
      if (topP != null) 'top_p': topP,
      if (presencePenalty != null) 'presence_penalty': presencePenalty,
      if (frequencyPenalty != null) 'frequency_penalty': frequencyPenalty,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (parentConversationId != null)
        'parent_conversation_id': parentConversationId,
      if (branchFromMessageId != null)
        'branch_from_message_id': branchFromMessageId,
      if (branchTitle != null) 'branch_title': branchTitle,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ConversationsCompanion copyWith({
    Value<int>? id,
    Value<int>? characterId,
    Value<String>? title,
    Value<String>? modelProvider,
    Value<String>? modelName,
    Value<String?>? presetDialogue,
    Value<double?>? topP,
    Value<double?>? presencePenalty,
    Value<double?>? frequencyPenalty,
    Value<int?>? maxTokens,
    Value<int?>? parentConversationId,
    Value<int?>? branchFromMessageId,
    Value<String?>? branchTitle,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      title: title ?? this.title,
      modelProvider: modelProvider ?? this.modelProvider,
      modelName: modelName ?? this.modelName,
      presetDialogue: presetDialogue ?? this.presetDialogue,
      topP: topP ?? this.topP,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      maxTokens: maxTokens ?? this.maxTokens,
      parentConversationId: parentConversationId ?? this.parentConversationId,
      branchFromMessageId: branchFromMessageId ?? this.branchFromMessageId,
      branchTitle: branchTitle ?? this.branchTitle,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (modelProvider.present) {
      map['model_provider'] = Variable<String>(modelProvider.value);
    }
    if (modelName.present) {
      map['model_name'] = Variable<String>(modelName.value);
    }
    if (presetDialogue.present) {
      map['preset_dialogue'] = Variable<String>(presetDialogue.value);
    }
    if (topP.present) {
      map['top_p'] = Variable<double>(topP.value);
    }
    if (presencePenalty.present) {
      map['presence_penalty'] = Variable<double>(presencePenalty.value);
    }
    if (frequencyPenalty.present) {
      map['frequency_penalty'] = Variable<double>(frequencyPenalty.value);
    }
    if (maxTokens.present) {
      map['max_tokens'] = Variable<int>(maxTokens.value);
    }
    if (parentConversationId.present) {
      map['parent_conversation_id'] = Variable<int>(parentConversationId.value);
    }
    if (branchFromMessageId.present) {
      map['branch_from_message_id'] = Variable<int>(branchFromMessageId.value);
    }
    if (branchTitle.present) {
      map['branch_title'] = Variable<String>(branchTitle.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('title: $title, ')
          ..write('modelProvider: $modelProvider, ')
          ..write('modelName: $modelName, ')
          ..write('presetDialogue: $presetDialogue, ')
          ..write('topP: $topP, ')
          ..write('presencePenalty: $presencePenalty, ')
          ..write('frequencyPenalty: $frequencyPenalty, ')
          ..write('maxTokens: $maxTokens, ')
          ..write('parentConversationId: $parentConversationId, ')
          ..write('branchFromMessageId: $branchFromMessageId, ')
          ..write('branchTitle: $branchTitle, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<Role, String> role =
      GeneratedColumn<String>(
        'role',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Role>($MessagesTable.$converterrole);
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeSwipeIndexMeta = const VerificationMeta(
    'activeSwipeIndex',
  );
  @override
  late final GeneratedColumn<int> activeSwipeIndex = GeneratedColumn<int>(
    'active_swipe_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    role,
    content,
    activeSwipeIndex,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('active_swipe_index')) {
      context.handle(
        _activeSwipeIndexMeta,
        activeSwipeIndex.isAcceptableOrUnknown(
          data['active_swipe_index']!,
          _activeSwipeIndexMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      role: $MessagesTable.$converterrole.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}role'],
        )!,
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      activeSwipeIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}active_swipe_index'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }

  static TypeConverter<Role, String> $converterrole = const RoleConverter();
}

class Message extends DataClass implements Insertable<Message> {
  final int id;

  /// 必填外键 → conversations.id，桌面端 ondelete=CASCADE + index=True。
  final int conversationId;

  /// 必填枚举，TypeConverter 显式按 `.value`（user/assistant/system）落库。
  final Role role;

  /// 必填文本。
  final String content;

  /// 当前激活候选序号（MS-01；spec §4.2 默认 0）。`messages.content` 恒为
  /// 当前激活候选——切换/追加候选时由仓储层同步覆写（对齐桌面
  /// `models/message.py::Message.active_swipe_index`，server_default '0'）。
  final int activeSwipeIndex;
  final DateTime createdAt;
  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.activeSwipeIndex,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<int>(conversationId);
    {
      map['role'] = Variable<String>($MessagesTable.$converterrole.toSql(role));
    }
    map['content'] = Variable<String>(content);
    map['active_swipe_index'] = Variable<int>(activeSwipeIndex);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      role: Value(role),
      content: Value(content),
      activeSwipeIndex: Value(activeSwipeIndex),
      createdAt: Value(createdAt),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      role: serializer.fromJson<Role>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      activeSwipeIndex: serializer.fromJson<int>(json['activeSwipeIndex']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<int>(conversationId),
      'role': serializer.toJson<Role>(role),
      'content': serializer.toJson<String>(content),
      'activeSwipeIndex': serializer.toJson<int>(activeSwipeIndex),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Message copyWith({
    int? id,
    int? conversationId,
    Role? role,
    String? content,
    int? activeSwipeIndex,
    DateTime? createdAt,
  }) => Message(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    role: role ?? this.role,
    content: content ?? this.content,
    activeSwipeIndex: activeSwipeIndex ?? this.activeSwipeIndex,
    createdAt: createdAt ?? this.createdAt,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      activeSwipeIndex: data.activeSwipeIndex.present
          ? data.activeSwipeIndex.value
          : this.activeSwipeIndex,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('activeSwipeIndex: $activeSwipeIndex, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    role,
    content,
    activeSwipeIndex,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.content == this.content &&
          other.activeSwipeIndex == this.activeSwipeIndex &&
          other.createdAt == this.createdAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> id;
  final Value<int> conversationId;
  final Value<Role> role;
  final Value<String> content;
  final Value<int> activeSwipeIndex;
  final Value<DateTime> createdAt;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.activeSwipeIndex = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    required int conversationId,
    required Role role,
    required String content,
    this.activeSwipeIndex = const Value.absent(),
    required DateTime createdAt,
  }) : conversationId = Value(conversationId),
       role = Value(role),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<int>? id,
    Expression<int>? conversationId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<int>? activeSwipeIndex,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (activeSwipeIndex != null) 'active_swipe_index': activeSwipeIndex,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MessagesCompanion copyWith({
    Value<int>? id,
    Value<int>? conversationId,
    Value<Role>? role,
    Value<String>? content,
    Value<int>? activeSwipeIndex,
    Value<DateTime>? createdAt,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      activeSwipeIndex: activeSwipeIndex ?? this.activeSwipeIndex,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(
        $MessagesTable.$converterrole.toSql(role.value),
      );
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (activeSwipeIndex.present) {
      map['active_swipe_index'] = Variable<int>(activeSwipeIndex.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('activeSwipeIndex: $activeSwipeIndex, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MemoryEntriesTable extends MemoryEntries
    with TableInfo<$MemoryEntriesTable, MemoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MemoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<MemoryKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<MemoryKind>($MemoryEntriesTable.$converterkind);
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importanceMeta = const VerificationMeta(
    'importance',
  );
  @override
  late final GeneratedColumn<int> importance = GeneratedColumn<int>(
    'importance',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    kind,
    content,
    importance,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'memory_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<MemoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('importance')) {
      context.handle(
        _importanceMeta,
        importance.isAcceptableOrUnknown(data['importance']!, _importanceMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MemoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MemoryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      )!,
      kind: $MemoryEntriesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      importance: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}importance'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $MemoryEntriesTable createAlias(String alias) {
    return $MemoryEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<MemoryKind, String> $converterkind =
      const MemoryKindConverter();
}

class MemoryEntry extends DataClass implements Insertable<MemoryEntry> {
  final int id;

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  final int characterId;

  /// 必填枚举（persona_fact / episodic），TypeConverter 显式按 `.value` 落库。
  final MemoryKind kind;

  /// 记忆正文（必填文本）。
  final String content;

  /// 重要性（整数，缺省 0；高者优先注入）。
  final int importance;
  final DateTime createdAt;
  final DateTime updatedAt;
  const MemoryEntry({
    required this.id,
    required this.characterId,
    required this.kind,
    required this.content,
    required this.importance,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<int>(characterId);
    {
      map['kind'] = Variable<String>(
        $MemoryEntriesTable.$converterkind.toSql(kind),
      );
    }
    map['content'] = Variable<String>(content);
    map['importance'] = Variable<int>(importance);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  MemoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return MemoryEntriesCompanion(
      id: Value(id),
      characterId: Value(characterId),
      kind: Value(kind),
      content: Value(content),
      importance: Value(importance),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory MemoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MemoryEntry(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<int>(json['characterId']),
      kind: serializer.fromJson<MemoryKind>(json['kind']),
      content: serializer.fromJson<String>(json['content']),
      importance: serializer.fromJson<int>(json['importance']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<int>(characterId),
      'kind': serializer.toJson<MemoryKind>(kind),
      'content': serializer.toJson<String>(content),
      'importance': serializer.toJson<int>(importance),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  MemoryEntry copyWith({
    int? id,
    int? characterId,
    MemoryKind? kind,
    String? content,
    int? importance,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => MemoryEntry(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    kind: kind ?? this.kind,
    content: content ?? this.content,
    importance: importance ?? this.importance,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MemoryEntry copyWithCompanion(MemoryEntriesCompanion data) {
    return MemoryEntry(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      kind: data.kind.present ? data.kind.value : this.kind,
      content: data.content.present ? data.content.value : this.content,
      importance: data.importance.present
          ? data.importance.value
          : this.importance,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MemoryEntry(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('kind: $kind, ')
          ..write('content: $content, ')
          ..write('importance: $importance, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    characterId,
    kind,
    content,
    importance,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MemoryEntry &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.kind == this.kind &&
          other.content == this.content &&
          other.importance == this.importance &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class MemoryEntriesCompanion extends UpdateCompanion<MemoryEntry> {
  final Value<int> id;
  final Value<int> characterId;
  final Value<MemoryKind> kind;
  final Value<String> content;
  final Value<int> importance;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const MemoryEntriesCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.kind = const Value.absent(),
    this.content = const Value.absent(),
    this.importance = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  MemoryEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int characterId,
    required MemoryKind kind,
    required String content,
    this.importance = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : characterId = Value(characterId),
       kind = Value(kind),
       content = Value(content),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<MemoryEntry> custom({
    Expression<int>? id,
    Expression<int>? characterId,
    Expression<String>? kind,
    Expression<String>? content,
    Expression<int>? importance,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (kind != null) 'kind': kind,
      if (content != null) 'content': content,
      if (importance != null) 'importance': importance,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  MemoryEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? characterId,
    Value<MemoryKind>? kind,
    Value<String>? content,
    Value<int>? importance,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return MemoryEntriesCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      kind: kind ?? this.kind,
      content: content ?? this.content,
      importance: importance ?? this.importance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $MemoryEntriesTable.$converterkind.toSql(kind.value),
      );
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (importance.present) {
      map['importance'] = Variable<int>(importance.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MemoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('kind: $kind, ')
          ..write('content: $content, ')
          ..write('importance: $importance, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PersonaRevisionsTable extends PersonaRevisions
    with TableInfo<$PersonaRevisionsTable, PersonaRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonaRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _personalitySnapshotMeta =
      const VerificationMeta('personalitySnapshot');
  @override
  late final GeneratedColumn<String> personalitySnapshot =
      GeneratedColumn<String>(
        'personality_snapshot',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    personalitySnapshot,
    reason,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'persona_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonaRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('personality_snapshot')) {
      context.handle(
        _personalitySnapshotMeta,
        personalitySnapshot.isAcceptableOrUnknown(
          data['personality_snapshot']!,
          _personalitySnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_personalitySnapshotMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PersonaRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonaRevision(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      )!,
      personalitySnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}personality_snapshot'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PersonaRevisionsTable createAlias(String alias) {
    return $PersonaRevisionsTable(attachedDatabase, alias);
  }
}

class PersonaRevision extends DataClass implements Insertable<PersonaRevision> {
  final int id;

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  final int characterId;

  /// 演化时点的角色人格全文快照（必填文本）。
  final String personalitySnapshot;

  /// 演化动机 / 备注（缺省空串）。
  final String reason;
  final DateTime createdAt;
  const PersonaRevision({
    required this.id,
    required this.characterId,
    required this.personalitySnapshot,
    required this.reason,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<int>(characterId);
    map['personality_snapshot'] = Variable<String>(personalitySnapshot);
    map['reason'] = Variable<String>(reason);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PersonaRevisionsCompanion toCompanion(bool nullToAbsent) {
    return PersonaRevisionsCompanion(
      id: Value(id),
      characterId: Value(characterId),
      personalitySnapshot: Value(personalitySnapshot),
      reason: Value(reason),
      createdAt: Value(createdAt),
    );
  }

  factory PersonaRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonaRevision(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<int>(json['characterId']),
      personalitySnapshot: serializer.fromJson<String>(
        json['personalitySnapshot'],
      ),
      reason: serializer.fromJson<String>(json['reason']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<int>(characterId),
      'personalitySnapshot': serializer.toJson<String>(personalitySnapshot),
      'reason': serializer.toJson<String>(reason),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PersonaRevision copyWith({
    int? id,
    int? characterId,
    String? personalitySnapshot,
    String? reason,
    DateTime? createdAt,
  }) => PersonaRevision(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    personalitySnapshot: personalitySnapshot ?? this.personalitySnapshot,
    reason: reason ?? this.reason,
    createdAt: createdAt ?? this.createdAt,
  );
  PersonaRevision copyWithCompanion(PersonaRevisionsCompanion data) {
    return PersonaRevision(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      personalitySnapshot: data.personalitySnapshot.present
          ? data.personalitySnapshot.value
          : this.personalitySnapshot,
      reason: data.reason.present ? data.reason.value : this.reason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonaRevision(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('personalitySnapshot: $personalitySnapshot, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, characterId, personalitySnapshot, reason, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonaRevision &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.personalitySnapshot == this.personalitySnapshot &&
          other.reason == this.reason &&
          other.createdAt == this.createdAt);
}

class PersonaRevisionsCompanion extends UpdateCompanion<PersonaRevision> {
  final Value<int> id;
  final Value<int> characterId;
  final Value<String> personalitySnapshot;
  final Value<String> reason;
  final Value<DateTime> createdAt;
  const PersonaRevisionsCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.personalitySnapshot = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PersonaRevisionsCompanion.insert({
    this.id = const Value.absent(),
    required int characterId,
    required String personalitySnapshot,
    this.reason = const Value.absent(),
    required DateTime createdAt,
  }) : characterId = Value(characterId),
       personalitySnapshot = Value(personalitySnapshot),
       createdAt = Value(createdAt);
  static Insertable<PersonaRevision> custom({
    Expression<int>? id,
    Expression<int>? characterId,
    Expression<String>? personalitySnapshot,
    Expression<String>? reason,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (personalitySnapshot != null)
        'personality_snapshot': personalitySnapshot,
      if (reason != null) 'reason': reason,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PersonaRevisionsCompanion copyWith({
    Value<int>? id,
    Value<int>? characterId,
    Value<String>? personalitySnapshot,
    Value<String>? reason,
    Value<DateTime>? createdAt,
  }) {
    return PersonaRevisionsCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      personalitySnapshot: personalitySnapshot ?? this.personalitySnapshot,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (personalitySnapshot.present) {
      map['personality_snapshot'] = Variable<String>(personalitySnapshot.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonaRevisionsCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('personalitySnapshot: $personalitySnapshot, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $RelationshipStatesTable extends RelationshipStates
    with TableInfo<$RelationshipStatesTable, RelationshipState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RelationshipStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE CASCADE',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<RelationshipStage, String> stage =
      GeneratedColumn<String>(
        'stage',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<RelationshipStage>(
        $RelationshipStatesTable.$converterstage,
      );
  static const VerificationMeta _affinityMeta = const VerificationMeta(
    'affinity',
  );
  @override
  late final GeneratedColumn<int> affinity = GeneratedColumn<int>(
    'affinity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    stage,
    affinity,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'relationship_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<RelationshipState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('affinity')) {
      context.handle(
        _affinityMeta,
        affinity.isAcceptableOrUnknown(data['affinity']!, _affinityMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RelationshipState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RelationshipState(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      )!,
      stage: $RelationshipStatesTable.$converterstage.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}stage'],
        )!,
      ),
      affinity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}affinity'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RelationshipStatesTable createAlias(String alias) {
    return $RelationshipStatesTable(attachedDatabase, alias);
  }

  static TypeConverter<RelationshipStage, String> $converterstage =
      const RelationshipStageConverter();
}

class RelationshipState extends DataClass
    implements Insertable<RelationshipState> {
  final int id;

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）；每角色至多一行。
  final int characterId;

  /// 必填枚举（stranger/acquainted/familiar/intimate/soulmate），字符串落库。
  final RelationshipStage stage;

  /// 亲密度 0-100（仓储/服务层 clamp，DB 不设 CHECK 约束）。
  final int affinity;
  final DateTime updatedAt;
  const RelationshipState({
    required this.id,
    required this.characterId,
    required this.stage,
    required this.affinity,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<int>(characterId);
    {
      map['stage'] = Variable<String>(
        $RelationshipStatesTable.$converterstage.toSql(stage),
      );
    }
    map['affinity'] = Variable<int>(affinity);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RelationshipStatesCompanion toCompanion(bool nullToAbsent) {
    return RelationshipStatesCompanion(
      id: Value(id),
      characterId: Value(characterId),
      stage: Value(stage),
      affinity: Value(affinity),
      updatedAt: Value(updatedAt),
    );
  }

  factory RelationshipState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RelationshipState(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<int>(json['characterId']),
      stage: serializer.fromJson<RelationshipStage>(json['stage']),
      affinity: serializer.fromJson<int>(json['affinity']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<int>(characterId),
      'stage': serializer.toJson<RelationshipStage>(stage),
      'affinity': serializer.toJson<int>(affinity),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RelationshipState copyWith({
    int? id,
    int? characterId,
    RelationshipStage? stage,
    int? affinity,
    DateTime? updatedAt,
  }) => RelationshipState(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    stage: stage ?? this.stage,
    affinity: affinity ?? this.affinity,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RelationshipState copyWithCompanion(RelationshipStatesCompanion data) {
    return RelationshipState(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      stage: data.stage.present ? data.stage.value : this.stage,
      affinity: data.affinity.present ? data.affinity.value : this.affinity,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RelationshipState(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('stage: $stage, ')
          ..write('affinity: $affinity, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, characterId, stage, affinity, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RelationshipState &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.stage == this.stage &&
          other.affinity == this.affinity &&
          other.updatedAt == this.updatedAt);
}

class RelationshipStatesCompanion extends UpdateCompanion<RelationshipState> {
  final Value<int> id;
  final Value<int> characterId;
  final Value<RelationshipStage> stage;
  final Value<int> affinity;
  final Value<DateTime> updatedAt;
  const RelationshipStatesCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.stage = const Value.absent(),
    this.affinity = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  RelationshipStatesCompanion.insert({
    this.id = const Value.absent(),
    required int characterId,
    required RelationshipStage stage,
    this.affinity = const Value.absent(),
    required DateTime updatedAt,
  }) : characterId = Value(characterId),
       stage = Value(stage),
       updatedAt = Value(updatedAt);
  static Insertable<RelationshipState> custom({
    Expression<int>? id,
    Expression<int>? characterId,
    Expression<String>? stage,
    Expression<int>? affinity,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (stage != null) 'stage': stage,
      if (affinity != null) 'affinity': affinity,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  RelationshipStatesCompanion copyWith({
    Value<int>? id,
    Value<int>? characterId,
    Value<RelationshipStage>? stage,
    Value<int>? affinity,
    Value<DateTime>? updatedAt,
  }) {
    return RelationshipStatesCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      stage: stage ?? this.stage,
      affinity: affinity ?? this.affinity,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(
        $RelationshipStatesTable.$converterstage.toSql(stage.value),
      );
    }
    if (affinity.present) {
      map['affinity'] = Variable<int>(affinity.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RelationshipStatesCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('stage: $stage, ')
          ..write('affinity: $affinity, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ProactivePlansTable extends ProactivePlans
    with TableInfo<$ProactivePlansTable, ProactivePlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProactivePlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<int> conversationId = GeneratedColumn<int>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES conversations (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
    'scheduled_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<ProactivePlanStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<ProactivePlanStatus>($ProactivePlansTable.$converterstatus);
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (id) ON DELETE SET NULL',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    conversationId,
    content,
    scheduledAt,
    sentAt,
    status,
    messageId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'proactive_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProactivePlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProactivePlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProactivePlan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}conversation_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_at'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      ),
      status: $ProactivePlansTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      ),
    );
  }

  @override
  $ProactivePlansTable createAlias(String alias) {
    return $ProactivePlansTable(attachedDatabase, alias);
  }

  static TypeConverter<ProactivePlanStatus, String> $converterstatus =
      const ProactivePlanStatusConverter();
}

class ProactivePlan extends DataClass implements Insertable<ProactivePlan> {
  final int id;

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  final int characterId;

  /// 必填外键 → conversations.id，ondelete=CASCADE（随对话删除）。
  final int conversationId;

  /// 预生成文案（必填文本）。
  final String content;

  /// 计划发送时间（必填）。
  final DateTime scheduledAt;

  /// 实际发送时间（可空；置 sent 时写，计数/冷却口径单一来源）。
  final DateTime? sentAt;

  /// 必填枚举（scheduled/sent/expired/dropped），字符串落库。
  final ProactivePlanStatus status;

  /// 已发送消息 id（可空）；消息删除时 FK setNull（重生成截断场景）。
  final int? messageId;
  const ProactivePlan({
    required this.id,
    required this.characterId,
    required this.conversationId,
    required this.content,
    required this.scheduledAt,
    this.sentAt,
    required this.status,
    this.messageId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<int>(characterId);
    map['conversation_id'] = Variable<int>(conversationId);
    map['content'] = Variable<String>(content);
    map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    if (!nullToAbsent || sentAt != null) {
      map['sent_at'] = Variable<DateTime>(sentAt);
    }
    {
      map['status'] = Variable<String>(
        $ProactivePlansTable.$converterstatus.toSql(status),
      );
    }
    if (!nullToAbsent || messageId != null) {
      map['message_id'] = Variable<int>(messageId);
    }
    return map;
  }

  ProactivePlansCompanion toCompanion(bool nullToAbsent) {
    return ProactivePlansCompanion(
      id: Value(id),
      characterId: Value(characterId),
      conversationId: Value(conversationId),
      content: Value(content),
      scheduledAt: Value(scheduledAt),
      sentAt: sentAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sentAt),
      status: Value(status),
      messageId: messageId == null && nullToAbsent
          ? const Value.absent()
          : Value(messageId),
    );
  }

  factory ProactivePlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProactivePlan(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<int>(json['characterId']),
      conversationId: serializer.fromJson<int>(json['conversationId']),
      content: serializer.fromJson<String>(json['content']),
      scheduledAt: serializer.fromJson<DateTime>(json['scheduledAt']),
      sentAt: serializer.fromJson<DateTime?>(json['sentAt']),
      status: serializer.fromJson<ProactivePlanStatus>(json['status']),
      messageId: serializer.fromJson<int?>(json['messageId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<int>(characterId),
      'conversationId': serializer.toJson<int>(conversationId),
      'content': serializer.toJson<String>(content),
      'scheduledAt': serializer.toJson<DateTime>(scheduledAt),
      'sentAt': serializer.toJson<DateTime?>(sentAt),
      'status': serializer.toJson<ProactivePlanStatus>(status),
      'messageId': serializer.toJson<int?>(messageId),
    };
  }

  ProactivePlan copyWith({
    int? id,
    int? characterId,
    int? conversationId,
    String? content,
    DateTime? scheduledAt,
    Value<DateTime?> sentAt = const Value.absent(),
    ProactivePlanStatus? status,
    Value<int?> messageId = const Value.absent(),
  }) => ProactivePlan(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    conversationId: conversationId ?? this.conversationId,
    content: content ?? this.content,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    sentAt: sentAt.present ? sentAt.value : this.sentAt,
    status: status ?? this.status,
    messageId: messageId.present ? messageId.value : this.messageId,
  );
  ProactivePlan copyWithCompanion(ProactivePlansCompanion data) {
    return ProactivePlan(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      content: data.content.present ? data.content.value : this.content,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      status: data.status.present ? data.status.value : this.status,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProactivePlan(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('conversationId: $conversationId, ')
          ..write('content: $content, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('sentAt: $sentAt, ')
          ..write('status: $status, ')
          ..write('messageId: $messageId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    characterId,
    conversationId,
    content,
    scheduledAt,
    sentAt,
    status,
    messageId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProactivePlan &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.conversationId == this.conversationId &&
          other.content == this.content &&
          other.scheduledAt == this.scheduledAt &&
          other.sentAt == this.sentAt &&
          other.status == this.status &&
          other.messageId == this.messageId);
}

class ProactivePlansCompanion extends UpdateCompanion<ProactivePlan> {
  final Value<int> id;
  final Value<int> characterId;
  final Value<int> conversationId;
  final Value<String> content;
  final Value<DateTime> scheduledAt;
  final Value<DateTime?> sentAt;
  final Value<ProactivePlanStatus> status;
  final Value<int?> messageId;
  const ProactivePlansCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.content = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.status = const Value.absent(),
    this.messageId = const Value.absent(),
  });
  ProactivePlansCompanion.insert({
    this.id = const Value.absent(),
    required int characterId,
    required int conversationId,
    required String content,
    required DateTime scheduledAt,
    this.sentAt = const Value.absent(),
    required ProactivePlanStatus status,
    this.messageId = const Value.absent(),
  }) : characterId = Value(characterId),
       conversationId = Value(conversationId),
       content = Value(content),
       scheduledAt = Value(scheduledAt),
       status = Value(status);
  static Insertable<ProactivePlan> custom({
    Expression<int>? id,
    Expression<int>? characterId,
    Expression<int>? conversationId,
    Expression<String>? content,
    Expression<DateTime>? scheduledAt,
    Expression<DateTime>? sentAt,
    Expression<String>? status,
    Expression<int>? messageId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (content != null) 'content': content,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (sentAt != null) 'sent_at': sentAt,
      if (status != null) 'status': status,
      if (messageId != null) 'message_id': messageId,
    });
  }

  ProactivePlansCompanion copyWith({
    Value<int>? id,
    Value<int>? characterId,
    Value<int>? conversationId,
    Value<String>? content,
    Value<DateTime>? scheduledAt,
    Value<DateTime?>? sentAt,
    Value<ProactivePlanStatus>? status,
    Value<int?>? messageId,
  }) {
    return ProactivePlansCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      conversationId: conversationId ?? this.conversationId,
      content: content ?? this.content,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      sentAt: sentAt ?? this.sentAt,
      status: status ?? this.status,
      messageId: messageId ?? this.messageId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<int>(conversationId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $ProactivePlansTable.$converterstatus.toSql(status.value),
      );
    }
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProactivePlansCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('conversationId: $conversationId, ')
          ..write('content: $content, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('sentAt: $sentAt, ')
          ..write('status: $status, ')
          ..write('messageId: $messageId')
          ..write(')'))
        .toString();
  }
}

class $InnerThoughtsTable extends InnerThoughts
    with TableInfo<$InnerThoughtsTable, InnerThought> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InnerThoughtsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    messageId,
    content,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inner_thoughts';
  @override
  VerificationContext validateIntegrity(
    Insertable<InnerThought> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InnerThought map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InnerThought(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $InnerThoughtsTable createAlias(String alias) {
    return $InnerThoughtsTable(attachedDatabase, alias);
  }
}

class InnerThought extends DataClass implements Insertable<InnerThought> {
  final int id;

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  final int characterId;

  /// 必填外键 → messages.id，ondelete=CASCADE（thought 随消息删除级联）。
  final int messageId;

  /// 独白正文（必填文本）。
  final String content;
  final DateTime createdAt;
  const InnerThought({
    required this.id,
    required this.characterId,
    required this.messageId,
    required this.content,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<int>(characterId);
    map['message_id'] = Variable<int>(messageId);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  InnerThoughtsCompanion toCompanion(bool nullToAbsent) {
    return InnerThoughtsCompanion(
      id: Value(id),
      characterId: Value(characterId),
      messageId: Value(messageId),
      content: Value(content),
      createdAt: Value(createdAt),
    );
  }

  factory InnerThought.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InnerThought(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<int>(json['characterId']),
      messageId: serializer.fromJson<int>(json['messageId']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<int>(characterId),
      'messageId': serializer.toJson<int>(messageId),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  InnerThought copyWith({
    int? id,
    int? characterId,
    int? messageId,
    String? content,
    DateTime? createdAt,
  }) => InnerThought(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    messageId: messageId ?? this.messageId,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
  );
  InnerThought copyWithCompanion(InnerThoughtsCompanion data) {
    return InnerThought(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InnerThought(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('messageId: $messageId, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, characterId, messageId, content, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InnerThought &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.messageId == this.messageId &&
          other.content == this.content &&
          other.createdAt == this.createdAt);
}

class InnerThoughtsCompanion extends UpdateCompanion<InnerThought> {
  final Value<int> id;
  final Value<int> characterId;
  final Value<int> messageId;
  final Value<String> content;
  final Value<DateTime> createdAt;
  const InnerThoughtsCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  InnerThoughtsCompanion.insert({
    this.id = const Value.absent(),
    required int characterId,
    required int messageId,
    required String content,
    required DateTime createdAt,
  }) : characterId = Value(characterId),
       messageId = Value(messageId),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<InnerThought> custom({
    Expression<int>? id,
    Expression<int>? characterId,
    Expression<int>? messageId,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (messageId != null) 'message_id': messageId,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  InnerThoughtsCompanion copyWith({
    Value<int>? id,
    Value<int>? characterId,
    Value<int>? messageId,
    Value<String>? content,
    Value<DateTime>? createdAt,
  }) {
    return InnerThoughtsCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      messageId: messageId ?? this.messageId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InnerThoughtsCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('messageId: $messageId, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $EmbeddingEntriesTable extends EmbeddingEntries
    with TableInfo<$EmbeddingEntriesTable, EmbeddingEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmbeddingEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<int> entryId = GeneratedColumn<int>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentSnapshotMeta = const VerificationMeta(
    'contentSnapshot',
  );
  @override
  late final GeneratedColumn<String> contentSnapshot = GeneratedColumn<String>(
    'content_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vectorMeta = const VerificationMeta('vector');
  @override
  late final GeneratedColumn<Uint8List> vector = GeneratedColumn<Uint8List>(
    'vector',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dimsMeta = const VerificationMeta('dims');
  @override
  late final GeneratedColumn<int> dims = GeneratedColumn<int>(
    'dims',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    entryId,
    contentSnapshot,
    vector,
    model,
    dims,
    contentHash,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'embedding_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<EmbeddingEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('content_snapshot')) {
      context.handle(
        _contentSnapshotMeta,
        contentSnapshot.isAcceptableOrUnknown(
          data['content_snapshot']!,
          _contentSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentSnapshotMeta);
    }
    if (data.containsKey('vector')) {
      context.handle(
        _vectorMeta,
        vector.isAcceptableOrUnknown(data['vector']!, _vectorMeta),
      );
    } else if (isInserting) {
      context.missing(_vectorMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('dims')) {
      context.handle(
        _dimsMeta,
        dims.isAcceptableOrUnknown(data['dims']!, _dimsMeta),
      );
    } else if (isInserting) {
      context.missing(_dimsMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EmbeddingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EmbeddingEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_id'],
      )!,
      contentSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_snapshot'],
      )!,
      vector: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}vector'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      dims: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dims'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EmbeddingEntriesTable createAlias(String alias) {
    return $EmbeddingEntriesTable(attachedDatabase, alias);
  }
}

class EmbeddingEntry extends DataClass implements Insertable<EmbeddingEntry> {
  final int id;

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除清向量）。
  final int characterId;

  /// 逻辑回指 memory_entries.id（普通 int，不建硬 FK）。
  final int entryId;

  /// 补嵌时点的文本快照（截断上限 2000 由仓储层负责，SR-21）。
  final String contentSnapshot;

  /// 向量 blob = float32 LE 打包（1536 维 ≈ 6144 字节，无压缩）。
  final Uint8List vector;

  /// 模型指纹（如 text-embedding-3-small）。
  final String model;

  /// 向量维度指纹。
  final int dims;

  /// SHA-256 hex（内容 hash，SR-21 去重键组成部分）。
  final String contentHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  const EmbeddingEntry({
    required this.id,
    required this.characterId,
    required this.entryId,
    required this.contentSnapshot,
    required this.vector,
    required this.model,
    required this.dims,
    required this.contentHash,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<int>(characterId);
    map['entry_id'] = Variable<int>(entryId);
    map['content_snapshot'] = Variable<String>(contentSnapshot);
    map['vector'] = Variable<Uint8List>(vector);
    map['model'] = Variable<String>(model);
    map['dims'] = Variable<int>(dims);
    map['content_hash'] = Variable<String>(contentHash);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  EmbeddingEntriesCompanion toCompanion(bool nullToAbsent) {
    return EmbeddingEntriesCompanion(
      id: Value(id),
      characterId: Value(characterId),
      entryId: Value(entryId),
      contentSnapshot: Value(contentSnapshot),
      vector: Value(vector),
      model: Value(model),
      dims: Value(dims),
      contentHash: Value(contentHash),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory EmbeddingEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EmbeddingEntry(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<int>(json['characterId']),
      entryId: serializer.fromJson<int>(json['entryId']),
      contentSnapshot: serializer.fromJson<String>(json['contentSnapshot']),
      vector: serializer.fromJson<Uint8List>(json['vector']),
      model: serializer.fromJson<String>(json['model']),
      dims: serializer.fromJson<int>(json['dims']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<int>(characterId),
      'entryId': serializer.toJson<int>(entryId),
      'contentSnapshot': serializer.toJson<String>(contentSnapshot),
      'vector': serializer.toJson<Uint8List>(vector),
      'model': serializer.toJson<String>(model),
      'dims': serializer.toJson<int>(dims),
      'contentHash': serializer.toJson<String>(contentHash),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  EmbeddingEntry copyWith({
    int? id,
    int? characterId,
    int? entryId,
    String? contentSnapshot,
    Uint8List? vector,
    String? model,
    int? dims,
    String? contentHash,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => EmbeddingEntry(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    entryId: entryId ?? this.entryId,
    contentSnapshot: contentSnapshot ?? this.contentSnapshot,
    vector: vector ?? this.vector,
    model: model ?? this.model,
    dims: dims ?? this.dims,
    contentHash: contentHash ?? this.contentHash,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EmbeddingEntry copyWithCompanion(EmbeddingEntriesCompanion data) {
    return EmbeddingEntry(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      contentSnapshot: data.contentSnapshot.present
          ? data.contentSnapshot.value
          : this.contentSnapshot,
      vector: data.vector.present ? data.vector.value : this.vector,
      model: data.model.present ? data.model.value : this.model,
      dims: data.dims.present ? data.dims.value : this.dims,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EmbeddingEntry(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('entryId: $entryId, ')
          ..write('contentSnapshot: $contentSnapshot, ')
          ..write('vector: $vector, ')
          ..write('model: $model, ')
          ..write('dims: $dims, ')
          ..write('contentHash: $contentHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    characterId,
    entryId,
    contentSnapshot,
    $driftBlobEquality.hash(vector),
    model,
    dims,
    contentHash,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmbeddingEntry &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.entryId == this.entryId &&
          other.contentSnapshot == this.contentSnapshot &&
          $driftBlobEquality.equals(other.vector, this.vector) &&
          other.model == this.model &&
          other.dims == this.dims &&
          other.contentHash == this.contentHash &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class EmbeddingEntriesCompanion extends UpdateCompanion<EmbeddingEntry> {
  final Value<int> id;
  final Value<int> characterId;
  final Value<int> entryId;
  final Value<String> contentSnapshot;
  final Value<Uint8List> vector;
  final Value<String> model;
  final Value<int> dims;
  final Value<String> contentHash;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const EmbeddingEntriesCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.entryId = const Value.absent(),
    this.contentSnapshot = const Value.absent(),
    this.vector = const Value.absent(),
    this.model = const Value.absent(),
    this.dims = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  EmbeddingEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int characterId,
    required int entryId,
    required String contentSnapshot,
    required Uint8List vector,
    required String model,
    required int dims,
    required String contentHash,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : characterId = Value(characterId),
       entryId = Value(entryId),
       contentSnapshot = Value(contentSnapshot),
       vector = Value(vector),
       model = Value(model),
       dims = Value(dims),
       contentHash = Value(contentHash),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<EmbeddingEntry> custom({
    Expression<int>? id,
    Expression<int>? characterId,
    Expression<int>? entryId,
    Expression<String>? contentSnapshot,
    Expression<Uint8List>? vector,
    Expression<String>? model,
    Expression<int>? dims,
    Expression<String>? contentHash,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (entryId != null) 'entry_id': entryId,
      if (contentSnapshot != null) 'content_snapshot': contentSnapshot,
      if (vector != null) 'vector': vector,
      if (model != null) 'model': model,
      if (dims != null) 'dims': dims,
      if (contentHash != null) 'content_hash': contentHash,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  EmbeddingEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? characterId,
    Value<int>? entryId,
    Value<String>? contentSnapshot,
    Value<Uint8List>? vector,
    Value<String>? model,
    Value<int>? dims,
    Value<String>? contentHash,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return EmbeddingEntriesCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      entryId: entryId ?? this.entryId,
      contentSnapshot: contentSnapshot ?? this.contentSnapshot,
      vector: vector ?? this.vector,
      model: model ?? this.model,
      dims: dims ?? this.dims,
      contentHash: contentHash ?? this.contentHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<int>(entryId.value);
    }
    if (contentSnapshot.present) {
      map['content_snapshot'] = Variable<String>(contentSnapshot.value);
    }
    if (vector.present) {
      map['vector'] = Variable<Uint8List>(vector.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (dims.present) {
      map['dims'] = Variable<int>(dims.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmbeddingEntriesCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('entryId: $entryId, ')
          ..write('contentSnapshot: $contentSnapshot, ')
          ..write('vector: $vector, ')
          ..write('model: $model, ')
          ..write('dims: $dims, ')
          ..write('contentHash: $contentHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $SemanticHitsTable extends SemanticHits
    with TableInfo<$SemanticHitsTable, SemanticHit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SemanticHitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<int> entryId = GeneratedColumn<int>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queryMeta = const VerificationMeta('query');
  @override
  late final GeneratedColumn<String> query = GeneratedColumn<String>(
    'query',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    entryId,
    query,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'semantic_hits';
  @override
  VerificationContext validateIntegrity(
    Insertable<SemanticHit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('query')) {
      context.handle(
        _queryMeta,
        query.isAcceptableOrUnknown(data['query']!, _queryMeta),
      );
    } else if (isInserting) {
      context.missing(_queryMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SemanticHit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SemanticHit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_id'],
      )!,
      query: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}query'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SemanticHitsTable createAlias(String alias) {
    return $SemanticHitsTable(attachedDatabase, alias);
  }
}

class SemanticHit extends DataClass implements Insertable<SemanticHit> {
  final int id;

  /// 必填外键 → characters.id，ondelete=CASCADE（随角色删除）。
  final int characterId;

  /// 逻辑回指 memory_entries.id（普通 int，同 [EmbeddingEntries.entryId]）。
  final int entryId;

  /// 检索 query 快照（必填文本）。
  final String query;
  final DateTime createdAt;
  const SemanticHit({
    required this.id,
    required this.characterId,
    required this.entryId,
    required this.query,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<int>(characterId);
    map['entry_id'] = Variable<int>(entryId);
    map['query'] = Variable<String>(query);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SemanticHitsCompanion toCompanion(bool nullToAbsent) {
    return SemanticHitsCompanion(
      id: Value(id),
      characterId: Value(characterId),
      entryId: Value(entryId),
      query: Value(query),
      createdAt: Value(createdAt),
    );
  }

  factory SemanticHit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SemanticHit(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<int>(json['characterId']),
      entryId: serializer.fromJson<int>(json['entryId']),
      query: serializer.fromJson<String>(json['query']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<int>(characterId),
      'entryId': serializer.toJson<int>(entryId),
      'query': serializer.toJson<String>(query),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SemanticHit copyWith({
    int? id,
    int? characterId,
    int? entryId,
    String? query,
    DateTime? createdAt,
  }) => SemanticHit(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    entryId: entryId ?? this.entryId,
    query: query ?? this.query,
    createdAt: createdAt ?? this.createdAt,
  );
  SemanticHit copyWithCompanion(SemanticHitsCompanion data) {
    return SemanticHit(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      query: data.query.present ? data.query.value : this.query,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SemanticHit(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('entryId: $entryId, ')
          ..write('query: $query, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, characterId, entryId, query, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SemanticHit &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.entryId == this.entryId &&
          other.query == this.query &&
          other.createdAt == this.createdAt);
}

class SemanticHitsCompanion extends UpdateCompanion<SemanticHit> {
  final Value<int> id;
  final Value<int> characterId;
  final Value<int> entryId;
  final Value<String> query;
  final Value<DateTime> createdAt;
  const SemanticHitsCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.entryId = const Value.absent(),
    this.query = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SemanticHitsCompanion.insert({
    this.id = const Value.absent(),
    required int characterId,
    required int entryId,
    required String query,
    required DateTime createdAt,
  }) : characterId = Value(characterId),
       entryId = Value(entryId),
       query = Value(query),
       createdAt = Value(createdAt);
  static Insertable<SemanticHit> custom({
    Expression<int>? id,
    Expression<int>? characterId,
    Expression<int>? entryId,
    Expression<String>? query,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (entryId != null) 'entry_id': entryId,
      if (query != null) 'query': query,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SemanticHitsCompanion copyWith({
    Value<int>? id,
    Value<int>? characterId,
    Value<int>? entryId,
    Value<String>? query,
    Value<DateTime>? createdAt,
  }) {
    return SemanticHitsCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      entryId: entryId ?? this.entryId,
      query: query ?? this.query,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<int>(entryId.value);
    }
    if (query.present) {
      map['query'] = Variable<String>(query.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SemanticHitsCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('entryId: $entryId, ')
          ..write('query: $query, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $MessageSwipesTable extends MessageSwipes
    with TableInfo<$MessageSwipesTable, MessageSwipe> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageSwipesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<int> messageId = GeneratedColumn<int>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES messages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _indexMeta = const VerificationMeta('index');
  @override
  late final GeneratedColumn<int> index = GeneratedColumn<int>(
    'index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    messageId,
    index,
    content,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_swipes';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageSwipe> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('index')) {
      context.handle(
        _indexMeta,
        index.isAcceptableOrUnknown(data['index']!, _indexMeta),
      );
    } else if (isInserting) {
      context.missing(_indexMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {messageId, index},
  ];
  @override
  MessageSwipe map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageSwipe(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_id'],
      )!,
      index: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}index'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $MessageSwipesTable createAlias(String alias) {
    return $MessageSwipesTable(attachedDatabase, alias);
  }
}

class MessageSwipe extends DataClass implements Insertable<MessageSwipe> {
  final int id;

  /// 必填外键 → messages.id，桌面端 ondelete=CASCADE + index=True。
  final int messageId;

  /// 候选序号（0 起；必填整数）。
  final int index;

  /// 候选正文（必填文本）。
  final String content;
  final DateTime createdAt;
  const MessageSwipe({
    required this.id,
    required this.messageId,
    required this.index,
    required this.content,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['message_id'] = Variable<int>(messageId);
    map['index'] = Variable<int>(index);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessageSwipesCompanion toCompanion(bool nullToAbsent) {
    return MessageSwipesCompanion(
      id: Value(id),
      messageId: Value(messageId),
      index: Value(index),
      content: Value(content),
      createdAt: Value(createdAt),
    );
  }

  factory MessageSwipe.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageSwipe(
      id: serializer.fromJson<int>(json['id']),
      messageId: serializer.fromJson<int>(json['messageId']),
      index: serializer.fromJson<int>(json['index']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'messageId': serializer.toJson<int>(messageId),
      'index': serializer.toJson<int>(index),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  MessageSwipe copyWith({
    int? id,
    int? messageId,
    int? index,
    String? content,
    DateTime? createdAt,
  }) => MessageSwipe(
    id: id ?? this.id,
    messageId: messageId ?? this.messageId,
    index: index ?? this.index,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
  );
  MessageSwipe copyWithCompanion(MessageSwipesCompanion data) {
    return MessageSwipe(
      id: data.id.present ? data.id.value : this.id,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      index: data.index.present ? data.index.value : this.index,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageSwipe(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('index: $index, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, messageId, index, content, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageSwipe &&
          other.id == this.id &&
          other.messageId == this.messageId &&
          other.index == this.index &&
          other.content == this.content &&
          other.createdAt == this.createdAt);
}

class MessageSwipesCompanion extends UpdateCompanion<MessageSwipe> {
  final Value<int> id;
  final Value<int> messageId;
  final Value<int> index;
  final Value<String> content;
  final Value<DateTime> createdAt;
  const MessageSwipesCompanion({
    this.id = const Value.absent(),
    this.messageId = const Value.absent(),
    this.index = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MessageSwipesCompanion.insert({
    this.id = const Value.absent(),
    required int messageId,
    required int index,
    required String content,
    required DateTime createdAt,
  }) : messageId = Value(messageId),
       index = Value(index),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<MessageSwipe> custom({
    Expression<int>? id,
    Expression<int>? messageId,
    Expression<int>? index,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (messageId != null) 'message_id': messageId,
      if (index != null) 'index': index,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  MessageSwipesCompanion copyWith({
    Value<int>? id,
    Value<int>? messageId,
    Value<int>? index,
    Value<String>? content,
    Value<DateTime>? createdAt,
  }) {
    return MessageSwipesCompanion(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      index: index ?? this.index,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<int>(messageId.value);
    }
    if (index.present) {
      map['index'] = Variable<int>(index.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageSwipesCompanion(')
          ..write('id: $id, ')
          ..write('messageId: $messageId, ')
          ..write('index: $index, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $LorebookEntriesTable extends LorebookEntries
    with TableInfo<$LorebookEntriesTable, LorebookEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LorebookEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _characterIdMeta = const VerificationMeta(
    'characterId',
  );
  @override
  late final GeneratedColumn<int> characterId = GeneratedColumn<int>(
    'character_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES characters (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> keys =
      GeneratedColumn<String>(
        'keys',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<String>>($LorebookEntriesTable.$converterkeys);
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _constantMeta = const VerificationMeta(
    'constant',
  );
  @override
  late final GeneratedColumn<bool> constant = GeneratedColumn<bool>(
    'constant',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("constant" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _orderMeta = const VerificationMeta('order');
  @override
  late final GeneratedColumn<int> order = GeneratedColumn<int>(
    'order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(100),
  );
  static const VerificationMeta _probabilityMeta = const VerificationMeta(
    'probability',
  );
  @override
  late final GeneratedColumn<int> probability = GeneratedColumn<int>(
    'probability',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(100),
  );
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _groupWeightMeta = const VerificationMeta(
    'groupWeight',
  );
  @override
  late final GeneratedColumn<int> groupWeight = GeneratedColumn<int>(
    'group_weight',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(100),
  );
  static const VerificationMeta _matchModeMeta = const VerificationMeta(
    'matchMode',
  );
  @override
  late final GeneratedColumn<String> matchMode = GeneratedColumn<String>(
    'match_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('or'),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<String> position = GeneratedColumn<String>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('world'),
  );
  static const VerificationMeta _depthMeta = const VerificationMeta('depth');
  @override
  late final GeneratedColumn<int> depth = GeneratedColumn<int>(
    'depth',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(20),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    characterId,
    title,
    keys,
    content,
    constant,
    order,
    probability,
    groupName,
    groupWeight,
    matchMode,
    position,
    depth,
    source,
    enabled,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lorebook_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LorebookEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('character_id')) {
      context.handle(
        _characterIdMeta,
        characterId.isAcceptableOrUnknown(
          data['character_id']!,
          _characterIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_characterIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('constant')) {
      context.handle(
        _constantMeta,
        constant.isAcceptableOrUnknown(data['constant']!, _constantMeta),
      );
    }
    if (data.containsKey('order')) {
      context.handle(
        _orderMeta,
        order.isAcceptableOrUnknown(data['order']!, _orderMeta),
      );
    }
    if (data.containsKey('probability')) {
      context.handle(
        _probabilityMeta,
        probability.isAcceptableOrUnknown(
          data['probability']!,
          _probabilityMeta,
        ),
      );
    }
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
      );
    }
    if (data.containsKey('group_weight')) {
      context.handle(
        _groupWeightMeta,
        groupWeight.isAcceptableOrUnknown(
          data['group_weight']!,
          _groupWeightMeta,
        ),
      );
    }
    if (data.containsKey('match_mode')) {
      context.handle(
        _matchModeMeta,
        matchMode.isAcceptableOrUnknown(data['match_mode']!, _matchModeMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('depth')) {
      context.handle(
        _depthMeta,
        depth.isAcceptableOrUnknown(data['depth']!, _depthMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LorebookEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LorebookEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      characterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}character_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      keys: $LorebookEntriesTable.$converterkeys.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}keys'],
        )!,
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      constant: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}constant'],
      )!,
      order: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order'],
      )!,
      probability: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}probability'],
      )!,
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      )!,
      groupWeight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}group_weight'],
      )!,
      matchMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}match_mode'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}position'],
      )!,
      depth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}depth'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $LorebookEntriesTable createAlias(String alias) {
    return $LorebookEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<List<String>, String> $converterkeys =
      const StringListConverter();
}

class LorebookEntry extends DataClass implements Insertable<LorebookEntry> {
  final int id;

  /// 必填外键 → characters.id，桌面端 ondelete=CASCADE + index=True。
  final int characterId;

  /// 条目标题（可空/缺省空串，桌面 String(200)）。
  final String title;

  /// 触发关键词（JSON 数组；桌面《JsonList》 TypeDecorator 语义）。
  final List<String> keys;

  /// 命中后注入内容（必填文本）。
  final String content;

  /// 常驻（不判命中直接注入；缺省 false）。
  final bool constant;

  /// 命中条目排序（升序注入；域 [0,9999]，缺省 100）。
  final int order;

  /// 独立命中概率（域 [1,100]，缺省 100）。
  final int probability;

  /// 互斥组名（空=不分组；桌面 String(100)）。
  final String groupName;

  /// 组内权重（同组随机抽一；域 [1,100]，缺省 100）。
  final int groupWeight;

  /// 命中模式（or / and；缺省 or）。
  final String matchMode;

  /// 注入位置（world / before_char / after_char；缺省 world）。
  final String position;

  /// 参与命中的最近轮数（域 [0,20]，缺省 20；0=只看当前输入）。
  final int depth;

  /// 条目来源（manual / auto；记忆宫殿产出为 auto，缺省 manual）。
  final String source;

  /// 单条开关（缺省 true）。
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LorebookEntry({
    required this.id,
    required this.characterId,
    required this.title,
    required this.keys,
    required this.content,
    required this.constant,
    required this.order,
    required this.probability,
    required this.groupName,
    required this.groupWeight,
    required this.matchMode,
    required this.position,
    required this.depth,
    required this.source,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['character_id'] = Variable<int>(characterId);
    map['title'] = Variable<String>(title);
    {
      map['keys'] = Variable<String>(
        $LorebookEntriesTable.$converterkeys.toSql(keys),
      );
    }
    map['content'] = Variable<String>(content);
    map['constant'] = Variable<bool>(constant);
    map['order'] = Variable<int>(order);
    map['probability'] = Variable<int>(probability);
    map['group_name'] = Variable<String>(groupName);
    map['group_weight'] = Variable<int>(groupWeight);
    map['match_mode'] = Variable<String>(matchMode);
    map['position'] = Variable<String>(position);
    map['depth'] = Variable<int>(depth);
    map['source'] = Variable<String>(source);
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LorebookEntriesCompanion toCompanion(bool nullToAbsent) {
    return LorebookEntriesCompanion(
      id: Value(id),
      characterId: Value(characterId),
      title: Value(title),
      keys: Value(keys),
      content: Value(content),
      constant: Value(constant),
      order: Value(order),
      probability: Value(probability),
      groupName: Value(groupName),
      groupWeight: Value(groupWeight),
      matchMode: Value(matchMode),
      position: Value(position),
      depth: Value(depth),
      source: Value(source),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LorebookEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LorebookEntry(
      id: serializer.fromJson<int>(json['id']),
      characterId: serializer.fromJson<int>(json['characterId']),
      title: serializer.fromJson<String>(json['title']),
      keys: serializer.fromJson<List<String>>(json['keys']),
      content: serializer.fromJson<String>(json['content']),
      constant: serializer.fromJson<bool>(json['constant']),
      order: serializer.fromJson<int>(json['order']),
      probability: serializer.fromJson<int>(json['probability']),
      groupName: serializer.fromJson<String>(json['groupName']),
      groupWeight: serializer.fromJson<int>(json['groupWeight']),
      matchMode: serializer.fromJson<String>(json['matchMode']),
      position: serializer.fromJson<String>(json['position']),
      depth: serializer.fromJson<int>(json['depth']),
      source: serializer.fromJson<String>(json['source']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'characterId': serializer.toJson<int>(characterId),
      'title': serializer.toJson<String>(title),
      'keys': serializer.toJson<List<String>>(keys),
      'content': serializer.toJson<String>(content),
      'constant': serializer.toJson<bool>(constant),
      'order': serializer.toJson<int>(order),
      'probability': serializer.toJson<int>(probability),
      'groupName': serializer.toJson<String>(groupName),
      'groupWeight': serializer.toJson<int>(groupWeight),
      'matchMode': serializer.toJson<String>(matchMode),
      'position': serializer.toJson<String>(position),
      'depth': serializer.toJson<int>(depth),
      'source': serializer.toJson<String>(source),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LorebookEntry copyWith({
    int? id,
    int? characterId,
    String? title,
    List<String>? keys,
    String? content,
    bool? constant,
    int? order,
    int? probability,
    String? groupName,
    int? groupWeight,
    String? matchMode,
    String? position,
    int? depth,
    String? source,
    bool? enabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => LorebookEntry(
    id: id ?? this.id,
    characterId: characterId ?? this.characterId,
    title: title ?? this.title,
    keys: keys ?? this.keys,
    content: content ?? this.content,
    constant: constant ?? this.constant,
    order: order ?? this.order,
    probability: probability ?? this.probability,
    groupName: groupName ?? this.groupName,
    groupWeight: groupWeight ?? this.groupWeight,
    matchMode: matchMode ?? this.matchMode,
    position: position ?? this.position,
    depth: depth ?? this.depth,
    source: source ?? this.source,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  LorebookEntry copyWithCompanion(LorebookEntriesCompanion data) {
    return LorebookEntry(
      id: data.id.present ? data.id.value : this.id,
      characterId: data.characterId.present
          ? data.characterId.value
          : this.characterId,
      title: data.title.present ? data.title.value : this.title,
      keys: data.keys.present ? data.keys.value : this.keys,
      content: data.content.present ? data.content.value : this.content,
      constant: data.constant.present ? data.constant.value : this.constant,
      order: data.order.present ? data.order.value : this.order,
      probability: data.probability.present
          ? data.probability.value
          : this.probability,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      groupWeight: data.groupWeight.present
          ? data.groupWeight.value
          : this.groupWeight,
      matchMode: data.matchMode.present ? data.matchMode.value : this.matchMode,
      position: data.position.present ? data.position.value : this.position,
      depth: data.depth.present ? data.depth.value : this.depth,
      source: data.source.present ? data.source.value : this.source,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LorebookEntry(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('title: $title, ')
          ..write('keys: $keys, ')
          ..write('content: $content, ')
          ..write('constant: $constant, ')
          ..write('order: $order, ')
          ..write('probability: $probability, ')
          ..write('groupName: $groupName, ')
          ..write('groupWeight: $groupWeight, ')
          ..write('matchMode: $matchMode, ')
          ..write('position: $position, ')
          ..write('depth: $depth, ')
          ..write('source: $source, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    characterId,
    title,
    keys,
    content,
    constant,
    order,
    probability,
    groupName,
    groupWeight,
    matchMode,
    position,
    depth,
    source,
    enabled,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LorebookEntry &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.title == this.title &&
          other.keys == this.keys &&
          other.content == this.content &&
          other.constant == this.constant &&
          other.order == this.order &&
          other.probability == this.probability &&
          other.groupName == this.groupName &&
          other.groupWeight == this.groupWeight &&
          other.matchMode == this.matchMode &&
          other.position == this.position &&
          other.depth == this.depth &&
          other.source == this.source &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LorebookEntriesCompanion extends UpdateCompanion<LorebookEntry> {
  final Value<int> id;
  final Value<int> characterId;
  final Value<String> title;
  final Value<List<String>> keys;
  final Value<String> content;
  final Value<bool> constant;
  final Value<int> order;
  final Value<int> probability;
  final Value<String> groupName;
  final Value<int> groupWeight;
  final Value<String> matchMode;
  final Value<String> position;
  final Value<int> depth;
  final Value<String> source;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const LorebookEntriesCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.title = const Value.absent(),
    this.keys = const Value.absent(),
    this.content = const Value.absent(),
    this.constant = const Value.absent(),
    this.order = const Value.absent(),
    this.probability = const Value.absent(),
    this.groupName = const Value.absent(),
    this.groupWeight = const Value.absent(),
    this.matchMode = const Value.absent(),
    this.position = const Value.absent(),
    this.depth = const Value.absent(),
    this.source = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  LorebookEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int characterId,
    this.title = const Value.absent(),
    this.keys = const Value.absent(),
    this.content = const Value.absent(),
    this.constant = const Value.absent(),
    this.order = const Value.absent(),
    this.probability = const Value.absent(),
    this.groupName = const Value.absent(),
    this.groupWeight = const Value.absent(),
    this.matchMode = const Value.absent(),
    this.position = const Value.absent(),
    this.depth = const Value.absent(),
    this.source = const Value.absent(),
    this.enabled = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : characterId = Value(characterId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<LorebookEntry> custom({
    Expression<int>? id,
    Expression<int>? characterId,
    Expression<String>? title,
    Expression<String>? keys,
    Expression<String>? content,
    Expression<bool>? constant,
    Expression<int>? order,
    Expression<int>? probability,
    Expression<String>? groupName,
    Expression<int>? groupWeight,
    Expression<String>? matchMode,
    Expression<String>? position,
    Expression<int>? depth,
    Expression<String>? source,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (title != null) 'title': title,
      if (keys != null) 'keys': keys,
      if (content != null) 'content': content,
      if (constant != null) 'constant': constant,
      if (order != null) 'order': order,
      if (probability != null) 'probability': probability,
      if (groupName != null) 'group_name': groupName,
      if (groupWeight != null) 'group_weight': groupWeight,
      if (matchMode != null) 'match_mode': matchMode,
      if (position != null) 'position': position,
      if (depth != null) 'depth': depth,
      if (source != null) 'source': source,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  LorebookEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? characterId,
    Value<String>? title,
    Value<List<String>>? keys,
    Value<String>? content,
    Value<bool>? constant,
    Value<int>? order,
    Value<int>? probability,
    Value<String>? groupName,
    Value<int>? groupWeight,
    Value<String>? matchMode,
    Value<String>? position,
    Value<int>? depth,
    Value<String>? source,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return LorebookEntriesCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      title: title ?? this.title,
      keys: keys ?? this.keys,
      content: content ?? this.content,
      constant: constant ?? this.constant,
      order: order ?? this.order,
      probability: probability ?? this.probability,
      groupName: groupName ?? this.groupName,
      groupWeight: groupWeight ?? this.groupWeight,
      matchMode: matchMode ?? this.matchMode,
      position: position ?? this.position,
      depth: depth ?? this.depth,
      source: source ?? this.source,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<int>(characterId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (keys.present) {
      map['keys'] = Variable<String>(
        $LorebookEntriesTable.$converterkeys.toSql(keys.value),
      );
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (constant.present) {
      map['constant'] = Variable<bool>(constant.value);
    }
    if (order.present) {
      map['order'] = Variable<int>(order.value);
    }
    if (probability.present) {
      map['probability'] = Variable<int>(probability.value);
    }
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (groupWeight.present) {
      map['group_weight'] = Variable<int>(groupWeight.value);
    }
    if (matchMode.present) {
      map['match_mode'] = Variable<String>(matchMode.value);
    }
    if (position.present) {
      map['position'] = Variable<String>(position.value);
    }
    if (depth.present) {
      map['depth'] = Variable<int>(depth.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LorebookEntriesCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('title: $title, ')
          ..write('keys: $keys, ')
          ..write('content: $content, ')
          ..write('constant: $constant, ')
          ..write('order: $order, ')
          ..write('probability: $probability, ')
          ..write('groupName: $groupName, ')
          ..write('groupWeight: $groupWeight, ')
          ..write('matchMode: $matchMode, ')
          ..write('position: $position, ')
          ..write('depth: $depth, ')
          ..write('source: $source, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CharactersTable characters = $CharactersTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $MemoryEntriesTable memoryEntries = $MemoryEntriesTable(this);
  late final $PersonaRevisionsTable personaRevisions = $PersonaRevisionsTable(
    this,
  );
  late final $RelationshipStatesTable relationshipStates =
      $RelationshipStatesTable(this);
  late final $ProactivePlansTable proactivePlans = $ProactivePlansTable(this);
  late final $InnerThoughtsTable innerThoughts = $InnerThoughtsTable(this);
  late final $EmbeddingEntriesTable embeddingEntries = $EmbeddingEntriesTable(
    this,
  );
  late final $SemanticHitsTable semanticHits = $SemanticHitsTable(this);
  late final $MessageSwipesTable messageSwipes = $MessageSwipesTable(this);
  late final $LorebookEntriesTable lorebookEntries = $LorebookEntriesTable(
    this,
  );
  late final Index idxCharactersName = Index(
    'idx_characters_name',
    'CREATE INDEX idx_characters_name ON characters (name)',
  );
  late final Index idxConversationsCharacterId = Index(
    'idx_conversations_character_id',
    'CREATE INDEX idx_conversations_character_id ON conversations (character_id)',
  );
  late final Index idxMessagesConversationId = Index(
    'idx_messages_conversation_id',
    'CREATE INDEX idx_messages_conversation_id ON messages (conversation_id)',
  );
  late final Index idxMessagesCreatedAt = Index(
    'idx_messages_created_at',
    'CREATE INDEX idx_messages_created_at ON messages (created_at)',
  );
  late final Index idxMemoryEntriesCharacterId = Index(
    'idx_memory_entries_character_id',
    'CREATE INDEX idx_memory_entries_character_id ON memory_entries (character_id)',
  );
  late final Index idxPersonaRevisionsCharacterId = Index(
    'idx_persona_revisions_character_id',
    'CREATE INDEX idx_persona_revisions_character_id ON persona_revisions (character_id)',
  );
  late final Index idxRelationshipStatesCharacterId = Index(
    'idx_relationship_states_character_id',
    'CREATE UNIQUE INDEX idx_relationship_states_character_id ON relationship_states (character_id)',
  );
  late final Index idxProactivePlansCharacterId = Index(
    'idx_proactive_plans_character_id',
    'CREATE INDEX idx_proactive_plans_character_id ON proactive_plans (character_id)',
  );
  late final Index idxProactivePlansConversationId = Index(
    'idx_proactive_plans_conversation_id',
    'CREATE INDEX idx_proactive_plans_conversation_id ON proactive_plans (conversation_id)',
  );
  late final Index idxProactivePlansStatus = Index(
    'idx_proactive_plans_status',
    'CREATE INDEX idx_proactive_plans_status ON proactive_plans (status)',
  );
  late final Index idxInnerThoughtsCharacterId = Index(
    'idx_inner_thoughts_character_id',
    'CREATE INDEX idx_inner_thoughts_character_id ON inner_thoughts (character_id)',
  );
  late final Index idxInnerThoughtsMessageId = Index(
    'idx_inner_thoughts_message_id',
    'CREATE INDEX idx_inner_thoughts_message_id ON inner_thoughts (message_id)',
  );
  late final Index idxEmbeddingEntriesCharacterId = Index(
    'idx_embedding_entries_character_id',
    'CREATE INDEX idx_embedding_entries_character_id ON embedding_entries (character_id)',
  );
  late final Index idxEmbeddingEntriesCharacterIdContentHash = Index(
    'idx_embedding_entries_character_id_content_hash',
    'CREATE UNIQUE INDEX idx_embedding_entries_character_id_content_hash ON embedding_entries (character_id, content_hash)',
  );
  late final Index idxSemanticHitsCharacterId = Index(
    'idx_semantic_hits_character_id',
    'CREATE INDEX idx_semantic_hits_character_id ON semantic_hits (character_id)',
  );
  late final Index idxMessageSwipesMessageId = Index(
    'idx_message_swipes_message_id',
    'CREATE INDEX idx_message_swipes_message_id ON message_swipes (message_id)',
  );
  late final Index idxLorebookEntriesCharacterId = Index(
    'idx_lorebook_entries_character_id',
    'CREATE INDEX idx_lorebook_entries_character_id ON lorebook_entries (character_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    characters,
    conversations,
    messages,
    settings,
    memoryEntries,
    personaRevisions,
    relationshipStates,
    proactivePlans,
    innerThoughts,
    embeddingEntries,
    semanticHits,
    messageSwipes,
    lorebookEntries,
    idxCharactersName,
    idxConversationsCharacterId,
    idxMessagesConversationId,
    idxMessagesCreatedAt,
    idxMemoryEntriesCharacterId,
    idxPersonaRevisionsCharacterId,
    idxRelationshipStatesCharacterId,
    idxProactivePlansCharacterId,
    idxProactivePlansConversationId,
    idxProactivePlansStatus,
    idxInnerThoughtsCharacterId,
    idxInnerThoughtsMessageId,
    idxEmbeddingEntriesCharacterId,
    idxEmbeddingEntriesCharacterIdContentHash,
    idxSemanticHitsCharacterId,
    idxMessageSwipesMessageId,
    idxLorebookEntriesCharacterId,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('conversations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('messages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('memory_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('persona_revisions', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('relationship_states', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('proactive_plans', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('proactive_plans', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('proactive_plans', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('inner_thoughts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('inner_thoughts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('embedding_entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('semantic_hits', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'messages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('message_swipes', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'characters',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('lorebook_entries', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$CharactersTableCreateCompanionBuilder = CharactersCompanion Function({
  Value<int> id,
  required String name,
  Value<String> description,
  Value<String> personality,
  Value<String> scenario,
  Value<String> firstMes,
  Value<String> mesExample,
  Value<String> systemPrompt,
  Value<String> postHistoryInstructions,
  Value<List<String>> alternateGreetings,
  Value<List<String>> tags,
  Value<String> creator,
  Value<String> version,
  Value<Map<String, dynamic>> creatorNotes,
  Value<Map<String, dynamic>> extensions,
  Value<String?> avatar,
  Value<double> temperature,
  Value<List<Map<String, String>>> presetDialogues,
  Value<String> promptMode,
  Value<String> expertPrompt,
  required DateTime createdAt,
  required DateTime updatedAt,
});
typedef $$CharactersTableUpdateCompanionBuilder = CharactersCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String> description,
  Value<String> personality,
  Value<String> scenario,
  Value<String> firstMes,
  Value<String> mesExample,
  Value<String> systemPrompt,
  Value<String> postHistoryInstructions,
  Value<List<String>> alternateGreetings,
  Value<List<String>> tags,
  Value<String> creator,
  Value<String> version,
  Value<Map<String, dynamic>> creatorNotes,
  Value<Map<String, dynamic>> extensions,
  Value<String?> avatar,
  Value<double> temperature,
  Value<List<Map<String, String>>> presetDialogues,
  Value<String> promptMode,
  Value<String> expertPrompt,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$CharactersTableReferences
    extends BaseReferences<_$AppDatabase, $CharactersTable, Character> {
  $$CharactersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ConversationsTable, List<Conversation>>
  _conversationsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.conversations,
    aliasName: 'characters__id__conversations__character_id',
  );

  $$ConversationsTableProcessedTableManager get conversationsRefs {
    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.characterId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_conversationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MemoryEntriesTable, List<MemoryEntry>>
  _memoryEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.memoryEntries,
    aliasName: 'characters__id__memory_entries__character_id',
  );

  $$MemoryEntriesTableProcessedTableManager get memoryEntriesRefs {
    final manager = $$MemoryEntriesTableTableManager(
      $_db,
      $_db.memoryEntries,
    ).filter((f) => f.characterId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_memoryEntriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PersonaRevisionsTable, List<PersonaRevision>>
  _personaRevisionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.personaRevisions,
    aliasName: 'characters__id__persona_revisions__character_id',
  );

  $$PersonaRevisionsTableProcessedTableManager get personaRevisionsRefs {
    final manager = $$PersonaRevisionsTableTableManager(
      $_db,
      $_db.personaRevisions,
    ).filter((f) => f.characterId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _personaRevisionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RelationshipStatesTable, List<RelationshipState>>
  _relationshipStatesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.relationshipStates,
        aliasName: 'characters__id__relationship_states__character_id',
      );

  $$RelationshipStatesTableProcessedTableManager get relationshipStatesRefs {
    final manager = $$RelationshipStatesTableTableManager(
      $_db,
      $_db.relationshipStates,
    ).filter((f) => f.characterId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _relationshipStatesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProactivePlansTable, List<ProactivePlan>>
  _proactivePlansRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.proactivePlans,
    aliasName: 'characters__id__proactive_plans__character_id',
  );

  $$ProactivePlansTableProcessedTableManager get proactivePlansRefs {
    final manager = $$ProactivePlansTableTableManager(
      $_db,
      $_db.proactivePlans,
    ).filter((f) => f.characterId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_proactivePlansRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$InnerThoughtsTable, List<InnerThought>>
  _innerThoughtsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.innerThoughts,
    aliasName: 'characters__id__inner_thoughts__character_id',
  );

  $$InnerThoughtsTableProcessedTableManager get innerThoughtsRefs {
    final manager = $$InnerThoughtsTableTableManager(
      $_db,
      $_db.innerThoughts,
    ).filter((f) => f.characterId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_innerThoughtsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EmbeddingEntriesTable, List<EmbeddingEntry>>
  _embeddingEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.embeddingEntries,
    aliasName: 'characters__id__embedding_entries__character_id',
  );

  $$EmbeddingEntriesTableProcessedTableManager get embeddingEntriesRefs {
    final manager = $$EmbeddingEntriesTableTableManager(
      $_db,
      $_db.embeddingEntries,
    ).filter((f) => f.characterId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _embeddingEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SemanticHitsTable, List<SemanticHit>>
  _semanticHitsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.semanticHits,
    aliasName: 'characters__id__semantic_hits__character_id',
  );

  $$SemanticHitsTableProcessedTableManager get semanticHitsRefs {
    final manager = $$SemanticHitsTableTableManager(
      $_db,
      $_db.semanticHits,
    ).filter((f) => f.characterId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_semanticHitsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$LorebookEntriesTable, List<LorebookEntry>>
  _lorebookEntriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.lorebookEntries,
    aliasName: 'characters__id__lorebook_entries__character_id',
  );

  $$LorebookEntriesTableProcessedTableManager get lorebookEntriesRefs {
    final manager = $$LorebookEntriesTableTableManager(
      $_db,
      $_db.lorebookEntries,
    ).filter((f) => f.characterId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _lorebookEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CharactersTableFilterComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personality => $composableBuilder(
    column: $table.personality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scenario => $composableBuilder(
    column: $table.scenario,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstMes => $composableBuilder(
    column: $table.firstMes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mesExample => $composableBuilder(
    column: $table.mesExample,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get postHistoryInstructions => $composableBuilder(
    column: $table.postHistoryInstructions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get alternateGreetings => $composableBuilder(
    column: $table.alternateGreetings,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String> get tags =>
      $composableBuilder(
        column: $table.tags,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get creator => $composableBuilder(
    column: $table.creator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, dynamic>,
    Map<String, dynamic>,
    String
  >
  get creatorNotes => $composableBuilder(
    column: $table.creatorNotes,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, dynamic>,
    Map<String, dynamic>,
    String
  >
  get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    List<Map<String, String>>,
    List<Map<String, String>>,
    String
  >
  get presetDialogues => $composableBuilder(
    column: $table.presetDialogues,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get promptMode => $composableBuilder(
    column: $table.promptMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expertPrompt => $composableBuilder(
    column: $table.expertPrompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> conversationsRefs(
    Expression<bool> Function($$ConversationsTableFilterComposer f) f,
  ) {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> memoryEntriesRefs(
    Expression<bool> Function($$MemoryEntriesTableFilterComposer f) f,
  ) {
    final $$MemoryEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memoryEntries,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MemoryEntriesTableFilterComposer(
            $db: $db,
            $table: $db.memoryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> personaRevisionsRefs(
    Expression<bool> Function($$PersonaRevisionsTableFilterComposer f) f,
  ) {
    final $$PersonaRevisionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.personaRevisions,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonaRevisionsTableFilterComposer(
            $db: $db,
            $table: $db.personaRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> relationshipStatesRefs(
    Expression<bool> Function($$RelationshipStatesTableFilterComposer f) f,
  ) {
    final $$RelationshipStatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.relationshipStates,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RelationshipStatesTableFilterComposer(
            $db: $db,
            $table: $db.relationshipStates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> proactivePlansRefs(
    Expression<bool> Function($$ProactivePlansTableFilterComposer f) f,
  ) {
    final $$ProactivePlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.proactivePlans,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProactivePlansTableFilterComposer(
            $db: $db,
            $table: $db.proactivePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> innerThoughtsRefs(
    Expression<bool> Function($$InnerThoughtsTableFilterComposer f) f,
  ) {
    final $$InnerThoughtsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.innerThoughts,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InnerThoughtsTableFilterComposer(
            $db: $db,
            $table: $db.innerThoughts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> embeddingEntriesRefs(
    Expression<bool> Function($$EmbeddingEntriesTableFilterComposer f) f,
  ) {
    final $$EmbeddingEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.embeddingEntries,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmbeddingEntriesTableFilterComposer(
            $db: $db,
            $table: $db.embeddingEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> semanticHitsRefs(
    Expression<bool> Function($$SemanticHitsTableFilterComposer f) f,
  ) {
    final $$SemanticHitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.semanticHits,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SemanticHitsTableFilterComposer(
            $db: $db,
            $table: $db.semanticHits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> lorebookEntriesRefs(
    Expression<bool> Function($$LorebookEntriesTableFilterComposer f) f,
  ) {
    final $$LorebookEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.lorebookEntries,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LorebookEntriesTableFilterComposer(
            $db: $db,
            $table: $db.lorebookEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CharactersTableOrderingComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personality => $composableBuilder(
    column: $table.personality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scenario => $composableBuilder(
    column: $table.scenario,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstMes => $composableBuilder(
    column: $table.firstMes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mesExample => $composableBuilder(
    column: $table.mesExample,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get postHistoryInstructions => $composableBuilder(
    column: $table.postHistoryInstructions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alternateGreetings => $composableBuilder(
    column: $table.alternateGreetings,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creator => $composableBuilder(
    column: $table.creator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creatorNotes => $composableBuilder(
    column: $table.creatorNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatar => $composableBuilder(
    column: $table.avatar,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get presetDialogues => $composableBuilder(
    column: $table.presetDialogues,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptMode => $composableBuilder(
    column: $table.promptMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expertPrompt => $composableBuilder(
    column: $table.expertPrompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CharactersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get personality => $composableBuilder(
    column: $table.personality,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scenario =>
      $composableBuilder(column: $table.scenario, builder: (column) => column);

  GeneratedColumn<String> get firstMes =>
      $composableBuilder(column: $table.firstMes, builder: (column) => column);

  GeneratedColumn<String> get mesExample => $composableBuilder(
    column: $table.mesExample,
    builder: (column) => column,
  );

  GeneratedColumn<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get postHistoryInstructions => $composableBuilder(
    column: $table.postHistoryInstructions,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String>
  get alternateGreetings => $composableBuilder(
    column: $table.alternateGreetings,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get creator =>
      $composableBuilder(column: $table.creator, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
  get creatorNotes => $composableBuilder(
    column: $table.creatorNotes,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
  get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<Map<String, String>>, String>
  get presetDialogues => $composableBuilder(
    column: $table.presetDialogues,
    builder: (column) => column,
  );

  GeneratedColumn<String> get promptMode => $composableBuilder(
    column: $table.promptMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get expertPrompt => $composableBuilder(
    column: $table.expertPrompt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> conversationsRefs<T extends Object>(
    Expression<T> Function($$ConversationsTableAnnotationComposer a) f,
  ) {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> memoryEntriesRefs<T extends Object>(
    Expression<T> Function($$MemoryEntriesTableAnnotationComposer a) f,
  ) {
    final $$MemoryEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.memoryEntries,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MemoryEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.memoryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> personaRevisionsRefs<T extends Object>(
    Expression<T> Function($$PersonaRevisionsTableAnnotationComposer a) f,
  ) {
    final $$PersonaRevisionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.personaRevisions,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonaRevisionsTableAnnotationComposer(
            $db: $db,
            $table: $db.personaRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> relationshipStatesRefs<T extends Object>(
    Expression<T> Function($$RelationshipStatesTableAnnotationComposer a) f,
  ) {
    final $$RelationshipStatesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.relationshipStates,
          getReferencedColumn: (t) => t.characterId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$RelationshipStatesTableAnnotationComposer(
                $db: $db,
                $table: $db.relationshipStates,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> proactivePlansRefs<T extends Object>(
    Expression<T> Function($$ProactivePlansTableAnnotationComposer a) f,
  ) {
    final $$ProactivePlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.proactivePlans,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProactivePlansTableAnnotationComposer(
            $db: $db,
            $table: $db.proactivePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> innerThoughtsRefs<T extends Object>(
    Expression<T> Function($$InnerThoughtsTableAnnotationComposer a) f,
  ) {
    final $$InnerThoughtsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.innerThoughts,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InnerThoughtsTableAnnotationComposer(
            $db: $db,
            $table: $db.innerThoughts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> embeddingEntriesRefs<T extends Object>(
    Expression<T> Function($$EmbeddingEntriesTableAnnotationComposer a) f,
  ) {
    final $$EmbeddingEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.embeddingEntries,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EmbeddingEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.embeddingEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> semanticHitsRefs<T extends Object>(
    Expression<T> Function($$SemanticHitsTableAnnotationComposer a) f,
  ) {
    final $$SemanticHitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.semanticHits,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SemanticHitsTableAnnotationComposer(
            $db: $db,
            $table: $db.semanticHits,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> lorebookEntriesRefs<T extends Object>(
    Expression<T> Function($$LorebookEntriesTableAnnotationComposer a) f,
  ) {
    final $$LorebookEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.lorebookEntries,
      getReferencedColumn: (t) => t.characterId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LorebookEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.lorebookEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CharactersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CharactersTable,
          Character,
          $$CharactersTableFilterComposer,
          $$CharactersTableOrderingComposer,
          $$CharactersTableAnnotationComposer,
          $$CharactersTableCreateCompanionBuilder,
          $$CharactersTableUpdateCompanionBuilder,
          (Character, $$CharactersTableReferences),
          Character,
          PrefetchHooks Function({
            bool conversationsRefs,
            bool memoryEntriesRefs,
            bool personaRevisionsRefs,
            bool relationshipStatesRefs,
            bool proactivePlansRefs,
            bool innerThoughtsRefs,
            bool embeddingEntriesRefs,
            bool semanticHitsRefs,
            bool lorebookEntriesRefs,
          })
        > {
  $$CharactersTableTableManager(_$AppDatabase db, $CharactersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharactersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharactersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CharactersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> personality = const Value.absent(),
                Value<String> scenario = const Value.absent(),
                Value<String> firstMes = const Value.absent(),
                Value<String> mesExample = const Value.absent(),
                Value<String> systemPrompt = const Value.absent(),
                Value<String> postHistoryInstructions = const Value.absent(),
                Value<List<String>> alternateGreetings = const Value.absent(),
                Value<List<String>> tags = const Value.absent(),
                Value<String> creator = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<Map<String, dynamic>> creatorNotes = const Value.absent(),
                Value<Map<String, dynamic>> extensions = const Value.absent(),
                Value<String?> avatar = const Value.absent(),
                Value<double> temperature = const Value.absent(),
                Value<List<Map<String, String>>> presetDialogues =
                    const Value.absent(),
                Value<String> promptMode = const Value.absent(),
                Value<String> expertPrompt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CharactersCompanion(
                id: id,
                name: name,
                description: description,
                personality: personality,
                scenario: scenario,
                firstMes: firstMes,
                mesExample: mesExample,
                systemPrompt: systemPrompt,
                postHistoryInstructions: postHistoryInstructions,
                alternateGreetings: alternateGreetings,
                tags: tags,
                creator: creator,
                version: version,
                creatorNotes: creatorNotes,
                extensions: extensions,
                avatar: avatar,
                temperature: temperature,
                presetDialogues: presetDialogues,
                promptMode: promptMode,
                expertPrompt: expertPrompt,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String> description = const Value.absent(),
                Value<String> personality = const Value.absent(),
                Value<String> scenario = const Value.absent(),
                Value<String> firstMes = const Value.absent(),
                Value<String> mesExample = const Value.absent(),
                Value<String> systemPrompt = const Value.absent(),
                Value<String> postHistoryInstructions = const Value.absent(),
                Value<List<String>> alternateGreetings = const Value.absent(),
                Value<List<String>> tags = const Value.absent(),
                Value<String> creator = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<Map<String, dynamic>> creatorNotes = const Value.absent(),
                Value<Map<String, dynamic>> extensions = const Value.absent(),
                Value<String?> avatar = const Value.absent(),
                Value<double> temperature = const Value.absent(),
                Value<List<Map<String, String>>> presetDialogues =
                    const Value.absent(),
                Value<String> promptMode = const Value.absent(),
                Value<String> expertPrompt = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => CharactersCompanion.insert(
                id: id,
                name: name,
                description: description,
                personality: personality,
                scenario: scenario,
                firstMes: firstMes,
                mesExample: mesExample,
                systemPrompt: systemPrompt,
                postHistoryInstructions: postHistoryInstructions,
                alternateGreetings: alternateGreetings,
                tags: tags,
                creator: creator,
                version: version,
                creatorNotes: creatorNotes,
                extensions: extensions,
                avatar: avatar,
                temperature: temperature,
                presetDialogues: presetDialogues,
                promptMode: promptMode,
                expertPrompt: expertPrompt,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CharactersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                conversationsRefs = false,
                memoryEntriesRefs = false,
                personaRevisionsRefs = false,
                relationshipStatesRefs = false,
                proactivePlansRefs = false,
                innerThoughtsRefs = false,
                embeddingEntriesRefs = false,
                semanticHitsRefs = false,
                lorebookEntriesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (conversationsRefs) db.conversations,
                    if (memoryEntriesRefs) db.memoryEntries,
                    if (personaRevisionsRefs) db.personaRevisions,
                    if (relationshipStatesRefs) db.relationshipStates,
                    if (proactivePlansRefs) db.proactivePlans,
                    if (innerThoughtsRefs) db.innerThoughts,
                    if (embeddingEntriesRefs) db.embeddingEntries,
                    if (semanticHitsRefs) db.semanticHits,
                    if (lorebookEntriesRefs) db.lorebookEntries,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (conversationsRefs)
                        await $_getPrefetchedData<
                          Character,
                          $CharactersTable,
                          Conversation
                        >(
                          currentTable: table,
                          referencedTable: $$CharactersTableReferences
                              ._conversationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CharactersTableReferences(
                                db,
                                table,
                                p0,
                              ).conversationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.characterId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (memoryEntriesRefs)
                        await $_getPrefetchedData<
                          Character,
                          $CharactersTable,
                          MemoryEntry
                        >(
                          currentTable: table,
                          referencedTable: $$CharactersTableReferences
                              ._memoryEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CharactersTableReferences(
                                db,
                                table,
                                p0,
                              ).memoryEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.characterId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (personaRevisionsRefs)
                        await $_getPrefetchedData<
                          Character,
                          $CharactersTable,
                          PersonaRevision
                        >(
                          currentTable: table,
                          referencedTable: $$CharactersTableReferences
                              ._personaRevisionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CharactersTableReferences(
                                db,
                                table,
                                p0,
                              ).personaRevisionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.characterId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (relationshipStatesRefs)
                        await $_getPrefetchedData<
                          Character,
                          $CharactersTable,
                          RelationshipState
                        >(
                          currentTable: table,
                          referencedTable: $$CharactersTableReferences
                              ._relationshipStatesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CharactersTableReferences(
                                db,
                                table,
                                p0,
                              ).relationshipStatesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.characterId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (proactivePlansRefs)
                        await $_getPrefetchedData<
                          Character,
                          $CharactersTable,
                          ProactivePlan
                        >(
                          currentTable: table,
                          referencedTable: $$CharactersTableReferences
                              ._proactivePlansRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CharactersTableReferences(
                                db,
                                table,
                                p0,
                              ).proactivePlansRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.characterId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (innerThoughtsRefs)
                        await $_getPrefetchedData<
                          Character,
                          $CharactersTable,
                          InnerThought
                        >(
                          currentTable: table,
                          referencedTable: $$CharactersTableReferences
                              ._innerThoughtsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CharactersTableReferences(
                                db,
                                table,
                                p0,
                              ).innerThoughtsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.characterId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (embeddingEntriesRefs)
                        await $_getPrefetchedData<
                          Character,
                          $CharactersTable,
                          EmbeddingEntry
                        >(
                          currentTable: table,
                          referencedTable: $$CharactersTableReferences
                              ._embeddingEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CharactersTableReferences(
                                db,
                                table,
                                p0,
                              ).embeddingEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.characterId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (semanticHitsRefs)
                        await $_getPrefetchedData<
                          Character,
                          $CharactersTable,
                          SemanticHit
                        >(
                          currentTable: table,
                          referencedTable: $$CharactersTableReferences
                              ._semanticHitsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CharactersTableReferences(
                                db,
                                table,
                                p0,
                              ).semanticHitsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.characterId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (lorebookEntriesRefs)
                        await $_getPrefetchedData<
                          Character,
                          $CharactersTable,
                          LorebookEntry
                        >(
                          currentTable: table,
                          referencedTable: $$CharactersTableReferences
                              ._lorebookEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CharactersTableReferences(
                                db,
                                table,
                                p0,
                              ).lorebookEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.characterId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CharactersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CharactersTable,
      Character,
      $$CharactersTableFilterComposer,
      $$CharactersTableOrderingComposer,
      $$CharactersTableAnnotationComposer,
      $$CharactersTableCreateCompanionBuilder,
      $$CharactersTableUpdateCompanionBuilder,
      (Character, $$CharactersTableReferences),
      Character,
      PrefetchHooks Function({
        bool conversationsRefs,
        bool memoryEntriesRefs,
        bool personaRevisionsRefs,
        bool relationshipStatesRefs,
        bool proactivePlansRefs,
        bool innerThoughtsRefs,
        bool embeddingEntriesRefs,
        bool semanticHitsRefs,
        bool lorebookEntriesRefs,
      })
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      Value<int> id,
      required int characterId,
      Value<String> title,
      Value<String> modelProvider,
      Value<String> modelName,
      Value<String?> presetDialogue,
      Value<double?> topP,
      Value<double?> presencePenalty,
      Value<double?> frequencyPenalty,
      Value<int?> maxTokens,
      Value<int?> parentConversationId,
      Value<int?> branchFromMessageId,
      Value<String?> branchTitle,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<int> id,
      Value<int> characterId,
      Value<String> title,
      Value<String> modelProvider,
      Value<String> modelName,
      Value<String?> presetDialogue,
      Value<double?> topP,
      Value<double?> presencePenalty,
      Value<double?> frequencyPenalty,
      Value<int?> maxTokens,
      Value<int?> parentConversationId,
      Value<int?> branchFromMessageId,
      Value<String?> branchTitle,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$ConversationsTableReferences
    extends BaseReferences<_$AppDatabase, $ConversationsTable, Conversation> {
  $$ConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CharactersTable _characterIdTable(_$AppDatabase db) =>
      db.characters.createAlias('conversations__character_id__characters__id');

  $$CharactersTableProcessedTableManager get characterId {
    final $_column = $_itemColumn<int>('character_id')!;

    final manager = $$CharactersTableTableManager(
      $_db,
      $_db.characters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_characterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.messages,
    aliasName: 'conversations__id__messages__conversation_id',
  );

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProactivePlansTable, List<ProactivePlan>>
  _proactivePlansRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.proactivePlans,
    aliasName: 'conversations__id__proactive_plans__conversation_id',
  );

  $$ProactivePlansTableProcessedTableManager get proactivePlansRefs {
    final manager = $$ProactivePlansTableTableManager(
      $_db,
      $_db.proactivePlans,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_proactivePlansRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelProvider => $composableBuilder(
    column: $table.modelProvider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelName => $composableBuilder(
    column: $table.modelName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get presetDialogue => $composableBuilder(
    column: $table.presetDialogue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get topP => $composableBuilder(
    column: $table.topP,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get presencePenalty => $composableBuilder(
    column: $table.presencePenalty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get frequencyPenalty => $composableBuilder(
    column: $table.frequencyPenalty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxTokens => $composableBuilder(
    column: $table.maxTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parentConversationId => $composableBuilder(
    column: $table.parentConversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get branchFromMessageId => $composableBuilder(
    column: $table.branchFromMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchTitle => $composableBuilder(
    column: $table.branchTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CharactersTableFilterComposer get characterId {
    final $$CharactersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableFilterComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> messagesRefs(
    Expression<bool> Function($$MessagesTableFilterComposer f) f,
  ) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> proactivePlansRefs(
    Expression<bool> Function($$ProactivePlansTableFilterComposer f) f,
  ) {
    final $$ProactivePlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.proactivePlans,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProactivePlansTableFilterComposer(
            $db: $db,
            $table: $db.proactivePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelProvider => $composableBuilder(
    column: $table.modelProvider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelName => $composableBuilder(
    column: $table.modelName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get presetDialogue => $composableBuilder(
    column: $table.presetDialogue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get topP => $composableBuilder(
    column: $table.topP,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get presencePenalty => $composableBuilder(
    column: $table.presencePenalty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get frequencyPenalty => $composableBuilder(
    column: $table.frequencyPenalty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxTokens => $composableBuilder(
    column: $table.maxTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parentConversationId => $composableBuilder(
    column: $table.parentConversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get branchFromMessageId => $composableBuilder(
    column: $table.branchFromMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchTitle => $composableBuilder(
    column: $table.branchTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharactersTableOrderingComposer get characterId {
    final $$CharactersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableOrderingComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get modelProvider => $composableBuilder(
    column: $table.modelProvider,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelName =>
      $composableBuilder(column: $table.modelName, builder: (column) => column);

  GeneratedColumn<String> get presetDialogue => $composableBuilder(
    column: $table.presetDialogue,
    builder: (column) => column,
  );

  GeneratedColumn<double> get topP =>
      $composableBuilder(column: $table.topP, builder: (column) => column);

  GeneratedColumn<double> get presencePenalty => $composableBuilder(
    column: $table.presencePenalty,
    builder: (column) => column,
  );

  GeneratedColumn<double> get frequencyPenalty => $composableBuilder(
    column: $table.frequencyPenalty,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxTokens =>
      $composableBuilder(column: $table.maxTokens, builder: (column) => column);

  GeneratedColumn<int> get parentConversationId => $composableBuilder(
    column: $table.parentConversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get branchFromMessageId => $composableBuilder(
    column: $table.branchFromMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchTitle => $composableBuilder(
    column: $table.branchTitle,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$CharactersTableAnnotationComposer get characterId {
    final $$CharactersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableAnnotationComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> messagesRefs<T extends Object>(
    Expression<T> Function($$MessagesTableAnnotationComposer a) f,
  ) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> proactivePlansRefs<T extends Object>(
    Expression<T> Function($$ProactivePlansTableAnnotationComposer a) f,
  ) {
    final $$ProactivePlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.proactivePlans,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProactivePlansTableAnnotationComposer(
            $db: $db,
            $table: $db.proactivePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (Conversation, $$ConversationsTableReferences),
          Conversation,
          PrefetchHooks Function({
            bool characterId,
            bool messagesRefs,
            bool proactivePlansRefs,
          })
        > {
  $$ConversationsTableTableManager(_$AppDatabase db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> characterId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> modelProvider = const Value.absent(),
                Value<String> modelName = const Value.absent(),
                Value<String?> presetDialogue = const Value.absent(),
                Value<double?> topP = const Value.absent(),
                Value<double?> presencePenalty = const Value.absent(),
                Value<double?> frequencyPenalty = const Value.absent(),
                Value<int?> maxTokens = const Value.absent(),
                Value<int?> parentConversationId = const Value.absent(),
                Value<int?> branchFromMessageId = const Value.absent(),
                Value<String?> branchTitle = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                characterId: characterId,
                title: title,
                modelProvider: modelProvider,
                modelName: modelName,
                presetDialogue: presetDialogue,
                topP: topP,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty,
                maxTokens: maxTokens,
                parentConversationId: parentConversationId,
                branchFromMessageId: branchFromMessageId,
                branchTitle: branchTitle,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int characterId,
                Value<String> title = const Value.absent(),
                Value<String> modelProvider = const Value.absent(),
                Value<String> modelName = const Value.absent(),
                Value<String?> presetDialogue = const Value.absent(),
                Value<double?> topP = const Value.absent(),
                Value<double?> presencePenalty = const Value.absent(),
                Value<double?> frequencyPenalty = const Value.absent(),
                Value<int?> maxTokens = const Value.absent(),
                Value<int?> parentConversationId = const Value.absent(),
                Value<int?> branchFromMessageId = const Value.absent(),
                Value<String?> branchTitle = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => ConversationsCompanion.insert(
                id: id,
                characterId: characterId,
                title: title,
                modelProvider: modelProvider,
                modelName: modelName,
                presetDialogue: presetDialogue,
                topP: topP,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty,
                maxTokens: maxTokens,
                parentConversationId: parentConversationId,
                branchFromMessageId: branchFromMessageId,
                branchTitle: branchTitle,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                characterId = false,
                messagesRefs = false,
                proactivePlansRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (messagesRefs) db.messages,
                    if (proactivePlansRefs) db.proactivePlans,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (characterId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.characterId,
                            referencedTable: $$ConversationsTableReferences
                                ._characterIdTable(db),
                            referencedColumn: $$ConversationsTableReferences
                                ._characterIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (messagesRefs)
                        await $_getPrefetchedData<
                          Conversation,
                          $ConversationsTable,
                          Message
                        >(
                          currentTable: table,
                          referencedTable: $$ConversationsTableReferences
                              ._messagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConversationsTableReferences(
                                db,
                                table,
                                p0,
                              ).messagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (proactivePlansRefs)
                        await $_getPrefetchedData<
                          Conversation,
                          $ConversationsTable,
                          ProactivePlan
                        >(
                          currentTable: table,
                          referencedTable: $$ConversationsTableReferences
                              ._proactivePlansRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ConversationsTableReferences(
                                db,
                                table,
                                p0,
                              ).proactivePlansRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.conversationId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (Conversation, $$ConversationsTableReferences),
      Conversation,
      PrefetchHooks Function({
        bool characterId,
        bool messagesRefs,
        bool proactivePlansRefs,
      })
    >;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  required int conversationId,
  required Role role,
  required String content,
  Value<int> activeSwipeIndex,
  required DateTime createdAt,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  Value<int> conversationId,
  Value<Role> role,
  Value<String> content,
  Value<int> activeSwipeIndex,
  Value<DateTime> createdAt,
});

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConversationsTable _conversationIdTable(_$AppDatabase db) => db
      .conversations
      .createAlias('messages__conversation_id__conversations__id');

  $$ConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<int>('conversation_id')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ProactivePlansTable, List<ProactivePlan>>
  _proactivePlansRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.proactivePlans,
    aliasName: 'messages__id__proactive_plans__message_id',
  );

  $$ProactivePlansTableProcessedTableManager get proactivePlansRefs {
    final manager = $$ProactivePlansTableTableManager(
      $_db,
      $_db.proactivePlans,
    ).filter((f) => f.messageId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_proactivePlansRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$InnerThoughtsTable, List<InnerThought>>
  _innerThoughtsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.innerThoughts,
    aliasName: 'messages__id__inner_thoughts__message_id',
  );

  $$InnerThoughtsTableProcessedTableManager get innerThoughtsRefs {
    final manager = $$InnerThoughtsTableTableManager(
      $_db,
      $_db.innerThoughts,
    ).filter((f) => f.messageId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_innerThoughtsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MessageSwipesTable, List<MessageSwipe>>
  _messageSwipesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.messageSwipes,
    aliasName: 'messages__id__message_swipes__message_id',
  );

  $$MessageSwipesTableProcessedTableManager get messageSwipesRefs {
    final manager = $$MessageSwipesTableTableManager(
      $_db,
      $_db.messageSwipes,
    ).filter((f) => f.messageId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_messageSwipesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Role, Role, String> get role =>
      $composableBuilder(
        column: $table.role,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get activeSwipeIndex => $composableBuilder(
    column: $table.activeSwipeIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> proactivePlansRefs(
    Expression<bool> Function($$ProactivePlansTableFilterComposer f) f,
  ) {
    final $$ProactivePlansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.proactivePlans,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProactivePlansTableFilterComposer(
            $db: $db,
            $table: $db.proactivePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> innerThoughtsRefs(
    Expression<bool> Function($$InnerThoughtsTableFilterComposer f) f,
  ) {
    final $$InnerThoughtsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.innerThoughts,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InnerThoughtsTableFilterComposer(
            $db: $db,
            $table: $db.innerThoughts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> messageSwipesRefs(
    Expression<bool> Function($$MessageSwipesTableFilterComposer f) f,
  ) {
    final $$MessageSwipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messageSwipes,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageSwipesTableFilterComposer(
            $db: $db,
            $table: $db.messageSwipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get activeSwipeIndex => $composableBuilder(
    column: $table.activeSwipeIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Role, String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get activeSwipeIndex => $composableBuilder(
    column: $table.activeSwipeIndex,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> proactivePlansRefs<T extends Object>(
    Expression<T> Function($$ProactivePlansTableAnnotationComposer a) f,
  ) {
    final $$ProactivePlansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.proactivePlans,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProactivePlansTableAnnotationComposer(
            $db: $db,
            $table: $db.proactivePlans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> innerThoughtsRefs<T extends Object>(
    Expression<T> Function($$InnerThoughtsTableAnnotationComposer a) f,
  ) {
    final $$InnerThoughtsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.innerThoughts,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InnerThoughtsTableAnnotationComposer(
            $db: $db,
            $table: $db.innerThoughts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> messageSwipesRefs<T extends Object>(
    Expression<T> Function($$MessageSwipesTableAnnotationComposer a) f,
  ) {
    final $$MessageSwipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.messageSwipes,
      getReferencedColumn: (t) => t.messageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessageSwipesTableAnnotationComposer(
            $db: $db,
            $table: $db.messageSwipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, $$MessagesTableReferences),
          Message,
          PrefetchHooks Function({
            bool conversationId,
            bool proactivePlansRefs,
            bool innerThoughtsRefs,
            bool messageSwipesRefs,
          })
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> conversationId = const Value.absent(),
                Value<Role> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> activeSwipeIndex = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                conversationId: conversationId,
                role: role,
                content: content,
                activeSwipeIndex: activeSwipeIndex,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int conversationId,
                required Role role,
                required String content,
                Value<int> activeSwipeIndex = const Value.absent(),
                required DateTime createdAt,
              }) => MessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                role: role,
                content: content,
                activeSwipeIndex: activeSwipeIndex,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                conversationId = false,
                proactivePlansRefs = false,
                innerThoughtsRefs = false,
                messageSwipesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (proactivePlansRefs) db.proactivePlans,
                    if (innerThoughtsRefs) db.innerThoughts,
                    if (messageSwipesRefs) db.messageSwipes,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (conversationId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.conversationId,
                            referencedTable: $$MessagesTableReferences
                                ._conversationIdTable(db),
                            referencedColumn: $$MessagesTableReferences
                                ._conversationIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (proactivePlansRefs)
                        await $_getPrefetchedData<
                          Message,
                          $MessagesTable,
                          ProactivePlan
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._proactivePlansRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).proactivePlansRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (innerThoughtsRefs)
                        await $_getPrefetchedData<
                          Message,
                          $MessagesTable,
                          InnerThought
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._innerThoughtsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).innerThoughtsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (messageSwipesRefs)
                        await $_getPrefetchedData<
                          Message,
                          $MessagesTable,
                          MessageSwipe
                        >(
                          currentTable: table,
                          referencedTable: $$MessagesTableReferences
                              ._messageSwipesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MessagesTableReferences(
                                db,
                                table,
                                p0,
                              ).messageSwipesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.messageId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, $$MessagesTableReferences),
      Message,
      PrefetchHooks Function({
        bool conversationId,
        bool proactivePlansRefs,
        bool innerThoughtsRefs,
        bool messageSwipesRefs,
      })
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  Value<String> value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$MemoryEntriesTableCreateCompanionBuilder =
    MemoryEntriesCompanion Function({
      Value<int> id,
      required int characterId,
      required MemoryKind kind,
      required String content,
      Value<int> importance,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$MemoryEntriesTableUpdateCompanionBuilder =
    MemoryEntriesCompanion Function({
      Value<int> id,
      Value<int> characterId,
      Value<MemoryKind> kind,
      Value<String> content,
      Value<int> importance,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$MemoryEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $MemoryEntriesTable, MemoryEntry> {
  $$MemoryEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CharactersTable _characterIdTable(_$AppDatabase db) =>
      db.characters.createAlias('memory_entries__character_id__characters__id');

  $$CharactersTableProcessedTableManager get characterId {
    final $_column = $_itemColumn<int>('character_id')!;

    final manager = $$CharactersTableTableManager(
      $_db,
      $_db.characters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_characterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MemoryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $MemoryEntriesTable> {
  $$MemoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<MemoryKind, MemoryKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importance => $composableBuilder(
    column: $table.importance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CharactersTableFilterComposer get characterId {
    final $$CharactersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableFilterComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MemoryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MemoryEntriesTable> {
  $$MemoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importance => $composableBuilder(
    column: $table.importance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharactersTableOrderingComposer get characterId {
    final $$CharactersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableOrderingComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MemoryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MemoryEntriesTable> {
  $$MemoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<MemoryKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get importance => $composableBuilder(
    column: $table.importance,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$CharactersTableAnnotationComposer get characterId {
    final $$CharactersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableAnnotationComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MemoryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MemoryEntriesTable,
          MemoryEntry,
          $$MemoryEntriesTableFilterComposer,
          $$MemoryEntriesTableOrderingComposer,
          $$MemoryEntriesTableAnnotationComposer,
          $$MemoryEntriesTableCreateCompanionBuilder,
          $$MemoryEntriesTableUpdateCompanionBuilder,
          (MemoryEntry, $$MemoryEntriesTableReferences),
          MemoryEntry,
          PrefetchHooks Function({bool characterId})
        > {
  $$MemoryEntriesTableTableManager(_$AppDatabase db, $MemoryEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MemoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MemoryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MemoryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> characterId = const Value.absent(),
                Value<MemoryKind> kind = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> importance = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => MemoryEntriesCompanion(
                id: id,
                characterId: characterId,
                kind: kind,
                content: content,
                importance: importance,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int characterId,
                required MemoryKind kind,
                required String content,
                Value<int> importance = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => MemoryEntriesCompanion.insert(
                id: id,
                characterId: characterId,
                kind: kind,
                content: content,
                importance: importance,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MemoryEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({characterId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (characterId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.characterId,
                        referencedTable: $$MemoryEntriesTableReferences
                            ._characterIdTable(db),
                        referencedColumn: $$MemoryEntriesTableReferences
                            ._characterIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MemoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MemoryEntriesTable,
      MemoryEntry,
      $$MemoryEntriesTableFilterComposer,
      $$MemoryEntriesTableOrderingComposer,
      $$MemoryEntriesTableAnnotationComposer,
      $$MemoryEntriesTableCreateCompanionBuilder,
      $$MemoryEntriesTableUpdateCompanionBuilder,
      (MemoryEntry, $$MemoryEntriesTableReferences),
      MemoryEntry,
      PrefetchHooks Function({bool characterId})
    >;
typedef $$PersonaRevisionsTableCreateCompanionBuilder =
    PersonaRevisionsCompanion Function({
      Value<int> id,
      required int characterId,
      required String personalitySnapshot,
      Value<String> reason,
      required DateTime createdAt,
    });
typedef $$PersonaRevisionsTableUpdateCompanionBuilder =
    PersonaRevisionsCompanion Function({
      Value<int> id,
      Value<int> characterId,
      Value<String> personalitySnapshot,
      Value<String> reason,
      Value<DateTime> createdAt,
    });

final class $$PersonaRevisionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $PersonaRevisionsTable, PersonaRevision> {
  $$PersonaRevisionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CharactersTable _characterIdTable(_$AppDatabase db) => db.characters
      .createAlias('persona_revisions__character_id__characters__id');

  $$CharactersTableProcessedTableManager get characterId {
    final $_column = $_itemColumn<int>('character_id')!;

    final manager = $$CharactersTableTableManager(
      $_db,
      $_db.characters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_characterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PersonaRevisionsTableFilterComposer
    extends Composer<_$AppDatabase, $PersonaRevisionsTable> {
  $$PersonaRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personalitySnapshot => $composableBuilder(
    column: $table.personalitySnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CharactersTableFilterComposer get characterId {
    final $$CharactersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableFilterComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PersonaRevisionsTableOrderingComposer
    extends Composer<_$AppDatabase, $PersonaRevisionsTable> {
  $$PersonaRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personalitySnapshot => $composableBuilder(
    column: $table.personalitySnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharactersTableOrderingComposer get characterId {
    final $$CharactersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableOrderingComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PersonaRevisionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PersonaRevisionsTable> {
  $$PersonaRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get personalitySnapshot => $composableBuilder(
    column: $table.personalitySnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CharactersTableAnnotationComposer get characterId {
    final $$CharactersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableAnnotationComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PersonaRevisionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PersonaRevisionsTable,
          PersonaRevision,
          $$PersonaRevisionsTableFilterComposer,
          $$PersonaRevisionsTableOrderingComposer,
          $$PersonaRevisionsTableAnnotationComposer,
          $$PersonaRevisionsTableCreateCompanionBuilder,
          $$PersonaRevisionsTableUpdateCompanionBuilder,
          (PersonaRevision, $$PersonaRevisionsTableReferences),
          PersonaRevision,
          PrefetchHooks Function({bool characterId})
        > {
  $$PersonaRevisionsTableTableManager(
    _$AppDatabase db,
    $PersonaRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonaRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonaRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonaRevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> characterId = const Value.absent(),
                Value<String> personalitySnapshot = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PersonaRevisionsCompanion(
                id: id,
                characterId: characterId,
                personalitySnapshot: personalitySnapshot,
                reason: reason,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int characterId,
                required String personalitySnapshot,
                Value<String> reason = const Value.absent(),
                required DateTime createdAt,
              }) => PersonaRevisionsCompanion.insert(
                id: id,
                characterId: characterId,
                personalitySnapshot: personalitySnapshot,
                reason: reason,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PersonaRevisionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({characterId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (characterId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.characterId,
                        referencedTable: $$PersonaRevisionsTableReferences
                            ._characterIdTable(db),
                        referencedColumn: $$PersonaRevisionsTableReferences
                            ._characterIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PersonaRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PersonaRevisionsTable,
      PersonaRevision,
      $$PersonaRevisionsTableFilterComposer,
      $$PersonaRevisionsTableOrderingComposer,
      $$PersonaRevisionsTableAnnotationComposer,
      $$PersonaRevisionsTableCreateCompanionBuilder,
      $$PersonaRevisionsTableUpdateCompanionBuilder,
      (PersonaRevision, $$PersonaRevisionsTableReferences),
      PersonaRevision,
      PrefetchHooks Function({bool characterId})
    >;
typedef $$RelationshipStatesTableCreateCompanionBuilder =
    RelationshipStatesCompanion Function({
      Value<int> id,
      required int characterId,
      required RelationshipStage stage,
      Value<int> affinity,
      required DateTime updatedAt,
    });
typedef $$RelationshipStatesTableUpdateCompanionBuilder =
    RelationshipStatesCompanion Function({
      Value<int> id,
      Value<int> characterId,
      Value<RelationshipStage> stage,
      Value<int> affinity,
      Value<DateTime> updatedAt,
    });

final class $$RelationshipStatesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $RelationshipStatesTable,
          RelationshipState
        > {
  $$RelationshipStatesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CharactersTable _characterIdTable(_$AppDatabase db) => db.characters
      .createAlias('relationship_states__character_id__characters__id');

  $$CharactersTableProcessedTableManager get characterId {
    final $_column = $_itemColumn<int>('character_id')!;

    final manager = $$CharactersTableTableManager(
      $_db,
      $_db.characters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_characterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RelationshipStatesTableFilterComposer
    extends Composer<_$AppDatabase, $RelationshipStatesTable> {
  $$RelationshipStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<RelationshipStage, RelationshipStage, String>
  get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get affinity => $composableBuilder(
    column: $table.affinity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CharactersTableFilterComposer get characterId {
    final $$CharactersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableFilterComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RelationshipStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $RelationshipStatesTable> {
  $$RelationshipStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get affinity => $composableBuilder(
    column: $table.affinity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharactersTableOrderingComposer get characterId {
    final $$CharactersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableOrderingComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RelationshipStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RelationshipStatesTable> {
  $$RelationshipStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<RelationshipStage, String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<int> get affinity =>
      $composableBuilder(column: $table.affinity, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$CharactersTableAnnotationComposer get characterId {
    final $$CharactersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableAnnotationComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RelationshipStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RelationshipStatesTable,
          RelationshipState,
          $$RelationshipStatesTableFilterComposer,
          $$RelationshipStatesTableOrderingComposer,
          $$RelationshipStatesTableAnnotationComposer,
          $$RelationshipStatesTableCreateCompanionBuilder,
          $$RelationshipStatesTableUpdateCompanionBuilder,
          (RelationshipState, $$RelationshipStatesTableReferences),
          RelationshipState,
          PrefetchHooks Function({bool characterId})
        > {
  $$RelationshipStatesTableTableManager(
    _$AppDatabase db,
    $RelationshipStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RelationshipStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RelationshipStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RelationshipStatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> characterId = const Value.absent(),
                Value<RelationshipStage> stage = const Value.absent(),
                Value<int> affinity = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => RelationshipStatesCompanion(
                id: id,
                characterId: characterId,
                stage: stage,
                affinity: affinity,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int characterId,
                required RelationshipStage stage,
                Value<int> affinity = const Value.absent(),
                required DateTime updatedAt,
              }) => RelationshipStatesCompanion.insert(
                id: id,
                characterId: characterId,
                stage: stage,
                affinity: affinity,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RelationshipStatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({characterId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (characterId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.characterId,
                        referencedTable: $$RelationshipStatesTableReferences
                            ._characterIdTable(db),
                        referencedColumn: $$RelationshipStatesTableReferences
                            ._characterIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RelationshipStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RelationshipStatesTable,
      RelationshipState,
      $$RelationshipStatesTableFilterComposer,
      $$RelationshipStatesTableOrderingComposer,
      $$RelationshipStatesTableAnnotationComposer,
      $$RelationshipStatesTableCreateCompanionBuilder,
      $$RelationshipStatesTableUpdateCompanionBuilder,
      (RelationshipState, $$RelationshipStatesTableReferences),
      RelationshipState,
      PrefetchHooks Function({bool characterId})
    >;
typedef $$ProactivePlansTableCreateCompanionBuilder =
    ProactivePlansCompanion Function({
      Value<int> id,
      required int characterId,
      required int conversationId,
      required String content,
      required DateTime scheduledAt,
      Value<DateTime?> sentAt,
      required ProactivePlanStatus status,
      Value<int?> messageId,
    });
typedef $$ProactivePlansTableUpdateCompanionBuilder =
    ProactivePlansCompanion Function({
      Value<int> id,
      Value<int> characterId,
      Value<int> conversationId,
      Value<String> content,
      Value<DateTime> scheduledAt,
      Value<DateTime?> sentAt,
      Value<ProactivePlanStatus> status,
      Value<int?> messageId,
    });

final class $$ProactivePlansTableReferences
    extends BaseReferences<_$AppDatabase, $ProactivePlansTable, ProactivePlan> {
  $$ProactivePlansTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CharactersTable _characterIdTable(_$AppDatabase db) => db.characters
      .createAlias('proactive_plans__character_id__characters__id');

  $$CharactersTableProcessedTableManager get characterId {
    final $_column = $_itemColumn<int>('character_id')!;

    final manager = $$CharactersTableTableManager(
      $_db,
      $_db.characters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_characterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ConversationsTable _conversationIdTable(_$AppDatabase db) => db
      .conversations
      .createAlias('proactive_plans__conversation_id__conversations__id');

  $$ConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<int>('conversation_id')!;

    final manager = $$ConversationsTableTableManager(
      $_db,
      $_db.conversations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MessagesTable _messageIdTable(_$AppDatabase db) =>
      db.messages.createAlias('proactive_plans__message_id__messages__id');

  $$MessagesTableProcessedTableManager? get messageId {
    final $_column = $_itemColumn<int>('message_id');
    if ($_column == null) return null;
    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProactivePlansTableFilterComposer
    extends Composer<_$AppDatabase, $ProactivePlansTable> {
  $$ProactivePlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    ProactivePlanStatus,
    ProactivePlanStatus,
    String
  >
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  $$CharactersTableFilterComposer get characterId {
    final $$CharactersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableFilterComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ConversationsTableFilterComposer get conversationId {
    final $$ConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableFilterComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableFilterComposer get messageId {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProactivePlansTableOrderingComposer
    extends Composer<_$AppDatabase, $ProactivePlansTable> {
  $$ProactivePlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharactersTableOrderingComposer get characterId {
    final $$CharactersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableOrderingComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ConversationsTableOrderingComposer get conversationId {
    final $$ConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableOrderingComposer get messageId {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProactivePlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProactivePlansTable> {
  $$ProactivePlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ProactivePlanStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  $$CharactersTableAnnotationComposer get characterId {
    final $$CharactersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableAnnotationComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ConversationsTableAnnotationComposer get conversationId {
    final $$ConversationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.conversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConversationsTableAnnotationComposer(
            $db: $db,
            $table: $db.conversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableAnnotationComposer get messageId {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProactivePlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProactivePlansTable,
          ProactivePlan,
          $$ProactivePlansTableFilterComposer,
          $$ProactivePlansTableOrderingComposer,
          $$ProactivePlansTableAnnotationComposer,
          $$ProactivePlansTableCreateCompanionBuilder,
          $$ProactivePlansTableUpdateCompanionBuilder,
          (ProactivePlan, $$ProactivePlansTableReferences),
          ProactivePlan,
          PrefetchHooks Function({
            bool characterId,
            bool conversationId,
            bool messageId,
          })
        > {
  $$ProactivePlansTableTableManager(
    _$AppDatabase db,
    $ProactivePlansTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProactivePlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProactivePlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProactivePlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> characterId = const Value.absent(),
                Value<int> conversationId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> scheduledAt = const Value.absent(),
                Value<DateTime?> sentAt = const Value.absent(),
                Value<ProactivePlanStatus> status = const Value.absent(),
                Value<int?> messageId = const Value.absent(),
              }) => ProactivePlansCompanion(
                id: id,
                characterId: characterId,
                conversationId: conversationId,
                content: content,
                scheduledAt: scheduledAt,
                sentAt: sentAt,
                status: status,
                messageId: messageId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int characterId,
                required int conversationId,
                required String content,
                required DateTime scheduledAt,
                Value<DateTime?> sentAt = const Value.absent(),
                required ProactivePlanStatus status,
                Value<int?> messageId = const Value.absent(),
              }) => ProactivePlansCompanion.insert(
                id: id,
                characterId: characterId,
                conversationId: conversationId,
                content: content,
                scheduledAt: scheduledAt,
                sentAt: sentAt,
                status: status,
                messageId: messageId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProactivePlansTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                characterId = false,
                conversationId = false,
                messageId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (characterId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.characterId,
                            referencedTable: $$ProactivePlansTableReferences
                                ._characterIdTable(db),
                            referencedColumn: $$ProactivePlansTableReferences
                                ._characterIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (conversationId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.conversationId,
                            referencedTable: $$ProactivePlansTableReferences
                                ._conversationIdTable(db),
                            referencedColumn: $$ProactivePlansTableReferences
                                ._conversationIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (messageId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.messageId,
                            referencedTable: $$ProactivePlansTableReferences
                                ._messageIdTable(db),
                            referencedColumn: $$ProactivePlansTableReferences
                                ._messageIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$ProactivePlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProactivePlansTable,
      ProactivePlan,
      $$ProactivePlansTableFilterComposer,
      $$ProactivePlansTableOrderingComposer,
      $$ProactivePlansTableAnnotationComposer,
      $$ProactivePlansTableCreateCompanionBuilder,
      $$ProactivePlansTableUpdateCompanionBuilder,
      (ProactivePlan, $$ProactivePlansTableReferences),
      ProactivePlan,
      PrefetchHooks Function({
        bool characterId,
        bool conversationId,
        bool messageId,
      })
    >;
typedef $$InnerThoughtsTableCreateCompanionBuilder =
    InnerThoughtsCompanion Function({
      Value<int> id,
      required int characterId,
      required int messageId,
      required String content,
      required DateTime createdAt,
    });
typedef $$InnerThoughtsTableUpdateCompanionBuilder =
    InnerThoughtsCompanion Function({
      Value<int> id,
      Value<int> characterId,
      Value<int> messageId,
      Value<String> content,
      Value<DateTime> createdAt,
    });

final class $$InnerThoughtsTableReferences
    extends BaseReferences<_$AppDatabase, $InnerThoughtsTable, InnerThought> {
  $$InnerThoughtsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CharactersTable _characterIdTable(_$AppDatabase db) =>
      db.characters.createAlias('inner_thoughts__character_id__characters__id');

  $$CharactersTableProcessedTableManager get characterId {
    final $_column = $_itemColumn<int>('character_id')!;

    final manager = $$CharactersTableTableManager(
      $_db,
      $_db.characters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_characterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MessagesTable _messageIdTable(_$AppDatabase db) =>
      db.messages.createAlias('inner_thoughts__message_id__messages__id');

  $$MessagesTableProcessedTableManager get messageId {
    final $_column = $_itemColumn<int>('message_id')!;

    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$InnerThoughtsTableFilterComposer
    extends Composer<_$AppDatabase, $InnerThoughtsTable> {
  $$InnerThoughtsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CharactersTableFilterComposer get characterId {
    final $$CharactersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableFilterComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableFilterComposer get messageId {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InnerThoughtsTableOrderingComposer
    extends Composer<_$AppDatabase, $InnerThoughtsTable> {
  $$InnerThoughtsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharactersTableOrderingComposer get characterId {
    final $$CharactersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableOrderingComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableOrderingComposer get messageId {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InnerThoughtsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InnerThoughtsTable> {
  $$InnerThoughtsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CharactersTableAnnotationComposer get characterId {
    final $$CharactersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableAnnotationComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MessagesTableAnnotationComposer get messageId {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InnerThoughtsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InnerThoughtsTable,
          InnerThought,
          $$InnerThoughtsTableFilterComposer,
          $$InnerThoughtsTableOrderingComposer,
          $$InnerThoughtsTableAnnotationComposer,
          $$InnerThoughtsTableCreateCompanionBuilder,
          $$InnerThoughtsTableUpdateCompanionBuilder,
          (InnerThought, $$InnerThoughtsTableReferences),
          InnerThought,
          PrefetchHooks Function({bool characterId, bool messageId})
        > {
  $$InnerThoughtsTableTableManager(_$AppDatabase db, $InnerThoughtsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InnerThoughtsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InnerThoughtsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InnerThoughtsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> characterId = const Value.absent(),
                Value<int> messageId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => InnerThoughtsCompanion(
                id: id,
                characterId: characterId,
                messageId: messageId,
                content: content,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int characterId,
                required int messageId,
                required String content,
                required DateTime createdAt,
              }) => InnerThoughtsCompanion.insert(
                id: id,
                characterId: characterId,
                messageId: messageId,
                content: content,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$InnerThoughtsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({characterId = false, messageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (characterId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.characterId,
                        referencedTable: $$InnerThoughtsTableReferences
                            ._characterIdTable(db),
                        referencedColumn: $$InnerThoughtsTableReferences
                            ._characterIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (messageId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.messageId,
                        referencedTable: $$InnerThoughtsTableReferences
                            ._messageIdTable(db),
                        referencedColumn: $$InnerThoughtsTableReferences
                            ._messageIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$InnerThoughtsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InnerThoughtsTable,
      InnerThought,
      $$InnerThoughtsTableFilterComposer,
      $$InnerThoughtsTableOrderingComposer,
      $$InnerThoughtsTableAnnotationComposer,
      $$InnerThoughtsTableCreateCompanionBuilder,
      $$InnerThoughtsTableUpdateCompanionBuilder,
      (InnerThought, $$InnerThoughtsTableReferences),
      InnerThought,
      PrefetchHooks Function({bool characterId, bool messageId})
    >;
typedef $$EmbeddingEntriesTableCreateCompanionBuilder =
    EmbeddingEntriesCompanion Function({
      Value<int> id,
      required int characterId,
      required int entryId,
      required String contentSnapshot,
      required Uint8List vector,
      required String model,
      required int dims,
      required String contentHash,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$EmbeddingEntriesTableUpdateCompanionBuilder =
    EmbeddingEntriesCompanion Function({
      Value<int> id,
      Value<int> characterId,
      Value<int> entryId,
      Value<String> contentSnapshot,
      Value<Uint8List> vector,
      Value<String> model,
      Value<int> dims,
      Value<String> contentHash,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$EmbeddingEntriesTableReferences
    extends
        BaseReferences<_$AppDatabase, $EmbeddingEntriesTable, EmbeddingEntry> {
  $$EmbeddingEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CharactersTable _characterIdTable(_$AppDatabase db) => db.characters
      .createAlias('embedding_entries__character_id__characters__id');

  $$CharactersTableProcessedTableManager get characterId {
    final $_column = $_itemColumn<int>('character_id')!;

    final manager = $$CharactersTableTableManager(
      $_db,
      $_db.characters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_characterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EmbeddingEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $EmbeddingEntriesTable> {
  $$EmbeddingEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentSnapshot => $composableBuilder(
    column: $table.contentSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dims => $composableBuilder(
    column: $table.dims,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CharactersTableFilterComposer get characterId {
    final $$CharactersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableFilterComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmbeddingEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $EmbeddingEntriesTable> {
  $$EmbeddingEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentSnapshot => $composableBuilder(
    column: $table.contentSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dims => $composableBuilder(
    column: $table.dims,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharactersTableOrderingComposer get characterId {
    final $$CharactersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableOrderingComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmbeddingEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmbeddingEntriesTable> {
  $$EmbeddingEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get contentSnapshot => $composableBuilder(
    column: $table.contentSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get vector =>
      $composableBuilder(column: $table.vector, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get dims =>
      $composableBuilder(column: $table.dims, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$CharactersTableAnnotationComposer get characterId {
    final $$CharactersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableAnnotationComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EmbeddingEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EmbeddingEntriesTable,
          EmbeddingEntry,
          $$EmbeddingEntriesTableFilterComposer,
          $$EmbeddingEntriesTableOrderingComposer,
          $$EmbeddingEntriesTableAnnotationComposer,
          $$EmbeddingEntriesTableCreateCompanionBuilder,
          $$EmbeddingEntriesTableUpdateCompanionBuilder,
          (EmbeddingEntry, $$EmbeddingEntriesTableReferences),
          EmbeddingEntry,
          PrefetchHooks Function({bool characterId})
        > {
  $$EmbeddingEntriesTableTableManager(
    _$AppDatabase db,
    $EmbeddingEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmbeddingEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmbeddingEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmbeddingEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> characterId = const Value.absent(),
                Value<int> entryId = const Value.absent(),
                Value<String> contentSnapshot = const Value.absent(),
                Value<Uint8List> vector = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int> dims = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => EmbeddingEntriesCompanion(
                id: id,
                characterId: characterId,
                entryId: entryId,
                contentSnapshot: contentSnapshot,
                vector: vector,
                model: model,
                dims: dims,
                contentHash: contentHash,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int characterId,
                required int entryId,
                required String contentSnapshot,
                required Uint8List vector,
                required String model,
                required int dims,
                required String contentHash,
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => EmbeddingEntriesCompanion.insert(
                id: id,
                characterId: characterId,
                entryId: entryId,
                contentSnapshot: contentSnapshot,
                vector: vector,
                model: model,
                dims: dims,
                contentHash: contentHash,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EmbeddingEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({characterId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (characterId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.characterId,
                        referencedTable: $$EmbeddingEntriesTableReferences
                            ._characterIdTable(db),
                        referencedColumn: $$EmbeddingEntriesTableReferences
                            ._characterIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EmbeddingEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EmbeddingEntriesTable,
      EmbeddingEntry,
      $$EmbeddingEntriesTableFilterComposer,
      $$EmbeddingEntriesTableOrderingComposer,
      $$EmbeddingEntriesTableAnnotationComposer,
      $$EmbeddingEntriesTableCreateCompanionBuilder,
      $$EmbeddingEntriesTableUpdateCompanionBuilder,
      (EmbeddingEntry, $$EmbeddingEntriesTableReferences),
      EmbeddingEntry,
      PrefetchHooks Function({bool characterId})
    >;
typedef $$SemanticHitsTableCreateCompanionBuilder =
    SemanticHitsCompanion Function({
      Value<int> id,
      required int characterId,
      required int entryId,
      required String query,
      required DateTime createdAt,
    });
typedef $$SemanticHitsTableUpdateCompanionBuilder =
    SemanticHitsCompanion Function({
      Value<int> id,
      Value<int> characterId,
      Value<int> entryId,
      Value<String> query,
      Value<DateTime> createdAt,
    });

final class $$SemanticHitsTableReferences
    extends BaseReferences<_$AppDatabase, $SemanticHitsTable, SemanticHit> {
  $$SemanticHitsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CharactersTable _characterIdTable(_$AppDatabase db) =>
      db.characters.createAlias('semantic_hits__character_id__characters__id');

  $$CharactersTableProcessedTableManager get characterId {
    final $_column = $_itemColumn<int>('character_id')!;

    final manager = $$CharactersTableTableManager(
      $_db,
      $_db.characters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_characterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SemanticHitsTableFilterComposer
    extends Composer<_$AppDatabase, $SemanticHitsTable> {
  $$SemanticHitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CharactersTableFilterComposer get characterId {
    final $$CharactersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableFilterComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SemanticHitsTableOrderingComposer
    extends Composer<_$AppDatabase, $SemanticHitsTable> {
  $$SemanticHitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get query => $composableBuilder(
    column: $table.query,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharactersTableOrderingComposer get characterId {
    final $$CharactersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableOrderingComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SemanticHitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SemanticHitsTable> {
  $$SemanticHitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get query =>
      $composableBuilder(column: $table.query, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CharactersTableAnnotationComposer get characterId {
    final $$CharactersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableAnnotationComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SemanticHitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SemanticHitsTable,
          SemanticHit,
          $$SemanticHitsTableFilterComposer,
          $$SemanticHitsTableOrderingComposer,
          $$SemanticHitsTableAnnotationComposer,
          $$SemanticHitsTableCreateCompanionBuilder,
          $$SemanticHitsTableUpdateCompanionBuilder,
          (SemanticHit, $$SemanticHitsTableReferences),
          SemanticHit,
          PrefetchHooks Function({bool characterId})
        > {
  $$SemanticHitsTableTableManager(_$AppDatabase db, $SemanticHitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SemanticHitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SemanticHitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SemanticHitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> characterId = const Value.absent(),
                Value<int> entryId = const Value.absent(),
                Value<String> query = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SemanticHitsCompanion(
                id: id,
                characterId: characterId,
                entryId: entryId,
                query: query,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int characterId,
                required int entryId,
                required String query,
                required DateTime createdAt,
              }) => SemanticHitsCompanion.insert(
                id: id,
                characterId: characterId,
                entryId: entryId,
                query: query,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SemanticHitsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({characterId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (characterId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.characterId,
                        referencedTable: $$SemanticHitsTableReferences
                            ._characterIdTable(db),
                        referencedColumn: $$SemanticHitsTableReferences
                            ._characterIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SemanticHitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SemanticHitsTable,
      SemanticHit,
      $$SemanticHitsTableFilterComposer,
      $$SemanticHitsTableOrderingComposer,
      $$SemanticHitsTableAnnotationComposer,
      $$SemanticHitsTableCreateCompanionBuilder,
      $$SemanticHitsTableUpdateCompanionBuilder,
      (SemanticHit, $$SemanticHitsTableReferences),
      SemanticHit,
      PrefetchHooks Function({bool characterId})
    >;
typedef $$MessageSwipesTableCreateCompanionBuilder =
    MessageSwipesCompanion Function({
      Value<int> id,
      required int messageId,
      required int index,
      required String content,
      required DateTime createdAt,
    });
typedef $$MessageSwipesTableUpdateCompanionBuilder =
    MessageSwipesCompanion Function({
      Value<int> id,
      Value<int> messageId,
      Value<int> index,
      Value<String> content,
      Value<DateTime> createdAt,
    });

final class $$MessageSwipesTableReferences
    extends BaseReferences<_$AppDatabase, $MessageSwipesTable, MessageSwipe> {
  $$MessageSwipesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MessagesTable _messageIdTable(_$AppDatabase db) =>
      db.messages.createAlias('message_swipes__message_id__messages__id');

  $$MessagesTableProcessedTableManager get messageId {
    final $_column = $_itemColumn<int>('message_id')!;

    final manager = $$MessagesTableTableManager(
      $_db,
      $_db.messages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_messageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MessageSwipesTableFilterComposer
    extends Composer<_$AppDatabase, $MessageSwipesTable> {
  $$MessageSwipesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get index => $composableBuilder(
    column: $table.index,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MessagesTableFilterComposer get messageId {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableFilterComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageSwipesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessageSwipesTable> {
  $$MessageSwipesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get index => $composableBuilder(
    column: $table.index,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MessagesTableOrderingComposer get messageId {
    final $$MessagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableOrderingComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageSwipesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessageSwipesTable> {
  $$MessageSwipesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get index =>
      $composableBuilder(column: $table.index, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$MessagesTableAnnotationComposer get messageId {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.messageId,
      referencedTable: $db.messages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.messages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MessageSwipesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessageSwipesTable,
          MessageSwipe,
          $$MessageSwipesTableFilterComposer,
          $$MessageSwipesTableOrderingComposer,
          $$MessageSwipesTableAnnotationComposer,
          $$MessageSwipesTableCreateCompanionBuilder,
          $$MessageSwipesTableUpdateCompanionBuilder,
          (MessageSwipe, $$MessageSwipesTableReferences),
          MessageSwipe,
          PrefetchHooks Function({bool messageId})
        > {
  $$MessageSwipesTableTableManager(_$AppDatabase db, $MessageSwipesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageSwipesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageSwipesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageSwipesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> messageId = const Value.absent(),
                Value<int> index = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => MessageSwipesCompanion(
                id: id,
                messageId: messageId,
                index: index,
                content: content,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int messageId,
                required int index,
                required String content,
                required DateTime createdAt,
              }) => MessageSwipesCompanion.insert(
                id: id,
                messageId: messageId,
                index: index,
                content: content,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MessageSwipesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({messageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (messageId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.messageId,
                        referencedTable: $$MessageSwipesTableReferences
                            ._messageIdTable(db),
                        referencedColumn: $$MessageSwipesTableReferences
                            ._messageIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MessageSwipesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessageSwipesTable,
      MessageSwipe,
      $$MessageSwipesTableFilterComposer,
      $$MessageSwipesTableOrderingComposer,
      $$MessageSwipesTableAnnotationComposer,
      $$MessageSwipesTableCreateCompanionBuilder,
      $$MessageSwipesTableUpdateCompanionBuilder,
      (MessageSwipe, $$MessageSwipesTableReferences),
      MessageSwipe,
      PrefetchHooks Function({bool messageId})
    >;
typedef $$LorebookEntriesTableCreateCompanionBuilder =
    LorebookEntriesCompanion Function({
      Value<int> id,
      required int characterId,
      Value<String> title,
      Value<List<String>> keys,
      Value<String> content,
      Value<bool> constant,
      Value<int> order,
      Value<int> probability,
      Value<String> groupName,
      Value<int> groupWeight,
      Value<String> matchMode,
      Value<String> position,
      Value<int> depth,
      Value<String> source,
      Value<bool> enabled,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$LorebookEntriesTableUpdateCompanionBuilder =
    LorebookEntriesCompanion Function({
      Value<int> id,
      Value<int> characterId,
      Value<String> title,
      Value<List<String>> keys,
      Value<String> content,
      Value<bool> constant,
      Value<int> order,
      Value<int> probability,
      Value<String> groupName,
      Value<int> groupWeight,
      Value<String> matchMode,
      Value<String> position,
      Value<int> depth,
      Value<String> source,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$LorebookEntriesTableReferences
    extends
        BaseReferences<_$AppDatabase, $LorebookEntriesTable, LorebookEntry> {
  $$LorebookEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CharactersTable _characterIdTable(_$AppDatabase db) => db.characters
      .createAlias('lorebook_entries__character_id__characters__id');

  $$CharactersTableProcessedTableManager get characterId {
    final $_column = $_itemColumn<int>('character_id')!;

    final manager = $$CharactersTableTableManager(
      $_db,
      $_db.characters,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_characterIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LorebookEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $LorebookEntriesTable> {
  $$LorebookEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String> get keys =>
      $composableBuilder(
        column: $table.keys,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get constant => $composableBuilder(
    column: $table.constant,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get probability => $composableBuilder(
    column: $table.probability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get groupWeight => $composableBuilder(
    column: $table.groupWeight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matchMode => $composableBuilder(
    column: $table.matchMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get depth => $composableBuilder(
    column: $table.depth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CharactersTableFilterComposer get characterId {
    final $$CharactersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableFilterComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LorebookEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LorebookEntriesTable> {
  $$LorebookEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keys => $composableBuilder(
    column: $table.keys,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get constant => $composableBuilder(
    column: $table.constant,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get order => $composableBuilder(
    column: $table.order,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get probability => $composableBuilder(
    column: $table.probability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get groupWeight => $composableBuilder(
    column: $table.groupWeight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matchMode => $composableBuilder(
    column: $table.matchMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get depth => $composableBuilder(
    column: $table.depth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharactersTableOrderingComposer get characterId {
    final $$CharactersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableOrderingComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LorebookEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LorebookEntriesTable> {
  $$LorebookEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<String>, String> get keys =>
      $composableBuilder(column: $table.keys, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<bool> get constant =>
      $composableBuilder(column: $table.constant, builder: (column) => column);

  GeneratedColumn<int> get order =>
      $composableBuilder(column: $table.order, builder: (column) => column);

  GeneratedColumn<int> get probability => $composableBuilder(
    column: $table.probability,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

  GeneratedColumn<int> get groupWeight => $composableBuilder(
    column: $table.groupWeight,
    builder: (column) => column,
  );

  GeneratedColumn<String> get matchMode =>
      $composableBuilder(column: $table.matchMode, builder: (column) => column);

  GeneratedColumn<String> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get depth =>
      $composableBuilder(column: $table.depth, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$CharactersTableAnnotationComposer get characterId {
    final $$CharactersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.characterId,
      referencedTable: $db.characters,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharactersTableAnnotationComposer(
            $db: $db,
            $table: $db.characters,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LorebookEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LorebookEntriesTable,
          LorebookEntry,
          $$LorebookEntriesTableFilterComposer,
          $$LorebookEntriesTableOrderingComposer,
          $$LorebookEntriesTableAnnotationComposer,
          $$LorebookEntriesTableCreateCompanionBuilder,
          $$LorebookEntriesTableUpdateCompanionBuilder,
          (LorebookEntry, $$LorebookEntriesTableReferences),
          LorebookEntry,
          PrefetchHooks Function({bool characterId})
        > {
  $$LorebookEntriesTableTableManager(
    _$AppDatabase db,
    $LorebookEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LorebookEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LorebookEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LorebookEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> characterId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<List<String>> keys = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<bool> constant = const Value.absent(),
                Value<int> order = const Value.absent(),
                Value<int> probability = const Value.absent(),
                Value<String> groupName = const Value.absent(),
                Value<int> groupWeight = const Value.absent(),
                Value<String> matchMode = const Value.absent(),
                Value<String> position = const Value.absent(),
                Value<int> depth = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => LorebookEntriesCompanion(
                id: id,
                characterId: characterId,
                title: title,
                keys: keys,
                content: content,
                constant: constant,
                order: order,
                probability: probability,
                groupName: groupName,
                groupWeight: groupWeight,
                matchMode: matchMode,
                position: position,
                depth: depth,
                source: source,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int characterId,
                Value<String> title = const Value.absent(),
                Value<List<String>> keys = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<bool> constant = const Value.absent(),
                Value<int> order = const Value.absent(),
                Value<int> probability = const Value.absent(),
                Value<String> groupName = const Value.absent(),
                Value<int> groupWeight = const Value.absent(),
                Value<String> matchMode = const Value.absent(),
                Value<String> position = const Value.absent(),
                Value<int> depth = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => LorebookEntriesCompanion.insert(
                id: id,
                characterId: characterId,
                title: title,
                keys: keys,
                content: content,
                constant: constant,
                order: order,
                probability: probability,
                groupName: groupName,
                groupWeight: groupWeight,
                matchMode: matchMode,
                position: position,
                depth: depth,
                source: source,
                enabled: enabled,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LorebookEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({characterId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (characterId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.characterId,
                        referencedTable: $$LorebookEntriesTableReferences
                            ._characterIdTable(db),
                        referencedColumn: $$LorebookEntriesTableReferences
                            ._characterIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LorebookEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LorebookEntriesTable,
      LorebookEntry,
      $$LorebookEntriesTableFilterComposer,
      $$LorebookEntriesTableOrderingComposer,
      $$LorebookEntriesTableAnnotationComposer,
      $$LorebookEntriesTableCreateCompanionBuilder,
      $$LorebookEntriesTableUpdateCompanionBuilder,
      (LorebookEntry, $$LorebookEntriesTableReferences),
      LorebookEntry,
      PrefetchHooks Function({bool characterId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CharactersTableTableManager get characters =>
      $$CharactersTableTableManager(_db, _db.characters);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$MemoryEntriesTableTableManager get memoryEntries =>
      $$MemoryEntriesTableTableManager(_db, _db.memoryEntries);
  $$PersonaRevisionsTableTableManager get personaRevisions =>
      $$PersonaRevisionsTableTableManager(_db, _db.personaRevisions);
  $$RelationshipStatesTableTableManager get relationshipStates =>
      $$RelationshipStatesTableTableManager(_db, _db.relationshipStates);
  $$ProactivePlansTableTableManager get proactivePlans =>
      $$ProactivePlansTableTableManager(_db, _db.proactivePlans);
  $$InnerThoughtsTableTableManager get innerThoughts =>
      $$InnerThoughtsTableTableManager(_db, _db.innerThoughts);
  $$EmbeddingEntriesTableTableManager get embeddingEntries =>
      $$EmbeddingEntriesTableTableManager(_db, _db.embeddingEntries);
  $$SemanticHitsTableTableManager get semanticHits =>
      $$SemanticHitsTableTableManager(_db, _db.semanticHits);
  $$MessageSwipesTableTableManager get messageSwipes =>
      $$MessageSwipesTableTableManager(_db, _db.messageSwipes);
  $$LorebookEntriesTableTableManager get lorebookEntries =>
      $$LorebookEntriesTableTableManager(_db, _db.lorebookEntries);
}
