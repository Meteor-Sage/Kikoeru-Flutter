import 'package:json_annotation/json_annotation.dart';
import 'package:equatable/equatable.dart';

part 'work.g.dart';

@JsonSerializable()
class Work extends Equatable {
  final int id;
  final String title;

  // API返回的是 circle_id 和 name，不是嵌套的circle对象
  @JsonKey(name: 'circle_id')
  final int? circleId;

  final String? name; // 这是circle的名称

  final List<Va>? vas;
  final List<Tag>? tags;
  final String? age;
  final String? release;

  @JsonKey(name: 'dl_count')
  final int? dlCount;

  final int? price; // price是int不是String

  @JsonKey(name: 'review_count')
  final int? reviewCount;

  @JsonKey(name: 'rate_count')
  final int? rateCount;

  @JsonKey(name: 'rate_average_2dp')
  final double? rateAverage;

  @JsonKey(name: 'has_subtitle')
  final bool? hasSubtitle;

  final int? duration; // 总时长(秒)

  final String?
      progress; // 收藏状态: marked, listening, listened, replay, postponed

  final List<String>? images;
  final String? description;
  final List<AudioFile>? children;

  const Work({
    required this.id,
    required this.title,
    this.circleId,
    this.name,
    this.vas,
    this.tags,
    this.age,
    this.release,
    this.dlCount,
    this.price,
    this.reviewCount,
    this.rateCount,
    this.rateAverage,
    this.hasSubtitle,
    this.duration,
    this.progress,
    this.images,
    this.description,
    this.children,
  });

  factory Work.fromJson(Map<String, dynamic> json) => _$WorkFromJson(json);

  Map<String, dynamic> toJson() => _$WorkToJson(this);

  String getCoverImageUrl(String baseUrl, {String? token}) {
    // 确保baseUrl包含协议前缀
    String normalizedUrl = baseUrl;
    if (baseUrl.isNotEmpty &&
        !baseUrl.startsWith('http://') &&
        !baseUrl.startsWith('https://')) {
      normalizedUrl = 'https://$baseUrl';
    }

    // 根据原始Java代码，封面图片URL格式为: /api/cover/{id}?token={token}
    if (token != null && token.isNotEmpty) {
      return '$normalizedUrl/api/cover/$id?token=$token';
    }
    return '$normalizedUrl/api/cover/$id';
  }

  String get circleTitle => name ?? '';

  @override
  List<Object?> get props => [
        id,
        title,
        circleId,
        name,
        vas,
        tags,
        age,
        release,
        dlCount,
        price,
        reviewCount,
        rateCount,
        rateAverage,
        hasSubtitle,
        duration,
        progress,
        images,
        description,
        children,
      ];
}

@JsonSerializable()
class Circle extends Equatable {
  final int id;

  @JsonKey(name: 'name')
  final String title;

  const Circle({required this.id, required this.title});

  factory Circle.fromJson(Map<String, dynamic> json) => _$CircleFromJson(json);

  Map<String, dynamic> toJson() => _$CircleToJson(this);

  @override
  List<Object?> get props => [id, title];
}

@JsonSerializable()
class Va extends Equatable {
  final String id; // Va的id是UUID字符串，不是int
  final String name;

  const Va({required this.id, required this.name});

  factory Va.fromJson(Map<String, dynamic> json) => _$VaFromJson(json);

  Map<String, dynamic> toJson() => _$VaToJson(this);

  @override
  List<Object?> get props => [id, name];
}

@JsonSerializable()
class Tag extends Equatable {
  final int id;
  final String name;

  const Tag({required this.id, required this.name});

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);

  Map<String, dynamic> toJson() => _$TagToJson(this);

  @override
  List<Object?> get props => [id, name];
}

@JsonSerializable()
class AudioFile extends Equatable {
  final String title;
  final String? type;
  final String? hash;
  final List<AudioFile>? children;

  const AudioFile({required this.title, this.type, this.hash, this.children});

  factory AudioFile.fromJson(Map<String, dynamic> json) =>
      _$AudioFileFromJson(json);

  Map<String, dynamic> toJson() => _$AudioFileToJson(this);

  bool get isFolder => type == 'folder';
  bool get isAudio => type == 'audio';
  bool get isText => type == 'text';
  bool get isImage => type == 'image';

  @override
  List<Object?> get props => [title, type, hash, children];
}
