//
//  FeatureSettingsView.swift
//  FreeAPS
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct FeatureSettingsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    var color: LinearGradient {
        colorScheme == .dark ? LinearGradient(
            gradient: Gradient(colors: [
                Color.bgDarkBlue,
                Color.bgDarkerDarkBlue
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
            :
            LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                startPoint: .top,
                endPoint: .bottom
            )
    }

    var body: some View {
        Form {
            Section(
                header: Text("Trio Features"),
                content: {
                    Text("Bolus Calculator").navigationLink(to: .bolusCalculatorConfig, from: self)
                    Text("Meal Settings").navigationLink(to: .mealSettings, from: self)
                    Text("Shortcuts").navigationLink(to: .shortcutsConfig, from: self)
                }
            )
            .listRowBackground(Color.chart)

            Section(
                header: Text("Trio Personalization"),
                content: {
                    Text("User Interface").navigationLink(to: .userInterfaceSettings, from: self)
                    Text("App Icons").navigationLink(to: .iconConfig, from: self)
                }
            )
            .listRowBackground(Color.chart)

            Section(
                header: Text("Data-Driven Settings Tuning"),
                content: {
                    Text("Autotune").navigationLink(to: .autotuneConfig, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden).background(color)
        .navigationTitle("Feature Settings")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
