# 签名流程

1. 签名
```bash
codesign --force --deep --sign "TranslatorGenerator" ./TranslatorGenerator-Bundle/pocket_translator.app 
```

2. 校验
```bash
codesign --verify --deep --strict ./TranslatorGenerator-Bundle/pocket_translator.app 
```

3. dmg制作
```bash
ln -s /Applications "./TranslatorGenerator-Bundle/Applications"

hdiutil create -volname "Pocket Translator" \
               -srcfolder TranslatorGenerator-Bundle \
               -ov -format UDZO \
               TranslatorGenerator.dmg
```