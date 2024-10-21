//
//  FeatureSettingsView.swift
//  FreeAPS
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct DevicesView: BaseView {
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
                header: Text("Setup & Configuraton"),
                content: {
                    Text("Insulin Pump").navigationLink(to: .pumpConfig, from: self)
                    Text("Continuous Glucose Monitor").navigationLink(to: .cgm, from: self)
                    Text("Smart Watch").navigationLink(to: .watch, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden).background(color)
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.automatic)
    }
}