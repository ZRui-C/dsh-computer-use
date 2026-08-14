import Foundation
import Darwin

/// A minimal Unix-domain-socket server speaking newline-delimited JSON.
public final class UnixSocketServer {
    public let path: String
    private var listenFd: Int32 = -1
    private var running = false

    public init(path: String) {
        self.path = path
    }

    /// Binds and listens on the socket path, then accepts connections on a
    /// background queue. Returns once the socket is listening.
    public func start(agent: ComputerUseAgent) throws {
        unlink(path)

        listenFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFd >= 0 else {
            throw AgentError.socket("socket() failed: \(String(cString: strerror(errno)))")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        var pathBytes = Array(path.utf8)
        pathBytes.append(0)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes.prefix(buffer.count))
        }

        let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddr in
                bind(listenFd, sockAddr, addressLength)
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(listenFd)
            throw AgentError.socket("bind() failed for \(path): \(message)")
        }

        guard chmod(path, S_IRUSR | S_IWUSR) == 0 else {
            let message = String(cString: strerror(errno))
            close(listenFd)
            unlink(path)
            throw AgentError.socket("chmod() failed for \(path): \(message)")
        }

        guard listen(listenFd, 16) == 0 else {
            let message = String(cString: strerror(errno))
            close(listenFd)
            throw AgentError.socket("listen() failed: \(message)")
        }

        running = true
        DispatchQueue.global(qos: .userInitiated).async {
            self.acceptLoop(agent: agent)
        }
    }

    public func stop() {
        running = false
        if listenFd >= 0 {
            close(listenFd)
            listenFd = -1
        }
        unlink(path)
    }

    private func acceptLoop(agent: ComputerUseAgent) {
        while running {
            let client = accept(listenFd, nil, nil)
            if client < 0 {
                if !running { break }
                continue
            }
            DispatchQueue.global(qos: .userInitiated).async {
                self.handle(client: client, agent: agent)
            }
        }
    }

    private func handle(client: Int32, agent: ComputerUseAgent) {
        defer { close(client) }

        var buffer = Data()
        var readBuffer = [UInt8](repeating: 0, count: 8192)

        while running {
            let bytesRead = read(client, &readBuffer, readBuffer.count)
            if bytesRead <= 0 { break }
            buffer.append(contentsOf: readBuffer[0..<bytesRead])
            buffer = processCompleteLines(in: buffer, agent: agent, fd: client)
        }
    }

    private func processCompleteLines(in buffer: Data, agent: ComputerUseAgent, fd: Int32) -> Data {
        var remaining = buffer
        while let newlineIndex = remaining.firstIndex(of: 0x0A) {
            let line = remaining[remaining.startIndex..<newlineIndex]
            remaining.removeSubrange(remaining.startIndex...newlineIndex)
            handleLine(line, agent: agent, fd: fd)
        }
        return remaining
    }

    private func handleLine(_ line: Data, agent: ComputerUseAgent, fd: Int32) {
        guard let text = String(data: line, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        guard let requestData = text.data(using: .utf8),
              let request = try? JSONDecoder().decode(Request.self, from: requestData) else {
            let response = Response.failure(
                id: "",
                error: .object([
                    "code": .string("INVALID_REQUEST"),
                    "message": .string("Request line is not valid NDJSON"),
                ])
            )
            sendResponse(response, fd: fd)
            return
        }

        let response = agent.handle(request: request)
        sendResponse(response, fd: fd)
    }

    private func sendResponse(_ response: Response, fd: Int32) {
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { rawBuffer in
            _ = Darwin.write(fd, rawBuffer.baseAddress, rawBuffer.count)
        }
    }
}
