import XCTest
@testable import Yield

/// Pinned tests for `GoogleAuthService`'s pure helpers — the parts of
/// the OAuth flow we can exercise without driving a live HTTP server
/// or hitting Google.
///
/// Everything here calls `nonisolated static` methods so no MainActor
/// hop is needed.
final class GoogleAuthServiceTests: XCTestCase {

    // MARK: - PKCE

    /// RFC 7636 §A.1 reference vector. Pins the SHA256→base64url
    /// derivation against the spec's own example so we know our
    /// challenge format matches what Google's authorization server
    /// computes server-side. If this drifts, every OAuth flow breaks
    /// with `invalid_grant` at token exchange.
    func test_codeChallenge_matchesRFC7636ReferenceVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        XCTAssertEqual(GoogleAuthService.codeChallenge(for: verifier), expected)
    }

    /// RFC 7636 §4.1: verifier is 43–128 chars from the unreserved set
    /// `[A-Za-z0-9-._~]`. Anything outside that range or alphabet gets
    /// rejected by Google with `invalid_request`.
    func test_generateCodeVerifier_satisfiesRFCFormat() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        // Sample enough times to catch any rare bad byte from the
        // base64url path (`/` → `_`, `+` → `-`, `=` stripped).
        for _ in 0..<100 {
            let verifier = GoogleAuthService.generateCodeVerifier()
            XCTAssertGreaterThanOrEqual(verifier.count, 43, "verifier too short: \(verifier)")
            XCTAssertLessThanOrEqual(verifier.count, 128, "verifier too long: \(verifier)")
            XCTAssertTrue(
                verifier.unicodeScalars.allSatisfy { allowed.contains($0) },
                "verifier contains non-unreserved character: \(verifier)"
            )
        }
    }

    /// Each call must produce a fresh value — reusing a verifier
    /// across flows would defeat the point of PKCE.
    func test_generateCodeVerifier_isUnique() {
        let samples = Set((0..<50).map { _ in GoogleAuthService.generateCodeVerifier() })
        XCTAssertEqual(samples.count, 50, "verifier collisions across 50 samples")
    }

    /// Base64URL has no padding (`=`) and no URL-unsafe `+`/`/`.
    func test_base64URLEncode_omitsPaddingAndUnsafeChars() {
        // Input that base64-standard would render with both `+` and
        // `/` and trailing `=` padding — pick bytes whose standard
        // base64 contains all three so the test exercises every
        // substitution.
        let input = Data([0xFB, 0xFF, 0xFE])  // base64: "+//+"
        let encoded = GoogleAuthService.base64URLEncode(input)
        XCTAssertFalse(encoded.contains("+"), "should substitute '+' with '-'")
        XCTAssertFalse(encoded.contains("/"), "should substitute '/' with '_'")
        XCTAssertFalse(encoded.contains("="), "should strip padding")
    }

    // MARK: - Form encoding

    /// Sanity check the helper used by every token request — the
    /// `+` and `=` chars below are common in OAuth bodies (refresh
    /// tokens, authorization codes) and the default URL-query
    /// percent-encoding leaves them unescaped, which breaks strict
    /// form-urlencoded parsers like Google's.
    func test_formURLEncoded_escapesSpecialCharacters() {
        let encoded = GoogleAuthService.formURLEncoded(["code": "a+b=c/d"])
        XCTAssertEqual(encoded, "code=a%2Bb%3Dc%2Fd")
    }

    /// Output is sorted by key so tests stay deterministic and
    /// debug logs are easier to diff.
    func test_formURLEncoded_isDeterministic() {
        let encoded = GoogleAuthService.formURLEncoded(["z": "1", "a": "2", "m": "3"])
        XCTAssertEqual(encoded, "a=2&m=3&z=1")
    }
}
