import Foundation
import Network

@MainActor
final class CompanionManager: ObservableObject {
    @Published private(set) var discoveredPeers: [CompanionPeer] = []
    @Published private(set) var connectionState: CompanionConnectionState = .off

    var onMessage: ((CompanionMessage) -> Void)?

    private let serviceType = "_vibectl._tcp"
    private let localName = Host.current().localizedName ?? "Vibe Controller"

    private var mode: CompanionMode = .off
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var connection: NWConnection?
    private var endpointsByID: [String: NWEndpoint] = [:]
    private var receiveBuffer = Data()

    func setMode(_ mode: CompanionMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        stop()

        switch mode {
        case .off:
            connectionState = .off
        case .controller:
            startBrowsing()
        case .receiver:
            startListening()
        }
    }

    func connect(to peerID: String) {
        guard let endpoint = endpointsByID[peerID],
              let peer = discoveredPeers.first(where: { $0.id == peerID }) else {
            return
        }

        disconnect()

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        connectionState = .connecting(peer.name)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state, peerName: peer.name)
            }
        }
        connection.start(queue: .main)
        startReceiving(on: connection)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        switch mode {
        case .off:
            connectionState = .off
        case .controller:
            connectionState = .browsing
        case .receiver:
            connectionState = .listening
        }
    }

    func send(_ message: CompanionMessage) {
        guard let connection else { return }
        do {
            let payload = try JSONEncoder().encode(message) + Data([0x0A])
            connection.send(content: payload, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.connectionState = .error(error.localizedDescription)
                    }
                }
            })
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    private func stop() {
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
        disconnect()
        discoveredPeers = []
        endpointsByID = [:]
    }

    private func startBrowsing() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        self.browser = browser
        connectionState = .browsing

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed(let error):
                    self?.connectionState = .error(error.localizedDescription)
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleBrowseResults(results)
            }
        }

        browser.start(queue: .main)
    }

    private func startListening() {
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: localName, type: serviceType)
            self.listener = listener
            connectionState = .listening

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .failed(let error):
                        self?.connectionState = .error(error.localizedDescription)
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.accept(connection: connection)
                }
            }

            listener.start(queue: .main)
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    private func accept(connection: NWConnection) {
        disconnect()
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state, peerName: "controller")
            }
        }
        connection.start(queue: .main)
        startReceiving(on: connection)
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        endpointsByID = Dictionary(
            uniqueKeysWithValues: results.map { endpoint in
                let id = endpoint.endpoint.debugDescription
                return (id, endpoint.endpoint)
            }
        )
        discoveredPeers = results.map { result in
            let id = result.endpoint.debugDescription
            let name: String
            switch result.endpoint {
            case .service(let serviceName, _, _, _):
                name = serviceName
            default:
                name = result.endpoint.debugDescription
            }
            return CompanionPeer(id: id, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if case .connected = connectionState {
            return
        }

        if connection == nil, let firstPeer = discoveredPeers.first {
            connect(to: firstPeer.id)
        }
    }

    private func handleConnectionState(_ state: NWConnection.State, peerName: String) {
        switch state {
        case .ready:
            connectionState = .connected(peerName)
            send(.hello(name: localName))
        case .failed(let error):
            connectionState = .error(error.localizedDescription)
            disconnect()
        case .cancelled:
            disconnect()
        case .waiting(let error):
            connectionState = .error(error.localizedDescription)
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.connectionState = .error(error.localizedDescription)
                    self.disconnect()
                    return
                }
                if let content, !content.isEmpty {
                    self.receiveBuffer.append(content)
                    self.drainReceiveBuffer()
                }
                if isComplete {
                    self.disconnect()
                    return
                }
                self.startReceiving(on: connection)
            }
        }
    }

    private func drainReceiveBuffer() {
        while let newlineRange = receiveBuffer.firstRange(of: Data([0x0A])) {
            let packet = receiveBuffer.subdata(in: receiveBuffer.startIndex..<newlineRange.lowerBound)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...newlineRange.lowerBound)
            guard !packet.isEmpty else { continue }
            do {
                let message = try JSONDecoder().decode(CompanionMessage.self, from: packet)
                if message.type == .hello, let name = message.name {
                    connectionState = .connected(name)
                }
                onMessage?(message)
            } catch {
                connectionState = .error("Invalid companion packet")
            }
        }
    }
}
