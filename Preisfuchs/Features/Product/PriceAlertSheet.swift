import SwiftData
import SwiftUI
import PriceCore

/// Legt einen Preisalarm an oder ändert ihn (#11).
struct PriceAlertSheet: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let product: Product

    /// Bestpreis, der gerade angezeigt wird – als Ausgangswert für den
    /// Vorschlag. `nil`, wenn es keinen gibt.
    let currentBest: Money?

    /// Vorhandener Alarm, falls schon einer besteht.
    let existing: PriceAlert?

    @State private var thresholdText: String = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            List {
                thresholdSection
                notificationSection
                if existing != nil { deleteSection }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .navigationTitle("Preisalarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(parsedThreshold == nil)
                }
            }
        }
        .task {
            thresholdText = initialText
            await appEnvironment.notifications.refreshAuthorization()
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Zielpreis

    private var thresholdSection: some View {
        Section {
            HStack {
                Text("Benachrichtigen unter")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("0,00", text: $thresholdText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 110)
                Text("€").foregroundStyle(Theme.textSecondary)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.deal)
            }
        } header: {
            Text(product.name)
        } footer: {
            if let currentBest {
                Text("Günstigster bekannter Preis: "
                     + currentBest.roundedToCents.formatted() + ".")
            } else {
                Text("Für dieses Produkt ist gerade kein Preis bekannt. Der Alarm greift, "
                     + "sobald einer auftaucht, der unter deinem Zielpreis liegt.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Zustellung

    private var notificationSection: some View {
        Section {
            switch appEnvironment.notifications.authorization {
            case .notDetermined:
                Button("Benachrichtigungen erlauben") {
                    Task { await appEnvironment.notifications.requestAuthorization() }
                }
            case .denied:
                Label("Benachrichtigungen sind aus", systemImage: "bell.slash")
                    .foregroundStyle(Theme.textSecondary)
            case .authorized:
                Label("Benachrichtigungen sind erlaubt", systemImage: "bell")
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text("Zustellung")
        } footer: {
            // Diese Einschränkung gehört in die App, nicht nur in die
            // Dokumentation. Wer einen Alarm setzt, soll wissen, worauf er
            // sich verlassen kann -- und worauf nicht.
            Text(appEnvironment.notifications.authorization.explanation
                 + "\n\nPreisfuchs prüft die Alarme selbst, ohne Server. Deshalb kann eine "
                 + "Meldung verspätet kommen oder ausbleiben, wenn die App länger nicht "
                 + "geöffnet wird. Beim Öffnen wird immer geprüft.")
        }
        .listRowBackground(Theme.surface)
    }

    private var deleteSection: some View {
        Section {
            Button("Preisalarm löschen", role: .destructive) {
                if let existing { context.delete(existing) }
                try? context.save()
                dismiss()
            }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Speichern

    private var initialText: String {
        if let existing, let threshold = existing.threshold {
            return format(threshold.amount)
        }
        // Vorschlag: etwas unter dem aktuellen Bestpreis -- aber ausdrücklich
        // nur als Startwert, den der Nutzer ändern kann.
        if let currentBest {
            let suggestion = currentBest.amount * Decimal(string: "0.9")!
            return format(DecimalParsing.round(suggestion, scale: 2))
        }
        return ""
    }

    private var parsedThreshold: Money? {
        guard let amount = DecimalParsing.decimal(from: thresholdText), amount > 0 else {
            return nil
        }
        return Money(amount: amount)
    }

    private func save() {
        guard let threshold = parsedThreshold else {
            validationMessage = "Bitte einen Betrag größer als null eingeben."
            return
        }

        if let existing {
            existing.thresholdText = "\(threshold.amount)"
            existing.currency = threshold.currency
            existing.isEnabled = true
            // Ein geänderter Zielpreis setzt die Sperre zurück, sonst bliebe
            // eine frühere Meldung für immer im Weg.
            existing.lastNotifiedPriceText = nil
        } else {
            context.insert(PriceAlert(productID: product.id,
                                      barcode: product.barcode,
                                      name: product.name,
                                      threshold: threshold))
        }

        try? context.save()
        PriceAlertService.scheduleNextRun()
        dismiss()
    }

    private func format(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }
}
