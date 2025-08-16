import UIKit

public enum Mode: String, Codable { case enhance, reply }

public enum Style: String, CaseIterable, Codable {
    case formal, friendly, lovely, concise, technical
}

public struct StickyKey: Hashable, Codable {
    public let returnKey: UIReturnKeyType.RawValue
    public let keyboardType: UIKeyboardType.RawValue
    public let autoCap: UITextAutocapitalizationType.RawValue
}

public struct StickyPreference: Codable { public let mode: Mode; public let style: Style }

public enum TransformError: Error { case offline, badResponse, server(String) }

public let APP_GROUP_ID = "group.com.yourco.KeyboardAI"

public let DEFAULT_API_ENDPOINT_KEY = "api.endpoint"
public let DEFAULT_API_KEY_KEY      = "api.key"
public let TIP_COUNTER_KEY          = "tipUsesRemaining"
public let USE_LOCAL_MODEL_KEY      = "useLocalModel"
