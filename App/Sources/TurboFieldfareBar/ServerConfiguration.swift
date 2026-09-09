import Foundation

public struct ServerConfiguration: Codable, Equatable {
    // 1. 监听端口 (默认: 1235)
    public var port: Int
    
    // 2. 最大上下文长度 (4096, 8192, 16384, 32768, 65536)
    public var maxContext: Int
    
    // 3. 专家缓存槽位数 (8, 16, 24, 32)
    public var expertCacheSlots: Int
    
    // 4. 专家缓存淘汰策略 (lfu, lru)
    public var expertCachePolicy: String
    
    // 5. 分块 Prompt 预热 (on, off)
    public var prefill: String
    
    // 6. Prefill 分块大小 (auto, 256, 128, 64, 32)
    public var prefillChunkTokens: String
    
    // 7. 视觉模块常驻策略 (on-demand, keep-ready)
    public var visionResidency: String
    
    // 8. KV 缓存复用模式 (single-prefix, off)
    public var promptCacheMode: String

    public init(
        port: Int = 1235,
        maxContext: Int = 32768,
        expertCacheSlots: Int = 24,
        expertCachePolicy: String = "lfu",
        prefill: String = "on",
        prefillChunkTokens: String = "auto",
        visionResidency: String = "on-demand",
        promptCacheMode: String = "single-prefix"
    ) {
        self.port = port
        self.maxContext = maxContext
        self.expertCacheSlots = expertCacheSlots
        self.expertCachePolicy = expertCachePolicy
        self.prefill = prefill
        self.prefillChunkTokens = prefillChunkTokens
        self.visionResidency = visionResidency
        self.promptCacheMode = promptCacheMode
    }

    /// 官方与脚本默认推荐配置基准
    public static let `default` = ServerConfiguration(
        port: 1235,
        maxContext: 32768,
        expertCacheSlots: 24,
        expertCachePolicy: "lfu",
        prefill: "on",
        prefillChunkTokens: "auto",
        visionResidency: "on-demand",
        promptCacheMode: "single-prefix"
    )

    private static let userDefaultsKey = "TurboFieldfare_ServerConfiguration"

    public static var configDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TurboFieldfare")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static var envConfigFile: URL {
        configDirectory.appendingPathComponent("config.env")
    }

    /// 读取持久化配置
    public static func load() -> ServerConfiguration {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(ServerConfiguration.self, from: data) {
            return decoded
        }
        return .default
    }

    /// 保存配置并同步导出环境变量文件（供命令行 server.sh 共享）
    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: ServerConfiguration.userDefaultsKey)
        }
        exportToEnvFile()
    }

    /// 导出为 Shell 可识别的 config.env
    public func exportToEnvFile() {
        let envContent = """
        # TurboFieldfare 运行配置 (由 TurboFieldfareBar 自动生成)
        export TURBO_PORT=\(port)
        export TURBO_MAX_CONTEXT=\(maxContext)
        export TURBO_EXPERT_CACHE_SLOTS=\(expertCacheSlots)
        export TURBO_EXPERT_CACHE_POLICY="\(expertCachePolicy)"
        export TURBO_PREFILL="\(prefill)"
        export TURBO_PREFILL_CHUNK_TOKENS="\(prefillChunkTokens)"
        export TURBO_VISION_RESIDENCY="\(visionResidency)"
        export TURBO_PROMPT_CACHE_MODE="\(promptCacheMode)"
        """
        try? envContent.write(to: ServerConfiguration.envConfigFile, atomically: true, encoding: .utf8)
    }

    /// 生成注入到 Process.environment 的字典
    public var environmentDictionary: [String: String] {
        return [
            "TURBO_PORT": "\(port)",
            "TURBO_MAX_CONTEXT": "\(maxContext)",
            "TURBO_EXPERT_CACHE_SLOTS": "\(expertCacheSlots)",
            "TURBO_EXPERT_CACHE_POLICY": expertCachePolicy,
            "TURBO_PREFILL": prefill,
            "TURBO_PREFILL_CHUNK_TOKENS": prefillChunkTokens,
            "TURBO_VISION_RESIDENCY": visionResidency,
            "TURBO_PROMPT_CACHE_MODE": promptCacheMode
        ]
    }
}
