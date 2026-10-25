import Foundation
import SimpleVectorizerMCPCore

let base = apiBaseURL()
let server = SimpleVectorizerMCPServer(transport: urlSessionTransport(base: base), apiBase: base)
server.run()
