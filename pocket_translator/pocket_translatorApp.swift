import SwiftUI
import Foundation
import Security

// MARK: - Translation Service Protocol
protocol TranslationService {
    var name: String { get }
    func translate(_ text: String, from: String, to: String) async throws -> String
}

// MARK: - OpenAI Models
private struct OpenAIRequest: Codable {
    let model: String
    let messages: [Message]
    
    struct Message: Codable {
        let role: String
        let content: String
    }
}

private struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String
        let role: String
    }
}

// MARK: - OpenAI Translation Service
class OpenAITranslationService: TranslationService {
    let name = "OpenAI"
    
    func translate(_ text: String, from: String, to: String) async throws -> String {
        guard let apiKey = try? KeychainManager.shared.getApiKey(for: "OpenAI"),
              !apiKey.isEmpty else {
            throw TranslationError.configuration("Please configure OpenAI API key in settings")
        }
        
        // 创建 URL 请求
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 构建请求体，使用字典而不是 Codable
        let messages: [[String: String]] = [
            ["role": "user", "content": "Translate the following text from \(from) to \(to): \(text)"]
        ]
        
        let requestDict: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages
        ]
        
        // 编码请求
        request.httpBody = try JSONSerialization.data(withJSONObject: requestDict)
        
        // 创建 URLSession 配置
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        
        let session = URLSession(configuration: config)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // 打印响应数据以便调试
            if let jsonString = String(data: data, encoding: .utf8) {
                print("OpenAI Response: \(jsonString)")
            }
            
            // 检查 HTTP 响应状态
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.network("Invalid response from server")
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                // 尝试解析错误信息
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw TranslationError.api("OpenAI Error: \(message)")
                }
                throw TranslationError.http("Server error: \(httpResponse.statusCode)")
            }
            
            // 使用 JSONSerialization 解析响应
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw TranslationError.noResult("Failed to parse response")
            }
            
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch let error as TranslationError {
            throw error
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    throw TranslationError.network("Request timed out")
                case .notConnectedToInternet:
                    throw TranslationError.network("No internet connection")
                default:
                    throw TranslationError.network("Network error: \(urlError.localizedDescription)")
                }
            }
            throw TranslationError.unknown("Unknown error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Secure Coding Models
struct TranslationRequest: Codable, Hashable {
    let q: String
    let source: String
    let target: String
    let format: String = "text"
}

struct TranslationResponse: Codable, Hashable {
    struct TranslationData: Codable, Hashable {
        struct Translation: Codable, Hashable {
            let translatedText: String
        }
        let translations: [Translation]
    }
    let data: TranslationData
}

struct ErrorResponse: Codable, Hashable {
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
            throw TranslationError.configuration("Please configure Google API key in settings")
        }
        
        // 构建请求 URL
        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")
        components?.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        guard let url = components?.url else {
            throw TranslationError.invalidRequest("Invalid URL configuration")
        }
        
        // 准备请求体
        let requestData = TranslationRequest(
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
        
        // 使用 JSONEncoder 进行编码
        let encoder = JSONEncoder()
        request.httpBody = try? encoder.encode(requestData)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.network("Invalid response from server")
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                // 使用 JSONDecoder 解码错误响应
                let decoder = JSONDecoder()
                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                    throw TranslationError.api(errorResponse.error.message)
                }
                throw TranslationError.http("Server error: \(httpResponse.statusCode)")
            }
            
            // 使用 JSONDecoder 解码成功响应
            let decoder = JSONDecoder()
            let translationResponse = try decoder.decode(TranslationResponse.self, from: data)
            
            guard let translation = translationResponse.data.translations.first?.translatedText else {
                throw TranslationError.noResult("No translation result")
            }
            
            return translation
            
        } catch let error as TranslationError {
            throw error
        } catch let error as DecodingError {
            throw TranslationError.unknown("Decoding error: \(error.localizedDescription)")
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    throw TranslationError.network("Request timed out")
                case .notConnectedToInternet:
                    throw TranslationError.network("No internet connection")
                default:
                    throw TranslationError.network("Network error: \(urlError.localizedDescription)")
                }
            }
            throw TranslationError.unknown("Unknown error: \(error.localizedDescription)")
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

