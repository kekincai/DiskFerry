import Darwin
import Foundation

/// Talks to the rclone remote-control server that each transfer process starts on
/// 127.0.0.1. rclone writes its human-readable stats into `--log-file`, so stdout/stderr
/// carry nothing useful; `core/stats` is the only accurate, cheap live source.
struct RcloneRemoteControl: Sendable {
    let port: UInt16
    let user: String
    let password: String

    static func makeLocal() throws -> RcloneRemoteControl {
        RcloneRemoteControl(
            port: try freeLoopbackPort(),
            user: "diskferry",
            password: UUID().uuidString.replacingOccurrences(of: "-", with: "")
        )
    }

    var arguments: [String] {
        [
            "--rc",
            "--rc-addr", "127.0.0.1:\(port)",
            "--rc-user", user,
            "--rc-pass", password
        ]
    }

    var statsURL: URL {
        URL(string: "http://127.0.0.1:\(port)/core/stats")!
    }

    private static func freeLoopbackPort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PortError.unavailable }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw PortError.unavailable }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else { throw PortError.unavailable }
        return UInt16(bigEndian: address.sin_port)
    }

    enum PortError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "无法为 rclone 分配本地统计端口。"
        }
    }
}

/// Subset of rclone's `core/stats` response that Disk Ferry displays.
struct RcloneCoreStats: Decodable, Equatable, Sendable {
    var bytes: Int64
    var totalBytes: Int64
    var transfers: Int
    var totalTransfers: Int
    var checks: Int
    var totalChecks: Int
    var listed: Int
    var errors: Int
    var fatalError: Bool
    var lastError: String?
    var speed: Double
    var eta: Double?
    var elapsedTime: Double
    var transferring: [Item]

    struct Item: Decodable, Equatable, Sendable {
        var name: String
        var size: Int64
        var bytes: Int64
        var percentage: Int
        var speedAvg: Double?
    }

    private enum CodingKeys: String, CodingKey {
        case bytes, totalBytes, transfers, totalTransfers, checks, totalChecks, listed
        case errors, fatalError, lastError, speed, eta, elapsedTime, transferring
    }

    init(
        bytes: Int64 = 0,
        totalBytes: Int64 = 0,
        transfers: Int = 0,
        totalTransfers: Int = 0,
        checks: Int = 0,
        totalChecks: Int = 0,
        listed: Int = 0,
        errors: Int = 0,
        fatalError: Bool = false,
        lastError: String? = nil,
        speed: Double = 0,
        eta: Double? = nil,
        elapsedTime: Double = 0,
        transferring: [Item] = []
    ) {
        self.bytes = bytes
        self.totalBytes = totalBytes
        self.transfers = transfers
        self.totalTransfers = totalTransfers
        self.checks = checks
        self.totalChecks = totalChecks
        self.listed = listed
        self.errors = errors
        self.fatalError = fatalError
        self.lastError = lastError
        self.speed = speed
        self.eta = eta
        self.elapsedTime = elapsedTime
        self.transferring = transferring
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bytes = try container.decodeIfPresent(Int64.self, forKey: .bytes) ?? 0
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        transfers = try container.decodeIfPresent(Int.self, forKey: .transfers) ?? 0
        totalTransfers = try container.decodeIfPresent(Int.self, forKey: .totalTransfers) ?? 0
        checks = try container.decodeIfPresent(Int.self, forKey: .checks) ?? 0
        totalChecks = try container.decodeIfPresent(Int.self, forKey: .totalChecks) ?? 0
        listed = try container.decodeIfPresent(Int.self, forKey: .listed) ?? 0
        errors = try container.decodeIfPresent(Int.self, forKey: .errors) ?? 0
        fatalError = try container.decodeIfPresent(Bool.self, forKey: .fatalError) ?? false
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 0
        // rclone reports `eta: null` when it cannot estimate yet.
        eta = try? container.decodeIfPresent(Double.self, forKey: .eta)
        elapsedTime = try container.decodeIfPresent(Double.self, forKey: .elapsedTime) ?? 0
        transferring = try container.decodeIfPresent([Item].self, forKey: .transferring) ?? []
    }
}

extension RcloneCoreStats.Item {
    private enum CodingKeys: String, CodingKey {
        case name, size, bytes, percentage, speedAvg
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        bytes = try container.decodeIfPresent(Int64.self, forKey: .bytes) ?? 0
        percentage = try container.decodeIfPresent(Int.self, forKey: .percentage) ?? 0
        speedAvg = try container.decodeIfPresent(Double.self, forKey: .speedAvg)
    }
}

final class RcloneStatsClient: Sendable {
    private let remote: RcloneRemoteControl
    private let session: URLSession

    init(remote: RcloneRemoteControl) {
        self.remote = remote
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = [:]
        self.session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func fetch() async throws -> RcloneCoreStats {
        var request = URLRequest(url: remote.statsURL)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(remote.user):\(remote.password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(RcloneCoreStats.self, from: data)
    }
}
