# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

口袋翻译 (Pocket Translator) - 一个运行在 macOS 状态栏的轻量级多引擎翻译工具，使用 SwiftUI 开发。

## Build Commands

```bash
# 构建项目
xcodebuild -project pocket_translator.xcodeproj -scheme pocket_translator build

# 运行项目
open pocket_translator.xcodeproj  # 在 Xcode 中打开后运行
```

## Architecture

### 文件结构
- `pocket_translatorApp.swift` - 应用入口、主视图 (TranslatorView)、设置视图 (SettingsView)
- `Models.swift` - 数据模型、翻译服务协议、网络请求、Keychain 管理
- `Theme.swift` - 主题颜色 (AppTheme)、字体 (AppFonts)、可复用 UI 组件

### 核心设计模式

**翻译服务抽象**
- `TranslationService` 协议定义翻译接口
- `GoogleTranslationService` - Google Cloud Translation API 实现
- `ConfigurableTranslationService` - 支持任意 OpenAI 兼容 API 的通用实现

**供应商管理**
- `ProviderManager` (单例) 管理自定义 AI 翻译供应商配置
- 供应商配置持久化到 UserDefaults，API Key 存储在 macOS Keychain

**输入类型检测**
- `detectInputType()` 自动区分单词和句子/段落
- 单词模式返回词典格式，句子模式返回直接翻译

### 关键技术点
- MenuBarExtra 实现状态栏常驻
- AppDelegate 设置 `.accessory` 激活策略隐藏 Dock 图标
- 多引擎并行翻译使用 `withTaskGroup`
- API Key 安全存储使用 Security 框架的 Keychain API

## Requirements

- macOS 13.0+
- Xcode 14.0+ (Swift 5.0+)
