// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_services_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$databaseServiceHash() => r'6c4dbe5519a778834a2cfaa3700e5a6df24e6d9f';

/// See also [databaseService].
@ProviderFor(databaseService)
final databaseServiceProvider = Provider<DatabaseService>.internal(
  databaseService,
  name: r'databaseServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$databaseServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef DatabaseServiceRef = ProviderRef<DatabaseService>;
String _$notificationServiceHash() =>
    r'015117d47fe71bf44664bf802ad1290b1e2492d4';

/// See also [notificationService].
@ProviderFor(notificationService)
final notificationServiceProvider = Provider<NotificationService>.internal(
  notificationService,
  name: r'notificationServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$notificationServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef NotificationServiceRef = ProviderRef<NotificationService>;
String _$bootRescheduleServiceHash() =>
    r'13ffc64311b278525feccddf288f9dfe521cc97c';

/// See also [bootRescheduleService].
@ProviderFor(bootRescheduleService)
final bootRescheduleServiceProvider = Provider<BootRescheduleService>.internal(
  bootRescheduleService,
  name: r'bootRescheduleServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bootRescheduleServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef BootRescheduleServiceRef = ProviderRef<BootRescheduleService>;
String _$appInitializeHash() => r'e9da6452a9549095643f59f48890bb6ac714b226';

/// See also [appInitialize].
@ProviderFor(appInitialize)
final appInitializeProvider = FutureProvider<void>.internal(
  appInitialize,
  name: r'appInitializeProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$appInitializeHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AppInitializeRef = FutureProviderRef<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
