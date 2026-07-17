import { createApp } from "./app.js";
import { createHttpServer } from "./http-server.js";

const app = createApp();
const server = createHttpServer(app);

server.listen(app.config.port, () => {
  console.log(`GridShare difficult core listening on http://localhost:${app.config.port}`);
});
