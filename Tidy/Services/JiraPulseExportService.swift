import AppKit
import CoreText
import Foundation

enum JiraPulseExportFormat: String, CaseIterable, Identifiable {
    case pdf
    case csv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf: "PDF report"
        case .csv: "CSV data"
        }
    }

    var fileExtension: String { rawValue }
}

enum JiraPulseExporter {
    static func suggestedFilename(
        projectKey: String,
        format: JiraPulseExportFormat,
        generatedAt: Date = Date()
    ) -> String {
        let project = projectKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(
                of: "[^A-Z0-9_-]",
                with: "-",
                options: .regularExpression
            )
        let day = filenameDateFormatter.string(from: generatedAt)
        let prefix = project.isEmpty ? "Jira" : project
        return "\(prefix)-Sprint-Pulse-\(day).\(format.fileExtension)"
    }

    static func data(
        for format: JiraPulseExportFormat,
        issues: [JiraIssue],
        notifications: [JiraNotification],
        projectKey: String,
        isFilteredToAssignee: Bool,
        generatedAt: Date = Date()
    ) throws -> Data {
        switch format {
        case .csv:
            Data(
                csv(
                    issues: issues,
                    projectKey: projectKey,
                    isFilteredToAssignee: isFilteredToAssignee,
                    generatedAt: generatedAt
                ).utf8
            )
        case .pdf:
            try pdf(
                issues: issues,
                notifications: notifications,
                projectKey: projectKey,
                isFilteredToAssignee: isFilteredToAssignee,
                generatedAt: generatedAt
            )
        }
    }

