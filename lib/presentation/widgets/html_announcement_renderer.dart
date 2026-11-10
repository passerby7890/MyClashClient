// lib/presentation/widgets/html_announcement_renderer.dart
//
// 零新增依賴之原生 HTML 富文本與 Emoji 公告渲染引擎
// 支援標題、段落、換行、粗體、字體顏色與大小樣式、科技感分隔線、超連結點擊與 Emoji 跨平台原色回退

import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as ul;

/// 跨平台安全原生 URL 開啟器 (具備協定白名單、Markdown 容錯與系統原生跳轉)
class NativeUrlOpener {
  static const List<String> _allowedSchemes = ['https://', 'http://', 'tg://'];

  static Future<bool> open(String url) async {
    String cleanUrl = url.trim();

    // 若誤貼 markdown 語法 [xxx](https://...)，提取括弧內的真實網址
    final mdMatch = RegExp(r'\((https?:\/\/[^\s\)]+|tg:\/\/[^\s\)]+)\)').firstMatch(cleanUrl);
    if (mdMatch != null && mdMatch.group(1) != null) {
      cleanUrl = mdMatch.group(1)!;
    } else {
      // 剝除可能的外圍中括號或引號
      cleanUrl = cleanUrl.replaceAll(RegExp(r'^[\[\("]+|[\]\)"\s]+$'), '').trim();
    }

    final isAllowed = _allowedSchemes.any(
      (scheme) => cleanUrl.toLowerCase().startsWith(scheme),
    );
    if (!isAllowed) {
      debugPrint('NativeUrlOpener rejected disallowed URL: $url (cleaned: $cleanUrl)');
      return false;
    }

    debugPrint('NativeUrlOpener opening: $cleanUrl');

    // 1. macOS 端：優先使用原生 open 命令
    if (Platform.isMacOS) {
      try {
        await Process.run('open', [cleanUrl]);
        return true;
      } catch (e) {
        debugPrint('macOS Process.run open failed: $e');
      }
    }

    // 2. Windows 端：原生 cmd /c start
    if (Platform.isWindows) {
      try {
        await Process.run('cmd', ['/c', 'start', '', cleanUrl], runInShell: true);
        return true;
      } catch (e) {
        debugPrint('Windows Process.run cmd start failed: $e');
      }
    }

    // 3. 次選使用 url_launcher
    try {
      final uri = Uri.tryParse(cleanUrl);
      if (uri != null) {
        final success = await ul.launchUrl(
          uri,
          mode: ul.LaunchMode.externalApplication,
        );
        if (success) return true;
      }
    } catch (e) {
      debugPrint('url_launcher failed: $e');
    }

    return false;
  }
}

/// 智慧優惠碼擷取器
class CouponExtractor {
  static String? extract(String html) {
    if (html.isEmpty) return null;

    // 1. 匹配關鍵字後包含在標籤內的英數代碼
    final p1 = RegExp(
      r'(?:優惠碼|优惠码|折扣碼|折扣码|Coupon)[:：\s]*<[^>]*>([A-Za-z0-9_]{4,20})<\/[^>]*>',
      caseSensitive: false,
    );
    final m1 = p1.firstMatch(html);
    if (m1 != null && m1.group(1) != null) {
      return m1.group(1)!.trim();
    }

    // 2. 匹配關鍵字後緊接的英數代碼
    final p2 = RegExp(
      r'(?:優惠碼|优惠码|折扣碼|折扣码|Coupon)[:：\s]*([A-Za-z0-9_]{4,20})',
      caseSensitive: false,
    );
    final m2 = p2.firstMatch(html);
    if (m2 != null && m2.group(1) != null) {
      return m2.group(1)!.trim();
    }

    // 3. 匹配帶有顏色樣式的 strong 標籤（如 <strong style="color: #e74c3c...">20261111</strong>）
    final p3 = RegExp(
      r'<strong[^>]*style=["\x27][^"\x27]*color:[^"\x27]*["\x27][^>]*>([A-Za-z0-9_]{4,20})<\/strong>',
      caseSensitive: false,
    );
    final m3 = p3.firstMatch(html);
    if (m3 != null && m3.group(1) != null) {
      return m3.group(1)!.trim();
    }

    // 4. 老用戶通用優惠碼備援
    if (html.contains('buyback')) {
      return 'buyback';
    }

    return null;
  }
}

