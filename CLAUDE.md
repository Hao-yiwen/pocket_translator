# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

口袋翻译 (Pocket Translator) - 一个运行在 macOS 状态栏的轻量级多引擎翻译工具，使用 SwiftUI 开发。支持文本翻译和图片翻译两种模式。

## Build Commands

```bash
# 构建项目
xcodebuild -project pocket_translator.xcodeproj -scheme pocket_translator build

# 运行项目
open pocket_translator.xcodeproj  # 在 Xcode 中打开后运行
```

## Architecture

### 文件结构
- `pocket_translatorApp.swift` - 应用入口、WindowManager、AppDelegate、TranslatorView、SettingsView
- `Models.swift` - 数据模型、翻译服务协议、网络请求、Keychain 管理、截图管理
- `Theme.swift` - 主题颜色 (AppTheme)、字体 (AppFonts)、可复用 UI 组件

### 核心设计模式

**应用架构**
- `AppDelegate` 管理 NSStatusItem 和 NSPopover（替代 MenuBarExtra 以获得更好的窗口控制）
- `WindowManager` (单例) 管理设置和打赏的独立窗口
- NSPopover 的 behavior 根据翻译模式动态切换（文本模式 `.transient`，图片模式 `.applicationDefined`）

**翻译服务抽象**
- `TranslationService` 协议定义文本翻译接口
- `GoogleTranslationService` - Google Cloud Translation API 实现
- `ConfigurableTranslationService` - 支持任意 OpenAI 兼容 API 的通用实现
- `VisionTranslationService` - 图片翻译服务，支持多模态 AI 模型

**供应商管理**
- `ProviderManager` (单例) 管理文本翻译供应商配置
- `VisionProviderManager` (单例) 管理图片翻译供应商配置
- 配置持久化到 UserDefaults，API Key 存储在 macOS Keychain（使用 `kSecAttrService` 标识应用）
- 支持自定义参数 (customParams) 用于传递额外 API 参数

**截图管理**
- `ScreenshotManager` (单例) 处理屏幕截图
- 使用 `screencapture -i -c` 命令进行交互式截图
- 需要屏幕录制权限，使用 `CGPreflightScreenCaptureAccess()` 检查

**输入类型检测**
- `detectInputType()` 自动区分单词和句子/段落
- 单词模式返回词典格式，句子模式返回直接翻译

### 关键技术点
- NSStatusItem + NSPopover 实现状态栏常驻（而非 MenuBarExtra）
- AppDelegate 设置 `.accessory` 激活策略隐藏 Dock 图标
- 多引擎并行翻译使用 `withTaskGroup`
- API Key 安全存储使用 Security 框架的 Keychain API
- 翻译结果支持 Markdown 渲染（使用 AttributedString）
- 窗口 collectionBehavior 设置 `.stationary` 防止跟随屏幕切换

## Requirements

- macOS 13.0+
- Xcode 14.0+ (Swift 5.0+)
- 图片翻译需要屏幕录制权限
