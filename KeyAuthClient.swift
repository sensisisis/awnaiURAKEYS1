import Foundation

public enum SensiAuraKeysError: LocalizedError, Sendable {
    case invalidConfiguration
    case network
    case server(String)
    case notInitialized
    case invalidLicense
    case expiredLicense

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "La configuración de la aplicación no es válida."
        case .network: return "No se pudo conectar con el servicio de licencias."
        case .server(let message): return message
        case .notInitialized: return "El cliente de licencias no está inicializado."
        case .invalidLicense: return "La licencia no es válida."
        case .expiredLicense: return "La licencia ha expirado."
        }
    }
}

public struct SensiAuraLicense: Sendable, Codable {
    public let key: String
    public let expiry: Date?
    public let subscriptionName: String?

    public var isExpired: Bool {
        guard let expiry else { return false }
        return expiry <= Date()
    }
}

public actor SensiAuraKeys {
    public struct Configuration: Sendable {
        public let applicationName: String
        public let ownerID: String
        public let version: String
        public let apiURL: URL

        public init(
            applicationName: String = "Dylanbrandonsmith123's Application",
            ownerID: String = "MQqz402Fyv",
            version: String = "1.0",
            apiURL: URL = URL(string: "https://keyauth.win/api/1.3/")!
        ) {
            self.applicationName = applicationName
            self.ownerID = ownerID
            self.version = version
            self.apiURL = apiURL
        }
    }

    private let configuration: Configuration
    private let urlSession: URLSession
    private var sessionID: String?
    private var currentLicense: SensiAuraLicense?

    public init(configuration: Configuration = .init(), urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func initialize() async throws {
        guard !configuration.applicationName.isEmpty,
              configuration.ownerID.count == 10,
              !configuration.version.isEmpty else {
            throw SensiAuraKeysError.invalidConfiguration
        }

        let response = try await request([
            "type": "init",
            "ver": configuration.version,
            "name": configuration.applicationName,
            "ownerid": configuration.ownerID
        ])

        guard response.success, let sessionID = response.sessionID, !sessionID.isEmpty else {
            throw SensiAuraKeysError.server(response.message ?? "No se pudo inicializar el servicio.")
        }
        self.sessionID = sessionID
    }

    @discardableResult
    public func login(withLicense key: String, hwid: String? = nil) async throws -> SensiAuraLicense {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { throw SensiAuraKeysError.invalidLicense }
        guard let sessionID else { throw SensiAuraKeysError.notInitialized }

        let response = try await request([
            "type": "license",
            "key": cleanKey,
            "sessionid": sessionID,
            "name": configuration.applicationName,
            "ownerid": configuration.ownerID,
            "hwid": hwid ?? Self.defaultHWID()
        ])

        guard response.success else {
            let message = (response.message ?? "").lowercased()
            if message.contains("expired") { throw SensiAuraKeysError.expiredLicense }
            throw SensiAuraKeysError.server(response.message ?? "La licencia no es válida.")
        }

        let subscription = response.info?.subscriptions?.first
        let expiry = subscription?.expiry.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) }
        let license = SensiAuraLicense(key: cleanKey, expiry: expiry, subscriptionName: subscription?.subscription)
        if license.isExpired { throw SensiAuraKeysError.expiredLicense }
        currentLicense = license
        return license
    }

    public func isLicenseValid() -> Bool {
        guard let currentLicense else { return false }
        return !currentLicense.isExpired
    }

    public func expirationDate() -> Date? { currentLicense?.expiry }

    public func activeLicense() -> SensiAuraLicense? { currentLicense }

    public func logout() {
        sessionID = nil
        currentLicense = nil
    }

    private func request(_ parameters: [String: String]) async throws -> APIResponse {
        var components = URLComponents(url: configuration.apiURL, resolvingAgainstBaseURL: false)
        components?.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw SensiAuraKeysError.network }

        do {
            let (data, response) = try await urlSession.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw SensiAuraKeysError.network
            }
            do { return try JSONDecoder().decode(APIResponse.self, from: data) }
            catch { throw SensiAuraKeysError.server("Respuesta inválida del servicio de licencias.") }
        } catch let error as SensiAuraKeysError { throw error }
        catch { throw SensiAuraKeysError.network }
    }

    private static func defaultHWID() -> String {
        let key = "SensiAuraKeys.hwid"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty { return saved }
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

private struct APIResponse: Decodable {
    let success: Bool
    let message: String?
    let sessionID: String?
    let info: LicenseInfo?

    enum CodingKeys: String, CodingKey {
        case success, message, info
        case sessionID = "sessionid"
    }
}

private struct LicenseInfo: Decodable {
    let subscriptions: [Subscription]?
}

private struct Subscription: Decodable {
    let subscription: String?
    let expiry: Int?
}