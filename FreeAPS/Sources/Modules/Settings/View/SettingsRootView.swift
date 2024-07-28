import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI
import Swinject

extension Settings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var showShareSheet = false

        @State private var searchText: String = ""

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons

        private var color: LinearGradient {
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
                let buildDetails = BuildDetails.default

                Section(
                    header: Text("BRANCH: \(buildDetails.branchAndSha)").textCase(nil),
                    content: {
                        let versionNumber = Bundle.main.releaseVersionNumber ?? "Unknown"
                        let buildNumber = Bundle.main.buildVersionNumber ?? "Unknown"

                        Group {
                            HStack {
                                Image(uiImage: UIImage(named: appIcons.appIcon.rawValue) ?? UIImage())
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 50, height: 50)
                                    .padding(.trailing, 10)
                                VStack(alignment: .leading) {
                                    Text("Trio v\(versionNumber) (\(buildNumber))")
                                        .font(.headline)
                                    if let expirationDate = buildDetails.calculateExpirationDate() {
                                        let formattedDate = DateFormatter.localizedString(
                                            from: expirationDate,
                                            dateStyle: .medium,
                                            timeStyle: .none
                                        )
                                        Text("\(buildDetails.expirationHeaderString): \(formattedDate)")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Simulator Build has no expiry")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Text("Statistics").navigationLink(to: .statistics, from: self)
                        }
                    }
                ).listRowBackground(Color.chart)

                Section(
                    header: Text("Automated Insulin Delivery"),
                    content: {
                        VStack {
                            Toggle("Closed Loop", isOn: $state.closedLoop)

                            Spacer()

                            (
                                Text("Running Trio in")
                                    +
                                    Text(" closed loop mode ").bold()
                                    +
                                    Text("requires an active CGM session sensor session and a connected pump.")
                                    +
                                    Text("This enables automated insulin delivery.").bold()
                            )
                            .foregroundColor(.secondary)
                            .font(.footnote)

                        }.padding(.vertical)
                    }
                ).listRowBackground(Color.chart)

                Section(
                    header: Text("Trio Configuration"),
                    content: {
                        Text("Devices").navigationLink(to: .devices, from: self)
                        Text("Therapy").navigationLink(to: .therapySettings, from: self)
                        Text("Algorithm").navigationLink(to: .algorithmSettings, from: self)
                        Text("Features").navigationLink(to: .featureSettings, from: self)
                        Text("Notifications").navigationLink(to: .notificationSettings, from: self)
                        Text("Services").navigationLink(to: .serviceSettings, from: self)
                    }
                ).listRowBackground(Color.chart)

                Section(
                    header: Text("Support & Community"),
                    content: {
                        HStack {
                            Text("Share Logs")
                                .onTapGesture {
                                    showShareSheet.toggle()
                                }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Submit Ticket on GitHub")
                                .onTapGesture {
                                    if let url = URL(string: "https://github.com/nightscout/Trio/issues/new/choose") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Trio Discord")
                                .onTapGesture {
                                    if let url = URL(string: "https://discord.gg/FnwFEFUwXE") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Trio Facebook")
                                .onTapGesture {
                                    if let url = URL(string: "https://m.facebook.com/groups/1351938092206709/") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                    }
                ).listRowBackground(Color.chart)

                // TODO: remove this more or less entirely; add build-time flag to enable Middleware; add settings export feature
//                Section {
//                    Toggle("Developer Options", isOn: $state.debugOptions)
//                    if state.debugOptions {
//                        Group {
//                            HStack {
//                                Text("NS Upload Profile and Settings")
//                                Button("Upload") { state.uploadProfileAndSettings(true) }
//                                    .frame(maxWidth: .infinity, alignment: .trailing)
//                                    .buttonStyle(.borderedProminent)
//                            }
//                            // Commenting this out for now, as not needed and possibly dangerous for users to be able to nuke their pump pairing informations via the debug menu
//                            // Leaving it in here, as it may be a handy functionality for further testing or developers.
//                            // See https://github.com/nightscout/Trio/pull/277 for more information
//                            //
//                            //                            HStack {
//                            //                                Text("Delete Stored Pump State Binary Files")
//                            //                                Button("Delete") { state.resetLoopDocuments() }
//                            //                                    .frame(maxWidth: .infinity, alignment: .trailing)
//                            //                                    .buttonStyle(.borderedProminent)
//                            //                            }
//                        }
//                        Group {
//                            Text("Preferences")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.preferences), from: self)
//                            Text("Pump Settings")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.settings), from: self)
//                            Text("Autosense")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autosense), from: self)
//                            //                            Text("Pump History")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.pumpHistory), from: self)
//                            Text("Basal profile")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.basalProfile), from: self)
//                            Text("Targets ranges")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.bgTargets), from: self)
//                            Text("Temp targets")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.tempTargets), from: self)
//                        }
//
//                        Group {
//                            Text("Pump profile")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.pumpProfile), from: self)
//                            Text("Profile")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.profile), from: self)
//                            //                            Text("Carbs")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.carbHistory), from: self)
//                            //                            Text("Announcements")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcements), from: self)
//                            //                            Text("Enacted announcements")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcementsEnacted), from: self)
//                            Text("Autotune")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autotune), from: self)
//                        }
//
//                        Group {
//                            Text("Target presets")
//                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.tempTargetsPresets), from: self)
//                            Text("Calibrations")
//                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.calibrations), from: self)
//                            Text("Middleware")
//                                .navigationLink(to: .configEditor(file: OpenAPS.Middleware.determineBasal), from: self)
//                            //                            Text("Statistics")
//                            //                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.statistics), from: self)
//                            Text("Edit settings json")
//                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.settings), from: self)
//                        }
//                    }
//                }.listRowBackground(Color.chart)

            }.scrollContentBackground(.hidden).background(color)
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(activityItems: state.logItems())
                }
                .onAppear(perform: configureView)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.automatic)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            action: {
                                if let url = URL(string: "https://triodocs.org/") {
                                    UIApplication.shared.open(url)
                                }
                            },
                            label: {
                                HStack {
                                    Text("Trio Docs")
                                    Image(systemName: "questionmark.circle")
                                }
                            }
                        )
                    }
                }
                // TODO: check how to implement intuitive search
//                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
                .onDisappear(perform: { state.uploadProfileAndSettings(false) })
                .screenNavigation(self)
        }
    }
}
