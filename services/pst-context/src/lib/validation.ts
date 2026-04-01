type ValidationSuccess<T> = { valid: true; data: T };
type ValidationFailure = { valid: false; error: string };
type ValidationResult<T> = ValidationSuccess<T> | ValidationFailure;

export interface RunInput {
  skill: string;
  repo: string | null;
  branch: string | null;
  prNumber: string | null;
  outcome: string | null;
  metadata: Record<string, unknown> | null;
}

export interface ArtifactInput {
  runId: string | null;
  localPath: string;
  artifactType: string;
  description: string | null;
  metadata: Record<string, unknown> | null;
}

export interface LearningInput {
  topic: string;
  content: string;
  sourceRepo: string | null;
  sourceRunId: string | null;
  metadata: Record<string, unknown> | null;
}

export function validateRunInput(
  body: Record<string, unknown>,
): ValidationResult<RunInput> {
  const { skill, repo, branch, prNumber, outcome, metadata } = body;
  if (!skill || typeof skill !== "string") {
    return { valid: false, error: "skill is required" };
  }
  return {
    valid: true,
    data: {
      skill,
      repo: typeof repo === "string" ? repo : null,
      branch: typeof branch === "string" ? branch : null,
      prNumber: typeof prNumber === "string" ? prNumber : null,
      outcome: typeof outcome === "string" ? outcome : null,
      metadata: isRecord(metadata) ? metadata : null,
    },
  };
}

export function validateArtifactInput(
  body: Record<string, unknown>,
): ValidationResult<ArtifactInput> {
  const { runId, localPath, artifactType, description, metadata } = body;
  if (!localPath || typeof localPath !== "string") {
    return { valid: false, error: "localPath and artifactType are required" };
  }
  if (!artifactType || typeof artifactType !== "string") {
    return { valid: false, error: "localPath and artifactType are required" };
  }
  return {
    valid: true,
    data: {
      runId: typeof runId === "string" ? runId : null,
      localPath,
      artifactType,
      description: typeof description === "string" ? description : null,
      metadata: isRecord(metadata) ? metadata : null,
    },
  };
}

export function validateLearningInput(
  body: Record<string, unknown>,
): ValidationResult<LearningInput> {
  const { topic, content, sourceRepo, sourceRunId, metadata } = body;
  if (!topic || typeof topic !== "string") {
    return { valid: false, error: "topic and content are required" };
  }
  if (!content || typeof content !== "string") {
    return { valid: false, error: "topic and content are required" };
  }
  return {
    valid: true,
    data: {
      topic,
      content,
      sourceRepo: typeof sourceRepo === "string" ? sourceRepo : null,
      sourceRunId: typeof sourceRunId === "string" ? sourceRunId : null,
      metadata: isRecord(metadata) ? metadata : null,
    },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
