import CoreLocation
import Foundation
import MapKit

/// 主 App 实时地理位置与周边 POI 自动学习服务：
/// - 使用系统原生 CoreLocation 获取当前真实省/市/区县/街道与兴趣点
/// - 使用 Apple 原生 MapKit (MKLocalSearch) 静默扫描当前 4.5km 内的高频地标（商圈/交通/医院/高校/小区/路名）
/// - 自动生成标准拼音并写入 App Group (`lingxi_geo_context.json`)，键盘零延迟生效，100% 留存本机绝不上云。
@MainActor
final class LiveLocationLexiconService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LiveLocationLexiconService()

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocating: Bool = false
    @Published var statusMessage: String = ""
    @Published var currentContext: GeoLocationContext = GeoLocationContext.load(force: true)

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
    }

    func reloadFromDisk() {
        currentContext = GeoLocationContext.load(force: true)
    }

    /// 若用户开启了「实时位置词库」且已授权定位、距离上次刷新超过指定分钟，切回前台时自动静默刷新。
    func autoRefreshIfStale(minIntervalMinutes: Double = 25) {
        let settings = LingxiSettings.load()
        guard settings.geoLocationBoostEnabled else { return }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else { return }
        guard !isLocating else { return }
        if let updated = currentContext.updatedAt,
           Date().timeIntervalSince(updated) < minIntervalMinutes * 60 {
            return
        }
        Task {
            await refreshLiveGPSAndNearbyPOIs()
        }
    }

    /// 触发实时 GPS 定位 + 逆地理编码 + MapKit 周边 POI 词库学习。
    func refreshLiveGPSAndNearbyPOIs() async {
        guard !isLocating else { return }
        isLocating = true
        statusMessage = "正在请求精准实时定位…"
        defer { isLocating = false }

        do {
            let status = await ensureAuthorized()
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                statusMessage = "尚未授予「使用 App 期间定位」权限，请在系统设置开启，或在下方手动搜索所在城市。"
                return
            }

            let location = try await requestSingleLocation()
            statusMessage = "定位成功，正在解析所在城市与周边地标…"
            try await buildContext(from: location, sourceMode: "gps")
        } catch {
            statusMessage = "定位暂未完成：\(error.localizedDescription)（也可直接手动输入城市名加载当地地标）"
        }
    }

    /// 手动指定任意城市或地标名（如「临沂」「青岛」「杭州西湖」），无需 GPS 也能用 MapKit 学习当地 60+ 真实地标词库！
    func learnCityOrAreaByName(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLocating else { return }
        isLocating = true
        statusMessage = "正在解析「\(trimmed)」并扫描当地地标词库…"
        defer { isLocating = false }

        do {
            let placemarks = try await geocoder.geocodeAddressString(trimmed, in: nil, preferredLocale: Locale(identifier: "zh_CN"))
            guard let place = placemarks.first, let loc = place.location else {
                // 离线兜底：即使无地图服务，也直接把用户输入城市名写入上下文
                var fallback = GeoLocationContext()
                fallback.city = trimmed
                fallback.formattedAddress = trimmed
                fallback.updatedAt = Date()
                fallback.sourceMode = "citySearch"
                if let entry = GeoPinyinConverter.makeEntry(word: trimmed, category: "城市", boostScore: 14.5) {
                    fallback.pois = [entry]
                }
                fallback.save()
                currentContext = fallback
                statusMessage = "✓ 已将「\(trimmed)」加入本机高优位置词库"
                return
            }
            try await buildContext(from: loc, sourceMode: "citySearch", fallbackPlacemark: place)
        } catch {
            statusMessage = "解析「\(trimmed)」失败：\(error.localizedDescription)"
        }
    }

    func clearLocationContext() {
        GeoLocationContext.clear()
        currentContext = GeoLocationContext()
        statusMessage = "已清空本机位置与周边地标缓存"
    }

    // MARK: - 内部地理编码与 MapKit POI 雷达

    private func buildContext(
        from location: CLLocation,
        sourceMode: String,
        fallbackPlacemark: CLPlacemark? = nil
    ) async throws {
        let placemarks = (try? await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "zh_CN"))) ?? []
        let pm = placemarks.first ?? fallbackPlacemark

        let province = pm?.administrativeArea ?? ""
        let city = pm?.locality ?? pm?.administrativeArea ?? ""
        let district = pm?.subLocality ?? ""
        let street = [pm?.thoroughfare, pm?.subThoroughfare].compactMap { $0 }.joined()
        let rawAOIs = pm?.areasOfInterest ?? []

        var ctx = GeoLocationContext()
        ctx.province = province
        ctx.city = city
        ctx.district = district
        ctx.street = street
        ctx.latitude = location.coordinate.latitude
        ctx.longitude = location.coordinate.longitude
        ctx.updatedAt = Date()
        ctx.sourceMode = sourceMode

        var addrParts: [String] = []
        if !province.isEmpty { addrParts.append(province) }
        if !city.isEmpty && city != province { addrParts.append(city) }
        if !district.isEmpty { addrParts.append(district) }
        if !street.isEmpty { addrParts.append(street) }
        if let firstAOI = rawAOIs.first, !firstAOI.isEmpty { addrParts.append(firstAOI) }
        ctx.formattedAddress = addrParts.joined()

        var entriesByWord: [String: GeoPOIEntry] = [:]
        func register(_ raw: String, category: String, score: Double) {
            guard let entry = GeoPinyinConverter.makeEntry(word: raw, category: category, boostScore: score) else { return }
            if let existing = entriesByWord[entry.word] {
                if score > existing.boostScore { entriesByWord[entry.word] = entry }
            } else {
                entriesByWord[entry.word] = entry
            }
        }

        // 1. 当前省 / 市 / 区县 / 街道（最高权重置顶）
        register(ctx.shortCityName, category: "城市", score: 15.0)
        register(city, category: "城市", score: 14.2)
        register(ctx.shortDistrictName, category: "区县", score: 13.8)
        register(district, category: "区县", score: 13.5)
        if !province.isEmpty {
            register(province, category: "省份", score: 11.8)
            let shortProv = province.replacingOccurrences(of: "省", with: "").replacingOccurrences(of: "市", with: "")
            if shortProv.count >= 2 { register(shortProv, category: "省份", score: 12.2) }
        }
        if let road = pm?.thoroughfare, !road.isEmpty {
            register(road, category: "街道", score: 12.6)
        }
        for aoi in rawAOIs {
            register(aoi, category: "地标", score: 12.8)
        }

        // 2. 并发执行 MapKit 周边 POI 雷达扫描（半径 4.5km，涵盖商圈/交通/医院高校/小区公园/路名）
        let queries: [(query: String, category: String, score: Double)] = [
            ("广场 商场", "商圈", 11.2),
            ("车站 地铁 机场", "交通", 11.4),
            ("医院 大学 中学", "高校", 10.6),
            ("小区 公园 大厦", "小区", 10.4),
            ("大道 路 商业街", "街道", 10.2),
        ]
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 4800,
            longitudinalMeters: 4800
        )

        let scannedPOIs: [(String, String, Double)] = await withTaskGroup(of: [(String, String, Double)].self) { group in
            for q in queries {
                group.addTask {
                    let req = MKLocalSearch.Request()
                    req.naturalLanguageQuery = q.query
                    req.region = region
                    req.resultTypes = .pointOfInterest
                    let search = MKLocalSearch(request: req)
                    guard let resp = try? await search.start() else { return [] }
                    var hits: [(String, String, Double)] = []
                    for item in resp.mapItems.prefix(24) {
                        if let name = item.name, !name.isEmpty {
                            hits.append((name, q.category, q.score))
                        }
                        if let road = item.placemark.thoroughfare, !road.isEmpty {
                            hits.append((road, "街道", 10.0))
                        }
                    }
                    return hits
                }
            }
            var merged: [(String, String, Double)] = []
            for await batch in group {
                merged.append(contentsOf: batch)
            }
            return merged
        }

        for (name, cat, score) in scannedPOIs {
            register(name, category: cat, score: score)
        }

        ctx.pois = entriesByWord.values
            .sorted { $0.boostScore > $1.boostScore }
            .prefix(160)
            .map { $0 }
        ctx.save()
        currentContext = ctx

        let locName = ctx.compactLocationLabel.isEmpty ? ctx.shortCityName : ctx.compactLocationLabel
        statusMessage = "✓ 已定位至「\(locName)」，学会 \(ctx.pois.count) 个本地与周边地标热词"
    }

    private func ensureAuthorized() async -> CLAuthorizationStatus {
        let current = locationManager.authorizationStatus
        authorizationStatus = current
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { cont in
            self.authContinuation = cont
            self.locationManager.requestWhenInUseAuthorization()
        }
    }

    private func requestSingleLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { cont in
            self.locationContinuation = cont
            self.locationManager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status != .notDetermined, let cont = self.authContinuation {
                self.authContinuation = nil
                cont.resume(returning: status)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            if let cont = self.locationContinuation {
                self.locationContinuation = nil
                cont.resume(returning: loc)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let cont = self.locationContinuation {
                self.locationContinuation = nil
                cont.resume(throwing: error)
            }
        }
    }
}
