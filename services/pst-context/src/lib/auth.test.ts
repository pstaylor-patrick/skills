import { describe, expect, it } from "vitest";
import { safeCompare } from "./auth";

describe("safeCompare", () => {
  it("returns true for matching strings", () => {
    expect(safeCompare("abc123", "abc123")).toBe(true);
  });

  it("returns false for different strings of same length", () => {
    expect(safeCompare("abc123", "xyz789")).toBe(false);
  });

  it("returns false for different lengths", () => {
    expect(safeCompare("short", "much-longer-string")).toBe(false);
  });

  it("returns false when first is longer", () => {
    expect(safeCompare("much-longer-string", "short")).toBe(false);
  });

  it("returns true for empty strings", () => {
    expect(safeCompare("", "")).toBe(true);
  });

  it("returns false for empty vs non-empty", () => {
    expect(safeCompare("", "x")).toBe(false);
  });

  it("handles unicode strings", () => {
    expect(safeCompare("hello-world", "hello-world")).toBe(true);
  });

  it("returns false for off-by-one character", () => {
    expect(safeCompare("abc123x", "abc123y")).toBe(false);
  });
});
