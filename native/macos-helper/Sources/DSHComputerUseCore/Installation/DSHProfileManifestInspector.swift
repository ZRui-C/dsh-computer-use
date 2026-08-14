import Foundation

public enum DSHProfilePluginStatus: Equatable {
    case missing
    case dependencyOnly
    case active
}

public enum DSHProfileManifestInspector {
    public static func pluginStatus(
        in data: Data,
        packageName: String
    ) -> DSHProfilePluginStatus {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dependencies = object["dependencies"] as? [String: Any],
              dependencies[packageName] is String else {
            return .missing
        }
        guard let dsh = object["dsh"] as? [String: Any],
              let profile = dsh["profile"] as? [String: Any],
              let bundles = profile["bundles"] as? [Any],
              bundles.contains(where: { ($0 as? String) == packageName }) else {
            return .dependencyOnly
        }
        return .active
    }
}
