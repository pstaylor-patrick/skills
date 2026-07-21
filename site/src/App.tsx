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
  { name: "k6", role: "load", detail: "Grades every threshold under load.", url: "https://github.com/grafana/k6" },
  { name: "axe-core", role: "accessibility", detail: "Fails on violations above an impact threshold.", url: "https://github.com/dequelabs/axe-core" },
  { name: "OWASP ZAP", role: "security", detail: "Passive baseline: headers, cookies, known CVEs.", url: "https://github.com/zaproxy/zaproxy" },
  { name: "browserless", role: "responsive UX", detail: "Every route at every viewport.", url: "https://github.com/browserless/browserless" },
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
          <span>GitHub</span>
        </a>
      </header>

      <main>
        <section className="hero">
          <h1>A dockerized local release-quality gate.</h1>
          <p>
            Four audit lanes run against a locally booted app, in ephemeral digest-pinned
            containers, gating a release before it merges.
          </p>
        </section>

        <section className="lanes" aria-label="Audit lanes">
          {LANES.map((lane) => (
            <a
              className="lane"
              key={lane.name}
              href={lane.url}
              target="_blank"
              rel="noopener noreferrer"
            >
              <span className="lane-role">{lane.role}</span>
              <span className="lane-name">
                {lane.name}
                <span className="lane-arrow" aria-hidden="true">
                  &#8599;
                </span>
              </span>
              <span className="lane-detail">{lane.detail}</span>
            </a>
          ))}
        </section>

        <section className="contract">
          <h2>One file per repo</h2>
          <p className="section-lede">
            The root <code>CHANGE.md</code> declares how a repo is audited and governed. Its
            frontmatter carries two blocks.
          </p>
          <div className="contract-grid">
            <div className="contract-card">
              <h3>
                <code>change_config</code>
              </h3>
              <p>Boot, health, routes, thresholds, viewports. What the lanes read.</p>
            </div>
            <div className="contract-card">
              <h3>
                <code>change_policy</code>
              </h3>
              <p>Protected branches, promotion rules, admin-bypass. What the merge gate enforces.</p>
            </div>
          </div>
          <p className="lineage">
            Same lineage as <code>AGENTS.md</code>, <code>CLAUDE.md</code>, and{" "}
            <code>design.md</code>: one root file a newcomer reads to work correctly here.
          </p>
        </section>

        <section className="spec">
          <details className="spec-details">
            <summary>
              <span>CHANGE.md frontmatter specification</span>
              <span className="version-badge">v{version}</span>
            </summary>
            <div
              className="spec-body"
              dangerouslySetInnerHTML={{ __html: specHtml(specMarkdown) }}
            />
          </details>
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
