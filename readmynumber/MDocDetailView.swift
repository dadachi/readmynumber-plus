//
//  MDocDetailView.swift
//  readmynumber
//
//  M-Doc Detail Display View
//

import SwiftUI
import UIKit

struct MDocDetailView: View {
    let document: MDocParser.ParsedDocument
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @State private var showingExportSheet = false
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.white, Color(UIColor.systemGray6)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Document Type Header
                        DocumentHeaderView(document: document)
                            .padding(.top, 20)
                        
                        // Tab Selection
                        Picker("", selection: $selectedTab) {
                            Text("基本情報").tag(0)
                            Text("文書情報").tag(1)
                            if document.drivingPrivileges != nil {
                                Text("運転免許").tag(2)
                            }
                            if document.biometricData != nil {
                                Text("生体情報").tag(3)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        
                        // Content based on selected tab
                        switch selectedTab {
                        case 0:
                            PersonalInfoSection(personalInfo: document.personalInfo)
                        case 1:
                            DocumentInfoSection(
                                documentInfo: document.documentInfo,
                                issuerInfo: document.issuerInfo
                            )
                        case 2:
                            if let privileges = document.drivingPrivileges {
                                DrivingPrivilegesSection(privileges: privileges)
                            }
                        case 3:
                            if let biometric = document.biometricData {
                                BiometricSection(biometricData: biometric)
                            }
                        default:
                            EmptyView()
                        }
                        
                        // Additional Data
                        if !document.additionalData.isEmpty {
                            AdditionalDataSection(data: document.additionalData)
                        }
                        
                        // Export Button
                        Button(action: exportDocument) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("データをエクスポート")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle(getDocumentTypeName())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(activityItems: [generateExportData()])
        }
    }
    
    private func getDocumentTypeName() -> String {
        switch document.docType {
        case MobileDrivingLicense.docType:
            return "モバイル運転免許証"
        default:
            return "M-Doc"
        }
    }
    
    private func exportDocument() {
        showingExportSheet = true
    }
    
    private func generateExportData() -> String {
        var exportString = "=== M-Doc データ ===\n\n"
        
        // Personal Info
        exportString += "【個人情報】\n"
        exportString += "氏名: \(document.personalInfo.familyName) \(document.personalInfo.givenName)\n"
        exportString += "生年月日: \(MDocParser.formatDate(document.personalInfo.birthDate))\n"
        
        if let sex = document.personalInfo.sex {
            exportString += "性別: \(sex)\n"
        }
        
        // Document Info
        exportString += "\n【文書情報】\n"
        exportString += "文書番号: \(document.documentInfo.documentNumber)\n"
        exportString += "発行日: \(MDocParser.formatDate(document.documentInfo.issueDate))\n"
        exportString += "有効期限: \(MDocParser.formatDate(document.documentInfo.expiryDate))\n"
        
        // Issuer Info
        exportString += "\n【発行者情報】\n"
        exportString += "発行国: \(document.issuerInfo.issuingCountry)\n"
        exportString += "発行機関: \(document.issuerInfo.issuingAuthority)\n"
        
        return exportString
    }
}

// MARK: - Sub Views