// MARK: - DeepL Translation Service (Mock)
class DeepLTranslationService: TranslationService {
    let name = "DeepL"
    
    private struct TranslationRequest: Codable {
        let text: [String]
        let target_lang: String
        let source_lang: String
    }
    
    private struct TranslationResponse: Codable {
        let translations: [Translation]
        
        struct Translation: Codable {
            let text: String
            let detected_source_language: String
        }
    }
    
    func translate(_ text: String, from: String, to: String) async throws -> String {
        guard let apiKey = try? KeychainManager.shared.getApiKey(for: "DeepL"),
              !apiKey.isEmpty else {
            throw TranslationError.configuration("Please configure DeepL API key in settings")
        }
        
        // DeepL API URL (使用免费版 API 端点，如果是 Pro 版本需要改为 api.deepl.com)
        let url = URL(string: "https://api-free.deepl.com/v2/translate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // 准备请求体
        let requestBody = TranslationRequest(
            text: [text],
            target_lang: convertLanguageCode(to),
            source_lang: convertLanguageCode(from)
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)
        
        // 创建 URLSession 配置
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        
        let session = URLSession(configuration: config)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            // 检查 HTTP 响应状态
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.network("Unable to connect to DeepL")
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                switch httpResponse.statusCode {
                case 401:
                    throw TranslationError.api("Invalid DeepL API key")
                case 429:
                    throw TranslationError.api("Too many requests. Please try again later")
                case 456:
                    throw TranslationError.api("DeepL quota exceeded. Please check your account")
                default:
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let message = errorJson["message"] as? String {
                        throw TranslationError.api("DeepL Error: \(message)")
                    }
                    throw TranslationError.http("DeepL server error: \(httpResponse.statusCode)")
                }
            }
            
            // 解析响应
            let decoder = JSONDecoder()
            let translationResponse = try decoder.decode(TranslationResponse.self, from: data)
            
            guard let translation = translationResponse.translations.first?.text else {
                throw TranslationError.noResult("No translation result")
            }
            
            return translation
            
        } catch let error as TranslationError {
            throw error
        } catch let error as DecodingError {
            throw TranslationError.unknown("Failed to process response: \(error.localizedDescription)")
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    throw TranslationError.network("Request timed out")
                case .notConnectedToInternet:
                    throw TranslationError.network("No internet connection")
                default:
                    throw TranslationError.network("Network error: \(urlError.localizedDescription)")
                }
            }
            throw TranslationError.unknown("Translation failed: \(error.localizedDescription)")
        }
    }
    
    private func convertLanguageCode(_ language: String) -> String {
        switch language.lowercased() {
        case "chinese":
            return "ZH" // 中文
        case "english":
            return "EN" // 英语
        case "german":
            return "DE" // 德语
        case "french":
            return "FR" // 法语
        case "italian":
            return "IT" // 意大利语
        case "japanese":
            return "JA" // 日语
        case "spanish":
            return "ES" // 西班牙语
        case "dutch":
            return "NL" // 荷兰语
        case "polish":
            return "PL" // 波兰语
        case "portuguese":
            return "PT" // 葡萄牙语
        case "russian":
            return "RU" // 俄语
        default:
            return language.uppercased()
        }
    }
}

// MARK: - Models

struct TranslationResult: Identifiable {
    let id = UUID()
    let serviceName: String
    let text: String
    var isError: Bool = false
}

