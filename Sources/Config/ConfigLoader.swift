import Foundation

// MARK: - Errors

enum ConfigError: Error, Equatable {
    case fileNotFound(URL)
    case invalidJSON(String)
    case invalidVersion(String)
    case decodingFailed(String)
}

// MARK: - Loader (순수 함수 파이프라인)

/// 설정 로딩 파이프라인.
/// loadConfig() = 번들 기본값 + 사용자 override deep merge
func loadConfig() -> Result<AppConfig, ConfigError> {
    loadBundleDefault()
        .flatMap { defaultConfig in
            loadUserConfig()
                .flatMap { userJSON -> Result<AppConfig, ConfigError> in
                    guard let userJSON else {
                        return .success(defaultConfig)
                    }
                    return merge(base: defaultConfig, override: userJSON)
                }
        }
}

// MARK: - Step 1: 번들 기본값

private func loadBundleDefault() -> Result<AppConfig, ConfigError> {
    guard let url = Bundle.main.url(forResource: "default-config", withExtension: "json") else {
        // 번들에 파일이 없으면 하드코딩 기본값 사용
        return .success(.default)
    }
    return readJSON(from: url)
        .flatMap(parseConfig)
}

// MARK: - Step 2: 사용자 파일 (없으면 nil)

private func loadUserConfig() -> Result<[String: Any]?, ConfigError> {
    let url = userConfigURL()
    guard FileManager.default.fileExists(atPath: url.path) else {
        return .success(nil)
    }
    return readJSON(from: url).map(Optional.some)
}

// MARK: - Step 3: Deep merge

func merge(base: AppConfig, override json: [String: Any]) -> Result<AppConfig, ConfigError> {
    // 기본값을 JSON으로 직렬화 → override와 merge → 재파싱
    let baseJSON = encodeToJSON(base)
    let merged   = deepMerge(base: baseJSON, override: json)
    return parseConfig(from: merged)
}

// MARK: - JSON parsing (순수 함수)

func parseConfig(from json: [String: Any]) -> Result<AppConfig, ConfigError> {
    do {
        let data   = try JSONSerialization.data(withJSONObject: json)
        let config = try JSONDecoder().decode(AppConfigCodable.self, from: data)
        return .success(config.toAppConfig())
    } catch {
        return .failure(.decodingFailed(error.localizedDescription))
    }
}

// MARK: - File I/O (순수 함수)

private func readJSON(from url: URL) -> Result<[String: Any], ConfigError> {
    do {
        let data = try Data(contentsOf: url)
        let obj  = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            return .failure(.invalidJSON("Root must be a JSON object"))
        }
        return .success(dict)
    } catch {
        return .failure(.invalidJSON(error.localizedDescription))
    }
}

// MARK: - Deep merge (순수 함수)

private func deepMerge(base: [String: Any], override: [String: Any]) -> [String: Any] {
    override.reduce(into: base) { result, pair in
        if let baseDict  = result[pair.key] as? [String: Any],
           let overrideDict = pair.value as? [String: Any] {
            result[pair.key] = deepMerge(base: baseDict, override: overrideDict)
        } else {
            result[pair.key] = pair.value
        }
    }
}

// MARK: - Encode to JSON dict (순수 함수)

private func encodeToJSON(_ config: AppConfig) -> [String: Any] {
    guard let data = try? JSONEncoder().encode(AppConfigCodable(config)),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return dict
}

// MARK: - Save user config

/// 현재 AppConfig를 사용자 설정 파일에 저장.
/// ConfigWatcher가 변경을 감지해 ConfigManager가 자동으로 재로드.
@discardableResult
func saveUserConfig(_ config: AppConfig) -> Result<Void, ConfigError> {
    let url = userConfigURL()
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(AppConfigCodable(config))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: url, options: .atomic)
        return .success(())
    } catch {
        return .failure(.decodingFailed(error.localizedDescription))
    }
}

// MARK: - Paths

func userConfigURL() -> URL {
    FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Intend/config.json")
}
