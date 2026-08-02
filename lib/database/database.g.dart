// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $RoutinesTable extends Routines
    with TableInfo<$RoutinesTable, RoutineModel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoutinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _IdMeta = const VerificationMeta('Id');
  @override
  late final GeneratedColumn<int> Id = GeneratedColumn<int>(
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
  static const VerificationMeta _NameMeta = const VerificationMeta('Name');
  @override
  late final GeneratedColumn<String> Name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 255,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _SnoozeSecondsMeta = const VerificationMeta(
    'SnoozeSeconds',
  );
  @override
  late final GeneratedColumn<int> SnoozeSeconds = GeneratedColumn<int>(
    'snooze_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(300),
  );
  static const VerificationMeta _IntervalSecondsMeta = const VerificationMeta(
    'IntervalSeconds',
  );
  @override
  late final GeneratedColumn<int> IntervalSeconds = GeneratedColumn<int>(
    'interval_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _MaxTimesPerDayMeta = const VerificationMeta(
    'MaxTimesPerDay',
  );
  @override
  late final GeneratedColumn<int> MaxTimesPerDay = GeneratedColumn<int>(
    'max_times_per_day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _DayStartSecondsMeta = const VerificationMeta(
    'DayStartSeconds',
  );
  @override
  late final GeneratedColumn<int> DayStartSeconds = GeneratedColumn<int>(
    'day_start_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _MaxTimesPerDayEnabledMeta =
      const VerificationMeta('MaxTimesPerDayEnabled');
  @override
  late final GeneratedColumn<bool> MaxTimesPerDayEnabled =
      GeneratedColumn<bool>(
        'max_times_per_day_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("max_times_per_day_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _EnabledWeekdaysMeta = const VerificationMeta(
    'EnabledWeekdays',
  );
  @override
  late final GeneratedColumn<int> EnabledWeekdays = GeneratedColumn<int>(
    'enabled_weekdays',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(127),
  );
  static const VerificationMeta _DriftCompensationTypeCodeMeta =
      const VerificationMeta('DriftCompensationTypeCode');
  @override
  late final GeneratedColumn<int> DriftCompensationTypeCode =
      GeneratedColumn<int>(
        'drift_compensation_type_code',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _ShowPreviewMeta = const VerificationMeta(
    'ShowPreview',
  );
  @override
  late final GeneratedColumn<bool> ShowPreview = GeneratedColumn<bool>(
    'show_preview',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("show_preview" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _VibrateMeta = const VerificationMeta(
    'Vibrate',
  );
  @override
  late final GeneratedColumn<bool> Vibrate = GeneratedColumn<bool>(
    'vibrate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("vibrate" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _VolumeMeta = const VerificationMeta('Volume');
  @override
  late final GeneratedColumn<int> Volume = GeneratedColumn<int>(
    'volume',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(50),
  );
  static const VerificationMeta _FadeInMeta = const VerificationMeta('FadeIn');
  @override
  late final GeneratedColumn<bool> FadeIn = GeneratedColumn<bool>(
    'fade_in',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("fade_in" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _AudioUriMeta = const VerificationMeta(
    'AudioUri',
  );
  @override
  late final GeneratedColumn<String> AudioUri = GeneratedColumn<String>(
    'audio_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _IsActiveMeta = const VerificationMeta(
    'IsActive',
  );
  @override
  late final GeneratedColumn<bool> IsActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _CreatedAtMeta = const VerificationMeta(
    'CreatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> CreatedAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _ModifiedAtMeta = const VerificationMeta(
    'ModifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> ModifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _DeletedMeta = const VerificationMeta(
    'Deleted',
  );
  @override
  late final GeneratedColumn<bool> Deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    Id,
    Name,
    SnoozeSeconds,
    IntervalSeconds,
    MaxTimesPerDay,
    DayStartSeconds,
    MaxTimesPerDayEnabled,
    EnabledWeekdays,
    DriftCompensationTypeCode,
    ShowPreview,
    Vibrate,
    Volume,
    FadeIn,
    AudioUri,
    IsActive,
    CreatedAt,
    ModifiedAt,
    Deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'routines';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoutineModel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_IdMeta, Id.isAcceptableOrUnknown(data['id']!, _IdMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _NameMeta,
        Name.isAcceptableOrUnknown(data['name']!, _NameMeta),
      );
    } else if (isInserting) {
      context.missing(_NameMeta);
    }
    if (data.containsKey('snooze_seconds')) {
      context.handle(
        _SnoozeSecondsMeta,
        SnoozeSeconds.isAcceptableOrUnknown(
          data['snooze_seconds']!,
          _SnoozeSecondsMeta,
        ),
      );
    }
    if (data.containsKey('interval_seconds')) {
      context.handle(
        _IntervalSecondsMeta,
        IntervalSeconds.isAcceptableOrUnknown(
          data['interval_seconds']!,
          _IntervalSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_IntervalSecondsMeta);
    }
    if (data.containsKey('max_times_per_day')) {
      context.handle(
        _MaxTimesPerDayMeta,
        MaxTimesPerDay.isAcceptableOrUnknown(
          data['max_times_per_day']!,
          _MaxTimesPerDayMeta,
        ),
      );
    }
    if (data.containsKey('day_start_seconds')) {
      context.handle(
        _DayStartSecondsMeta,
        DayStartSeconds.isAcceptableOrUnknown(
          data['day_start_seconds']!,
          _DayStartSecondsMeta,
        ),
      );
    }
    if (data.containsKey('max_times_per_day_enabled')) {
      context.handle(
        _MaxTimesPerDayEnabledMeta,
        MaxTimesPerDayEnabled.isAcceptableOrUnknown(
          data['max_times_per_day_enabled']!,
          _MaxTimesPerDayEnabledMeta,
        ),
      );
    }
    if (data.containsKey('enabled_weekdays')) {
      context.handle(
        _EnabledWeekdaysMeta,
        EnabledWeekdays.isAcceptableOrUnknown(
          data['enabled_weekdays']!,
          _EnabledWeekdaysMeta,
        ),
      );
    }
    if (data.containsKey('drift_compensation_type_code')) {
      context.handle(
        _DriftCompensationTypeCodeMeta,
        DriftCompensationTypeCode.isAcceptableOrUnknown(
          data['drift_compensation_type_code']!,
          _DriftCompensationTypeCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_DriftCompensationTypeCodeMeta);
    }
    if (data.containsKey('show_preview')) {
      context.handle(
        _ShowPreviewMeta,
        ShowPreview.isAcceptableOrUnknown(
          data['show_preview']!,
          _ShowPreviewMeta,
        ),
      );
    }
    if (data.containsKey('vibrate')) {
      context.handle(
        _VibrateMeta,
        Vibrate.isAcceptableOrUnknown(data['vibrate']!, _VibrateMeta),
      );
    }
    if (data.containsKey('volume')) {
      context.handle(
        _VolumeMeta,
        Volume.isAcceptableOrUnknown(data['volume']!, _VolumeMeta),
      );
    }
    if (data.containsKey('fade_in')) {
      context.handle(
        _FadeInMeta,
        FadeIn.isAcceptableOrUnknown(data['fade_in']!, _FadeInMeta),
      );
    }
    if (data.containsKey('audio_uri')) {
      context.handle(
        _AudioUriMeta,
        AudioUri.isAcceptableOrUnknown(data['audio_uri']!, _AudioUriMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _IsActiveMeta,
        IsActive.isAcceptableOrUnknown(data['is_active']!, _IsActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _CreatedAtMeta,
        CreatedAt.isAcceptableOrUnknown(data['created_at']!, _CreatedAtMeta),
      );
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _ModifiedAtMeta,
        ModifiedAt.isAcceptableOrUnknown(data['modified_at']!, _ModifiedAtMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _DeletedMeta,
        Deleted.isAcceptableOrUnknown(data['deleted']!, _DeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {Id};
  @override
  RoutineModel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoutineModel(
      Id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      Name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      SnoozeSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snooze_seconds'],
      )!,
      IntervalSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval_seconds'],
      )!,
      MaxTimesPerDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_times_per_day'],
      )!,
      DayStartSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_start_seconds'],
      )!,
      MaxTimesPerDayEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}max_times_per_day_enabled'],
      )!,
      EnabledWeekdays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}enabled_weekdays'],
      )!,
      DriftCompensationTypeCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}drift_compensation_type_code'],
      )!,
      ShowPreview: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}show_preview'],
      )!,
      Vibrate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}vibrate'],
      )!,
      Volume: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}volume'],
      )!,
      FadeIn: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}fade_in'],
      )!,
      AudioUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_uri'],
      ),
      IsActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      CreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      ModifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      ),
      Deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
    );
  }

  @override
  $RoutinesTable createAlias(String alias) {
    return $RoutinesTable(attachedDatabase, alias);
  }
}

class RoutineModel extends DataClass implements Insertable<RoutineModel> {
  final int Id;
  final String Name;

  /// Duration of snooze in total seconds.
  final int SnoozeSeconds;

  /// Total repeating interval length in seconds.
  final int IntervalSeconds;

  /// Max fresh rings per day period when [MaxTimesPerDayEnabled] is true.
  final int MaxTimesPerDay;

  /// Seconds after local midnight when the daily ring counter resets.
  final int DayStartSeconds;

  /// When false, daily ring cap fields are ignored (unlimited rings).
  final bool MaxTimesPerDayEnabled;

  /// Monday-first weekday bitmask (bit 0 = Mon … bit 6 = Sun). Default all days.
  final int EnabledWeekdays;
  final int DriftCompensationTypeCode;
  final bool ShowPreview;

  /// When true, the device vibrates while this routine's alarm is ringing.
  final bool Vibrate;

  /// Alarm playback volume from 5 (minimum) to 100 (full).
  final int Volume;

