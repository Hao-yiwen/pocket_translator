import SwiftUI

// MARK: - Window Manager
class WindowManager {
    static let shared = WindowManager()
    private var settingsWindow: NSWindow?
    private var donateWindow: NSWindow?

    private init() {}

    func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.minSize = NSSize(width: 450, height: 500)
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func openDonate() {
        if let window = donateWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "请我喝咖啡"
        window.center()
        window.contentView = NSHostingView(rootView: DonateView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        donateWindow = window
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "翻译助手")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // 创建 Popover，默认使用 transient（文本模式）
        popover = NSPopover()
        popover.contentSize = NSSize(width: 480, height: 720)
        popover.behavior = .transient  // 默认点击外部可关闭
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: TranslatorView(
            closeAction: { [weak self] in
                self?.popover.performClose(nil)
            },
            onModeChange: { [weak self] mode in
                // 根据模式切换 popover 行为
                // .text 模式：点击外部可关闭
                // .image 模式：只能点击 X 关闭
                self?.popover.behavior = (mode == .text) ? .transient : .applicationDefined
            }
        ))
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let button = statusItem.button {
                // 记录当前鼠标所在的屏幕
                let mouseLocation = NSEvent.mouseLocation
                let currentScreen = NSScreen.screens.first { screen in
                    screen.frame.contains(mouseLocation)
                } ?? NSScreen.main

                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

                // 确保 popover 窗口可以接收键盘输入
                if let window = popover.contentViewController?.view.window {
                    window.makeKey()
                    // 不跟随空间切换
                    window.collectionBehavior = [.stationary, .ignoresCycle]

                    // 如果窗口不在原屏幕上，移回去
                    if let screen = currentScreen, !screen.frame.intersects(window.frame) {
                        let newOrigin = NSPoint(
                            x: screen.frame.midX - window.frame.width / 2,
                            y: screen.frame.maxY - window.frame.height - 30
                        )
                        window.setFrameOrigin(newOrigin)
                    }
                }
            }
        }
    }
}

// MARK: - Main App
@main
struct TranslatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 使用 Settings 场景作为占位，实际 UI 由 AppDelegate 管理
        Settings {
            EmptyView()
        }
    }
}

// MARK: - Translator View
struct TranslatorView: View {
    var closeAction: (() -> Void)?
    var onModeChange: ((TranslationMode) -> Void)?

    @State private var inputText = ""
    @State private var translationResults: [TranslationResult] = []
    @State private var sourceLanguage = "English"
    @State private var targetLanguage = "Chinese"
    @State private var isTranslating = false
    @State private var showingMenu = false
    @State private var didAppear = false
    @FocusState private var isInputFocused: Bool
    @ObservedObject private var providerManager = ProviderManager.shared
    @ObservedObject private var visionProviderManager = VisionProviderManager.shared

    // 截图翻译相关状态
    @State private var translationMode: TranslationMode = .text
    @State private var selectedImage: NSImage?
    @State private var imageData: Data?

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

    // Vision 翻译服务
    private var visionServices: [VisionTranslationService] {
        visionProviderManager.providers
            .filter { $0.isEnabled }
            .map { VisionTranslationService(config: $0) }
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
        switch translationMode {
        case .text:
            return 1 + providerManager.providers.filter { $0.isEnabled }.count
        case .image:
            return visionProviderManager.providers.filter { $0.isEnabled }.count
        }
    }

