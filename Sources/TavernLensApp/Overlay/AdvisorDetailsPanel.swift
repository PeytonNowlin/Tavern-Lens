import OverlayLayout
import SwiftUI
import TavernEngine

/// Scrollable explanations occupy the existing build-tips space only while requested.
/// The visible sequence belongs to one advice fingerprint and never becomes a saved checklist.
struct AdvisorDetailsPanel: View {
    let presentation: AdvisorPresentation
    let scale: CGFloat
    var density: OverlayDensity = .compact
    let name: (String) -> String

    private var type: AdvisorTypography { AdvisorTypography(density: density, panelScale: scale) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13 * scale) {
                Text("WHY & PLAN")
                    .font(.system(size: type.labelFontSize, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(AdvisorStyle.accent)
                if let primary = presentation.primary {
                    section("Why this action") { Text(primary.reason) }
                    section("Sequence · reassess after each action") {
                        ForEach(Array(primary.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(index + 1).")
                                    .monospacedDigit().foregroundStyle(.secondary)
                                Text(step)
                            }
                        }
                    }
                    if !primary.limitations.isEmpty {
                        section("Limits to this advice") {
                            ForEach(Array(primary.limitations.enumerated()), id: \.offset) { _, limitation in
                                Text(limitation).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    section(presentation.title) { Text(presentation.reason) }
                }
                if let note = presentation.note, note != presentation.reason {
                    Text(note).foregroundStyle(.secondary)
                }
                if !presentation.alternatives.isEmpty {
                    section(presentation.primary == nil ? "Tentative options" : "Alternative actions") {
                        ForEach(Array(presentation.alternatives.enumerated()), id: \.offset) { _, option in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title).fontWeight(.medium)
                                Text(AdvisorStyle.label(option.confidence))
                                    .foregroundStyle(AdvisorStyle.color(option.confidence))
                                Text(option.reason).foregroundStyle(.secondary)
                                if option.steps.count > 1 {
                                    Text(option.steps.joined(separator: " → "))
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(Array(option.limitations.enumerated()), id: \.offset) { _, limitation in
                                    Text(limitation).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if let direction = presentation.direction {
                    section(direction.committed ? "Suggested direction · Building" : "Suggested direction · Considering") {
                        Text(direction.name).fontWeight(.medium)
                        Text(direction.reason)
                        if !presentation.requirements.isEmpty {
                            ForEach(Array(presentation.requirements.enumerated()), id: \.offset) { _, requirement in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(requirementLabel(requirement.state)): \(requirement.role)")
                                        .fontWeight(.medium)
                                    if !requirement.cards.isEmpty {
                                        Text(requirement.cards.joined(separator: " or "))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } else if !direction.missing.isEmpty {
                            Text("Look for: " + direction.missing.map(name).joined(separator: ", "))
                        }
                        if let commitment = direction.commitment { Text(commitment) }
                        if let guidance = direction.guidance { Text(guidance) }
                        Text(direction.acquisition).foregroundStyle(.secondary)
                        Text(direction.fallback).foregroundStyle(.secondary)
                        if let source = direction.source {
                            Text("Source: \(source)").foregroundStyle(.secondary)
                        }
                        if let updated = direction.sourceUpdated {
                            Text(updated).foregroundStyle(.secondary)
                        }
                    }
                }
                if !presentation.currentFits.isEmpty {
                    section("Current fit · held pieces") {
                        ForEach(presentation.currentFits, id: \.id) { fit in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fit.name).fontWeight(.medium)
                                if !fit.coreHave.isEmpty {
                                    Text("Owned: " + fit.coreHave.map(name).joined(separator: ", "))
                                }
                                if !fit.coreMissing.isEmpty {
                                    Text("Unowned core: " + fit.coreMissing.map(name).joined(separator: ", "))
                                        .foregroundStyle(.secondary)
                                }
                                if let commitment = fit.tips.whenToCommit { Text(commitment) }
                                if let tip = fit.tips.tip { Text(tip).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .font(.system(size: type.bodyFontSize))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10 * scale)
        }
        .scrollIndicators(.visible)
        .modifier(AdvisorSurface(radius: 10 * scale))
        .accessibilityLabel("Advisor explanation and plan")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            Text(title).font(.system(size: type.labelFontSize, weight: .semibold))
                .foregroundStyle(AdvisorStyle.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requirementLabel(_ state: AdvisorPresentation.Requirement.State) -> String {
        switch state {
        case .owned: "Owned"
        case .available: "Available now"
        case .required: "Still need"
        case .unverified: "Unverified"
        }
    }
}
