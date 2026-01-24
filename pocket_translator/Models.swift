import Foundation
import Security

// MARK: - Provider Configuration Model
struct ProviderConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String        // 显示名称
    var baseURL: String     // API 端点
    var modelName: String   // 模型名称
    var isEnabled: Bool = true

    static func == (lhs: ProviderConfig, rhs: ProviderConfig) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Provider Manager
class ProviderManager: ObservableObject {
    static let shared = ProviderManager()

    @Published var providers: [ProviderConfig] = []

    private let providersKey = "translationProviders"
    private let hasLoadedDefaultsKey = "hasLoadedDefaultProviders"

    private init() {
        loadProviders()
        loadDefaultProvidersIfNeeded()
    }

    // MARK: - Persistence

    func loadProviders() {
        guard let data = UserDefaults.standard.data(forKey: providersKey),
              let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: data) else {
            return
        }
        providers = decoded
    }

    func saveProviders() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        UserDefaults.standard.set(data, forKey: providersKey)
    }

    // MARK: - Default Providers

    func loadDefaultProvidersIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasLoadedDefaultsKey) else { return }

        let defaults: [ProviderConfig] = [
            ProviderConfig(
                name: "DeepSeek",
                baseURL: "https://api.deepseek.com/v1/chat/completions",
                modelName: "deepseek-chat"
            )
        ]

        providers = defaults
        saveProviders()
        UserDefaults.standard.set(true, forKey: hasLoadedDefaultsKey)
    }

    // MARK: - CRUD Operations

    func addProvider(_ config: ProviderConfig) {
        providers.append(config)
        saveProviders()
    }

    func updateProvider(_ config: ProviderConfig) {
        if let index = providers.firstIndex(where: { $0.id == config.id }) {
            providers[index] = config
            saveProviders()
        }
    }

    func deleteProvider(id: UUID) {
        providers.removeAll { $0.id == id }
        // 同时删除 Keychain 中的 API Key
        try? KeychainManager.shared.deleteApiKey(for: id.uuidString)
        saveProviders()
    }

    // MARK: - API Key Management

    func getApiKey(for providerId: UUID) -> String? {
        try? KeychainManager.shared.getApiKey(for: providerId.uuidString)
    }

    func saveApiKey(_ key: String, for providerId: UUID) throws {
        try KeychainManager.shared.saveApiKey(key, for: providerId.uuidString)
    }
}

// MARK: - Translation Service Protocol
protocol TranslationService {
    var name: String { get }
    func translate(_ text: String, from: String, to: String) async throws -> String
}

// MARK: - Input Type Detection
enum InputType {
    case word      // 单词
    case sentence  // 句子/段落
}

func detectInputType(_ text: String) -> InputType {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // 包含空格 = 多个单词/句子
    if trimmed.contains(" ") {
        return .sentence
    }

    // 判断是否主要是中文
    let chineseCount = trimmed.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count

    if chineseCount > 0 {
        // 中文：4个字以内视为单词
        if chineseCount <= 4 {
            return .word
        }
    } else {
        // 英文/其他：没有空格就是单词（不限长度）
        return .word
    }

    return .sentence
}

// MARK: - Configurable Translation Service
class ConfigurableTranslationService: TranslationService {
    let config: ProviderConfig

    var name: String { config.name }

    init(config: ProviderConfig) {
        self.config = config
    }

    func translate(_ text: String, from: String, to: String) async throws -> String {
        guard let apiKey = ProviderManager.shared.getApiKey(for: config.id),
              !apiKey.isEmpty else {
            throw TranslationError.configuration("请在设置中配置 \(config.name) 的 API Key")
        }

        guard let url = URL(string: config.baseURL) else {
            throw TranslationError.invalidRequest("无效的 API 地址")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 根据输入类型选择不同的 prompt
        let inputType = detectInputType(text)
        let systemPrompt: String
        let userPrompt: String

        switch inputType {
        case .word:
            // 单词模式：词典格式
            systemPrompt = "You are a concise technical dictionary, especially for software/programming terms."
            userPrompt = """
            Word: \(text)
            From \(from) to \(to).

            Format:
            1. [词性] 翻译 - 简短解释
            2. [词性] 翻译 - 简短解释

            Rules:
            - 词性用中文：名词、动词、形容词、副词、感叹词等
            - Max 2-3 meanings
            - No phonetics
            - Keep explanations very short
            - 如果是技术/软件术语，优先给出技术领域的含义
            """
        case .sentence:
            // 段落模式：直接翻译
            systemPrompt = "You are a professional translator specializing in software/technical content."
            userPrompt = """
            Translate from \(from) to \(to): \(text)

            Rules:
            - 技术专有名词保留英文，在括号内加中文解释
            - 例如：Transformer（转换器架构）、API（应用程序接口）
            - 常见缩写如 CPU、GPU、API 等可不翻译
            """
        }

        // 构建请求体 (OpenAI 兼容格式)
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let requestDict: [String: Any] = [
            "model": config.modelName,
            "messages": messages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestDict)

        // 创建 URLSession 配置
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.waitsForConnectivity = true

        let session = URLSession(configuration: sessionConfig)

        do {
            let (data, response) = try await session.data(for: request)

            // 打印响应以便调试
            if let jsonString = String(data: data, encoding: .utf8) {
                print("\(config.name) Response: \(jsonString)")
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.network("无法连接到服务器")
            }

            if !(200...299).contains(httpResponse.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw TranslationError.api("\(config.name) 错误: \(message)")
                }
                throw TranslationError.http("服务器错误: \(httpResponse.statusCode)")
            }

            // 解析响应 (OpenAI 兼容格式)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw TranslationError.noResult("无法解析响应")
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch let error as TranslationError {
            throw error
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    throw TranslationError.network("请求超时")
                case .notConnectedToInternet:
                    throw TranslationError.network("无网络连接")
                default:
                    throw TranslationError.network("网络错误: \(urlError.localizedDescription)")
                }
            }
            throw TranslationError.unknown("未知错误: \(error.localizedDescription)")
        }
    }
}

