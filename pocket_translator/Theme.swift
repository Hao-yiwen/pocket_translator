import SwiftUI

// MARK: - App Theme
enum AppTheme {
    static let accent = Color(red: 0.22, green: 0.36, blue: 0.94)
    static let accentAlt = Color(red: 0.10, green: 0.65, blue: 0.78)
    static let warm = Color(red: 0.96, green: 0.92, blue: 0.86)
    static let surface = Color(NSColor.windowBackgroundColor).opacity(0.9)
    static let surfaceStrong = Color(NSColor.controlBackgroundColor)
    static let border = Color.black.opacity(0.08)
    static let shadow = Color.black.opacity(0.12)
    static let success = Color(red: 0.17, green: 0.68, blue: 0.39)
    static let danger = Color(red: 0.86, green: 0.28, blue: 0.30)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.95, blue: 0.93),
                Color(red: 0.91, green: 0.94, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentAlt],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Custom Switch Toggle Style
struct CustomSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(configuration.isOn ? AppTheme.accent : Color.gray.opacity(0.3))
            .frame(width: 48, height: 28)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 1)
                    .padding(3)
                    .offset(x: configuration.isOn ? 10 : -10)
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    configuration.isOn.toggle()
                }
            }
    }
}

// MARK: - App Fonts
enum AppFonts {
    static func title(_ size: CGFloat) -> Font {
        Font.custom("Avenir Next", size: size).weight(.semibold)
    }

    static func headline(_ size: CGFloat) -> Font {
        Font.custom("Avenir Next", size: size).weight(.medium)
    }

    static func body(_ size: CGFloat) -> Font {
        Font.custom("Avenir", size: size)
    }

    static func mono(_ size: CGFloat) -> Font {
        Font.custom("Menlo", size: size)
    }
}

// MARK: - Section Card
struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let padding: CGFloat
    let content: Content

    init(title: String, subtitle: String? = nil, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFonts.headline(14))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AppFonts.body(12))
                        .foregroundColor(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
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
}

// MARK: - Capsule Tag
struct CapsuleTag: View {
    let text: String
    let systemImage: String?
    let tint: Color

    init(_ text: String, systemImage: String? = nil, tint: Color = AppTheme.accent) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(AppFonts.mono(11))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(tint)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
    }
}

extension View {
    @ViewBuilder
    func scrollBackgroundHiddenIfAvailable() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

// MARK: - Translation Result View
struct TranslationResultView: View {
    let result: TranslationResult
    @State private var isCopied = false

