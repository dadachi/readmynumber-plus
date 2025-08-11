import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ResidenceCardDetailView: View {
    let cardData: ResidenceCardData
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @State private var showingExportSheet = false
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @StateObject private var dataManager = ResidenceCardDataManager.shared

    var body: some View {
        ZStack {
            // 背景グラデーション
            LinearGradient(
                gradient: Gradient(colors: [Color.white, Color(UIColor.systemGray6)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // メインのスクロール可能な領域
            ScrollView {
                VStack(spacing: 20) {
                    // タイトル
                    Text("在留カード情報")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top, 20)

                    // 基本情報カード
                    VStack(spacing: 12) {
                        // ヘッダー部分
                        HStack {
                            Image(systemName: "person.text.rectangle.fill")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundColor(Color.green)
                                .symbolRenderingMode(.hierarchical)

                            Text("基本情報")
                                .font(.headline)
                                .fontWeight(.bold)

                            Spacer()

                            Text("在留カード")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .padding(.bottom, 8)

                        Divider()
                            .background(Color.green.opacity(0.3))

                        // 共通データ要素
                        if let versionData = cardData.parseTLV(data: cardData.commonData, tag: 0xC0),
                           let version = String(data: versionData, encoding: .utf8) {
                            InfoCardView(title: "仕様バージョン", value: version, systemImage: "info.circle")
                        }

                        // カード種別
                        let cardType = parseCardTypeString(from: cardData.cardType)
                        InfoCardView(title: "カード種別", value: cardType, systemImage: "creditcard")

                        // 住所情報
                        if let addressString = parseAddressData(from: cardData.address) {
                            InfoCardView(title: "住所", value: addressString, systemImage: "location.fill", isFullWidth: true)
                        }

                        // 在留カード特有の追加情報
                        if let additionalData = cardData.additionalData {
                            if let permission = parsePermissionData(from: additionalData.comprehensivePermission) {
                                InfoCardView(title: "包括的活動許可", value: permission, systemImage: "checkmark.circle", isFullWidth: true)
                            }
                            
                            if let individual = parsePermissionData(from: additionalData.individualPermission) {
                                InfoCardView(title: "個別許可", value: individual, systemImage: "person.circle", isFullWidth: true)
                            }
                        }
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                    .cornerRadius(16)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                    // 画像データ表示エリア
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("画像データ")
                                .font(.headline)
                                .fontWeight(.bold)

                            Spacer()

                            Button(action: exportImages) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("エクスポート")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }

                        // 券面画像情報
                        VStack(alignment: .leading, spacing: 8) {
                            Text("券面画像: \(cardData.frontImage.count) bytes (MMR/TIFF)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("顔写真: \(cardData.faceImage.count) bytes (JPEG2000)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color.white)
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                    .cornerRadius(16)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                    // 電子署名表示エリア
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("電子署名データ")
                                .font(.headline)
                                .fontWeight(.bold)

                            Spacer()

                            Button(action: {
                                copySignatureData()
                            }) {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                    Text("コピー")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }

                        // 署名データのサマリー表示
                        ScrollView {
                            Text("署名データ: \(cardData.signature.count) bytes")
                                .font(.system(.footnote, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color.white)
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .cornerRadius(8)
                        }
                        .frame(height: 100)
                    }
                    .padding()
                    .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                    .cornerRadius(16)
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)

                    // 操作ボタン
                    VStack(spacing: 12) {
                        // 戻るボタン
                        Button(action: {
                            // データをクリアしてから画面を閉じる
                            dataManager.clearData()
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Text("メイン画面に戻る")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()

                                Image(systemName: "arrow.left.circle.fill")
                                    .font(.headline)
                            }
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingExportSheet) {
            if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let frontImageURL = documentsDirectory.appendingPathComponent("residence_card_front.tiff")
                let faceImageURL = documentsDirectory.appendingPathComponent("residence_card_face.jp2")
                ShareSheet(activityItems: [frontImageURL, faceImageURL])
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    // 画像エクスポート処理
    private func exportImages() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            showError(title: "エラー", message: "ドキュメントディレクトリにアクセスできません")
            return
        }
        
        do {
            // 券面画像を保存（TIFF形式）
            let frontImageURL = documentsDirectory.appendingPathComponent("residence_card_front.tiff")
            try cardData.frontImage.write(to: frontImageURL)
            
            // 顔写真を保存（JPEG2000形式）
            let faceImageURL = documentsDirectory.appendingPathComponent("residence_card_face.jp2")
            try cardData.faceImage.write(to: faceImageURL)
            
            showingExportSheet = true
        } catch {
            showError(title: "エクスポートエラー", message: "画像の保存に失敗しました: \(error.localizedDescription)")
        }
    }
    
    // 署名データをコピー
    private func copySignatureData() {
        let signatureHex = cardData.signature.map { String(format: "%02X", $0) }.joined(separator: " ")
        UIPasteboard.general.string = signatureHex
        showError(title: "コピー完了", message: "電子署名データをクリップボードにコピーしました")
    }
    
    // カード種別文字列を解析
    private func parseCardTypeString(from data: Data) -> String {
        if let typeValue = cardData.parseTLV(data: data, tag: 0xC1),
           let typeString = String(data: typeValue, encoding: .utf8) {
            switch typeString {
            case "1":
                return "在留カード"
            case "2":
                return "特別永住者証明書"
            default:
                return "不明なカード種別: \(typeString)"
            }
        }
        return "カード種別情報なし"
    }
    
    // 住所データを解析
    private func parseAddressData(from data: Data) -> String? {
        // TLVから住所データを取得
        if let addressData = cardData.parseTLV(data: data, tag: 0x11),
           let addressString = String(data: addressData, encoding: .utf8) {
            return addressString
        }
        return nil
    }
    
    // 許可データを解析
    private func parsePermissionData(from data: Data) -> String? {
        // TLVから許可データを取得
        if let permissionData = cardData.parseTLV(data: data, tag: 0x12),
           let permissionString = String(data: permissionData, encoding: .utf8) {
            return permissionString
        }
        return nil
    }
    
    private func showError(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }
}


#Preview {
    // サンプルデータでプレビュー
    let sampleData = ResidenceCardData(
        commonData: Data([0xC0, 0x04, 0x01, 0x02, 0x03, 0x04]), // サンプル共通データ
        cardType: Data([0xC1, 0x01, 0x31]), // "1" = 在留カード
        frontImage: Data(repeating: 0x00, count: 1000), // サンプル券面画像
        faceImage: Data(repeating: 0x00, count: 500),   // サンプル顔写真
        address: Data([0x11, 0x10, 0x6A, 0x65, 0x6E, 0x6B, 0x69, 0x6E, 0x73, 0x20, 0x61, 0x64, 0x64, 0x72, 0x65, 0x73, 0x73]), // サンプル住所
        additionalData: ResidenceCardData.AdditionalData(
            comprehensivePermission: Data([0x12, 0x04, 0x70, 0x65, 0x72, 0x6D]), // "perm"
            individualPermission: Data([0x12, 0x04, 0x69, 0x6E, 0x64, 0x76]), // "indv"
            extensionApplication: Data([0x12, 0x04, 0x65, 0x78, 0x74, 0x6E])  // "extn"
        ),
        signature: Data(repeating: 0xFF, count: 256) // サンプル署名
    )
    
    ResidenceCardDetailView(cardData: sampleData)
}