// MARK: - Main App
@main
struct TranslatorApp: App {
    var body: some Scene {
        MenuBarExtra("Translator", systemImage: "character.bubble") {
            TranslatorView()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Main View
struct TranslatorView: View {
    @State private var inputText = ""
   @State private var translationResults: [TranslationResult] = []
   @State private var sourceLanguage = "English"
   @State private var targetLanguage = "Chinese"
   @State private var isTranslating = false
   @State private var showingSettings = false
    @FocusState private var isInputFocused: Bool
    
    private let languages = ["English", "Chinese"]
    private let translationServices: [TranslationService] = [
        DeepLTranslationService(),
        QwenTranslationService(),
        OpenAITranslationService(),
        GoogleTranslationService()
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with Settings Button
            HStack {
                Text("Translator")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: {
                    showingSettings.toggle()
                }) {
                    Label("Settings", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingSettings, arrowEdge: .top) {
                    SettingsView()
                }
            }
            .padding(.bottom, 8)
            
            // Language selection
            HStack {
                Picker("From", selection: $sourceLanguage) {
                    ForEach(languages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                
                Button(action: {
                    let temp = sourceLanguage
                    sourceLanguage = targetLanguage
                    targetLanguage = temp
                }) {
                    Image(systemName: "arrow.right.arrow.left")
                }
                
                Picker("To", selection: $targetLanguage) {
                    ForEach(languages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
            }
            
            // Input text field
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty && !isInputFocused {
                    Text("请输入内容...") // 占位符文本
                        .foregroundColor(.gray)
                        .padding(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 0))
                }
                
                TextEditor(text: $inputText)
                    .padding(8)
                    .font(.body)
                    .frame(height: 80)
                    .border(Color.gray.opacity(0.2))
                    .focused($isInputFocused) // 绑定焦点状态
            }
            
            // Translate button
            Button(action: {
                Task {
                    await translateText()
                }
            }) {
                if isTranslating {
                    ProgressView()
                } else {
                    Text("Translate")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.isEmpty || isTranslating)
            
            // Results
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(translationResults) { result in
                        TranslationResultView(result: result)
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func translateText() async {
        isTranslating = true
        translationResults = Array(repeating: TranslationResult(serviceName: "", text: ""), count: translationServices.count)
        
        await withTaskGroup(of: (Int, TranslationResult).self) { group in
            for (index, service) in translationServices.enumerated() {
                group.addTask {
                    do {
                        let result = try await service.translate(
                            inputText,
                            from: sourceLanguage.lowercased(),
                            to: targetLanguage.lowercased()
                        )
                        let translationResult = TranslationResult(serviceName: service.name, text: result)
                        return (index, translationResult)
                    } catch {
                        let translationResult = TranslationResult(
                            serviceName: service.name,
                            text: error.localizedDescription,
                            isError: true
                        )
                        return (index, translationResult)
                    }
                }
            }
            
            for await (index, result) in group {
                translationResults[index] = result
            }
        }
        
        // 移除未完成或空的结果
        translationResults = translationResults.filter { !$0.serviceName.isEmpty }
        
        isTranslating = false
    }
}


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
}

// MARK: - API Configuration View Model
@MainActor
class APIConfigurationViewModel: ObservableObject {
    @Published var openAIKey: String = ""
    @Published var googleKey: String = ""
    @Published var deepLKey: String = ""
    @Published var qwenKey: String = ""  // 添加通义千问的 key
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var shouldDismiss = false
    @Published var isSaving = false
    
    init() {
        loadKeys()
    }
    
    private func loadKeys() {
        do {
            openAIKey = try KeychainManager.shared.getApiKey(for: "OpenAI")
        } catch {}
        
        do {
            googleKey = try KeychainManager.shared.getApiKey(for: "Google")
        } catch {}
        
        do {
            deepLKey = try KeychainManager.shared.getApiKey(for: "DeepL")
        } catch {}
        
        do {
            qwenKey = try KeychainManager.shared.getApiKey(for: "Qwen")
        } catch {}
    }
    
    func saveKeys() async {
        isSaving = true
        do {
            try KeychainManager.shared.saveApiKey(openAIKey, for: "OpenAI")
            try KeychainManager.shared.saveApiKey(googleKey, for: "Google")
            try KeychainManager.shared.saveApiKey(deepLKey, for: "DeepL")
            try KeychainManager.shared.saveApiKey(qwenKey, for: "Qwen")
            
            alertMessage = "Settings saved successfully"
            showAlert = true
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showAlert = false
            shouldDismiss = true
            
        } catch {
            alertMessage = "Failed to save settings"
            showAlert = true
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showAlert = false
        }
        isSaving = false
    }
}
// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var viewModel = APIConfigurationViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                apiKeyField(
                    title: "OpenAI API Key",
                    placeholder: "sk-...",
                    text: $viewModel.openAIKey,
                    info: "From platform.openai.com"
                )
                
                apiKeyField(
                    title: "Google Translate API Key",
                    placeholder: "Enter API Key",
                    text: $viewModel.googleKey,
                    info: "From Google Cloud Console"
                )
                
                apiKeyField(
                    title: "DeepL API Key",
                    placeholder: "Enter API Key",
                    text: $viewModel.deepLKey,
                    info: "From deepl.com/pro-api"
                )
                
                apiKeyField(
                    title: "Qwen API Key",
                    placeholder: "Enter Qwen API Key",
                    text: $viewModel.qwenKey,
                    info: "From DashScope Console"
                )
            }
            .padding()
            .background(Color(.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Button(action: {
                Task {
                    await viewModel.saveKeys()
                }
            }) {
                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text("Save Changes")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(width: 200)
            .disabled(viewModel.isSaving)
        }
        .padding()
        .frame(width: 400)
        .overlay {
            if viewModel.showAlert {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Group {
                                if viewModel.alertMessage.contains("successfully") {
                                    Image(systemName: "checkmark.circle.fill")
                                        .symbolRenderingMode(.multicolor)
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .symbolRenderingMode(.multicolor)
                                        .foregroundStyle(.red)
                                }
                            }
                            .font(.system(size: 40))
                            
                            Text(viewModel.alertMessage)
                                .multilineTextAlignment(.center)
                                .font(.headline)
                        }
                        .padding()
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.thinMaterial)
                                .shadow(radius: 5)
                        }
                        Spacer()
                    }
                    Spacer()
                }
                .animation(.easeInOut, value: viewModel.showAlert)
            }
        }
    }
    