    static func csv(
        issues: [JiraIssue],
        projectKey: String,
        isFilteredToAssignee: Bool,
        generatedAt: Date = Date()
    ) -> String {
        let header = [
            "Project",
            "Scope",
            "Exported At",
            "Workflow",
            "Jira Status",
            "Ticket",
            "Summary",
            "Description",
            "Type",
            "Priority",
            "Assignee",
            "Created",
            "Updated",
            "Completed for Sprint"
        ]

        let project = projectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let scope = isFilteredToAssignee ? "Current assignee" : "Everyone"
        let exportedAt = iso8601.string(from: generatedAt)
        let rows = orderedIssues(issues).map { issue in
            [
                project,
                scope,
                exportedAt,
                workflowLabel(for: issue),
                issue.fields.status.name,
                issue.key,
                issue.fields.summary,
                issue.fields.description?.plainText
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                issue.fields.issueType.name,
                issue.fields.priority?.name ?? "None",
                issue.fields.assignee?.displayName ?? "Unassigned",
                issue.createdDate.map(iso8601.string(from:)) ?? "",
                issue.updatedDate.map(iso8601.string(from:)) ?? "",
                issue.isCompleted ? "Yes" : "No"
            ]
        }

        return ([header] + rows)
            .map { $0.map(csvField).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    static func pdf(
        issues: [JiraIssue],
        notifications: [JiraNotification],
        projectKey: String,
        isFilteredToAssignee: Bool,
        generatedAt: Date = Date()
    ) throws -> Data {
        let analytics = JiraSprintAnalytics(
            issues: issues,
            notifications: notifications,
            now: generatedAt
        )
        let renderer = JiraPulsePDFRenderer()
        let project = projectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let title = project.isEmpty ? "Jira Sprint Pulse" : "\(project) Sprint Pulse"

        renderer.beginDocument()
        renderer.drawTitle(title)
        renderer.drawMuted(
            "\(isFilteredToAssignee ? "Current assignee" : "Everyone") scope | "
                + "Exported \(generatedAt.formatted(date: .abbreviated, time: .shortened))"
        )
        renderer.addSpace(18)

        renderer.drawSection("Sprint summary")
        renderer.drawMetricRow([
            ("Completion", "\(Int((analytics.completionRate * 100).rounded()))%"),
            ("Completed", "\(analytics.completed) / \(analytics.total)"),
            ("Active WIP", "\(analytics.active)"),
            ("Needs attention", "\(analytics.attentionIssues.count)")
        ])
        renderer.drawMuted("Ready for Release is counted as completed for sprint reporting.")
        renderer.addSpace(14)

        renderer.drawSection("Workflow distribution")
        for item in analytics.statusCounts {
            renderer.drawKeyValue(item.status.rawValue, value: "\(item.count)")
        }
        renderer.addSpace(14)

        renderer.drawSection("Team flow")
        if analytics.team.isEmpty {
            renderer.drawMuted("No assigned tickets in this scope.")
        } else {
            renderer.beginContinuation("Team flow")
            for member in analytics.team {
                renderer.drawTeamMember(member)
            }
            renderer.endContinuation()
        }
        renderer.addSpace(16)

        renderer.drawSection("All sprint tickets")
        let grouped = groupedIssues(issues)
        for group in grouped where !group.issues.isEmpty {
            renderer.drawTicketGroup(group.title, count: group.issues.count)
            for issue in group.issues {
                renderer.drawTicket(issue)
            }
            renderer.addSpace(8)
        }

        return try renderer.finish()
    }

    static func workflowLabel(for issue: JiraIssue) -> String {
        JiraWorkflowStatus.allCases.first {
            $0.matches(issue.fields.status.name)
        }?.rawValue ?? "Other"
    }

    static func orderedIssues(_ issues: [JiraIssue]) -> [JiraIssue] {
        issues.sorted {
            let left = workflowIndex(for: $0)
            let right = workflowIndex(for: $1)
            if left != right { return left < right }
            return $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }
    }

    private static func groupedIssues(
        _ issues: [JiraIssue]
    ) -> [(title: String, issues: [JiraIssue])] {
        var groups = JiraWorkflowStatus.allCases.map { status in
            (
                title: status.rawValue,
                issues: issues
                    .filter { status.matches($0.fields.status.name) }
                    .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            )
        }
        let other = issues
            .filter { issue in
                !JiraWorkflowStatus.allCases.contains {
                    $0.matches(issue.fields.status.name)
                }
            }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        if !other.isEmpty {
            groups.append((title: "Other", issues: other))
        }
        return groups
    }

    private static func workflowIndex(for issue: JiraIssue) -> Int {
        JiraWorkflowStatus.allCases.firstIndex {
            $0.matches(issue.fields.status.name)
        } ?? JiraWorkflowStatus.allCases.count
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private final class JiraPulsePDFRenderer {
    private let pageSize = CGSize(width: 612, height: 792)
    private let margin: CGFloat = 42
    private let bottomMargin: CGFloat = 46
    private let data = NSMutableData()
    private var context: CGContext?
    private var cursorY: CGFloat = 0
    private var pageNumber = 0
    private var documentStarted = false
    private var currentTicketGroup: (title: String, count: Int)?
    private var continuationTitle: String?
    private let ink = NSColor(
        calibratedRed: 0.10,
        green: 0.12,
        blue: 0.15,
        alpha: 1
    )
    private let mutedInk = NSColor(
        calibratedRed: 0.36,
        green: 0.39,
        blue: 0.44,
        alpha: 1
    )
    private let faintInk = NSColor(
        calibratedRed: 0.52,
        green: 0.55,
        blue: 0.60,
        alpha: 1
    )
    private let panelFill = NSColor(
        calibratedRed: 0.95,
        green: 0.96,
        blue: 0.98,
        alpha: 1
    )
    private let ruleColor = NSColor(
        calibratedRed: 0.82,
        green: 0.84,
        blue: 0.88,
        alpha: 1
    )
    private let accentBlue = NSColor(
        calibratedRed: 0.05,
        green: 0.38,
        blue: 0.86,
        alpha: 1
    )
    private let warningOrange = NSColor(
        calibratedRed: 0.85,
        green: 0.40,
        blue: 0.05,
        alpha: 1
    )

    private var contentWidth: CGFloat {
        pageSize.width - (margin * 2)
    }

    func beginDocument() {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(
                consumer: consumer,
                mediaBox: &mediaBox,
                nil
              ) else {
            return
        }
        self.context = context
        context.beginPDFPage(nil)
        paintPageBackground()
        pageNumber = 1
        cursorY = pageSize.height - margin
        documentStarted = true
    }

    func drawTitle(_ text: String) {
        draw(text, font: .systemFont(ofSize: 24, weight: .bold), color: ink)
    }

    func drawMuted(_ text: String) {
        draw(
            text,
            font: .systemFont(ofSize: 9, weight: .regular),
            color: mutedInk,
            spacingAfter: 3
        )
    }

    func drawSection(_ text: String) {
        ensureSpace(30)
        draw(
            text,
            font: .systemFont(ofSize: 14, weight: .bold),
            color: ink,
            spacingAfter: 7
        )
        drawRule()
        addSpace(7)
    }

    func drawMetricRow(_ metrics: [(String, String)]) {
        ensureSpace(56)
        let gap: CGFloat = 8
        let width = (contentWidth - gap * CGFloat(max(0, metrics.count - 1)))
            / CGFloat(max(1, metrics.count))
        let top = cursorY

        for (index, metric) in metrics.enumerated() {
            let x = margin + CGFloat(index) * (width + gap)
            context?.setFillColor(panelFill.cgColor)
            context?.fill(
                CGRect(
                    x: x,
                    y: top - 50,
                    width: width,
                    height: 50
                )
            )
            drawText(
                metric.0,
                x: x + 9,
                top: top - 8,
                width: width - 18,
                font: .systemFont(ofSize: 8, weight: .semibold),
                color: mutedInk
            )
            drawText(
                metric.1,
                x: x + 9,
                top: top - 23,
                width: width - 18,
                font: .systemFont(ofSize: 15, weight: .bold),
                color: ink
            )
        }
        cursorY -= 57
    }

    func drawKeyValue(_ key: String, value: String) {
        ensureSpace(18)
        drawText(
            key,
            x: margin,
            top: cursorY,
            width: contentWidth - 50,
            font: .systemFont(ofSize: 10, weight: .medium),
            color: ink
        )
        drawText(
            value,
            x: pageSize.width - margin - 44,
            top: cursorY,
            width: 44,
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            color: ink,
            alignment: .right
        )
        cursorY -= 18
    }

    func drawTeamMember(_ member: JiraTeamFlowMember) {
        ensureSpace(27)
        let summary = "Total \(member.assigned) | Active \(member.active) | Review "
            + "\(member.inReview) | QA \(member.inQA) | Done \(member.completed) | At risk \(member.atRisk)"
        drawText(
            member.name,
            x: margin,
            top: cursorY,
            width: 150,
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: ink
        )
        drawText(
            summary,
            x: margin + 158,
            top: cursorY,
            width: contentWidth - 158,
            font: .monospacedDigitSystemFont(ofSize: 8.5, weight: .regular),
            color: member.atRisk > 0 ? warningOrange : mutedInk,
            alignment: .right
        )
        cursorY -= 21
        drawRule(color: ruleColor, alpha: 0.7)
        cursorY -= 5
    }

    func beginContinuation(_ title: String) {
        continuationTitle = title
    }

    func endContinuation() {
        continuationTitle = nil
    }

    func drawTicketGroup(_ title: String, count: Int) {
        ensureSpace(32)
        currentTicketGroup = (title, count)
        drawTicketGroupBanner(title, count: count)
    }

    private func drawTicketGroupBanner(_ title: String, count: Int) {
        context?.setFillColor(panelFill.cgColor)
        context?.fill(
            CGRect(
                x: margin,
                y: cursorY - 23,
                width: contentWidth,
                height: 23
            )
        )
        drawText(
            title,
            x: margin + 8,
            top: cursorY - 6,
            width: contentWidth - 66,
            font: .systemFont(ofSize: 10, weight: .bold),
            color: ink
        )
        drawText(
            "\(count)",
            x: pageSize.width - margin - 48,
            top: cursorY - 6,
            width: 40,
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            color: mutedInk,
            alignment: .right
        )
        cursorY -= 31
    }

    func drawTicket(_ issue: JiraIssue) {
        let summaryHeight = measuredHeight(
            issue.fields.summary,
            width: contentWidth - 74,
            font: .systemFont(ofSize: 9.5, weight: .semibold)
        )
        let requiredHeight = max(37, summaryHeight + 20)
        ensureSpace(requiredHeight)

        drawText(
            issue.key,
            x: margin,
            top: cursorY,
            width: 70,
            font: .monospacedSystemFont(ofSize: 9, weight: .bold),
            color: accentBlue
        )
        drawText(
            issue.fields.summary,
            x: margin + 74,
            top: cursorY,
            width: contentWidth - 74,
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: ink
        )

        let meta = [
            issue.fields.issueType.name,
            issue.fields.priority?.name ?? "No priority",
            issue.fields.assignee?.displayName ?? "Unassigned",
            issue.updatedDate.map {
                "Updated \($0.formatted(date: .abbreviated, time: .omitted))"
            } ?? "No update date"
        ].joined(separator: " | ")
        drawText(
            meta,
            x: margin + 74,
            top: cursorY - summaryHeight - 3,
            width: contentWidth - 74,
            font: .systemFont(ofSize: 8, weight: .regular),
            color: mutedInk
        )
        cursorY -= requiredHeight
        drawRule(color: ruleColor, alpha: 0.55)
        cursorY -= 5
    }

    func addSpace(_ amount: CGFloat) {
        cursorY -= amount
    }

    func finish() throws -> Data {
        guard documentStarted, let context else {
            throw JiraPulseExportError.couldNotCreatePDF
        }
        drawFooter()
        context.endPDFPage()
        context.closePDF()
        guard data.length > 0 else {
            throw JiraPulseExportError.couldNotCreatePDF
        }
        return data as Data
    }

    private func draw(
        _ text: String,
        font: NSFont,
        color: NSColor,
        spacingAfter: CGFloat = 6
    ) {
        let height = measuredHeight(text, width: contentWidth, font: font)
        ensureSpace(height + spacingAfter)
        drawText(
            text,
            x: margin,
            top: cursorY,
            width: contentWidth,
            font: font,
            color: color
        )
        cursorY -= height + spacingAfter
    }

    private func ensureSpace(_ height: CGFloat) {
        guard cursorY - height < bottomMargin else { return }
        guard let context else { return }
        drawFooter()
        context.endPDFPage()
        context.beginPDFPage(nil)
        paintPageBackground()
        pageNumber += 1
        cursorY = pageSize.height - margin
        if let currentTicketGroup {
            drawTicketGroupBanner(
                "\(currentTicketGroup.title) (continued)",
                count: currentTicketGroup.count
            )
        } else if let continuationTitle {
            drawContinuationHeader("\(continuationTitle) (continued)")
        }
    }

    private func drawContinuationHeader(_ title: String) {
        drawText(
            title,
            x: margin,
            top: cursorY,
            width: contentWidth,
            font: .systemFont(ofSize: 14, weight: .bold),
            color: ink
        )
        cursorY -= 23
        drawRule()
        cursorY -= 9
    }

    private func drawRule(
        color: NSColor? = nil,
        alpha: CGFloat = 0.65
    ) {
        guard let context else { return }
        context.saveGState()
        context.setStrokeColor((color ?? ruleColor).withAlphaComponent(alpha).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: cursorY))
        context.addLine(to: CGPoint(x: pageSize.width - margin, y: cursorY))
        context.strokePath()
        context.restoreGState()
    }

    private func drawFooter() {
        drawText(
            "Tidy Project Pulse",
            x: margin,
            top: 28,
            width: contentWidth / 2,
            font: .systemFont(ofSize: 7.5, weight: .regular),
            color: faintInk
        )
        drawText(
            "Page \(pageNumber)",
            x: pageSize.width / 2,
            top: 28,
            width: contentWidth / 2,
            font: .monospacedDigitSystemFont(ofSize: 7.5, weight: .regular),
            color: faintInk,
            alignment: .right
        )
    }

    private func paintPageBackground() {
        guard let context else { return }
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: pageSize))
        context.restoreGState()
    }

    private func measuredHeight(
        _ text: String,
        width: CGFloat,
        font: NSFont
    ) -> CGFloat {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        return max(font.pointSize + 3, ceil(size.height))
    }

    private func drawText(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        guard let context else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil
        )
        let height = max(font.pointSize + 3, ceil(size.height))
        let path = CGPath(
            rect: CGRect(x: x, y: top - height, width: width, height: height),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(),
            path,
            nil
        )
        context.saveGState()
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

private enum JiraPulseExportError: LocalizedError {
    case couldNotCreatePDF

    var errorDescription: String? {
        "Tidy couldn’t create the PDF report."
    }
}
