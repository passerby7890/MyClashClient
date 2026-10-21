// lib/business/auth/notice_model.dart

/// 機場公告模型 (對齊 V2Board /api/v1/user/notice/fetch)
class NoticeModel {
  final int id;
  final String title;
  final String content;
  final bool show;
  final String? imgUrl;
  final List<String> tags;
  final int createdAt;

  const NoticeModel({
    required this.id,
    required this.title,
    required this.content,
    required this.show,
    this.imgUrl,
    required this.tags,
    required this.createdAt,
  });

  /// 是否為強制彈窗公告 (包含 "弹窗" 標籤)
  bool get isPopup => tags.any((t) => t.contains('弹窗') || t.contains('彈窗'));

  /// 移除 HTML 標籤後之乾淨文本內容 (供純文本 Dialog 呈現)
  String get cleanContent {
    return content
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  factory NoticeModel.fromJson(Map<String, dynamic> json) {
    List<String> parseTags(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
    }

    return NoticeModel(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '系統公告',
      content: json['content'] as String? ?? '',
      show: (json['show'] as int? ?? 1) == 1,
      imgUrl: json['img_url'] as String?,
      tags: parseTags(json['tags']),
      createdAt: json['created_at'] as int? ?? 0,
    );
  }
}
