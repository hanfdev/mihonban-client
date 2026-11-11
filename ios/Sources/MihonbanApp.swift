import SwiftUI

@main
struct MihonbanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .modifier(AppAppearance())
                .tint(Theme.accent)
                .foregroundStyle(Theme.ink)
                .font(Theme.body())
                .task { await model.bootstrap() }
                .onChange(of: phase) { _, value in
                    model.player.setForeground(value == .active)
                    if value == .active { Task { await model.refresh() } }
                }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    // An authorized snapshot is ready to browse while its refresh continues.
    // Authentication and an empty first load still use the startup surface.
    var showsStartupBrand: Bool {
        model.isBootstrapping && !(model.signedIn && !model.catalog.index.albums.isEmpty)
    }

    var body: some View {
        Group {
            if showsStartupBrand { StartupBrandView() }
            else if model.signedIn {
                CatalogShell(model: model).id(model.sessionStore.authorizationRevision)
            }
            else { ConnectionView(model: model) }
        }
        .background(Theme.background)
    }
}

struct StartupBrandView: View {
    var body: some View {
        GeometryReader { geometry in
            let shortestSide = min(geometry.size.width, geometry.size.height)
            let size: CGFloat = UIDevice.current.userInterfaceIdiom == .pad
                ? min(180, max(104, shortestSide * 0.22)) : 104
            Image("Logo").resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size / 4, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "見本盤"))
        .accessibilityValue(Text(L10n.text("common.loading")))
        .accessibilityIdentifier("connection.restoring")
    }
}

