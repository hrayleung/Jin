actor AgentApprovalSessionStore {
    private var approvedKeys: Set<String> = []

    func isApproved(key: String) -> Bool {
        approvedKeys.contains(key)
    }

    func approve(key: String) {
        approvedKeys.insert(key)
    }
}
