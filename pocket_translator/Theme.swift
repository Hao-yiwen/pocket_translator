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

            Text(result.text)
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

    @State private var isEnabled: Bool

    init(provider: ProviderConfig, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void, onToggle: @escaping (Bool) -> Void) {
        self.provider = provider
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onToggle = onToggle
        self._isEnabled = State(initialValue: provider.isEnabled)
    }

    private var initials: String {
        guard let first = provider.name.first else { return "?" }
        return String(first).uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $isEnabled) { EmptyView() }
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 38, height: 22, alignment: .center)
                .fixedSize()
                .onChange(of: isEnabled) { newValue in
                    onToggle(newValue)
                }

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

            CapsuleTag(isEnabled ? "启用" : "停用", systemImage: isEnabled ? "checkmark.circle.fill" : "pause.circle.fill", tint: isEnabled ? AppTheme.success : AppTheme.danger)

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
                            TextField("例如: gpt-4o, deepseek-chat", text: $provider.modelName)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Key")
                                .font(AppFonts.body(12))
                                .foregroundStyle(.secondary)
                            SecureField("输入 API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
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
