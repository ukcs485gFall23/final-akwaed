/*
 Copyright (c) 2019, Apple Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 1.  Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2.  Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.
 
 3. Neither the name of the copyright holder(s) nor the names of any contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission. No license is granted to the trademarks of
 the copyright holders even if such marks are included in this software.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import CareKit
import CareKitStore
import CareKitUI
import CareKitUtilities
import os.log
import ResearchKit
import SwiftUI
import UIKit

@MainActor
class CareViewController: OCKDailyPageViewController {

    private var isSyncing = false
    private var isLoading = false
    var events: CareStoreFetchedResults<OCKAnyEvent, OCKEventQuery>? {
        didSet {
            self.reloadView()
        }
    }

    /// Create an instance of the view controller. Will hook up the calendar to the tasks collection,
    /// and query and display the tasks.
    ///
    /// - Parameter store: The store from which to query the tasks.
    /// - Parameter computeProgress: Used to compute the combined progress for a series of CareKit events.
    init(store: OCKAnyStoreProtocol,
         events: CareStoreFetchedResults<OCKAnyEvent, OCKEventQuery>? = nil,
         computeProgress: @escaping (OCKAnyEvent) -> CareTaskProgress = { event in
        event.computeProgress(by: .checkingOutcomeExists)
    }) {
        super.init(store: store, computeProgress: computeProgress)
        self.events = events
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh,
                                                            target: self,
                                                            action: #selector(synchronizeWithRemote))
        NotificationCenter.default.addObserver(self, selector: #selector(synchronizeWithRemote),
                                               name: Notification.Name(rawValue: Constants.requestSync),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateSynchronizationProgress(_:)),
                                               name: Notification.Name(rawValue: Constants.progressUpdate),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadView(_:)),
                                               name: Notification.Name(rawValue: Constants.finishedAskingForPermission),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadView(_:)),
                                               name: Notification.Name(rawValue: Constants.shouldRefreshView),
                                               object: nil)
    }

    @objc private func updateSynchronizationProgress(_ notification: Notification) {
        guard let receivedInfo = notification.userInfo as? [String: Any],
            let progress = receivedInfo[Constants.progressUpdate] as? Int else {
            return
        }

        DispatchQueue.main.async {
            switch progress {
            case 0, 100:
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "\(progress)",
                                                                         style: .plain, target: self,
                                                                         action: #selector(self.synchronizeWithRemote))
                if progress == 100 {
                    // Give sometime for the user to see 100
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh,
                                                                                 target: self,
                                                                                 // swiftlint:disable:next line_length
                                                                                 action: #selector(self.synchronizeWithRemote))
                        // swiftlint:disable:next line_length
                        self.navigationItem.rightBarButtonItem?.tintColor = self.navigationItem.leftBarButtonItem?.tintColor
                    }
                }
            default:
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "\(progress)",
                                                                         style: .plain, target: self,
                                                                         action: #selector(self.synchronizeWithRemote))
                self.navigationItem.rightBarButtonItem?.tintColor = TintColorKey.defaultValue
            }
        }
    }

    @objc private func synchronizeWithRemote() {
        guard !isSyncing else {
            return
        }
        isSyncing = true
        AppDelegateKey.defaultValue?.store.synchronize { error in
            let errorString = error?.localizedDescription ?? "Successful sync with remote!"
            Logger.feed.info("\(errorString)")
            DispatchQueue.main.async {
                if error != nil {
                    self.navigationItem.rightBarButtonItem?.tintColor = .red
                } else {
                    self.navigationItem.rightBarButtonItem?.tintColor = self.navigationItem.leftBarButtonItem?.tintColor
                }
                self.isSyncing = false
            }
        }
    }

    @objc private func reloadView(_ notification: Notification? = nil) {
        guard !isLoading else {
            return
        }
        DispatchQueue.main.async {
            self.isLoading = true
            self.reload()
        }
    }

    /*
     This will be called each time the selected date changes.
     Use this as an opportunity to rebuild the content shown to the user.
     */
    override func dailyPageViewController(_ dailyPageViewController: OCKDailyPageViewController,
                                          prepare listViewController: OCKListViewController, for date: Date) {

        Task {

            guard await Utility.checkIfOnboardingIsComplete() else {
                let onboardSurvey = Onboard()
                var query = OCKEventQuery(for: Date())
                query.taskIDs = [Onboard.identifier()]
                let onboardCard = OCKSurveyTaskViewController(eventQuery: query,
                                                              store: self.store,
                                                              survey: onboardSurvey.createSurvey(),
                                                              extractOutcome: { _ in [OCKOutcomeValue(Date())] })
                onboardCard.surveyDelegate = self

                listViewController.clear()
                listViewController.appendViewController(
                    onboardCard,
                    animated: false
                )
                self.isLoading = false
                return
            }

            do {
                let tasks = try await fetchTasks(on: date)
                let isCurrentDay = Calendar.current.isDate(date, inSameDayAs: Date())
                let taskCards = tasks.compactMap {
                    let cards = self.taskViewController(for: $0,
                                                        on: date)
                    cards?.forEach {
                        if let carekitView = $0.view as? OCKView {
                            carekitView.customStyle = CustomStylerKey.defaultValue
                        }
                        $0.view.isUserInteractionEnabled = isCurrentDay
                        $0.view.alpha = !isCurrentDay ? 0.4 : 1.0
                    }
                    return cards
                }

                // Only show the tip view on the current date
                listViewController.clear()
                if isCurrentDay {
                    if Calendar.current.isDate(date, inSameDayAs: Date()) {
                        // Add a non-CareKit view into the list
                        /*let tipTitle = "Benefits of exercising"
                        let tipText = "Learn how activity can promote a healthy pregnancy."
                        let tipView = TipView()
                        tipView.headerView.titleLabel.text = tipTitle
                        tipView.headerView.detailLabel.text = tipText
                        tipView.imageView.image = UIImage(named: "exercise.jpg")
                        tipView.customStyle = CustomStylerKey.defaultValue
                         listViewController.appendView(tipView, animated: false)
                        */
                        let customFeaturedView = CustomFeaturedContentViewController(
                            url: "https://www.reddit.com/r/Ergonomics/",
                            imageOverlayStyle: .unspecified,
                            image: UIImage(named: "banner"),
                            text: "Reddit Community",
                            textColor: .white)
                        customFeaturedView.customStyle = CustomStylerKey.defaultValue
                        listViewController.appendView(customFeaturedView, animated: false)

                    }
                }

                // Added custom card.
                let newCustomCard = CustomCardView()
                    .careKitStyle(CustomStylerKey.defaultValue)
                let newCustomCardViewController = newCustomCard.formattedHostingController()
                listViewController.appendViewController(
                    newCustomCardViewController,
                    animated: false
                )
                _ = AlcoholIntakeCard()
                    .careKitStyle(CustomStylerKey.defaultValue)

                taskCards.forEach { (cards: [UIViewController]) in
                    cards.forEach {
                        listViewController.appendViewController($0, animated: false)
                    }
                }
            } catch {
                Logger.feed.error("Could not fetch tasks: \(error)")
            }

            self.isLoading = false

        }

    }

    private func getStoreFetchRequestEvent(for taskId: String) -> CareStoreFetchedResult<OCKAnyEvent>? {
        events?.filter({ $0.result.task.id == taskId }).last
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func taskViewController(for task: OCKAnyTask,
                                    on date: Date) -> [UIViewController]? {

        var query = OCKEventQuery(for: Date())
        query.taskIDs = [task.id]

        let cardView: CareKitCard!

        if let task = task as? OCKTask {
            cardView = task.card
        } else if let task = task as? OCKHealthKitTask {
            cardView = task.card
        } else {
            return nil
        }

        switch cardView {
        case .numericProgress:
            guard let event = getStoreFetchRequestEvent(for: task.id) else {
                return nil
            }
            let view = NumericProgressTaskView<InformationHeaderView>(event: event, numberFormatter: .none)
                .careKitStyle(CustomStylerKey.defaultValue)

            return [view.formattedHostingController()]

        case .custom:
            /*
             xTODO: Example of showing how to use your custom card. This
             should be placed correctly for the final to receive credit.
             This card currently only shows when numericProgress is selected,
             you should add the card to the switch statement properly to
             make it show on purpose when the card type is selected.
            */
            guard let event = getStoreFetchRequestEvent(for: task.id) else {
                return nil
            }
            let view = NumericProgressTaskView<InformationHeaderView>(event: event, numberFormatter: .none)
                .careKitStyle(CustomStylerKey.defaultValue)

            return [view.formattedHostingController()]

        case .instruction:
            return [OCKInstructionsTaskViewController(query: query,
                                                      store: self.store)]

        case .simple:
            /*
             Since the kegel task is only scheduled every other day, there will be cases
             where it is not contained in the tasks array returned from the query.
             */
            return [OCKSimpleTaskViewController(query: query,
                                                store: self.store)]

        // Create a card for the doxylamine task if there are events for it on this day.
        case .checklist:

            return [OCKChecklistTaskViewController(query: query,
                                                   store: self.store)]

        case .button:

            /*
             Also create a card that displays a single event.
             The event query passed into the initializer specifies that only
             today's log entries should be displayed by this log task view controller.
             */
            let waterIntakeCard = OCKButtonLogTaskViewController(query: query,
                                                            store: self.store)
            return [waterIntakeCard]

        case .labeledValue:

            guard let event = getStoreFetchRequestEvent(for: task.id) else {
                return nil
            }
            let view = LabeledValueTaskView<_LabeledValueTaskViewHeader>(event: event, numberFormatter: .none)
                .careKitStyle(CustomStylerKey.defaultValue)

            return [view.formattedHostingController()]

        case .link:
            let linkView = LinkView(title: .init("My Link"),
                                    // swiftlint:disable:next line_length
                                    links: [.website("http://www.engr.uky.edu/research-faculty/departments/computer-science",
                                                     title: "College of Engineering")])
            return [linkView.formattedHostingController()]

        case .survey:
            guard let surveyTask = task as? OCKTask else {
                Logger.feed.error("Can only use a survey for an \"OCKTask\", not \(task.id)")
                return nil
            }

            let surveyCard = OCKSurveyTaskViewController(
                eventQuery: query,
                store: self.store,
                survey: surveyTask.survey.type().createSurvey(),
                viewSynchronizer: SurveyViewSynchronizer(),
                extractOutcome: surveyTask.survey.type().extractAnswers
            )
            surveyCard.surveyDelegate = self
            return [surveyCard]

        default:
            // Check if a healthKit task
            guard task is OCKHealthKitTask else {
                return [OCKSimpleTaskViewController(query: query,
                                                    store: self.store)]
            }

            guard let event = getStoreFetchRequestEvent(for: task.id) else {
                return nil
            }

            let view = LabeledValueTaskView<_LabeledValueTaskViewHeader>(event: event, numberFormatter: .none)
                .careKitStyle(CustomStylerKey.defaultValue)

            return [view.formattedHostingController()]
        }
    }

    private func fetchTasks(on date: Date) async throws -> [OCKAnyTask] {
        var query = OCKTaskQuery(for: date)
        query.excludesTasksWithNoEvents = true
        let tasks = try await store.fetchAnyTasks(query: query)

        // Remove onboarding tasks from array
        let filteredTasks = tasks.filter { $0.id != Onboard.identifier() }
        return filteredTasks
    }

}

private extension View {
    func formattedHostingController() -> UIHostingController<Self> {
        let viewController = UIHostingController(rootView: self)
        viewController.view.backgroundColor = .clear
        return viewController
    }
}

extension CareViewController: OCKSurveyTaskViewControllerDelegate {
    func surveyTask(viewController: OCKSurveyTaskViewController,
                    for task: OCKAnyTask,
                    didFinish result: Result<ORKTaskViewControllerFinishReason, Error>) {

        if case let .success(reason) = result, reason == .completed {
            reload()
        }
    }
}
