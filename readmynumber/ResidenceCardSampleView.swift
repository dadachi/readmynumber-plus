//
//  ResidenceCardSampleView.swift
//  readmynumber
//
//  Created by Claude Code on 2025/08/16.
//

import SwiftUI

struct ResidenceCardSampleView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 20) {
                    // Segmented Control for front/back
                    Picker("表示面", selection: $selectedTab) {
                        Text("表面").tag(0)
                        Text("裏面").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    TabView(selection: $selectedTab) {
                        // Front side
                        VStack(spacing: 15) {
                            Text("在留カード（表面）")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Image("front_image")
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: geometry.size.height * 0.5)
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("読み取り可能な情報")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    Label("氏名", systemImage: "person")
                                    Label("生年月日", systemImage: "calendar")
                                    Label("性別", systemImage: "person.2")
                                    Label("国籍・地域", systemImage: "globe")
                                    Label("住居地", systemImage: "house")
                                    Label("在留資格", systemImage: "doc.text")
                                    Label("在留期間", systemImage: "clock")
                                    Label("在留カード番号", systemImage: "number")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                        .tag(0)
                        
                        // Back side
                        VStack(spacing: 15) {
                            Text("在留カード（裏面）")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            // Placeholder for back image
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.2))
                                .frame(maxHeight: geometry.size.height * 0.5)
                                .overlay(
                                    VStack(spacing: 20) {
                                        Image(systemName: "creditcard.fill")
                                            .font(.system(size: 60))
                                            .foregroundColor(.gray)
                                        Text("裏面イメージ")
                                            .foregroundColor(.gray)
                                    }
                                )
                                .padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("裏面の情報")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    Label("資格外活動許可欄", systemImage: "doc.badge.plus")
                                    Label("在留期間更新許可申請欄", systemImage: "arrow.clockwise")
                                    Label("住居地記載欄（変更時）", systemImage: "house.fill")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }
                        .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    
                    Spacer()
                    
                    // Notice
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("実際の在留カードをNFC機能で読み取ります")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("在留カードサンプル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ResidenceCardSampleView()
}