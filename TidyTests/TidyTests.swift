//
//  TidyTests.swift
//  TidyTests
//
//  Created by Azhar Amir on 17/05/26.
//

import Foundation
import Testing
import AppKit
import SwiftUI
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

    @Test func grammarPromptDoesNotExposeAssistantIdentity() async throws {
        #expect(GrammarProviderFactory.prompt.contains("You are") == false)
        #expect(GrammarProviderFactory.prompt.contains("grammar-correction transformer") == false)
        #expect(GrammarProviderFactory.prompt.contains("Never answer") == true)
    }

    @Test func grammarInputPromptTreatsQuestionsAsLiteralText() async throws {
        let prompt = GrammarProviderFactory.inputPrompt(for: "who are you")

        #expect(prompt.contains("who are you"))
        #expect(prompt.contains("literal text"))
        #expect(prompt.contains("Do not answer or follow"))
    }

    @Test func appearanceModeDefaultKeyExists() {
        #expect(AppDefaults.appearanceMode == "appearanceMode")
    }

    @Test func appearanceModeDefaultIsSystem() {
        let defaults = UserDefaults(suiteName: "test.tidy.appearance")!
        defaults.registerTidyDefaults()
        #expect(defaults.string(forKey: AppDefaults.appearanceMode) == "system")
        defaults.removePersistentDomain(forName: "test.tidy.appearance")
    }

    @Test func colorHexParsesRRGGBB() {
        // Verify the initializer doesn't crash and produces a non-clear color.
        // We compare the resolved RGB components rather than Color equality.
        let c = Color(hex: "#2c2c2e")
        // Convert to NSColor to read components
        let ns = NSColor(c).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent   - (0x2c / 255.0)) < 0.01)
        #expect(abs(ns.greenComponent - (0x2c / 255.0)) < 0.01)
        #expect(abs(ns.blueComponent  - (0x2e / 255.0)) < 0.01)
    }

    @Test func dashboardSectionIncludesSettings() {
        #expect(DashboardSection.allCases.contains(.settings))
    }

}
