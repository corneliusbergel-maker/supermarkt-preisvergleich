import Foundation

// Stellt ein Foto mit genau derselben Logik frei wie die App
// (Preisfuchs/Services/ProductCutout.swift) und schreibt das Ergebnis als PNG.
//
// Grund: Im iOS-Simulator läuft das Freistellen nicht – Vision braucht GPU
// oder Neural Engine. Die CI prüft es deshalb direkt auf dem Mac.
//
// Aufruf: check <eingabe.jpg> <ausgabe.png>

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Aufruf: check <eingabe> <ausgabe.png>")
    exit(2)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])

do {
    let data = try Data(contentsOf: input)
    switch try ProductCutout.cutout(imageData: data) {
    case .cutout(let png):
        try png.write(to: output)
        print("Freigestellt: \(output.lastPathComponent) (\(png.count / 1024) KB)")
    case .noSubject:
        print("Kein eindeutiges Produkt erkannt: \(input.lastPathComponent)")
        exit(1)
    }
} catch {
    print("Vision-Fehler bei \(input.lastPathComponent): \(error)")
    exit(1)
}
