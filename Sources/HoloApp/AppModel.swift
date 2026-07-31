import AppKit
import Combine
import CoreLocation
import Foundation
import HoloCore

struct EnvironmentalPlace: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let region: String?
    let country: String
    let latitude: Double
    let longitude: Double

    var displayName: String {
        [name, region, country].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: ", ")
    }
}

private final class EnvironmentalLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((CLLocation) -> Void)?
    var onError: ((Error) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            onError?(CLError(.denied))
        @unknown default:
            onError?(CLError(.denied))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            onError?(CLError(.denied))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocation?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onError?(error)
    }
}

private enum EnvironmentalAPI {
    private struct GeocodingResponse: Decodable { let results: [GeocodingResult]? }
    private struct GeocodingResult: Decodable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String
        let admin1: String?
    }
    private struct WeatherResponse: Decodable {
        let current: CurrentWeather
        let daily: DailyWeather
    }
    private struct CurrentWeather: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Double
        let precipitation: Double
    }
    private struct DailyWeather: Decodable {
        let uv_index_max: [Double]
        let precipitation_sum: [Double]
    }
    private struct AirResponse: Decodable { let current: CurrentAir }
    private struct CurrentAir: Decodable {
        let us_aqi: Int
        let pm2_5: Double
        let pm10: Double
        let ozone: Double
    }

    static func search(_ query: String) async throws -> [EnvironmentalPlace] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        let response: GeocodingResponse = try await decode(components.url!)
        return (response.results ?? []).map {
            EnvironmentalPlace(
                id: $0.id, name: $0.name, region: $0.admin1, country: $0.country,
                latitude: $0.latitude, longitude: $0.longitude
            )
        }
    }

    static func snapshot(latitude: Double, longitude: Double, locationName: String) async throws -> EnvironmentalSnapshot {
        let weatherURL = url(
            base: "https://api.open-meteo.com/v1/forecast",
            latitude: latitude,
            longitude: longitude,
            fields: [
                URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation"),
                URLQueryItem(name: "daily", value: "uv_index_max,precipitation_sum"),
                URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
                URLQueryItem(name: "precipitation_unit", value: "inch")
            ]
        )
        let airURL = url(
            base: "https://air-quality-api.open-meteo.com/v1/air-quality",
            latitude: latitude,
            longitude: longitude,
            fields: [URLQueryItem(name: "current", value: "us_aqi,pm2_5,pm10,ozone")]
        )

        async let weatherRequest: WeatherResponse = decode(weatherURL)
        async let airRequest: AirResponse = decode(airURL)
        let (weather, air) = try await (weatherRequest, airRequest)
        let category = USAirQualityCategory(aqi: air.current.us_aqi)
        let uv = weather.daily.uv_index_max.first ?? 0
        let uvRisk = UVRisk(index: uv)
        let rainfall = weather.daily.precipitation_sum.first ?? weather.current.precipitation

        return EnvironmentalSnapshot(
            locationName: locationName,
            updatedAt: Date(),
            isDemonstration: false,
            readings: [
                EnvironmentalReading(
                    topic: .airQuality,
                    headline: category.title,
                    value: "AQI \(air.current.us_aqi)",
                    explanation: "AQI means Air Quality Index. PM2.5 is \(format(air.current.pm2_5)) micrograms per cubic meter; these tiny particles can travel deep into the lungs. Ozone is \(format(air.current.ozone)) micrograms per cubic meter. These are modeled conditions, not a regulatory determination.",
                    guidance: category.guidance,
                    spokenSummary: "Air quality is \(category.title.lowercased()). The Air Quality Index is \(air.current.us_aqi). \(category.guidance)"
                ),
                EnvironmentalReading(
                    topic: .weatherAndUV,
                    headline: "\(Int(weather.current.temperature_2m.rounded())) degrees · \(uvRisk.title) UV",
                    value: "UV \(format(uv))",
                    explanation: "It feels like \(Int(weather.current.apparent_temperature.rounded())) degrees with \(Int(weather.current.relative_humidity_2m.rounded())) percent humidity. The UV Index describes the strength of skin-damaging ultraviolet radiation.",
                    guidance: uvRisk.guidance,
                    spokenSummary: "It is \(Int(weather.current.temperature_2m.rounded())) degrees and feels like \(Int(weather.current.apparent_temperature.rounded())). The UV Index is \(format(uv)), which is \(uvRisk.title.lowercased()). \(uvRisk.guidance)"
                ),
                EnvironmentalReading(
                    topic: .environmentalAlerts,
                    headline: "Official alerts not connected",
                    value: "Coming next",
                    explanation: "Open-Meteo does not provide the official United States hazard feed used by this zone. Holo will connect National Weather Service alerts separately.",
                    guidance: "Check local authorities for urgent warnings until official alerts are connected.",
                    spokenSummary: "Official environmental alerts are not connected yet. Check local authorities for urgent warnings."
                ),
                EnvironmentalReading(
                    topic: .waterAndRain,
                    headline: rainfall < 0.1 ? "Little rain expected" : "Rain expected today",
                    value: "\(format(rainfall)) inches",
                    explanation: "This is today's modeled precipitation total. Rainfall can affect runoff and flood potential, but this value does not measure drinking-water quality or stream level.",
                    guidance: rainfall >= 1 ? "Watch official flood information and avoid flooded roads." : "No conclusion about flooding can be made from rainfall alone.",
                    spokenSummary: "Today's forecast rainfall is \(format(rainfall)) inches. Rainfall alone does not determine flood risk or drinking-water quality."
                )
            ]
        )
    }

    private static func url(base: String, latitude: Double, longitude: Double, fields: [URLQueryItem]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto")
        ] + fields
        return components.url!
    }

    private static func decode<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

