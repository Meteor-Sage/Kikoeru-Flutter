// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
      id: (json['id'] as num?)?.toInt(),
      name: json['name'] as String,
      password: json['password'] as String?,
      host: json['host'] as String?,
      token: json['token'] as String?,
      lastUpdateTime: json['lastUpdateTime'] == null
          ? null
          : DateTime.parse(json['lastUpdateTime'] as String),
      loggedIn: json['loggedIn'] as bool? ?? false,
      group: json['group'] as String?,
      email: json['email'] as String?,
      recommenderUuid: json['recommenderUuid'] as String?,
    );

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'password': instance.password,
      'host': instance.host,
      'token': instance.token,
      'lastUpdateTime': instance.lastUpdateTime?.toIso8601String(),
      'loggedIn': instance.loggedIn,
      'group': instance.group,
      'email': instance.email,
      'recommenderUuid': instance.recommenderUuid,
    };
