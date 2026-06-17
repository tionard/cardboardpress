// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PaletteColorsTable extends PaletteColors
    with TableInfo<$PaletteColorsTable, PaletteColor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaletteColorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _c1Meta = const VerificationMeta('c1');
  @override
  late final GeneratedColumn<int> c1 = GeneratedColumn<int>(
    'c1',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _c2Meta = const VerificationMeta('c2');
  @override
  late final GeneratedColumn<int> c2 = GeneratedColumn<int>(
    'c2',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orientationMeta = const VerificationMeta(
    'orientation',
  );
  @override
  late final GeneratedColumn<String> orientation = GeneratedColumn<String>(
    'orientation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('vertical'),
  );
  static const VerificationMeta _mixMeta = const VerificationMeta('mix');
  @override
  late final GeneratedColumn<double> mix = GeneratedColumn<double>(
    'mix',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.3),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    c1,
    c2,
    orientation,
    mix,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'palette_colors';
  @override
  VerificationContext validateIntegrity(
    Insertable<PaletteColor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('c1')) {
      context.handle(_c1Meta, c1.isAcceptableOrUnknown(data['c1']!, _c1Meta));
    } else if (isInserting) {
      context.missing(_c1Meta);
    }
    if (data.containsKey('c2')) {
      context.handle(_c2Meta, c2.isAcceptableOrUnknown(data['c2']!, _c2Meta));
    }
    if (data.containsKey('orientation')) {
      context.handle(
        _orientationMeta,
        orientation.isAcceptableOrUnknown(
          data['orientation']!,
          _orientationMeta,
        ),
      );
    }
    if (data.containsKey('mix')) {
      context.handle(
        _mixMeta,
        mix.isAcceptableOrUnknown(data['mix']!, _mixMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PaletteColor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PaletteColor(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      c1: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}c1'],
      )!,
      c2: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}c2'],
      ),
      orientation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}orientation'],
      )!,
      mix: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}mix'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $PaletteColorsTable createAlias(String alias) {
    return $PaletteColorsTable(attachedDatabase, alias);
  }
}

