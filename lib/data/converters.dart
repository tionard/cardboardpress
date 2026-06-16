// lib/data/converters.dart
//
// drift TypeConverters: let a column store a structured value object by
// (de)serialising it to JSON text. The column reads/writes TemplateData while
// SQLite only ever sees a string.

import 'package:drift/drift.dart';

import '../model/card_model.dart';
import '../model/serialization.dart';

class TemplateSpecConverter extends TypeConverter<TemplateData, String> {
  const TemplateSpecConverter();

  @override
  TemplateData fromSql(String fromDb) => templateFromJson(fromDb);

  @override
  String toSql(TemplateData value) => templateToJson(value);
}