    private var canTranslate: Bool {
        switch translationMode {
        case .text:
            return !inputText.isEmpty
        case .image:
            return imageData != nil
        }
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                topBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        // 模式切换
                        modeToggleCard
                            .opacity(didAppear ? 1 : 0)
                            .offset(y: didAppear ? 0 : 12)
                            .animation(appearAnimation(0.02), value: didAppear)

                        languageCard
                            .opacity(didAppear ? 1 : 0)
                            .offset(y: didAppear ? 0 : 12)
                            .animation(appearAnimation(0.05), value: didAppear)

                        // 根据模式显示不同输入区域
                        Group {
                            if translationMode == .text {
                                inputCard
                            } else {
                                ImageInputCard(selectedImage: $selectedImage, imageData: $imageData)
                            }
                        }
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
                .onChange(of: translationMode) { newMode in
                    onModeChange?(newMode)
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
                closeAction?()
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

    private var modeToggleCard: some View {
        HStack {
            Spacer()
            ModeToggle(mode: $translationMode)
            Spacer()
        }
    }

    private var languageCard: some View {
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadow, radius: 10, x: 0, y: 6)
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
        VStack(spacing: 8) {
            Button(action: {
                Task {
                    if translationMode == .text {
                        await translateText()
                    } else {
                        await translateImage()
                    }
                }
            }) {
                HStack(spacing: 8) {
                    if isTranslating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: translationMode == .text ? "sparkles" : "photo.badge.checkmark")
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
            .disabled(!canTranslate || isTranslating)
            .opacity(!canTranslate || isTranslating ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.2), value: isTranslating)

            // 图片模式下的提示
            if translationMode == .image && visionServices.isEmpty {
                Text("请先在设置中配置图片翻译服务")
                    .font(AppFonts.body(11))
                    .foregroundColor(AppTheme.danger)
            }
        }
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
                        showingMenu = false
                        WindowManager.shared.openSettings()
                    }) {
                        Label("设置", systemImage: "gear")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()

                    Button(action: {
                        showingMenu = false
                        WindowManager.shared.openDonate()
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

    private func translateImage() async {
        guard let imageData = imageData else { return }

        isTranslating = true
        translationResults = []

        let services = visionServices
        if services.isEmpty {
            translationResults.append(TranslationResult(
                serviceName: "系统",
                text: "请先在设置中配置图片翻译服务",
                isError: true
            ))
            isTranslating = false
            return
        }

        await withTaskGroup(of: TranslationResult?.self) { group in
            for service in services {
                group.addTask {
                    do {
                        let result = try await service.translateImage(
                            imageData,
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
        case editVisionProvider(VisionProviderConfig, isNew: Bool)
    }

    @ObservedObject private var providerManager = ProviderManager.shared
    @ObservedObject private var visionProviderManager = VisionProviderManager.shared
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
        case .editVisionProvider(let provider, let isNew):
            VisionProviderEditView(
                provider: provider,
                isNew: isNew,
                onSave: { updated, apiKey in
                    if isNew {
                        visionProviderManager.addProvider(updated)
                    } else {
                        visionProviderManager.updateProvider(updated)
                    }
                    if !apiKey.isEmpty {
                        try? visionProviderManager.saveApiKey(apiKey, for: updated.id)
                    }
                    viewMode = .list
                },
                onCancel: { viewMode = .list }
            )
        }
    }

    private var listView: some View {
        ScrollView {
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

            // Vision 服务配置区域
            SectionCard(title: "图片翻译服务", subtitle: "配置多模态 AI 模型（如豆包、Gemini）") {
                ScrollView {
                    VStack(spacing: 10) {
                        if visionProviderManager.providers.isEmpty {
                            Text("尚未添加图片翻译服务")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(visionProviderManager.providers) { provider in
                                VisionProviderRowView(
                                    provider: provider,
                                    onEdit: { viewMode = .editVisionProvider(provider, isNew: false) },
                                    onDelete: { visionProviderManager.deleteProvider(id: provider.id) },
                                    onToggle: { enabled in
                                        var updated = provider
                                        updated.isEnabled = enabled
                                        visionProviderManager.updateProvider(updated)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 180)

                Button(action: {
                    viewMode = .editVisionProvider(VisionProviderConfig(name: "", baseURL: "", modelName: ""), isNew: true)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("添加图片翻译服务")
                    }
                    .font(AppFonts.headline(12))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundColor(AppTheme.accentAlt)
                    .background(
                        Capsule()
                            .fill(AppTheme.accentAlt.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
            }
            .padding(20)
        }
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