class PaletteColor extends DataClass implements Insertable<PaletteColor> {
  final String id;
  final String name;
  final int c1;
  final int? c2;
  final String orientation;
  final double mix;
  final int position;
  const PaletteColor({
    required this.id,
    required this.name,
    required this.c1,
    this.c2,
    required this.orientation,
    required this.mix,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['c1'] = Variable<int>(c1);
    if (!nullToAbsent || c2 != null) {
      map['c2'] = Variable<int>(c2);
    }
    map['orientation'] = Variable<String>(orientation);
    map['mix'] = Variable<double>(mix);
    map['position'] = Variable<int>(position);
    return map;
  }

  PaletteColorsCompanion toCompanion(bool nullToAbsent) {
    return PaletteColorsCompanion(
      id: Value(id),
      name: Value(name),
      c1: Value(c1),
      c2: c2 == null && nullToAbsent ? const Value.absent() : Value(c2),
      orientation: Value(orientation),
      mix: Value(mix),
      position: Value(position),
    );
  }

  factory PaletteColor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PaletteColor(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      c1: serializer.fromJson<int>(json['c1']),
      c2: serializer.fromJson<int?>(json['c2']),
      orientation: serializer.fromJson<String>(json['orientation']),
      mix: serializer.fromJson<double>(json['mix']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'c1': serializer.toJson<int>(c1),
      'c2': serializer.toJson<int?>(c2),
      'orientation': serializer.toJson<String>(orientation),
      'mix': serializer.toJson<double>(mix),
      'position': serializer.toJson<int>(position),
    };
  }

  PaletteColor copyWith({
    String? id,
    String? name,
    int? c1,
    Value<int?> c2 = const Value.absent(),
    String? orientation,
    double? mix,
    int? position,
  }) => PaletteColor(
    id: id ?? this.id,
    name: name ?? this.name,
    c1: c1 ?? this.c1,
    c2: c2.present ? c2.value : this.c2,
    orientation: orientation ?? this.orientation,
    mix: mix ?? this.mix,
    position: position ?? this.position,
  );
  PaletteColor copyWithCompanion(PaletteColorsCompanion data) {
    return PaletteColor(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      c1: data.c1.present ? data.c1.value : this.c1,
      c2: data.c2.present ? data.c2.value : this.c2,
      orientation: data.orientation.present
          ? data.orientation.value
          : this.orientation,
      mix: data.mix.present ? data.mix.value : this.mix,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PaletteColor(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('c1: $c1, ')
          ..write('c2: $c2, ')
          ..write('orientation: $orientation, ')
          ..write('mix: $mix, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, c1, c2, orientation, mix, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PaletteColor &&
          other.id == this.id &&
          other.name == this.name &&
          other.c1 == this.c1 &&
          other.c2 == this.c2 &&
          other.orientation == this.orientation &&
          other.mix == this.mix &&
          other.position == this.position);
}

class PaletteColorsCompanion extends UpdateCompanion<PaletteColor> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> c1;
  final Value<int?> c2;
  final Value<String> orientation;
  final Value<double> mix;
  final Value<int> position;
  final Value<int> rowid;
  const PaletteColorsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.c1 = const Value.absent(),
    this.c2 = const Value.absent(),
    this.orientation = const Value.absent(),
    this.mix = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PaletteColorsCompanion.insert({
    required String id,
    required String name,
    required int c1,
    this.c2 = const Value.absent(),
    this.orientation = const Value.absent(),
    this.mix = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       c1 = Value(c1);
  static Insertable<PaletteColor> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? c1,
    Expression<int>? c2,
    Expression<String>? orientation,
    Expression<double>? mix,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (c1 != null) 'c1': c1,
      if (c2 != null) 'c2': c2,
      if (orientation != null) 'orientation': orientation,
      if (mix != null) 'mix': mix,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PaletteColorsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? c1,
    Value<int?>? c2,
    Value<String>? orientation,
    Value<double>? mix,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return PaletteColorsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      c1: c1 ?? this.c1,
      c2: c2 ?? this.c2,
      orientation: orientation ?? this.orientation,
      mix: mix ?? this.mix,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (c1.present) {
      map['c1'] = Variable<int>(c1.value);
    }
    if (c2.present) {
      map['c2'] = Variable<int>(c2.value);
    }
    if (orientation.present) {
      map['orientation'] = Variable<String>(orientation.value);
    }
    if (mix.present) {
      map['mix'] = Variable<double>(mix.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaletteColorsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('c1: $c1, ')
          ..write('c2: $c2, ')
          ..write('orientation: $orientation, ')
          ..write('mix: $mix, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TemplatesTable extends Templates
    with TableInfo<$TemplatesTable, Template> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<TemplateData, String> spec =
      GeneratedColumn<String>(
        'spec',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TemplateData>($TemplatesTable.$converterspec);
  @override
  List<GeneratedColumn> get $columns => [id, name, position, spec];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'templates';
  @override
  VerificationContext validateIntegrity(
    Insertable<Template> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Template map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Template(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      spec: $TemplatesTable.$converterspec.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}spec'],
        )!,
      ),
    );
  }

  @override
  $TemplatesTable createAlias(String alias) {
    return $TemplatesTable(attachedDatabase, alias);
  }

  static TypeConverter<TemplateData, String> $converterspec =
      const TemplateSpecConverter();
}

class Template extends DataClass implements Insertable<Template> {
  final String id;
  final String name;
  final int position;
  final TemplateData spec;
  const Template({
    required this.id,
    required this.name,
    required this.position,
    required this.spec,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['position'] = Variable<int>(position);
    {
      map['spec'] = Variable<String>(
        $TemplatesTable.$converterspec.toSql(spec),
      );
    }
    return map;
  }

  TemplatesCompanion toCompanion(bool nullToAbsent) {
    return TemplatesCompanion(
      id: Value(id),
      name: Value(name),
      position: Value(position),
      spec: Value(spec),
    );
  }

  factory Template.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Template(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      position: serializer.fromJson<int>(json['position']),
      spec: serializer.fromJson<TemplateData>(json['spec']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'position': serializer.toJson<int>(position),
      'spec': serializer.toJson<TemplateData>(spec),
    };
  }

  Template copyWith({
    String? id,
    String? name,
    int? position,
    TemplateData? spec,
  }) => Template(
    id: id ?? this.id,
    name: name ?? this.name,
    position: position ?? this.position,
    spec: spec ?? this.spec,
  );
  Template copyWithCompanion(TemplatesCompanion data) {
    return Template(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      position: data.position.present ? data.position.value : this.position,
      spec: data.spec.present ? data.spec.value : this.spec,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Template(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('spec: $spec')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, position, spec);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Template &&
          other.id == this.id &&
          other.name == this.name &&
          other.position == this.position &&
          other.spec == this.spec);
}

class TemplatesCompanion extends UpdateCompanion<Template> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> position;
  final Value<TemplateData> spec;
  final Value<int> rowid;
  const TemplatesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.position = const Value.absent(),
    this.spec = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TemplatesCompanion.insert({
    required String id,
    required String name,
    this.position = const Value.absent(),
    required TemplateData spec,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       spec = Value(spec);
  static Insertable<Template> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? position,
    Expression<String>? spec,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (position != null) 'position': position,
      if (spec != null) 'spec': spec,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TemplatesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? position,
    Value<TemplateData>? spec,
    Value<int>? rowid,
  }) {
    return TemplatesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      spec: spec ?? this.spec,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (spec.present) {
      map['spec'] = Variable<String>(
        $TemplatesTable.$converterspec.toSql(spec.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TemplatesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('spec: $spec, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardsTable extends Cards with TableInfo<$CardsTable, Card> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES templates (id) ON DELETE SET NULL',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<TemplateData, String>
  templateSnapshot = GeneratedColumn<String>(
    'template_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<TemplateData>($CardsTable.$convertertemplateSnapshot);
  @override
  late final GeneratedColumnWithTypeConverter<CardContent, String> content =
      GeneratedColumn<String>(
        'content',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<CardContent>($CardsTable.$convertercontent);
  static const VerificationMeta _foilMeta = const VerificationMeta('foil');
  @override
  late final GeneratedColumn<String> foil = GeneratedColumn<String>(
    'foil',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _setIdMeta = const VerificationMeta('setId');
  @override
  late final GeneratedColumn<String> setId = GeneratedColumn<String>(
    'set_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    templateId,
    templateSnapshot,
    content,
    foil,
    setId,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<Card> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    }
    if (data.containsKey('foil')) {
      context.handle(
        _foilMeta,
        foil.isAcceptableOrUnknown(data['foil']!, _foilMeta),
      );
    }
    if (data.containsKey('set_id')) {
      context.handle(
        _setIdMeta,
        setId.isAcceptableOrUnknown(data['set_id']!, _setIdMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Card map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Card(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      ),
      templateSnapshot: $CardsTable.$convertertemplateSnapshot.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}template_snapshot'],
        )!,
      ),
      content: $CardsTable.$convertercontent.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}content'],
        )!,
      ),
      foil: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}foil'],
      )!,
      setId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}set_id'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $CardsTable createAlias(String alias) {
    return $CardsTable(attachedDatabase, alias);
  }

  static TypeConverter<TemplateData, String> $convertertemplateSnapshot =
      const TemplateSpecConverter();
  static TypeConverter<CardContent, String> $convertercontent =
      const CardContentConverter();
}

class Card extends DataClass implements Insertable<Card> {
  final String id;
  final String? templateId;
  final TemplateData templateSnapshot;
  final CardContent content;
  final String foil;
  final String? setId;
  final int position;
  const Card({
    required this.id,
    this.templateId,
    required this.templateSnapshot,
    required this.content,
    required this.foil,
    this.setId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || templateId != null) {
      map['template_id'] = Variable<String>(templateId);
    }
    {
      map['template_snapshot'] = Variable<String>(
        $CardsTable.$convertertemplateSnapshot.toSql(templateSnapshot),
      );
    }
    {
      map['content'] = Variable<String>(
        $CardsTable.$convertercontent.toSql(content),
      );
    }
    map['foil'] = Variable<String>(foil);
    if (!nullToAbsent || setId != null) {
      map['set_id'] = Variable<String>(setId);
    }
    map['position'] = Variable<int>(position);
    return map;
  }

  CardsCompanion toCompanion(bool nullToAbsent) {
    return CardsCompanion(
      id: Value(id),
      templateId: templateId == null && nullToAbsent
          ? const Value.absent()
          : Value(templateId),
      templateSnapshot: Value(templateSnapshot),
      content: Value(content),
      foil: Value(foil),
      setId: setId == null && nullToAbsent
          ? const Value.absent()
          : Value(setId),
      position: Value(position),
    );
  }

  factory Card.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Card(
      id: serializer.fromJson<String>(json['id']),
      templateId: serializer.fromJson<String?>(json['templateId']),
      templateSnapshot: serializer.fromJson<TemplateData>(
        json['templateSnapshot'],
      ),
      content: serializer.fromJson<CardContent>(json['content']),
      foil: serializer.fromJson<String>(json['foil']),
      setId: serializer.fromJson<String?>(json['setId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'templateId': serializer.toJson<String?>(templateId),
      'templateSnapshot': serializer.toJson<TemplateData>(templateSnapshot),
      'content': serializer.toJson<CardContent>(content),
      'foil': serializer.toJson<String>(foil),
      'setId': serializer.toJson<String?>(setId),
      'position': serializer.toJson<int>(position),
    };
  }

  Card copyWith({
    String? id,
    Value<String?> templateId = const Value.absent(),
    TemplateData? templateSnapshot,
    CardContent? content,
    String? foil,
    Value<String?> setId = const Value.absent(),
    int? position,
  }) => Card(
    id: id ?? this.id,
    templateId: templateId.present ? templateId.value : this.templateId,
    templateSnapshot: templateSnapshot ?? this.templateSnapshot,
    content: content ?? this.content,
    foil: foil ?? this.foil,
    setId: setId.present ? setId.value : this.setId,
    position: position ?? this.position,
  );
  Card copyWithCompanion(CardsCompanion data) {
    return Card(
      id: data.id.present ? data.id.value : this.id,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      templateSnapshot: data.templateSnapshot.present
          ? data.templateSnapshot.value
          : this.templateSnapshot,
      content: data.content.present ? data.content.value : this.content,
      foil: data.foil.present ? data.foil.value : this.foil,
      setId: data.setId.present ? data.setId.value : this.setId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Card(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('templateSnapshot: $templateSnapshot, ')
          ..write('content: $content, ')
          ..write('foil: $foil, ')
          ..write('setId: $setId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    templateId,
    templateSnapshot,
    content,
    foil,
    setId,
    position,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Card &&
          other.id == this.id &&
          other.templateId == this.templateId &&
          other.templateSnapshot == this.templateSnapshot &&
          other.content == this.content &&
          other.foil == this.foil &&
          other.setId == this.setId &&
          other.position == this.position);
}

class CardsCompanion extends UpdateCompanion<Card> {
  final Value<String> id;
  final Value<String?> templateId;
  final Value<TemplateData> templateSnapshot;
  final Value<CardContent> content;
  final Value<String> foil;
  final Value<String?> setId;
  final Value<int> position;
  final Value<int> rowid;
  const CardsCompanion({
    this.id = const Value.absent(),
    this.templateId = const Value.absent(),
    this.templateSnapshot = const Value.absent(),
    this.content = const Value.absent(),
    this.foil = const Value.absent(),
    this.setId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardsCompanion.insert({
    required String id,
    this.templateId = const Value.absent(),
    required TemplateData templateSnapshot,
    required CardContent content,
    this.foil = const Value.absent(),
    this.setId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       templateSnapshot = Value(templateSnapshot),
       content = Value(content);
  static Insertable<Card> custom({
    Expression<String>? id,
    Expression<String>? templateId,
    Expression<String>? templateSnapshot,
    Expression<String>? content,
    Expression<String>? foil,
    Expression<String>? setId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (templateId != null) 'template_id': templateId,
      if (templateSnapshot != null) 'template_snapshot': templateSnapshot,
      if (content != null) 'content': content,
      if (foil != null) 'foil': foil,
      if (setId != null) 'set_id': setId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardsCompanion copyWith({
    Value<String>? id,
    Value<String?>? templateId,
    Value<TemplateData>? templateSnapshot,
    Value<CardContent>? content,
    Value<String>? foil,
    Value<String?>? setId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return CardsCompanion(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      templateSnapshot: templateSnapshot ?? this.templateSnapshot,
      content: content ?? this.content,
      foil: foil ?? this.foil,
      setId: setId ?? this.setId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (templateSnapshot.present) {
      map['template_snapshot'] = Variable<String>(
        $CardsTable.$convertertemplateSnapshot.toSql(templateSnapshot.value),
      );
    }
    if (content.present) {
      map['content'] = Variable<String>(
        $CardsTable.$convertercontent.toSql(content.value),
      );
    }
    if (foil.present) {
      map['foil'] = Variable<String>(foil.value);
    }
    if (setId.present) {
      map['set_id'] = Variable<String>(setId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardsCompanion(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('templateSnapshot: $templateSnapshot, ')
          ..write('content: $content, ')
          ..write('foil: $foil, ')
          ..write('setId: $setId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PaletteColorsTable paletteColors = $PaletteColorsTable(this);
  late final $TemplatesTable templates = $TemplatesTable(this);
  late final $CardsTable cards = $CardsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    paletteColors,
    templates,
    cards,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'templates',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('cards', kind: UpdateKind.update)],
    ),
  ]);
}

typedef $$PaletteColorsTableCreateCompanionBuilder =
    PaletteColorsCompanion Function({
      required String id,
      required String name,
      required int c1,
      Value<int?> c2,
      Value<String> orientation,
      Value<double> mix,
      Value<int> position,
      Value<int> rowid,
    });
typedef $$PaletteColorsTableUpdateCompanionBuilder =
    PaletteColorsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> c1,
      Value<int?> c2,
      Value<String> orientation,
      Value<double> mix,
      Value<int> position,
      Value<int> rowid,
    });

class $$PaletteColorsTableFilterComposer
    extends Composer<_$AppDatabase, $PaletteColorsTable> {
  $$PaletteColorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get c1 => $composableBuilder(
    column: $table.c1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get c2 => $composableBuilder(
    column: $table.c2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get mix => $composableBuilder(
    column: $table.mix,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PaletteColorsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaletteColorsTable> {
  $$PaletteColorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get c1 => $composableBuilder(
    column: $table.c1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get c2 => $composableBuilder(
    column: $table.c2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get mix => $composableBuilder(
    column: $table.mix,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PaletteColorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaletteColorsTable> {
  $$PaletteColorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get c1 =>
      $composableBuilder(column: $table.c1, builder: (column) => column);

  GeneratedColumn<int> get c2 =>
      $composableBuilder(column: $table.c2, builder: (column) => column);

  GeneratedColumn<String> get orientation => $composableBuilder(
    column: $table.orientation,
    builder: (column) => column,
  );

  GeneratedColumn<double> get mix =>
      $composableBuilder(column: $table.mix, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$PaletteColorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PaletteColorsTable,
          PaletteColor,
          $$PaletteColorsTableFilterComposer,
          $$PaletteColorsTableOrderingComposer,
          $$PaletteColorsTableAnnotationComposer,
          $$PaletteColorsTableCreateCompanionBuilder,
          $$PaletteColorsTableUpdateCompanionBuilder,
          (
            PaletteColor,
            BaseReferences<_$AppDatabase, $PaletteColorsTable, PaletteColor>,
          ),
          PaletteColor,
          PrefetchHooks Function()
        > {
  $$PaletteColorsTableTableManager(_$AppDatabase db, $PaletteColorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaletteColorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaletteColorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaletteColorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> c1 = const Value.absent(),
                Value<int?> c2 = const Value.absent(),
                Value<String> orientation = const Value.absent(),
                Value<double> mix = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PaletteColorsCompanion(
                id: id,
                name: name,
                c1: c1,
                c2: c2,
                orientation: orientation,
                mix: mix,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int c1,
                Value<int?> c2 = const Value.absent(),
                Value<String> orientation = const Value.absent(),
                Value<double> mix = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PaletteColorsCompanion.insert(
                id: id,
                name: name,
                c1: c1,
                c2: c2,
                orientation: orientation,
                mix: mix,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PaletteColorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PaletteColorsTable,
      PaletteColor,
      $$PaletteColorsTableFilterComposer,
      $$PaletteColorsTableOrderingComposer,
      $$PaletteColorsTableAnnotationComposer,
      $$PaletteColorsTableCreateCompanionBuilder,
      $$PaletteColorsTableUpdateCompanionBuilder,
      (
        PaletteColor,
        BaseReferences<_$AppDatabase, $PaletteColorsTable, PaletteColor>,
      ),
      PaletteColor,
      PrefetchHooks Function()
    >;
typedef $$TemplatesTableCreateCompanionBuilder =
    TemplatesCompanion Function({
      required String id,
      required String name,
      Value<int> position,
      required TemplateData spec,
      Value<int> rowid,
    });
typedef $$TemplatesTableUpdateCompanionBuilder =
    TemplatesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> position,
      Value<TemplateData> spec,
      Value<int> rowid,
    });

final class $$TemplatesTableReferences
    extends BaseReferences<_$AppDatabase, $TemplatesTable, Template> {
  $$TemplatesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CardsTable, List<Card>> _cardsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.cards,
    aliasName: 'templates__id__cards__template_id',
  );

  $$CardsTableProcessedTableManager get cardsRefs {
    final manager = $$CardsTableTableManager(
      $_db,
      $_db.cards,
    ).filter((f) => f.templateId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_cardsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TemplatesTableFilterComposer
    extends Composer<_$AppDatabase, $TemplatesTable> {
  $$TemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TemplateData, TemplateData, String> get spec =>
      $composableBuilder(
        column: $table.spec,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  Expression<bool> cardsRefs(
    Expression<bool> Function($$CardsTableFilterComposer f) f,
  ) {
    final $$CardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.templateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableFilterComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TemplatesTableOrderingComposer
    extends Composer<_$AppDatabase, $TemplatesTable> {
  $$TemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get spec => $composableBuilder(
    column: $table.spec,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TemplatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TemplatesTable> {
  $$TemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TemplateData, String> get spec =>
      $composableBuilder(column: $table.spec, builder: (column) => column);

  Expression<T> cardsRefs<T extends Object>(
    Expression<T> Function($$CardsTableAnnotationComposer a) f,
  ) {
    final $$CardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.templateId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableAnnotationComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TemplatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TemplatesTable,
          Template,
          $$TemplatesTableFilterComposer,
          $$TemplatesTableOrderingComposer,
          $$TemplatesTableAnnotationComposer,
          $$TemplatesTableCreateCompanionBuilder,
          $$TemplatesTableUpdateCompanionBuilder,
          (Template, $$TemplatesTableReferences),
          Template,
          PrefetchHooks Function({bool cardsRefs})
        > {
  $$TemplatesTableTableManager(_$AppDatabase db, $TemplatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<TemplateData> spec = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TemplatesCompanion(
                id: id,
                name: name,
                position: position,
                spec: spec,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> position = const Value.absent(),
                required TemplateData spec,
                Value<int> rowid = const Value.absent(),
              }) => TemplatesCompanion.insert(
                id: id,
                name: name,
                position: position,
                spec: spec,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TemplatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({cardsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (cardsRefs) db.cards],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (cardsRefs)
                    await $_getPrefetchedData<Template, $TemplatesTable, Card>(
                      currentTable: table,
                      referencedTable: $$TemplatesTableReferences
                          ._cardsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$TemplatesTableReferences(db, table, p0).cardsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.templateId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TemplatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TemplatesTable,
      Template,
      $$TemplatesTableFilterComposer,
      $$TemplatesTableOrderingComposer,
      $$TemplatesTableAnnotationComposer,
      $$TemplatesTableCreateCompanionBuilder,
      $$TemplatesTableUpdateCompanionBuilder,
      (Template, $$TemplatesTableReferences),
      Template,
      PrefetchHooks Function({bool cardsRefs})
    >;
typedef $$CardsTableCreateCompanionBuilder =
    CardsCompanion Function({
      required String id,
      Value<String?> templateId,
      required TemplateData templateSnapshot,
      required CardContent content,
      Value<String> foil,
      Value<String?> setId,
      Value<int> position,
      Value<int> rowid,
    });
typedef $$CardsTableUpdateCompanionBuilder =
    CardsCompanion Function({
      Value<String> id,
      Value<String?> templateId,
      Value<TemplateData> templateSnapshot,
      Value<CardContent> content,
      Value<String> foil,
      Value<String?> setId,
      Value<int> position,
      Value<int> rowid,
    });

final class $$CardsTableReferences
    extends BaseReferences<_$AppDatabase, $CardsTable, Card> {
  $$CardsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TemplatesTable _templateIdTable(_$AppDatabase db) =>
      db.templates.createAlias('cards__template_id__templates__id');

  $$TemplatesTableProcessedTableManager? get templateId {
    final $_column = $_itemColumn<String>('template_id');
    if ($_column == null) return null;
    final manager = $$TemplatesTableTableManager(
      $_db,
      $_db.templates,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_templateIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CardsTableFilterComposer extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TemplateData, TemplateData, String>
  get templateSnapshot => $composableBuilder(
    column: $table.templateSnapshot,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<CardContent, CardContent, String>
  get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get foil => $composableBuilder(
    column: $table.foil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get setId => $composableBuilder(
    column: $table.setId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$TemplatesTableFilterComposer get templateId {
    final $$TemplatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableFilterComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardsTableOrderingComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get templateSnapshot => $composableBuilder(
    column: $table.templateSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get foil => $composableBuilder(
    column: $table.foil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get setId => $composableBuilder(
    column: $table.setId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$TemplatesTableOrderingComposer get templateId {
    final $$TemplatesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableOrderingComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TemplateData, String> get templateSnapshot =>
      $composableBuilder(
        column: $table.templateSnapshot,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<CardContent, String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get foil =>
      $composableBuilder(column: $table.foil, builder: (column) => column);

  GeneratedColumn<String> get setId =>
      $composableBuilder(column: $table.setId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$TemplatesTableAnnotationComposer get templateId {
    final $$TemplatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.templateId,
      referencedTable: $db.templates,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TemplatesTableAnnotationComposer(
            $db: $db,
            $table: $db.templates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardsTable,
          Card,
          $$CardsTableFilterComposer,
          $$CardsTableOrderingComposer,
          $$CardsTableAnnotationComposer,
          $$CardsTableCreateCompanionBuilder,
          $$CardsTableUpdateCompanionBuilder,
          (Card, $$CardsTableReferences),
          Card,
          PrefetchHooks Function({bool templateId})
        > {
  $$CardsTableTableManager(_$AppDatabase db, $CardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> templateId = const Value.absent(),
                Value<TemplateData> templateSnapshot = const Value.absent(),
                Value<CardContent> content = const Value.absent(),
                Value<String> foil = const Value.absent(),
                Value<String?> setId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion(
                id: id,
                templateId: templateId,
                templateSnapshot: templateSnapshot,
                content: content,
                foil: foil,
                setId: setId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> templateId = const Value.absent(),
                required TemplateData templateSnapshot,
                required CardContent content,
                Value<String> foil = const Value.absent(),
                Value<String?> setId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion.insert(
                id: id,
                templateId: templateId,
                templateSnapshot: templateSnapshot,
                content: content,
                foil: foil,
                setId: setId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$CardsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({templateId = false}) {
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
                    if (templateId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.templateId,
                                referencedTable: $$CardsTableReferences
                                    ._templateIdTable(db),
                                referencedColumn: $$CardsTableReferences
                                    ._templateIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$CardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardsTable,
      Card,
      $$CardsTableFilterComposer,
      $$CardsTableOrderingComposer,
      $$CardsTableAnnotationComposer,
      $$CardsTableCreateCompanionBuilder,
      $$CardsTableUpdateCompanionBuilder,
      (Card, $$CardsTableReferences),
      Card,
      PrefetchHooks Function({bool templateId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PaletteColorsTableTableManager get paletteColors =>
      $$PaletteColorsTableTableManager(_db, _db.paletteColors);
  $$TemplatesTableTableManager get templates =>
      $$TemplatesTableTableManager(_db, _db.templates);
  $$CardsTableTableManager get cards =>
      $$CardsTableTableManager(_db, _db.cards);
}
