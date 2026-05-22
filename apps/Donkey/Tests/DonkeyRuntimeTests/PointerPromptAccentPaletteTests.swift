import DonkeyContracts
import Testing

@Suite
struct PointerPromptAccentPaletteTests {
    @Test
    func paletteCyclesThroughSupportedAccentList() {
        var currentIndex: Int?

        let sequence = (0..<10).map { _ in
            let nextIndex = currentIndex.map(PointerPromptAccentPalette.index(after:))
                ?? PointerPromptAccentPalette.firstIndex
            currentIndex = nextIndex
            return nextIndex
        }

        #expect(sequence == [0, 1, 2, 3, 4, 5, 6, 7, 0, 1])
    }

    @Test
    func paletteContinuesAfterKnownAccent() {
        #expect(PointerPromptAccentPalette.index(after: 1) == 2)
        #expect(PointerPromptAccentPalette.index(after: 7) == 0)
    }

    @Test
    func paletteNormalizesOutOfRangeIndexes() {
        #expect(PointerPromptAccentPalette.normalizedIndex(-1) == 7)
        #expect(PointerPromptAccentPalette.normalizedIndex(8) == 0)
        #expect(PointerPromptAccentPalette.index(after: 7) == 0)
    }
}
