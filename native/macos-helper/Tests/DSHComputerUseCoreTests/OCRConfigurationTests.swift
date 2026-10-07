import XCTest
import CoreGraphics
import DSHComputerUseCore

final class OCRConfigurationTests: XCTestCase {
    func testUnsupportedLanguageReportsExplicitError() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        XCTAssertThrowsError(try VisionOCRService().recognize(cgImage: image, languages: ["invalid-language"])) { error in
            guard case AgentError.ocr(let message) = error else {
                return XCTFail("Expected an OCR error, got \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported OCR languages"))
        }
    }

    func testLegacyRequestsRemainDecodable() throws {
        let observe = try JSONDecoder().decode(ObserveParams.self, from: Data("{}".utf8))
        XCTAssertNil(observe.ocrLanguages)
        let file = try JSONDecoder().decode(OCRFileRequest.self, from: Data("{\"path\":\"fixture.png\"}".utf8))
        XCTAssertNil(file.languages)
    }

    func testLanguagesRoundTripInBothRequests() throws {
        let languages = ["zh-Hans", "en-US"]
        let observe = ObserveParams(ocr: .always, ocrLanguages: languages)
        XCTAssertEqual(try JSONDecoder().decode(ObserveParams.self, from: JSONEncoder().encode(observe)), observe)
        let file = OCRFileRequest(path: "fixture.png", languages: languages)
        XCTAssertEqual(try JSONDecoder().decode(OCRFileRequest.self, from: JSONEncoder().encode(file)), file)
    }
}
