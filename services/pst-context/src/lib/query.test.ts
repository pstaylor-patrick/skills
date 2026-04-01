import { describe, expect, it } from "vitest";
import { parseLimit, escapeLikePattern, parseJsonBody } from "./query";

describe("parseLimit", () => {
  it("returns default 50 for null", () => {
    expect(parseLimit(null)).toBe(50);
  });

  it("parses valid number", () => {
    expect(parseLimit("25")).toBe(25);
  });

  it("caps at 100", () => {
    expect(parseLimit("200")).toBe(100);
  });

  it("returns default for non-numeric string", () => {
    expect(parseLimit("abc")).toBe(50);
  });

  it("returns default for zero", () => {
    expect(parseLimit("0")).toBe(50);
  });

  it("returns default for negative", () => {
    expect(parseLimit("-5")).toBe(50);
  });

  it("returns default for Infinity", () => {
    expect(parseLimit("Infinity")).toBe(50);
  });

  it("handles float by truncating via Math.min", () => {
    expect(parseLimit("25.7")).toBe(25.7);
  });

  it("caps exactly at 100", () => {
    expect(parseLimit("100")).toBe(100);
  });

  it("returns 1 for minimum valid", () => {
    expect(parseLimit("1")).toBe(1);
  });
});

describe("escapeLikePattern", () => {
  it("returns plain strings unchanged", () => {
    expect(escapeLikePattern("hello world")).toBe("hello world");
  });

  it("escapes percent", () => {
    expect(escapeLikePattern("100%")).toBe("100\\%");
  });

  it("escapes underscore", () => {
    expect(escapeLikePattern("user_name")).toBe("user\\_name");
  });

  it("escapes backslash", () => {
    expect(escapeLikePattern("path\\to")).toBe("path\\\\to");
  });

  it("escapes all special characters together", () => {
    expect(escapeLikePattern("%_\\")).toBe("\\%\\_\\\\");
  });

  it("handles empty string", () => {
    expect(escapeLikePattern("")).toBe("");
  });

  it("handles string with only special chars", () => {
    expect(escapeLikePattern("%%%")).toBe("\\%\\%\\%");
  });
});

describe("parseJsonBody", () => {
  it("accepts plain object", () => {
    const result = parseJsonBody({ key: "value" });
    expect(result).toEqual({ ok: true, data: { key: "value" } });
  });

  it("accepts empty object", () => {
    const result = parseJsonBody({});
    expect(result).toEqual({ ok: true, data: {} });
  });

  it("rejects null", () => {
    expect(parseJsonBody(null)).toEqual({ ok: false });
  });

  it("rejects array", () => {
    expect(parseJsonBody([1, 2, 3])).toEqual({ ok: false });
  });

  it("rejects string", () => {
    expect(parseJsonBody("hello")).toEqual({ ok: false });
  });

  it("rejects number", () => {
    expect(parseJsonBody(42)).toEqual({ ok: false });
  });

  it("rejects undefined", () => {
    expect(parseJsonBody(undefined)).toEqual({ ok: false });
  });
});
