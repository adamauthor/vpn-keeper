import Foundation
import ServiceManagement
import VPNCore

/// Local automation interface. It never returns passwords, TOTP seeds, or live codes.
enum CommandInterface {
    @MainActor static func run(_ arguments: [String]) throws {
        let defaults = UserDefaults.standard
        guard let command = arguments.first else { throw KeeperError("Не указана команда.") }
        switch command {
        case "--runtime-status":
            guard arguments.count == 1 else { throw KeeperError("Неизвестные параметры команды.") }
            guard let data = defaults.data(forKey: "runtimeStatus"),
                let runtime = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                try output(["available": false])
                return
            }
            try output(runtime)
        case "--inspect-qr":
            guard arguments.count == 2 else { throw KeeperError("Укажите путь к изображению QR.") }
            let result = try QRImport.readAccounts(URL(fileURLWithPath: arguments[1]))
            let vpn = result.accounts.filter { account in
                let name = (account.name + " " + account.issuer).lowercased()
                return account.token != nil && ["vpn", "cisco", "anyconnect"].contains(where: name.contains)
            }
            var response: [String: Any] = [
                "accounts": result.accounts.count,
                "supportedAccounts": result.accounts.filter { $0.token != nil }.count,
                "vpnCandidates": vpn.map { ["id": $0.id, "name": $0.name, "issuer": $0.issuer] as [String: Any] },
            ]
            if result.accounts.count == 1, result.accounts[0].token != nil {
                response["singleAccountId"] = result.accounts[0].id
                response["singleAccountName"] = result.accounts[0].name
                response["singleAccountIssuer"] = result.accounts[0].issuer
            }
            try output(response)
        case "--import-qr":
            guard arguments.count == 4, arguments[2] == "--account", let id = Int(arguments[3]) else {
                throw KeeperError("Укажите путь к QR и --account с номером выбранного аккаунта.")
            }
            let result = try QRImport.readAccounts(URL(fileURLWithPath: arguments[1]))
            let token = try result.selectedToken(id: id)
            let previous = try KeychainStore.load(interactive: false)
            try KeychainStore.save(VaultEntry(password: previous?.password ?? "", token: token))
            defaults.set(true, forKey: "hasPendingImportedToken")
            defaults.synchronize()
            try output(["imported": true, "passwordAlreadySaved": !(previous?.password.isEmpty ?? true)])
        case "--setup-status":
            guard arguments.count == 1 else { throw KeeperError("Неизвестные параметры команды.") }
            let entry = try KeychainStore.load(interactive: false)
            let profile = defaults.data(forKey: "profile").flatMap {
                try? JSONDecoder().decode(VPNProfile.self, from: $0)
            }
            var missing: [String] = []
            if profile?.server.isEmpty ?? true { missing.append("server") }
            if profile?.group.isEmpty ?? true { missing.append("group") }
            if profile?.username.isEmpty ?? true { missing.append("username") }
            if entry?.password.isEmpty ?? true { missing.append("password") }
            if entry?.token == nil { missing.append("qr") }
            try output([
                "missing": missing, "autoReconnect": defaults.bool(forKey: "keepConnected"),
                "automaticBlocked": defaults.bool(forKey: "automaticBlocked"),
                "launchAtLogin": SMAppService.mainApp.status == .enabled,
                "loginNeedsApproval": SMAppService.mainApp.status == .requiresApproval,
            ])
        case "--set-server":
            guard arguments.count == 2 else { throw KeeperError("Укажите адрес сервера VPN.") }
            var profile =
                defaults.data(forKey: "profile").flatMap { try? JSONDecoder().decode(VPNProfile.self, from: $0) }
                ?? VPNProfile()
            var check = profile
            check.server = arguments[1]
            if check.username.isEmpty { check.username = "validation" }
            let validated = try check.validated()
            guard profile.server.isEmpty || profile.server == validated.server else {
                throw KeeperError("Другой сервер уже сохранён. Измените его в окне настроек.")
            }
            profile.server = validated.server
            defaults.set(try JSONEncoder().encode(profile), forKey: "profile")
            defaults.synchronize()
            try output(["serverSaved": true])
        case "--set-identity":
            guard arguments.count == 5, arguments[1] == "--username", arguments[3] == "--group",
                let data = defaults.data(forKey: "profile"),
                var profile = try? JSONDecoder().decode(VPNProfile.self, from: data)
            else {
                throw KeeperError("Сначала укажите сервер, затем --username и --group.")
            }
            profile.username = arguments[2]
            profile.group = arguments[4]
            profile = try profile.validated()
            defaults.set(try JSONEncoder().encode(profile), forKey: "profile")
            defaults.synchronize()
            try output(["identitySaved": true])
        case "--enable-login":
            guard arguments.count == 1 else { throw KeeperError("Неизвестные параметры команды.") }
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
            try SMAppService.mainApp.register()
            try output([
                "launchAtLogin": SMAppService.mainApp.status == .enabled,
                "loginNeedsApproval": SMAppService.mainApp.status == .requiresApproval,
            ])
        default: throw KeeperError("Неизвестная команда локального интерфейса.")
        }
    }

    static func output(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
