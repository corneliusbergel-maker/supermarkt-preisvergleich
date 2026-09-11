import PhotosUI
import SwiftUI
import PriceCore
import PriceData
#if canImport(UIKit)
import UIKit
#endif

/// Trägt einen im Markt gesehenen Preis bei.
///
/// Damit wächst genau der Teil der Datenbank, den man selbst braucht. Der
/// Beitrag steht danach unter ODbL allen zur Verfügung – das ist der Preis
/// dafür, dass die Daten nichts kosten.
struct ContributePriceSheet: View {

    let product: Product

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var session: OpenPricesSession?
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var signInError: String?

    @State private var stores: [Store] = []
    @State private var selectedStoreID: String?
    @State private var isLoadingStores = false

    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isTakingPhoto = false

    @State private var priceText = ""
    @State private var isDiscounted = false
    @State private var originalPriceText = ""

    @State private var submission: Submission = .idle

    enum Submission: Equatable {
        case idle
        case uploading
        case done
        case failed(String)
    }

    private let client = OpenPricesContributionClient()

    var body: some View {
        NavigationStack {
            Group {
                if session == nil {
                    signInForm
                } else {
                    contributionForm
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .navigationTitle("Preis beitragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .task {
            session = OpenPricesCredentialStore.load()
            await loadStores()
        }
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { image in
                photoData = Self.compressImage(image)
            }
            .ignoresSafeArea()
        }
        #endif
    }

    // MARK: - Anmeldung

    private var signInForm: some View {
        List {
            Section {
                TextField("Benutzername", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Kennwort", text: $password)
                    .textContentType(.password)

                Button {
                    Task { await signIn() }
                } label: {
                    if isSigningIn {
                        HStack {
                            ProgressView().tint(Theme.accent)
                            Text("Anmelden …")
                        }
                    } else {
                        Text("Anmelden")
                    }
                }
                .disabled(isSigningIn
                          || username.trimmingCharacters(in: .whitespaces).isEmpty
                          || password.isEmpty)

                if let signInError {
                    Text(signInError)
                        .font(.cardBody)
                        .foregroundStyle(Theme.deal)
                }
            } header: {
                Text("Open-Food-Facts-Konto")
            } footer: {
                Text("Beiträge brauchen ein kostenloses Konto bei Open Food Facts – "
                     + "damit die Datenbank nachvollziehen kann, woher ein Preis stammt.\n\n"
                     + "Wichtig: Hier gehört der **Benutzername** hin, nicht die "
                     + "E-Mail-Adresse. Das Kennwort wird nur einmal zum Anmelden gesendet "
                     + "und nicht gespeichert – gespeichert wird allein ein Zugangstoken, "
                     + "und der liegt im Schlüsselbund des Geräts.")
            }
            .listRowBackground(Theme.surface)
        }
    }

    private func signIn() async {
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }

        do {
            let newSession = try await client.signIn(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
            OpenPricesCredentialStore.save(newSession)
            session = newSession
            // Das Kennwort wird nicht länger im Speicher gehalten als nötig.
            password = ""
        } catch let error as DataSourceError {
            signInError = error == .unauthorized
                ? "Benutzername oder Kennwort stimmt nicht. Bitte beachte: der "
                  + "Benutzername, nicht die E-Mail-Adresse."
                : error.userMessage
        } catch {
            signInError = "Die Anmeldung ist fehlgeschlagen."
        }
    }

    // MARK: - Beitrag

    private var contributionForm: some View {
        List {
            productSection
            storeSection
            photoSection
            priceSection
            submitSection
            accountSection
        }
    }

    private var productSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let quantity = product.quantity {
                    Text(quantity.formatted())
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("Produkt")
        }
        .listRowBackground(Theme.surface)
    }

    private var storeSection: some View {
        Section {
            if isLoadingStores {
                HStack {
                    ProgressView().tint(Theme.accent)
                    Text("Filialen werden gesucht …").foregroundStyle(Theme.textSecondary)
                }
            } else if stores.isEmpty {
                Text("Keine Filiale in der Nähe gefunden. Ohne Filiale lässt sich ein "
                     + "Preis nicht zuordnen – gib den Standort frei oder wähle in den "
                     + "Einstellungen einen Ort.")
                    .font(.cardBody)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Picker("Filiale", selection: $selectedStoreID) {
                    Text("Bitte wählen").tag(String?.none)
                    ForEach(stores) { store in
                        Text(store.displayName).tag(String?.some(store.id))
                    }
                }
            }
        } header: {
            Text("Wo hast du den Preis gesehen?")
        }
        .listRowBackground(Theme.surface)
    }

    private var photoSection: some View {
        Section {
            // Vor dem Regal ist die Kamera der kürzeste Weg. Wo es keine
            // gibt (Mac, Simulator), erscheint der Eintrag gar nicht.
            if CameraCapture.isAvailable {
                Button {
                    isTakingPhoto = true
                } label: {
                    Label(photoData == nil ? "Preisschild fotografieren" : "Neu fotografieren",
                          systemImage: "camera.fill")
                }
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(photoData == nil ? "Foto aus der Mediathek wählen" : "Anderes Foto wählen",
                      systemImage: "photo.on.rectangle")
            }
            .onChange(of: photoItem) { _, newValue in
                Task { await loadPhoto(newValue) }
            }

            if let photoData {
                Text("Foto ausgewählt (\(photoData.count / 1024) KB)")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text("Beleg")
        } footer: {
            Text("Ein Foto des Preisschilds ist Pflicht. Genau diesen Nachweis erwartet "
                 + "die App auch von fremden Daten – ohne Beleg gilt ein Preis dort nicht "
                 + "als bestätigt.")
        }
        .listRowBackground(Theme.surface)
    }

    private var priceSection: some View {
        Section {
            HStack {
                Text("Preis").foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("0,00", text: $priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 110)
                Text("€").foregroundStyle(Theme.textSecondary)
            }

            Toggle("Ist ein Angebot", isOn: $isDiscounted)

            if isDiscounted {
                HStack {
                    Text("Normalpreis").foregroundStyle(Theme.textSecondary)
                    Spacer()
                    TextField("optional", text: $originalPriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 110)
                    Text("€").foregroundStyle(Theme.textSecondary)
                }
            }
        } header: {
            Text("Preis")
        } footer: {
            if isDiscounted {
                Text("Den Normalpreis nur eintragen, wenn er auf dem Schild steht. "
                     + "Ein geschätzter Wert stünde sonst als Tatsache in einer "
                     + "öffentlichen Datenbank.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var submitSection: some View {
        Section {
            switch submission {
            case .idle, .failed:
                Button("Preis beitragen") {
                    Task { await submit() }
                }
                .disabled(!canSubmit)

                if case .failed(let message) = submission {
                    Text(message)
                        .font(.cardBody)
                        .foregroundStyle(Theme.deal)
                }

            case .uploading:
                HStack {
                    ProgressView().tint(Theme.accent)
                    Text("Wird übertragen …").foregroundStyle(Theme.textSecondary)
                }

            case .done:
                Label("Danke – dein Preis ist eingetragen.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
        } footer: {
            Text("Dein Beitrag steht anschließend unter ODbL allen zur Verfügung. "
                 + "Das ist der Grund, warum die Daten in dieser App nichts kosten.")
        }
        .listRowBackground(Theme.surface)
    }

    private var accountSection: some View {
        Section {
            LabeledContent("Angemeldet als", value: session?.userID ?? "–")
            Button("Abmelden", role: .destructive) {
                OpenPricesCredentialStore.clear()
                session = nil
            }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Ablauf

    private var selectedStore: Store? {
        stores.first { $0.id == selectedStoreID }
    }

    private var parsedPrice: Money? {
        guard let amount = DecimalParsing.decimal(from: priceText), amount > 0 else {
            return nil
        }
        return Money(amount: amount)
    }

    private var canSubmit: Bool {
        session != nil && selectedStore != nil && photoData != nil && parsedPrice != nil
    }

    private func loadStores() async {
        guard let coordinate = appEnvironment.activeCoordinate else { return }
        isLoadingStores = true
        defer { isLoadingStores = false }
        stores = (try? await appEnvironment.stores.stores(near: coordinate, radiusKm: 5)) ?? []
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let raw = try? await item.loadTransferable(type: Data.self) else { return }
        photoData = Self.compress(raw)
    }

    /// Verkleinert das Bild vor dem Hochladen.
    ///
    /// Ein unbearbeitetes Kamerafoto hat schnell mehrere Megabyte. Das einem
    /// gemeinnützig betriebenen Dienst zuzumuten wäre unhöflich – und für das
    /// Lesen eines Preisschilds völlig unnötig.
    private static func compress(_ data: Data) -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return data }
        return compressImage(image) ?? data
        #else
        return data
        #endif
    }

    #if canImport(UIKit)
    static func compressImage(_ image: UIImage) -> Data? {
        let maximumEdge: CGFloat = 1600
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return nil }

        let scale = min(1, maximumEdge / longestSide)
        let target = CGSize(width: image.size.width * scale,
                            height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
    #endif

    private func submit() async {
        guard let session, let store = selectedStore,
              let photoData, let price = parsedPrice,
              let barcode = product.barcode else { return }

        submission = .uploading

        do {
            let proofID = try await client.uploadPriceTag(
                imageData: photoData,
                store: store,
                currency: price.currency,
                date: Date(),
                token: session.accessToken
            )

            let original = isDiscounted
                ? DecimalParsing.decimal(from: originalPriceText).map { Money(amount: $0) }
                : nil

            try await client.submitPrice(
                barcode: barcode,
                price: price,
                date: Date(),
                store: store,
                proofID: proofID,
                isDiscounted: isDiscounted,
                priceWithoutDiscount: original,
                token: session.accessToken
            )

            submission = .done

        } catch let error as DataSourceError {
            if error == .unauthorized {
                // Token abgelaufen -- zurück zur Anmeldung statt einer
                // Fehlermeldung, die niemand einordnen kann.
                OpenPricesCredentialStore.clear()
                self.session = nil
                signInError = error.userMessage
            }
            submission = .failed(error.userMessage)
        } catch {
            submission = .failed("Der Beitrag konnte nicht übertragen werden.")
        }
    }
}
