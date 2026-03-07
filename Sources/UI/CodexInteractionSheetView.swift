import SwiftUI

struct CodexInteractionSheetView: View {
    let request: CodexInteractionRequest
    let onResolve: (CodexInteractionResponse) -> Void

    @State private var textAnswers: [String: String]
    @State private var selectedOptions: [String: String]
    @State private var validationMessage: String?

    init(request: CodexInteractionRequest, onResolve: @escaping (CodexInteractionResponse) -> Void) {
        self.request = request
        self.onResolve = onResolve

        if case .userInput(let input) = request.kind {
            _selectedOptions = State(initialValue: Dictionary(uniqueKeysWithValues: input.questions.compactMap { question in
                question.options.first.map { (question.id, $0.label) }
            }))
        } else {
            _selectedOptions = State(initialValue: [:])
        }
        _textAnswers = State(initialValue: [:])
        _validationMessage = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JinSpacing.large) {
                    headerCard

                    switch request.kind {
                    case .commandApproval(let approval):
                        commandApprovalContent(approval)
                    case .fileChangeApproval(let approval):
                        fileChangeApprovalContent(approval)
                    case .userInput(let input):
                        userInputContent(input)
                    }

                    if let validationMessage, !validationMessage.isEmpty {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(JinSpacing.small)
                            .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                    }
                }
                .padding(JinSpacing.large)
            }
            .background {
                JinSemanticColor.detailSurface
                    .ignoresSafeArea()
            }
            .navigationTitle(request.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        switch request.kind {
                        case .commandApproval, .fileChangeApproval:
                            onResolve(.approval(.cancel))
                        case .userInput:
                            onResolve(.cancelled(message: "User cancelled the Codex interaction."))
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch request.kind {
                    case .userInput:
                        Button("Submit") {
                            submitUserInput()
                        }
                    case .commandApproval, .fileChangeApproval:
                        EmptyView()
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 420, idealHeight: 520)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            if let subtitle = request.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .jinInfoCallout()
            } else {
                Text(requestDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: JinSpacing.small) {
                if let threadID = request.threadID, !threadID.isEmpty {
                    codexMetaPill(title: "Thread", value: threadID)
                }
                if let turnID = request.turnID, !turnID.isEmpty {
                    codexMetaPill(title: "Turn", value: turnID)
                }
            }
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }

    private var requestDescription: String {
        switch request.kind {
        case .commandApproval:
            return "Codex paused because the current approval policy requires explicit consent for this command."
        case .fileChangeApproval:
            return "Codex paused before writing files outside the current allowance."
        case .userInput:
            return "Codex needs a small bit of guidance before it can continue the turn."
        }
    }

    @ViewBuilder
    private func commandApprovalContent(_ approval: CodexCommandApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            if let command = approval.command, !command.isEmpty {
                codexCodeCard(title: "Command", content: command)
            }

            if let cwd = approval.cwd, !cwd.isEmpty {
                codexCodeCard(title: "Working Directory", content: cwd)
            }

            if !approval.actionSummaries.isEmpty {
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text("Detected Actions")
                        .font(.headline)

                    ForEach(approval.actionSummaries) { action in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                            if let subtitle = action.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(JinSpacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .jinSurface(.subtle, cornerRadius: JinRadius.small)
                    }
                }
                .padding(JinSpacing.large)
                .jinSurface(.raised, cornerRadius: JinRadius.large)
            }

            approvalButtons
        }
    }

    @ViewBuilder
    private func fileChangeApprovalContent(_ approval: CodexFileChangeApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            if let grantRoot = approval.grantRoot, !grantRoot.isEmpty {
                codexCodeCard(title: "Requested Write Root", content: grantRoot)
            }

            VStack(alignment: .leading, spacing: JinSpacing.small) {
                Text("Changed Files")
                    .font(.headline)

                if approval.fileChanges.isEmpty {
                    Text("Codex did not provide a file list, but it is asking for write approval.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(approval.fileChanges) { change in
                        HStack(alignment: .top, spacing: JinSpacing.small) {
                            Text(change.changeType.uppercased())
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, JinSpacing.xSmall)
                                .padding(.vertical, 3)
                                .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
                            Text(change.path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(JinSpacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .jinSurface(.subtle, cornerRadius: JinRadius.small)
                    }
                }
            }
            .padding(JinSpacing.large)
            .jinSurface(.raised, cornerRadius: JinRadius.large)

            approvalButtons
        }
    }

    @ViewBuilder
    private func userInputContent(_ input: CodexUserInputRequest) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            ForEach(input.questions) { question in
                VStack(alignment: .leading, spacing: JinSpacing.small) {
                    Text(question.header)
                        .font(.headline)
                    Text(question.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !question.options.isEmpty {
                        Picker("", selection: bindingForSelectedOption(questionID: question.id)) {
                            ForEach(question.options, id: \.label) { option in
                                Text(option.label).tag(option.label)
                            }
                        }
                        .pickerStyle(.menu)

                        if let detail = question.options.first(where: { $0.label == selectedOptions[question.id] })?.detail,
                           !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if question.isOtherAllowed || question.options.isEmpty {
                        Group {
                            if question.isSecret {
                                SecureField("Your answer", text: bindingForTextAnswer(questionID: question.id))
                            } else {
                                TextField("Your answer", text: bindingForTextAnswer(questionID: question.id), axis: .vertical)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(JinSpacing.large)
                .jinSurface(.raised, cornerRadius: JinRadius.large)
            }
        }
    }

    private var approvalButtons: some View {
        HStack(spacing: JinSpacing.medium) {
            Button(CodexApprovalChoice.decline.displayName) {
                onResolve(.approval(.decline))
            }
            .buttonStyle(.bordered)

            Button(CodexApprovalChoice.cancel.displayName, role: .destructive) {
                onResolve(.approval(.cancel))
            }
            .buttonStyle(.borderless)

            Spacer(minLength: 0)

            Button(CodexApprovalChoice.acceptForSession.displayName) {
                onResolve(.approval(.acceptForSession))
            }
            .buttonStyle(.bordered)

            Button(CodexApprovalChoice.accept.displayName) {
                onResolve(.approval(.accept))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func submitUserInput() {
        guard let answers = buildAnswers() else { return }
        onResolve(.userInput(answers))
    }

    private func buildAnswers() -> [String: [String]]? {
        guard case .userInput(let input) = request.kind else {
            return nil
        }

        var answers: [String: [String]] = [:]
        for question in input.questions {
            let freeText = textAnswers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let selected = selectedOptions[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let value: String
            if !freeText.isEmpty {
                value = freeText
            } else if !selected.isEmpty {
                value = selected
            } else {
                validationMessage = "Please answer every required Codex question before continuing."
                return nil
            }

            answers[question.id] = [value]
        }

        validationMessage = nil
        return answers
    }

    private func bindingForTextAnswer(questionID: String) -> Binding<String> {
        Binding(
            get: { textAnswers[questionID] ?? "" },
            set: { textAnswers[questionID] = $0 }
        )
    }

    private func bindingForSelectedOption(questionID: String) -> Binding<String> {
        Binding(
            get: { selectedOptions[questionID] ?? "" },
            set: { selectedOptions[questionID] = $0 }
        )
    }

    private func codexMetaPill(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
        }
        .padding(.horizontal, JinSpacing.small)
        .padding(.vertical, 4)
        .jinSurface(.subtle, cornerRadius: JinRadius.small)
    }

    private func codexCodeCard(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.small) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(JinSpacing.small)
                .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
        }
        .padding(JinSpacing.large)
        .jinSurface(.raised, cornerRadius: JinRadius.large)
    }
}
