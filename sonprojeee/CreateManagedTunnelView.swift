import SwiftUI
import AppKit // For FileManager

struct CreateManagedTunnelView: View {
    @EnvironmentObject var tunnelManager: TunnelManager
    @Environment(\.dismiss) var dismiss // Use standard dismiss

    // Form State
    @State private var tunnelName: String = ""
    @State private var configName: String = ""
    @State private var hostname: String = ""
    @State private var portString: String = "80" // Default to 80
    @State private var documentRoot: String = ""
    @State private var updateVHost: Bool = false

    // UI State
    @State private var isCreating: Bool = false
    @State private var creationStatus: String = ""
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var showSuccessAlert: Bool = false
    @State private var successMessage: String = ""

    // Validation computed property
    var isFormValid: Bool {
         !tunnelName.isEmpty && tunnelName.rangeOfCharacter(from: .whitespacesAndNewlines) == nil &&
         !configName.isEmpty && configName.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:")) == nil &&
         !hostname.isEmpty && hostname.contains(".") && hostname.rangeOfCharacter(from: .whitespacesAndNewlines) == nil &&
         !portString.isEmpty && Int(portString) != nil && (1...65535).contains(Int(portString)!) &&
         (!updateVHost || (!documentRoot.isEmpty && FileManager.default.fileExists(atPath: documentRoot))) // If updateVHost, docRoot must exist
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Yeni Yönetilen Tünel Oluştur")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)

            // Main Content
            VStack(spacing: 16) {
                // Tunnel Details Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tünel Detayları")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        FormField(label: "Tünel Adı", text: $tunnelName, placeholder: "Cloudflare'deki Ad (boşluksuz)")
                            .onChange(of: tunnelName) { syncConfigName() }
                        
                        FormField(label: "Config Adı", text: $configName, placeholder: "Yerel .yml Dosya Adı")
                        
                        FormField(label: "Hostname", text: $hostname, placeholder: "Erişilecek Alan Adı")
                        
                        HStack {
                            Text("Yerel Port")
                                .frame(width: 100, alignment: .trailing)
                            TextField("Port", text: $portString)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                                .onChange(of: portString) { newValue in
                                    let filtered = newValue.filter { "0123456789".contains($0) }
                                    let clamped = String(filtered.prefix(5))
                                    if clamped != newValue {
                                        DispatchQueue.main.async { portString = clamped }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }

                Divider()
                    .padding(.horizontal)

                // MAMP Integration Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "link.circle.fill")
                            .foregroundColor(.blue)
                        Text("MAMP Entegrasyonu")
                            .font(.headline)
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Proje Kökü")
                                .frame(width: 100, alignment: .trailing)
                            TextField("MAMP site klasörü", text: $documentRoot)
                                .textFieldStyle(.roundedBorder)
                            Button(action: browseForDocumentRoot) {
                                Image(systemName: "folder")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.bordered)
                            .help("Proje kök dizinini seç")
                        }

                        Toggle("MAMP Apache vHost Dosyasını Güncelle", isOn: $updateVHost)
                            .padding(.leading, 105)
                            .disabled(documentRoot.isEmpty || !FileManager.default.fileExists(atPath: documentRoot))

                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Proje kökü geçerliyse ve seçilirse, httpd-vhosts.conf dosyasına giriş eklemeyi dener. MAMP'ın yeniden başlatılması gerekir.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 105)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)

            // Status/Progress Area
            if isCreating {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(creationStatus)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            Divider()

            // Action Buttons
            HStack {
                Button("İptal") {
                    if !isCreating { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: startCreationProcess) {
                    HStack {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Oluştur")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || !isFormValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            portString = "\(tunnelManager.defaultMampPort)" // Set default MAMP port
        }
        .alert("Hata", isPresented: $showErrorAlert) {
            Button("Tamam") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Başarılı", isPresented: $showSuccessAlert) {
            Button("Harika!") { dismiss() }
        } message: {
            Text(successMessage)
        }
    }

    // Helper Views
    private struct FormField: View {
        let label: String
        @Binding var text: String
        let placeholder: String
        
        var body: some View {
            HStack {
                Text(label)
                    .frame(width: 100, alignment: .trailing)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // Sync config name with tunnel name initially
    private func syncConfigName() {
         if configName.isEmpty && !tunnelName.isEmpty {
             var safeName = tunnelName.replacingOccurrences(of: " ", with: "-").lowercased()
             safeName = safeName.filter { "abcdefghijklmnopqrstuvwxyz0123456789-_".contains($0) }
             configName = safeName
         }
    }

    func browseForDocumentRoot() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.message = "Lütfen MAMP Proje Kök Dizinini Seçin"
        if !documentRoot.isEmpty && FileManager.default.fileExists(atPath: documentRoot) { panel.directoryURL = URL(fileURLWithPath: documentRoot) }
        else if FileManager.default.fileExists(atPath: tunnelManager.mampSitesDirectoryPath) { panel.directoryURL = URL(fileURLWithPath: tunnelManager.mampSitesDirectoryPath) }

        panel.begin { response in
            if response == .OK, let url = panel.url { DispatchQueue.main.async { self.documentRoot = url.path } }
        }
    }

    private func startCreationProcess() {
        guard isFormValid else { /* Build specific error message based on invalid fields */
             errorMessage = "Lütfen tüm gerekli alanları doğru doldurun."
             // Add specific checks for better feedback (optional)
             showErrorAlert = true; return
        }
        guard let portIntValue = Int(portString), (1...65535).contains(portIntValue) else {
             errorMessage = "Geçersiz port numarası."; showErrorAlert = true; return
        }

        isCreating = true
        creationStatus = "'\(tunnelName)' tüneli Cloudflare'da oluşturuluyor..."

        // Step 1: Create the tunnel on Cloudflare
        tunnelManager.createTunnel(name: tunnelName) { createResult in
            DispatchQueue.main.async {
                switch createResult {
                case .success(let tunnelData):
                    creationStatus = "Yapılandırma dosyası '\(configName).yml' oluşturuluyor..."
                    let finalDocRoot = (self.updateVHost && !self.documentRoot.isEmpty && FileManager.default.fileExists(atPath: self.documentRoot)) ? self.documentRoot : nil

                    // Step 2: Create the local config file & potentially update MAMP
                    tunnelManager.createConfigFile(configName: self.configName, tunnelUUID: tunnelData.uuid, credentialsPath: tunnelData.jsonPath, hostname: self.hostname, port: self.portString, documentRoot: finalDocRoot) { configResult in
                        DispatchQueue.main.async {
                            switch configResult {
                            case .success(let configPath):
                                isCreating = false
                                successMessage = "Tünel '\(tunnelName)' ve yapılandırma '\((configPath as NSString).lastPathComponent)' başarıyla oluşturuldu."
                                if finalDocRoot != nil { successMessage += "\n\nMAMP vHost dosyası güncellenmeye çalışıldı. MAMP sunucularını yeniden başlatmanız gerekebilir." }
                                showSuccessAlert = true // Trigger success alert & dismiss

                            case .failure(let configError):
                                errorMessage = "Tünel oluşturuldu ancak yapılandırma/MAMP hatası:\n\(configError.localizedDescription)"
                                showErrorAlert = true; isCreating = false; creationStatus = "Hata."
                            }
                        }
                    }
                case .failure(let createError):
                     errorMessage = "Cloudflare'da tünel oluşturma hatası:\n\(createError.localizedDescription)"
                     showErrorAlert = true; isCreating = false; creationStatus = "Hata."
                }
             }
        }
    }
}

