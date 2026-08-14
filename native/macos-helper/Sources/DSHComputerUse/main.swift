import AppKit
import Foundation
import DSHComputerUseCore

private enum AgentRuntime {
    static var requested: Bool {
        CommandLine.arguments.contains("--agent") || CommandLine.arguments.contains("--socket")
    }

    static func run() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let socketPath = resolveSocketPath()
        let agent = ComputerUseAgent()
        agent.socketPath = socketPath
        let server = UnixSocketServer(path: socketPath)

        do {
            try server.start(agent: agent)
            FileHandle.standardOutput.write(
                "DSHComputerUse agent listening on \(socketPath)\n".data(using: .utf8)!
            )
            RunLoop.main.run()
        } catch {
            FileHandle.standardError.write(
                "DSHComputerUse agent failed to start: \(error.localizedDescription)\n".data(using: .utf8)!
            )
            exit(1)
        }
    }

    private static func resolveSocketPath() -> String {
        if let index = CommandLine.arguments.firstIndex(of: "--socket"),
           index + 1 < CommandLine.arguments.count {
            return CommandLine.arguments[index + 1]
        }
        let environment = ProcessInfo.processInfo.environment
        for key in ["DSH_COMPUTER_USE_SOCKET", "DEEPSEEK_AGENT_SOCKET"] {
            if let value = environment[key], !value.isEmpty { return value }
        }
        return "/tmp/dsh-computer-use-agent.sock"
    }
}

if AgentRuntime.requested {
    AgentRuntime.run()
} else {
    MainActor.assumeIsolated {
        SetupApplication.run()
    }
}
