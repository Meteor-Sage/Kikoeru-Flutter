import 'package:json_annotation/json_annotation.dart';
import 'package:equatable/equatable.dart';

part 'work.g.dart';

@JsonSerializable()
class Work extends Equatable {
  final int id;
  final String title;

  @JsonKey(name: 'circle_id')
  final int? circleId;

  final String? name; // circle名称

  final List<Va>? vas;
  final List<Tag>? tags;
  final String? age;
  final String? release;

  @JsonKey(name: 'dl_count')
  final int? dlCount;

  final int? price;

  @JsonKey(name: 'review_count')
  final int? reviewCount;

  @JsonKey(name: 'rate_count')
  final int? rateCount;

  @JsonKey(name: 'rate_average_2dp')
  final double? rateAverage;

  @JsonKey(name: 'has_subtitle')
  final bool? hasSubtitle;

  final int? duration;

  final String?
      progress; // 收藏状态: marked, listening, listened, replay, postponed

  @JsonKey(name: 'userRating')
  final int? userRating; // 用户评分: 1-5星

  @JsonKey(name: 'rate_count_detail')
  final List<RatingDetail>? rateCountDetail; // 评分详情

  final List<String>? images;
  final String? description;
  final List<AudioFile>? children;

  @JsonKey(name: 'source_url')
  final String? sourceUrl; // 作品原始链接

  @JsonKey(name: 'other_language_editions_in_db')
  final List<OtherLanguageEdition>? otherLanguageEditions; // 其他语言版本

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
    this.userRating,
    this.rateCountDetail,
    this.images,
    this.description,
    this.children,
    this.sourceUrl,
    this.otherLanguageEditions,
  });

  factory Work.fromJson(Map<String, dynamic> json) => _$WorkFromJson(json);

  Map<String, dynamic> toJson() => _$WorkToJson(this);

  String getCoverImageUrl(String baseUrl, {String? token}) {
    String normalizedUrl = baseUrl;
    if (baseUrl.isNotEmpty &&
        !baseUrl.startsWith('http://') &&
        !baseUrl.startsWith('https://')) {
      normalizedUrl = 'https://$baseUrl';
    }

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
        userRating,
        rateCountDetail,
        images,
        description,
        children,
        sourceUrl,
        otherLanguageEditions,
      ];
}

@JsonSerializable()
class OtherLanguageEdition extends Equatable {
  final int id;
  final String lang;
  final String title;

  @JsonKey(name: 'source_id')
  final String sourceId;

  @JsonKey(name: 'is_original')
  final bool isOriginal;

  @JsonKey(name: 'source_type')
  final String sourceType;

  const OtherLanguageEdition({
    required this.id,
    required this.lang,
    required this.title,
    required this.sourceId,
    required this.isOriginal,
    required this.sourceType,
  });

  factory OtherLanguageEdition.fromJson(Map<String, dynamic> json) =>
      _$OtherLanguageEditionFromJson(json);

  Map<String, dynamic> toJson() => _$OtherLanguageEditionToJson(this);

  @override
  List<Object?> get props =>
      [id, lang, title, sourceId, isOriginal, sourceType];
}

@JsonSerializable()
class RatingDetail extends Equatable {
  @JsonKey(name: 'review_point')
  final int reviewPoint;

  final int count;
  final int ratio;

  const RatingDetail({
    required this.reviewPoint,
    required this.count,
    required this.ratio,
  });

  factory RatingDetail.fromJson(Map<String, dynamic> json) =>
      _$RatingDetailFromJson(json);

  Map<String, dynamic> toJson() => _$RatingDetailToJson(this);

  @override
  List<Object?> get props => [reviewPoint, count, ratio];
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
  final String id;
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
  final int? upvote; // 支持投票数量
  final int? downvote; // 反对投票数量

  @JsonKey(name: 'myVote')
  final int? myVote; // 我的投票状态：0=未投票，1=支持，2=反对

  const Tag({
    required this.id,
    required this.name,
    this.upvote,
    this.downvote,
    this.myVote,
  });

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);

  Map<String, dynamic> toJson() => _$TagToJson(this);

  @override
  List<Object?> get props => [id, name, upvote, downvote, myVote];
}

@JsonSerializable()
class AudioFile extends Equatable {
  final String title;
  final String? type;
  final String? hash;
  final List<AudioFile>? children;

  @JsonKey(name: 'mediaDownloadUrl')
  final String? mediaDownloadUrl;

  final int? size;
  final dynamic duration; // 时长（秒），可能是 int 或 double

  const AudioFile({
    required this.title,
    this.type,
    this.hash,
    this.children,
    this.mediaDownloadUrl,
    this.size,
    this.duration,
  });

  factory AudioFile.fromJson(Map<String, dynamic> json) =>
      _$AudioFileFromJson(json);

  Map<String, dynamic> toJson() => _$AudioFileToJson(this);

  bool get isFolder => type == 'folder';
  bool get isAudio => type == 'audio';
  bool get isText => type == 'text';
  bool get isImage => type == 'image';

  @override
  List<Object?> get props =>
      [title, type, hash, children, mediaDownloadUrl, size, duration];
}
