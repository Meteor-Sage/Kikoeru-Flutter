import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:equatable/equatable.dart';

@HiveType(typeId: 0)
@JsonSerializable()
class User extends Equatable {
  @HiveField(0)
  final int? id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String? password;

  @HiveField(3)
  final String? host;

  @HiveField(4)
  final String? token;

  @HiveField(5)
  final DateTime? lastUpdateTime;

  @HiveField(6)
  final bool loggedIn;

  @HiveField(7)
  final String? group;

  @HiveField(8)
  final String? email;

  @HiveField(9)
  final String? recommenderUuid;

  const User({
    this.id,
    required this.name,
    this.password,
    this.host,
    this.token,
    this.lastUpdateTime,
    this.loggedIn = false,
    this.group,
    this.email,
    this.recommenderUuid,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] ?? json;

    return User(
      name: userJson['name'] as String? ?? '',
      loggedIn:
          (userJson['loggedIn'] as bool?) ?? (json['auth'] as bool?) ?? false,
      group: userJson['group'] as String?,
      email: userJson['email'] as String?,
      recommenderUuid: userJson['recommenderUuid'] as String?,
      password: json['password'] as String?,
      host: json['host'] as String?,
      token: json['token'] as String?,
      id: json['id'] as int?,
      lastUpdateTime: json['lastUpdateTime'] != null
          ? DateTime.parse(json['lastUpdateTime'] as String)
          : null,
    );
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'password': password,
      'host': host,
      'token': token,
      'lastUpdateTime': lastUpdateTime?.toIso8601String(),
      'loggedIn': loggedIn,
      'group': group,
      'email': email,
      'recommenderUuid': recommenderUuid,
    };
  }

  User copyWith({
    int? id,
    String? name,
    String? password,
    String? host,
    String? token,
    DateTime? lastUpdateTime,
    bool? loggedIn,
    String? group,
    String? email,
    String? recommenderUuid,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      password: password ?? this.password,
      host: host ?? this.host,
      token: token ?? this.token,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      loggedIn: loggedIn ?? this.loggedIn,
      group: group ?? this.group,
      email: email ?? this.email,
      recommenderUuid: recommenderUuid ?? this.recommenderUuid,
    );
  }

  String get formattedHost {
    final hostValue = host ?? '';
    if (hostValue.startsWith('http')) {
      return hostValue;
    } else {
      return 'http://$hostValue';
    }
  }

  @override
  List<Object?> get props => [
        id,
        name,
        password,
        host,
        token,
        lastUpdateTime,
        loggedIn,
        group,
        email,
        recommenderUuid
      ];
}
