import fs from "node:fs";
import path from "node:path";

export class JsonlEventSink {
  constructor(filePath) {
    this.filePath = filePath;
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
  }

  write(event) {
    fs.appendFileSync(this.filePath, `${JSON.stringify(event)}\n`, "utf8");
  }
}