struct ConnectionView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Image("Logo").resizable().scaledToFit().frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityHidden(true)
                    Text("見本盤").displayFont(44)
                    Text(L10n.text("mobile.connectHint")).foregroundStyle(Theme.dim)
                }.padding(.bottom, 12)
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("mobile.address")).foregroundStyle(Theme.dim)
                        TextField(L10n.text("mobile.address"), text: $model.address,
                                  prompt: Text(verbatim: "https://music.example.com").foregroundStyle(Theme.dim))
                            .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never)
                            .autocorrectionDisabled().accessibilityIdentifier("connection.address")
                            .padding(14).background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("login.password")).foregroundStyle(Theme.dim)
                        SecureField(L10n.text("login.password"), text: $model.password,
                                    prompt: Text(L10n.text("mobile.optionalPassword")).foregroundStyle(Theme.dim))
                            .textContentType(.password).accessibilityIdentifier("connection.password")
                            .padding(14).background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Toggle(L10n.text("mobile.remember"), isOn: $model.rememberPassword)
                        .font(Theme.body(13)).tint(Theme.accent)
                    if model.address.lowercased().hasPrefix("http://") {
                        Label(L10n.text("mobile.insecureHTTP"), systemImage: "lock.open")
                            .font(Theme.body(13)).foregroundStyle(Theme.dim)
                    }
                }
                if let error = model.error ?? (model.sessionStore.needsSignIn ? L10n.text("mobile.sessionExpired") : nil) {
                    Text(error).foregroundStyle(Theme.accent).font(Theme.body(14))
                }
                Button { Task { await model.connect() } } label: {
                    HStack {
                        if model.connecting { ProgressView().tint(Theme.onAccent) }
                        Text(L10n.text(model.connecting ? "mobile.connecting" : "mobile.connect"))
                    }.font(Theme.body(16, weight: .semibold)).frame(maxWidth: .infinity).frame(minHeight: 52)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.onAccent).background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                .disabled(model.connecting || model.address.isEmpty).accessibilityIdentifier("connection.connect")
                .opacity(model.connecting || model.address.isEmpty ? 0.55 : 1)
            }.padding(28).frame(maxWidth: 500).frame(maxWidth: .infinity).padding(.top, 42)
        }.background(Theme.background).scrollDismissesKeyboard(.interactively)
    }
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisconnect = false
    @State private var clearMessage: String?
    @State private var clearing = false
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    private var usage: CacheUsage { model.media?.usage ?? CacheUsage() }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    private var roleName: String {
        switch model.session?.role ?? "" {
        case "admin": L10n.text("login.roleAdmin")
        case "user" where model.session?.guest == true: L10n.text("login.roleGuest")
        default: L10n.text("login.roleListener")
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.text("mobile.appearance")) {
                    Picker(L10n.text("mobile.appearance"), selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.rawValue) { Text(L10n.text($0.label)).tag($0.rawValue) }
                    }.accessibilityIdentifier("settings.appearance")
                }.listRowBackground(Theme.surface)
                Section(L10n.text("mobile.connection")) {
                    Text(model.demo ? "Demo" : model.address).font(Theme.body(14)).textSelection(.enabled)
                    LabeledContent(L10n.text("login.menuTitle"), value: roleName)
                    Button(L10n.text("login.signOut"), role: .destructive) { confirmDisconnect = true }
                        .accessibilityIdentifier("settings.signOut")
                }.listRowBackground(Theme.surface)
                Section {
                    Toggle(L10n.text("mobile.cacheEnable"), isOn: $model.cache.enabled)
                    Picker(L10n.text("mobile.cacheLimit"), selection: $model.cache.limitBytes) {
                        ForEach(CacheSettings.limits, id: \.self) { Text(CacheSettings.label($0)).tag($0) }
                    }.disabled(!model.cache.enabled)
                    LabeledContent(L10n.text("mobile.cacheUsed"), value: CacheSettings.size(usage.cached))
                        .accessibilityIdentifier("cache.used")
                    if usage.cached > 0 || usage.buffering > 0 {
                        Group {
                            LabeledContent(L10n.text("mobile.cacheAudio"), value: CacheSettings.size(usage.audio))
                            LabeledContent(L10n.text("mobile.cacheCovers"), value: CacheSettings.size(usage.artwork))
                            if usage.buffering > 0 {
                                LabeledContent(L10n.text("mobile.cacheBuffer"), value: CacheSettings.size(usage.buffering))
                            }
                        }.font(Theme.body(15)).foregroundStyle(.secondary)
                    }
                    if let clearMessage {
                        Text(clearMessage).font(Theme.body(13)).foregroundStyle(Theme.dim)
                    }
                    Button(L10n.text("mobile.clearCache"), role: .destructive) {
                        clearing = true
                        Task {
                            let ok = await model.clearCache()
                            clearMessage = L10n.text(ok ? "mobile.cacheCleared" : "mobile.cacheClearFailed")
                            clearing = false
                        }
                    }.disabled(clearing).accessibilityIdentifier("cache.clear")
                } header: { Text(L10n.text("mobile.cache")) } footer: {
                    Text(L10n.text(model.cache.enabled ? "mobile.cacheHint" : "mobile.cacheOffNotice"))
                }.listRowBackground(Theme.surface)
                if let downloads = model.downloads {
                    Section {
                        NavigationLink {
                            DownloadsView(model: model, downloads: downloads)
                        } label: {
                            LabeledContent(L10n.text("mobile.downloads"), value: CacheSettings.size(Int(downloads.totalBytes)))
                        }.accessibilityIdentifier("downloads.open")
                    } footer: { Text(L10n.text("mobile.downloadsHint")) }.listRowBackground(Theme.surface)
                }
                Section {
                    Picker(L10n.text("mobile.preloadNext"), selection: $model.cache.preloadPolicy) {
                        ForEach(PreloadPolicy.allCases, id: \.self) { Text(L10n.text($0.label)).tag($0) }
                    }.accessibilityIdentifier("settings.preload")
                    Text(L10n.text("mobile.preloadHint"))
                    Text("Mihonban " + version).foregroundStyle(Theme.faint)
                }.font(Theme.body(14)).listRowBackground(Theme.surface)
                Section {
                    NavigationLink(L10n.text("mobile.licenses")) { LicenseView() }
                }.listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden).background(Theme.background)
            .accessibilityIdentifier("settings.content")
            .accessibilityValue(L10n.text(colorScheme == .dark ? "mobile.appearanceDark" : "mobile.appearanceLight"))
            .navigationTitle(L10n.text("mobile.settings")).navigationBarTitleDisplayMode(.inline)
            .task { await model.media?.refreshUsage() }
            .onChange(of: model.cache.enabled) { model.cacheSettingsChanged() }
            .onChange(of: model.cache.limitBytes) { model.cacheSettingsChanged() }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("common.done")) { dismiss() } } }
            .confirmationDialog(L10n.text("mobile.disconnectConfirm"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button(L10n.text("login.signOut"), role: .destructive) { dismiss(); model.disconnect() }
                    .accessibilityIdentifier("settings.signOutConfirm")
            }
        }.tint(Theme.accent)
    }
}

struct LicenseView: View {
    private var licenses: String {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "SFBAudioEngine · sbooth/SFBAudioEngine\nShippori Mincho · SIL Open Font License\nInter · SIL Open Font License" }
        return text
    }
    var body: some View {
        ScrollView { Text(licenses).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(20) }
            .background(Theme.background).navigationTitle(L10n.text("mobile.licenses"))
    }
}
