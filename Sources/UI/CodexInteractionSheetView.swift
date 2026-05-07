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
            _selectedOptions = State(initialValue: CodexInteractionSheetSupport.initialSelectedOptions(for: input))
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
                    CodexInteractionHeaderCardView(
                        subtitle: request.subtitle,
                        description: CodexInteractionSheetSupport.requestDescription(for: request.kind),
                        threadID: request.threadID,
                        turnID: request.turnID
                    )

                    switch request.kind {
                    case .commandApproval(let approval):
                        CodexCommandApprovalContentView(approval: approval) { choice in
                            onResolve(.approval(choice))
                        }
                    case .fileChangeApproval(let approval):
                        CodexFileChangeApprovalContentView(approval: approval) { choice in
                            onResolve(.approval(choice))
                        }
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
                        onResolve(CodexInteractionSheetSupport.cancelResponse(for: request.kind))
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

    @ViewBuilder
    private func userInputContent(_ input: CodexUserInputRequest) -> some View {
        VStack(alignment: .leading, spacing: JinSpacing.large) {
            ForEach(input.questions) { question in
                CodexInteractionSectionCardView {
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
                }
            }
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

        guard let answers = CodexInteractionSheetSupport.answers(
            for: input,
            textAnswers: textAnswers,
            selectedOptions: selectedOptions
        ) else {
            validationMessage = CodexInteractionSheetSupport.requiredAnswerValidationMessage
            return nil
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
}