  /// When true, alarm audio fades from silent up to [Volume] on trigger.
  final bool FadeIn;
  final String? AudioUri;
  final bool IsActive;
  final DateTime CreatedAt;
  final DateTime? ModifiedAt;
  final bool Deleted;
  const RoutineModel({
    required this.Id,
    required this.Name,
    required this.SnoozeSeconds,
    required this.IntervalSeconds,
    required this.MaxTimesPerDay,
    required this.DayStartSeconds,
    required this.MaxTimesPerDayEnabled,
    required this.EnabledWeekdays,
    required this.DriftCompensationTypeCode,
    required this.ShowPreview,
    required this.Vibrate,
    required this.Volume,
    required this.FadeIn,
    this.AudioUri,
    required this.IsActive,
    required this.CreatedAt,
    this.ModifiedAt,
    required this.Deleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(Id);
    map['name'] = Variable<String>(Name);
    map['snooze_seconds'] = Variable<int>(SnoozeSeconds);
    map['interval_seconds'] = Variable<int>(IntervalSeconds);
    map['max_times_per_day'] = Variable<int>(MaxTimesPerDay);
    map['day_start_seconds'] = Variable<int>(DayStartSeconds);
    map['max_times_per_day_enabled'] = Variable<bool>(MaxTimesPerDayEnabled);
    map['enabled_weekdays'] = Variable<int>(EnabledWeekdays);
    map['drift_compensation_type_code'] = Variable<int>(
      DriftCompensationTypeCode,
    );
    map['show_preview'] = Variable<bool>(ShowPreview);
    map['vibrate'] = Variable<bool>(Vibrate);
    map['volume'] = Variable<int>(Volume);
    map['fade_in'] = Variable<bool>(FadeIn);
    if (!nullToAbsent || AudioUri != null) {
      map['audio_uri'] = Variable<String>(AudioUri);
    }
    map['is_active'] = Variable<bool>(IsActive);
    map['created_at'] = Variable<DateTime>(CreatedAt);
    if (!nullToAbsent || ModifiedAt != null) {
      map['modified_at'] = Variable<DateTime>(ModifiedAt);
    }
    map['deleted'] = Variable<bool>(Deleted);
    return map;
  }

  RoutinesCompanion toCompanion(bool nullToAbsent) {
    return RoutinesCompanion(
      Id: Value(Id),
      Name: Value(Name),
      SnoozeSeconds: Value(SnoozeSeconds),
      IntervalSeconds: Value(IntervalSeconds),
      MaxTimesPerDay: Value(MaxTimesPerDay),
      DayStartSeconds: Value(DayStartSeconds),
      MaxTimesPerDayEnabled: Value(MaxTimesPerDayEnabled),
      EnabledWeekdays: Value(EnabledWeekdays),
      DriftCompensationTypeCode: Value(DriftCompensationTypeCode),
      ShowPreview: Value(ShowPreview),
      Vibrate: Value(Vibrate),
      Volume: Value(Volume),
      FadeIn: Value(FadeIn),
      AudioUri: AudioUri == null && nullToAbsent
          ? const Value.absent()
          : Value(AudioUri),
      IsActive: Value(IsActive),
      CreatedAt: Value(CreatedAt),
      ModifiedAt: ModifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(ModifiedAt),
      Deleted: Value(Deleted),
    );
  }

  factory RoutineModel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoutineModel(
      Id: serializer.fromJson<int>(json['Id']),
      Name: serializer.fromJson<String>(json['Name']),
      SnoozeSeconds: serializer.fromJson<int>(json['SnoozeSeconds']),
      IntervalSeconds: serializer.fromJson<int>(json['IntervalSeconds']),
      MaxTimesPerDay: serializer.fromJson<int>(json['MaxTimesPerDay']),
      DayStartSeconds: serializer.fromJson<int>(json['DayStartSeconds']),
      MaxTimesPerDayEnabled: serializer.fromJson<bool>(
        json['MaxTimesPerDayEnabled'],
      ),
      EnabledWeekdays: serializer.fromJson<int>(json['EnabledWeekdays']),
      DriftCompensationTypeCode: serializer.fromJson<int>(
        json['DriftCompensationTypeCode'],
      ),
      ShowPreview: serializer.fromJson<bool>(json['ShowPreview']),
      Vibrate: serializer.fromJson<bool>(json['Vibrate']),
      Volume: serializer.fromJson<int>(json['Volume']),
      FadeIn: serializer.fromJson<bool>(json['FadeIn']),
      AudioUri: serializer.fromJson<String?>(json['AudioUri']),
      IsActive: serializer.fromJson<bool>(json['IsActive']),
      CreatedAt: serializer.fromJson<DateTime>(json['CreatedAt']),
      ModifiedAt: serializer.fromJson<DateTime?>(json['ModifiedAt']),
      Deleted: serializer.fromJson<bool>(json['Deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'Id': serializer.toJson<int>(Id),
      'Name': serializer.toJson<String>(Name),
      'SnoozeSeconds': serializer.toJson<int>(SnoozeSeconds),
      'IntervalSeconds': serializer.toJson<int>(IntervalSeconds),
      'MaxTimesPerDay': serializer.toJson<int>(MaxTimesPerDay),
      'DayStartSeconds': serializer.toJson<int>(DayStartSeconds),
      'MaxTimesPerDayEnabled': serializer.toJson<bool>(MaxTimesPerDayEnabled),
      'EnabledWeekdays': serializer.toJson<int>(EnabledWeekdays),
      'DriftCompensationTypeCode': serializer.toJson<int>(
        DriftCompensationTypeCode,
      ),
      'ShowPreview': serializer.toJson<bool>(ShowPreview),
      'Vibrate': serializer.toJson<bool>(Vibrate),
      'Volume': serializer.toJson<int>(Volume),
      'FadeIn': serializer.toJson<bool>(FadeIn),
      'AudioUri': serializer.toJson<String?>(AudioUri),
      'IsActive': serializer.toJson<bool>(IsActive),
      'CreatedAt': serializer.toJson<DateTime>(CreatedAt),
      'ModifiedAt': serializer.toJson<DateTime?>(ModifiedAt),
      'Deleted': serializer.toJson<bool>(Deleted),
    };
  }

  RoutineModel copyWith({
    int? Id,
    String? Name,
    int? SnoozeSeconds,
    int? IntervalSeconds,
    int? MaxTimesPerDay,
    int? DayStartSeconds,
    bool? MaxTimesPerDayEnabled,
    int? EnabledWeekdays,
    int? DriftCompensationTypeCode,
    bool? ShowPreview,
    bool? Vibrate,
    int? Volume,
    bool? FadeIn,
    Value<String?> AudioUri = const Value.absent(),
    bool? IsActive,
    DateTime? CreatedAt,
    Value<DateTime?> ModifiedAt = const Value.absent(),
    bool? Deleted,
  }) => RoutineModel(
    Id: Id ?? this.Id,
    Name: Name ?? this.Name,
    SnoozeSeconds: SnoozeSeconds ?? this.SnoozeSeconds,
    IntervalSeconds: IntervalSeconds ?? this.IntervalSeconds,
    MaxTimesPerDay: MaxTimesPerDay ?? this.MaxTimesPerDay,
    DayStartSeconds: DayStartSeconds ?? this.DayStartSeconds,
    MaxTimesPerDayEnabled: MaxTimesPerDayEnabled ?? this.MaxTimesPerDayEnabled,
    EnabledWeekdays: EnabledWeekdays ?? this.EnabledWeekdays,
    DriftCompensationTypeCode:
        DriftCompensationTypeCode ?? this.DriftCompensationTypeCode,
    ShowPreview: ShowPreview ?? this.ShowPreview,
    Vibrate: Vibrate ?? this.Vibrate,
    Volume: Volume ?? this.Volume,
    FadeIn: FadeIn ?? this.FadeIn,
    AudioUri: AudioUri.present ? AudioUri.value : this.AudioUri,
    IsActive: IsActive ?? this.IsActive,
    CreatedAt: CreatedAt ?? this.CreatedAt,
    ModifiedAt: ModifiedAt.present ? ModifiedAt.value : this.ModifiedAt,
    Deleted: Deleted ?? this.Deleted,
  );
  RoutineModel copyWithCompanion(RoutinesCompanion data) {
    return RoutineModel(
      Id: data.Id.present ? data.Id.value : this.Id,
      Name: data.Name.present ? data.Name.value : this.Name,
      SnoozeSeconds: data.SnoozeSeconds.present
          ? data.SnoozeSeconds.value
          : this.SnoozeSeconds,
      IntervalSeconds: data.IntervalSeconds.present
          ? data.IntervalSeconds.value
          : this.IntervalSeconds,
      MaxTimesPerDay: data.MaxTimesPerDay.present
          ? data.MaxTimesPerDay.value
          : this.MaxTimesPerDay,
      DayStartSeconds: data.DayStartSeconds.present
          ? data.DayStartSeconds.value
          : this.DayStartSeconds,
      MaxTimesPerDayEnabled: data.MaxTimesPerDayEnabled.present
          ? data.MaxTimesPerDayEnabled.value
          : this.MaxTimesPerDayEnabled,
      EnabledWeekdays: data.EnabledWeekdays.present
          ? data.EnabledWeekdays.value
          : this.EnabledWeekdays,
      DriftCompensationTypeCode: data.DriftCompensationTypeCode.present
          ? data.DriftCompensationTypeCode.value
          : this.DriftCompensationTypeCode,
      ShowPreview: data.ShowPreview.present
          ? data.ShowPreview.value
          : this.ShowPreview,
      Vibrate: data.Vibrate.present ? data.Vibrate.value : this.Vibrate,
      Volume: data.Volume.present ? data.Volume.value : this.Volume,
      FadeIn: data.FadeIn.present ? data.FadeIn.value : this.FadeIn,
      AudioUri: data.AudioUri.present ? data.AudioUri.value : this.AudioUri,
      IsActive: data.IsActive.present ? data.IsActive.value : this.IsActive,
      CreatedAt: data.CreatedAt.present ? data.CreatedAt.value : this.CreatedAt,
      ModifiedAt: data.ModifiedAt.present
          ? data.ModifiedAt.value
          : this.ModifiedAt,
      Deleted: data.Deleted.present ? data.Deleted.value : this.Deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoutineModel(')
          ..write('Id: $Id, ')
          ..write('Name: $Name, ')
          ..write('SnoozeSeconds: $SnoozeSeconds, ')
          ..write('IntervalSeconds: $IntervalSeconds, ')
          ..write('MaxTimesPerDay: $MaxTimesPerDay, ')
          ..write('DayStartSeconds: $DayStartSeconds, ')
          ..write('MaxTimesPerDayEnabled: $MaxTimesPerDayEnabled, ')
          ..write('EnabledWeekdays: $EnabledWeekdays, ')
          ..write('DriftCompensationTypeCode: $DriftCompensationTypeCode, ')
          ..write('ShowPreview: $ShowPreview, ')
          ..write('Vibrate: $Vibrate, ')
          ..write('Volume: $Volume, ')
          ..write('FadeIn: $FadeIn, ')
          ..write('AudioUri: $AudioUri, ')
          ..write('IsActive: $IsActive, ')
          ..write('CreatedAt: $CreatedAt, ')
          ..write('ModifiedAt: $ModifiedAt, ')
          ..write('Deleted: $Deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    Id,
    Name,
    SnoozeSeconds,
    IntervalSeconds,
    MaxTimesPerDay,
    DayStartSeconds,
    MaxTimesPerDayEnabled,
    EnabledWeekdays,
    DriftCompensationTypeCode,
    ShowPreview,
    Vibrate,
    Volume,
    FadeIn,
    AudioUri,
    IsActive,
    CreatedAt,
    ModifiedAt,
    Deleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoutineModel &&
          other.Id == this.Id &&
          other.Name == this.Name &&
          other.SnoozeSeconds == this.SnoozeSeconds &&
          other.IntervalSeconds == this.IntervalSeconds &&
          other.MaxTimesPerDay == this.MaxTimesPerDay &&
          other.DayStartSeconds == this.DayStartSeconds &&
          other.MaxTimesPerDayEnabled == this.MaxTimesPerDayEnabled &&
          other.EnabledWeekdays == this.EnabledWeekdays &&
          other.DriftCompensationTypeCode == this.DriftCompensationTypeCode &&
          other.ShowPreview == this.ShowPreview &&
          other.Vibrate == this.Vibrate &&
          other.Volume == this.Volume &&
          other.FadeIn == this.FadeIn &&
          other.AudioUri == this.AudioUri &&
          other.IsActive == this.IsActive &&
          other.CreatedAt == this.CreatedAt &&
          other.ModifiedAt == this.ModifiedAt &&
          other.Deleted == this.Deleted);
}

class RoutinesCompanion extends UpdateCompanion<RoutineModel> {
  final Value<int> Id;
  final Value<String> Name;
  final Value<int> SnoozeSeconds;
  final Value<int> IntervalSeconds;
  final Value<int> MaxTimesPerDay;
  final Value<int> DayStartSeconds;
  final Value<bool> MaxTimesPerDayEnabled;
  final Value<int> EnabledWeekdays;
  final Value<int> DriftCompensationTypeCode;
  final Value<bool> ShowPreview;
  final Value<bool> Vibrate;
  final Value<int> Volume;
  final Value<bool> FadeIn;
  final Value<String?> AudioUri;
  final Value<bool> IsActive;
  final Value<DateTime> CreatedAt;
  final Value<DateTime?> ModifiedAt;
  final Value<bool> Deleted;
  const RoutinesCompanion({
    this.Id = const Value.absent(),
    this.Name = const Value.absent(),
    this.SnoozeSeconds = const Value.absent(),
    this.IntervalSeconds = const Value.absent(),
    this.MaxTimesPerDay = const Value.absent(),
    this.DayStartSeconds = const Value.absent(),
    this.MaxTimesPerDayEnabled = const Value.absent(),
    this.EnabledWeekdays = const Value.absent(),
    this.DriftCompensationTypeCode = const Value.absent(),
    this.ShowPreview = const Value.absent(),
    this.Vibrate = const Value.absent(),
    this.Volume = const Value.absent(),
    this.FadeIn = const Value.absent(),
    this.AudioUri = const Value.absent(),
    this.IsActive = const Value.absent(),
    this.CreatedAt = const Value.absent(),
    this.ModifiedAt = const Value.absent(),
    this.Deleted = const Value.absent(),
  });
  RoutinesCompanion.insert({
    this.Id = const Value.absent(),
    required String Name,
    this.SnoozeSeconds = const Value.absent(),
    required int IntervalSeconds,
    this.MaxTimesPerDay = const Value.absent(),
    this.DayStartSeconds = const Value.absent(),
    this.MaxTimesPerDayEnabled = const Value.absent(),
    this.EnabledWeekdays = const Value.absent(),
    required int DriftCompensationTypeCode,
    this.ShowPreview = const Value.absent(),
    this.Vibrate = const Value.absent(),
    this.Volume = const Value.absent(),
    this.FadeIn = const Value.absent(),
    this.AudioUri = const Value.absent(),
    this.IsActive = const Value.absent(),
    this.CreatedAt = const Value.absent(),
    this.ModifiedAt = const Value.absent(),
    this.Deleted = const Value.absent(),
  }) : Name = Value(Name),
       IntervalSeconds = Value(IntervalSeconds),
       DriftCompensationTypeCode = Value(DriftCompensationTypeCode);
  static Insertable<RoutineModel> custom({
    Expression<int>? Id,
    Expression<String>? Name,
    Expression<int>? SnoozeSeconds,
    Expression<int>? IntervalSeconds,
    Expression<int>? MaxTimesPerDay,
    Expression<int>? DayStartSeconds,
    Expression<bool>? MaxTimesPerDayEnabled,
    Expression<int>? EnabledWeekdays,
    Expression<int>? DriftCompensationTypeCode,
    Expression<bool>? ShowPreview,
    Expression<bool>? Vibrate,
    Expression<int>? Volume,
    Expression<bool>? FadeIn,
    Expression<String>? AudioUri,
    Expression<bool>? IsActive,
    Expression<DateTime>? CreatedAt,
    Expression<DateTime>? ModifiedAt,
    Expression<bool>? Deleted,
  }) {
    return RawValuesInsertable({
      if (Id != null) 'id': Id,
      if (Name != null) 'name': Name,
      if (SnoozeSeconds != null) 'snooze_seconds': SnoozeSeconds,
      if (IntervalSeconds != null) 'interval_seconds': IntervalSeconds,
      if (MaxTimesPerDay != null) 'max_times_per_day': MaxTimesPerDay,
      if (DayStartSeconds != null) 'day_start_seconds': DayStartSeconds,
      if (MaxTimesPerDayEnabled != null)
        'max_times_per_day_enabled': MaxTimesPerDayEnabled,
      if (EnabledWeekdays != null) 'enabled_weekdays': EnabledWeekdays,
      if (DriftCompensationTypeCode != null)
        'drift_compensation_type_code': DriftCompensationTypeCode,
      if (ShowPreview != null) 'show_preview': ShowPreview,
      if (Vibrate != null) 'vibrate': Vibrate,
      if (Volume != null) 'volume': Volume,
      if (FadeIn != null) 'fade_in': FadeIn,
      if (AudioUri != null) 'audio_uri': AudioUri,
      if (IsActive != null) 'is_active': IsActive,
      if (CreatedAt != null) 'created_at': CreatedAt,
      if (ModifiedAt != null) 'modified_at': ModifiedAt,
      if (Deleted != null) 'deleted': Deleted,
    });
  }

  RoutinesCompanion copyWith({
    Value<int>? Id,
    Value<String>? Name,
    Value<int>? SnoozeSeconds,
    Value<int>? IntervalSeconds,
    Value<int>? MaxTimesPerDay,
    Value<int>? DayStartSeconds,
    Value<bool>? MaxTimesPerDayEnabled,
    Value<int>? EnabledWeekdays,
    Value<int>? DriftCompensationTypeCode,
    Value<bool>? ShowPreview,
    Value<bool>? Vibrate,
    Value<int>? Volume,
    Value<bool>? FadeIn,
    Value<String?>? AudioUri,
    Value<bool>? IsActive,
    Value<DateTime>? CreatedAt,
    Value<DateTime?>? ModifiedAt,
    Value<bool>? Deleted,
  }) {
    return RoutinesCompanion(
      Id: Id ?? this.Id,
      Name: Name ?? this.Name,
      SnoozeSeconds: SnoozeSeconds ?? this.SnoozeSeconds,
      IntervalSeconds: IntervalSeconds ?? this.IntervalSeconds,
      MaxTimesPerDay: MaxTimesPerDay ?? this.MaxTimesPerDay,
      DayStartSeconds: DayStartSeconds ?? this.DayStartSeconds,
      MaxTimesPerDayEnabled:
          MaxTimesPerDayEnabled ?? this.MaxTimesPerDayEnabled,
      EnabledWeekdays: EnabledWeekdays ?? this.EnabledWeekdays,
      DriftCompensationTypeCode:
          DriftCompensationTypeCode ?? this.DriftCompensationTypeCode,
      ShowPreview: ShowPreview ?? this.ShowPreview,
      Vibrate: Vibrate ?? this.Vibrate,
      Volume: Volume ?? this.Volume,
      FadeIn: FadeIn ?? this.FadeIn,
      AudioUri: AudioUri ?? this.AudioUri,
      IsActive: IsActive ?? this.IsActive,
      CreatedAt: CreatedAt ?? this.CreatedAt,
      ModifiedAt: ModifiedAt ?? this.ModifiedAt,
      Deleted: Deleted ?? this.Deleted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (Id.present) {
      map['id'] = Variable<int>(Id.value);
    }
    if (Name.present) {
      map['name'] = Variable<String>(Name.value);
    }
    if (SnoozeSeconds.present) {
      map['snooze_seconds'] = Variable<int>(SnoozeSeconds.value);
    }
    if (IntervalSeconds.present) {
      map['interval_seconds'] = Variable<int>(IntervalSeconds.value);
    }
    if (MaxTimesPerDay.present) {
      map['max_times_per_day'] = Variable<int>(MaxTimesPerDay.value);
    }
    if (DayStartSeconds.present) {
      map['day_start_seconds'] = Variable<int>(DayStartSeconds.value);
    }
    if (MaxTimesPerDayEnabled.present) {
      map['max_times_per_day_enabled'] = Variable<bool>(
        MaxTimesPerDayEnabled.value,
      );
    }
    if (EnabledWeekdays.present) {
      map['enabled_weekdays'] = Variable<int>(EnabledWeekdays.value);
    }
    if (DriftCompensationTypeCode.present) {
      map['drift_compensation_type_code'] = Variable<int>(
        DriftCompensationTypeCode.value,
      );
    }
    if (ShowPreview.present) {
      map['show_preview'] = Variable<bool>(ShowPreview.value);
    }
    if (Vibrate.present) {
      map['vibrate'] = Variable<bool>(Vibrate.value);
    }
    if (Volume.present) {
      map['volume'] = Variable<int>(Volume.value);
    }
    if (FadeIn.present) {
      map['fade_in'] = Variable<bool>(FadeIn.value);
    }
    if (AudioUri.present) {
      map['audio_uri'] = Variable<String>(AudioUri.value);
    }
    if (IsActive.present) {
      map['is_active'] = Variable<bool>(IsActive.value);
    }
    if (CreatedAt.present) {
      map['created_at'] = Variable<DateTime>(CreatedAt.value);
    }
    if (ModifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(ModifiedAt.value);
    }
    if (Deleted.present) {
      map['deleted'] = Variable<bool>(Deleted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoutinesCompanion(')
          ..write('Id: $Id, ')
          ..write('Name: $Name, ')
          ..write('SnoozeSeconds: $SnoozeSeconds, ')
          ..write('IntervalSeconds: $IntervalSeconds, ')
          ..write('MaxTimesPerDay: $MaxTimesPerDay, ')
          ..write('DayStartSeconds: $DayStartSeconds, ')
          ..write('MaxTimesPerDayEnabled: $MaxTimesPerDayEnabled, ')
          ..write('EnabledWeekdays: $EnabledWeekdays, ')
          ..write('DriftCompensationTypeCode: $DriftCompensationTypeCode, ')
          ..write('ShowPreview: $ShowPreview, ')
          ..write('Vibrate: $Vibrate, ')
          ..write('Volume: $Volume, ')
          ..write('FadeIn: $FadeIn, ')
          ..write('AudioUri: $AudioUri, ')
          ..write('IsActive: $IsActive, ')
          ..write('CreatedAt: $CreatedAt, ')
          ..write('ModifiedAt: $ModifiedAt, ')
          ..write('Deleted: $Deleted')
          ..write(')'))
        .toString();
  }
}

class $RoutineStatesTable extends RoutineStates
    with TableInfo<$RoutineStatesTable, RoutineStateModel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoutineStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _IdMeta = const VerificationMeta('Id');
  @override
  late final GeneratedColumn<int> Id = GeneratedColumn<int>(
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
  static const VerificationMeta _RoutineIdMeta = const VerificationMeta(
    'RoutineId',
  );
  @override
  late final GeneratedColumn<int> RoutineId = GeneratedColumn<int>(
    'routine_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _NextTriggerTimeMeta = const VerificationMeta(
    'NextTriggerTime',
  );
  @override
  late final GeneratedColumn<DateTime> NextTriggerTime =
      GeneratedColumn<DateTime>(
        'next_trigger_time',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _InitialRingTimeMeta = const VerificationMeta(
    'InitialRingTime',
  );
  @override
  late final GeneratedColumn<DateTime> InitialRingTime =
      GeneratedColumn<DateTime>(
        'initial_ring_time',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _CurrentSnoozeCountMeta =
      const VerificationMeta('CurrentSnoozeCount');
  @override
  late final GeneratedColumn<int> CurrentSnoozeCount = GeneratedColumn<int>(
    'current_snooze_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _TimesRingTodayMeta = const VerificationMeta(
    'TimesRingToday',
  );
  @override
  late final GeneratedColumn<int> TimesRingToday = GeneratedColumn<int>(
    'times_ring_today',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _TimesRingDayMeta = const VerificationMeta(
    'TimesRingDay',
  );
  @override
  late final GeneratedColumn<DateTime> TimesRingDay = GeneratedColumn<DateTime>(
    'times_ring_day',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ExtraMaxTimesTodayMeta =
      const VerificationMeta('ExtraMaxTimesToday');
  @override
  late final GeneratedColumn<int> ExtraMaxTimesToday = GeneratedColumn<int>(
    'extra_max_times_today',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _IsRingingMeta = const VerificationMeta(
    'IsRinging',
  );
  @override
  late final GeneratedColumn<bool> IsRinging = GeneratedColumn<bool>(
    'is_ringing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_ringing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _LastDismissedAtMeta = const VerificationMeta(
    'LastDismissedAt',
  );
  @override
  late final GeneratedColumn<DateTime> LastDismissedAt =
      GeneratedColumn<DateTime>(
        'last_dismissed_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _PausedAtMeta = const VerificationMeta(
    'PausedAt',
  );
  @override
  late final GeneratedColumn<DateTime> PausedAt = GeneratedColumn<DateTime>(
    'paused_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _MutedAtMeta = const VerificationMeta(
    'MutedAt',
  );
  @override
  late final GeneratedColumn<DateTime> MutedAt = GeneratedColumn<DateTime>(
    'muted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _CreatedAtMeta = const VerificationMeta(
    'CreatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> CreatedAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _ModifiedAtMeta = const VerificationMeta(
    'ModifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> ModifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _DeletedMeta = const VerificationMeta(
    'Deleted',
  );
  @override
  late final GeneratedColumn<bool> Deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    Id,
    RoutineId,
    NextTriggerTime,
    InitialRingTime,
    CurrentSnoozeCount,
    TimesRingToday,
    TimesRingDay,
    ExtraMaxTimesToday,
    IsRinging,
    LastDismissedAt,
    PausedAt,
    MutedAt,
    CreatedAt,
    ModifiedAt,
    Deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'routine_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoutineStateModel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_IdMeta, Id.isAcceptableOrUnknown(data['id']!, _IdMeta));
    }
    if (data.containsKey('routine_id')) {
      context.handle(
        _RoutineIdMeta,
        RoutineId.isAcceptableOrUnknown(data['routine_id']!, _RoutineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_RoutineIdMeta);
    }
    if (data.containsKey('next_trigger_time')) {
      context.handle(
        _NextTriggerTimeMeta,
        NextTriggerTime.isAcceptableOrUnknown(
          data['next_trigger_time']!,
          _NextTriggerTimeMeta,
        ),
      );
    }
    if (data.containsKey('initial_ring_time')) {
      context.handle(
        _InitialRingTimeMeta,
        InitialRingTime.isAcceptableOrUnknown(
          data['initial_ring_time']!,
          _InitialRingTimeMeta,
        ),
      );
    }
    if (data.containsKey('current_snooze_count')) {
      context.handle(
        _CurrentSnoozeCountMeta,
        CurrentSnoozeCount.isAcceptableOrUnknown(
          data['current_snooze_count']!,
          _CurrentSnoozeCountMeta,
        ),
      );
    }
    if (data.containsKey('times_ring_today')) {
      context.handle(
        _TimesRingTodayMeta,
        TimesRingToday.isAcceptableOrUnknown(
          data['times_ring_today']!,
          _TimesRingTodayMeta,
        ),
      );
    }
    if (data.containsKey('times_ring_day')) {
      context.handle(
        _TimesRingDayMeta,
        TimesRingDay.isAcceptableOrUnknown(
          data['times_ring_day']!,
          _TimesRingDayMeta,
        ),
      );
    }
    if (data.containsKey('extra_max_times_today')) {
      context.handle(
        _ExtraMaxTimesTodayMeta,
        ExtraMaxTimesToday.isAcceptableOrUnknown(
          data['extra_max_times_today']!,
          _ExtraMaxTimesTodayMeta,
        ),
      );
    }
    if (data.containsKey('is_ringing')) {
      context.handle(
        _IsRingingMeta,
        IsRinging.isAcceptableOrUnknown(data['is_ringing']!, _IsRingingMeta),
      );
    }
    if (data.containsKey('last_dismissed_at')) {
      context.handle(
        _LastDismissedAtMeta,
        LastDismissedAt.isAcceptableOrUnknown(
          data['last_dismissed_at']!,
          _LastDismissedAtMeta,
        ),
      );
    }
    if (data.containsKey('paused_at')) {
      context.handle(
        _PausedAtMeta,
        PausedAt.isAcceptableOrUnknown(data['paused_at']!, _PausedAtMeta),
      );
    }
    if (data.containsKey('muted_at')) {
      context.handle(
        _MutedAtMeta,
        MutedAt.isAcceptableOrUnknown(data['muted_at']!, _MutedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _CreatedAtMeta,
        CreatedAt.isAcceptableOrUnknown(data['created_at']!, _CreatedAtMeta),
      );
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _ModifiedAtMeta,
        ModifiedAt.isAcceptableOrUnknown(data['modified_at']!, _ModifiedAtMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _DeletedMeta,
        Deleted.isAcceptableOrUnknown(data['deleted']!, _DeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {Id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {RoutineId},
  ];
  @override
  RoutineStateModel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoutineStateModel(
      Id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      RoutineId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}routine_id'],
      )!,
      NextTriggerTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_trigger_time'],
      ),
      InitialRingTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}initial_ring_time'],
      ),
      CurrentSnoozeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_snooze_count'],
      )!,
      TimesRingToday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}times_ring_today'],
      )!,
      TimesRingDay: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}times_ring_day'],
      ),
      ExtraMaxTimesToday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}extra_max_times_today'],
      )!,
      IsRinging: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_ringing'],
      )!,
      LastDismissedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_dismissed_at'],
      ),
      PausedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paused_at'],
      ),
      MutedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}muted_at'],
      ),
      CreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      ModifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      ),
      Deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
    );
  }

  @override
  $RoutineStatesTable createAlias(String alias) {
    return $RoutineStatesTable(attachedDatabase, alias);
  }
}

