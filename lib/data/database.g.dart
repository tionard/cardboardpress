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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PaletteColorsTable paletteColors = $PaletteColorsTable(this);
  late final $TemplatesTable templates = $TemplatesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    paletteColors,
    templates,
  ];
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
          (Template, BaseReferences<_$AppDatabase, $TemplatesTable, Template>),
          Template,
          PrefetchHooks Function()
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
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
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
      (Template, BaseReferences<_$AppDatabase, $TemplatesTable, Template>),
      Template,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PaletteColorsTableTableManager get paletteColors =>
      $$PaletteColorsTableTableManager(_db, _db.paletteColors);
  $$TemplatesTableTableManager get templates =>
      $$TemplatesTableTableManager(_db, _db.templates);
}
