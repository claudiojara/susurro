import Foundation
import Testing

@testable import DesignSystem

@Suite("RGBA color")
struct RGBAColorTests {
    @Test("reads #RRGGBB as opaque")
    func readsSixDigits() throws {
        let color = try #require(RGBAColor(hex: "#1D3A5F"))
        #expect(color == RGBAColor(red: 29.0 / 255, green: 58.0 / 255, blue: 95.0 / 255, alpha: 1))
    }

    @Test("reads #RRGGBBAA with the alpha last, in either case")
    func readsEightDigits() throws {
        let color = try #require(RGBAColor(hex: "#ff800080"))
        #expect(color == RGBAColor(red: 1, green: 128.0 / 255, blue: 0, alpha: 128.0 / 255))
    }

    @Test(
        "rejects text that is not a color",
        arguments: ["", "FFFFFF", "#FFF", "#12345", "#GGGGGG", "#FFFFFFFFF", "# FFFFF", "#+FFFFF"])
    func rejectsBadText(text: String) {
        #expect(RGBAColor(hex: text) == nil)
    }

    @Test("writes the shortest uppercase form", arguments: ["#1D3A5F", "#FFFFFF80", "#000000"])
    func roundTrips(text: String) throws {
        #expect(try #require(RGBAColor(hex: text)).hex == text)
        #expect(try #require(RGBAColor(hex: text.lowercased())).hex == text)
    }

    @Test("decodes from a JSON string and reports the bad one with its path")
    func decodes() throws {
        struct Box: Codable { let tint: RGBAColor }
        let good = try JSONDecoder().decode(Box.self, from: Data(##"{"tint":"#102030"}"##.utf8))
        #expect(good.tint == RGBAColor(hex: "#102030"))
        do {
            _ = try JSONDecoder().decode(Box.self, from: Data(##"{"tint":"#12"}"##.utf8))
            Issue.record("a bad color decoded")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.codingPath.map(\.stringValue) == ["tint"])
        }
    }

    @Test("encodes as the hex string")
    func encodes() throws {
        struct Box: Codable { let tint: RGBAColor }
        let color = try #require(RGBAColor(hex: "#102030"))
        let data = try JSONEncoder().encode(Box(tint: color))
        #expect(String(decoding: data, as: UTF8.self) == ##"{"tint":"#102030"}"##)
    }

    @Test("a color painted over another gives the color the eye sees")
    func composites() {
        let white = RGBAColor(red: 1, green: 1, blue: 1)
        let blue = RGBAColor(red: 0, green: 0, blue: 1)
        // Opaque paint hides what is under it, and transparent paint shows it.
        #expect(blue.composited(over: white) == blue)
        #expect(RGBAColor(red: 0, green: 0, blue: 1, alpha: 0).composited(over: white) == white)
        // Half black over white is middle gray; a tenth of black over white is 90 % gray.
        let half = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5).composited(over: white)
        #expect(half == RGBAColor(red: 0.5, green: 0.5, blue: 0.5))
        let tenth = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.1).composited(over: white)
        #expect(abs(tenth.red - 0.9) < 1e-9 && abs(tenth.alpha - 1) < 1e-9)
        // The paint is a translucent color itself: the result is translucent too, and is weighted by both alphas.
        let veil = RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        let glass = RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        let both = veil.composited(over: glass)
        #expect(abs(both.alpha - 0.75) < 1e-9)
        #expect(abs(both.red - 2.0 / 3.0) < 1e-9 && abs(both.blue - 1.0 / 3.0) < 1e-9)
        // Nothing over nothing is nothing.
        let nothing = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
        #expect(nothing.composited(over: nothing).alpha == 0)
    }
}
