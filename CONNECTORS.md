# Tidy Connector SDK

Tidy connectors declare capabilities and privacy behavior before they expose
data to a workflow. The initial SDK is intentionally small: it standardizes
identity, permissions, retention, and user-facing disclosure while existing
MCP, Jira, and Asana clients keep their proven transport implementations.

## Contract

A connector conforms to `TidyConnector` and provides a
`TidyConnectorDescriptor` containing:

- a stable namespaced identifier;
- a user-facing title and SF Symbol;
- explicit read and write capabilities;
- whether the connector is read-only by default;
- what data it reads, whether data can be sent to AI, and how it is retained.

```swift
struct ExampleConnector: TidyConnector {
    let descriptor = TidyConnectorDescriptor(
        id: "example-alerts",
        title: "Example Alerts",
        systemImage: "bell",
        capabilities: [.readServiceHealth],
        isReadOnlyByDefault: true,
        privacy: ConnectorPrivacyDisclosure(
            dataRead: "Open alerts selected by the user",
            dataSentToAI: nil,
            retention: .memoryOnly
        )
    )
}
```

## Safety requirements

1. Use a stable identifier that cannot collide with another connector.
2. Request the smallest capability set needed for the feature.
3. Default to read-only behavior. Writes must be initiated and previewed by the
   user.
4. Keep credentials in Keychain and reject credentials embedded in URLs.
5. Do not persist third-party content unless the disclosure declares it.
6. Use synthetic test fixtures and reserved example domains.
7. Treat remote tool output as untrusted input, including when building an AI
   prompt.

Future connector execution APIs can build on this contract without changing
the privacy and capability declarations shipped in the first version.
