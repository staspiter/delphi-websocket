# Delphi WebSocket Server
A simple and lightweight Delphi class that runs a WebSocket server. 
Initially, it was developed for CodeRage 2019. 
See the explanation and demonstration video on Embarcadero YouTube channel: https://www.youtube.com/watch?v=kg-rWjbKEUc

# Contact
- E-mail: stas@forji.org
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

# Usage
- Include WebSocketServer.pas unit.
- Follow the first demo to create an instance of TWebSocketServer.
- Define OnExecute event and handle it as a usual Indy TCP server.
- Connect to the WebSocket from a JS code or use any WebSocket client.