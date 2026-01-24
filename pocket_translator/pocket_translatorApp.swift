import SwiftUI

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Optional: If you want to prevent the app from showing in Force Quit window
        if let window = NSApplication.shared.windows.first {
            window.level = .statusBar
        }
    }
}

// MARK: - Main App
@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Translator", systemImage: "character.bubble") {
            TranslatorView()
                .frame(width: 640, height: 720)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Translator View
struct TranslatorView: View {
    @State private var inputText = ""
    @State private var translationResults: [TranslationResult] = []
    @State private var sourceLanguage = "English"
    @State private var targetLanguage = "Chinese"
    @State private var isTranslating = false
    @State private var showingSettings = false
    @State private var showingMenu = false
    @State private var showingDonateView = false
    @State private var didAppear = false
    @FocusState private var isInputFocused: Bool
    @ObservedObject private var providerManager = ProviderManager.shared

    private let languages = ["English", "Chinese"]

    // Google 翻译服务（固定）
    private let googleService = GoogleTranslationService()

    // 从 ProviderManager 动态获取启用的供应商 + Google 翻译
    private var translationServices: [TranslationService] {
        var services: [TranslationService] = [googleService]
        services += providerManager.providers
            .filter { $0.isEnabled }
            .map { ConfigurableTranslationService(config: $0) }
        return services
    }

    private var sortedTranslationResults: [TranslationResult] {
        translationResults.sorted { first, second in
            // 如果第一个是错误而第二个不是，第一个应该排在后面
            if first.isError && !second.isError {
                return false
            }
            // 如果第二个是错误而第一个不是，第一个应该排在前面
            if !first.isError && second.isError {
                return true
            }
            // 如果都是错误或都不是错误，保持原有顺序
            return first.serviceName < second.serviceName
        }
    }

