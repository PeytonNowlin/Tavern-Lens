import CoreGraphics
import ScreenReading
import Testing

@Suite("MMR screen evidence")
struct RatingScreenParserTests {
    func line(_ text: String, _ x: Double = 100, _ y: Double = 100, confidence: Double = 0.99) -> RecognizedLine {
        .init(text: text, confidence: confidence, rect: CGRect(x: x, y: y, width: 90, height: 20))
    }

    @Test func labeledValuesOnly() {
        #expect(RatingScreenParser.rating(in: [line("Rating: 6,421")]) == 6421)
        #expect(RatingScreenParser.rating(in: [line("Rating"), line("6421", 100, 70)]) == 6421)
        #expect(RatingScreenParser.rating(in: [line("Rating"), line("0", 100, 128)]) == 0)
        #expect(RatingScreenParser.rating(in: [line("6421")]) == nil)
        #expect(RatingScreenParser.rating(in: [line("Rating"), line("6421", 400, 100)]) == nil)
        #expect(RatingScreenParser.rating(in: [line("Rating: 6,421", confidence: 0.7)]) == nil)
    }

    @Test func rejectAmbiguityAndOtherModes() {
        for text in ["+89", "6O00", "-2", "12/20", "6,42", "100000"] {
            #expect(RatingScreenParser.rating(in: [line("Rating"), line(text, 100, 125)]) == nil)
        }
        #expect(RatingScreenParser.rating(in: [line("Rating"), line("6000", 100, 70), line("6100", 100, 130)]) == nil)
        #expect(RatingScreenParser.rating(in: [line("Rating: 6000"), line("Rating: 6100")]) == nil)
        #expect(RatingScreenParser.rating(in: [line("Rating: 6000"), line("Duos")]) == nil)
    }

    @Test func uncertainDuosEvidenceStillVetoesSoloRating() {
        for confidence in [0.0, 0.2, 0.84] {
            #expect(RatingScreenParser.rating(in: [line("Rating: 6000"), line("Duos", confidence: confidence)]) == nil)
        }
    }

    @Test func stableReadingsRejectAnimationsAndGaps() {
        var reader = StableRatingReading()
        for value in [6000, 6010, 6040, 6040] { #expect(reader.observe(value) == nil) }
        #expect(reader.observe(nil) == nil)
        #expect(reader.observe(6040) == nil)
        #expect(reader.observe(6040) == nil)
        #expect(reader.observe(6040) == 6040)
        #expect(reader.observe(0) == nil)
        #expect(reader.observe(0) == nil)
        #expect(reader.observe(0) == 0)
    }
}
