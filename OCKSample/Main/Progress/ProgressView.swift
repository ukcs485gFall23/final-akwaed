//
//  ProgressView.swift
//  OCKSample
//
//  Created by  on 12/9/23.
//  Copyright © 2023 Network Reconnaissance Lab. All rights reserved.
//

import CareKit
import CareKitStore
import CareKitUI
import CareKitUtilities
import SwiftUI

struct ProgressView: View {
    @Environment(\.tintColor) private var tintColor
    @CareStoreFetchRequest(query: ProgressViewModel.queryEvents()) private var events

    var body: some View {
        NavigationView {
            ScrollView {
                VStack {

                    // Example of using a CareKitUIView.
                    LinkView(
                        title: .init("Other Communities worth checking"),
                        links: [
                            .website(
                                "https://www.quora.com/topic/Ergonomics",
                                title: "Quora"

                            )
                        ]
                    )

                    if let stepEvent = getEvent(for: TaskID.steps) {

                        // Example of using another CareKitUIView.
                        NumericProgressTaskView<InformationHeaderView>(event: stepEvent)
                    }

                    if let standingEvent = getEvent(for: TaskID.standingTime) {
                        // Example of using another CareKitUIView.
                        NumericProgressTaskView<InformationHeaderView>(event: standingEvent)
                    }
                    if let alchoolIntake = getEvent(for: TaskID.alchoolIntake) {
                        // Example of using another CareKitUIView.
                        NumericProgressTaskView<InformationHeaderView>(event: alchoolIntake)

                    }

                    AlcoholIntakeCard()

                }
                .padding()
            }
            .background(Color(.systemGray6))
        }
    }

    /// Helper method for getting specific event to show on a CareKit SwiftUI card.
    private func getEvent(for taskId: String) -> CareStoreFetchedResult<OCKAnyEvent>? {
        events.filter({ $0.result.task.id == taskId }).last
    }
}

// Only need to make this change for older Xcode, otherwise use #Preview.
struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ProgressView()
            .accentColor(Color(TintColorKey.defaultValue))
            .environment(\.appDelegate, AppDelegate())
            .environment(\.careStore, Utility.createPreviewStore())
    }
}