/// 區塊元素封裝
class _HtmlBlock {
  final String type; // 'h1', 'h2', 'h3', 'h4', 'p', 'hr'
  final String content;
  _HtmlBlock(this.type, this.content);
}

/// 行內樣式封裝
class _InlineSpanData {
  final String text;
  final bool isBold;
  final bool isItalic;
  final Color? color;
  final double? fontSize;
  final String? linkUrl;

  _InlineSpanData({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.color,
    this.fontSize,
    this.linkUrl,
  });
}

/// 原生 HTML 公告渲染器
class HtmlAnnouncementRenderer extends StatefulWidget {
  final String html;
  final TextStyle? defaultTextStyle;

  const HtmlAnnouncementRenderer({
    super.key,
    required this.html,
    this.defaultTextStyle,
  });

  /// 彩色 Emoji 跨平台字型回退鏈
  static const List<String> emojiFontFallback = [
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Noto Color Emoji',
    'Microsoft YaHei',
    'PingFang SC',
  ];

  @override
  State<HtmlAnnouncementRenderer> createState() => _HtmlAnnouncementRendererState();
}

class _HtmlAnnouncementRendererState extends State<HtmlAnnouncementRenderer> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    // 釋放所有手勢辨識器，避免記憶體洩漏
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 零 Crash 防禦：若解析異常則降級至純文字
    try {
      final blocks = _parseBlocks(widget.html);
      if (blocks.isEmpty) {
        return SelectableText(
          widget.html,
          style: widget.defaultTextStyle ?? const TextStyle(color: Colors.white, fontSize: 14),
        );
      }

      final widgets = <Widget>[];
      for (int i = 0; i < blocks.length; i++) {
        final block = blocks[i];
        if (block.type == 'hr') {
          widgets.add(
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, thickness: 1, color: Color(0xFF1E293B)),
            ),
          );
        } else {
          final spans = _parseInlineSpans(block.content, block.type);
          widgets.add(
            Padding(
              padding: EdgeInsets.only(
                bottom: block.type.startsWith('h') ? 10 : 8,
                top: block.type.startsWith('h') && i > 0 ? 6 : 0,
              ),
              child: Text.rich(
                TextSpan(children: spans),
                style: widget.defaultTextStyle ??
                    const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Color(0xFFE2E8F0),
                      fontFamilyFallback: HtmlAnnouncementRenderer.emojiFontFallback,
                    ),
              ),
            ),
          );
        }
      }

      return SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: widgets,
        ),
      );
    } catch (e) {
      debugPrint('HtmlAnnouncementRenderer fallback: $e');
      return SelectableText(
        widget.html.replaceAll(RegExp(r'<[^>]*>'), ''),
        style: widget.defaultTextStyle ?? const TextStyle(color: Colors.white, fontSize: 14),
      );
    }
  }

  List<_HtmlBlock> _parseBlocks(String raw) {
    final blocks = <_HtmlBlock>[];
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final blockRegExp = RegExp(
      r'(<h[1-6][^>]*>[\s\S]*?<\/h[1-6]>|<p[^>]*>[\s\S]*?<\/p>|<hr\s*\/?>)',
      caseSensitive: false,
    );

    int lastEnd = 0;
    for (final match in blockRegExp.allMatches(text)) {
      if (match.start > lastEnd) {
        final lead = text.substring(lastEnd, match.start).trim();
        if (lead.isNotEmpty) {
          blocks.add(_HtmlBlock('p', lead));
        }
      }

      final matchStr = match.group(0)!;
      if (RegExp(r'<hr\s*\/?>', caseSensitive: false).hasMatch(matchStr)) {
        blocks.add(_HtmlBlock('hr', ''));
      } else {
        final hMatch = RegExp(r'<h([1-6])[^>]*>([\s\S]*?)<\/h\1>', caseSensitive: false).firstMatch(matchStr);
        if (hMatch != null) {
          blocks.add(_HtmlBlock('h${hMatch.group(1)}', hMatch.group(2)!.trim()));
        } else {
          final pMatch = RegExp(r'<p[^>]*>([\s\S]*?)<\/p>', caseSensitive: false).firstMatch(matchStr);
          if (pMatch != null) {
            blocks.add(_HtmlBlock('p', pMatch.group(1)!.trim()));
          } else {
            blocks.add(_HtmlBlock('p', matchStr.trim()));
          }
        }
      }
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      final tail = text.substring(lastEnd).trim();
      if (tail.isNotEmpty) {
        blocks.add(_HtmlBlock('p', tail));
      }
    }

    return blocks;
  }

  List<InlineSpan> _parseInlineSpans(String raw, String blockType) {
    final spansData = _parseInlineData(raw);
    final spans = <InlineSpan>[];

    final isHeading = blockType.startsWith('h');
    double defaultSize = 14.0;
    FontWeight defaultWeight = FontWeight.normal;
    Color defaultColor = const Color(0xFFE2E8F0);

    if (isHeading) {
      switch (blockType) {
        case 'h1':
          defaultSize = 20.0;
          defaultWeight = FontWeight.bold;
          defaultColor = Colors.white;
          break;
        case 'h2':
          defaultSize = 18.0;
          defaultWeight = FontWeight.bold;
          defaultColor = Colors.white;
          break;
        case 'h3':
          defaultSize = 17.0;
          defaultWeight = FontWeight.bold;
          defaultColor = const Color(0xFFF8FAFC);
          break;
        case 'h4':
        default:
          defaultSize = 15.0;
          defaultWeight = FontWeight.bold;
          defaultColor = const Color(0xFFF8FAFC);
          break;
      }
    }

    for (final d in spansData) {
      final link = d.linkUrl;
      TapGestureRecognizer? recognizer;

      if (link != null && link.isNotEmpty) {
        recognizer = TapGestureRecognizer()
          ..onTap = () {
            NativeUrlOpener.open(link);
          };
        _recognizers.add(recognizer);
      }

      final color = link != null
          ? const Color(0xFF38BDF8)
          : (d.color ?? defaultColor);

      final weight = isHeading
          ? FontWeight.bold
          : (d.isBold ? FontWeight.bold : defaultWeight);

      final decoration = link != null ? TextDecoration.underline : TextDecoration.none;
      final decorationColor = link != null ? const Color(0xFF38BDF8) : null;

      spans.add(
        TextSpan(
          text: d.text,
          recognizer: recognizer,
          mouseCursor: link != null ? SystemMouseCursors.click : MouseCursor.defer,
          style: TextStyle(
            fontSize: d.fontSize ?? defaultSize,
            fontWeight: weight,
            fontStyle: d.isItalic ? FontStyle.italic : FontStyle.normal,
            color: color,
            decoration: decoration,
            decorationColor: decorationColor,
            fontFamilyFallback: HtmlAnnouncementRenderer.emojiFontFallback,
          ),
        ),
      );
    }

    return spans;
  }

  List<_InlineSpanData> _parseInlineData(String raw) {
    final spans = <_InlineSpanData>[];
    final text = raw.replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n');

    final tagRegex = RegExp(
      r'(<a\s+[^>]*href=["\x27]([^"\x27]+)["\x27][^>]*>([\s\S]*?)<\/a>|\[([^\]]+)\]\(((?:https?:\/\/|tg:\/\/)[^\s\)]+)\)|<strong\s*([^>]*)>([\s\S]*?)<\/strong>|<b\s*([^>]*)>([\s\S]*?)<\/b>|<span\s*([^>]*)>([\s\S]*?)<\/span>)',
      caseSensitive: false,
    );

    int lastIndex = 0;
    for (final match in tagRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        final plain = text.substring(lastIndex, match.start);
        if (plain.isNotEmpty) {
          spans.add(_InlineSpanData(text: _unescapeHtml(plain)));
        }
      }

      final fullMatch = match.group(0)!;

      if (match.group(2) != null) {
        // <a href="...">
        final href = match.group(2)!;
        final inner = match.group(3)!;
        final subSpans = _parseInlineData(inner);
        for (final s in subSpans) {
          String linkText = s.text;
          // 若標籤內部文字誤貼 Markdown 格式 [顯示名稱](網址) 或 [網址](網址)，提取清晰標題
          final mdTextMatch = RegExp(r'^\[([\s\S]*?)\]\(([^\)]+)\)$').firstMatch(linkText.trim());
          if (mdTextMatch != null) {
            linkText = mdTextMatch.group(1)!.trim();
          }
          spans.add(_InlineSpanData(
            text: linkText,
            isBold: s.isBold || inner.contains('<strong>') || inner.contains('<b>'),
            isItalic: s.isItalic,
            color: s.color,
            fontSize: s.fontSize,
            linkUrl: href,
          ));
        }
      } else if (match.group(4) != null && match.group(5) != null) {
        // Markdown 語法原生支援：[顯示文字](網址)
        final mdText = match.group(4)!;
        final mdUrl = match.group(5)!;
        spans.add(_InlineSpanData(
          text: _unescapeHtml(mdText),
          linkUrl: mdUrl,
        ));
      } else if (fullMatch.toLowerCase().startsWith('<strong') || fullMatch.toLowerCase().startsWith('<b')) {
        // <strong> 或 <b>
        final attrs = match.group(6) ?? match.group(8) ?? '';
        final inner = match.group(7) ?? match.group(9) ?? '';
        final style = _parseStyle(attrs);

        final subSpans = _parseInlineData(inner);
        for (final s in subSpans) {
          spans.add(_InlineSpanData(
            text: s.text,
            isBold: true,
            isItalic: s.isItalic,
            color: style.color ?? s.color,
            fontSize: style.fontSize ?? s.fontSize,
            linkUrl: s.linkUrl,
          ));
        }
      } else if (fullMatch.toLowerCase().startsWith('<span')) {
        // <span>
        final attrs = match.group(10) ?? '';
        final inner = match.group(11) ?? '';
        final style = _parseStyle(attrs);

        final subSpans = _parseInlineData(inner);
        for (final s in subSpans) {
          spans.add(_InlineSpanData(
            text: s.text,
            isBold: s.isBold,
            isItalic: s.isItalic,
            color: style.color ?? s.color,
            fontSize: style.fontSize ?? s.fontSize,
            linkUrl: s.linkUrl,
          ));
        }
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      final plain = text.substring(lastIndex);
      if (plain.isNotEmpty) {
        spans.add(_InlineSpanData(text: _unescapeHtml(plain)));
      }
    }

    return spans;
  }

  _ParsedStyle _parseStyle(String attrs) {
    Color? color;
    double? fontSize;

    final styleMatch = RegExp(r'style=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(attrs);
    if (styleMatch != null) {
      final styleContent = styleMatch.group(1)!;
      final pairs = styleContent.split(';');
      for (final p in pairs) {
        final parts = p.split(':');
        if (parts.length == 2) {
          final k = parts[0].trim().toLowerCase();
          final v = parts[1].trim().toLowerCase();

          if (k == 'color') {
            color = _parseColor(v);
          } else if (k == 'font-size') {
            final numVal = double.tryParse(v.replaceAll('px', '').replaceAll('pt', '').trim());
            if (numVal != null) {
              fontSize = numVal.clamp(12.0, 28.0);
            }
          }
        }
      }
    }

    // 相容 <font color="...">
    final colorAttrMatch = RegExp(r'color=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(attrs);
    if (colorAttrMatch != null && color == null) {
      color = _parseColor(colorAttrMatch.group(1)!.trim());
    }

    return _ParsedStyle(color: color, fontSize: fontSize);
  }

  Color? _parseColor(String raw) {
    final hexMatch = RegExp(r'^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$').firstMatch(raw);
    if (hexMatch != null) {
      var hex = hexMatch.group(1)!;
      if (hex.length == 3) {
        hex = hex.split('').map((c) => '$c$c').join();
      }
      final intVal = int.tryParse(hex, radix: 16);
      if (intVal != null) {
        return Color(0xFF000000 | intVal);
      }
    }

    switch (raw.toLowerCase()) {
      case 'red':
        return const Color(0xFFEF4444);
      case 'green':
        return const Color(0xFF10B981);
      case 'blue':
        return const Color(0xFF3B82F6);
      case 'yellow':
        return const Color(0xFFF59E0B);
      case 'orange':
        return const Color(0xFFF97316);
      case 'cyan':
        return const Color(0xFF06B6D4);
      case 'white':
        return Colors.white;
    }
    return null;
  }

  String _unescapeHtml(String s) {
    return s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\[cite:\s*\d+\]', caseSensitive: false), '');
  }
}

class _ParsedStyle {
  final Color? color;
  final double? fontSize;
  _ParsedStyle({this.color, this.fontSize});
}

