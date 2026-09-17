# Delphi WebSocket Server
A simple and lightweight Delphi class that runs a WebSocket server. 
Initially, it was developed for CodeRage 2019. 
See the explanation and demonstration video on Embarcadero YouTube channel: https://www.youtube.com/watch?v=kg-rWjbKEUc

# Contact
- E-mail: stas@forji.ai
- Website: https://staspiter.com
- Github: https://github.com/staspiter
- Facebook: https://www.facebook.com/piterstas/

# Features
- Based on Indy TCP server
- WSS (WebSocket Secured)

# Included demos
- Quick start - a basic demo that runs a server, that responds with received messages.
- Circles - an advanced demo with entities, data streaming and actions.
- WSS - demo of using an SSL/TLS certificate to run a secured WebSocket server.
- HTTP and WebSocket - serves the client html page over plain HTTP and handles WebSocket connections on the same port.

# Usage
- Include WebSocketServer.pas unit.
- Follow the first demo to create an instance of TWebSocketServer.
- Define OnExecute event and handle it as a usual Indy TCP server.
- Connect to the WebSocket from a JS code or use any WebSocket client.

# Serving plain HTTP on the same port
A browser does not upgrade the connection that it used to load the page - it opens a separate TCP connection for the WebSocket. So a connection that is used for plain HTTP has to be closed by the server once the response has been sent, otherwise its Indy thread stays alive with nothing on the other end.

Data received from a connection that has not been handshaked is left in the IOHandler's InputBuffer, so it can be read and answered in the OnExecute event (see the HTTP and WebSocket demo). Connections that do not complete the handshake within HandshakeTimeout milliseconds (10 seconds by default, 0 disables it) are disconnected, so that a client which connects and stays silent does not occupy a thread forever.
