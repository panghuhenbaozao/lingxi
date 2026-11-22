import CoreLocation
import SwiftUI
import UIKit

/// 📍 实时地理位置与周边 POI 自学习词库管理页（100% 本机隐私，绝不上云）。
struct LocationLexiconView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var locationService = LiveLocationLexiconService.shared
    @State private var manualCityInput: String = ""
    @State private var selectedCategory: String = "全部"

    private let quickCities = ["临沂", "青岛", "济南", "北京", "上海", "杭州", "成都", "深圳", "广州", "南京", "苏州", "西安"]
    private let categories = ["全部", "城市", "区县", "街道", "商圈", "交通", "高校", "小区", "地标"]

    var body: some View {
        List {
            // 1. 当前实时定位卡片
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(Design.Palette.accentSoft))
                                .frame(width: 44, height: 44)
                            Image(systemName: locationService.currentContext.isPopulated ? "location.fill" : "location.slash")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color(Design.Palette.accent))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(locationService.currentContext.isPopulated
                                 ? locationService.currentContext.compactLocationLabel
                                 : "尚未获取实时地理位置")
                                .font(.headline)
                                .foregroundStyle(Color(Design.Palette.ink))

                            if locationService.currentContext.isPopulated {
                                Text("已学会 \(locationService.currentContext.pois.count) 个本地与周边地标热词（全国 6,403 行政区已内置离线词库）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("全国 6,403 个省市区县简称已内置；开启定位后还将实时学会你身边 5km 内的商场、路名、车站与小区。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !locationService.currentContext.fullDisplayAddress.isEmpty {
                        HStack {
                            Text("完整位置：\(locationService.currentContext.fullDisplayAddress)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("复制") {
                                UIPasteboard.general.string = locationService.currentContext.fullDisplayAddress
                            }
                            .font(.caption.bold())
                            .foregroundStyle(Color(Design.Palette.accent))
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(Color(Design.Palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    Button {
                        Task { await locationService.refreshLiveGPSAndNearbyPOIs() }
                    } label: {
                        HStack(spacing: 8) {
                            if locationService.isLocating {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "location.north.circle.fill")
                            }
                            Text(locationService.isLocating ? "正在定位并扫描 5km 周边地标…" : "立即实时 GPS 定位并学习周边地标")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(Design.Palette.accent))
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(locationService.isLocating)

                    if !locationService.statusMessage.isEmpty {
                        Text(locationService.statusMessage)
                            .font(.caption)
                            .foregroundStyle(locationService.statusMessage.hasPrefix("✓") ? Color(Design.Palette.success) : .secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("📍 实时位置感知与周边 POI 雷达")
            } footer: {
                Text("切换到其他城市出差或旅行时，每次回到本 App 会自动静默刷新当地周边路名与商圈；定位信息 100% 留存本机 App Group，绝不上传任何服务器。")
            }

            // 2. 开关控制与快捷键说明
            Section("智能联动开关") {
                Toggle("键盘自动提权当前城市与周边地标", isOn: $appState.settings.geoLocationBoostEnabled)
                Toggle("AI 写作自动融合当前所在城市与时段", isOn: $appState.settings.aiGeoContextEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Text("快捷插入当前位置技巧：")
                        .font(.caption.bold())
                        .foregroundStyle(Color(Design.Palette.accent))
                    Text("• 键盘直接输入 vwz 或 vdz：一键上屏当前实时定位地址\n• 快捷短语支持动态变量：{{当前城市}}、{{当前区县}}、{{当前位置}}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
                .padding(.vertical, 2)
            }

            // 3. 手动探索或预加载任意城市地标词库（无需 GPS 也可秒学任意城市）
            Section {
                HStack(spacing: 8) {
                    TextField("输入任意城市或商圈（如：临沂 / 青岛）", text: $manualCityInput)
                        .font(.subheadline)
                    Button("加载") {
                        let q = manualCityInput
                        manualCityInput = ""
                        Task { await locationService.learnCityOrAreaByName(q) }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(Color(Design.Palette.accent))
                    .disabled(locationService.isLocating || manualCityInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickCities, id: \.self) { city in
                            Button(city) {
                                Task { await locationService.learnCityOrAreaByName(city) }
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(locationService.currentContext.shortCityName == city ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
                            .foregroundStyle(locationService.currentContext.shortCityName == city ? Color.white : Color(Design.Palette.ink))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                            .disabled(locationService.isLocating)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("🌍 手动切换 / 提前预载目的地城市地标")
            }

            // 4. 当前已学会的本地地标与拼音一览
            if !locationService.currentContext.pois.isEmpty {
                let filtered = selectedCategory == "全部"
                    ? locationService.currentContext.pois
                    : locationService.currentContext.pois.filter { $0.category == selectedCategory }

                Section("已激活的本地地标热词 (\(filtered.count))") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(categories, id: \.self) { cat in
                                Button(cat) { selectedCategory = cat }
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(selectedCategory == cat ? Color(Design.Palette.accent) : Color(Design.Palette.surface))
                                    .foregroundStyle(selectedCategory == cat ? Color.white : Color(Design.Palette.ink))
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    ForEach(filtered.prefix(60)) { poi in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(poi.word)
                                    .font(.subheadline.bold())
                                Text("\(poi.pinyin) · 简拼 \(poi.abbr)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(poi.category)
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(Design.Palette.accentSoft))
                                .foregroundStyle(Color(Design.Palette.accent))
                                .clipShape(Capsule())
                        }
                    }
                }

                Section {
                    Button("清除本机实时位置缓存", role: .destructive) {
                        locationService.clearLocationContext()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("实时位置词库")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationService.reloadFromDisk()
        }
    }
}
