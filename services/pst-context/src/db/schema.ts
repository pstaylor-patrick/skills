import {
  pgTable,
  uuid,
  text,
  timestamp,
  jsonb,
  index,
} from "drizzle-orm/pg-core";

export const skillRuns = pgTable(
  "skill_runs",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    skill: text("skill").notNull(),
    repo: text("repo"),
    branch: text("branch"),
    prNumber: text("pr_number"),
    outcome: text("outcome"),
    metadata: jsonb("metadata").$type<Record<string, unknown>>(),
    startedAt: timestamp("started_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
    finishedAt: timestamp("finished_at", { withTimezone: true }),
  },
  (table) => [
    index("skill_runs_skill_idx").on(table.skill),
    index("skill_runs_repo_idx").on(table.repo),
  ],
);

export const artifacts = pgTable(
  "artifacts",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    runId: uuid("run_id").references(() => skillRuns.id, {
      onDelete: "cascade",
    }),
    localPath: text("local_path").notNull(),
    artifactType: text("artifact_type").notNull(),
    description: text("description"),
    metadata: jsonb("metadata").$type<Record<string, unknown>>(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("artifacts_run_id_idx").on(table.runId),
    index("artifacts_type_idx").on(table.artifactType),
  ],
);

export const learnings = pgTable(
  "learnings",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    topic: text("topic").notNull(),
    content: text("content").notNull(),
    sourceRepo: text("source_repo"),
    sourceRunId: uuid("source_run_id").references(() => skillRuns.id, {
      onDelete: "set null",
    }),
    metadata: jsonb("metadata").$type<Record<string, unknown>>(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("learnings_topic_idx").on(table.topic),
    index("learnings_source_repo_idx").on(table.sourceRepo),
  ],
);
