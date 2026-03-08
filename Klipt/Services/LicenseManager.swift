import Foundation

@Observable
class LicenseManager {
    static let shared = LicenseManager()

    var isLicensed: Bool = false
    var licenseKey: String = ""
    var validationError: String?
    var isValidating: Bool = false

    private let licenseKeyKey = "klipt_licenseKey"
    private let isLicensedKey = "klipt_isLicensed"

    init() {
        let defaults = UserDefaults.standard
        self.isLicensed = defaults.bool(forKey: isLicensedKey)
        self.licenseKey = defaults.string(forKey: licenseKeyKey) ?? ""
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
                    UserDefaults.standard.set(true, forKey: self.isLicensedKey)
                    UserDefaults.standard.set(key, forKey: self.licenseKeyKey)

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

        let body: [String: String] = [
            "license_key": key,
            "instance_name": Host.current().localizedName ?? "Mac"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    func removeLicense() {
        isLicensed = false
        licenseKey = ""
        validationError = nil
        UserDefaults.standard.removeObject(forKey: isLicensedKey)
        UserDefaults.standard.removeObject(forKey: licenseKeyKey)
    }
}
