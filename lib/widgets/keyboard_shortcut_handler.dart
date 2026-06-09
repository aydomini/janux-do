import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_utils.dart';

/// 全局键盘快捷键处理器（简化版，仅桌面端后退快捷键）
class KeyboardShortcutHandler extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const KeyboardShortcutHandler({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<KeyboardShortcutHandler> createState() =>
      _KeyboardShortcutHandlerState();
}

class _KeyboardShortcutHandlerState extends State<KeyboardShortcutHandler> {
  @override
  void initState() {
    super.initState();
    if (PlatformUtils.isDesktop) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  @override
  void dispose() {
    if (PlatformUtils.isDesktop) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    // 焦点在文本输入框中时不拦截
    if (_isFocusInTextInput()) return false;

    // Escape / Backspace → 返回
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      widget.navigatorKey.currentState?.maybePop();
      return true;
    }

    return false;
  }

  bool _isFocusInTextInput() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context == null) return false;
    var element = focus!.context! as Element;
    var found = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