struct DocumentHeaderView: View {
    let document: MDocParser.ParsedDocument
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: getDocumentIcon())
                .font(.system(size: 60))
                .foregroundColor(.purple)
                .symbolRenderingMode(.hierarchical)
            
            Text("\(document.personalInfo.familyName) \(document.personalInfo.givenName)")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack {
                if MDocParser.isExpired(document.documentInfo.expiryDate) {
                    Label("期限切れ", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Label("有効", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                Text("有効期限: \(MDocParser.formatDate(document.documentInfo.expiryDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
    
    private func getDocumentIcon() -> String {
        switch document.docType {
        case MobileDrivingLicense.docType:
            return "car.fill"
        default:
            return "doc.text.fill"
        }
    }
}

struct PersonalInfoSection: View {
    let personalInfo: MDocParser.PersonalInfo
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "個人情報", systemImage: "person.fill")
            
            VStack(spacing: 12) {
                InfoRow(label: "氏名", value: "\(personalInfo.familyName) \(personalInfo.givenName)")
                InfoRow(label: "生年月日", value: MDocParser.formatDate(personalInfo.birthDate))
                InfoRow(label: "年齢", value: "\(MDocParser.calculateAge(from: personalInfo.birthDate))歳")
                
                if let sex = personalInfo.sex {
                    InfoRow(label: "性別", value: sex)
                }
                
                if let nationality = personalInfo.nationality {
                    InfoRow(label: "国籍", value: nationality)
                }
                
                if let address = personalInfo.residentAddress {
                    InfoRow(label: "住所", value: address)
                }
                
                if let height = personalInfo.height {
                    InfoRow(label: "身長", value: "\(height)cm")
                }
                
                if let weight = personalInfo.weight {
                    InfoRow(label: "体重", value: "\(weight)kg")
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
}

struct DocumentInfoSection: View {
    let documentInfo: MDocParser.DocumentInfo
    let issuerInfo: MDocParser.IssuerInfo
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "文書情報", systemImage: "doc.text")
            
            VStack(spacing: 12) {
                InfoRow(label: "文書番号", value: documentInfo.documentNumber)
                InfoRow(label: "発行日", value: MDocParser.formatDate(documentInfo.issueDate))
                InfoRow(label: "有効期限", value: MDocParser.formatDate(documentInfo.expiryDate))
                
                if let adminNumber = documentInfo.administrativeNumber {
                    InfoRow(label: "管理番号", value: adminNumber)
                }
                
                Divider()
                
                InfoRow(label: "発行国", value: issuerInfo.issuingCountry)
                InfoRow(label: "発行機関", value: issuerInfo.issuingAuthority)
                
                if let jurisdiction = issuerInfo.issuingJurisdiction {
                    InfoRow(label: "管轄", value: jurisdiction)
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
}

struct DrivingPrivilegesSection: View {
    let privileges: [MDocParser.DrivingPrivilege]
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "運転免許情報", systemImage: "car.fill")
            
            ForEach(Array(privileges.enumerated()), id: \.offset) { index, privilege in
                VStack(alignment: .leading, spacing: 8) {
                    Text("車両カテゴリー: \(privilege.vehicleCategoryCode)")
                        .font(.headline)
                    
                    if let issueDate = privilege.issueDate {
                        Text("発行日: \(MDocParser.formatDate(issueDate))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let expiryDate = privilege.expiryDate {
                        Text("有効期限: \(MDocParser.formatDate(expiryDate))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let codes = privilege.codes, !codes.isEmpty {
                        let codesString = codes.joined(separator: ", ")
                        Text("制限コード: \(codesString)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
}

struct BiometricSection: View {
    let biometricData: MDocParser.BiometricData
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "生体情報", systemImage: "person.crop.square")
            
            VStack(spacing: 12) {
                if let portrait = biometricData.portrait {
                    VStack {
                        Text("顔写真")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(uiImage: portrait)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                        
                        if let captureDate = biometricData.portraitCaptureDate {
                            Text("撮影日: \(MDocParser.formatDate(captureDate))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let signature = biometricData.signatureOrUsualMark {
                    VStack {
                        Text("署名")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(uiImage: signature)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 100)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
}

struct AdditionalDataSection: View {
    let data: [String: String]
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeader(title: "追加情報", systemImage: "info.circle")
            
            VStack(spacing: 12) {
                ForEach(Array(data.keys.sorted()), id: \.self) { key in
                    InfoRow(label: formatKey(key), value: data[key] ?? "")
                }
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(UIColor.systemGray4) : Color.white)
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
    
    private func formatKey(_ key: String) -> String {
        return key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

struct SectionHeader: View {
    let title: String
    let systemImage: String
    
    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(.purple)
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
    }
}

#Preview {
    // Create sample parsed document for preview
    let sampleDocument = MDocParser.ParsedDocument(
        docType: MobileDrivingLicense.docType,
        issuerInfo: MDocParser.IssuerInfo(
            issuingCountry: "JP",
            issuingAuthority: "警視庁",
            issuingJurisdiction: "東京都"
        ),
        personalInfo: MDocParser.PersonalInfo(
            familyName: "山田",
            givenName: "太郎",
            birthDate: Date(timeIntervalSince1970: 631152000),
            sex: "男性",
            height: 170,
            weight: 65,
            eyeColor: "茶",
            hairColor: "黒",
            birthPlace: "東京都",
            nationality: "日本",
            residentAddress: "東京都千代田区霞が関1-1-1",
            residentCity: "千代田区",
            residentState: "東京都",
            residentPostalCode: "100-0013",
            residentCountry: "日本"
        ),
        documentInfo: MDocParser.DocumentInfo(
            documentNumber: "123456789",
            issueDate: Date(),
            expiryDate: Date().addingTimeInterval(365 * 24 * 60 * 60 * 5),
            administrativeNumber: "ADM123",
            unDistinguishingSign: "J"
        ),
        drivingPrivileges: [
            MDocParser.DrivingPrivilege(
                vehicleCategoryCode: "普通",
                issueDate: Date(),
                expiryDate: Date().addingTimeInterval(365 * 24 * 60 * 60 * 3),
                codes: ["AT限定"],
                sign: nil,
                value: nil
            )
        ],
        biometricData: nil,
        additionalData: ["age_over_18": "true", "age_over_21": "true"]
    )
    
    MDocDetailView(document: sampleDocument)
}