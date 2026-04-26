import { createServer } from "node:http";
import { config } from "./src/config.mjs";
import { handleRequest } from "./src/routes.mjs";

const server = createServer((req, res) => {
  handleRequest(req, res);
});

server.listen(config.port, config.host, () => {
  console.log(`Warframe KB local API listening on http://${config.host}:${config.port}`);
});
