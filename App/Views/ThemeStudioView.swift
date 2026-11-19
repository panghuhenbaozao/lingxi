import PhotosUI
import SwiftUI
import UIKit

extension Color {
    init(hexColor: HexColor, opacityScale: Double = 1.0) {
        let c = hexColor.rgba
        self.init(
            .sRGB,
            red: c.r,
            green: c.g,
            blue: c.b,
            opacity: c.a * opacityScale
        )
    }
}

struct ThemeStudioView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPhotoItem: PhotosPickerItem?

    private var activePreset: KeyboardThemePreset {
        appState.theme.activePreset(isSystemDark: colorScheme == .dark)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    previewCard
                    presetGrid
                    customBackgroundSection
                    keyAppearanceSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("皮肤工坊")
            .onChange(of: selectedPhotoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            appState.saveCustomBackgroundImage(uiImage)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 实时拟真预览

    private var previewCard: some View {
        let preset = activePreset
        let hasBg = appState.customBgPreview != nil
        let keyAlpha = hasBg ? appState.theme.keyOpacity : 1.0
        let radius = appState.theme.keyCornerRadius

        return VStack(spacing: 0) {
            // 顶部候选栏预览
            HStack(spacing: 10) {
                Text("✨ AI")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hexColor: preset.accentFill).opacity(0.18))
                    .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                    .clipShape(Capsule())

                Text("译")
                    .font(.caption.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(hexColor: preset.keyFill, opacityScale: keyAlpha))
                    .foregroundStyle(Color(hexColor: preset.keyText))
                    .clipShape(Capsule())

                Text("灵犀输入法")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(hexColor: preset.candidateHighlight))
                Text("真好看")
                    .font(.subheadline)
                    .foregroundStyle(Color(hexColor: preset.candidateText))
                Text("绝绝子")
                    .font(.subheadline)
                    .foregroundStyle(Color(hexColor: preset.candidateText))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(hexColor: preset.toolbarBackground).opacity(hasBg ? 0.85 : 1.0))

            // 模拟按键区
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    ForEach(["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"], id: \.self) { ch in
                        mockKey(ch, fill: Color(hexColor: preset.keyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius)
                    }
                }
                HStack(spacing: 5) {
                    ForEach(["A", "S", "D", "F", "G", "H", "J", "K", "L"], id: \.self) { ch in
                        mockKey(ch, fill: Color(hexColor: preset.keyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius)
                    }
                }
                .padding(.horizontal, 12)
                HStack(spacing: 5) {
                    mockKey("123", fill: Color(hexColor: preset.specialKeyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius, widthWeight: 1.4)
                    mockKey("中/英", fill: Color(hexColor: preset.specialKeyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius, widthWeight: 1.4)
                    mockKey("灵犀 · \(appState.settings.inputScheme.shortBadge)", fill: Color(hexColor: preset.keyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyHintText), radius: radius, widthWeight: 3.4)
                    mockKey("，", fill: Color(hexColor: preset.keyFill, opacityScale: keyAlpha), text: Color(hexColor: preset.keyText), radius: radius, widthWeight: 1.2)
                    mockKey("发送", fill: Color(hexColor: preset.accentFill), text: Color(hexColor: preset.accentText), radius: radius, widthWeight: 1.7)
                }
            }
            .padding(8)
        }
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(hexColor: preset.canvasTop), Color(hexColor: preset.canvasBottom)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if let bg = appState.customBgPreview {
                    Image(uiImage: bg)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: appState.theme.backgroundBlurRadius * 0.6)
                    (preset.isDark ? Color.black : Color.white)
                        .opacity(appState.theme.backgroundDimOpacity)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }

    private func mockKey(_ label: String, fill: Color, text: Color, radius: Double, widthWeight: Double = 1.0) -> some View {
        Text(label)
            .font(.system(size: label.count > 2 ? 11 : 14, weight: appState.theme.boldKeyLabel ? .semibold : .regular))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .layoutPriority(widthWeight)
    }

    // MARK: - 预设主题

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("精选预设主题")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(KeyboardThemePreset.presets) { preset in
                    let isSelected = (appState.theme.selectedThemeID == preset.id)
                    Button {
                        appState.theme.selectedThemeID = preset.id
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hexColor: preset.canvasTop), Color(hexColor: preset.canvasBottom)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                Circle()
                                    .fill(Color(hexColor: preset.accentFill))
                                    .frame(width: 14, height: 14)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text(preset.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 相册自定义背景

    private var customBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("自定义相册壁纸", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                Spacer()
                if appState.customBgPreview != nil {
                    Button("移除壁纸", role: .destructive) {
                        appState.removeCustomBackgroundImage()
                    }
                    .font(.caption.bold())
                }
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text(appState.customBgPreview == nil ? "从相册挑选一张照片作为键盘背景" : "更换背景图片（已自动压缩适配扩展内存）")
                        .font(.subheadline.bold())
                    Spacer()
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.12))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if appState.customBgPreview != nil {
                sliderRow(title: "背景模糊度", value: $appState.theme.backgroundBlurRadius, range: 0...24, format: "%.0f")
                sliderRow(title: "暗化/柔光遮罩", value: $appState.theme.backgroundDimOpacity, range: 0...0.75, format: "%.2f")
                sliderRow(title: "按键不透明度", value: $appState.theme.keyOpacity, range: 0.4...1.0, format: "%.2f")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 按键几何与深色模式联动

    private var keyAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("细节精调")
                .font(.headline)
            sliderRow(title: "按键圆角", value: $appState.theme.keyCornerRadius, range: 2...14, format: "%.0f pt")

            Toggle("键帽加粗字体", isOn: $appState.theme.boldKeyLabel)
            Toggle("跟随系统深色模式自动切换暗色主题", isOn: $appState.theme.adaptiveDarkMode)

            if appState.theme.adaptiveDarkMode {
                Picker("深色模式配对主题", selection: $appState.theme.darkThemeID) {
                    ForEach(KeyboardThemePreset.presets.filter(\.isDark)) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
