import Foundation

/// Entfernungsberechnung.
///
/// Bewusst ohne CoreLocation, damit `PriceCore` plattformunabhaengig bleibt
/// und auf jedem Mac mit `swift test` pruefbar ist.
public enum GeoDistance {

    /// Mittlerer Erdradius in Metern (IUGG).
    private static let earthRadiusMeters = 6_371_008.8

    /// Luftlinie zwischen zwei Punkten in Metern (Haversine).
    ///
    /// Wichtig: Das ist **Luftlinie**, nicht Fahrstrecke. Die App muss das so
    /// benennen -- eine Luftlinie als "Entfernung zur Filiale" auszugeben,
    /// waere eine stille Ungenauigkeit.
    public static func straightLineMeters(from: Coordinate, to: Coordinate) -> Double? {
        guard from.isValid, to.isValid else { return nil }

        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLat = (to.latitude - from.latitude) * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadiusMeters * c
    }

    /// Anzeige wie "850 m" oder "2,4 km".
    public static func formatted(meters: Double,
                                 locale: Locale = Locale(identifier: "de_DE")) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal

        if meters < 1000 {
            formatter.maximumFractionDigits = 0
            let value = formatter.string(from: NSNumber(value: meters.rounded())) ?? "\(Int(meters))"
            return "\(value) m"
        }

        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        let km = meters / 1000
        let value = formatter.string(from: NSNumber(value: km)) ?? "\(km)"
        return "\(value) km"
    }
}
