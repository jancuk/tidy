//
//  TidyTests.swift
//  TidyTests
//
//  Created by Azhar Amir on 17/05/26.
//

import Testing
@testable import Tidy

struct TidyTests {

    @Test func jsonFormatterValidatesAndFormats() async throws {
        let result = JSONTool.format("{\"b\":2,\"a\":1}")

        #expect(result.isError == false)
        #expect(result.output.contains("\"a\" : 1"))
        #expect(result.output.contains("\"b\" : 2"))
    }

    @Test func jwtDebuggerDecodesPayloadClaims() async throws {
        let result = JWTTool.decode("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.signature")

        #expect(result.isError == false)
        #expect(result.payloadJSON.contains("\"sub\" : \"123\""))
    }

    @Test func csvConvertsToJSON() async throws {
        let result = CSVTool.csvToJSON("name,role\nTidy,Tools")

        #expect(result.isError == false)
        #expect(result.output.contains("\"name\" : \"Tidy\""))
        #expect(result.output.contains("\"role\" : \"Tools\""))
    }

    @Test func cronParsesStepExpression() async throws {
        let result = CronTool.parse("*/15 * * * *")

        #expect(result.isError == false)
        #expect(result.description == "Every 15 minutes")
        #expect(result.fields.first?.1.contains("0") == true)
        #expect(result.nextRuns.isEmpty == false)
    }

}
