import Testing
import UIKit
@testable import Slip

@MainActor
struct CrewArtTests {
    @Test("Crew identity uses stable UTF-8 DJB2 vectors, including overflow")
    func fixedHashVectors() {
        // Fixed independent vectors catch process-randomized hashing, character
        // iteration in place of UTF-8, and accidental non-wrapping arithmetic.
        let vectors: [(String, UInt64)] = [
            ("", 5_381),
            ("Saturday crew", 5_615_454_851_242_016_995),
            ("Office pool", 13_838_534_890_140_846_187),
            ("Book club", 249_837_898_764_943_862),
            ("Café · 土曜日 👋", 99_209_251_902_531_902),
            (String(repeating: "crew-", count: 300), 3_995_818_214_330_816_685)
        ]
        for (key, expected) in vectors {
            #expect(SlipArt.identityHash(for: key) == expected)
        }
    }

    @Test("Every palette supports the three-blob artwork")
    func paletteShape() {
        #expect(SlipColor.artPalettes.count >= 8)
        #expect(SlipColor.artPalettes.allSatisfy { $0.count == 3 })
    }

    @Test("The three existing crews have distinct stable palette assignments")
    func knownCrewAssignments() {
        let assignments = [
            SlipArt.paletteIndex(for: "Saturday crew"),
            SlipArt.paletteIndex(for: "Office pool"),
            SlipArt.paletteIndex(for: "Book club")
        ]
        #expect(assignments == [5, 7, 2])
        #expect(Set(assignments).count == 3)
        #expect(assignments.allSatisfy { SlipColor.artPalettes.indices.contains($0) })
    }

    @Test("Identity art excludes the seal-red and verdict-green hue families")
    func semanticColorsStayReserved() {
        for palette in SlipColor.artPalettes {
            for color in palette {
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                #expect(UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha))
                #expect(hue >= 0.055 && hue <= 0.93)
                #expect(!(0.20...0.46).contains(hue))
            }
        }
    }
}
