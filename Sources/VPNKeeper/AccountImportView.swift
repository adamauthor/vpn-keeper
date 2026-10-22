import SwiftUI
import VPNCore

struct AccountImportView: View {
    let preview: QRImportResult
    let confirm: (Int) -> Void
    let cancel: () -> Void
    @State private var selectedID: Int?

    private var selectionValid: Bool {
        guard let selectedID else { return false }
        return (try? preview.selectedToken(id: selectedID)) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Выбери аккаунт VPN", systemImage: "qrcode").font(.title2.bold())
            Text("Из экспорта будет импортирован только выбранный аккаунт. Остальные секреты не сохраняются.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(Array(preview.notices.enumerated()), id: \.offset) { _, notice in
                Text(notice).font(.callout).foregroundStyle(.orange)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(preview.accounts) { account in
                        Button {
                            selectedID = account.id
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selectedID == account.id ? "largecircle.fill.circle" : "circle")
                                    .font(.title3).foregroundStyle(account.token == nil ? Color.secondary : Color.teal)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name).font(.headline)
                                    if !account.issuer.isEmpty {
                                        Text(account.issuer).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    if let token = account.token {
                                        Text(
                                            "\(token.algorithm.rawValue) · \(token.digits) цифр · \(token.period) сек."
                                        )
                                        .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text(account.unavailableReason ?? "Не поддерживается").font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(
                                selectedID == account.id ? Color.teal.opacity(0.10) : Color.secondary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(account.token == nil)
                        .accessibilityLabel(account.name + (account.issuer.isEmpty ? "" : ", " + account.issuer))
                        .accessibilityIdentifier("import-account-\(account.id)")
                    }
                }
            }
            Divider()
            HStack {
                Button("Отмена", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Импортировать выбранный") {
                    if let selectedID { confirm(selectedID) }
                }.buttonStyle(.borderedProminent).disabled(!selectionValid).keyboardShortcut(.defaultAction)
            }
        }.padding(24).tint(.teal).frame(width: 560, height: 500)
    }
}
