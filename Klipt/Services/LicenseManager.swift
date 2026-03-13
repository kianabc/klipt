import Foundation
import IOKit
import Security

@Observable
class LicenseManager {
    static let shared = LicenseManager()

    var isLicensed: Bool = false
    var licenseKey: String = ""
    var validationError: String?
    var isValidating: Bool = false

    private let keychainService = "app.klipt.Klipt"
    private let keychainAccount = "licenseKey"

    init() {
        // Migrate from UserDefaults to Keychain (one-time)
        if let oldKey = UserDefaults.standard.string(forKey: "klipt_licenseKey"), !oldKey.isEmpty {
            saveKeyToKeychain(oldKey)
            UserDefaults.standard.removeObject(forKey: "klipt_licenseKey")
            UserDefaults.standard.removeObject(forKey: "klipt_isLicensed")
        }

        self.licenseKey = loadKeyFromKeychain() ?? ""
        self.isLicensed = !licenseKey.isEmpty
        // Re-validate on launch if we have a stored key
        if isLicensed {
            revalidate()
        }
    }

    private func revalidate() {
        guard !licenseKey.isEmpty else { return }
        let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: String] = ["license_key": licenseKey]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // On network error, keep current state (grace period)
                guard error == nil, let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                let valid = json["valid"] as? Bool ?? false
                let status = (json["license_key"] as? [String: Any])?["status"] as? String
                if !valid || (status != "active" && status != "inactive") {
                    self.isLicensed = false
                    self.deleteKeyFromKeychain()
                    self.licenseKey = ""
                }
            }
        }.resume()
    }

    func validate(key: String) {
        isValidating = true
        validationError = nil

        let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = ["license_key": key]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isValidating = false

                if let error = error {
                    self.validationError = "Network error: \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.validationError = "Invalid response"
                    return
                }

                let valid = json["valid"] as? Bool ?? false
                let licenseKeyData = json["license_key"] as? [String: Any]
                let status = licenseKeyData?["status"] as? String

                if valid && (status == "active" || status == "inactive") {
                    self.isLicensed = true
                    self.licenseKey = key
                    self.validationError = nil
                    self.saveKeyToKeychain(key)

                    // Activate the key if it's inactive
                    if status == "inactive" {
                        self.activate(key: key)
                    }
                } else {
                    let errorMsg = json["error"] as? String ?? "Invalid license key"
                    self.validationError = errorMsg
                }
            }
        }.resume()
    }

    private func activate(key: String) {
        let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Use a non-identifying instance name
        let hardwareUUID = IORegistryEntryCreateCFProperty(
            IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")),
            "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String ?? UUID().uuidString
        let instanceHash = String(hardwareUUID.hashValue, radix: 16, uppercase: false)
        let body: [String: String] = [
            "license_key": key,
            "instance_name": "Mac-\(instanceHash.prefix(8))"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    func removeLicense() {
        isLicensed = false
        licenseKey = ""
        validationError = nil
        deleteKeyFromKeychain()
    }

    // MARK: - Keychain helpers

    private func saveKeyToKeychain(_ key: String) {
        deleteKeyFromKeychain()
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
