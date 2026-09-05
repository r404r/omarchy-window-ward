import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = new URL(".", import.meta.url);
const modelPath = fileURLToPath(new URL("../WardModel.js", here));
const source = fs.readFileSync(modelPath, "utf8").replace(/^\.pragma library\s*\n/, "");
const context = { Number, JSON, String, Array, Object, RegExp };
vm.createContext(context);
vm.runInContext(source, context, { filename: modelPath });

const valid = {
  schemaVersion: 1,
  enabled: true,
  confirmWindowMs: 3000,
  protectedApplications: [{
    id: "google-chrome",
    name: "Google Chrome",
    enabled: true,
    mode: "double-press",
    match: { class: ["google-chrome"], initialClass: [] }
  }]
};

assert.deepEqual(JSON.parse(JSON.stringify(context.parseStatus(JSON.stringify(valid)))), {
  enabled: true,
  applications: [{
    id: "google-chrome",
    name: "Google Chrome",
    enabled: true,
    match: { class: ["google-chrome"], initialClass: [] }
  }]
});

for (const invalid of [
  "",
  "{}",
  "[]",
  "not json",
  JSON.stringify({ ...valid, enabled: "true" }),
  JSON.stringify({ ...valid, protectedApplications: undefined }),
  JSON.stringify({ ...valid, protectedApplications: [{ ...valid.protectedApplications[0], match: { class: [] } }] }),
  JSON.stringify({ ...valid, protectedApplications: [{ ...valid.protectedApplications[0], mode: "single-press" }] }),
  JSON.stringify({ ...valid, protectedApplications: [{ ...valid.protectedApplications[0], match: { class: ["  "], initialClass: [] } }] }),
  JSON.stringify({ ...valid, protectedApplications: [{ ...valid.protectedApplications[0], match: { class: ["bad\u0000class"], initialClass: [] } }] }),
  JSON.stringify({ ...valid, protectedApplications: [{ ...valid.protectedApplications[0], match: { class: ["x".repeat(257)], initialClass: [] } }] }),
  JSON.stringify({ ...valid, protectedApplications: [
    { ...valid.protectedApplications[0], id: "__proto__" },
    { ...valid.protectedApplications[0], id: "__proto__" }
  ] })
]) {
  assert.equal(context.parseStatus(invalid), null, `must reject ${invalid || "empty status"}`);
}

const oversized = structuredClone(valid);
oversized.protectedApplications = Array.from({ length: 129 }, (_, index) => ({
  ...valid.protectedApplications[0], id: `app-${index}`
}));
assert.equal(context.parseStatus(JSON.stringify(oversized)), null, "must reject over-limit applications");
console.log("ok");
