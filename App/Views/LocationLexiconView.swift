import CoreLocation
import SwiftUI
import UIKit

/// 实时位置与周边地名学习（v6）：位置只存本机，用于提升本地地名的打字命中率。
struct LocationLexiconView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showClearConfirm = false
    @ObservedObject private var locationService = LiveLocationLexiconService.shared
    @State private var manualCityInput: String = ""
    @State private var selectedCategory: String = "全部"
    @State private var toast: String?
    @FocusState private var cityFocused: Bool

    private let quickCities = ["北京", "上海", "广州", "深圳", "杭州", "成都", "南京", "苏州", "西安", "青岛", "济南", "临沂"]
    private let categories = ["全部", "城市", "区县", "街道", "商圈", "交通", "高校", "小区", "地标"]

    private var context: GeoLocationContext { locationService.currentContext }

    private var isDenied: Bool {
        locationService.authorizationStatus == .denied || locationService.authorizationStatus == .restricted
    }

    var body: some View {
        List {
            currentSection
            switchesSection
            manualSection
            if !context.pois.isEmpty {
                poiSection
                Section {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("清除已学会的周边地名")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .lxToast($toast)
        .confirmationDialog("清除位置缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                locationService.clearLocationContext()
                toast = "已清除周边地名"
            }
        } message: {
            Text("已学会的周边地名会被清空，下次定位时重新学习。全国内置地名不受影响。")
        }
        .navigationTitle("实时地名词库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { cityFocused = false }
            }
        }
        .onAppear {
            locationService.reloadFromDisk()
        }
    }

    // MARK: - 1. 当前位置

    private var currentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    LXIconTile(
                        icon: context.isPopulated ? "location.fill" : "location.slash",
                        tint: context.isPopulated ? Color(Design.Palette.accent) : Color(Design.Palette.stone),
                        size: 44
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.isPopulated ? context.compactLocationLabel : "还没有获取位置")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(Color(Design.Palette.ink))
                            .lineLimit(2)
                        Text(context.isPopulated
                             ? "已学会 \(context.pois.count) 个附近的地名"
                             : "全国 6,403 个省市区县已内置；定位后还会学习附近 5 公里的路名、商圈和车站")
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !context.fullDisplayAddress.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text(context.fullDisplayAddress)
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.charcoal))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = context.fullDisplayAddress
                            toast = "已复制地址"
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(LXCapsuleButtonStyle(prominent: false))
                        .accessibilityLabel("复制地址")
                    }
                    .padding(10)
                    .background(Color(Design.Palette.surface), in: RoundedRectangle(cornerRadius: Design.Radius.input, style: .continuous))
                }

                if isDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("位置权限已关闭，去设置打开", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true, tint: Color(Design.Palette.warning)))
                } else {
                    Button {
                        Task { await locationService.refreshLiveGPSAndNearbyPOIs() }
                    } label: {
                        HStack(spacing: 6) {
                            if locationService.isLocating {
                                ProgressView().controlSize(.small).tint(Color.white)
                            } else {
                                Image(systemName: "location.circle.fill")
                            }
                            Text(locationService.isLocating ? "正在定位并学习附近地名…" : (context.isPopulated ? "重新定位" : "定位并学习附近地名"))
                        }
                    }
                    .buttonStyle(LXCapsuleButtonStyle(prominent: true, wide: true))
                    .disabled(locationService.isLocating)
                }

                if !locationService.statusMessage.isEmpty {
                    let ok = locationService.statusMessage.hasPrefix("✓")
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: ok ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(ok ? Color(Design.Palette.success) : Color(Design.Palette.stone))
                            .padding(.top, 1)
                        Text(LXToastText.clean(locationService.statusMessage))
                            .font(.caption)
                            .foregroundStyle(Color(Design.Palette.stone))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 6)
        } footer: {
            Text("出差或旅行时，每次打开灵犀都会在后台安静地刷新当地地名。位置信息只保存在本机，不会上传。")
        }
    }

    // MARK: - 2. 开关与用法

    private var switchesSection: some View {
        Section {
            LXToggleRow("打字时优先本地地名", subtitle: "当前城市和附近的地名排在候选前面", isOn: $appState.settings.geoLocationBoostEnabled)
            LXToggleRow("AI 写作参考所在城市和时段", isOn: $appState.settings.aiGeoContextEnabled)
        } header: {
            Text("用在哪里")
        } footer: {
            Text("键盘里输入 vwz 或 vdz 可以直接发出当前位置；快捷短语里可用 {{当前城市}}、{{当前区县}}、{{当前位置}}。")
        }
    }

    // MARK: - 3. 手动加载城市

    private var manualSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("输入城市或商圈名，如：青岛", text: $manualCityInput)
                    .font(.subheadline)
                    .focused($cityFocused)
                    .submitLabel(.search)
                    .onSubmit { loadManualCity() }
                Button("加载") {
                    loadManualCity()
                }
                .buttonStyle(LXCapsuleButtonStyle(prominent: true))
                .disabled(locationService.isLocating || manualCityInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(minHeight: 36)

            LXFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(quickCities, id: \.self) { city in
                    let active = context.shortCityName == city
                    Button {
                        Task { await locationService.learnCityOrAreaByName(city) }
                    } label: {
                        Text(city)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                            .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(locationService.isLocating)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("提前加载其他城市")
        } footer: {
            Text("去外地之前先加载目的地，不用定位也能打出当地的地名。")
        }
    }

    // MARK: - 4. 已学会的地名

    private var poiSection: some View {
        let filtered = selectedCategory == "全部"
            ? context.pois
            : context.pois.filter { $0.category == selectedCategory }
        let present = Set(context.pois.map(\.category))
        let visibleCategories = categories.filter { $0 == "全部" || present.contains($0) }

        return Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleCategories, id: \.self) { cat in
                        let active = selectedCategory == cat
                        Button {
                            selectedCategory = cat
                        } label: {
                            Text(cat)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .foregroundStyle(active ? Color.white : Color(Design.Palette.ink))
                                .background(active ? Color(Design.Palette.accent) : Color(Design.Palette.surface), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if filtered.isEmpty {
                LXEmptyState(icon: "mappin.slash", title: "这一类还没有地名", message: "换个分类看看。")
            } else {
                ForEach(filtered.prefix(60)) { poi in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(poi.word)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.ink))
                            Text("\(poi.pinyin.replacingOccurrences(of: "'", with: " ")) · \(poi.abbr)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color(Design.Palette.stone))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        LXTag(text: poi.category, tint: Color(Design.Palette.accent), filled: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("已学会的地名 · \(filtered.count)")
        } footer: {
            if filtered.count > 60 {
                Text("只显示前 60 个，键盘里全部可用。")
            }
        }
    }

    private func loadManualCity() {
        let q = manualCityInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !locationService.isLocating else { return }
        manualCityInput = ""
        cityFocused = false
        Task { await locationService.learnCityOrAreaByName(q) }
    }
}
