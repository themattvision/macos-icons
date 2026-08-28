//
//  WorkerConfigurationTests.swift
//  MacOS IconsTests
//

import Foundation
import Testing
@testable import MacOS_Icons

@MainActor
struct WorkerConfigurationTests {

    @Test(arguments: [
        ("https://icons.example.workers.dev", "https://icons.example.workers.dev"),
        ("  https://icons.example.workers.dev/path///  ", "https://icons.example.workers.dev/path")
    ])
    func normalizesHTTPSWorkerURLs(input: String, expected: String) throws {
        let url = try IconSearchService.normalizedWorkerURL(input)
        #expect(url.absoluteString == expected)
    }

    @Test(arguments: [
        "http://icons.example.workers.dev",
        "https://user:password@icons.example.workers.dev",
        "https://icons.example.workers.dev/?debug=true",
        "https://icons.example.workers.dev/#fragment",
        "not a URL"
    ])
    func rejectsUnsafeOrAmbiguousWorkerURLs(input: String) {
        #expect(throws: WorkerConfigurationError.invalidURL) {
            try IconSearchService.normalizedWorkerURL(input)
        }
    }

    @Test
    func searchRequestDoesNotEncodeAnAPIKey() throws {
        let request = SearchRequest(query: "Safari", searchOptions: SearchOptions(hitsPerPage: 20, page: 1))
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(object?["query"] as? String == "Safari")
        #expect(object?["apiKey"] == nil)
    }
}
