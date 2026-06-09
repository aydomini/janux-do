import 'package:flutter/widgets.dart';

class JavBusLayout {
  const JavBusLayout._();

  static const double compactBreakpoint = 860;
  static const double sidebarWidth = 300;
  static const double contentMaxWidth = 920;
  static const double textContentMaxWidth = 720;
  static const double contentHorizontalPadding = 24;
  static const double listHorizontalPadding = 24;
  static const double postMetaColumnWidth = 150;
  static const double topicReplyColumnWidth = 100;
  static const double topicViewsColumnWidth = 100;
  static const double topicTimeColumnWidth = 150;
  static const double mediaPreviewMinWidth = 260;
  static const double mediaPreviewMaxWidth = 480;
  static const double mediaPreviewHeight = 270;
  static const double inlineEmojiSize = 22;

  static const EdgeInsets listPadding = EdgeInsets.fromLTRB(
    listHorizontalPadding,
    8,
    listHorizontalPadding,
    24,
  );

  static const EdgeInsets threadPadding = EdgeInsets.fromLTRB(
    contentHorizontalPadding,
    18,
    contentHorizontalPadding,
    88,
  );
}
