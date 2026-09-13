const fs = require("fs")

fs.writeFileSync(
  "/app/dist/extensions/slack/node_modules/ws/wrapper.mjs",
  `import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const createWebSocketStream = require('./lib/stream.js');
const extension = require('./lib/extension.js');
const PerMessageDeflate = require('./lib/permessage-deflate.js');
const Receiver = require('./lib/receiver.js');
const Sender = require('./lib/sender.js');
const subprotocol = require('./lib/subprotocol.js');
const WebSocket = require('./lib/websocket.js');
const WebSocketServer = require('./lib/websocket-server.js');

export {
  createWebSocketStream,
  extension,
  PerMessageDeflate,
  Receiver,
  Sender,
  subprotocol,
  WebSocket,
  WebSocketServer
};

export default WebSocket;
`,
)
