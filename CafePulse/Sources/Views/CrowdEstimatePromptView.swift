import SwiftUI

struct CrowdEstimatePromptView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How full is the cafe right now?")
                .font(.title3.weight(.semibold))

            Picker("Fullness", selection: fullnessBinding) {
                ForEach(CrowdFullness.allCases) { fullness in
                    Text(fullness.displayName).tag(fullness)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Include estimated people count", isOn: includePeopleCountBinding)

            if model.crowdEstimateDraft.includePeopleCount {
                Stepper(value: peopleCountBinding, in: 0...500, step: 1) {
                    Text("Estimated people: \(model.crowdEstimateDraft.peopleCount)")
                }
            }

            Spacer()

            HStack {
                Button("Dismiss") {
                    model.dismissCrowdEstimatePrompt()
                }

                Spacer()

                Button("Save Estimate") {
                    model.submitCrowdEstimate()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }

    private var fullnessBinding: Binding<CrowdFullness> {
        Binding(
            get: { model.crowdEstimateDraft.fullness },
            set: {
                model.crowdEstimateDraft.fullness = $0
            }
        )
    }

    private var includePeopleCountBinding: Binding<Bool> {
        Binding(
            get: { model.crowdEstimateDraft.includePeopleCount },
            set: {
                model.crowdEstimateDraft.includePeopleCount = $0
            }
        )
    }

    private var peopleCountBinding: Binding<Int> {
        Binding(
            get: { model.crowdEstimateDraft.peopleCount },
            set: {
                model.crowdEstimateDraft.peopleCount = $0
            }
        )
    }
}
