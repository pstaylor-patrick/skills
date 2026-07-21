import { marked } from "marked";
import specMarkdown from "./generated/spec.md?raw";

const REPO_URL = "https://github.com/pstaylor-patrick/change-fabric";

// Phosphor Icons github-logo (regular), MIT licensed. Inlined so the page stays
// self-contained with no external asset requests.
function GithubLogo() {
  return (
    <svg viewBox="0 0 256 256" width="20" height="20" fill="currentColor" aria-hidden="true">
      <path d="M208.31,75.68A59.78,59.78,0,0,0,202.93,28,8,8,0,0,0,196,24a59.75,59.75,0,0,0-48,24H124A59.75,59.75,0,0,0,76,24a8,8,0,0,0-6.93,4,59.78,59.78,0,0,0-5.38,47.68A58.14,58.14,0,0,0,56,104v8a56.06,56.06,0,0,0,48.44,55.47A39.8,39.8,0,0,0,96,192v8H72a24,24,0,0,1-24-24A40,40,0,0,0,8,136a8,8,0,0,0,0,16,24,24,0,0,1,24,24,40,40,0,0,0,40,40H96v16a8,8,0,0,0,16,0V192a24,24,0,0,1,48,0v40a8,8,0,0,0,16,0V192a39.8,39.8,0,0,0-8.44-24.53A56.06,56.06,0,0,0,216,112v-8A58.14,58.14,0,0,0,208.31,75.68Z" />
    </svg>
  );
}

const LANES = [
  { name: "k6", role: "load and burst", detail: "Grafana k6 drives the target and grades each threshold, with a scenario-driven load narrative for the go/no-go reader." },
  { name: "axe-core", role: "accessibility", detail: "axe-core runs against each route in an ephemeral browser and fails on violations at or above an impact threshold." },
  { name: "OWASP ZAP", role: "security", detail: "A passive ZAP baseline spiders each in-scope target for missing headers, cookie flags, and known-vulnerable libraries." },
  { name: "browserless", role: "responsive UX", detail: "Each route loads at every configured viewport to catch horizontal overflow, bad status, and console errors." },
];

function schemaVersion(markdown: string): string {
  const match = markdown.match(/^Schema version:\s*(\S+)/m);
  return match ? match[1] : "unknown";
}

// The spec is our own trusted, build-time-embedded content, so rendering its
// markdown to HTML directly is safe.
function specHtml(markdown: string): string {
  return marked.parse(markdown, { async: false });
}

export function App() {
  const version = schemaVersion(specMarkdown);

  return (
    <div className="page">
      <header className="site-header">
        <span className="wordmark">change fabric</span>
        <a className="repo-link" href={REPO_URL} target="_blank" rel="noopener noreferrer">
          <GithubLogo />
          <span>pstaylor-patrick/change-fabric</span>
        </a>
      </header>

      <main>
        <section className="hero">
          <h1>A dockerized local release-quality gate.</h1>
          <p>
            change fabric runs four automated audit lanes against a locally booted app, in
            ephemeral digest-pinned containers, and gates a release-affecting merge on the
            result. One file per repo, the root <code>CHANGE.md</code>, tells it how to boot
            the app, what to audit, and how the repo is governed.
          </p>
        </section>

        <section className="lanes" aria-label="Audit lanes">
          {LANES.map((lane) => (
            <article className="lane" key={lane.name}>
              <h2>{lane.name}</h2>
              <p className="lane-role">{lane.role}</p>
              <p>{lane.detail}</p>
            </article>
          ))}
        </section>

        <section className="contract">
          <h2>The CHANGE.md contract</h2>
          <p>
            <code>CHANGE.md</code> is a repo's answer to "how do changes get made here." It sits
            in the same lineage as the root-level convention files a tool or a newcomer reads to
            operate correctly in a specific repo: <code>AGENTS.md</code> for how a coding agent
            works, <code>CLAUDE.md</code> for what Claude needs to know, <code>design.md</code>{" "}
            for how a project is designed.
          </p>
          <p>
            Its frontmatter carries two blocks. <code>change_config</code> is the mechanical
            target-app config the audit lanes read (boot, health, routes, thresholds, viewports).
            <code>change_policy</code> is the machine-checkable governance the merge gate enforces
            (protected branches, promotion rules, admin-bypass policy). The prose body below is
            the human governance FAQ.
          </p>
        </section>

        <section className="spec">
          <div className="spec-heading">
            <h2>CHANGE.md frontmatter specification</h2>
            <span className="version-badge">v{version}</span>
          </div>
          <div className="spec-body" dangerouslySetInnerHTML={{ __html: specHtml(specMarkdown) }} />
        </section>
      </main>

      <footer className="site-footer">
        <a href={REPO_URL} target="_blank" rel="noopener noreferrer">
          <GithubLogo />
          <span>pstaylor-patrick/change-fabric</span>
        </a>
      </footer>
    </div>
  );
}