class RoutineStateModel extends DataClass
    implements Insertable<RoutineStateModel> {
  final int Id;
  final int RoutineId;
  final DateTime? NextTriggerTime;
  final DateTime? InitialRingTime;
  final int CurrentSnoozeCount;

  /// Fresh rings that counted toward [Routines.MaxTimesPerDay] for [TimesRingDay].
  final int TimesRingToday;

  /// Start of the day period that [TimesRingToday] applies to.
  final DateTime? TimesRingDay;

  /// Bonus daily cap additions for the current [TimesRingDay].
  final int ExtraMaxTimesToday;
  final bool IsRinging;
  final DateTime? LastDismissedAt;

  /// When set, the routine is paused: countdown freezes at
  /// [NextTriggerTime] minus this instant until resume.
  final DateTime? PausedAt;

  /// When set, the routine is muted: schedule continues but fires are
  /// silently auto-dismissed and still count toward [TimesRingToday].
  final DateTime? MutedAt;
  final DateTime CreatedAt;
  final DateTime? ModifiedAt;
  final bool Deleted;
  const RoutineStateModel({
    required this.Id,
    required this.RoutineId,
    this.NextTriggerTime,
    this.InitialRingTime,
    required this.CurrentSnoozeCount,
    required this.TimesRingToday,
    this.TimesRingDay,
    required this.ExtraMaxTimesToday,
    required this.IsRinging,
    this.LastDismissedAt,
    this.PausedAt,
    this.MutedAt,
    required this.CreatedAt,
    this.ModifiedAt,
    required this.Deleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(Id);
    map['routine_id'] = Variable<int>(RoutineId);
    if (!nullToAbsent || NextTriggerTime != null) {
      map['next_trigger_time'] = Variable<DateTime>(NextTriggerTime);
    }
    if (!nullToAbsent || InitialRingTime != null) {
      map['initial_ring_time'] = Variable<DateTime>(InitialRingTime);
    }
    map['current_snooze_count'] = Variable<int>(CurrentSnoozeCount);
    map['times_ring_today'] = Variable<int>(TimesRingToday);
    if (!nullToAbsent || TimesRingDay != null) {
      map['times_ring_day'] = Variable<DateTime>(TimesRingDay);
    }
    map['extra_max_times_today'] = Variable<int>(ExtraMaxTimesToday);
    map['is_ringing'] = Variable<bool>(IsRinging);
    if (!nullToAbsent || LastDismissedAt != null) {
      map['last_dismissed_at'] = Variable<DateTime>(LastDismissedAt);
    }
    if (!nullToAbsent || PausedAt != null) {
      map['paused_at'] = Variable<DateTime>(PausedAt);
    }
    if (!nullToAbsent || MutedAt != null) {
      map['muted_at'] = Variable<DateTime>(MutedAt);
    }
    map['created_at'] = Variable<DateTime>(CreatedAt);
    if (!nullToAbsent || ModifiedAt != null) {
      map['modified_at'] = Variable<DateTime>(ModifiedAt);
    }
    map['deleted'] = Variable<bool>(Deleted);
    return map;
  }

  RoutineStatesCompanion toCompanion(bool nullToAbsent) {
    return RoutineStatesCompanion(
      Id: Value(Id),
      RoutineId: Value(RoutineId),
      NextTriggerTime: NextTriggerTime == null && nullToAbsent
          ? const Value.absent()
          : Value(NextTriggerTime),
      InitialRingTime: InitialRingTime == null && nullToAbsent
          ? const Value.absent()
          : Value(InitialRingTime),
      CurrentSnoozeCount: Value(CurrentSnoozeCount),
      TimesRingToday: Value(TimesRingToday),
      TimesRingDay: TimesRingDay == null && nullToAbsent
          ? const Value.absent()
          : Value(TimesRingDay),
      ExtraMaxTimesToday: Value(ExtraMaxTimesToday),
      IsRinging: Value(IsRinging),
      LastDismissedAt: LastDismissedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(LastDismissedAt),
      PausedAt: PausedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(PausedAt),
      MutedAt: MutedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(MutedAt),
      CreatedAt: Value(CreatedAt),
      ModifiedAt: ModifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(ModifiedAt),
      Deleted: Value(Deleted),
    );
  }

  factory RoutineStateModel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoutineStateModel(
      Id: serializer.fromJson<int>(json['Id']),
      RoutineId: serializer.fromJson<int>(json['RoutineId']),
      NextTriggerTime: serializer.fromJson<DateTime?>(json['NextTriggerTime']),
      InitialRingTime: serializer.fromJson<DateTime?>(json['InitialRingTime']),
      CurrentSnoozeCount: serializer.fromJson<int>(json['CurrentSnoozeCount']),
      TimesRingToday: serializer.fromJson<int>(json['TimesRingToday']),
      TimesRingDay: serializer.fromJson<DateTime?>(json['TimesRingDay']),
      ExtraMaxTimesToday: serializer.fromJson<int>(json['ExtraMaxTimesToday']),
      IsRinging: serializer.fromJson<bool>(json['IsRinging']),
      LastDismissedAt: serializer.fromJson<DateTime?>(json['LastDismissedAt']),
      PausedAt: serializer.fromJson<DateTime?>(json['PausedAt']),
      MutedAt: serializer.fromJson<DateTime?>(json['MutedAt']),
      CreatedAt: serializer.fromJson<DateTime>(json['CreatedAt']),
      ModifiedAt: serializer.fromJson<DateTime?>(json['ModifiedAt']),
      Deleted: serializer.fromJson<bool>(json['Deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'Id': serializer.toJson<int>(Id),
      'RoutineId': serializer.toJson<int>(RoutineId),
      'NextTriggerTime': serializer.toJson<DateTime?>(NextTriggerTime),
      'InitialRingTime': serializer.toJson<DateTime?>(InitialRingTime),
      'CurrentSnoozeCount': serializer.toJson<int>(CurrentSnoozeCount),
      'TimesRingToday': serializer.toJson<int>(TimesRingToday),
      'TimesRingDay': serializer.toJson<DateTime?>(TimesRingDay),
      'ExtraMaxTimesToday': serializer.toJson<int>(ExtraMaxTimesToday),
      'IsRinging': serializer.toJson<bool>(IsRinging),
      'LastDismissedAt': serializer.toJson<DateTime?>(LastDismissedAt),
      'PausedAt': serializer.toJson<DateTime?>(PausedAt),
      'MutedAt': serializer.toJson<DateTime?>(MutedAt),
      'CreatedAt': serializer.toJson<DateTime>(CreatedAt),
      'ModifiedAt': serializer.toJson<DateTime?>(ModifiedAt),
      'Deleted': serializer.toJson<bool>(Deleted),
    };
  }

  RoutineStateModel copyWith({
    int? Id,
    int? RoutineId,
    Value<DateTime?> NextTriggerTime = const Value.absent(),
    Value<DateTime?> InitialRingTime = const Value.absent(),
    int? CurrentSnoozeCount,
    int? TimesRingToday,
    Value<DateTime?> TimesRingDay = const Value.absent(),
    int? ExtraMaxTimesToday,
    bool? IsRinging,
    Value<DateTime?> LastDismissedAt = const Value.absent(),
    Value<DateTime?> PausedAt = const Value.absent(),
    Value<DateTime?> MutedAt = const Value.absent(),
    DateTime? CreatedAt,
    Value<DateTime?> ModifiedAt = const Value.absent(),
    bool? Deleted,
  }) => RoutineStateModel(
    Id: Id ?? this.Id,
    RoutineId: RoutineId ?? this.RoutineId,
    NextTriggerTime: NextTriggerTime.present
        ? NextTriggerTime.value
        : this.NextTriggerTime,
    InitialRingTime: InitialRingTime.present
        ? InitialRingTime.value
        : this.InitialRingTime,
    CurrentSnoozeCount: CurrentSnoozeCount ?? this.CurrentSnoozeCount,
    TimesRingToday: TimesRingToday ?? this.TimesRingToday,
    TimesRingDay: TimesRingDay.present ? TimesRingDay.value : this.TimesRingDay,
    ExtraMaxTimesToday: ExtraMaxTimesToday ?? this.ExtraMaxTimesToday,
    IsRinging: IsRinging ?? this.IsRinging,
    LastDismissedAt: LastDismissedAt.present
        ? LastDismissedAt.value
        : this.LastDismissedAt,
    PausedAt: PausedAt.present ? PausedAt.value : this.PausedAt,
    MutedAt: MutedAt.present ? MutedAt.value : this.MutedAt,
    CreatedAt: CreatedAt ?? this.CreatedAt,
    ModifiedAt: ModifiedAt.present ? ModifiedAt.value : this.ModifiedAt,
    Deleted: Deleted ?? this.Deleted,
  );
  RoutineStateModel copyWithCompanion(RoutineStatesCompanion data) {
    return RoutineStateModel(
      Id: data.Id.present ? data.Id.value : this.Id,
      RoutineId: data.RoutineId.present ? data.RoutineId.value : this.RoutineId,
      NextTriggerTime: data.NextTriggerTime.present
          ? data.NextTriggerTime.value
          : this.NextTriggerTime,
      InitialRingTime: data.InitialRingTime.present
          ? data.InitialRingTime.value
          : this.InitialRingTime,
      CurrentSnoozeCount: data.CurrentSnoozeCount.present
          ? data.CurrentSnoozeCount.value
          : this.CurrentSnoozeCount,
      TimesRingToday: data.TimesRingToday.present
          ? data.TimesRingToday.value
          : this.TimesRingToday,
      TimesRingDay: data.TimesRingDay.present
          ? data.TimesRingDay.value
          : this.TimesRingDay,
      ExtraMaxTimesToday: data.ExtraMaxTimesToday.present
          ? data.ExtraMaxTimesToday.value
          : this.ExtraMaxTimesToday,
      IsRinging: data.IsRinging.present ? data.IsRinging.value : this.IsRinging,
      LastDismissedAt: data.LastDismissedAt.present
          ? data.LastDismissedAt.value
          : this.LastDismissedAt,
      PausedAt: data.PausedAt.present ? data.PausedAt.value : this.PausedAt,
      MutedAt: data.MutedAt.present ? data.MutedAt.value : this.MutedAt,
      CreatedAt: data.CreatedAt.present ? data.CreatedAt.value : this.CreatedAt,
      ModifiedAt: data.ModifiedAt.present
          ? data.ModifiedAt.value
          : this.ModifiedAt,
      Deleted: data.Deleted.present ? data.Deleted.value : this.Deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoutineStateModel(')
          ..write('Id: $Id, ')
          ..write('RoutineId: $RoutineId, ')
          ..write('NextTriggerTime: $NextTriggerTime, ')
          ..write('InitialRingTime: $InitialRingTime, ')
          ..write('CurrentSnoozeCount: $CurrentSnoozeCount, ')
          ..write('TimesRingToday: $TimesRingToday, ')
          ..write('TimesRingDay: $TimesRingDay, ')
          ..write('ExtraMaxTimesToday: $ExtraMaxTimesToday, ')
          ..write('IsRinging: $IsRinging, ')
          ..write('LastDismissedAt: $LastDismissedAt, ')
          ..write('PausedAt: $PausedAt, ')
          ..write('MutedAt: $MutedAt, ')
          ..write('CreatedAt: $CreatedAt, ')
          ..write('ModifiedAt: $ModifiedAt, ')
          ..write('Deleted: $Deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    Id,
    RoutineId,
    NextTriggerTime,
    InitialRingTime,
    CurrentSnoozeCount,
    TimesRingToday,
    TimesRingDay,
    ExtraMaxTimesToday,
    IsRinging,
    LastDismissedAt,
    PausedAt,
    MutedAt,
    CreatedAt,
    ModifiedAt,
    Deleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoutineStateModel &&
          other.Id == this.Id &&
          other.RoutineId == this.RoutineId &&
          other.NextTriggerTime == this.NextTriggerTime &&
          other.InitialRingTime == this.InitialRingTime &&
          other.CurrentSnoozeCount == this.CurrentSnoozeCount &&
          other.TimesRingToday == this.TimesRingToday &&
          other.TimesRingDay == this.TimesRingDay &&
          other.ExtraMaxTimesToday == this.ExtraMaxTimesToday &&
          other.IsRinging == this.IsRinging &&
          other.LastDismissedAt == this.LastDismissedAt &&
          other.PausedAt == this.PausedAt &&
          other.MutedAt == this.MutedAt &&
          other.CreatedAt == this.CreatedAt &&
          other.ModifiedAt == this.ModifiedAt &&
          other.Deleted == this.Deleted);
}

class RoutineStatesCompanion extends UpdateCompanion<RoutineStateModel> {
  final Value<int> Id;
  final Value<int> RoutineId;
  final Value<DateTime?> NextTriggerTime;
  final Value<DateTime?> InitialRingTime;
  final Value<int> CurrentSnoozeCount;
  final Value<int> TimesRingToday;
  final Value<DateTime?> TimesRingDay;
  final Value<int> ExtraMaxTimesToday;
  final Value<bool> IsRinging;
  final Value<DateTime?> LastDismissedAt;
  final Value<DateTime?> PausedAt;
  final Value<DateTime?> MutedAt;
  final Value<DateTime> CreatedAt;
  final Value<DateTime?> ModifiedAt;
  final Value<bool> Deleted;
  const RoutineStatesCompanion({
    this.Id = const Value.absent(),
    this.RoutineId = const Value.absent(),
    this.NextTriggerTime = const Value.absent(),
    this.InitialRingTime = const Value.absent(),
    this.CurrentSnoozeCount = const Value.absent(),
    this.TimesRingToday = const Value.absent(),
    this.TimesRingDay = const Value.absent(),
    this.ExtraMaxTimesToday = const Value.absent(),
    this.IsRinging = const Value.absent(),
    this.LastDismissedAt = const Value.absent(),
    this.PausedAt = const Value.absent(),
    this.MutedAt = const Value.absent(),
    this.CreatedAt = const Value.absent(),
    this.ModifiedAt = const Value.absent(),
    this.Deleted = const Value.absent(),
  });
  RoutineStatesCompanion.insert({
    this.Id = const Value.absent(),
    required int RoutineId,
    this.NextTriggerTime = const Value.absent(),
    this.InitialRingTime = const Value.absent(),
    this.CurrentSnoozeCount = const Value.absent(),
    this.TimesRingToday = const Value.absent(),
    this.TimesRingDay = const Value.absent(),
    this.ExtraMaxTimesToday = const Value.absent(),
    this.IsRinging = const Value.absent(),
    this.LastDismissedAt = const Value.absent(),
    this.PausedAt = const Value.absent(),
    this.MutedAt = const Value.absent(),
    this.CreatedAt = const Value.absent(),
    this.ModifiedAt = const Value.absent(),
    this.Deleted = const Value.absent(),
  }) : RoutineId = Value(RoutineId);
  static Insertable<RoutineStateModel> custom({
    Expression<int>? Id,
    Expression<int>? RoutineId,
    Expression<DateTime>? NextTriggerTime,
    Expression<DateTime>? InitialRingTime,
    Expression<int>? CurrentSnoozeCount,
    Expression<int>? TimesRingToday,
    Expression<DateTime>? TimesRingDay,
    Expression<int>? ExtraMaxTimesToday,
    Expression<bool>? IsRinging,
    Expression<DateTime>? LastDismissedAt,
    Expression<DateTime>? PausedAt,
    Expression<DateTime>? MutedAt,
    Expression<DateTime>? CreatedAt,
    Expression<DateTime>? ModifiedAt,
    Expression<bool>? Deleted,
  }) {
    return RawValuesInsertable({
      if (Id != null) 'id': Id,
      if (RoutineId != null) 'routine_id': RoutineId,
      if (NextTriggerTime != null) 'next_trigger_time': NextTriggerTime,
      if (InitialRingTime != null) 'initial_ring_time': InitialRingTime,
      if (CurrentSnoozeCount != null)
        'current_snooze_count': CurrentSnoozeCount,
      if (TimesRingToday != null) 'times_ring_today': TimesRingToday,
      if (TimesRingDay != null) 'times_ring_day': TimesRingDay,
      if (ExtraMaxTimesToday != null)
        'extra_max_times_today': ExtraMaxTimesToday,
      if (IsRinging != null) 'is_ringing': IsRinging,
      if (LastDismissedAt != null) 'last_dismissed_at': LastDismissedAt,
      if (PausedAt != null) 'paused_at': PausedAt,
      if (MutedAt != null) 'muted_at': MutedAt,
      if (CreatedAt != null) 'created_at': CreatedAt,
      if (ModifiedAt != null) 'modified_at': ModifiedAt,
      if (Deleted != null) 'deleted': Deleted,
    });
  }

  RoutineStatesCompanion copyWith({
    Value<int>? Id,
    Value<int>? RoutineId,
    Value<DateTime?>? NextTriggerTime,
    Value<DateTime?>? InitialRingTime,
    Value<int>? CurrentSnoozeCount,
    Value<int>? TimesRingToday,
    Value<DateTime?>? TimesRingDay,
    Value<int>? ExtraMaxTimesToday,
    Value<bool>? IsRinging,
    Value<DateTime?>? LastDismissedAt,
    Value<DateTime?>? PausedAt,
    Value<DateTime?>? MutedAt,
    Value<DateTime>? CreatedAt,
    Value<DateTime?>? ModifiedAt,
    Value<bool>? Deleted,
  }) {
    return RoutineStatesCompanion(
      Id: Id ?? this.Id,
      RoutineId: RoutineId ?? this.RoutineId,
      NextTriggerTime: NextTriggerTime ?? this.NextTriggerTime,
      InitialRingTime: InitialRingTime ?? this.InitialRingTime,
      CurrentSnoozeCount: CurrentSnoozeCount ?? this.CurrentSnoozeCount,
      TimesRingToday: TimesRingToday ?? this.TimesRingToday,
      TimesRingDay: TimesRingDay ?? this.TimesRingDay,
      ExtraMaxTimesToday: ExtraMaxTimesToday ?? this.ExtraMaxTimesToday,
      IsRinging: IsRinging ?? this.IsRinging,
      LastDismissedAt: LastDismissedAt ?? this.LastDismissedAt,
      PausedAt: PausedAt ?? this.PausedAt,
      MutedAt: MutedAt ?? this.MutedAt,
      CreatedAt: CreatedAt ?? this.CreatedAt,
      ModifiedAt: ModifiedAt ?? this.ModifiedAt,
      Deleted: Deleted ?? this.Deleted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (Id.present) {
      map['id'] = Variable<int>(Id.value);
    }
    if (RoutineId.present) {
      map['routine_id'] = Variable<int>(RoutineId.value);
    }
    if (NextTriggerTime.present) {
      map['next_trigger_time'] = Variable<DateTime>(NextTriggerTime.value);
    }
    if (InitialRingTime.present) {
      map['initial_ring_time'] = Variable<DateTime>(InitialRingTime.value);
    }
    if (CurrentSnoozeCount.present) {
      map['current_snooze_count'] = Variable<int>(CurrentSnoozeCount.value);
    }
    if (TimesRingToday.present) {
      map['times_ring_today'] = Variable<int>(TimesRingToday.value);
    }
    if (TimesRingDay.present) {
      map['times_ring_day'] = Variable<DateTime>(TimesRingDay.value);
    }
    if (ExtraMaxTimesToday.present) {
      map['extra_max_times_today'] = Variable<int>(ExtraMaxTimesToday.value);
    }
    if (IsRinging.present) {
      map['is_ringing'] = Variable<bool>(IsRinging.value);
    }
    if (LastDismissedAt.present) {
      map['last_dismissed_at'] = Variable<DateTime>(LastDismissedAt.value);
    }
    if (PausedAt.present) {
      map['paused_at'] = Variable<DateTime>(PausedAt.value);
    }
    if (MutedAt.present) {
      map['muted_at'] = Variable<DateTime>(MutedAt.value);
    }
    if (CreatedAt.present) {
      map['created_at'] = Variable<DateTime>(CreatedAt.value);
    }
    if (ModifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(ModifiedAt.value);
    }
    if (Deleted.present) {
      map['deleted'] = Variable<bool>(Deleted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoutineStatesCompanion(')
          ..write('Id: $Id, ')
          ..write('RoutineId: $RoutineId, ')
          ..write('NextTriggerTime: $NextTriggerTime, ')
          ..write('InitialRingTime: $InitialRingTime, ')
          ..write('CurrentSnoozeCount: $CurrentSnoozeCount, ')
          ..write('TimesRingToday: $TimesRingToday, ')
          ..write('TimesRingDay: $TimesRingDay, ')
          ..write('ExtraMaxTimesToday: $ExtraMaxTimesToday, ')
          ..write('IsRinging: $IsRinging, ')
          ..write('LastDismissedAt: $LastDismissedAt, ')
          ..write('PausedAt: $PausedAt, ')
          ..write('MutedAt: $MutedAt, ')
          ..write('CreatedAt: $CreatedAt, ')
          ..write('ModifiedAt: $ModifiedAt, ')
          ..write('Deleted: $Deleted')
          ..write(')'))
        .toString();
  }
}

class $LogEntriesTable extends LogEntries
    with TableInfo<$LogEntriesTable, LogEntryModel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LogEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _IdMeta = const VerificationMeta('Id');
  @override
  late final GeneratedColumn<int> Id = GeneratedColumn<int>(
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
  static const VerificationMeta _RoutineIdMeta = const VerificationMeta(
    'RoutineId',
  );
  @override
  late final GeneratedColumn<int> RoutineId = GeneratedColumn<int>(
    'routine_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _TimestampMeta = const VerificationMeta(
    'Timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> Timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _LogActionTypeCodeMeta = const VerificationMeta(
    'LogActionTypeCode',
  );
  @override
  late final GeneratedColumn<int> LogActionTypeCode = GeneratedColumn<int>(
    'log_action_type_code',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _TimeSinceLastDismissalSecondsMeta =
      const VerificationMeta('TimeSinceLastDismissalSeconds');
  @override
  late final GeneratedColumn<int> TimeSinceLastDismissalSeconds =
      GeneratedColumn<int>(
        'time_since_last_dismissal_seconds',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _WasMutedMeta = const VerificationMeta(
    'WasMuted',
  );
  @override
  late final GeneratedColumn<bool> WasMuted = GeneratedColumn<bool>(
    'was_muted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("was_muted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _CreatedAtMeta = const VerificationMeta(
    'CreatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> CreatedAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _ModifiedAtMeta = const VerificationMeta(
    'ModifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> ModifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _DeletedMeta = const VerificationMeta(
    'Deleted',
  );
  @override
  late final GeneratedColumn<bool> Deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    Id,
    RoutineId,
    Timestamp,
    LogActionTypeCode,
    TimeSinceLastDismissalSeconds,
    WasMuted,
    CreatedAt,
    ModifiedAt,
    Deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'log_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<LogEntryModel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_IdMeta, Id.isAcceptableOrUnknown(data['id']!, _IdMeta));
    }
    if (data.containsKey('routine_id')) {
      context.handle(
        _RoutineIdMeta,
        RoutineId.isAcceptableOrUnknown(data['routine_id']!, _RoutineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_RoutineIdMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _TimestampMeta,
        Timestamp.isAcceptableOrUnknown(data['timestamp']!, _TimestampMeta),
      );
    } else if (isInserting) {
      context.missing(_TimestampMeta);
    }
    if (data.containsKey('log_action_type_code')) {
      context.handle(
        _LogActionTypeCodeMeta,
        LogActionTypeCode.isAcceptableOrUnknown(
          data['log_action_type_code']!,
          _LogActionTypeCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_LogActionTypeCodeMeta);
    }
    if (data.containsKey('time_since_last_dismissal_seconds')) {
      context.handle(
        _TimeSinceLastDismissalSecondsMeta,
        TimeSinceLastDismissalSeconds.isAcceptableOrUnknown(
          data['time_since_last_dismissal_seconds']!,
          _TimeSinceLastDismissalSecondsMeta,
        ),
      );
    }
    if (data.containsKey('was_muted')) {
      context.handle(
        _WasMutedMeta,
        WasMuted.isAcceptableOrUnknown(data['was_muted']!, _WasMutedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _CreatedAtMeta,
        CreatedAt.isAcceptableOrUnknown(data['created_at']!, _CreatedAtMeta),
      );
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _ModifiedAtMeta,
        ModifiedAt.isAcceptableOrUnknown(data['modified_at']!, _ModifiedAtMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _DeletedMeta,
        Deleted.isAcceptableOrUnknown(data['deleted']!, _DeletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {Id};
  @override
  LogEntryModel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LogEntryModel(
      Id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      RoutineId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}routine_id'],
      )!,
      Timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      LogActionTypeCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}log_action_type_code'],
      )!,
      TimeSinceLastDismissalSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_since_last_dismissal_seconds'],
      ),
      WasMuted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}was_muted'],
      )!,
      CreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      ModifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      ),
      Deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
    );
  }

  @override
  $LogEntriesTable createAlias(String alias) {
    return $LogEntriesTable(attachedDatabase, alias);
  }
}

class LogEntryModel extends DataClass implements Insertable<LogEntryModel> {
  final int Id;
  final int RoutineId;
  final DateTime Timestamp;
  final int LogActionTypeCode;
  final int? TimeSinceLastDismissalSeconds;

  /// True when this event was produced by a muted auto dismiss (no ring UX).
  final bool WasMuted;
  final DateTime CreatedAt;
  final DateTime? ModifiedAt;
  final bool Deleted;
  const LogEntryModel({
    required this.Id,
    required this.RoutineId,
    required this.Timestamp,
    required this.LogActionTypeCode,
    this.TimeSinceLastDismissalSeconds,
    required this.WasMuted,
    required this.CreatedAt,
    this.ModifiedAt,
    required this.Deleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(Id);
    map['routine_id'] = Variable<int>(RoutineId);
    map['timestamp'] = Variable<DateTime>(Timestamp);
    map['log_action_type_code'] = Variable<int>(LogActionTypeCode);
    if (!nullToAbsent || TimeSinceLastDismissalSeconds != null) {
      map['time_since_last_dismissal_seconds'] = Variable<int>(
        TimeSinceLastDismissalSeconds,
      );
    }
    map['was_muted'] = Variable<bool>(WasMuted);
    map['created_at'] = Variable<DateTime>(CreatedAt);
    if (!nullToAbsent || ModifiedAt != null) {
      map['modified_at'] = Variable<DateTime>(ModifiedAt);
    }
    map['deleted'] = Variable<bool>(Deleted);
    return map;
  }

  LogEntriesCompanion toCompanion(bool nullToAbsent) {
    return LogEntriesCompanion(
      Id: Value(Id),
      RoutineId: Value(RoutineId),
      Timestamp: Value(Timestamp),
      LogActionTypeCode: Value(LogActionTypeCode),
      TimeSinceLastDismissalSeconds:
          TimeSinceLastDismissalSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(TimeSinceLastDismissalSeconds),
      WasMuted: Value(WasMuted),
      CreatedAt: Value(CreatedAt),
      ModifiedAt: ModifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(ModifiedAt),
      Deleted: Value(Deleted),
    );
  }

  factory LogEntryModel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LogEntryModel(
      Id: serializer.fromJson<int>(json['Id']),
      RoutineId: serializer.fromJson<int>(json['RoutineId']),
      Timestamp: serializer.fromJson<DateTime>(json['Timestamp']),
      LogActionTypeCode: serializer.fromJson<int>(json['LogActionTypeCode']),
      TimeSinceLastDismissalSeconds: serializer.fromJson<int?>(
        json['TimeSinceLastDismissalSeconds'],
      ),
      WasMuted: serializer.fromJson<bool>(json['WasMuted']),
      CreatedAt: serializer.fromJson<DateTime>(json['CreatedAt']),
      ModifiedAt: serializer.fromJson<DateTime?>(json['ModifiedAt']),
      Deleted: serializer.fromJson<bool>(json['Deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'Id': serializer.toJson<int>(Id),
      'RoutineId': serializer.toJson<int>(RoutineId),
      'Timestamp': serializer.toJson<DateTime>(Timestamp),
      'LogActionTypeCode': serializer.toJson<int>(LogActionTypeCode),
      'TimeSinceLastDismissalSeconds': serializer.toJson<int?>(
        TimeSinceLastDismissalSeconds,
      ),
      'WasMuted': serializer.toJson<bool>(WasMuted),
      'CreatedAt': serializer.toJson<DateTime>(CreatedAt),
      'ModifiedAt': serializer.toJson<DateTime?>(ModifiedAt),
      'Deleted': serializer.toJson<bool>(Deleted),
    };
  }

  LogEntryModel copyWith({
    int? Id,
    int? RoutineId,
    DateTime? Timestamp,
    int? LogActionTypeCode,
    Value<int?> TimeSinceLastDismissalSeconds = const Value.absent(),
    bool? WasMuted,
    DateTime? CreatedAt,
    Value<DateTime?> ModifiedAt = const Value.absent(),
    bool? Deleted,
  }) => LogEntryModel(
    Id: Id ?? this.Id,
    RoutineId: RoutineId ?? this.RoutineId,
    Timestamp: Timestamp ?? this.Timestamp,
    LogActionTypeCode: LogActionTypeCode ?? this.LogActionTypeCode,
    TimeSinceLastDismissalSeconds: TimeSinceLastDismissalSeconds.present
        ? TimeSinceLastDismissalSeconds.value
        : this.TimeSinceLastDismissalSeconds,
    WasMuted: WasMuted ?? this.WasMuted,
    CreatedAt: CreatedAt ?? this.CreatedAt,
    ModifiedAt: ModifiedAt.present ? ModifiedAt.value : this.ModifiedAt,
    Deleted: Deleted ?? this.Deleted,
  );
  LogEntryModel copyWithCompanion(LogEntriesCompanion data) {
    return LogEntryModel(
      Id: data.Id.present ? data.Id.value : this.Id,
      RoutineId: data.RoutineId.present ? data.RoutineId.value : this.RoutineId,
      Timestamp: data.Timestamp.present ? data.Timestamp.value : this.Timestamp,
      LogActionTypeCode: data.LogActionTypeCode.present
          ? data.LogActionTypeCode.value
          : this.LogActionTypeCode,
      TimeSinceLastDismissalSeconds: data.TimeSinceLastDismissalSeconds.present
          ? data.TimeSinceLastDismissalSeconds.value
          : this.TimeSinceLastDismissalSeconds,
      WasMuted: data.WasMuted.present ? data.WasMuted.value : this.WasMuted,
      CreatedAt: data.CreatedAt.present ? data.CreatedAt.value : this.CreatedAt,
      ModifiedAt: data.ModifiedAt.present
          ? data.ModifiedAt.value
          : this.ModifiedAt,
      Deleted: data.Deleted.present ? data.Deleted.value : this.Deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LogEntryModel(')
          ..write('Id: $Id, ')
          ..write('RoutineId: $RoutineId, ')
          ..write('Timestamp: $Timestamp, ')
          ..write('LogActionTypeCode: $LogActionTypeCode, ')
          ..write(
            'TimeSinceLastDismissalSeconds: $TimeSinceLastDismissalSeconds, ',
          )
          ..write('WasMuted: $WasMuted, ')
          ..write('CreatedAt: $CreatedAt, ')
          ..write('ModifiedAt: $ModifiedAt, ')
          ..write('Deleted: $Deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    Id,
    RoutineId,
    Timestamp,
    LogActionTypeCode,
    TimeSinceLastDismissalSeconds,
    WasMuted,
    CreatedAt,
    ModifiedAt,
    Deleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LogEntryModel &&
          other.Id == this.Id &&
          other.RoutineId == this.RoutineId &&
          other.Timestamp == this.Timestamp &&
          other.LogActionTypeCode == this.LogActionTypeCode &&
          other.TimeSinceLastDismissalSeconds ==
              this.TimeSinceLastDismissalSeconds &&
          other.WasMuted == this.WasMuted &&
          other.CreatedAt == this.CreatedAt &&
          other.ModifiedAt == this.ModifiedAt &&
          other.Deleted == this.Deleted);
}

class LogEntriesCompanion extends UpdateCompanion<LogEntryModel> {
  final Value<int> Id;
  final Value<int> RoutineId;
  final Value<DateTime> Timestamp;
  final Value<int> LogActionTypeCode;
  final Value<int?> TimeSinceLastDismissalSeconds;
  final Value<bool> WasMuted;
  final Value<DateTime> CreatedAt;
  final Value<DateTime?> ModifiedAt;
  final Value<bool> Deleted;
  const LogEntriesCompanion({
    this.Id = const Value.absent(),
    this.RoutineId = const Value.absent(),
    this.Timestamp = const Value.absent(),
    this.LogActionTypeCode = const Value.absent(),
    this.TimeSinceLastDismissalSeconds = const Value.absent(),
    this.WasMuted = const Value.absent(),
    this.CreatedAt = const Value.absent(),
    this.ModifiedAt = const Value.absent(),
    this.Deleted = const Value.absent(),
  });
  LogEntriesCompanion.insert({
    this.Id = const Value.absent(),
    required int RoutineId,
    required DateTime Timestamp,
    required int LogActionTypeCode,
    this.TimeSinceLastDismissalSeconds = const Value.absent(),
    this.WasMuted = const Value.absent(),
    this.CreatedAt = const Value.absent(),
    this.ModifiedAt = const Value.absent(),
    this.Deleted = const Value.absent(),
  }) : RoutineId = Value(RoutineId),
       Timestamp = Value(Timestamp),
       LogActionTypeCode = Value(LogActionTypeCode);
  static Insertable<LogEntryModel> custom({
    Expression<int>? Id,
    Expression<int>? RoutineId,
    Expression<DateTime>? Timestamp,
    Expression<int>? LogActionTypeCode,
    Expression<int>? TimeSinceLastDismissalSeconds,
    Expression<bool>? WasMuted,
    Expression<DateTime>? CreatedAt,
    Expression<DateTime>? ModifiedAt,
    Expression<bool>? Deleted,
  }) {
    return RawValuesInsertable({
      if (Id != null) 'id': Id,
      if (RoutineId != null) 'routine_id': RoutineId,
      if (Timestamp != null) 'timestamp': Timestamp,
      if (LogActionTypeCode != null) 'log_action_type_code': LogActionTypeCode,
      if (TimeSinceLastDismissalSeconds != null)
        'time_since_last_dismissal_seconds': TimeSinceLastDismissalSeconds,
      if (WasMuted != null) 'was_muted': WasMuted,
      if (CreatedAt != null) 'created_at': CreatedAt,
      if (ModifiedAt != null) 'modified_at': ModifiedAt,
      if (Deleted != null) 'deleted': Deleted,
    });
  }

  LogEntriesCompanion copyWith({
    Value<int>? Id,
    Value<int>? RoutineId,
    Value<DateTime>? Timestamp,
    Value<int>? LogActionTypeCode,
    Value<int?>? TimeSinceLastDismissalSeconds,
    Value<bool>? WasMuted,
    Value<DateTime>? CreatedAt,
    Value<DateTime?>? ModifiedAt,
    Value<bool>? Deleted,
  }) {
    return LogEntriesCompanion(
      Id: Id ?? this.Id,
      RoutineId: RoutineId ?? this.RoutineId,
      Timestamp: Timestamp ?? this.Timestamp,
      LogActionTypeCode: LogActionTypeCode ?? this.LogActionTypeCode,
      TimeSinceLastDismissalSeconds:
          TimeSinceLastDismissalSeconds ?? this.TimeSinceLastDismissalSeconds,
      WasMuted: WasMuted ?? this.WasMuted,
      CreatedAt: CreatedAt ?? this.CreatedAt,
      ModifiedAt: ModifiedAt ?? this.ModifiedAt,
      Deleted: Deleted ?? this.Deleted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (Id.present) {
      map['id'] = Variable<int>(Id.value);
    }
    if (RoutineId.present) {
      map['routine_id'] = Variable<int>(RoutineId.value);
    }
    if (Timestamp.present) {
      map['timestamp'] = Variable<DateTime>(Timestamp.value);
    }
    if (LogActionTypeCode.present) {
      map['log_action_type_code'] = Variable<int>(LogActionTypeCode.value);
    }
    if (TimeSinceLastDismissalSeconds.present) {
      map['time_since_last_dismissal_seconds'] = Variable<int>(
        TimeSinceLastDismissalSeconds.value,
      );
    }
    if (WasMuted.present) {
      map['was_muted'] = Variable<bool>(WasMuted.value);
    }
    if (CreatedAt.present) {
      map['created_at'] = Variable<DateTime>(CreatedAt.value);
    }
    if (ModifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(ModifiedAt.value);
    }
    if (Deleted.present) {
      map['deleted'] = Variable<bool>(Deleted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LogEntriesCompanion(')
          ..write('Id: $Id, ')
          ..write('RoutineId: $RoutineId, ')
          ..write('Timestamp: $Timestamp, ')
          ..write('LogActionTypeCode: $LogActionTypeCode, ')
          ..write(
            'TimeSinceLastDismissalSeconds: $TimeSinceLastDismissalSeconds, ',
          )
          ..write('WasMuted: $WasMuted, ')
          ..write('CreatedAt: $CreatedAt, ')
          ..write('ModifiedAt: $ModifiedAt, ')
          ..write('Deleted: $Deleted')
          ..write(')'))
        .toString();
  }
}

abstract class _$RA_Database extends GeneratedDatabase {
  _$RA_Database(QueryExecutor e) : super(e);
  $RA_DatabaseManager get managers => $RA_DatabaseManager(this);
  late final $RoutinesTable routines = $RoutinesTable(this);
  late final $RoutineStatesTable routineStates = $RoutineStatesTable(this);
  late final $LogEntriesTable logEntries = $LogEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    routines,
    routineStates,
    logEntries,
  ];
}

typedef $$RoutinesTableCreateCompanionBuilder =
    RoutinesCompanion Function({
      Value<int> Id,
      required String Name,
      Value<int> SnoozeSeconds,
      required int IntervalSeconds,
      Value<int> MaxTimesPerDay,
      Value<int> DayStartSeconds,
      Value<bool> MaxTimesPerDayEnabled,
      Value<int> EnabledWeekdays,
      required int DriftCompensationTypeCode,
      Value<bool> ShowPreview,
      Value<bool> Vibrate,
      Value<int> Volume,
      Value<bool> FadeIn,
      Value<String?> AudioUri,
      Value<bool> IsActive,
      Value<DateTime> CreatedAt,
      Value<DateTime?> ModifiedAt,
      Value<bool> Deleted,
    });
typedef $$RoutinesTableUpdateCompanionBuilder =
    RoutinesCompanion Function({
      Value<int> Id,
      Value<String> Name,
      Value<int> SnoozeSeconds,
      Value<int> IntervalSeconds,
      Value<int> MaxTimesPerDay,
      Value<int> DayStartSeconds,
      Value<bool> MaxTimesPerDayEnabled,
      Value<int> EnabledWeekdays,
      Value<int> DriftCompensationTypeCode,
      Value<bool> ShowPreview,
      Value<bool> Vibrate,
      Value<int> Volume,
      Value<bool> FadeIn,
      Value<String?> AudioUri,
      Value<bool> IsActive,
      Value<DateTime> CreatedAt,
      Value<DateTime?> ModifiedAt,
      Value<bool> Deleted,
    });

class $$RoutinesTableFilterComposer
    extends Composer<_$RA_Database, $RoutinesTable> {
  $$RoutinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get Id => $composableBuilder(
    column: $table.Id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get Name => $composableBuilder(
    column: $table.Name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get SnoozeSeconds => $composableBuilder(
    column: $table.SnoozeSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get IntervalSeconds => $composableBuilder(
    column: $table.IntervalSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get MaxTimesPerDay => $composableBuilder(
    column: $table.MaxTimesPerDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get DayStartSeconds => $composableBuilder(
    column: $table.DayStartSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get MaxTimesPerDayEnabled => $composableBuilder(
    column: $table.MaxTimesPerDayEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get EnabledWeekdays => $composableBuilder(
    column: $table.EnabledWeekdays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get DriftCompensationTypeCode => $composableBuilder(
    column: $table.DriftCompensationTypeCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get ShowPreview => $composableBuilder(
    column: $table.ShowPreview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get Vibrate => $composableBuilder(
    column: $table.Vibrate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get Volume => $composableBuilder(
    column: $table.Volume,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get FadeIn => $composableBuilder(
    column: $table.FadeIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get AudioUri => $composableBuilder(
    column: $table.AudioUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get IsActive => $composableBuilder(
    column: $table.IsActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get CreatedAt => $composableBuilder(
    column: $table.CreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get ModifiedAt => $composableBuilder(
    column: $table.ModifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get Deleted => $composableBuilder(
    column: $table.Deleted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoutinesTableOrderingComposer
    extends Composer<_$RA_Database, $RoutinesTable> {
  $$RoutinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get Id => $composableBuilder(
    column: $table.Id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get Name => $composableBuilder(
    column: $table.Name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get SnoozeSeconds => $composableBuilder(
    column: $table.SnoozeSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get IntervalSeconds => $composableBuilder(
    column: $table.IntervalSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get MaxTimesPerDay => $composableBuilder(
    column: $table.MaxTimesPerDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get DayStartSeconds => $composableBuilder(
    column: $table.DayStartSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get MaxTimesPerDayEnabled => $composableBuilder(
    column: $table.MaxTimesPerDayEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get EnabledWeekdays => $composableBuilder(
    column: $table.EnabledWeekdays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get DriftCompensationTypeCode => $composableBuilder(
    column: $table.DriftCompensationTypeCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get ShowPreview => $composableBuilder(
    column: $table.ShowPreview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get Vibrate => $composableBuilder(
    column: $table.Vibrate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get Volume => $composableBuilder(
    column: $table.Volume,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get FadeIn => $composableBuilder(
    column: $table.FadeIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get AudioUri => $composableBuilder(
    column: $table.AudioUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get IsActive => $composableBuilder(
    column: $table.IsActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get CreatedAt => $composableBuilder(
    column: $table.CreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get ModifiedAt => $composableBuilder(
    column: $table.ModifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get Deleted => $composableBuilder(
    column: $table.Deleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoutinesTableAnnotationComposer
    extends Composer<_$RA_Database, $RoutinesTable> {
  $$RoutinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get Id =>
      $composableBuilder(column: $table.Id, builder: (column) => column);

  GeneratedColumn<String> get Name =>
      $composableBuilder(column: $table.Name, builder: (column) => column);

  GeneratedColumn<int> get SnoozeSeconds => $composableBuilder(
    column: $table.SnoozeSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get IntervalSeconds => $composableBuilder(
    column: $table.IntervalSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get MaxTimesPerDay => $composableBuilder(
    column: $table.MaxTimesPerDay,
    builder: (column) => column,
  );

  GeneratedColumn<int> get DayStartSeconds => $composableBuilder(
    column: $table.DayStartSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get MaxTimesPerDayEnabled => $composableBuilder(
    column: $table.MaxTimesPerDayEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get EnabledWeekdays => $composableBuilder(
    column: $table.EnabledWeekdays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get DriftCompensationTypeCode => $composableBuilder(
    column: $table.DriftCompensationTypeCode,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get ShowPreview => $composableBuilder(
    column: $table.ShowPreview,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get Vibrate =>
      $composableBuilder(column: $table.Vibrate, builder: (column) => column);

  GeneratedColumn<int> get Volume =>
      $composableBuilder(column: $table.Volume, builder: (column) => column);

  GeneratedColumn<bool> get FadeIn =>
      $composableBuilder(column: $table.FadeIn, builder: (column) => column);

  GeneratedColumn<String> get AudioUri =>
      $composableBuilder(column: $table.AudioUri, builder: (column) => column);

  GeneratedColumn<bool> get IsActive =>
      $composableBuilder(column: $table.IsActive, builder: (column) => column);

  GeneratedColumn<DateTime> get CreatedAt =>
      $composableBuilder(column: $table.CreatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get ModifiedAt => $composableBuilder(
    column: $table.ModifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get Deleted =>
      $composableBuilder(column: $table.Deleted, builder: (column) => column);
}

class $$RoutinesTableTableManager
    extends
        RootTableManager<
          _$RA_Database,
          $RoutinesTable,
          RoutineModel,
          $$RoutinesTableFilterComposer,
          $$RoutinesTableOrderingComposer,
          $$RoutinesTableAnnotationComposer,
          $$RoutinesTableCreateCompanionBuilder,
          $$RoutinesTableUpdateCompanionBuilder,
          (
            RoutineModel,
            BaseReferences<_$RA_Database, $RoutinesTable, RoutineModel>,
          ),
          RoutineModel,
          PrefetchHooks Function()
        > {
  $$RoutinesTableTableManager(_$RA_Database db, $RoutinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoutinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoutinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoutinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> Id = const Value.absent(),
                Value<String> Name = const Value.absent(),
                Value<int> SnoozeSeconds = const Value.absent(),
                Value<int> IntervalSeconds = const Value.absent(),
                Value<int> MaxTimesPerDay = const Value.absent(),
                Value<int> DayStartSeconds = const Value.absent(),
                Value<bool> MaxTimesPerDayEnabled = const Value.absent(),
                Value<int> EnabledWeekdays = const Value.absent(),
                Value<int> DriftCompensationTypeCode = const Value.absent(),
                Value<bool> ShowPreview = const Value.absent(),
                Value<bool> Vibrate = const Value.absent(),
                Value<int> Volume = const Value.absent(),
                Value<bool> FadeIn = const Value.absent(),
                Value<String?> AudioUri = const Value.absent(),
                Value<bool> IsActive = const Value.absent(),
                Value<DateTime> CreatedAt = const Value.absent(),
                Value<DateTime?> ModifiedAt = const Value.absent(),
                Value<bool> Deleted = const Value.absent(),
              }) => RoutinesCompanion(
                Id: Id,
                Name: Name,
                SnoozeSeconds: SnoozeSeconds,
                IntervalSeconds: IntervalSeconds,
                MaxTimesPerDay: MaxTimesPerDay,
                DayStartSeconds: DayStartSeconds,
                MaxTimesPerDayEnabled: MaxTimesPerDayEnabled,
                EnabledWeekdays: EnabledWeekdays,
                DriftCompensationTypeCode: DriftCompensationTypeCode,
                ShowPreview: ShowPreview,
                Vibrate: Vibrate,
                Volume: Volume,
                FadeIn: FadeIn,
                AudioUri: AudioUri,
                IsActive: IsActive,
                CreatedAt: CreatedAt,
                ModifiedAt: ModifiedAt,
                Deleted: Deleted,
              ),
          createCompanionCallback:
              ({
                Value<int> Id = const Value.absent(),
                required String Name,
                Value<int> SnoozeSeconds = const Value.absent(),
                required int IntervalSeconds,
                Value<int> MaxTimesPerDay = const Value.absent(),
                Value<int> DayStartSeconds = const Value.absent(),
                Value<bool> MaxTimesPerDayEnabled = const Value.absent(),
                Value<int> EnabledWeekdays = const Value.absent(),
                required int DriftCompensationTypeCode,
                Value<bool> ShowPreview = const Value.absent(),
                Value<bool> Vibrate = const Value.absent(),
                Value<int> Volume = const Value.absent(),
                Value<bool> FadeIn = const Value.absent(),
                Value<String?> AudioUri = const Value.absent(),
                Value<bool> IsActive = const Value.absent(),
                Value<DateTime> CreatedAt = const Value.absent(),
                Value<DateTime?> ModifiedAt = const Value.absent(),
                Value<bool> Deleted = const Value.absent(),
              }) => RoutinesCompanion.insert(
                Id: Id,
                Name: Name,
                SnoozeSeconds: SnoozeSeconds,
                IntervalSeconds: IntervalSeconds,
                MaxTimesPerDay: MaxTimesPerDay,
                DayStartSeconds: DayStartSeconds,
                MaxTimesPerDayEnabled: MaxTimesPerDayEnabled,
                EnabledWeekdays: EnabledWeekdays,
                DriftCompensationTypeCode: DriftCompensationTypeCode,
                ShowPreview: ShowPreview,
                Vibrate: Vibrate,
                Volume: Volume,
                FadeIn: FadeIn,
                AudioUri: AudioUri,
                IsActive: IsActive,
                CreatedAt: CreatedAt,
                ModifiedAt: ModifiedAt,
                Deleted: Deleted,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoutinesTableProcessedTableManager =
    ProcessedTableManager<
      _$RA_Database,
      $RoutinesTable,
      RoutineModel,
      $$RoutinesTableFilterComposer,
      $$RoutinesTableOrderingComposer,
      $$RoutinesTableAnnotationComposer,
      $$RoutinesTableCreateCompanionBuilder,
      $$RoutinesTableUpdateCompanionBuilder,
      (
        RoutineModel,
        BaseReferences<_$RA_Database, $RoutinesTable, RoutineModel>,
      ),
      RoutineModel,
      PrefetchHooks Function()
    >;
typedef $$RoutineStatesTableCreateCompanionBuilder =
    RoutineStatesCompanion Function({
      Value<int> Id,
      required int RoutineId,
      Value<DateTime?> NextTriggerTime,
      Value<DateTime?> InitialRingTime,
      Value<int> CurrentSnoozeCount,
      Value<int> TimesRingToday,
      Value<DateTime?> TimesRingDay,
      Value<int> ExtraMaxTimesToday,
      Value<bool> IsRinging,
      Value<DateTime?> LastDismissedAt,
      Value<DateTime?> PausedAt,
      Value<DateTime?> MutedAt,
      Value<DateTime> CreatedAt,
      Value<DateTime?> ModifiedAt,
      Value<bool> Deleted,
    });
typedef $$RoutineStatesTableUpdateCompanionBuilder =
    RoutineStatesCompanion Function({
      Value<int> Id,
      Value<int> RoutineId,
      Value<DateTime?> NextTriggerTime,
      Value<DateTime?> InitialRingTime,
      Value<int> CurrentSnoozeCount,
      Value<int> TimesRingToday,
      Value<DateTime?> TimesRingDay,
      Value<int> ExtraMaxTimesToday,
      Value<bool> IsRinging,
      Value<DateTime?> LastDismissedAt,
      Value<DateTime?> PausedAt,
      Value<DateTime?> MutedAt,
      Value<DateTime> CreatedAt,
      Value<DateTime?> ModifiedAt,
      Value<bool> Deleted,
    });

class $$RoutineStatesTableFilterComposer
    extends Composer<_$RA_Database, $RoutineStatesTable> {
  $$RoutineStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get Id => $composableBuilder(
    column: $table.Id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get RoutineId => $composableBuilder(
    column: $table.RoutineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get NextTriggerTime => $composableBuilder(
    column: $table.NextTriggerTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get InitialRingTime => $composableBuilder(
    column: $table.InitialRingTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get CurrentSnoozeCount => $composableBuilder(
    column: $table.CurrentSnoozeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get TimesRingToday => $composableBuilder(
    column: $table.TimesRingToday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get TimesRingDay => $composableBuilder(
    column: $table.TimesRingDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ExtraMaxTimesToday => $composableBuilder(
    column: $table.ExtraMaxTimesToday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get IsRinging => $composableBuilder(
    column: $table.IsRinging,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get LastDismissedAt => $composableBuilder(
    column: $table.LastDismissedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get PausedAt => $composableBuilder(
    column: $table.PausedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get MutedAt => $composableBuilder(
    column: $table.MutedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get CreatedAt => $composableBuilder(
    column: $table.CreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get ModifiedAt => $composableBuilder(
    column: $table.ModifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get Deleted => $composableBuilder(
    column: $table.Deleted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoutineStatesTableOrderingComposer
    extends Composer<_$RA_Database, $RoutineStatesTable> {
  $$RoutineStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get Id => $composableBuilder(
    column: $table.Id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get RoutineId => $composableBuilder(
    column: $table.RoutineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get NextTriggerTime => $composableBuilder(
    column: $table.NextTriggerTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get InitialRingTime => $composableBuilder(
    column: $table.InitialRingTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get CurrentSnoozeCount => $composableBuilder(
    column: $table.CurrentSnoozeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get TimesRingToday => $composableBuilder(
    column: $table.TimesRingToday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get TimesRingDay => $composableBuilder(
    column: $table.TimesRingDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ExtraMaxTimesToday => $composableBuilder(
    column: $table.ExtraMaxTimesToday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get IsRinging => $composableBuilder(
    column: $table.IsRinging,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get LastDismissedAt => $composableBuilder(
    column: $table.LastDismissedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get PausedAt => $composableBuilder(
    column: $table.PausedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get MutedAt => $composableBuilder(
    column: $table.MutedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get CreatedAt => $composableBuilder(
    column: $table.CreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get ModifiedAt => $composableBuilder(
    column: $table.ModifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get Deleted => $composableBuilder(
    column: $table.Deleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoutineStatesTableAnnotationComposer
    extends Composer<_$RA_Database, $RoutineStatesTable> {
  $$RoutineStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get Id =>
      $composableBuilder(column: $table.Id, builder: (column) => column);

  GeneratedColumn<int> get RoutineId =>
      $composableBuilder(column: $table.RoutineId, builder: (column) => column);

  GeneratedColumn<DateTime> get NextTriggerTime => $composableBuilder(
    column: $table.NextTriggerTime,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get InitialRingTime => $composableBuilder(
    column: $table.InitialRingTime,
    builder: (column) => column,
  );

  GeneratedColumn<int> get CurrentSnoozeCount => $composableBuilder(
    column: $table.CurrentSnoozeCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get TimesRingToday => $composableBuilder(
    column: $table.TimesRingToday,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get TimesRingDay => $composableBuilder(
    column: $table.TimesRingDay,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ExtraMaxTimesToday => $composableBuilder(
    column: $table.ExtraMaxTimesToday,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get IsRinging =>
      $composableBuilder(column: $table.IsRinging, builder: (column) => column);

  GeneratedColumn<DateTime> get LastDismissedAt => $composableBuilder(
    column: $table.LastDismissedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get PausedAt =>
      $composableBuilder(column: $table.PausedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get MutedAt =>
      $composableBuilder(column: $table.MutedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get CreatedAt =>
      $composableBuilder(column: $table.CreatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get ModifiedAt => $composableBuilder(
    column: $table.ModifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get Deleted =>
      $composableBuilder(column: $table.Deleted, builder: (column) => column);
}

class $$RoutineStatesTableTableManager
    extends
        RootTableManager<
          _$RA_Database,
          $RoutineStatesTable,
          RoutineStateModel,
          $$RoutineStatesTableFilterComposer,
          $$RoutineStatesTableOrderingComposer,
          $$RoutineStatesTableAnnotationComposer,
          $$RoutineStatesTableCreateCompanionBuilder,
          $$RoutineStatesTableUpdateCompanionBuilder,
          (
            RoutineStateModel,
            BaseReferences<
              _$RA_Database,
              $RoutineStatesTable,
              RoutineStateModel
            >,
          ),
          RoutineStateModel,
          PrefetchHooks Function()
        > {
  $$RoutineStatesTableTableManager(_$RA_Database db, $RoutineStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoutineStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoutineStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoutineStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> Id = const Value.absent(),
                Value<int> RoutineId = const Value.absent(),
                Value<DateTime?> NextTriggerTime = const Value.absent(),
                Value<DateTime?> InitialRingTime = const Value.absent(),
                Value<int> CurrentSnoozeCount = const Value.absent(),
                Value<int> TimesRingToday = const Value.absent(),
                Value<DateTime?> TimesRingDay = const Value.absent(),
                Value<int> ExtraMaxTimesToday = const Value.absent(),
                Value<bool> IsRinging = const Value.absent(),
                Value<DateTime?> LastDismissedAt = const Value.absent(),
                Value<DateTime?> PausedAt = const Value.absent(),
                Value<DateTime?> MutedAt = const Value.absent(),
                Value<DateTime> CreatedAt = const Value.absent(),
                Value<DateTime?> ModifiedAt = const Value.absent(),
                Value<bool> Deleted = const Value.absent(),
              }) => RoutineStatesCompanion(
                Id: Id,
                RoutineId: RoutineId,
                NextTriggerTime: NextTriggerTime,
                InitialRingTime: InitialRingTime,
                CurrentSnoozeCount: CurrentSnoozeCount,
                TimesRingToday: TimesRingToday,
                TimesRingDay: TimesRingDay,
                ExtraMaxTimesToday: ExtraMaxTimesToday,
                IsRinging: IsRinging,
                LastDismissedAt: LastDismissedAt,
                PausedAt: PausedAt,
                MutedAt: MutedAt,
                CreatedAt: CreatedAt,
                ModifiedAt: ModifiedAt,
                Deleted: Deleted,
              ),
          createCompanionCallback:
              ({
                Value<int> Id = const Value.absent(),
                required int RoutineId,
                Value<DateTime?> NextTriggerTime = const Value.absent(),
                Value<DateTime?> InitialRingTime = const Value.absent(),
                Value<int> CurrentSnoozeCount = const Value.absent(),
                Value<int> TimesRingToday = const Value.absent(),
                Value<DateTime?> TimesRingDay = const Value.absent(),
                Value<int> ExtraMaxTimesToday = const Value.absent(),
                Value<bool> IsRinging = const Value.absent(),
                Value<DateTime?> LastDismissedAt = const Value.absent(),
                Value<DateTime?> PausedAt = const Value.absent(),
                Value<DateTime?> MutedAt = const Value.absent(),
                Value<DateTime> CreatedAt = const Value.absent(),
                Value<DateTime?> ModifiedAt = const Value.absent(),
                Value<bool> Deleted = const Value.absent(),
              }) => RoutineStatesCompanion.insert(
                Id: Id,
                RoutineId: RoutineId,
                NextTriggerTime: NextTriggerTime,
                InitialRingTime: InitialRingTime,
                CurrentSnoozeCount: CurrentSnoozeCount,
                TimesRingToday: TimesRingToday,
                TimesRingDay: TimesRingDay,
                ExtraMaxTimesToday: ExtraMaxTimesToday,
                IsRinging: IsRinging,
                LastDismissedAt: LastDismissedAt,
                PausedAt: PausedAt,
                MutedAt: MutedAt,
                CreatedAt: CreatedAt,
                ModifiedAt: ModifiedAt,
                Deleted: Deleted,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoutineStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$RA_Database,
      $RoutineStatesTable,
      RoutineStateModel,
      $$RoutineStatesTableFilterComposer,
      $$RoutineStatesTableOrderingComposer,
      $$RoutineStatesTableAnnotationComposer,
      $$RoutineStatesTableCreateCompanionBuilder,
      $$RoutineStatesTableUpdateCompanionBuilder,
      (
        RoutineStateModel,
        BaseReferences<_$RA_Database, $RoutineStatesTable, RoutineStateModel>,
      ),
      RoutineStateModel,
      PrefetchHooks Function()
    >;
typedef $$LogEntriesTableCreateCompanionBuilder =
    LogEntriesCompanion Function({
      Value<int> Id,
      required int RoutineId,
      required DateTime Timestamp,
      required int LogActionTypeCode,
      Value<int?> TimeSinceLastDismissalSeconds,
      Value<bool> WasMuted,
      Value<DateTime> CreatedAt,
      Value<DateTime?> ModifiedAt,
      Value<bool> Deleted,
    });
typedef $$LogEntriesTableUpdateCompanionBuilder =
    LogEntriesCompanion Function({
      Value<int> Id,
      Value<int> RoutineId,
      Value<DateTime> Timestamp,
      Value<int> LogActionTypeCode,
      Value<int?> TimeSinceLastDismissalSeconds,
      Value<bool> WasMuted,
      Value<DateTime> CreatedAt,
      Value<DateTime?> ModifiedAt,
      Value<bool> Deleted,
    });

class $$LogEntriesTableFilterComposer
    extends Composer<_$RA_Database, $LogEntriesTable> {
  $$LogEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get Id => $composableBuilder(
    column: $table.Id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get RoutineId => $composableBuilder(
    column: $table.RoutineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get Timestamp => $composableBuilder(
    column: $table.Timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get LogActionTypeCode => $composableBuilder(
    column: $table.LogActionTypeCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get TimeSinceLastDismissalSeconds => $composableBuilder(
    column: $table.TimeSinceLastDismissalSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get WasMuted => $composableBuilder(
    column: $table.WasMuted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get CreatedAt => $composableBuilder(
    column: $table.CreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get ModifiedAt => $composableBuilder(
    column: $table.ModifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get Deleted => $composableBuilder(
    column: $table.Deleted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LogEntriesTableOrderingComposer
    extends Composer<_$RA_Database, $LogEntriesTable> {
  $$LogEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get Id => $composableBuilder(
    column: $table.Id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get RoutineId => $composableBuilder(
    column: $table.RoutineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get Timestamp => $composableBuilder(
    column: $table.Timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get LogActionTypeCode => $composableBuilder(
    column: $table.LogActionTypeCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get TimeSinceLastDismissalSeconds => $composableBuilder(
    column: $table.TimeSinceLastDismissalSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get WasMuted => $composableBuilder(
    column: $table.WasMuted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get CreatedAt => $composableBuilder(
    column: $table.CreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get ModifiedAt => $composableBuilder(
    column: $table.ModifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get Deleted => $composableBuilder(
    column: $table.Deleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LogEntriesTableAnnotationComposer
    extends Composer<_$RA_Database, $LogEntriesTable> {
  $$LogEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get Id =>
      $composableBuilder(column: $table.Id, builder: (column) => column);

  GeneratedColumn<int> get RoutineId =>
      $composableBuilder(column: $table.RoutineId, builder: (column) => column);

  GeneratedColumn<DateTime> get Timestamp =>
      $composableBuilder(column: $table.Timestamp, builder: (column) => column);

  GeneratedColumn<int> get LogActionTypeCode => $composableBuilder(
    column: $table.LogActionTypeCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get TimeSinceLastDismissalSeconds => $composableBuilder(
    column: $table.TimeSinceLastDismissalSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get WasMuted =>
      $composableBuilder(column: $table.WasMuted, builder: (column) => column);

  GeneratedColumn<DateTime> get CreatedAt =>
      $composableBuilder(column: $table.CreatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get ModifiedAt => $composableBuilder(
    column: $table.ModifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get Deleted =>
      $composableBuilder(column: $table.Deleted, builder: (column) => column);
}

class $$LogEntriesTableTableManager
    extends
        RootTableManager<
          _$RA_Database,
          $LogEntriesTable,
          LogEntryModel,
          $$LogEntriesTableFilterComposer,
          $$LogEntriesTableOrderingComposer,
          $$LogEntriesTableAnnotationComposer,
          $$LogEntriesTableCreateCompanionBuilder,
          $$LogEntriesTableUpdateCompanionBuilder,
          (
            LogEntryModel,
            BaseReferences<_$RA_Database, $LogEntriesTable, LogEntryModel>,
          ),
          LogEntryModel,
          PrefetchHooks Function()
        > {
  $$LogEntriesTableTableManager(_$RA_Database db, $LogEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LogEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LogEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LogEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> Id = const Value.absent(),
                Value<int> RoutineId = const Value.absent(),
                Value<DateTime> Timestamp = const Value.absent(),
                Value<int> LogActionTypeCode = const Value.absent(),
                Value<int?> TimeSinceLastDismissalSeconds =
                    const Value.absent(),
                Value<bool> WasMuted = const Value.absent(),
                Value<DateTime> CreatedAt = const Value.absent(),
                Value<DateTime?> ModifiedAt = const Value.absent(),
                Value<bool> Deleted = const Value.absent(),
              }) => LogEntriesCompanion(
                Id: Id,
                RoutineId: RoutineId,
                Timestamp: Timestamp,
                LogActionTypeCode: LogActionTypeCode,
                TimeSinceLastDismissalSeconds: TimeSinceLastDismissalSeconds,
                WasMuted: WasMuted,
                CreatedAt: CreatedAt,
                ModifiedAt: ModifiedAt,
                Deleted: Deleted,
              ),
          createCompanionCallback:
              ({
                Value<int> Id = const Value.absent(),
                required int RoutineId,
                required DateTime Timestamp,
                required int LogActionTypeCode,
                Value<int?> TimeSinceLastDismissalSeconds =
                    const Value.absent(),
                Value<bool> WasMuted = const Value.absent(),
                Value<DateTime> CreatedAt = const Value.absent(),
                Value<DateTime?> ModifiedAt = const Value.absent(),
                Value<bool> Deleted = const Value.absent(),
              }) => LogEntriesCompanion.insert(
                Id: Id,
                RoutineId: RoutineId,
                Timestamp: Timestamp,
                LogActionTypeCode: LogActionTypeCode,
                TimeSinceLastDismissalSeconds: TimeSinceLastDismissalSeconds,
                WasMuted: WasMuted,
                CreatedAt: CreatedAt,
                ModifiedAt: ModifiedAt,
                Deleted: Deleted,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LogEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$RA_Database,
      $LogEntriesTable,
      LogEntryModel,
      $$LogEntriesTableFilterComposer,
      $$LogEntriesTableOrderingComposer,
      $$LogEntriesTableAnnotationComposer,
      $$LogEntriesTableCreateCompanionBuilder,
      $$LogEntriesTableUpdateCompanionBuilder,
      (
        LogEntryModel,
        BaseReferences<_$RA_Database, $LogEntriesTable, LogEntryModel>,
      ),
      LogEntryModel,
      PrefetchHooks Function()
    >;

class $RA_DatabaseManager {
  final _$RA_Database _db;
  $RA_DatabaseManager(this._db);
  $$RoutinesTableTableManager get routines =>
      $$RoutinesTableTableManager(_db, _db.routines);
  $$RoutineStatesTableTableManager get routineStates =>
      $$RoutineStatesTableTableManager(_db, _db.routineStates);
  $$LogEntriesTableTableManager get logEntries =>
      $$LogEntriesTableTableManager(_db, _db.logEntries);
}