enum DiagnosticLabel: Hashable, Identifiable {
    case zone(DeskZone)
    case negative(String)

    var id: String {
        switch self {
        case .zone(let zone): return "zone-\(zone.rawValue)"
        case .negative(let label): return "negative-\(label)"
        }
    }

    var displayName: String {
        switch self {
        case .zone(let zone): return zone.displayName
        case .negative(let label): return label
        }
    }

    var zone: DeskZone? {
        if case .zone(let zone) = self { return zone }
        return nil
    }
}

enum HoloStorageError: Error, LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let area):
            return "\(area) storage is unavailable. Holo did not save this change."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var section: AppSection = .live
    @Published private(set) var profiles: [HoloProfile] = []
    @Published var selectedProfileID: UUID?
    @Published private(set) var activeZone: DeskZone?
    @Published private(set) var lastDecision: ClassificationDecision?
    @Published private(set) var statusMessage = "Ready to map your desk"
    @Published private(set) var calibrationSession: CalibrationSession?
    @Published private(set) var calibrationValidation: CrossValidationResult?
    @Published private(set) var evaluationSession: EvaluationSession?
    @Published private(set) var latestEvaluation: EvaluationReport?
    @Published private(set) var evaluationHistory: [EvaluationReport] = []
    @Published private(set) var latestEvaluationIsPersisted = false
    @Published private(set) var benchmarkSession: BenchmarkSession?
    @Published private(set) var approachComparison: ApproachComparison?
    @Published private(set) var diagnosticCaptures: [DiagnosticCaptureRecord] = []
    @Published var diagnosticLabel: DiagnosticLabel = .zone(.leftTop)
    @Published var diagnosticCaptureArmed = false
    @Published private(set) var guidedCaptureIssue: GuidedCaptureQualityIssue?
    @Published var debugRecordingEnabled = false
    @Published private(set) var hasDebugRecordings = false
    @Published var errorMessage: String?
    @Published private(set) var environmentalSnapshot = EnvironmentalSnapshot.demonstration()
    @Published var learningMode = true
    @Published private(set) var environmentalPlaces: [EnvironmentalPlace] = []
    @Published private(set) var selectedEnvironmentalPlace: EnvironmentalPlace?
    @Published private(set) var isLoadingEnvironmentalData = false
    @Published private(set) var environmentalDataMessage = "Choose a location for live conditions"

    let audio = AudioCaptureService()
    @Published var calibrationDraft = CalibrationDraft()

    private let profileStore: ProfileStore?
    private let evaluationStore: EvaluationStore?
    private let comparisonStore: ApproachComparisonStore?
    private let debugStore: DebugRecordingStore?
    private let actionDispatcher = LocalActionDispatcher()
    private let environmentalSpeaker = NSSpeechSynthesizer()
    private let environmentalLocationProvider = EnvironmentalLocationProvider()
    private var recalibratingProfileID: UUID?
    private var calibrationAcceptAfter = Date.distantPast
    private var evaluationAcceptAfter = Date.distantPast
    private var benchmarkAcceptAfter = Date.distantPast
    private var calibrationArmTask: Task<Void, Never>?
    private var evaluationArmTask: Task<Void, Never>?
    private var benchmarkArmTask: Task<Void, Never>?
    private var activeZoneClearTask: Task<Void, Never>?
    private var pausedByUser = false
    private var cancellables: Set<AnyCancellable> = []
    private static let environmentalSnapshotKey = "environmental.snapshot.v1"
    private static let environmentalPlaceKey = "environmental.place.v1"

    init() {
        var startupErrors: [String] = []
        do { profileStore = try ProfileStore() }
        catch {
            profileStore = nil
            startupErrors.append("Profiles: \(error.localizedDescription)")
        }
        do { evaluationStore = try EvaluationStore() }
        catch {
            evaluationStore = nil
            startupErrors.append("Evaluations: \(error.localizedDescription)")
        }
        do { comparisonStore = try ApproachComparisonStore() }
        catch {
            comparisonStore = nil
            startupErrors.append("Sensing comparison: \(error.localizedDescription)")
        }
        do { debugStore = try DebugRecordingStore() }
        catch {
            debugStore = nil
            startupErrors.append("Debug recordings: \(error.localizedDescription)")
        }

        if let debugStore {
            do { hasDebugRecordings = try debugStore.containsRecordings() }
            catch { startupErrors.append("Debug recordings: \(error.localizedDescription)") }
        }
        if let profileStore {
            do { profiles = try profileStore.loadAll() }
            catch { startupErrors.append("Profiles: \(error.localizedDescription)") }
        }
        selectedProfileID = profiles.first?.id
        if let evaluationStore {
            do { evaluationHistory = try evaluationStore.loadAll() }
            catch { startupErrors.append("Evaluations: \(error.localizedDescription)") }
        }
        refreshLatestEvaluation()
        if let comparisonStore {
            do { approachComparison = try comparisonStore.load() }
            catch { startupErrors.append("Sensing comparison: \(error.localizedDescription)") }
        }
        if let profile = profiles.first {
            calibrationDraft = draft(for: profile)
        } else {
            calibrationDraft.strategy = applicableApproachComparison?.selectedStrategy ?? .passive
        }
        if !startupErrors.isEmpty {
            statusMessage = "Local storage needs attention"
            errorMessage = "Some local data could not be opened:\n\n" + startupErrors.joined(separator: "\n")
        }

        audio.onObservation = { [weak self] observation in
            self?.handle(observation)
        }
        audio.onRouteInvalidated = { [weak self] message in
            self?.disarmAllCaptureIntents()
            self?.activeZone = nil
            self?.statusMessage = "Built-in audio route required"
            self?.errorMessage = message
        }
        actionDispatcher.onAsyncError = { [weak self] error in
            self?.errorMessage = "The assigned action failed. \(error.localizedDescription)"
        }
        audio.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        environmentalLocationProvider.onLocation = { [weak self] location in
            Task { @MainActor in await self?.useCurrentLocation(location) }
        }
        environmentalLocationProvider.onError = { [weak self] error in
            Task { @MainActor in
                self?.isLoadingEnvironmentalData = false
                self?.environmentalDataMessage = "Location unavailable — search for a city or ZIP code"
                self?.errorMessage = "Holo could not use the current location. You can search for a city or ZIP code instead. \(error.localizedDescription)"
            }
        }
        restoreEnvironmentalCache()
    }

    var selectedProfile: HoloProfile? {
        guard let selectedProfileID else { return profiles.first }
        return profiles.first { $0.id == selectedProfileID }
    }

    var guidedSection: AppSection? {
        GuidedNavigationGate.guidedSection(
            calibrationActive: calibrationSession != nil,
            evaluationActive: evaluationSession != nil,
            benchmarkActive: benchmarkSession != nil
        )
    }

    func canNavigate(to candidate: AppSection) -> Bool {
        GuidedNavigationGate.canNavigate(to: candidate, guidedSection: guidedSection)
    }

    var targetStrategy: SensingStrategy {
        SensingStrategyResolver.resolve(
            benchmark: benchmarkSession?.currentStrategy,
            calibration: calibrationSession?.draft.strategy,
            profile: selectedProfile?.sensingStrategy,
            comparison: applicableApproachComparison?.selectedStrategy
        )
    }

    var applicableApproachComparison: ApproachComparison? {
        guard let comparison = approachComparison else { return nil }
        return comparison.applies(to: selectedProfile?.id) ? comparison : nil
    }

    func activate() async {
        do {
            try await audio.start(strategy: targetStrategy)
            if let zone = calibrationSession?.currentZone {
                statusMessage = "Calibration ready • move to \(zone.displayName), then arm"
            } else if let zone = evaluationSession?.currentZone {
                statusMessage = "Accuracy test ready • move to \(zone.displayName), then arm"
            } else if let benchmark = benchmarkSession,
                      let strategy = benchmark.currentStrategy,
                      let zone = benchmark.currentZone {
                statusMessage = "Sensing comparison ready • \(strategy.displayName) • \(zone.displayName)"
            } else {
                statusMessage = selectedProfile == nil ? "Listening • calibration needed" : "Listening for desk taps"
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Microphone unavailable"
        }
    }

    func activateOnLaunch() async {
        if selectedEnvironmentalPlace != nil {
            Task { await refreshEnvironmentalData() }
        }
        guard selectedProfile != nil else {
            section = .calibrate
            statusMessage = "Setup required • calibrate the four desk zones"
            return
        }

        switch audio.authorizationState {
        case .authorized:
            await activate()
        case .notDetermined:
            statusMessage = selectedProfile == nil
                ? "Microphone access will be requested when calibration begins"
                : "Press Resume to enable microphone access"
        case .unavailable:
            statusMessage = "Microphone access is off"
        }
    }

    func togglePause() {
        if audio.isListening {
            pausedByUser = true
            disarmAllCaptureIntents()
            audio.stop()
            statusMessage = "Paused"
            activeZone = nil
        } else if selectedProfile == nil && guidedSection == nil {
            openSetup()
        } else {
            pausedByUser = false
            Task { await activate() }
        }
    }

    func openSetup() {
        guard guidedSection == nil else { return }
        section = .calibrate
        statusMessage = "Setup required • calibrate the four desk zones"
    }

    func selectProfile(_ id: UUID?) {
        guard guidedSection == nil else { return }
        selectedProfileID = id
        activeZoneClearTask?.cancel()
        activeZone = nil
        lastDecision = nil
        refreshLatestEvaluation()
        if let profile = selectedProfile {
            calibrationDraft = draft(for: profile)
        }
        Task {
            do { try await reconfigureListeningAudio(to: targetStrategy) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func beginCalibration(draft: CalibrationDraft, recalibrating: HoloProfile? = nil) {
        pausedByUser = false
        calibrationArmTask?.cancel()
        evaluationArmTask?.cancel()
        benchmarkArmTask?.cancel()
        calibrationDraft = draft
        recalibratingProfileID = recalibrating?.id
        calibrationSession = CalibrationSession(draft: draft)
        calibrationValidation = nil
        guidedCaptureIssue = nil
        calibrationAcceptAfter = Date().addingTimeInterval(0.5)
        evaluationSession = nil
        benchmarkSession = nil
        section = .calibrate
        statusMessage = "Calibration • \(DeskZone.leftTop.displayName)"
        Task {
            do {
                try await prepareGuidedAudio(to: draft.strategy)
                guard calibrationSession != nil,
                      audio.isListening,
                      audio.strategy == draft.strategy else { return }
                armCalibrationZone()
            }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func prepareRecalibration() {
        guard guidedSection == nil else { return }
        if let profile = selectedProfile {
            calibrationDraft = draft(for: profile)
        }
        section = .calibrate
    }

    func cancelCalibration() {
        calibrationArmTask?.cancel()
        calibrationSession = nil
        calibrationValidation = nil
        guidedCaptureIssue = nil
        recalibratingProfileID = nil
        statusMessage = "Calibration cancelled"
        Task {
            do { try await reconfigureListeningAudio(to: targetStrategy) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func armCalibrationZone() {
        guard var session = calibrationSession, let zone = session.currentZone else { return }
        calibrationArmTask?.cancel()
        session.isArmed = false
        session.isSettling = true
        guidedCaptureIssue = nil
        calibrationSession = session
        statusMessage = "Get ready • listening starts in one second"
        scheduleCalibrationArm(for: zone, delayNanoseconds: 1_000_000_000)
    }

    private func scheduleCalibrationArm(for zone: DeskZone, delayNanoseconds: UInt64) {
        calibrationArmTask?.cancel()
        calibrationArmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  var current = self.calibrationSession,
                  self.audio.isListening,
                  self.audio.strategy == current.draft.strategy,
                  current.currentZone == zone,
                  current.isSettling else { return }
            current.isSettling = false
            current.isArmed = true
            self.calibrationAcceptAfter = Date()
            self.calibrationSession = current
            self.statusMessage = "Calibration armed • \(zone.displayName) • tap 1 of \(current.targetPerZone)"
        }
    }

    func collectNegativeExamples(label: String?) {
        calibrationSession?.negativeLabel = label
        calibrationSession?.isArmed = label != nil
        calibrationSession?.isSettling = false
        guidedCaptureIssue = nil
        calibrationAcceptAfter = Date().addingTimeInterval(label == nil ? 0 : 0.8)
        if let label {
            statusMessage = "Rejection training • make a \(label.lowercased()) sound"
        } else {
            statusMessage = "Calibration zones complete"
        }
    }

    func clearNegativeExamples(label: String) {
        guard var session = calibrationSession else { return }
        session.negativeSamples.removeAll { $0.negativeLabel == label }
        if session.negativeLabel == label {
            session.negativeLabel = nil
            session.isArmed = false
            session.isSettling = false
        }
        guidedCaptureIssue = nil
        calibrationSession = session
        statusMessage = "Cleared \(label.lowercased()) examples"
    }

    func undoLastCalibrationTap() {
        calibrationArmTask?.cancel()
        guard var session = calibrationSession else { return }
        if session.negativeLabel != nil, !session.negativeSamples.isEmpty {
            session.negativeSamples.removeLast()
        } else if !session.positiveSamples.isEmpty {
            session.positiveSamples.removeLast()
        }
        session.isArmed = false
        session.isSettling = false
        calibrationValidation = nil
        guidedCaptureIssue = nil
        calibrationSession = session
        calibrationAcceptAfter = Date().addingTimeInterval(0.35)
        if let zone = session.currentZone {
            statusMessage = "\(zone.displayName) • tap \(session.count(for: zone) + 1) of \(session.targetPerZone)"
        }
    }

    func retryCalibrationZone(_ requestedZone: DeskZone? = nil) {
        calibrationArmTask?.cancel()
        guard var session = calibrationSession else { return }
        let zone: DeskZone?
        if let requestedZone {
            zone = requestedZone
        } else {
            let current = session.currentZone
            if let current, session.count(for: current) > 0 {
                zone = current
            } else if let current {
                zone = DeskZone.allCases.last {
                    $0.rawValue < current.rawValue && session.count(for: $0) > 0
                }
            } else {
                zone = DeskZone.allCases.last
            }
        }
        guard let zone else { return }
        session.positiveSamples.removeAll { $0.zone == zone }
        session.negativeLabel = nil
        session.isArmed = false
        session.isSettling = false
        calibrationValidation = nil
        guidedCaptureIssue = nil
        calibrationSession = session
        calibrationAcceptAfter = Date().addingTimeInterval(0.5)
        statusMessage = "Retry \(zone.displayName) • tap 1 of \(session.targetPerZone)"
    }

    func finishCalibration() {
        guard let session = calibrationSession, session.zonesComplete else { return }
        do {
            let classifier = try TrainedTapClassifier.train(
                positiveExamples: session.positiveSamples,
                negativeExamples: session.negativeSamples
            )
            let crossValidation = try calibrationValidation
                ?? ClassifierEvaluator.leaveOneOut(session.positiveSamples)
            let counts = DeskZone.allCases.map { session.count(for: $0) }
            let summary = CalibrationSummary(
                sampleCount: session.positiveSamples.count,
                samplesPerZone: counts,
                leaveOneOutAccuracy: crossValidation.accuracy
            )
            let oldProfile = profiles.first { $0.id == recalibratingProfileID }
            var profile = HoloProfile(
                id: oldProfile?.id ?? UUID(),
                name: session.draft.name,
                surfaceDescription: session.draft.surfaceDescription,
                laptopPositionNote: session.draft.laptopPositionNote,
                classifier: classifier,
                calibration: summary,
                zones: oldProfile?.zones ?? DeskZone.allCases.map { ZoneConfiguration(zone: $0) }
            )
            if let oldProfile { profile.createdAt = oldProfile.createdAt }
            guard let profileStore else { throw HoloStorageError.unavailable("Desk profile") }
            try profileStore.save(profile)
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
            } else {
                profiles.insert(profile, at: 0)
            }
            selectedProfileID = profile.id
            calibrationArmTask?.cancel()
            calibrationSession = nil
            calibrationValidation = nil
            guidedCaptureIssue = nil
            recalibratingProfileID = nil
            section = .live
            statusMessage = "Calibration saved • listening"
            Task {
                do { try await reconfigureListeningAudio(to: profile.sensingStrategy) }
                catch { errorMessage = error.localizedDescription }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEvaluation() {
        guard selectedProfile != nil else {
            errorMessage = "Calibrate a desk profile before evaluating it."
            return
        }
        pausedByUser = false
        calibrationSession = nil
        benchmarkSession = nil
        calibrationArmTask?.cancel()
        benchmarkArmTask?.cancel()
        evaluationArmTask?.cancel()
        latestEvaluation = nil
        latestEvaluationIsPersisted = false
        activeZoneClearTask?.cancel()
        guidedCaptureIssue = nil
        activeZone = nil
        lastDecision = nil
        evaluationSession = EvaluationSession()
        section = .evaluate
        statusMessage = "Accuracy test ready • move to Left Top, then arm"
        Task {
            do { try await prepareGuidedAudio(to: targetStrategy) }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func armEvaluationZone() {
        guard var session = evaluationSession, let zone = session.currentZone else { return }
        evaluationArmTask?.cancel()
        session.isArmed = false
        session.isSettling = true
        evaluationSession = session
        statusMessage = "Get ready • accuracy test starts in one second"
        evaluationArmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  var current = self.evaluationSession,
                  self.audio.isListening,
                  self.audio.strategy == self.targetStrategy,
                  current.currentZone == zone,
                  current.isSettling else { return }
            current.isSettling = false
            current.isArmed = true
            self.evaluationAcceptAfter = Date()
            self.evaluationSession = current
            let count = current.records.filter { $0.expectedZone == zone }.count
            self.statusMessage = "Accuracy test armed • \(zone.displayName) • \(count + 1)/\(current.targetPerZone)"
        }
    }

    func cancelEvaluation() {
        evaluationArmTask?.cancel()
        evaluationSession = nil
        activeZone = nil
        refreshLatestEvaluation()
        statusMessage = "Accuracy test cancelled"
    }

    func beginApproachBenchmark() {
        pausedByUser = false
        calibrationArmTask?.cancel()
        evaluationArmTask?.cancel()
        benchmarkArmTask?.cancel()
        calibrationSession = nil
        evaluationSession = nil
        benchmarkSession = BenchmarkSession()
        guidedCaptureIssue = nil
        section = .diagnostics
        statusMessage = "Sensing comparison ready • move to Left Top, then arm"
        Task {
            do { try await prepareGuidedAudio(to: .passive) }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func armApproachBenchmarkZone() {
        guard var session = benchmarkSession,
              let strategy = session.currentStrategy,
              let zone = session.currentZone else { return }
        benchmarkArmTask?.cancel()
        session.isArmed = false
        session.isSettling = true
        guidedCaptureIssue = nil
        benchmarkSession = session
        statusMessage = "Get ready • \(strategy.displayName) • \(zone.displayName)"
        benchmarkArmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  var current = self.benchmarkSession,
                  self.audio.isListening,
                  self.audio.strategy == strategy,
                  current.currentStrategy == strategy,
                  current.currentZone == zone,
                  current.isSettling else { return }
            current.isSettling = false
            current.isArmed = true
            self.benchmarkAcceptAfter = Date()
            self.benchmarkSession = current
            self.statusMessage = "Sensing comparison armed • \(strategy.displayName) • \(zone.displayName)"
        }
    }

    func cancelApproachBenchmark() {
        benchmarkArmTask?.cancel()
        benchmarkSession = nil
        guidedCaptureIssue = nil
        statusMessage = "Sensing comparison cancelled"
        Task {
            do { try await reconfigureListeningAudio(to: targetStrategy) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func armDiagnosticCapture() {
        diagnosticCaptureArmed = true
        statusMessage = "Diagnostic armed • tap \(diagnosticLabel.displayName)"
    }

    func exportDiagnosticReport() {
        let report = DiagnosticSessionReport(
            microphone: audio.diagnostics,
            captures: diagnosticCaptures,
            approachComparison: approachComparison,
            recordingsRetained: debugRecordingEnabled
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "holo-diagnostic-\(Self.fileTimestamp()).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try report.jsonData().write(to: url, options: .atomic) }
        catch { errorMessage = error.localizedDescription }
    }

    func setDebugRecordingEnabled(_ enabled: Bool) {
        guard enabled else {
            debugRecordingEnabled = false
            return
        }
        guard debugStore != nil else {
            debugRecordingEnabled = false
            errorMessage = HoloStorageError.unavailable("Debug recording").localizedDescription
            return
        }
        debugRecordingEnabled = true
    }

    func clearDebugRecordings() {
        do {
            guard let debugStore else { throw HoloStorageError.unavailable("Debug recording") }
            try debugStore.clear()
            hasDebugRecordings = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func updateAction(for zone: DeskZone, action: ZoneActionConfiguration) -> Bool {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == selectedProfileID }),
              let zoneIndex = profiles[profileIndex].zones.firstIndex(where: { $0.zone == zone }) else { return false }
        var updatedProfile = profiles[profileIndex]
        updatedProfile.zones[zoneIndex].action = action
        do {
            guard let profileStore else { throw HoloStorageError.unavailable("Desk profile") }
            try profileStore.save(updatedProfile)
            profiles[profileIndex] = updatedProfile
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func testAction(_ action: ZoneActionConfiguration) {
        do { try actionDispatcher.perform(action) }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteSelectedProfile() {
        guard let profile = selectedProfile else { return }
        do {
            guard let profileStore else { throw HoloStorageError.unavailable("Desk profile") }
            try profileStore.delete(profile)
            profiles.removeAll { $0.id == profile.id }
            selectedProfileID = profiles.first?.id
            refreshLatestEvaluation()
            if let nextProfile = selectedProfile {
                calibrationDraft = draft(for: nextProfile)
            }
            statusMessage = profiles.isEmpty ? "Calibration needed" : "Profile deleted"
            Task {
                do { try await reconfigureListeningAudio(to: targetStrategy) }
                catch { errorMessage = error.localizedDescription }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ observation: TapObservation) {
        if debugRecordingEnabled {
            let label = currentCaptureLabel
            do {
                guard let debugStore else { throw HoloStorageError.unavailable("Debug recording") }
                try debugStore.save(
                   observation,
                   label: label,
                   sampleRate: audio.diagnostics.sampleRate
                )
                hasDebugRecordings = true
            } catch {
                debugRecordingEnabled = false
                errorMessage = "Debug recording stopped because the WAV could not be saved. \(error.localizedDescription)"
            }
        }

        if var benchmark = benchmarkSession {
            handleBenchmark(observation, session: &benchmark)
            benchmarkSession = benchmark.currentStrategy == nil ? nil : benchmark
            return
        }

        if var calibration = calibrationSession {
            handleCalibration(observation, session: &calibration)
            calibrationSession = calibration
            return
        }

        if var evaluation = evaluationSession, let profile = selectedProfile, let expected = evaluation.currentZone {
            guard evaluation.isArmed, Date() >= evaluationAcceptAfter else { return }
            var decision = profile.classifier.predict(observation.feature)
            decision.processingLatencyMilliseconds = observation.processingLatencyMilliseconds
            evaluation.records.append(EvaluationRecord(
                expectedZone: expected,
                decision: decision,
                responseLatencyMilliseconds: responseLatencyMilliseconds(for: observation)
            ))
            present(decision)
            evaluationAcceptAfter = Date().addingTimeInterval(0.40)
            let completedExpectedZone = evaluation.records.filter { $0.expectedZone == expected }.count == evaluation.targetPerZone
            if completedExpectedZone {
                evaluation.isArmed = false
                evaluation.isSettling = false
                activeZone = nil
            }
            evaluationSession = evaluation
            if let next = evaluation.currentZone {
                statusMessage = completedExpectedZone
                    ? "Zone complete • move to \(next.displayName), then arm"
                    : "Accuracy test • \(next.displayName) • \(evaluation.records.filter { $0.expectedZone == next }.count + 1)/\(evaluation.targetPerZone)"
            } else {
                finishEvaluation(evaluation)
            }
            return
        }

        if section == .diagnostics {
            if diagnosticCaptureArmed {
                let capture = DiagnosticCaptureRecord(
                    label: diagnosticLabel.displayName,
                    zone: diagnosticLabel.zone,
                    feature: observation.feature,
                    responseLatencyMilliseconds: responseLatencyMilliseconds(for: observation)
                )
                diagnosticCaptures.append(capture)
                diagnosticCaptureArmed = false
                statusMessage = "Diagnostic captured • \(observation.feature.quality.summary)"
            }
            return
        }

        guard let profile = selectedProfile else {
            statusMessage = "Tap detected • calibrate to identify its zone"
            return
        }
        var decision = profile.classifier.predict(observation.feature)
        decision.processingLatencyMilliseconds = observation.processingLatencyMilliseconds
        present(decision)
        if let zone = decision.zone {
            if section == .live {
                statusMessage = "\(zone.environmentalTopic.title) • \(Int(decision.confidence * 100))% confidence"
                speakEnvironmentalSummary(for: zone)
            } else {
                statusMessage = "\(zone.displayName) detected • environmental output paused outside Desk"
            }
        } else {
            statusMessage = "Rejected • \(decision.rejectionReason?.displayName ?? "low confidence")"
        }
    }

    func environmentalReading(for zone: DeskZone) -> EnvironmentalReading? {
        environmentalSnapshot.reading(for: zone.environmentalTopic)
    }

    func requestCurrentEnvironmentalLocation() {
        isLoadingEnvironmentalData = true
        environmentalDataMessage = "Requesting current location…"
        environmentalLocationProvider.request()
    }

    func searchEnvironmentalLocations(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            environmentalPlaces = []
            return
        }
        isLoadingEnvironmentalData = true
        environmentalDataMessage = "Searching locations…"
        do {
            environmentalPlaces = try await EnvironmentalAPI.search(trimmed)
            environmentalDataMessage = environmentalPlaces.isEmpty
                ? "No matching locations"
                : "Select a matching location"
        } catch {
            environmentalPlaces = []
            environmentalDataMessage = "Location search failed"
            errorMessage = "Holo could not search locations. Check your internet connection and try again. \(error.localizedDescription)"
        }
        isLoadingEnvironmentalData = false
    }

    func selectEnvironmentalPlace(_ place: EnvironmentalPlace) async {
        selectedEnvironmentalPlace = place
        environmentalPlaces = []
        await refreshEnvironmentalData()
    }

    func refreshEnvironmentalData() async {
        guard let place = selectedEnvironmentalPlace else {
            environmentalDataMessage = "Choose a location for live conditions"
            return
        }
        isLoadingEnvironmentalData = true
        environmentalDataMessage = "Updating \(place.displayName)…"
        do {
            let snapshot = try await EnvironmentalAPI.snapshot(
                latitude: place.latitude,
                longitude: place.longitude,
                locationName: place.displayName
            )
            environmentalSnapshot = snapshot
            environmentalDataMessage = "Live modeled conditions · Open-Meteo"
            saveEnvironmentalCache()
        } catch {
            environmentalDataMessage = environmentalSnapshot.isDemonstration
                ? "Live data unavailable"
                : "Update failed · showing saved conditions"
            errorMessage = "Holo could not update environmental conditions. \(error.localizedDescription)"
        }
        isLoadingEnvironmentalData = false
    }

    private func useCurrentLocation(_ location: CLLocation) async {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.locality ?? placemark?.administrativeArea ?? "Current location"
        let place = EnvironmentalPlace(
            id: 0,
            name: name,
            region: placemark?.locality == nil ? nil : placemark?.administrativeArea,
            country: placemark?.country ?? "",
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        await selectEnvironmentalPlace(place)
    }

    private func restoreEnvironmentalCache() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.environmentalSnapshotKey),
           let snapshot = try? JSONDecoder().decode(EnvironmentalSnapshot.self, from: data) {
            environmentalSnapshot = snapshot
            environmentalDataMessage = "Saved conditions · refresh for the latest update"
        }
        if let data = defaults.data(forKey: Self.environmentalPlaceKey),
           let place = try? JSONDecoder().decode(EnvironmentalPlace.self, from: data) {
            selectedEnvironmentalPlace = place
        }
    }

    private func saveEnvironmentalCache() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(environmentalSnapshot) {
            defaults.set(data, forKey: Self.environmentalSnapshotKey)
        }
        if let selectedEnvironmentalPlace,
           let data = try? JSONEncoder().encode(selectedEnvironmentalPlace) {
            defaults.set(data, forKey: Self.environmentalPlaceKey)
        }
    }

    private func speakEnvironmentalSummary(for zone: DeskZone) {
        guard let reading = environmentalReading(for: zone) else { return }
        environmentalSpeaker.stopSpeaking()
        environmentalSpeaker.startSpeaking(reading.spokenSummary)
    }

    private func handleCalibration(_ observation: TapObservation, session: inout CalibrationSession) {
        guard session.isArmed else { return }
        guard Date() >= calibrationAcceptAfter else { return }
        guard observation.feature.strategy == session.draft.strategy else { return }
        let quality = observation.feature.quality

        if let zone = session.currentZone {
            if let issue = GuidedCaptureQuality.issue(for: quality) {
                guidedCaptureIssue = issue
                statusMessage = issue.guidance
                return
            }
            guidedCaptureIssue = nil
            session.positiveSamples.append(LabeledTap(zone: zone, feature: observation.feature))
            let count = session.count(for: zone)
            calibrationAcceptAfter = Date().addingTimeInterval(0.40)
            if let next = session.currentZone {
                if count == session.targetPerZone {
                    session.isArmed = false
                    session.isSettling = true
                    statusMessage = "Zone saved • move to \(next.displayName) • listening starts automatically"
                    scheduleCalibrationArm(for: next, delayNanoseconds: 2_000_000_000)
                } else {
                    statusMessage = "\(zone.displayName) • tap \(count + 1) of \(session.targetPerZone)"
                }
            } else {
                session.isArmed = false
                session.isSettling = false
                do {
                    calibrationValidation = try ClassifierEvaluator.leaveOneOut(session.positiveSamples)
                    statusMessage = "All four zones captured • save or add rejection examples"
                } catch {
                    calibrationValidation = nil
                    statusMessage = "Calibration review unavailable"
                    errorMessage = "Holo could not review calibration consistency. \(error.localizedDescription)"
                }
            }
        } else if let label = session.negativeLabel {
            // Rejection examples are intentionally not required to resemble a
            // clean tap. Their job is to represent talking, typing, laptop
            // touches, and other sounds that should never run an action.
            guidedCaptureIssue = nil
            session.negativeSamples.append(LabeledTap(zone: nil, negativeLabel: label, feature: observation.feature))
            statusMessage = "\(label) examples • \(session.negativeCount(for: label)) captured"
        }
    }

    private func handleBenchmark(_ observation: TapObservation, session: inout BenchmarkSession) {
        guard session.isArmed,
              Date() >= benchmarkAcceptAfter,
              let strategy = session.currentStrategy,
              let zone = session.currentZone,
              observation.feature.strategy == strategy else { return }
        let quality = observation.feature.quality
        if let issue = GuidedCaptureQuality.issue(for: quality) {
            guidedCaptureIssue = issue
            statusMessage = "Sensing comparison • \(issue.guidance)"
            return
        }
        guidedCaptureIssue = nil
        let oldStrategy = strategy
        session.samples.append(BenchmarkSample(
            labeledTap: LabeledTap(zone: zone, feature: observation.feature),
            processingLatencyMilliseconds: observation.processingLatencyMilliseconds
        ))
        benchmarkAcceptAfter = Date().addingTimeInterval(0.40)

        guard let nextStrategy = session.currentStrategy, let nextZone = session.currentZone else {
            do {
                let comparison = try ApproachComparison.measure(
                    session.samples,
                    profileID: selectedProfile?.id
                )
                approachComparison = comparison
                guard let comparisonStore else { throw HoloStorageError.unavailable("Sensing comparison") }
                try comparisonStore.save(comparison)
                calibrationDraft.strategy = comparison.selectedStrategy
                benchmarkSession = nil
                statusMessage = "Comparison selected • \(comparison.selectedStrategy.displayName)"
                let resumeStrategy = selectedProfile?.sensingStrategy ?? comparison.selectedStrategy
                Task {
                    do { try await reconfigureListeningAudio(to: resumeStrategy) }
                    catch { errorMessage = error.localizedDescription }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        let completedZone = session.count(strategy: strategy, zone: zone) == session.targetPerZone
        if completedZone {
            session.isArmed = false
            session.isSettling = false
            statusMessage = "Set saved • move to \(nextZone.displayName), then arm \(nextStrategy.displayName)"
        } else {
            let nextTap = session.count(strategy: strategy, zone: zone) + 1
            statusMessage = "Sensing comparison • \(strategy.displayName) • \(zone.displayName) • \(nextTap)/\(session.targetPerZone)"
        }
        if nextStrategy != oldStrategy {
            Task {
                do { try await reconfigureListeningAudio(to: nextStrategy) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func finishEvaluation(_ session: EvaluationSession) {
        guard let profile = selectedProfile else { return }
        let report = EvaluationReport(
            profileID: profile.id,
            profileName: profile.name,
            strategy: profile.sensingStrategy,
            startedAt: session.startedAt,
            records: session.records,
            notes: "Guided held-out session; \(EvaluationAcceptance.tapsPerZone) taps per zone."
        )
        latestEvaluation = report
        latestEvaluationIsPersisted = false
        evaluationSession = nil
        do {
            guard let evaluationStore else { throw HoloStorageError.unavailable("Evaluation report") }
            try evaluationStore.save(report)
            evaluationHistory.removeAll {
                $0.profileID == report.profileID && $0.completedAt == report.completedAt
            }
            evaluationHistory.append(report)
            evaluationHistory.sort { $0.completedAt > $1.completedAt }
            latestEvaluationIsPersisted = true
            statusMessage = report.meetsAccuracyAndLatencyTargets
                ? "Accuracy test passed"
                : "Accuracy test complete • review results"
        } catch {
            statusMessage = "Accuracy test complete • report not saved"
            errorMessage = "The accuracy test completed, but its JSON/CSV report was not saved. \(error.localizedDescription)"
        }
    }

    private var currentCaptureLabel: String {
        if let session = calibrationSession {
            if let zone = session.currentZone { return "calibration-\(zone.shortName)" }
            if let label = session.negativeLabel { return "negative-\(label)" }
        }
        if let session = evaluationSession, let zone = session.currentZone { return "evaluation-\(zone.shortName)" }
        if let session = benchmarkSession, let strategy = session.currentStrategy, let zone = session.currentZone {
            return "benchmark-\(strategy.rawValue)-\(zone.shortName)"
        }
        return diagnosticLabel.displayName
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func responseLatencyMilliseconds(for observation: TapObservation) -> Double {
        AudioTimeline.elapsedMilliseconds(
            since: observation.eventHostTimeSeconds,
            now: ProcessInfo.processInfo.systemUptime
        )
    }

    private func refreshLatestEvaluation() {
        latestEvaluation = EvaluationHistory.latest(
            for: selectedProfile?.id,
            in: evaluationHistory
        )
        latestEvaluationIsPersisted = latestEvaluation != nil
    }

    private func disarmAllCaptureIntents() {
        calibrationArmTask?.cancel()
        evaluationArmTask?.cancel()
        benchmarkArmTask?.cancel()
        calibrationSession?.isArmed = false
        calibrationSession?.isSettling = false
        calibrationSession?.negativeLabel = nil
        evaluationSession?.isArmed = false
        evaluationSession?.isSettling = false
        benchmarkSession?.isArmed = false
        benchmarkSession?.isSettling = false
        diagnosticCaptureArmed = false
        guidedCaptureIssue = nil
    }

    private func present(_ decision: ClassificationDecision) {
        activeZoneClearTask?.cancel()
        lastDecision = decision
        activeZone = decision.zone
        guard let zone = decision.zone else { return }
        activeZoneClearTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.activeZone == zone else { return }
            self.activeZone = nil
        }
    }

    private func reconfigureListeningAudio(to strategy: SensingStrategy) async throws {
        guard audio.isListening else { return }
        try await audio.reconfigure(strategy: strategy)
    }

    private func prepareGuidedAudio(to strategy: SensingStrategy) async throws {
        guard !pausedByUser else { return }
        if audio.isListening {
            try await audio.reconfigure(strategy: strategy)
        } else {
            try await audio.start(strategy: strategy)
        }
    }

    private func draft(for profile: HoloProfile) -> CalibrationDraft {
        CalibrationDraft(
            name: profile.name,
            surfaceDescription: profile.surfaceDescription,
            laptopPositionNote: profile.laptopPositionNote,
            strategy: applicableApproachComparison?.selectedStrategy ?? profile.sensingStrategy
        )
    }
}
