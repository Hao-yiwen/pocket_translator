# 签名流程

1. 签名
```bash
codesign --force --deep --sign "QRCodeGenerator" ./QRCodeGenerator-Bundle/qrcode_generator.app 
```

2. 校验
```bash
codesign --verify --deep --strict ./QRCodeGenerator-Bundle/qrcode_generator.app 
```

3. dmg制作
```bash
ln -s /Applications "./QRCodeGenerator-Bundle/Applications"

hdiutil create -volname "QR Code Generator" \
               -srcfolder QRCodeGenerator-Bundle \
               -ov -format UDZO \
               QRCodeGenerator.dmg
```