import AVFoundation
import Foundation
import UIKit
import WebKit

/// 键盘扩展内原生免跳转麦克风采集引擎（v5.7 行业前沿 Wispr Flow / Raycast / Dictus 同款方案）：
///
/// 核心原理：
/// - iOS 键盘扩展沙盒禁止进程直接调用 `AVAudioEngine` / `AVAudioSession` 录音（必报 `561017449 / !pri`）；
/// - 但在键盘视图内嵌入一个 1×1 透明 `WKWebView`（运行在系统独立的 `WebContent / GPU` 媒体进程中），
///   加载安全上下文 `https://lingxi-ime.pages.dev/` + `WKUIDelegate.requestMediaCapturePermissionFor(.grant)`，
///   即可通过标准 `navigator.mediaDevices.getUserMedia` + `AudioContext` 在微信/抖音键盘内**直接采集真实 16kHz 单声道 PCM 语音流**！
/// - 零跳转主 App、不依赖 App Group（免费个人 Apple ID 侧载 100% 畅通）、不依赖 `127.0.0.1` 回环，
///   且仅在用户点录音时按需创建，停止后立即释放轨道并关闭 `AudioContext`，确保内存安全远低于键盘 50MB 限制！
final class WebKitAudioCaptureEngine: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private static let handlerName = "lingxiMic"
    /// 最多缓存在内存中的 60 秒 16kHz 16-bit PCM（约 1.92 MB，严格防止键盘内存溢出）
    private static let maxBufferedPCMBytes = 16_000 * 2 * 60

    var onStarted: (() -> Void)?
    var onPCMChunk: ((Data, Float) -> Void)?
    var onError: ((String, String) -> Void)? // (code/name, readableMessage)

    private weak var hostView: UIView?
    private var webView: WKWebView?
    private var isPageReady = false
    private var wantsCapture = false
    private(set) var isCapturing = false
    private(set) var recordedPCM16 = Data()

    /// 弱引用桥接，彻底杜绝 `WKUserContentController` 强引用导致的内存泄漏
    private final class WeakMessageProxy: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(userContentController, didReceive: message)
        }
    }

    init(hostView: UIView) {
        self.hostView = hostView
        super.init()
    }

    deinit {
        teardown()
    }

    /// 预加载隐藏 WebView（几乎 0 负载），让用户点「开始说话」时毫秒级开麦
    func prewarmIfNeeded() {
        guard webView == nil, let hostView else { return }
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakMessageProxy(target: self), name: Self.handlerName)

        // 必须挂在可见视图树内（1×1、alpha 0.02、不可点击），否则 WebKit 会休眠不响应 getUserMedia
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.alpha = 0.02
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.isUserInteractionEnabled = false
        wv.uiDelegate = self
        wv.navigationDelegate = self
        hostView.addSubview(wv)
        self.webView = wv
        self.isPageReady = false

        let secureOrigin = URL(string: "https://lingxi-ime.pages.dev/")!
        wv.loadHTMLString(Self.captureHTML, baseURL: secureOrigin)
    }

    func startCapture() {
        recordedPCM16.removeAll(keepingCapacity: true)
        wantsCapture = true
        isCapturing = false
        prewarmIfNeeded()
        if isPageReady {
            evaluateStartJS()
        }
    }

    @discardableResult
    func stopCapture() -> Data {
        wantsCapture = false
        isCapturing = false
        webView?.evaluateJavaScript("window.lingxiStopMic && window.lingxiStopMic();", completionHandler: nil)
        return recordedPCM16
    }

    func teardown() {
        wantsCapture = false
        isCapturing = false
        if let wv = webView {
            wv.evaluateJavaScript("window.lingxiStopMic && window.lingxiStopMic();", completionHandler: nil)
            wv.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName)
            wv.uiDelegate = nil
            wv.navigationDelegate = nil
            wv.removeFromSuperview()
        }
        webView = nil
        isPageReady = false
        recordedPCM16.removeAll(keepingCapacity: false)
    }

    private func evaluateStartJS() {
        webView?.evaluateJavaScript("window.lingxiStartMic && window.lingxiStartMic();") { [weak self] _, err in
            if let err {
                self?.isCapturing = false
                self?.wantsCapture = false
                self?.onError?("JSEvalError", "语音桥接启动异常：\(err.localizedDescription)")
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageReady = true
        if wantsCapture {
            evaluateStartJS()
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // 系统在极端内存压力下回收了后台 WebContent 进程：自动重置句柄，下次点击毫秒级重建不黑屏不静默失效！
        let wasActive = wantsCapture || isCapturing
        teardown()
        if wasActive {
            onError?("WebContentTerminated", "系统回收了后台音频通道，请再点一次「开始说话」即可重新开麦")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isPageReady = false
        if wantsCapture {
            wantsCapture = false
            isCapturing = false
            onError?("NavigationFailed", "音频页面加载失败：\(error.localizedDescription)")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isPageReady = false
        if wantsCapture {
            wantsCapture = false
            isCapturing = false
            onError?("ProvisionalNavFailed", "音频环境初始化失败：\(error.localizedDescription)")
        }
    }

    // MARK: - WKUIDelegate（自动放行本域麦克风权限，避免弹出网页重复询问框）

    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        if type == .microphone {
            decisionHandler(.grant)
        } else {
            decisionHandler(.deny)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName,
              let dict = message.body as? [String: Any],
              let type = dict["t"] as? String else { return }

        switch type {
        case "started":
            isCapturing = true
            onStarted?()

        case "pcm":
            guard wantsCapture,
                  let b64 = dict["b64"] as? String,
                  let pcm = Data(base64Encoded: b64),
                  !pcm.isEmpty else { return }
            let rms = Float((dict["rms"] as? Double) ?? 0.0)
            if recordedPCM16.count + pcm.count <= Self.maxBufferedPCMBytes {
                recordedPCM16.append(pcm)
            }
            onPCMChunk?(pcm, rms)

        case "err":
            isCapturing = false
            wantsCapture = false
            let name = (dict["name"] as? String) ?? "MicError"
            let rawMsg = (dict["msg"] as? String) ?? "未知错误"
            let readable: String
            switch name {
            case "NotAllowedError", "PermissionDeniedError":
                readable = "未授予麦克风权限（请在「灵犀 App → 权限中心」或系统设置中开启麦克风权限）"
            case "NotFoundError", "DevicesNotFoundError":
                readable = "未检测到可用麦克风设备"
            case "NoMediaDevices":
                readable = "当前系统限制了扩展内网页麦克风通道"
            default:
                readable = "麦克风启动失败(\(name))：\(rawMsg)"
            }
            onError?(name, readable)

        default:
            break
        }
    }

    // MARK: - 16kHz 单声道 PCM 采集 HTML/JS（全本地内联，零外网加载耗时）

    private static let captureHTML = """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
    <body><script>
    (function() {
      let stream = null;
      let ctx = null;
      let source = null;
      let processor = null;
      let zeroGain = null;
      let active = false;

      function post(obj) {
        try { window.webkit.messageHandlers.lingxiMic.postMessage(obj); } catch (_) {}
      }

      function downsampleTo16kInt16(float32, inputRate) {
        const targetRate = 16000;
        let outLen;
        let out;
        if (inputRate <= targetRate) {
          outLen = float32.length;
          out = new Int16Array(outLen);
          for (let i = 0; i < outLen; i++) {
            const s = Math.max(-1, Math.min(1, float32[i]));
            out[i] = s < 0 ? s * 32768 : s * 32767;
          }
          return out;
        }
        const ratio = inputRate / targetRate;
        outLen = Math.floor(float32.length / ratio);
        out = new Int16Array(outLen);
        for (let i = 0; i < outLen; i++) {
          const pos = i * ratio;
          const idx = Math.floor(pos);
          const frac = pos - idx;
          const s0 = float32[idx] || 0;
          const s1 = float32[Math.min(idx + 1, float32.length - 1)] || s0;
          const s = Math.max(-1, Math.min(1, s0 + (s1 - s0) * frac));
          out[i] = s < 0 ? s * 32768 : s * 32767;
        }
        return out;
      }

      function int16ToBase64(int16Arr) {
        const bytes = new Uint8Array(int16Arr.buffer, int16Arr.byteOffset, int16Arr.byteLength);
        let bin = '';
        const chunk = 0x8000;
        for (let i = 0; i < bytes.length; i += chunk) {
          bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
        }
        return btoa(bin);
      }

      window.lingxiStopMic = function() {
        active = false;
        try { if (processor) { processor.onaudioprocess = null; processor.disconnect(); } } catch (_) {}
        try { if (source) source.disconnect(); } catch (_) {}
        try { if (zeroGain) zeroGain.disconnect(); } catch (_) {}
        try { if (stream) stream.getTracks().forEach(t => t.stop()); } catch (_) {}
        try { if (ctx && ctx.state !== 'closed') ctx.close(); } catch (_) {}
        processor = null; source = null; zeroGain = null; stream = null; ctx = null;
      };

      window.lingxiStartMic = async function() {
        window.lingxiStopMic();
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
          post({ t: 'err', name: 'NoMediaDevices', msg: 'navigator.mediaDevices unavailable (secure=' + window.isSecureContext + ')' });
          return;
        }
        try {
          stream = await navigator.mediaDevices.getUserMedia({
            audio: {
              channelCount: 1,
              echoCancellation: true,
              noiseSuppression: true,
              autoGainControl: true
            }
          });
          const AC = window.AudioContext || window.webkitAudioContext;
          ctx = new AC();
          if (ctx.state !== 'running') {
            await ctx.resume();
          }
          source = ctx.createMediaStreamSource(stream);
          processor = ctx.createScriptProcessor(4096, 1, 1);
          zeroGain = ctx.createGain();
          zeroGain.gain.value = 0;
          active = true;

          const inputRate = ctx.sampleRate || 48000;
          processor.onaudioprocess = function(ev) {
            if (!active) return;
            const ch = ev.inputBuffer.getChannelData(0);
            let sum = 0;
            for (let i = 0; i < ch.length; i++) sum += ch[i] * ch[i];
            const rms = Math.min(1.0, Math.sqrt(sum / Math.max(1, ch.length)) * 8.0);
            const pcm16 = downsampleTo16kInt16(ch, inputRate);
            if (pcm16.length > 0) {
              post({ t: 'pcm', rms: rms, b64: int16ToBase64(pcm16) });
            }
          };

          source.connect(processor);
          processor.connect(zeroGain);
          zeroGain.connect(ctx.destination);
          post({ t: 'started', sr: inputRate });
        } catch (e) {
          window.lingxiStopMic();
          post({ t: 'err', name: (e && e.name) || 'MicError', msg: (e && e.message) || String(e) });
        }
      };
    })();
    </script></body></html>
    """
}
