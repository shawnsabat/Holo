import HoloCore
import SwiftUI

struct LiveSurfaceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.selectedProfile == nil {
            setupPrompt
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(36)
                .background(HoloTheme.background)
        } else {
            liveDesk
        }
    }

    private var liveDesk: some View {
        ScrollView {
            VStack(spacing: 20) {
                demonstrationNotice

                DeskMapView(
                    activeZone: model.activeZone,
                    targetZone: nil,
                    confidence: model.lastDecision?.confidence ?? 0,
                    signalStrength: model.lastDecision?.signalStrength ?? model.audio.liveLevel,
                    isListening: model.audio.isListening,
                    showsEnvironmentalTopics: true
                )
                .frame(maxWidth: 800, minHeight: 360, maxHeight: 460)
                .padding(.horizontal, 24)

                environmentalReadings
                resultStrip
            }
            .frame(maxWidth: 860)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .background(HoloTheme.background)
    }

    private var demonstrationNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "testtube.2")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Demonstration readings")
                    .font(.callout.weight(.semibold))
                Text("These values teach the interface and are not live conditions. Live location and environmental data are the next integration step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Explain terms", isOn: $model.learningMode)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Show plain-language explanations of environmental terms")
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: 760)
    }

    private var environmentalReadings: some View {
        VStack(spacing: 0) {
            ForEach(model.environmentalSnapshot.readings) { reading in
                environmentalRow(reading)
                if reading.id != model.environmentalSnapshot.readings.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: 760)
    }

    private func environmentalRow(_ reading: EnvironmentalReading) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: reading.topic.symbolName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(reading.topic.title)
                        .font(.headline)
                    Text(reading.headline)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(reading.value)
                        .font(.callout.monospacedDigit().weight(.medium))
                }
                Text(reading.guidance)
                    .font(.callout)
                if model.learningMode {
                    Text(reading.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 4)
        .background(reading.topic == model.activeZone?.environmentalTopic ? Color.accentColor.opacity(0.08) : .clear)
        .accessibilityElement(children: .combine)
    }

    private var setupPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("Set up the desk around your MacBook")
                .font(.title2.weight(.semibold))
            Text("Taps cannot be assigned until Holo learns this desk. You will tap ten times across each of four broad zones: rear and front on both sides of the MacBook.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Text("Microphone access is requested when calibration begins.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Set Up Four Zones") {
                model.openSetup()
            }
            .holoPrimaryButton()
            .controlSize(.large)
        }
        .padding(.top, 4)
    }

    private var resultStrip: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lastResultTitle)
                    .font(.headline)
                Text(model.lastDecision?.rejectionReason?.displayName ?? model.selectedProfile?.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 170, alignment: .leading)

            Divider().frame(height: 34)

            compactGauge("Confidence", value: model.lastDecision?.confidence ?? 0)
            compactGauge("Signal", value: model.lastDecision?.signalStrength ?? model.audio.liveLevel)

            if let latency = model.lastDecision?.processingLatencyMilliseconds, latency > 0 {
                Divider().frame(height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f ms", latency))
                        .font(.callout.monospacedDigit())
                    Text("Processing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Recalibrate", systemImage: "arrow.triangle.2.circlepath") {
                model.prepareRecalibration()
            }
            .holoSecondaryButton()
        }
        .padding(16)
        .frame(maxWidth: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var lastResultTitle: String {
        guard let decision = model.lastDecision else { return "Waiting for a tap" }
        return decision.zone?.environmentalTopic.title ?? "Tap rejected"
    }

    private func compactGauge(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(value * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: value)
                .frame(width: 112)
        }
    }
}
