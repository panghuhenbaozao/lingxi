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

    func prepare() {
        let now = CACurrentMediaTime()
        guard now - lastPrepareTime > 0.35 else { return }
        lastPrepareTime = now
        lightImpact.prepare()
        mediumImpact.prepare()
        rigidImpact.prepare()
        selectionFeedback.prepare()
    }

    func triggerKeyFeedback(tone: KeyTone = .letter, settings: LingxiSettings, hasFullAccess: Bool) {
        if settings.keySoundEnabled {
            playSound(tone: tone, hasFullAccess: hasFullAccess)
        }
        switch settings.hapticStrength {
        case .off:
            break
        case .light:
            lightImpact.impactOccurred(intensity: tone == .letter ? 0.62 : 0.8)
            lightImpact.prepare()
        case .medium:
            mediumImpact.impactOccurred(intensity: tone == .letter ? 0.78 : 0.92)
            mediumImpact.prepare()
        case .strong:
            rigidImpact.impactOccurred(intensity: 0.95)
            rigidImpact.prepare()
        }
    }

    func triggerCursorTick(settings: LingxiSettings) {
        guard settings.hapticStrength != .off else { return }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    private func playSound(tone: KeyTone, hasFullAccess: Bool) {
        if hasFullAccess {
            let soundID: SystemSoundID
            switch tone {
            case .letter: soundID = 1104
            case .delete: soundID = 1155
            case .modifier: soundID = 1156
            }
            AudioServicesPlaySystemSound(soundID)
        } else {
            UIDevice.current.playInputClick()
        }
    }
}
