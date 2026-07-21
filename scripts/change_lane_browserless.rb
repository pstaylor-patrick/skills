#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'change_lane'
require_relative 'change_findings'
require_relative 'change_figma'

# The browserless UX/responsive lane. Loads each route at each configured
# viewport in the shared browserless Chromium container and asserts the baseline
# responsive-health checks a manual multi-viewport pass would look for: the page
# navigated without an error status, and it does not overflow horizontally (a
# body wider than the viewport is the classic responsive break). A navigation
# error or horizontal overflow is a fail; page console errors are a warn.
#
# Two further capabilities layer on top of that baseline, both real (no stubs,
# no bypass logic):
#
# - Authenticated routes: `routes[]` entries can be a mapping with `auth: true`
#   plus a lane-level `auth:` block (login url, selectors, credentials read from
#   env vars). The single browserless /function call logs in once, in the same
#   page, before checking any auth-required route, so the same session cookies
#   carry into the rest of the matrix. A route needing auth is only ever checked
#   authenticated for real; if auth is not configured or the credentials are
#   missing, those routes are skipped with a named failing finding rather than
#   silently graded unauthenticated.
# - Figma visual alignment: a route entry's `figma:` block (file key + node id)
#   fetches a rendered reference PNG from the real Figma REST API
#   (ChangeFigma), then diffs it against browserless's own screenshot of that
#   route/viewport using a pure Canvas 2D pixel comparison run inside the same
#   Chromium page (no new dependency: the browserless image already has a real
#   browser canvas, so decode-and-diff happens there rather than in Ruby, which
#   has no image-decoding library in this repo's Gemfile).
#
# This is the deterministic, config-driven counterpart to the AMFM
# apps/e2e/src/smoke.ts / full.ts Playwright-over-CDP harness: same ephemeral
# browserless container, but a fixed responsive/auth/visual-alignment rubric
# across a viewport matrix rather than hand-authored flow assertions.
class ChangeLaneBrowserless < ChangeLane
  DEFAULT_VIEWPORTS = [
    { 'name' => 'mobile', 'width' => 390, 'height' => 844 },
    { 'name' => 'tablet', 'width' => 768, 'height' => 1024 },
    { 'name' => 'desktop', 'width' => 1440, 'height' => 900 }
  ].freeze

  DEFAULT_EMAIL_SELECTOR = 'input[name="email"]'
  DEFAULT_PASSWORD_SELECTOR = 'input[type="password"]'
  DEFAULT_SUBMIT_SELECTOR = 'button[type="submit"]'
  DEFAULT_TIMEOUT_MS = 15_000
  DEFAULT_MAX_DIFF_PERCENT = 10.0

  def run
    session = @context.browserless
    return [ unavailable ] unless session

    findings = []
    entries = route_entries
    auth = auth_config

    auth_ready, auth_finding = resolve_auth(entries, auth)
    findings << auth_finding if auth_finding

    usable = auth_ready ? entries : entries.reject { |e| e[:auth] }
    (entries - usable).each { |entry| findings << auth_skip_finding(entry) }

    figma_refs, figma_findings = resolve_figma_refs(usable)
    findings.concat(figma_findings)

    begin
      result = session.run_function(scan_module(usable, auth_ready ? auth : nil, figma_refs))
      Array(result).each do |check|
        findings << check_finding(check)
        findings << figma_diff_finding(check) if check['figmaDiff']
      end
    rescue StandardError => e
      findings << Finding.new(lane: 'browserless', check: 'viewport scan', status: 'fail', severity: 'high',
                               detail: "scan error: #{e.message}")
    end
    findings
  end

  private

  def viewports = (@config['viewports'] || DEFAULT_VIEWPORTS)

  # Route entries as a normalized array of { path:, auth:, figma: }. A plain
  # string route is `{ path: it, auth: false, figma: nil }`; a mapping route can
  # add `auth: true` and a `figma: { file_key:, node_id:, viewport: }` block.
  # Overrides the string-only ChangeLane#routes (still available via `routes`,
  # derived below) so the shared redirect-detection helper keeps working
  # unchanged for this lane.
  def route_entries
    list = Array(@config['routes']).map { |item| normalize_route(item) }.reject { |e| e[:path].empty? }
    return list unless list.empty?

    self.class::DEFAULT_ROUTES.map { |path| { path: path, auth: false, figma: nil } }
  end

  def routes = route_entries.map { |e| e[:path] }

  def normalize_route(item)
    if item.is_a?(Hash)
      { path: item['path'].to_s, auth: item['auth'] == true, figma: normalize_figma(item['figma']) }
    else
      { path: item.to_s, auth: false, figma: nil }
    end
  end

  def normalize_figma(figma)
    return nil unless figma.is_a?(Hash)

    file_key = figma['file_key'].to_s
    node_id = figma['node_id'].to_s
    return nil if file_key.empty? || node_id.empty?

    { file_key: file_key, node_id: node_id, viewport: figma['viewport']&.to_s }
  end

  # --- auth -----------------------------------------------------------------

  def auth_config
    raw = @config['auth']
    raw.is_a?(Hash) ? AuthConfig.new(raw) : nil
  end

  # Decides whether the auth-required routes can actually be checked
  # authenticated. Real credentials only: no test-mode bypass header, no fake
  # session. When auth is missing or incomplete, the caller skips just the
  # auth-required routes and this returns a named finding explaining why, per
  # the platform rule that a real blocker is reported, never silently absorbed.
  def resolve_auth(entries, auth)
    return [ true, nil ] unless entries.any? { |e| e[:auth] }
    return [ false, auth_blocker("route(s) are marked auth: true but lanes.browserless.auth is not configured") ] unless auth

    return [ false, auth_blocker('auth.login_url is not set') ] if auth.login_url.empty?
    return [ false, auth_blocker("auth.email_env (#{auth.email_env_name.inspect}) is unset or empty in this process's environment") ] if auth.email.empty?
    if auth.password.empty?
      return [ false, auth_blocker("auth.password_env (#{auth.password_env_name.inspect}) is unset or empty in this process's environment") ]
    end

    [ true, nil ]
  end

  def auth_blocker(detail)
    Finding.new(lane: 'browserless', check: 'auth login', target: base_url, status: 'fail', severity: 'high',
                detail: "cannot run authenticated checks: #{detail}")
  end

  def auth_skip_finding(entry)
    Finding.new(lane: 'browserless', check: 'auth-required route skipped', target: base_url,
                location: entry[:path], status: 'fail', severity: 'high',
                detail: 'skipped because the login flow could not run; see the "auth login" finding for the reason')
  end

  # --- figma ------------------------------------------------------------------

  def figma_token_env = (@config['figma'] || {}).fetch('token_env', 'FIGMA_ACCESS_TOKEN').to_s
  def figma_token = ENV[figma_token_env].to_s
  def figma_max_diff_percent = Float((@config['figma'] || {}).fetch('max_diff_percent', DEFAULT_MAX_DIFF_PERCENT))

  # Fetches every configured route's Figma reference PNG up front (base64,
  # keyed by route path) so the single browserless call can embed them as
  # literals and diff in-page. A fetch failure (no token, bad file/node id, API
  # error) is a named finding for that route; the route's ordinary responsive
  # checks still run, only the visual diff for it is skipped.
  def resolve_figma_refs(entries)
    refs = {}
    findings = []
    token = figma_token
    entries.each do |entry|
      next unless entry[:figma]

      if token.empty?
        findings << figma_blocker(entry[:path], "no Figma access token: set lanes.browserless.figma.token_env " \
                                                 "(default #{figma_token_env}) in the environment")
        next
      end

      begin
        refs[entry[:path]] = ChangeFigma.fetch_reference_png_base64(
          file_key: entry[:figma][:file_key], node_id: entry[:figma][:node_id], token: token
        )
      rescue ChangeFigma::FigmaError => e
        findings << figma_blocker(entry[:path], e.message)
      end
    end
    [ refs, findings ]
  end

  def figma_blocker(path, detail)
    Finding.new(lane: 'browserless', check: 'figma reference fetch', target: base_url, location: path,
                status: 'fail', severity: 'high', detail: detail)
  end

  # --- grading ----------------------------------------------------------------

  def check_finding(check)
    status, severity, detail = grade(check)
    Finding.new(lane: 'browserless', check: "#{check['viewport']} #{check['width']}x#{check['height']}",
                target: base_url, status: status, severity: severity,
                location: check['route'].to_s, detail: detail)
  end

  def grade(check)
    return [ 'fail', 'high', "auth login failed before this route could be reached: #{check['authError']}" ] if check['authBlocked']
    return [ 'fail', 'high', "navigation error: #{check['error']}" ] if check['error']
    return [ 'fail', 'high', "http #{check['httpStatus']}" ] if bad_status?(check['httpStatus'])

    served = redirected_path(check['route'], check['finalUrl'])
    if served
      return [ 'warn', 'low',
               "requested #{check['route']}, redirected to #{served}; the viewport checks reflect that page, not the requested route" ]
    end

    return [ 'fail', 'medium', "horizontal overflow: scrollWidth #{check['scrollWidth']} > #{check['width']}" ] if check['overflow']
    return [ 'warn', 'low', "#{check['consoleErrors']} console error(s)" ] if check['consoleErrors'].to_i.positive?

    [ 'pass', 'info', 'no responsive break' ]
  end

  # Grades the pixel-diff percentage against the configured (or default)
  # threshold. Below the threshold but nonzero is a warn, not a pass: the
  # number is the "iterate until aligned" signal the report should keep
  # surfacing even once it is small enough not to gate, so a rerun after each
  # fix visibly shows it moving toward zero.
  def figma_diff_finding(check)
    diff = check['figmaDiff']
    percent = diff['diffPercent'].to_f
    threshold = figma_max_diff_percent
    status, severity =
      if percent > threshold
        [ 'fail', 'high' ]
      elsif percent.positive?
        [ 'warn', 'low' ]
      else
        [ 'pass', 'info' ]
      end
    detail = format('%.2f%% pixel difference vs the Figma reference (fail above %.1f%%); compared %dx%d ' \
                     '(screenshot %dx%d, reference %dx%d)',
                     percent, threshold, diff['comparedWidth'].to_i, diff['comparedHeight'].to_i,
                     diff['shotWidth'].to_i, diff['shotHeight'].to_i, diff['refWidth'].to_i, diff['refHeight'].to_i)
    Finding.new(lane: 'browserless', check: "#{check['viewport']} figma diff", target: base_url,
                location: check['route'].to_s, status: status, severity: severity, detail: detail)
  end

  def bad_status?(status) = status && status.to_i >= 400

  def unavailable
    Finding.new(lane: 'browserless', check: 'browserless', status: 'fail', severity: 'high',
                detail: 'browserless session unavailable; cannot run viewport checks')
  end

  def resolve_login_url(login_url)
    return login_url if login_url =~ %r{\Ahttps?://}

    "#{base_url}#{login_url.start_with?('/') ? login_url : "/#{login_url}"}"
  end

  # --- the browserless module --------------------------------------------------

  # One module walks the viewport-by-route matrix in a single page, so an
  # authenticated login (when configured) happens once and its cookies carry
  # into every later navigation on the same page. For each cell it sets the
  # viewport, navigates, records the response status, counts page console
  # errors, measures horizontal overflow, and (when a Figma reference was
  # fetched for that route/viewport) screenshots and pixel-diffs against it,
  # returning one flat entry per cell.
  def scan_module(entries, auth, figma_refs)
    <<~JS
      export default async function ({ page }) {
        const baseUrl = #{JSON.generate(base_url)};
        const routeEntries = #{JSON.generate(js_route_entries(entries, figma_refs))};
        const viewports = #{JSON.generate(viewports)};
        const auth = #{JSON.generate(js_auth(auth))};
        const figmaRefs = #{JSON.generate(figma_refs)};

        let authOk = null;
        let authError = null;

        async function ensureAuth() {
          if (!auth || authOk !== null) return authOk;
          try {
            await page.goto(auth.loginUrl, { waitUntil: "networkidle2", timeout: auth.timeoutMs });
            await page.waitForSelector(auth.emailSelector, { timeout: auth.timeoutMs });
            await page.type(auth.emailSelector, auth.email);
            await page.type(auth.passwordSelector, auth.password);
            await Promise.all([
              page.waitForNavigation({ waitUntil: "networkidle2", timeout: auth.timeoutMs }).catch(() => null),
              page.click(auth.submitSelector),
            ]);
            if (auth.waitForSelector) await page.waitForSelector(auth.waitForSelector, { timeout: auth.timeoutMs });
            authOk = true;
          } catch (err) {
            authOk = false;
            authError = String(err);
          }
          return authOk;
        }

        async function diffAgainstReference(shotBase64, refBase64) {
          return page.evaluate(async (a, b) => {
            function loadImage(base64) {
              return new Promise((resolve, reject) => {
                const img = new Image();
                img.onload = () => resolve(img);
                img.onerror = reject;
                img.src = "data:image/png;base64," + base64;
              });
            }
            function toImageData(img) {
              const canvas = document.createElement("canvas");
              canvas.width = img.width;
              canvas.height = img.height;
              const ctx = canvas.getContext("2d");
              ctx.drawImage(img, 0, 0);
              return { imageData: ctx.getImageData(0, 0, canvas.width, canvas.height), width: canvas.width, height: canvas.height };
            }
            const shotImg = await loadImage(a);
            const refImg = await loadImage(b);
            const shot = toImageData(shotImg);
            const ref = toImageData(refImg);
            const width = Math.min(shot.width, ref.width);
            const height = Math.min(shot.height, ref.height);
            const threshold = 32;
            let diffCount = 0;
            for (let y = 0; y < height; y++) {
              for (let x = 0; x < width; x++) {
                const si = (y * shot.width + x) * 4;
                const ri = (y * ref.width + x) * 4;
                const dr = shot.imageData.data[si] - ref.imageData.data[ri];
                const dg = shot.imageData.data[si + 1] - ref.imageData.data[ri + 1];
                const db = shot.imageData.data[si + 2] - ref.imageData.data[ri + 2];
                if (Math.sqrt(dr * dr + dg * dg + db * db) > threshold) diffCount += 1;
              }
            }
            const totalPixels = width * height;
            return {
              diffPercent: totalPixels ? (diffCount / totalPixels) * 100 : 100,
              comparedWidth: width,
              comparedHeight: height,
              shotWidth: shot.width,
              shotHeight: shot.height,
              refWidth: ref.width,
              refHeight: ref.height,
            };
          }, shotBase64, refBase64);
        }

        const out = [];
        for (const vp of viewports) {
          for (const entry of routeEntries) {
            const cell = { viewport: vp.name, width: vp.width, height: vp.height, route: entry.path };
            if (entry.auth) {
              const ok = await ensureAuth();
              if (!ok) {
                cell.authBlocked = true;
                cell.authError = authError;
                out.push(cell);
                continue;
              }
            }
            let consoleErrors = 0;
            const onError = (msg) => { if (msg.type() === "error") consoleErrors += 1; };
            page.on("console", onError);
            try {
              await page.setViewport({ width: vp.width, height: vp.height });
              const resp = await page.goto(baseUrl + entry.path, { waitUntil: "networkidle2", timeout: 30000 });
              cell.httpStatus = resp ? resp.status() : null;
              cell.finalUrl = page.url();
              const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
              cell.scrollWidth = scrollWidth;
              cell.overflow = scrollWidth > vp.width + 1;
              cell.consoleErrors = consoleErrors;

              const refBase64 = entry.figmaViewport === vp.name ? figmaRefs[entry.path] : null;
              if (refBase64) {
                const shotBase64 = await page.screenshot({ encoding: "base64" });
                cell.figmaDiff = await diffAgainstReference(shotBase64, refBase64);
              }
            } catch (err) {
              cell.error = String(err);
            } finally {
              page.off("console", onError);
            }
            out.push(cell);
          }
        }
        return { data: out, type: "application/json" };
      }
    JS
  end

  def js_route_entries(entries, figma_refs)
    entries.map do |e|
      figma_viewport = e[:figma] && figma_refs.key?(e[:path]) ? (e[:figma][:viewport] || viewports.first['name']) : nil
      { path: e[:path], auth: e[:auth], figmaViewport: figma_viewport }
    end
  end

  def js_auth(auth)
    return nil unless auth

    {
      loginUrl: resolve_login_url(auth.login_url),
      email: auth.email,
      password: auth.password,
      emailSelector: auth.email_selector,
      passwordSelector: auth.password_selector,
      submitSelector: auth.submit_selector,
      waitForSelector: auth.wait_for_selector,
      timeoutMs: auth.timeout_ms
    }
  end

  # Typed view over the lane's `auth:` block. Credentials are always read from
  # the environment by the variable name the config names (`email_env`,
  # `password_env`), never written into CHANGE.md itself, matching how this
  # platform never accepts a raw secret literal in the config it checks in.
  class AuthConfig
    def initialize(raw) = @raw = raw

    def login_url = @raw['login_url'].to_s
    def email_env_name = @raw['email_env'].to_s
    def password_env_name = @raw['password_env'].to_s
    def email = ENV[email_env_name].to_s
    def password = ENV[password_env_name].to_s
    def email_selector = (@raw['email_selector'] || DEFAULT_EMAIL_SELECTOR).to_s
    def password_selector = (@raw['password_selector'] || DEFAULT_PASSWORD_SELECTOR).to_s
    def submit_selector = (@raw['submit_selector'] || DEFAULT_SUBMIT_SELECTOR).to_s
    def wait_for_selector = @raw['wait_for_selector']&.to_s
    def timeout_ms = Integer(@raw['timeout_ms'] || DEFAULT_TIMEOUT_MS)
  end
end