    // API Key 输入字段组件
    private func apiKeyField(title: String, placeholder: String, text: Binding<String>, info: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text(info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .help(info)
        }
    }
}

struct TranslationResultView: View {
    let result: TranslationResult
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.serviceName)
                    .font(.headline)
                    .foregroundColor(result.isError ? .red : .primary)
                
                Spacer()
                
                Button {
                    copyToClipboard(result.text)
                    withAnimation {
                        isCopied = true
                    }
                    // 2秒后重置复制状态
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            isCopied = false
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundColor(isCopied ? .green : .primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy translation")
            }
            
            Text(result.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.textBackgroundColor))
                }
                .contextMenu {
                    Button {
                        copyToClipboard(result.text)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
        .padding(.horizontal, 4)
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

class QwenTranslationService: TranslationService {
    var name: String = "Qwen"
    struct ChatCompletionRequest: Codable {
        let model: String
        let messages: [Message]
        
        struct Message: Codable {
            let role: String
            let content: String
        }
    }

    struct ChatCompletionResponse: Codable {
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [Choice]
        
        struct Choice: Codable {
            let index: Int
            let message: Message
            let finish_reason: String
            
            struct Message: Codable {
                let role: String
                let content: String
            }
        }
    }

    func translate(_ text: String, from: String, to: String) async throws -> String {
        guard let apiKey = try? KeychainManager.shared.getApiKey(for: "Qwen"),
              !apiKey.isEmpty else {
            throw TranslationError.configuration("请在设置中配置Qwen API密钥")
        }
        
        let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 构建messages
        let messages = [
            ChatCompletionRequest.Message(role: "system", content: "You are a professional translator."),
            ChatCompletionRequest.Message(role: "user", content: "Please translate the following text from \(from) to \(to): \(text)")
        ]
        
        let requestBody = ChatCompletionRequest(model: "qwen-plus", messages: messages)
        
        // 编码请求体
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        request.httpBody = try encoder.encode(requestBody)
        
        // 打印请求体
        if let httpBody = request.httpBody, let jsonString = String(data: httpBody, encoding: .utf8) {
            print("请求体:\n\(jsonString)")
        }
        
        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 打印响应
        if let jsonString = String(data: data, encoding: .utf8) {
            print("响应:\n\(jsonString)")
        }
        
        // 检查HTTP响应
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.network("无法连接到Qwen API")
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw TranslationError.api("Qwen API错误: \(message)")
            }
            throw TranslationError.http("Qwen服务器错误: \(httpResponse.statusCode)")
        }
        
        // 解析响应
        let decoder = JSONDecoder()
        let chatResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
        
        if let content = chatResponse.choices.first?.message.content {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw TranslationError.noResult("无法获取翻译结果")
        }
    }
}