    private var markdownText: AttributedString {
        (try? AttributedString(markdown: result.text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(result.text)
    }

    var body: some View {
        let statusColor = result.isError ? AppTheme.danger : AppTheme.success
        let cardTint = result.isError ? AppTheme.danger.opacity(0.08) : AppTheme.accentAlt.opacity(0.08)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(result.serviceName)
                        .font(AppFonts.headline(13))
                }

                Spacer()

                if !result.isError {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.text, forType: .string)

                        withAnimation {
                            isCopied = true
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                isCopied = false
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            Text(isCopied ? "已复制" : "复制")
                        }
                        .font(AppFonts.body(11))
                        .foregroundColor(isCopied ? AppTheme.success : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(markdownText)
                .font(AppFonts.body(13))
                .foregroundColor(result.isError ? AppTheme.danger : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.surfaceStrong)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(statusColor.opacity(0.25), lineWidth: 1)
                )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(statusColor.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Provider Row View
struct ProviderRowView: View {
    let provider: ProviderConfig
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: (Bool) -> Void

    private var initials: String {
        guard let first = provider.name.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { provider.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(CustomSwitchToggleStyle())
            .labelsHidden()

            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.16))
                    .frame(width: 32, height: 32)
                Text(initials)
                    .font(AppFonts.headline(12))
                    .foregroundColor(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name.isEmpty ? "未命名" : provider.name)
                    .font(AppFonts.headline(13))
                Text(provider.modelName)
                    .font(AppFonts.body(11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            CapsuleTag(provider.isEnabled ? "启用" : "停用", systemImage: provider.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill", tint: provider.isEnabled ? AppTheme.success : AppTheme.danger)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("编辑")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.danger)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(AppTheme.danger.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.surfaceStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Provider Edit View
struct ProviderEditView: View {
    @State private var provider: ProviderConfig
    @State private var apiKey: String = ""
    let isNew: Bool
    let onSave: (ProviderConfig, String) -> Void
    let onCancel: () -> Void

    init(provider: ProviderConfig, isNew: Bool, onSave: @escaping (ProviderConfig, String) -> Void, onCancel: @escaping () -> Void) {
        self._provider = State(initialValue: provider)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel

        // 加载已保存的 API Key
        if !isNew {
            if let savedKey = ProviderManager.shared.getApiKey(for: provider.id) {
                self._apiKey = State(initialValue: savedKey)
            }
        }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isNew ? "添加供应商" : "编辑供应商")
                        .font(AppFonts.title(20))
                    Text("配置名称、端点与模型")
                        .font(AppFonts.body(12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SectionCard(title: "基础信息", subtitle: nil) {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("名称")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            TextField("例如: OpenAI, DeepSeek", text: $provider.name)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base URL")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            TextField("https://api.openai.com/v1/chat/completions", text: $provider.baseURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("模型名称")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            TextField("例如: deepseek-chat, doubao-seed-1.8", text: $provider.modelName)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Key")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            SecureField("输入 API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("自定义参数 (JSON)")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            TextField("{\"reasoning_effort\": \"medium\"}", text: $provider.customParams)
                                .textFieldStyle(.roundedBorder)
                            Text("可选，用于添加额外的 API 参数")
                                .font(AppFonts.body(10))
                                .foregroundStyle(.tertiary)
                        }

                        Toggle("启用此供应商", isOn: $provider.isEnabled)
                            .toggleStyle(.switch)
                    }
                }

                HStack(spacing: 14) {
                    Button("取消") {
                        onCancel()
                    }
                    .buttonStyle(.plain)
                    .font(AppFonts.headline(12))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .foregroundColor(.secondary)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                    )

                    Button("保存") {
                        onSave(provider, apiKey)
                    }
                    .buttonStyle(.plain)
                    .font(AppFonts.headline(12))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(AppTheme.accentGradient)
                    .clipShape(Capsule())
                    .disabled(provider.name.isEmpty || provider.baseURL.isEmpty || provider.modelName.isEmpty)
                    .opacity(provider.name.isEmpty || provider.baseURL.isEmpty || provider.modelName.isEmpty ? 0.5 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .frame(width: 420)
    }
}

// MARK: - Donate View
struct DonateView: View {
    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("感谢您的支持！")
                        .font(AppFonts.title(18))
                    Text("每一杯咖啡都是动力")
                        .font(AppFonts.body(12))
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    Image("alipay-qr") // 确保在 Assets.xcassets 中添加您的收款码图片
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 260)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 6)

                    Text("扫描上方二维码向我打赏")
                        .font(AppFonts.body(12))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
            }
            .padding(20)
        }
        .frame(width: 320, height: 420)
    }
}

// MARK: - Mode Toggle
struct ModeToggle: View {
    @Binding var mode: TranslationMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TranslationMode.allCases, id: \.self) { m in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = m
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: m == .text ? "doc.text" : "photo")
                            .font(.system(size: 12))
                        Text(m.rawValue)
                            .font(AppFonts.headline(12))
                    }
                    .foregroundColor(mode == m ? .white : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if mode == m {
                                Capsule()
                                    .fill(AppTheme.accentGradient)
                            } else {
                                Capsule()
                                    .fill(Color.clear)
                            }
                        }
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.06))
        )
    }
}

// MARK: - Image Input Card
struct ImageInputCard: View {
    @Binding var selectedImage: NSImage?
    @Binding var imageData: Data?
    @State private var isDropTargeted = false

