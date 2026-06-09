import Cocoa
import FlutterMacOS
import WebKit

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false  // 关闭窗口时不退出，保持 MessageBus 运行
  }

  // 点击 Dock 图标时重新显示窗口
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      super.applicationDidFinishLaunching(notification)
      return
    }

    // Raw Set-Cookie 写入通道
    let rawCookieChannel = FlutterMethodChannel(
      name: "com.fluxdo/raw_cookie",
      binaryMessenger: controller.engine.binaryMessenger
    )
    rawCookieChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setRawCookie":
        guard let args = call.arguments as? [String: Any],
              let urlString = args["url"] as? String,
              let rawSetCookie = args["rawSetCookie"] as? String,
              let url = URL(string: urlString) else {
          result(false)
          return
        }
        let headers = ["Set-Cookie": rawSetCookie]
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        guard let cookie = cookies.first else {
          result(false)
          return
        }
        // 同时写入 HTTPCookieStorage.shared，配合 sharedCookiesEnabled
        // 确保 WKWebView 在创建时即可从 shared storage 读取到 cookie
        HTTPCookieStorage.shared.setCookie(cookie)
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.setCookie(cookie) {
          result(true)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.applicationDidFinishLaunching(notification)
  }
}