    private var activeEngineCount: Int {
        1 + providerManager.providers.filter { $0.isEnabled }.count
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                topBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        languageCard
                            .opacity(didAppear ? 1 : 0)
                            .offset(y: didAppear ? 0 : 12)
                            .animation(appearAnimation(0.05), value: didAppear)
                        inputCard
                            .opacity(didAppear ? 1 : 0)
                            .offset(y: didAppear ? 0 : 12)
                            .animation(appearAnimation(0.12), value: didAppear)
                        translateButton
                            .opacity(didAppear ? 1 : 0)
                            .offset(y: didAppear ? 0 : 12)
                            .animation(appearAnimation(0.18), value: didAppear)
                        if !translationResults.isEmpty {
                            resultsCard
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(14)
                }
                .onAppear {
                    didAppear = true
                }

                bottomBar
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            AppTheme.backgroundGradient
            Circle()
                .fill(AppTheme.accent.opacity(0.12))
                .frame(width: 260, height: 260)
                .offset(x: -140, y: -200)
            Circle()
                .fill(AppTheme.accentAlt.opacity(0.12))
                .frame(width: 220, height: 220)
                .offset(x: 180, y: 240)
            RoundedRectangle(cornerRadius: 32)
                .fill(AppTheme.warm.opacity(0.35))
                .frame(width: 320, height: 120)
                .rotationEffect(.degrees(-8))
                .offset(x: -90, y: 250)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient)
                    .frame(width: 32, height: 32)
                Image(systemName: "character.bubble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("翻译助手")
                    .font(AppFonts.title(15))
                Text("多引擎 · 迅速 · 轻量")
                    .font(AppFonts.body(11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            CapsuleTag("⌘⌃Q", tint: AppTheme.accent)

            Button(action: {
                if let window = NSApp.windows.first(where: { $0.isKeyWindow }) {
                    window.close()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("关闭窗口")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    private var languageCard: some View {
        SectionCard(title: "语言方向", subtitle: nil, padding: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("源语言")
                        .font(AppFonts.body(11))
                        .foregroundColor(.secondary)
                    Picker("From", selection: $sourceLanguage) {
                        ForEach(languages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity)

                Button(action: {
                    let temp = sourceLanguage
                    sourceLanguage = targetLanguage
                    targetLanguage = temp
                }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(AppTheme.accent.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .help("交换语言")

                VStack(alignment: .leading, spacing: 6) {
                    Text("目标语言")
                        .font(AppFonts.body(11))
                        .foregroundColor(.secondary)
                    Picker("To", selection: $targetLanguage) {
                        ForEach(languages, id: \.self) { language in
                            Text(language).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var inputCard: some View {
        SectionCard(title: "输入文本", subtitle: "支持单词与句子自动识别", padding: 12) {
            VStack(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty && !isInputFocused {
                        Text("请输入要翻译的文本…")
                            .font(AppFonts.body(11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $inputText)
                        .font(AppFonts.body(12))
                        .padding(6)
                        .focused($isInputFocused)
                        .background(Color.clear)
                        .scrollBackgroundHiddenIfAvailable()
                }
                .frame(height: 110)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isInputFocused ? AppTheme.accent : AppTheme.border, lineWidth: isInputFocused ? 2 : 1)
                )

                HStack {
                    Text("\(inputText.count) 字符")
                        .font(AppFonts.mono(10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("提示：自动判断词典 / 翻译模式")
                        .font(AppFonts.body(10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var translateButton: some View {
        Button(action: {
            Task {
                await translateText()
            }
        }) {
            HStack(spacing: 8) {
                if isTranslating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isTranslating ? "翻译中…" : "开始翻译")
                    .font(AppFonts.headline(14))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
            .background(AppTheme.accentGradient)
            .clipShape(Capsule())
            .shadow(color: AppTheme.accent.opacity(0.25), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(inputText.isEmpty || isTranslating)
        .opacity(inputText.isEmpty || isTranslating ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.2), value: isTranslating)
    }

    private var resultsCard: some View {
        SectionCard(title: "翻译结果", subtitle: "来自 \(activeEngineCount) 个引擎") {
            VStack(spacing: 14) {
                ForEach(sortedTranslationResults) { result in
                    TranslationResultView(result: result)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            CapsuleTag(isTranslating ? "正在翻译" : "就绪", systemImage: isTranslating ? "sparkles" : "checkmark.circle", tint: isTranslating ? AppTheme.accentAlt : AppTheme.success)
            CapsuleTag("引擎 \(activeEngineCount)", systemImage: "bolt.fill", tint: AppTheme.accent)

            Spacer()

            Button(action: { showingMenu.toggle() }) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingMenu, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    Button(action: {
                        showingSettings = true
                        showingMenu = false
                    }) {
                        Label("设置", systemImage: "gear")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()

                    Button(action: {
                        showingDonateView = true
                        showingMenu = false
                    }) {
                        Label("请我喝咖啡", systemImage: "cup.and.saucer.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()

                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Label("退出应用", systemImage: "power")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .padding(6)
                .frame(width: 200)
            }
            .popover(isPresented: $showingSettings) {
                SettingsView()
                    .frame(width: 460, height: 520)
            }
            .popover(isPresented: $showingDonateView) {
                DonateView()
                    .frame(width: 320, height: 420)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func appearAnimation(_ delay: Double) -> Animation {
        .spring(response: 0.5, dampingFraction: 0.88).delay(delay)
    }

    private func translateText() async {
        isTranslating = true
        translationResults = []

        await withTaskGroup(of: TranslationResult?.self) { group in
            for service in translationServices {
                group.addTask {
                    do {
                        let result = try await service.translate(
                            inputText,
                            from: sourceLanguage.lowercased(),
                            to: targetLanguage.lowercased()
                        )
                        return TranslationResult(
                            serviceName: service.name,
                            text: result,
                            isError: false
                        )
                    } catch {
                        return TranslationResult(
                            serviceName: service.name,
                            text: "翻译失败: \(error.localizedDescription)",
                            isError: true
                        )
                    }
                }
            }

            for await result in group {
                if let result = result {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        translationResults.append(result)
                    }
                }
            }
        }

        isTranslating = false
    }
}

// MARK: - Settings View
struct SettingsView: View {
    enum ViewMode {
        case list
        case editProvider(ProviderConfig, isNew: Bool)
    }

    @ObservedObject private var providerManager = ProviderManager.shared
    @State private var viewMode: ViewMode = .list
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var googleApiKey: String = ""

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()
            contentView
        }
        .task {
            googleApiKey = (try? KeychainManager.shared.getApiKey(for: "Google")) ?? ""
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewMode {
        case .list:
            listView
        case .editProvider(let provider, let isNew):
            ProviderEditView(
                provider: provider,
                isNew: isNew,
                onSave: { updated, apiKey in
                    if isNew {
                        providerManager.addProvider(updated)
                    } else {
                        providerManager.updateProvider(updated)
                    }
                    if !apiKey.isEmpty {
                        try? providerManager.saveApiKey(apiKey, for: updated.id)
                    }
                    viewMode = .list
                },
                onCancel: { viewMode = .list }
            )
        }
    }

    private var listView: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(AppFonts.title(20))
                    Text("配置翻译引擎与密钥")
                        .font(AppFonts.body(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            SectionCard(title: "Google 翻译", subtitle: "备用翻译服务") {
                HStack(spacing: 12) {
                    SecureField("Google API Key", text: $googleApiKey)
                        .textFieldStyle(.roundedBorder)

                    Button("保存") {
                        if googleApiKey.isEmpty {
                            try? KeychainManager.shared.deleteApiKey(for: "Google")
                        } else {
                            try? KeychainManager.shared.saveApiKey(googleApiKey, for: "Google")
                        }
                        alertMessage = "已保存"
                        showAlert = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showAlert = false
                        }
                    }
                    .buttonStyle(.plain)
                    .font(AppFonts.headline(12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundColor(.white)
                    .background(AppTheme.accentGradient)
                    .clipShape(Capsule())
                }
            }

            SectionCard(title: "AI 翻译服务供应商", subtitle: "管理自定义模型与端点") {
                ScrollView {
                    VStack(spacing: 10) {
                        if providerManager.providers.isEmpty {
                            Text("尚未添加供应商")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(providerManager.providers) { provider in
                                ProviderRowView(
                                    provider: provider,
                                    onEdit: { viewMode = .editProvider(provider, isNew: false) },
                                    onDelete: { providerManager.deleteProvider(id: provider.id) },
                                    onToggle: { enabled in
                                        var updated = provider
                                        updated.isEnabled = enabled
                                        providerManager.updateProvider(updated)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 180)

                Button(action: {
                    viewMode = .editProvider(ProviderConfig(name: "", baseURL: "", modelName: ""), isNew: true)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("添加供应商")
                    }
                    .font(AppFonts.headline(12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundColor(AppTheme.accent)
                    .background(
                        Capsule()
                            .fill(AppTheme.accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(20)
        .overlay {
            if showAlert {
                VStack {
                    Text(alertMessage)
                        .font(AppFonts.body(12))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(.thinMaterial)
                        )
                }
            }
        }
    }
}