    var body: some View {
        SectionCard(title: "图片输入", subtitle: "支持截图、粘贴或选择文件", padding: 12) {
            VStack(spacing: 12) {
                // 图片预览区域
                ZStack {
                    if let image = selectedImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .cornerRadius(8)
                            .overlay(
                                // 清除按钮
                                Button(action: clearImage) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                }
                                .buttonStyle(.plain)
                                .padding(8),
                                alignment: .topTrailing
                            )
                    } else {
                        // 拖拽放置区域
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("拖拽图片到此处")
                                .font(AppFonts.body(12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isDropTargeted ? AppTheme.accent.opacity(0.1) : Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isDropTargeted ? AppTheme.accent : AppTheme.border, style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6]))
                        )
                    }
                }
                .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }

                // 操作按钮
                HStack(spacing: 10) {
                    ActionButton(title: "截取屏幕", icon: "camera.viewfinder") {
                        Task {
                            if let image = await ScreenshotManager.shared.captureScreen() {
                                setImage(image)
                            }
                        }
                    }

                    ActionButton(title: "从剪贴板", icon: "doc.on.clipboard") {
                        if let image = ScreenshotManager.shared.getImageFromClipboard() {
                            setImage(image)
                        }
                    }

                    ActionButton(title: "选择文件", icon: "folder") {
                        Task { @MainActor in
                            if let image = await ScreenshotManager.shared.selectImageFile() {
                                setImage(image)
                            }
                        }
                    }
                }
            }
        }
    }

    private func setImage(_ image: NSImage) {
        selectedImage = image
        if let data = ScreenshotManager.imageToData(image) {
            // 压缩大图片
            imageData = ScreenshotManager.compressImageIfNeeded(data)
        }
    }

    private func clearImage() {
        selectedImage = nil
        imageData = nil
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // 尝试加载图片
            if provider.hasItemConformingToTypeIdentifier("public.image") {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    if let image = object as? NSImage {
                        DispatchQueue.main.async {
                            setImage(image)
                        }
                    }
                }
                return
            }

            // 尝试加载文件 URL
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       let image = NSImage(contentsOf: url) {
                        DispatchQueue.main.async {
                            setImage(image)
                        }
                    }
                }
                return
            }
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(AppFonts.body(10))
            }
            .foregroundColor(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.accent.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vision Provider Row View
struct VisionProviderRowView: View {
    let provider: VisionProviderConfig
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggle: (Bool) -> Void

    private var initials: String {
        guard let first = provider.name.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { provider.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(CustomSwitchToggleStyle())
            .labelsHidden()

            ZStack {
                Circle()
                    .fill(AppTheme.accentAlt.opacity(0.16))
                    .frame(width: 32, height: 32)
                Text(initials)
                    .font(AppFonts.headline(12))
                    .foregroundColor(AppTheme.accentAlt)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name.isEmpty ? "未命名" : provider.name)
                    .font(AppFonts.headline(13))
                Text(provider.modelName)
                    .font(AppFonts.body(11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            CapsuleTag(provider.isEnabled ? "启用" : "停用", systemImage: provider.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill", tint: provider.isEnabled ? AppTheme.success : AppTheme.danger)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("编辑")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.danger)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(AppTheme.danger.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.surfaceStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Vision Provider Edit View
struct VisionProviderEditView: View {
    @State private var provider: VisionProviderConfig
    @State private var apiKey: String = ""
    let isNew: Bool
    let onSave: (VisionProviderConfig, String) -> Void
    let onCancel: () -> Void

    init(provider: VisionProviderConfig, isNew: Bool, onSave: @escaping (VisionProviderConfig, String) -> Void, onCancel: @escaping () -> Void) {
        self._provider = State(initialValue: provider)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel

        if !isNew {
            if let savedKey = VisionProviderManager.shared.getApiKey(for: provider.id) {
                self._apiKey = State(initialValue: savedKey)
            }
        }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isNew ? "添加图片翻译服务" : "编辑图片翻译服务")
                        .font(AppFonts.title(20))
                    Text("配置多模态 AI 模型")
                        .font(AppFonts.body(12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SectionCard(title: "服务配置", subtitle: nil) {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("名称")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            TextField("例如: 豆包, DeepSeek", text: $provider.name)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base URL")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            TextField("https://api.openai.com/v1/chat/completions", text: $provider.baseURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("模型名称")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            TextField("例如: doubao-seed-1.8", text: $provider.modelName)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Key")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            SecureField("输入 API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("自定义参数 (JSON)")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            TextField("{\"reasoning_effort\": \"medium\"}", text: $provider.customParams)
                                .textFieldStyle(.roundedBorder)
                            Text("可选，用于添加额外的 API 参数")
                                .font(AppFonts.body(10))
                                .foregroundStyle(.tertiary)
                        }

                        Toggle("启用此服务", isOn: $provider.isEnabled)
                            .toggleStyle(.switch)
                    }
                }

                HStack(spacing: 14) {
                    Button("取消") {
                        onCancel()
                    }
                    .buttonStyle(.plain)
                    .font(AppFonts.headline(12))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .foregroundColor(.secondary)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                    )

                    Button("保存") {
                        onSave(provider, apiKey)
                    }
                    .buttonStyle(.plain)
                    .font(AppFonts.headline(12))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(AppTheme.accentGradient)
                    .clipShape(Capsule())
                    .disabled(provider.name.isEmpty || provider.baseURL.isEmpty || provider.modelName.isEmpty)
                    .opacity(provider.name.isEmpty || provider.baseURL.isEmpty || provider.modelName.isEmpty ? 0.5 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .frame(width: 420)
    }
}
