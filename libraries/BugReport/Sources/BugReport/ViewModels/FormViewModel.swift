//
//  Created on 2022-01-12.
//
//  Copyright (c) 2022 Proton AG
//
//  ProtonVPN is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ProtonVPN is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ProtonVPN.  If not, see <https://www.gnu.org/licenses/>.

import Foundation

@available(iOS 14.0, *)
final class FormViewModel: ObservableObject {

    @Published var fields: [FormInputField]
    @Published var isSending: Bool = false
    @Published var sendResult: BugReportDelegate.SendReportResult? {
        didSet {
            sendResultChanged?()
        }
    }

    var showLogsInfo: Bool {
        return fields.last?.boolValue == false
    }

    // Lint is disbled here, because swiftui doesn't like get-only properties
    var shouldShowResultView: Bool { get { sendResult != nil } set {} } // swiftlint:disable:this unused_setter_value
    var sendResultError: Error? {
        if case .failure(let error) = sendResult {
            return error
        }
        return nil
    }

    var canBeSent: Bool {
        var result = true

        // Check if any of mandatory fields are not filled in
        for field in fields {
            // IsMandatory - optional boolean, if the field is absent, the input field is mandatory
            guard field.inputField.isMandatory ?? true else { continue }

            switch field.inputField.type {
            case .textSingleLine, .textMultiLine:
                if field.stringValue.isEmpty {
                    result = false
                }
            case .switch:
                if !field.boolValue {
                    result = false
                }
            }
        }

        return result
    }

    var sendResultChanged: (() -> Void)?

    // MARK: - User actions

    func sendTapped() {
        guard canBeSent && !isSending else { return }
        isSending = true
        self.sendResult = nil

        delegate?.send(form: makeResult(), result: { requestResult in
            self.isSending = false
            self.sendResult = requestResult
        })
    }

    func troubleshootingTapped() {
        delegate?.troubleshootingRequired()
    }

    func finished() {
        delegate?.finished()
    }

    // MARK: - Other

    private weak var delegate: BugReportDelegate? = Current.bugReportDelegate
    private let emailFieldName = "_email"
    private let logsFieldName = "_logs"

    init(fields: [InputField]) {
        var formFields: [FormInputField] = []

        // Email field is always first
        formFields.append(FormInputField(
            inputField: InputField(
                label: LocalizedString.br3Email,
                submitLabel: emailFieldName,
                type: .textSingleLine,
                isMandatory: true,
                placeholder: nil
            ),
            stringValue: delegate?.prefilledEmail ?? ""
        ))

        formFields.append(contentsOf: fields.map { FormInputField(inputField: $0) })

        // Logs field is always last
        formFields.append(FormInputField(
            inputField: InputField(
                label: LocalizedString.br3LogsField,
                submitLabel: logsFieldName,
                type: .switch,
                isMandatory: false,
                placeholder: LocalizedString.br3LogsDescription),
            boolValue: true)
        )

        self.fields = formFields
    }

    private func makeResult() -> BugReportResult {
        var email = ""
        var text = ""
        var logs = false

        for field in fields {
            // Custom pre-set fields
            if field.inputField.submitLabel == emailFieldName {
                email = field.stringValue
                continue
            }
            if field.inputField.submitLabel == logsFieldName {
                logs = field.boolValue
                continue
            }

            // Fields from the outside
            switch field.inputField.type {
            case .textSingleLine, .textMultiLine:
                text += "\(field.inputField.submitLabel)\n"
                text += "\(field.stringValue)\n---\n"
            case .switch:
                text += "\(field.inputField.submitLabel): "
                text += "\(field.boolValue ? "YES" : "NO")\n---\n"
            }
        }

        return BugReportResult(email: email, text: text, logs: logs)
    }
}
