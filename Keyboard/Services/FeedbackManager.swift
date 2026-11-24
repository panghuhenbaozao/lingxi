import AudioToolbox
import UIKit

/// 按键震动与音效反馈管理器。
///
/// - 震动：预热 `UIImpactFeedbackGenerator`，消除首次按键延迟。
/// - 音效：支持系统标准键盘音（需开启完全访问时区分字符/删除/功能键），无完全访问时优雅退回 `UIDevice.current.playInputClick()`。
final class FeedbackManager {
    enum KeyTone {
        case letter
        case delete
        case modifier
    }

    private var lightImpact = UIImpactFeedbackGenerator(style: .light)
    private var mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private var rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private var selectionFeedback = UISelectionFeedbackGenerator()
    private var lastPrepareTime: CFTimeInterval = 0
    private var lastFeedbackTime: CFTimeInterval = 0
    private let audioQueue = DispatchQueue(label: "com.lingxi.keyaudio", qos: .userInteractive)

    func prepare() {
        let now = CACurrentMediaTime()
        guard now - lastPrepareTime > 0.6 else { return }
        lastPrepareTime = now
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        selectionFeedback.prepare()
    }

    func triggerKeyFeedback(tone: KeyTone = .letter, settings: LingxiSettings, hasFullAccess: Bool) {
        let now = CACurrentMediaTime()
        // 极高速连打（< 22ms 同帧滚键）合并震动与音效，防止主线程与 Taptic Engine 排队卡顿
        guard now - lastFeedbackTime >= 0.022 else { return }
        lastFeedbackTime = now
        if settings.keySoundEnabled {
            playSound(tone: tone, hasFullAccess: hasFullAccess)
        }
        switch settings.hapticStrength {
        case .off:
            break
        case .light:
            lightImpact.impactOccurred(intensity: tone == .letter ? 0.62 : 0.8)
        case .medium:
            mediumImpact.impactOccurred(intensity: tone == .letter ? 0.78 : 0.92)
        case .strong:
            rigidImpact.impactOccurred(intensity: 0.95)
        }
    }

    func triggerCursorTick(settings: LingxiSettings) {
        guard settings.hapticStrength != .off else { return }
        selectionFeedback.selectionChanged()
    }

    /// 动态音效：光标/滑行/滑动指示（每步小声滴，给“动”的节奏感）
    func triggerCursorSound(settings: LingxiSettings) {
        guard settings.keySoundEnabled else { return }
        UIDevice.current.playInputClick()
    }

    private func playSound(tone: KeyTone, hasFullAccess: Bool) {
        if hasFullAccess {
            let soundID: SystemSoundID
            switch tone {
            case .letter: soundID = 1104
            case .delete: soundID = 1155
            case .modifier: soundID = 1156
            }
            audioQueue.async {
                AudioServicesPlaySystemSound(soundID)
            }
        } else {
            UIDevice.current.playInputClick()
        }
    }
}
