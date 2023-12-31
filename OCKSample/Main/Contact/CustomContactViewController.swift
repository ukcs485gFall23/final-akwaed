//
//  CustomContactViewController.swift
//  OCKSample
//
//  Created by Elnoel Akwa on 11/7/23.
//  Copyright © 2023 Network Reconnaissance Lab. All rights reserved.
//

import UIKit
import CareKitStore
import CareKit
import Contacts
import ContactsUI
import ParseSwift
import ParseCareKit
import os.log

class CustomContactViewController: OCKListViewController {

    fileprivate var allContacts = [OCKContact]()
    var contacts: CareStoreFetchedResults<OCKAnyContact, OCKContactQuery>? {
        didSet {
            reloadView()
        }
    }

    /// The store the view controller uses for synchronization.
    fileprivate let store: OCKAnyStoreProtocol
    fileprivate let viewSynchronizer: OCKSimpleContactViewSynchronizer

    /// Create an instance of the view controller. Will hook up the calendar to the tasks collection,
    /// and query and display the tasks.
    ///
    /// - Parameter store: The store from which to query the tasks.
    /// - Parameter contacts: The current contacts queryied.
    /// - Parameter viewSynchronizer: The type of view to show
    init(store: OCKAnyStoreProtocol,
         contacts: CareStoreFetchedResults<OCKAnyContact, OCKContactQuery>? = nil,
         viewSynchronizer: OCKSimpleContactViewSynchronizer
    ) {
        self.store = store
        self.contacts = contacts
        self.viewSynchronizer = viewSynchronizer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.searchBarStyle = UISearchBar.Style.prominent
        searchController.searchBar.placeholder = " Search Contacts"
        searchController.searchBar.showsCancelButton = true
        searchController.searchBar.delegate = self
        navigationItem.searchController = searchController
        definesPresentationContext = true

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                           target: self,
                                                           action: #selector(presentContactsListViewController))

        reloadView()
    }

    override func viewDidAppear(_ animated: Bool) {
        reloadView()
    }

    @objc private func presentContactsListViewController() {

        let contactPicker = CNContactPickerViewController()
        contactPicker.view.tintColor = self.view.tintColor
        contactPicker.delegate = self
        contactPicker.predicateForEnablingContact = NSPredicate(
          format: "phoneNumbers.@count > 0")
        present(contactPicker, animated: true, completion: nil)
    }

    @objc private func dismissViewController() {
        dismiss(animated: true, completion: nil)
    }

    func clearAndKeepSearchBar() {
        clear()
    }

    func reloadView() {
        Task {
            try? await updateContacts()
        }
    }

    @MainActor
    func updateContacts() async throws {

        guard (try? await User.current()) != nil else {
            Logger.contact.error("User not logged in")
            return
        }

        guard let personUUIDString = (try? await Utility.getRemoteClockUUID())?.uuidString else {
            Logger.contact.error("Could not get logged in personUUID")
            return
        }
        /*
                 TODOy: You should not show any contacts if your user has not completed the
                 onboarding task yet. There was a method added recently in Utility.swift to
                 assist with this. Use this method here and write a comment and state if
                 it's an "instance method" or "type method". If you are trying to copy the
                 method to this file, you are using the code incorrectly. Be
                 sure to understand the difference between a type method and instance method.
                 */

        guard let contacts = contacts else {
            Logger.contact.error("No contacts to display")
            return
        }
        if await Utility.checkIfOnboardingIsComplete() {
            let filterdContacts = contacts.filter { convertedContact in
                Logger.contact.info("Contact filtered: \(convertedContact.id)")
                if convertedContact.id == personUUIDString {
                    return false
                } else {
                    return true
                }
            }

            self.clearAndKeepSearchBar()
            // Map all filtered contacts to a direct contact.
            self.allContacts = filterdContacts.compactMap { $0.result as? OCKContact }
            self.displayContacts(self.allContacts)
        }
    }
    @MainActor
    func displayContacts(_ contacts: [OCKAnyContact]) {
        var query = ContactViewModel.contactQuery()

        for contact in contacts {
            query.ids = [contact.id]
            query.limit = 1
            let contactViewController = OCKSimpleContactViewController(
                query: query,
                store: store,
                viewSynchronizer: viewSynchronizer
            )
            self.appendViewController(contactViewController, animated: false)
        }
    }

    func convertDeviceContacts(_ contact: CNContact) -> OCKAnyContact {

        var convertedContact = OCKContact(id: contact.identifier, givenName: contact.givenName,
                                          familyName: contact.familyName, carePlanUUID: nil)
        convertedContact.title = contact.jobTitle

        var emails = [OCKLabeledValue]()
        contact.emailAddresses.forEach {
            emails.append(OCKLabeledValue(label: $0.label ?? "email", value: $0.value as String))
        }
        convertedContact.emailAddresses = emails

        var phoneNumbers = [OCKLabeledValue]()
        contact.phoneNumbers.forEach {
            phoneNumbers.append(OCKLabeledValue(label: $0.label ?? "phone", value: $0.value.stringValue))
        }
        convertedContact.phoneNumbers = phoneNumbers
        convertedContact.messagingNumbers = phoneNumbers

        if let address = contact.postalAddresses.first {
            convertedContact.address = {
                let newAddress = OCKPostalAddress()
                newAddress.street = address.value.street
                newAddress.city = address.value.city
                newAddress.state = address.value.state
                newAddress.postalCode = address.value.postalCode
                return newAddress
            }()
        }

        return convertedContact
    }
}

extension CustomContactViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        Logger.contact.debug("Searching text is '\(searchText)'")

        if searchBar.text!.isEmpty {
            // Show all contacts
            clearAndKeepSearchBar()
            displayContacts(allContacts)
            return
        }

        clearAndKeepSearchBar()

        let filteredContacts = allContacts.filter { (contact: OCKAnyContact) -> Bool in

            if let givenName = contact.name.givenName {
                return givenName.lowercased().contains(searchText.lowercased())
            } else if let familyName = contact.name.familyName {
                return familyName.lowercased().contains(searchText.lowercased())
            } else {
                return false
            }
        }
        displayContacts(filteredContacts)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        clearAndKeepSearchBar()
        displayContacts(allContacts)
    }
}

extension CustomContactViewController: CNContactPickerDelegate {

    @MainActor
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        Task {
            guard (try? await User.current()) != nil else {
                Logger.contact.error("User not logged in")
                return
            }

            let contactToAdd = convertDeviceContacts(contact)

            if !(self.allContacts.contains { $0.id == contactToAdd.id }) {

                // Note - once the functionality is added to edit a contact,
                // let the user potentially edit before the save
                do {
                    _ = try await store.addAnyContact(contactToAdd)
                } catch {
                    Logger.contact.error("Could not add contact: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
        Task {
            guard (try? await User.current()) != nil else {
                Logger.contact.error("User not logged in")
                return
            }

            let newContacts = contacts.compactMap { convertDeviceContacts($0) }

            var contactsToAdd = [OCKAnyContact]()
            for newContact in newContacts {
                // swiftlint:disable:next for_where
                if self.allContacts.first(where: { $0.id == newContact.id }) == nil {
                    contactsToAdd.append(newContact)
                }
            }

            let immutableContactsToAdd = contactsToAdd

            do {
                _ = try await store.addAnyContacts(immutableContactsToAdd)
            } catch {
                Logger.contact.error("Could not add contacts: \(error.localizedDescription)")
            }
        }
    }
}
