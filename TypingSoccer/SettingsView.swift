//
//  SettingsView.swift
//  TypingSoccer
//
//  Settings screen: language (English / Bahasa Indonesia), master audio
//  volume, and larger in-game text. Values persist via SettingsStore.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var coordinator: GameCoordinator
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 26) {
            ZStack {
                Text(L("settings.title"))
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(red: 238/255, green: 170/255, blue: 82/255))
                HStack { BackButton(); Spacer() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 34) {
                // Language
                settingRow(L("settings.language")) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }

                // Audio volume
                settingRow(L("settings.audio")) {
                    HStack(spacing: 10) {
                        Image(systemName: settings.audioVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(.white.opacity(0.7))
                        Slider(value: $settings.audioVolume, in: 0...1)
                            .frame(width: 320)
                    }
                }

                // Text size (applies to the in-game word prompt + HUD)
                settingRow(L("settings.textSize")) {
                    HStack(spacing: 10) {
                        Text("A")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                        Slider(value: $settings.textScale, in: 1.0...1.5, step: 0.125)
                            .frame(width: 300)
                        Text("A")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 46)
            .frame(width: 720)
            .background(Color(red: 109/255, green: 112/255, blue: 116/255).opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Spacer()
        }
    }

    private func settingRow<Content: View>(_ label: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            content()
        }
    }
}
