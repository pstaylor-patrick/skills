// Copies the canonical CHANGE.md frontmatter spec into the site source at build
// time, so the page ships a self-contained snapshot whose version always matches
// what was built. Runs as the prebuild/predev step; the generated file is
// git-ignored because it is derived from the spec, not authored here.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const source = resolve(here, "../../skills/change/reference/CHANGE-frontmatter-spec.md");
const target = resolve(here, "../src/generated/spec.md");

mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, readFileSync(source, "utf8"));
console.log(`embedded spec: ${source} -> ${target}`);
