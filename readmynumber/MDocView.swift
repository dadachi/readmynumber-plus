//
//  MDocView.swift
//  readmynumber
//

import SwiftUI
import CoreNFC
import AVFoundation
import CoreBluetooth

struct MDocView: View {
    @StateObject private var mdocReader = MDocReader()
    @State private var showAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showDocumentDetail = false
    @State private var parsedDocument: MDocParser.ParsedDocument?
    @State private var selectedReadingMethod: ReadingMethod = .qrCode
    @Environment(\.colorScheme) var colorScheme
    
    enum ReadingMethod {
        case qrCode
        case nfc
        case bluetooth
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [Color.white, Color(UIColor.systemGray6)]),
                                   startPoint: .top,
                                   endPoint: .bottom)
                        .ignoresSafeArea()

                    VStack(spacing: geometry.size.height * 0.03) {
                        // Logo and Title
                        VStack(spacing: geometry.size.height * 0.015) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.13, weight: .regular))
                                .foregroundColor(.purple)
                                .symbolRenderingMode(.hierarchical)

                            Text("M-Doc読み取り")
                                .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.06, weight: .bold))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, geometry.size.height * 0.006)
                        .padding(.bottom, geometry.size.height * 0.03)

                        // M-Doc Information Section
                        VStack(alignment: .leading, spacing: geometry.size.height * 0.02) {
                            HStack {
                                Text("Mobile Document (M-Doc)")
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Spacer()

                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                                    .foregroundColor(.purple)
                            }

                            Text("ISO/IEC 18013-5準拠のモバイル文書フォーマットに対応しています。デジタル身分証明書やモバイル運転免許証などを読み取ることができます。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Supported Standards
                            VStack(alignment: .leading, spacing: 8) {
                                Label("ISO/IEC 18013-5 (mDL)", systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundColor(.green)
                                
                                Label("ISO/IEC 23220 (モバイルeID)", systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundColor(.green)
                                
                                Label("NFC & QRコード両対応", systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundColor(.green)
                            }
                            .padding()
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)

                            // Reading Method Selection
                            HStack {
                                Text("読み取り方法:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Picker("", selection: $selectedReadingMethod) {
                                    Label("QRコード", systemImage: "qrcode").tag(ReadingMethod.qrCode)
                                    Label("NFC", systemImage: "wave.3.right").tag(ReadingMethod.nfc)
                                    Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right").tag(ReadingMethod.bluetooth)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                            }
                            .padding(.vertical, 8)
                            
                            Button(action: {
                                startMDocReading()
                            }) {
                                HStack {
                                    Spacer()
                                    Text("M-Docを読み取る")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    Spacer()

                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.headline)
                                }
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .shadow(color: Color.purple.opacity(colorScheme == .dark ? 0.5 : 0.3), radius: 5, x: 0, y: 3)
                        }
                        .padding(min(geometry.size.width, geometry.size.height) * 0.05)
                        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                        .cornerRadius(16)
                        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .frame(width: geometry.size.width * 0.9)

                        // Information Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("対応文書タイプ")
                                .font(.headline)
                                .padding(.bottom, 5)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "car.fill")
                                        .foregroundColor(.blue)
                                    Text("モバイル運転免許証 (mDL)")
                                        .font(.subheadline)
                                }
                                
                                HStack {
                                    Image(systemName: "person.text.rectangle")
                                        .foregroundColor(.green)
                                    Text("デジタル身分証明書")
                                        .font(.subheadline)
                                }
                                
                                HStack {
                                    Image(systemName: "building.2.fill")
                                        .foregroundColor(.orange)
                                    Text("デジタル社員証")
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(min(geometry.size.width, geometry.size.height) * 0.05)
                        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                        .cornerRadius(16)
                        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .frame(width: geometry.size.width * 0.9)

                        // Footer
                        Text("© 2025 Meikenn")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, geometry.size.height * 0.01)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)

                    if mdocReader.isReading {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                        ProgressView("M-Doc読み取り中...")
                            .padding()
                            .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
                            .cornerRadius(10)
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .sheet(isPresented: $showDocumentDetail) {
                if let document = parsedDocument {
                    MDocDetailView(document: document)
                }
            }
        }
    }
    
    private func startMDocReading() {
        switch selectedReadingMethod {
        case .qrCode:
            startQRCodeReading()
        case .nfc:
            startNFCReading()
        case .bluetooth:
            startBluetoothReading()
        }
    }
    
    private func startQRCodeReading() {
        mdocReader.startQRCodeReading { result in
            switch result {
            case .success(let deviceEngagement):
                // QRコード読み取り成功後、BLE接続を開始
                mdocReader.connectBLE(with: deviceEngagement)
                requestMDocData()
            case .failure(let error):
                showError(title: "QRコード読み取りエラー", message: error.localizedDescription)
            }
        }
    }
    
    private func startNFCReading() {
        guard NFCTagReaderSession.readingAvailable else {
            showError(title: "NFC利用不可", message: "このデバイスはNFC読み取りに対応していません")
            return
        }
        
        mdocReader.startNFCReading()
        observeReaderStatus()
    }
    
    private func startBluetoothReading() {
        // Simulate device engagement for BLE direct connection
        mdocReader.startQRCodeReading { result in
            switch result {
            case .success(let deviceEngagement):
                mdocReader.connectBLE(with: deviceEngagement)
                requestMDocData()
            case .failure(let error):
                showError(title: "Bluetooth接続エラー", message: error.localizedDescription)
            }
        }
    }
    
    private func requestMDocData() {
        // Request mobile driver's license data
        let request = mdocReader.requestDataElements(
            docType: MobileDrivingLicense.docType,
            elements: [
                MobileDrivingLicense.isoMdlNamespace: [
                    "family_name", "given_name", "birth_date",
                    "document_number", "issue_date", "expiry_date",
                    "issuing_country", "issuing_authority",
                    "portrait", "driving_privileges"
                ]
            ]
        )
        
        mdocReader.sendRequest(request) { result in
            switch result {
            case .success(let response):
                if let document = response.documents?.first {
                    processReceivedDocument(document)
                }
            case .failure(let error):
                showError(title: "データ取得エラー", message: error.localizedDescription)
            }
        }
    }
    
    private func processReceivedDocument(_ document: Document) {
        if let parsed = MDocParser.parse(document) {
            self.parsedDocument = parsed
            self.showDocumentDetail = true
        } else {
            showError(title: "解析エラー", message: "M-Docデータの解析に失敗しました")
        }
    }
    
    private func observeReaderStatus() {
        // Observe reader status changes
        switch mdocReader.connectionStatus {
        case .completed:
            if let document = mdocReader.receivedDocument {
                processReceivedDocument(document)
            }
        case .failed(let error):
            showError(title: "読み取りエラー", message: error.localizedDescription)
        default:
            break
        }
    }
    
    private func showError(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.showAlert = true
    }
}

#Preview {
    MDocView()
}