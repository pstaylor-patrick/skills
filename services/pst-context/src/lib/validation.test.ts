import { describe, expect, it } from "vitest";
import {
  validateRunInput,
  validateArtifactInput,
  validateLearningInput,
} from "./validation";

describe("validateRunInput", () => {
  it("returns valid data for complete input", () => {
    const result = validateRunInput({
      skill: "pst:qa",
      repo: "org/repo",
      branch: "main",
      prNumber: "42",
      outcome: "pass",
      metadata: { duration: 100 },
    });
    expect(result).toEqual({
      valid: true,
      data: {
        skill: "pst:qa",
        repo: "org/repo",
        branch: "main",
        prNumber: "42",
        outcome: "pass",
        metadata: { duration: 100 },
      },
    });
  });

  it("returns valid data with only required field", () => {
    const result = validateRunInput({ skill: "pst:push" });
    expect(result).toEqual({
      valid: true,
      data: {
        skill: "pst:push",
        repo: null,
        branch: null,
        prNumber: null,
        outcome: null,
        metadata: null,
      },
    });
  });

  it("rejects missing skill", () => {
    const result = validateRunInput({ repo: "org/repo" });
    expect(result).toEqual({ valid: false, error: "skill is required" });
  });

  it("rejects empty skill string", () => {
    const result = validateRunInput({ skill: "" });
    expect(result).toEqual({ valid: false, error: "skill is required" });
  });

  it("rejects non-string skill", () => {
    const result = validateRunInput({ skill: 123 });
    expect(result).toEqual({ valid: false, error: "skill is required" });
  });

  it("nullifies non-string optional fields", () => {
    const result = validateRunInput({
      skill: "pst:qa",
      repo: 42,
      branch: true,
    });
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.data.repo).toBeNull();
      expect(result.data.branch).toBeNull();
    }
  });

  it("nullifies array metadata", () => {
    const result = validateRunInput({ skill: "pst:qa", metadata: [1, 2, 3] });
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.data.metadata).toBeNull();
    }
  });
});

describe("validateArtifactInput", () => {
  it("returns valid data for complete input", () => {
    const result = validateArtifactInput({
      runId: "uuid-123",
      localPath: "~/Desktop/screenshot.png",
      artifactType: "screenshot",
      description: "Dashboard",
      metadata: { width: 1920 },
    });
    expect(result).toEqual({
      valid: true,
      data: {
        runId: "uuid-123",
        localPath: "~/Desktop/screenshot.png",
        artifactType: "screenshot",
        description: "Dashboard",
        metadata: { width: 1920 },
      },
    });
  });

  it("returns valid with only required fields", () => {
    const result = validateArtifactInput({
      localPath: "/tmp/file.txt",
      artifactType: "report",
    });
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.data.runId).toBeNull();
      expect(result.data.description).toBeNull();
      expect(result.data.metadata).toBeNull();
    }
  });

  it("rejects missing localPath", () => {
    const result = validateArtifactInput({ artifactType: "screenshot" });
    expect(result.valid).toBe(false);
  });

  it("rejects missing artifactType", () => {
    const result = validateArtifactInput({ localPath: "/tmp/file.txt" });
    expect(result.valid).toBe(false);
  });

  it("rejects empty strings", () => {
    const result = validateArtifactInput({ localPath: "", artifactType: "" });
    expect(result.valid).toBe(false);
  });
});

describe("validateLearningInput", () => {
  it("returns valid data for complete input", () => {
    const result = validateLearningInput({
      topic: "neon-config",
      content: "Use sslmode=require",
      sourceRepo: "org/repo",
      sourceRunId: "uuid-456",
      metadata: { confidence: "high" },
    });
    expect(result).toEqual({
      valid: true,
      data: {
        topic: "neon-config",
        content: "Use sslmode=require",
        sourceRepo: "org/repo",
        sourceRunId: "uuid-456",
        metadata: { confidence: "high" },
      },
    });
  });

  it("rejects missing topic", () => {
    const result = validateLearningInput({ content: "something" });
    expect(result).toEqual({
      valid: false,
      error: "topic and content are required",
    });
  });

  it("rejects missing content", () => {
    const result = validateLearningInput({ topic: "something" });
    expect(result).toEqual({
      valid: false,
      error: "topic and content are required",
    });
  });

  it("rejects empty topic", () => {
    const result = validateLearningInput({ topic: "", content: "x" });
    expect(result.valid).toBe(false);
  });

  it("rejects empty content", () => {
    const result = validateLearningInput({ topic: "x", content: "" });
    expect(result.valid).toBe(false);
  });

  it("nullifies non-string optional fields", () => {
    const result = validateLearningInput({
      topic: "x",
      content: "y",
      sourceRepo: 123,
      sourceRunId: false,
    });
    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.data.sourceRepo).toBeNull();
      expect(result.data.sourceRunId).toBeNull();
    }
  });
});