// MARK: - Google Translation Models
struct GoogleTranslationRequest: Codable, Hashable {
    let q: String
    let source: String
    let target: String
    let format: String = "text"
}

struct GoogleTranslationResponse: Codable, Hashable {
    struct TranslationData: Codable, Hashable {
        struct Translation: Codable, Hashable {
            let translatedText: String
        }
        let translations: [Translation]
    }
    let data: TranslationData
}

struct GoogleErrorResponse: Codable, Hashable {
    struct ErrorDetail: Codable, Hashable {
        let message: String
    }
    let error: ErrorDetail
}

// MARK: - Google Translation Service
class GoogleTranslationService: TranslationService {
    let name = "Google"

    func translate(_ text: String, from: String, to: String) async throws -> String {
        guard let apiKey = try? KeychainManager.shared.getApiKey(for: "Google"),
              !apiKey.isEmpty else {
            throw TranslationError.configuration("请在设置中配置 Google API Key")
        }

        // 构建请求 URL
        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
            throw TranslationError.invalidRequest("无效的 URL 配置")
        }

        // 准备请求体
        let requestData = GoogleTranslationRequest(
            q: text,
            source: convertLanguageCode(from),
            target: convertLanguageCode(to)
        )

        // 创建自定义的 URLSession 配置
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: config)

        // 准备请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let encoder = JSONEncoder()
        request.httpBody = try? encoder.encode(requestData)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.network("无法连接到服务器")
            }

            if !(200...299).contains(httpResponse.statusCode) {
                let decoder = JSONDecoder()
                if let errorResponse = try? decoder.decode(GoogleErrorResponse.self, from: data) {
                    throw TranslationError.api(errorResponse.error.message)
                }
                throw TranslationError.http("服务器错误: \(httpResponse.statusCode)")
            }

            let decoder = JSONDecoder()
            let translationResponse = try decoder.decode(GoogleTranslationResponse.self, from: data)

            guard let translation = translationResponse.data.translations.first?.translatedText else {
                throw TranslationError.noResult("无翻译结果")
            }

            return translation

        } catch let error as TranslationError {
            throw error
        } catch let error as DecodingError {
            throw TranslationError.unknown("解码错误: \(error.localizedDescription)")
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    throw TranslationError.network("请求超时")
                case .notConnectedToInternet:
                    throw TranslationError.network("无网络连接")
                default:
                    throw TranslationError.network("网络错误: \(urlError.localizedDescription)")
                }
            }
            throw TranslationError.unknown("未知错误: \(error.localizedDescription)")
        }
    }

    private func convertLanguageCode(_ language: String) -> String {
        switch language.lowercased() {
        case "chinese":
            return "zh-CN"
        case "english":
            return "en"
        default:
            return language.lowercased()
        }
    }
}

// MARK: - Translation Error
enum TranslationError: LocalizedError, Hashable {
    case configuration(String)
    case invalidRequest(String)
    case network(String)
    case http(String)
    case api(String)
    case noResult(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .configuration(let message),
             .invalidRequest(let message),
             .network(let message),
             .http(let message),
             .api(let message),
             .noResult(let message),
             .unknown(let message):
            return message
        }
    }

    static func == (lhs: TranslationError, rhs: TranslationError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(errorDescription)
    }
}

// MARK: - Translation Result
struct TranslationResult: Identifiable {
    let id = UUID()
    let serviceName: String
    let text: String
    let isError: Bool
}

// MARK: - Keychain Manager
class KeychainManager {
    static let shared = KeychainManager()

    private init() {}

    enum KeychainError: Error {
        case duplicateEntry
        case unknown(OSStatus)
        case notFound
    }

    func saveApiKey(_ key: String, for service: String) throws {
        guard let data = key.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // 如果已存在，则更新
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: service
            ]

            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unknown(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }

    func getApiKey(for service: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }

        return key
    }

    func deleteApiKey(for service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }
}
